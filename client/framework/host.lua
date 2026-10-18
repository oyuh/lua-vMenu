-- Ports of vMenu.Enhanced.MenuFramework/MenuHost.cs and MenuBuilder.cs. A host
-- owns one MenuAPI menu: it subscribes to the menu's events once and routes
-- them to the entry behind each item, gates and relabels the entries, and
-- hides the ones a 'hide' gate denies through the menu's filter. A menu
-- definition's build(builder) receives the host itself as its builder.

local Log = require('shared.log')
local Localization = require('shared.localization')
local Gate = require('client.framework.gate')
local Entries = require('client.framework.entries')
local Items = require('menu.items')

local Host = {}
Host.__index = Host

-- The default for a denied gate: a player who can see why something is
-- unavailable asks a better question than one looking at a menu that seems broken.
Host.default_gate_behaviour = 'lock'

local resolve = Localization.resolve

local function registry()
    -- Required lazily: the registry requires this module.
    return require('client.framework.registry')
end

-- Handlers run guarded: one throwing must not stop the rest of an event.
local function guard(item, handler, ...)
    if not handler then
        return
    end
    local ok, err = pcall(handler, ...)
    if not ok then
        Log.error(("[Menu] '%s' handler threw: %s"):format(item and item.Text or '<menu>', tostring(err)))
    end
end

local function guard_all(item, handlers, ...)
    for _, handler in ipairs(handlers) do
        guard(item, handler, ...)
    end
end

local function index_of(list, value)
    for index, entry in ipairs(list) do
        if entry == value then
            return index
        end
    end
    return nil
end

-- MenuAPI draws the bar under the banner whether or not it has text, but only
-- moves the rows down when it does, so an empty subtitle falls back to the title.
function Host.resolve_subtitle(title, subtitle)
    local resolved = resolve(subtitle)
    return resolved ~= '' and resolved or resolve(title)
end

function Host.new(menu, parent, gate, title, subtitle, default_behaviour, audit_name)
    local self = setmetatable({
        menu = menu,
        parent = parent,
        gate = Gate.normalize(gate),
        title = title,
        subtitle = subtitle,
        audit_name = audit_name,
        children = {},
        entries = {},
        keys = {},
        registered = {},
        default_gate_behaviour = default_behaviour,
        opened_handlers = {},
        opened_async_handlers = {},
        closed_handlers = {},
        index_changed_handlers = {},
        by_item = {},
        hidden = {},
        in_flight = {},
        new_children = {},
        update_depth = 0,
        attached = false,
        notice_shown = false,
    }, Host)
    -- Every framework menu is made here, so this reaches menus built after
    -- the skin was applied.
    menu.HeaderImage = require('client.framework.skin').banner()
    return self
end

function Host:is_reachable()
    local host = self
    while host do
        if not Gate.evaluate(host.gate) then
            return false
        end
        host = host.parent
    end
    return true
end

-- Gating happens later: the filter needs the complete item list.
function Host:materialise(entry, position)
    local item = entry:materialise()
    if position == nil then
        self.menu:AddMenuItem(item)
    else
        self.menu:InsertMenuItem(position, item)
    end
    self.by_item[item] = entry
    return item
end

function Host:is_live()
    return self.attached
end

-- Builder API --------------------------------------------------------------------------

