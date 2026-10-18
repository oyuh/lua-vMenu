-- Port of vMenu.Enhanced.Plugins/PluginValidation.cs: indexes a plugin's
-- menus, items and keys into its state, skipping (with a warning) what cannot
-- be shown and refusing (with an error) what would make the tree ambiguous.
-- report is { accepted, errors, warnings }.

local Config = require('shared.config')
local State = require('client.plugins.state')

local Validation = {}

Validation.MAX_ITEMS = 2000
Validation.MAX_DEPTH = 8
Validation.MAX_KEYS = 25
local MAX_KEY_NAME_LENGTH = 32

local PLAYER_ACTION_TYPES = { button = true, confirmButton = true, list = true, separator = true }

local is_text = State.is_text

local function warn(report, message, ...)
    report.warnings[#report.warnings + 1] = message:format(...)
end

local function fail(report, message, ...)
    report.errors[#report.errors + 1] = message:format(...)
end

local function at_capacity(state)
    return state.item_count >= Validation.MAX_ITEMS
end

local function is_key_name(name)
    return type(name) == 'string' and #name > 0 and #name <= MAX_KEY_NAME_LENGTH and name:match('^[%w_]+$') ~= nil
end

local function key_problem(state, key)
    local id = key.id
    if type(id) ~= 'string' or not Config.is_valid_segment(id) then
        return ("Key '%s' was skipped: key ids may only contain letters, digits and underscores."):format(tostring(id))
    end
    if state.keys_by_id[id] then
        return ("Key id '%s' is used twice, the second one was skipped."):format(id)
    end
    local count = 0
    for _ in pairs(state.keys_by_id) do
        count = count + 1
    end
    if count >= Validation.MAX_KEYS then
        return ("Key '%s' was skipped: a plugin may declare at most %d keys."):format(id, Validation.MAX_KEYS)
    end
    if not is_key_name(key.defaultKey) then
        return ("Key '%s' was skipped: '%s' is not a keyboard key name."):format(id, tostring(key.defaultKey))
    end
    if is_text(key.defaultButton) and not is_key_name(key.defaultButton) then
        return ("Key '%s' was skipped: '%s' is not a controller button name."):format(id, key.defaultButton)
    end
    if key.shadowedControl ~= nil and (math.type(key.shadowedControl) ~= 'integer' or key.shadowedControl < 0) then
        return ("Key '%s' was skipped: %s is not a game control."):format(id, tostring(key.shadowedControl))
    end
    return nil
end

local function index_keys(state, menu, report)
    local keys = menu.keys
    if type(keys) ~= 'table' then
        return
    end
    local index = 1
    while index <= #keys do
        local key = keys[index]
        local problem = key_problem(state, key)
        if problem then
            report.warnings[#report.warnings + 1] = problem
            table.remove(keys, index)
        else
            state.keys_by_id[key.id] = key
            index = index + 1
        end
    end
end

function Validation.index_late_key(state, key, report)
    local problem = key_problem(state, key)
    if problem then
        report.warnings[#report.warnings + 1] = problem
        return false
    end
    state.keys_by_id[key.id] = key
    return true
end

function Validation.index_item(state, node, menu_id, report)
    local id = node.id
    if not is_text(id) then
        warn(report, 'An item without an id was skipped.')
        return false
    end
    if state.items_by_id[id] then
        warn(report, "Item id '%s' is used twice, the second one was skipped.", id)
        return false
    end
    node.type = node.type or 'button'
    local kind = node.type
    if kind == 'list' or kind == 'confirmList' then
        if type(node.options) ~= 'table' or #node.options == 0 then
            warn(report, "List '%s' was skipped: it has no options.", id)
            return false
        end
    elseif kind == 'slider' then
        if (tonumber(node.min) or 0) >= (tonumber(node.max) or 0) then
            warn(report, "Slider '%s' was skipped: min must be smaller than max.", id)
            return false
        end
    elseif kind == 'submenu' then
        if type(node.menu) ~= 'table' then
            warn(report, "Submenu '%s' was skipped: it declares no menu.", id)
            return false
        end
    elseif
        not (
            kind == 'button'
            or kind == 'confirmButton'
            or kind == 'checkbox'
            or kind == 'dynamicList'
            or kind == 'separator'
        )
    then
        warn(report, "Item '%s' was skipped: unknown type '%s'.", id, tostring(kind))
        return false
    end
    state.items_by_id[id] = node
    state.item_owners[id] = menu_id
    state.item_count = state.item_count + 1
    return true
end

function Validation.unindex(state, node)
    local id = node.id
    if state.items_by_id[id] then
        state.item_count = state.item_count - 1
    end
    state.items_by_id[id] = nil
    state.item_owners[id] = nil
    state.player_action_ids[id] = nil
    state.options_by_item_id[id] = nil
    local entry = state.entries_by_id[id]
    state.entries_by_id[id] = nil
    if entry and entry.item then
        state.nodes_by_item[entry.item] = nil
    end
    local menu = node.type == 'submenu' and node.menu
    if type(menu) ~= 'table' then
        return
    end
    state.menus_by_id[menu.id] = nil
    state.menu_depths[menu.id] = nil
    state.menu_filters[menu.id] = nil
    for _, key in ipairs(menu.keys or {}) do
        state.keys_by_id[key.id] = nil
    end
    local builder = state:remove_builder(menu.id)
    if builder then
        state:forget_items_of(builder)
    end
    for _, child in ipairs(menu.items or {}) do
        Validation.unindex(state, child)
    end
end

local function index_menu(state, menu, depth, report)
    if type(menu) ~= 'table' or not is_text(menu.id) then
        fail(report, 'A menu has no id.')
        return false
    end
    if state.menus_by_id[menu.id] then
        fail(report, "Menu id '%s' is used twice.", menu.id)
        return false
    end
    state.menus_by_id[menu.id] = menu
    menu.items = type(menu.items) == 'table' and menu.items or {}
    state.menu_depths[menu.id] = depth
    index_keys(state, menu, report)
    local items = menu.items
    local index = 1
    while index <= #items do
        local node = items[index]
        if at_capacity(state) then
            fail(report, 'The menu tree holds more than %d items.', Validation.MAX_ITEMS)
            return false
        end
        if type(node) ~= 'table' or not Validation.index_item(state, node, menu.id, report) then
            table.remove(items, index)
        elseif node.type == 'submenu' and depth + 1 > Validation.MAX_DEPTH then
            warn(report, "Submenu '%s' was skipped: menus nest deeper than %d levels.", node.id, Validation.MAX_DEPTH)
            Validation.unindex(state, node)
            table.remove(items, index)
        else
            if node.type == 'submenu' and not index_menu(state, node.menu, depth + 1, report) then
                return false
            end
            index = index + 1
        end
    end
    return true
end

function Validation.index_menu_tree(state, menu, report)
    return index_menu(state, menu, 1, report)
end

local function snapshot(set)
    local copy = {}
    for id in pairs(set) do
        copy[id] = true
    end
    return copy
end

-- Like index_menu_tree, but a failure leaves the state as it was.
function Validation.index_late_menu_tree(state, menu, report)
    local items = snapshot(state.items_by_id)
    local menus = snapshot(state.menus_by_id)
    local keys = snapshot(state.keys_by_id)
    if Validation.index_menu_tree(state, menu, report) then
        return true
    end
    for id in pairs(snapshot(state.items_by_id)) do
        if not items[id] then
            state.item_count = state.item_count - 1
            state.items_by_id[id] = nil
            state.item_owners[id] = nil
        end
    end
    for id in pairs(snapshot(state.menus_by_id)) do
        if not menus[id] then
            state.menus_by_id[id] = nil
            state.menu_depths[id] = nil
        end
    end
    for id in pairs(snapshot(state.keys_by_id)) do
        if not keys[id] then
            state.keys_by_id[id] = nil
        end
    end
    return false
end

function Validation.index_player_action(state, node, report)
    if at_capacity(state) then
        warn(
            report,
            "Player action '%s' was skipped: the plugin is at its ceiling of %d items.",
            tostring(node.id),
            Validation.MAX_ITEMS
        )
        return false
    end
    if not PLAYER_ACTION_TYPES[node.type or 'button'] then
        warn(
            report,
            "Player action '%s' was skipped: type '%s' cannot be shared across players, "
                .. 'use button, confirmButton, list or separator.',
            tostring(node.id),
            tostring(node.type)
        )
        return false
    end
    if not Validation.index_item(state, node, State.PLAYER_ACTIONS_MENU_ID, report) then
        return false
    end
    state.player_action_ids[node.id] = true
    return true
end

function Validation.index_late_item(state, node, menu_id, report)
    if at_capacity(state) then
        warn(
            report,
            "Item '%s' was skipped: the plugin is at its ceiling of %d items.",
            tostring(node.id),
            Validation.MAX_ITEMS
        )
        return false
    end
    local depth = state.menu_depths[menu_id] or 1
    if node.type == 'submenu' and depth + 1 > Validation.MAX_DEPTH then
        warn(report, "Submenu '%s' was skipped: menus nest deeper than %d levels.", node.id, Validation.MAX_DEPTH)
        return false
    end
    if not Validation.index_item(state, node, menu_id, report) then
        return false
    end
    if node.type ~= 'submenu' then
        return true
    end
    if index_menu(state, node.menu, depth + 1, report) then
        return true
    end
    Validation.unindex(state, node)
    return false
end

return Validation
