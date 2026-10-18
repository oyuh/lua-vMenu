-- Port of vMenu.Enhanced.Plugins/PluginEntryFactory.cs: turns a plugin's
-- menu and item nodes into framework entries. Every text, flag and value is
-- read from the node on each refresh, so an update only has to change the
-- node and invalidate the menu.

local Localization = require('shared.localization')
local Gate = require('client.framework.gate')
local Entries = require('client.framework.entries')
local Icons = require('menu.icons')
local State = require('client.plugins.state')

local Factory = {}

local ICONS = {}
for _, name in ipairs(Icons.NAMES) do
    ICONS[name] = true
end

local CONFIRM_DESCRIPTION = Localization.key('framework.confirm')

function Factory.live(state, read)
    return Localization.from(function()
        return state:resolve(read())
    end)
end

local live = Factory.live

-- A fixed TextRef, or '' for none.
function Factory.text_for(state, reference)
    if reference == nil then
        return ''
    end
    return live(state, function()
        return reference
    end)
end

-- Exact match, like upstream's StringComparer.Ordinal.
function Factory.wants(events, name)
    if type(events) ~= 'table' then
        return false
    end
    for _, subscribed in ipairs(events) do
        if subscribed == name then
            return true
        end
    end
    return false
end

local function icon(name)
    if type(name) ~= 'string' then
        return 'NONE'
    end
    name = name:upper()
    return ICONS[name] and name or 'NONE'
end

local function behaviour_for(node)
    local behaviour = type(node.behaviour) == 'string' and node.behaviour:lower()
    if behaviour == 'hide' or behaviour == 'lock' then
        return behaviour
    end
    return nil
end

local function callback(kind, menu_id, node)
    return { type = kind, menuId = menu_id, itemId = node.id }
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

-- The options the list entry reads, refilled in place by setOptions.
function Factory.fill_options(state, node, options)
    for index = #options, 1, -1 do
        options[index] = nil
    end
    for index, option in ipairs(type(node.options) == 'table' and node.options or {}) do
        options[index] = live(state, function()
            return option
        end)
    end
end

local function build_options(state, node)
    local options = {}
    state.options_by_item_id[node.id] = options
    Factory.fill_options(state, node, options)
    return options
end

-- The options every interactive row shares.
local function common(state, node, menu_id, with_label)
    return {
        text = live(state, function()
            return node.text
        end),
        description = live(state, function()
            return node.description
        end),
        label = with_label and live(state, function()
            return node.label
        end) or nil,
        locked_description = live(state, function()
            return node.lockedDescription
        end),
        gate = Gate.when(function()
            return state:evaluate_gate(node.gate)
        end),
        read_behaviour = function()
            return behaviour_for(node)
        end,
        read_enabled = function()
            return node.enabled ~= false
        end,
        read_left_icon = function()
            return icon(node.leftIcon)
        end,
        read_right_icon = function()
            return icon(node.rightIcon)
        end,
        on_highlighted = function()
            if Factory.wants(node.events, 'highlighted') then
                state:emit(callback('itemHighlighted', menu_id, node))
            end
        end,
        configure = function(item)
            state.nodes_by_item[item] = node
        end,
    }
end

local function confirmation_for(state, node)
    return Localization.from(function()
        if node.confirmationDescription ~= nil then
            return state:resolve(node.confirmationDescription)
        end
        return Localization.resolve(CONFIRM_DESCRIPTION)
    end)
end