function Host:on_opened(handler)
    self.opened_handlers[#self.opened_handlers + 1] = handler
end

-- Runs in its own thread, so it may Wait; a second open while it runs skips it.
function Host:on_opened_async(handler)
    self.opened_async_handlers[#self.opened_async_handlers + 1] = handler
end

function Host:on_closed(handler)
    self.closed_handlers[#self.closed_handlers + 1] = handler
end

function Host:on_index_changed(handler)
    self.index_changed_handlers[#self.index_changed_handlers + 1] = handler
end

-- key: { name, description, default_key, default_button, press_type, handler,
-- text, shadowed_control, gate }. Registered with MenuAPI on the next refresh.
function Host:add_key(key)
    key.press_type = key.press_type or 'JUST_PRESSED'
    key.gate = Gate.normalize(key.gate)
    self.keys[#self.keys + 1] = key
    return key
end

-- Holds back the refresh and filter pass of insert, remove and move until fn
-- returns, so many changes cost one pass. Nesting is fine.
function Host:update(fn)
    self.update_depth = self.update_depth + 1
    local ok, err = pcall(fn)
    self.update_depth = self.update_depth - 1
    self:settle()
    if not ok then
        error(err, 0)
    end
end

local function settle(self)
    if self.update_depth > 0 then
        return
    end
    if not self.attached then
        self.needs_refresh = false
        self.needs_filter = false
        self.new_children = {}
        return
    end
    if self.needs_refresh then
        self.needs_refresh = false
        self:refresh_with(true)
        for _, child in ipairs(self.new_children) do
            registry().refresh_branch(child)
        end
        self.new_children = {}
    end
    if self.needs_filter or self.filter_dirty then
        self.needs_filter = false
        self:apply_filter()
    end
end

Host.settle = settle

-- Safe after the menu was built: the entry is materialised and gated at once,
-- and the highlighted row stays highlighted.
function Host:insert(index, entry)
    index = math.max(0, math.min(index, #self.entries))
    table.insert(self.entries, index + 1, entry)
    if not self.attached then
        return entry
    end
    local child = registry().materialise_late(self, entry, index)
    if child then
        self.new_children[#self.new_children + 1] = child
    end
    self.needs_refresh = true
    self.needs_filter = true
    settle(self)
    return entry
end

function Host:add(entry)
    return self:insert(#self.entries, entry)
end

-- One refresh at the end instead of one per entry.
function Host:insert_range(index, entries)
    local batch = table.move(entries, 1, #entries, 1, {})
    index = math.max(0, math.min(index, #self.entries))
    self:update(function()
        for _, entry in ipairs(batch) do
            self:insert(index, entry)
            index = index + 1
        end
    end)
end

function Host:add_range(entries)
    self:insert_range(#self.entries, entries)
end

-- A submenu entry takes its child menu with it. False when not in this menu.
function Host:remove(entry)
    local index = index_of(self.entries, entry)
    if not index then
        return false
    end
    table.remove(self.entries, index)
    if entry.kind == 'submenu' and entry.child then
        local at = index_of(self.new_children, entry.child)
        if at then
            table.remove(self.new_children, at)
        end
        registry().untrack(entry.child)
    end
    if entry.item then
        self.menu:RemoveMenuItem(entry.item)
        self.by_item[entry.item] = nil
        self.hidden[entry.item] = nil
    end
    self.in_flight[entry] = nil
    if self.awaiting_confirmation == entry then
        self.awaiting_confirmation = nil
    end
    if self.attached then
        self.needs_filter = true
        settle(self)
    end
    return true
end

-- A submenu entry keeps its child menu. False when not in this menu.
function Host:move(entry, index)
    local from = index_of(self.entries, entry)
    if not from then
        return false
    end
    table.remove(self.entries, from)
    index = math.max(0, math.min(index, #self.entries))
    table.insert(self.entries, index + 1, entry)
    if self.attached and entry.item then
        self.menu:MoveMenuItem(entry.item, index)
        self.needs_filter = true
        settle(self)
    end
    return true
end

-- Moves the cursor to an entry, raising the same events as the player moving
-- there. False when the entry is not shown.
function Host:select(entry)
    local item = entry.item
    if not item then
        return false
    end
    local index = index_of(self.menu:GetMenuItems(), item)
    if not index then
        return false
    end
    index = index - 1
    local old_index = self.menu.CurrentIndex
    local old = self.menu:GetCurrentMenuItem()
    if old == item then
        return true
    end
    local max = self.menu.MaxItemsOnScreen
    local offset = math.min(self.menu.ViewIndexOffset, math.max(self.menu:Size() - max, 0))
    self.menu:RefreshIndex(index, math.max(math.max(index - max + 1, 0), math.min(offset, index)))
    self:handle_index_change(self.menu, old or item, item, old_index, index)
    return true
end

function Host:invalidate()
    self.needs_refresh = true
    settle(self)
end

function Host:invalidate_filter()
    self.needs_filter = true
    settle(self)
end

-- Everything that remembers an item is emptied together, or a later refresh
-- would gate rows the menu no longer has.
function Host:clear_entries()
    for _, entry in ipairs(self.entries) do
        if entry.kind == 'submenu' and entry.child then
            registry().untrack(entry.child)
        end
    end
    self.menu:ClearMenuItems()
    self.entries = {}
    self.by_item = {}
    self.hidden = {}
    self.in_flight = {}
    self.awaiting_confirmation = nil
    self.filter_dirty = false
    self.new_children = {}
    self.needs_refresh = false
    self.needs_filter = false
    -- ClearMenuItems took the notice with everything else.
    self.notice_shown = false
end

-- For one detail menu shared by a long list of rows, where a submenu entry
-- would build one child menu per row. Title and subtitle re-resolve on every
-- refresh, so Localization.from can follow the selection.
function Host:add_detached_menu(title, subtitle, build, gate)
    return registry().create_detached(self, title, subtitle, gate or Gate.ALWAYS, build, self.default_gate_behaviour)
end

function Host:add_raw(item)
    return self:add(Entries.raw(item))
end

-- MenuAPI's sort drops the filter, so it is put back afterwards.
function Host:sort_items(compare)
    self:show_notice(false)
    self.menu:SortMenuItems(compare)
    self:apply_filter()
end

-- An extra visibility predicate, combined with gate hiding. nil clears it.
function Host:set_user_filter(predicate)
    self.user_filter = predicate
    if self.attached then
        self:apply_filter()
    else
        self.needs_filter = true
    end
end

function Host:refresh_filter()
    self:apply_filter()
end

-- Refreshing ---------------------------------------------------------------------------

function Host:refresh_header()
    self.menu.MenuTitle = resolve(self.title)
    self.menu.MenuSubtitle = Host.resolve_subtitle(self.title, self.subtitle)
end

local function register_key_bindings(self)
    for index = #self.registered + 1, #self.keys do
        local key = self.keys[index]
        self.registered[index] = self.menu:AddKeyBinding(
            key.name,
            resolve(key.description),
            key.default_key,
            key.default_button,
            key.press_type,
            key.handler,
            resolve(key.text)
        )
    end
end

local function notice_wanted(self)
    local any = false
    for _, entry in ipairs(self.entries) do
        if entry.item then
            if not self.hidden[entry.item] then
                return false
            end
            any = true
        end
    end
    return any
end

local function update_notice_text(self)
    local notice = self.empty_notice
    if notice then
        notice.Text = Localization.get('framework.emptymenu')
        notice.Description = Localization.get('framework.emptymenu.desc')
    end
end

function Host:show_notice(wanted)
    if wanted == self.notice_shown then
        return
    end
    self.notice_shown = wanted
    if not wanted then
        self.menu:RemoveMenuItem(self.empty_notice)
        return
    end
    if not self.empty_notice then
        self.empty_notice = Items.MenuItem.new('')
        self.empty_notice.Enabled = false
    end
    update_notice_text(self)
    self.menu:AddMenuItem(self.empty_notice)
end

function Host:apply_filter()
    self.filter_dirty = false
    local menu = self.menu
    local restore = menu:GetCurrentMenuItem()
    local offset = menu.ViewIndexOffset
    local empty = notice_wanted(self)
    self:show_notice(empty)
    if next(self.hidden) == nil and self.user_filter == nil and not empty then
        menu:ResetFilter()
    else
        menu:FilterMenuItems(function(item)
            if item == self.empty_notice then
                return empty
            end
            return not self.hidden[item] and (self.user_filter == nil or self.user_filter(item))
        end)
    end
    if restore == nil then
        return
    end
    -- Filtering always goes back to the top, so put the player back on their
    -- row if it survived.
    local index = index_of(menu:GetMenuItems(), restore)
    if not index then
        menu:RefreshIndex(0, 0)
        return
    end
    index = index - 1
    local max = menu.MaxItemsOnScreen
    offset = math.min(offset, math.max(menu:Size() - max, 0))
    offset = math.max(math.max(index - max + 1, 0), math.min(offset, index))
    menu:RefreshIndex(index, offset)
end

-- Used for a permission resync, a language change and a settings change,
-- which must never disagree about what an item says.
function Host:refresh_with(defer_filter)
    self:refresh_header()
    register_key_bindings(self)
    for index, registered in ipairs(self.registered) do
        local key = self.keys[index]
        local allowed = Gate.evaluate(key.gate)
        registered.ButtonText = allowed and resolve(key.text) or nil
        registered.Handler = allowed and key.handler or nil
    end

    local fallback = self.default_gate_behaviour or Host.default_gate_behaviour
    local visibility_changed, revealed = false, false
    for _, entry in ipairs(self.entries) do
        entry.is_allowed = Gate.evaluate(entry:effective_gate())
        local behaviour = entry.read_behaviour and entry.read_behaviour() or entry.behaviour or fallback
        entry:apply_presentation(behaviour)
        local item = entry.item
        if item then
            local hide = not entry.is_allowed and behaviour == 'hide'
            if hide then
                if not self.hidden[item] then
                    self.hidden[item] = true
                    visibility_changed = true
                end
            elseif self.hidden[item] then
                self.hidden[item] = nil
                visibility_changed = true
                revealed = true
            end
        end
    end
    update_notice_text(self)

    if not visibility_changed and self.notice_shown == notice_wanted(self) then
        -- Leave the filter alone so the cursor does not jump.
        return
    end
    if defer_filter then
        self.needs_filter = true
        return
    end
    if self.menu.Visible and not revealed then
        -- Re-filtered when the menu next opens, not under the player's cursor.
        self.filter_dirty = true
        return
    end
    self:apply_filter()
end

function Host:refresh()
    self:refresh_with(false)
end

function Host:apply_pending_filter()
    if self.needs_filter and self.attached and self.update_depth == 0 then
        self.needs_filter = false
        self:apply_filter()
    end
end

-- Events -------------------------------------------------------------------------------

local function clear_confirmation(self)
    local entry = self.awaiting_confirmation
    if entry then
        self.awaiting_confirmation = nil
        entry:reset_confirmation()
    end
end

local function arm(self, entry)
    if entry:press_confirm() then
        self.awaiting_confirmation = nil
        return true
    end
    self.awaiting_confirmation = entry
    return false
end

local function run_async(self, entry, handler, args)
    if not handler then
        return
    end
    local single_flight = entry.single_flight ~= false
    if single_flight then
        if self.in_flight[entry] then
            return
        end
        self.in_flight[entry] = true
    end
    CreateThread(function()
        guard(args.item, handler, args)
        if single_flight then
            self.in_flight[entry] = nil
        end
    end)
end

local function stats_or_nil(read)
    return read and read() or nil
end

-- Drives the stats panels from the highlighted entry.
local function apply_highlight(self, item)
    local menu = self.menu
    local entry = item and self.by_item[item]
    if not entry then
        menu.ShowVehicleStatsPanel = false
        menu.ShowWeaponStatsPanel = false
        return
    end
    local vehicle = stats_or_nil(entry.vehicle_stats)
    if vehicle then
        local upgrades = stats_or_nil(entry.vehicle_upgrade_stats) or { 0, 0, 0, 0 }
        menu.ShowVehicleStatsPanel = true
        menu:SetVehicleStats(vehicle[1], vehicle[2], vehicle[3], vehicle[4])
        menu:SetVehicleUpgradeStats(upgrades[1], upgrades[2], upgrades[3], upgrades[4])
    else
        menu.ShowVehicleStatsPanel = false
    end
    local weapon = stats_or_nil(entry.weapon_stats)
    if weapon then
        local components = stats_or_nil(entry.weapon_component_stats) or { 0, 0, 0, 0 }
        menu.ShowWeaponStatsPanel = true
        menu:SetWeaponStats(weapon[1], weapon[2], weapon[3], weapon[4])
        menu:SetWeaponComponentStats(components[1], components[2], components[3], components[4])
    else
        menu.ShowWeaponStatsPanel = false
    end
    guard(item, function()
        entry:raise_highlighted()
    end)
end

local function handle_item_select(self, menu, item, item_index)
    local entry = self.by_item[item]
    if not entry or not item.Enabled then
        return
    end
    local args = { menu = menu, item = item, item_index = item_index }
    if entry.kind == 'submenu' then
        guard(item, entry.on_selected, args)
    elseif entry.kind == 'confirm_button' then
        if arm(self, entry) then
            guard(item, entry.on_confirmed, args)
            run_async(self, entry, entry.on_confirmed_async, args)
        end
    elseif entry.kind == 'button' then
        guard(item, entry.on_selected, args)
        run_async(self, entry, entry.on_selected_async, args)
    end
end

local function handle_checkbox_change(self, menu, item, item_index, checked)
    local entry = self.by_item[item]
    if not entry then
        return
    end
    -- Belt and braces: a checkbox only gets here through SelectItem, which
    -- honors Enabled.
    if not item.Enabled then
        item.Checked = not checked
        return
    end
    if entry.kind ~= 'checkbox' then
        return
    end
    local args = { menu = menu, item = item, item_index = item_index, checked = checked }
    guard(item, entry.on_changed, args)
    if entry.on_changed_async then
        CreateThread(function()
            guard(item, entry.on_changed_async, args)
        end)
    end
end

local function handle_list_index_change(self, menu, item, old_index, new_index, item_index)
    local entry = self.by_item[item]
    if not entry then
        return
    end
    -- Left and right do not check Enabled and the value already moved, so the
    -- change is undone instead of the callback suppressed.
    if not item.Enabled then
        item.ListIndex = old_index
        return
    end
    -- Scrolling to another value leaves whatever was confirmed.
    clear_confirmation(self)
    if entry.kind == 'list' or entry.kind == 'confirm_list' then
        guard(item, entry.on_index_changed, {
            menu = menu,
            item = item,
            item_index = item_index,
            old_index = old_index,
            new_index = new_index,
        })
    end
end

local function handle_list_select(self, menu, item, selected_index, item_index)
    local entry = self.by_item[item]
    if not entry or not item.Enabled then
        return
    end
    local args = {
        menu = menu,
        item = item,
        item_index = item_index,
        selected_index = selected_index,
        value = item:GetCurrentSelection(),
    }
    if entry.kind == 'confirm_list' then
        if arm(self, entry) then
            guard(item, entry.on_confirmed, args)
            run_async(self, entry, entry.on_confirmed_async, args)
        end
    elseif entry.kind == 'list' then
        guard(item, entry.on_selected, args)
        if entry.on_selected_async then
            CreateThread(function()
                guard(item, entry.on_selected_async, args)
            end)
        end
    end
end

local function handle_slider_moved(self, menu, item, old_position, new_position, item_index)
    local entry = self.by_item[item]
    if not entry then
        return
    end
    if not item.Enabled then
        item.Position = old_position
        return
    end
    if entry.kind == 'slider' then
        guard(item, entry.on_moved, {
            menu = menu,
            item = item,
            item_index = item_index,
            old_position = old_position,
            new_position = new_position,
        })
    end
end

local function handle_slider_select(self, menu, item, position, item_index)
    local entry = self.by_item[item]
    if not entry or not item.Enabled or entry.kind ~= 'slider' then
        return
    end
    local args = { menu = menu, item = item, item_index = item_index, position = position }
    guard(item, entry.on_selected, args)
    if entry.on_selected_async then
        CreateThread(function()
            guard(item, entry.on_selected_async, args)
        end)
    end
end

local function handle_dynamic_changed(self, menu, item, old_value, new_value)
    local entry = self.by_item[item]
    if not entry then
        return
    end
    if not item.Enabled then
        item.CurrentItem = old_value
        return
    end
    if entry.kind == 'dynamic_list' then
        guard(item, entry.on_changed, { menu = menu, item = item, old_value = old_value, new_value = new_value })
    end
end

local function handle_dynamic_select(self, menu, item, value)
    local entry = self.by_item[item]
    if not entry or not item.Enabled or entry.kind ~= 'dynamic_list' then
        return
    end
    local args = { menu = menu, item = item, value = value }
    guard(item, entry.on_selected, args)
    if entry.on_selected_async then
        CreateThread(function()
            guard(item, entry.on_selected_async, args)
        end)
    end
end

local function handle_menu_open(self, menu)
    clear_confirmation(self)
    -- Any code can call OpenMenu directly, so the menu checks its own gate
    -- instead of trusting the door.
    if not self:is_reachable() then
        menu:CloseMenu()
        if self.parent then
            self.parent.menu:OpenMenu()
        end
        return
    end
    -- A row bound to a submenu is opened by MenuAPI itself, so a title that
    -- depends on what was just picked has had no refresh since.
    self:refresh_header()
    if self.filter_dirty then
        self:apply_filter()
    end
    local current = menu:GetCurrentMenuItem()
    apply_highlight(self, current)
    local opened = { menu = menu, current_item = current }
    guard_all(current, self.opened_handlers, opened)
    if #self.opened_async_handlers == 0 or self.open_in_flight then
        return
    end
    self.open_in_flight = true
    CreateThread(function()
        for _, handler in ipairs(self.opened_async_handlers) do
            local ok, err = pcall(handler, opened)
            if not ok then
                Log.error(("[Menu] '%s' open handler threw: %s"):format(tostring(menu.MenuTitle), tostring(err)))
                break
            end
        end
        self.open_in_flight = false
    end)
end

-- Opening a submenu closes this one, so this covers walking away too.
local function handle_menu_close(self, menu)
    clear_confirmation(self)
    guard_all(nil, self.closed_handlers, menu)
end

function Host:handle_index_change(menu, old_item, new_item, old_index, new_index)
    clear_confirmation(self)
    apply_highlight(self, new_item)
    guard_all(new_item, self.index_changed_handlers, {
        menu = menu,
        old_item = old_item,
        new_item = new_item,
        old_index = old_index,
        new_index = new_index,
    })
end

local EVENTS = {
    OnItemSelect = handle_item_select,
    OnCheckboxChange = handle_checkbox_change,
    OnListItemSelect = handle_list_select,
    OnListIndexChange = handle_list_index_change,
    OnSliderItemSelect = handle_slider_select,
    OnSliderPositionChange = handle_slider_moved,
    OnDynamicListItemSelect = handle_dynamic_select,
    OnDynamicListItemCurrentItemChange = handle_dynamic_changed,
    OnMenuOpen = handle_menu_open,
    OnMenuClose = handle_menu_close,
}

function Host:attach()
    if self.attached then
        return
    end
    self.attached = true
    for event, handler in pairs(EVENTS) do
        self.menu[event] = function(...)
            handler(self, ...)
        end
    end
    self.menu.OnIndexChange = function(...)
        self:handle_index_change(...)
    end
end

function Host:dispose()
    if not self.attached then
        return
    end
    self.attached = false
    for event in pairs(EVENTS) do
        self.menu[event] = nil
    end
    self.menu.OnIndexChange = nil
end

return Host
