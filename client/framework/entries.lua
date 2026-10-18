-- Ports of vMenu.Enhanced.MenuFramework's entry types (MenuEntry.cs and the
-- *Entry.cs files). An entry declares its item instead of holding a made one,
-- which is what lets the framework rewrite text on a language change and the
-- description on a permission change.
--
-- Every entry takes a table of options. Shared ones:
--   text, description, label        menu text (see shared/localization.lua)
--   gate                            permission string or framework/gate.lua gate
--   locked_description              text shown while the gate locks the row
--   read_locked_description         function, read on every refresh instead
--   behaviour, read_behaviour       'lock' or 'hide' when the gate denies
--   left_icon, right_icon           MenuAPI icon names; read_* variants are functions
--   read_enabled                    function; greys the row without gating it
--   vehicle_stats, vehicle_upgrade_stats, weapon_stats, weapon_component_stats
--                                   functions returning { a, b, c, d } or nil
--   configure(item)                 runs once after the item is created
--   on_highlighted(item)
-- Handlers named *_async run in their own thread, so they may Wait; with
-- single_flight (the default) a second press while one runs is ignored.

local Gate = require('client.framework.gate')
local Localization = require('shared.localization')
local Items = require('menu.items')

local Entries = {}

local resolve = Localization.resolve

local CONFIRM_DESCRIPTION = Localization.key('framework.confirm')
local RESTRICTED_DESCRIPTION = 'framework.restricted'

local Entry = {}
Entry.__index = Entry

local function is_empty(text)
    return text == nil or text == ''
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

-- MenuAPI shows "N/A" for an empty list, so 0 stays valid.
local function clamp_list_index(index, count)
    return clamp(index or 0, 0, math.max(0, count - 1))
end

local function resolve_options(options)
    local resolved = {}
    for index, option in ipairs(options) do
        resolved[index] = resolve(option)
    end
    return resolved
end

local function new(kind, options, required)
    for _, field in ipairs(required) do
        if options[field] == nil then
            error(('%s entry needs %s'):format(kind, field), 3)
        end
    end
    options.kind = kind
    options.is_allowed = true
    options.gate = Gate.normalize(options.gate)
    return setmetatable(options, Entry)
end

function Entries.button(options)
    options = new('button', options, { 'text' })
    if options.single_flight == nil then
        options.single_flight = true
    end
    return options
end

function Entries.checkbox(options)
    return new('checkbox', options, { 'text' })
end

function Entries.list(options)
    return new('list', options, { 'text', 'options' })
end

function Entries.slider(options)
    return new('slider', options, { 'text', 'min', 'max' })
end

function Entries.dynamic_list(options)
    return new('dynamic_list', options, { 'text', 'read_value', 'change' })
end

-- definition: a menu definition (see framework/registry.lua), or build(builder)
-- for a menu declared inline. menu_title defaults to text.
function Entries.submenu(options)
    return new('submenu', options, { 'text' })
end

-- The row that opens definition from its parent.
function Entries.submenu_for(definition)
    return Entries.submenu({
        text = definition.link_text or definition.title,
        description = definition.link_description,
        label = definition.link_label,
        behaviour = definition.link_behaviour,
        definition = definition,
    })
end

function Entries.separator(options)
    options = new('separator', options, { 'text' })
    if options.show_arrows == nil then
        options.show_arrows = true
    end
    return options
end

-- Asks once, then acts on the second press.
function Entries.confirm_button(options)
    options = new('confirm_button', options, { 'text' })
    options.confirmation_description = options.confirmation_description or CONFIRM_DESCRIPTION
    if options.single_flight == nil then
        options.single_flight = true
    end
    return options
end

function Entries.confirm_list(options)
    options = new('confirm_list', options, { 'text', 'options' })
    options.confirmation_description = options.confirmation_description or CONFIRM_DESCRIPTION
    if options.single_flight == nil then
        options.single_flight = true
    end
    return options
end

-- An item made by hand. Its text never changes, so it does not translate;
-- registering it still keeps a locked raw list or slider from changing.
function Entries.raw(item)
    local entry = new('raw', { text = '', raw_item = item }, {})
    entry.raw_description = item.Description
    entry.raw_left_icon = item.LeftIcon
    return entry
end

function Entries.is_confirm(entry)
    return entry.kind == 'confirm_button' or entry.kind == 'confirm_list'
end

-- A submenu keeps its definition's gate too, so declaring the definition does
-- not silently drop that menu's permission.
function Entry:effective_gate()
    if self.kind == 'submenu' and self.definition and self.definition.gate then
        if not self.combined_gate then
            self.combined_gate = Gate.all(self.gate, self.definition.gate)
        end
        return self.combined_gate
    end
    return self.gate
end

function Entry:title_of_menu()
    return is_empty(self.menu_title) and self.text or self.menu_title
end