local function list_options(state, node, menu_id, options)
    local entry = common(state, node, menu_id, false)
    entry.options = options
    entry.read_selected_index = function()
        return clamp(math.tointeger(node.selectedIndex) or 0, 0, math.max(0, #options - 1))
    end
    entry.on_index_changed = function(args)
        node.selectedIndex = args.new_index
        local changed = callback('listIndexChanged', menu_id, node)
        changed.oldIndex = args.old_index
        changed.newIndex = args.new_index
        state:emit(changed)
    end
    return entry
end

local builders = {}

function builders.button(state, node, menu_id)
    local entry = common(state, node, menu_id, true)
    entry.on_selected = function()
        state:emit(callback('itemSelected', menu_id, node))
    end
    return Entries.button(entry)
end

function builders.confirmButton(state, node, menu_id)
    local entry = common(state, node, menu_id, true)
    entry.confirmation_description = confirmation_for(state, node)
    entry.on_confirmed = function()
        state:emit(callback('confirmed', menu_id, node))
    end
    return Entries.confirm_button(entry)
end

function builders.checkbox(state, node, menu_id)
    local entry = common(state, node, menu_id, false)
    entry.read_state = function()
        return node.checked == true
    end
    entry.style = type(node.checkStyle) == 'string' and node.checkStyle:lower() == 'cross' and 'Cross' or 'Tick'
    entry.on_changed = function(args)
        node.checked = args.checked
        local changed = callback('checkboxChanged', menu_id, node)
        changed.checked = args.checked
        state:emit(changed)
    end
    return Entries.checkbox(entry)
end

function builders.list(state, node, menu_id)
    local entry = list_options(state, node, menu_id, build_options(state, node))
    entry.on_selected = function(args)
        local selected = callback('listSelected', menu_id, node)
        selected.selectedIndex = args.selected_index
        state:emit(selected)
    end
    return Entries.list(entry)
end

function builders.confirmList(state, node, menu_id)
    local entry = list_options(state, node, menu_id, build_options(state, node))
    entry.confirmation_description = confirmation_for(state, node)
    entry.on_confirmed = function(args)
        local confirmed = callback('confirmed', menu_id, node)
        confirmed.selectedIndex = args.selected_index
        state:emit(confirmed)
    end
    return Entries.confirm_list(entry)
end

function builders.slider(state, node, menu_id)
    local minimum = math.tointeger(node.min) or 0
    local maximum = math.tointeger(node.max) or 10
    local entry = common(state, node, menu_id, false)
    entry.min = minimum
    entry.max = maximum
    entry.show_divider = node.showDivider == true
    entry.read_position = function()
        return clamp(math.tointeger(node.position) or minimum, minimum, maximum)
    end
    entry.on_moved = function(args)
        node.position = args.new_position
        local moved = callback('sliderMoved', menu_id, node)
        moved.oldPosition = args.old_position
        moved.newPosition = args.new_position
        state:emit(moved)
    end
    entry.on_selected = function(args)
        local selected = callback('sliderSelected', menu_id, node)
        selected.position = args.position
        state:emit(selected)
    end
    return Entries.slider(entry)
end

function builders.dynamicList(state, node, menu_id)
    local entry = common(state, node, menu_id, false)
    entry.read_value = function()
        return node.value ~= nil and tostring(node.value) or ''
    end
    -- Local events run synchronously, so a plugin that answers with setValue
    -- has already changed node.value when this returns.
    entry.change = function(args)
        local changing = callback('dynamicChanging', menu_id, node)
        changing.currentValue = args.current_value
        changing.left = args.left
        state:emit(changing)
        return node.value ~= nil and tostring(node.value) or args.current_value
    end
    entry.on_selected = function(args)
        local selected = callback('dynamicSelected', menu_id, node)
        selected.value = args.value
        state:emit(selected)
    end
    return Entries.dynamic_list(entry)
end

function builders.separator(state, node)
    return Entries.separator({
        text = live(state, function()
            return node.text
        end),
        description = live(state, function()
            return node.description
        end),
        gate = Gate.when(function()
            return state:evaluate_gate(node.gate)
        end),
        read_behaviour = function()
            return behaviour_for(node)
        end,
        configure = function(item)
            state.nodes_by_item[item] = node
        end,
    })
end

function builders.submenu(state, node, menu_id)
    local child = node.menu
    if type(child) ~= 'table' then
        return nil
    end
    local entry = common(state, node, menu_id, true)
    entry.menu_title = live(state, function()
        return child.title
    end)
    entry.menu_subtitle = live(state, function()
        return child.subtitle
    end)
    entry.build = function(builder)
        Factory.build_menu(state, child, builder)
    end
    return Entries.submenu(entry)
end

function Factory.create_entry(state, node, menu_id)
    local build = builders[node.type]
    local entry = build and build(state, node, menu_id)
    if entry then
        state.entries_by_id[node.id] = entry
    end
    return entry
end

local function key_pressed(state, menu, menu_id, key)
    local pressed = { type = 'keyPressed', menuId = menu_id, keyId = key.id }
    local item = menu:GetCurrentMenuItem()
    local node = item and state.nodes_by_item[item]
    if not node then
        return pressed
    end
    if item.Enabled then
        pressed.itemId = node.id
    else
        pressed.disabledItemId = node.id
    end
    return pressed
end

function Factory.create_key(state, key, menu_id)
    return {
        name = ('plugin:%s:%s'):format(state.id, key.id),
        description = Localization.from(function()
            return state:display_name_text() .. ': ' .. state:resolve(key.description or key.text)
        end),
        default_key = key.defaultKey,
        default_button = State.is_text(key.defaultButton) and key.defaultButton or nil,
        shadowed_control = key.shadowedControl,
        text = live(state, function()
            return key.text
        end),
        gate = Gate.when(function()
            return key.enabled ~= false and state:evaluate_gate(key.gate)
        end),
        handler = function(menu)
            state:emit(key_pressed(state, menu, menu_id, key))
        end,
    }
end

function Factory.build_menu(state, menu_node, builder)
    state:add_builder(menu_node.id, builder)
    builder:set_user_filter(function(item)
        return state:is_visible(item)
    end)
    builder:on_opened(function()
        if Factory.wants(menu_node.events, 'opened') then
            state:emit({ type = 'menuOpened', menuId = menu_node.id })
        end
    end)
    builder:on_closed(function()
        if Factory.wants(menu_node.events, 'closed') then
            state:emit({ type = 'menuClosed', menuId = menu_node.id })
        end
    end)
    builder:on_index_changed(function(args)
        if Factory.wants(menu_node.events, 'indexChanged') then
            state:emit({
                type = 'menuIndexChanged',
                menuId = menu_node.id,
                oldIndex = args.old_index,
                newIndex = args.new_index,
            })
        end
    end)
    for _, key in ipairs(menu_node.keys or {}) do
        builder:add_key(Factory.create_key(state, key, menu_node.id))
    end
    for _, node in ipairs(menu_node.items) do
        local entry = Factory.create_entry(state, node, menu_node.id)
        if entry then
            builder:add(entry)
        end
    end
end

return Factory