local creators = {
    button = function(self)
        return Items.MenuItem.new(resolve(self.text), resolve(self.description))
    end,
    submenu = function(self)
        return Items.MenuItem.new(resolve(self.text), resolve(self.description))
    end,
    confirm_button = function(self)
        return Items.MenuItem.new(resolve(self.text), resolve(self.description))
    end,
    checkbox = function(self)
        local checked = self.checked == true
        if self.read_state then
            checked = self.read_state()
        end
        local item = Items.MenuCheckboxItem.new(resolve(self.text), resolve(self.description), checked)
        item.Style = self.style or 'Tick'
        return item
    end,
    list = function(self)
        local values = resolve_options(self.options)
        local index = self.read_selected_index and self.read_selected_index() or self.selected_index
        return Items.MenuListItem.new(
            resolve(self.text),
            values,
            clamp_list_index(index, #values),
            resolve(self.description)
        )
    end,
    slider = function(self)
        local position = self.read_position and self.read_position() or self.position or self.min
        local item = Items.MenuSliderItem.new(
            resolve(self.text),
            self.min,
            self.max,
            clamp(position, self.min, self.max),
            resolve(self.description),
            self.show_divider
        )
        item.SliderLeftIcon = self.slider_left_icon or 'NONE'
        item.SliderRightIcon = self.slider_right_icon or 'NONE'
        return item
    end,
    dynamic_list = function(self)
        return Items.MenuDynamicListItem.new(resolve(self.text), self.read_value(), function(item, left)
            -- Every row the framework builds seeds CurrentItem from read_value,
            -- so nil only happens to a row something else re-seeded.
            local current = item.CurrentItem or ''
            if not item.Enabled then
                return current
            end
            return self.change({ item = item, current_value = current, left = left })
        end, resolve(self.description))
    end,
    separator = function(self)
        return Items.SeparatorMenuItem.new(resolve(self.text), resolve(self.description), self.show_arrows)
    end,
    raw = function(self)
        return self.raw_item
    end,
}
creators.confirm_list = creators.list

function Entry:materialise()
    local item = creators[self.kind](self)
    self.item = item
    if self.configure then
        self.configure(item)
    end
    return item
end

function Entry:raise_highlighted()
    if self.on_highlighted and self.item then
        self.on_highlighted(self.item)
    end
end

-- Confirmation -------------------------------------------------------------------------

local function paint_confirmation(self)
    if self.item then
        self.item.Description = resolve(self.armed and self.confirmation_description or self.description)
    end
end

function Entry:reset_confirmation()
    if not self.armed then
        return
    end
    self.armed = false
    paint_confirmation(self)
end

-- True on the confirming press; arms the row on the first.
function Entry:press_confirm()
    if self.armed then
        self:reset_confirmation()
        return true
    end
    self.armed = true
    paint_confirmation(self)
    return false
end

-- Presentation -------------------------------------------------------------------------

-- Derived from the declaration every time instead of snapshotting and
-- restoring, so repeated lock and unlock cycles end in the same place and a
-- locked row stays translated.
local function apply_base(self, behaviour)
    local item = self.item
    local locked = not self.is_allowed and behaviour == 'lock'
    item.Text = resolve(self.text)
    item.Enabled = self.is_allowed and (self.read_enabled == nil or self.read_enabled() == true)
    if locked then
        item.LeftIcon = 'LOCK'
    else
        item.LeftIcon = self.read_left_icon and self.read_left_icon() or self.left_icon or 'NONE'
    end
    item.RightIcon = self.read_right_icon and self.read_right_icon() or self.right_icon or 'NONE'
    if locked then
        local reason = self.read_locked_description and self.read_locked_description()
        if is_empty(reason) then
            reason = self.locked_description
        end
        item.Description = is_empty(reason) and Localization.get(RESTRICTED_DESCRIPTION) or resolve(reason)
    else
        item.Description = resolve(self.description)
    end
    local label = self.label
    if is_empty(label) and self.kind == 'submenu' then
        label = '→'
    end
    if not is_empty(label) then
        item.Label = resolve(label)
    end
end

-- Rewrites the values in place, so the selection survives a language change.
local function rewrite_list(self)
    local item = self.item
    local values = resolve_options(self.options)
    item.ListItems = values
    local index = self.read_selected_index and self.read_selected_index() or item.ListIndex
    item.ListIndex = clamp_list_index(index, #values)
end

function Entry:apply_presentation(behaviour)
    local item = self.item
    if not item then
        return
    end
    local kind = self.kind
    if kind == 'separator' then
        item.Text = resolve(self.text)
        item.Description = resolve(self.description)
        return
    end
    if kind == 'raw' then
        local locked = not self.is_allowed and behaviour == 'lock'
        item.Enabled = self.is_allowed
        item.LeftIcon = locked and 'LOCK' or self.raw_left_icon
        item.Description = locked and Localization.get(RESTRICTED_DESCRIPTION) or self.raw_description
        return
    end
    -- A row that just lost its permission must not keep warning about
    -- something it will no longer do.
    if Entries.is_confirm(self) and not self.is_allowed then
        self.armed = false
    end

    apply_base(self, behaviour)

    if kind == 'checkbox' and self.read_state then
        item.Checked = self.read_state()
    elseif kind == 'list' or kind == 'confirm_list' then
        rewrite_list(self)
    elseif kind == 'slider' and self.read_position then
        item.Position = clamp(self.read_position(), item.Min, item.Max)
    elseif kind == 'dynamic_list' then
        item.CurrentItem = self.read_value()
    end
    -- After the base pass, so a locked row still says it is restricted and a
    -- language change reaches the warning too.
    if Entries.is_confirm(self) and self.armed then
        item.Description = resolve(self.confirmation_description)
    end
end

return Entries
