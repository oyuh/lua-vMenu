-- Port of vMenu.Enhanced.Plugins/PluginUpdateOps.cs: applies a batch of
-- update ops from a plugin. Ops change nodes and record which menus need a
-- refresh; the batch settles once at the end, so a hundred setText ops cost
-- one refresh per menu.

local Log = require('shared.log')
local Controller = require('menu.controller')
local Registry = require('client.framework.registry')
local Arbiter = require('client.framework.arbiter')
local State = require('client.plugins.state')
local Validation = require('client.plugins.validation')
local Factory = require('client.plugins.entry_factory')

local UpdateOps = {}

local function host()
    -- Required lazily: the host requires this module.
    return require('client.plugins.host')
end

local function default(value, fallback)
    if value == nil then
        return fallback
    end
    return value
end

local function new_report()
    return { accepted = true, errors = {}, warnings = {} }
end

local function log_report(state, report)
    for _, warning in ipairs(report.warnings) do
        Log.warning(("[Plugins] '%s': %s"):format(state.resource, warning))
    end
    for _, problem in ipairs(report.errors) do
        Log.warning(("[Plugins] '%s': %s"):format(state.resource, problem))
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

local function remove_value(list, value)
    for index = #list, 1, -1 do
        if list[index] == value then
            table.remove(list, index)
            return
        end
    end
end

-- Changes ----------------------------------------------------------------------------

local Changes = {}
Changes.__index = Changes

local function new_changes(state)
    return setmetatable({
        state = state,
        refresh = {},
        filter = {},
        updates = {},
        replies = {},
        everything = false,
        gates_changed = false,
        open_after = nil, -- { builder, op }
        close_after = false,
        select_after = nil, -- { builder, entry }
    }, Changes)
end

function Changes:item(node)
    local state = self.state
    if state.player_action_ids[node.id] then
        return
    end
    local owner = state.item_owners[node.id]
    if owner then
        self.refresh[owner] = true
    end
end

function Changes:visibility(node)
    local owner = not self.state.player_action_ids[node.id] and self.state.item_owners[node.id]
    if owner then
        self.filter[owner] = true
    end
end

function Changes:menu(menu_id)
    if menu_id then
        self.refresh[menu_id] = true
    end
end

-- Holds the builder's refresh until the batch settles.
function Changes:structure(builder)
    if index_of(self.updates, builder) then
        return
    end
    self.updates[#self.updates + 1] = builder
    builder:begin_update()
end

function Changes:answer(request_id, reason)
    if request_id ~= nil then
        self.replies[#self.replies + 1] = { request_id, reason }
    end
end

function Changes:supersede()
    if self.open_after then
        self:answer(self.open_after.op.requestId, 'superseded')
    end
end

function Changes:send_replies()
    for _, reply in ipairs(self.replies) do
        self.state:reply_open(reply[1], reply[2])
    end
    self.replies = {}
end

function Changes:apply_refresh()
    local state = self.state
    if self.everything then
        for menu_id in pairs(state.builders) do
            self.refresh[menu_id] = true
        end
        host().refresh_row(state)
    end
    for menu_id in pairs(self.refresh) do
        local builder = state.builders[menu_id]
        if builder then
            self:structure(builder)
            builder:invalidate()
        end
    end
    for menu_id in pairs(self.filter) do
        local builder = state.builders[menu_id]
        if builder then
            self:structure(builder)
            builder:invalidate_filter()
        end
    end
    -- Every builder is released even when one refresh throws.
    local first_error
    for _, builder in ipairs(self.updates) do
        local ok, err = pcall(builder.end_update, builder)
        first_error = first_error or (not ok and err) or nil
    end
    self.updates = {}
    if self.gates_changed then
        Registry.back_out_if_unreachable()
    end
    if first_error then
        error(first_error, 0)
    end
end

function Changes:open(builder, op)
    local state = self.state
    local priority = Arbiter.priority(op.priority)
    local do_not_close = op.doNotClose == true
    if do_not_close and priority ~= Arbiter.HIGH then
        Log.warning(
            ("[Plugins] '%s' asked to keep menu '%s' open below high priority, which only high allows."):format(
                state.resource,
                tostring(op.menuId)
            )
        )
        do_not_close = false
    end
    self:answer(op.requestId, Arbiter.try_open(builder.menu, state.resource, priority, do_not_close))
end

function Changes:navigate()
    local state = self.state
    if self.close_after then
        local open = Controller.GetCurrentMenu()
        if open and state:menu_id_of(open) then
            Arbiter.release_for(state.resource)
            open:CloseMenu()
        end
    end
    if self.open_after then
        self:open(self.open_after.builder, self.open_after.op)
    end
    if self.select_after then
        self.select_after.builder:select(self.select_after.entry)
    end
end

function Changes:settle()
    local ok, err = pcall(self.apply_refresh, self)
    self:navigate()
    if not ok then
        error(err, 0)
    end
end

-- Lookups ----------------------------------------------------------------------------

local function warn_unknown(state, what, id, op)
    Log.warning(
        ("[Plugins] '%s' targeted unknown %s '%s' with op '%s'."):format(
            state.resource,
            what,
            tostring(id),
            tostring(op.op)
        )
    )
end

local function find_item(state, op)
    local node = State.is_text(op.itemId) and state.items_by_id[op.itemId]
    if not node then
        warn_unknown(state, 'item', op.itemId, op)
        return nil
    end
    return node
end

local function find_menu(state, op)
    local menu = State.is_text(op.menuId) and state.menus_by_id[op.menuId]
    if not menu then
        warn_unknown(state, 'menu', op.menuId, op)
        return nil
    end
    return menu
end

-- The key and the id of the menu that declares it.
local function find_key(state, op)
    local key = State.is_text(op.keyId) and state.keys_by_id[op.keyId]
    if not key then
        warn_unknown(state, 'key', op.keyId, op)
        return nil
    end
    for menu_id, menu in pairs(state.menus_by_id) do
        if index_of(menu.keys or {}, key) then
            return key, menu_id
        end
    end
    return key, nil
end

-- 1-based position to insert at in menu.items: before the anchor, or last.
local function anchor_position(state, menu, before_item_id)
    local anchor = before_item_id ~= nil and state.items_by_id[before_item_id]
    return anchor and index_of(menu.items, anchor) or #menu.items + 1
end

-- 0-based entry index in the builder: the anchor's, or the end.
local function entry_index(state, builder, before_item_id)
    local anchor = before_item_id ~= nil and state.entries_by_id[before_item_id]
    local index = anchor and index_of(builder.entries, anchor)
    return index and index - 1 or #builder.entries
end

-- Ops --------------------------------------------------------------------------------

local function add_items(state, menu, op, changes)
    local report = new_report()
    local builder = state.builders[menu.id]
    local position = anchor_position(state, menu, op.beforeItemId)
    local index = builder and entry_index(state, builder, op.beforeItemId) or 0
    local added = false
    for _, node in ipairs(op.items) do
        if type(node) ~= 'table' then
            Log.warning(("[Plugins] '%s' sent an item that is not an object."):format(state.resource))
        elseif node.id ~= nil and state.item_owners[node.id] == menu.id then
            Log.debug(
                ("[Plugins] '%s': item '%s' is already in menu '%s', the repeat was skipped."):format(
                    state.resource,
                    tostring(node.id),
                    menu.id
                )
            )
        elseif Validation.index_late_item(state, node, menu.id, report) then
            table.insert(menu.items, position, node)
            position = position + 1
            added = true
            local entry = builder and Factory.create_entry(state, node, menu.id)
            if entry then
                changes:structure(builder)
                builder:insert(index, entry)
                index = index + 1
            end
        end
    end
    log_report(state, report)
    if added and not builder then
        host().materialise_row(state)
    end
end

local function remove_items(state, ids, changes)
    for _, id in ipairs(ids) do
        local node = state.items_by_id[id]
        local owner = state.item_owners[id]
        if not node or not owner then
            Log.warning(("[Plugins] '%s' asked to remove unknown item '%s'."):format(state.resource, tostring(id)))
        elseif owner == State.PLAYER_ACTIONS_MENU_ID then
            remove_value(state.player_actions, node)
            Validation.unindex(state, node)
        else
            local menu = state.menus_by_id[owner]
            if menu then
                remove_value(menu.items, node)
            end
            local builder = state.builders[owner]
            local entry = state.entries_by_id[id]
            if builder and entry then
                changes:structure(builder)
                builder:remove(entry)
            end
            local filtered = state.menu_filters[owner]
            if filtered then
                filtered[id] = nil
            end
            Validation.unindex(state, node)
        end
    end
end

local function move_item(state, node, before_item_id, changes)
    local owner = state.item_owners[node.id]
    local menu = owner and state.menus_by_id[owner]
    if not menu or before_item_id == node.id then
        return
    end
    if before_item_id ~= nil and state.item_owners[before_item_id] ~= owner then
        Log.warning(
            ("[Plugins] '%s' tried to move '%s' next to '%s', which is not in the same menu."):format(
                state.resource,
                node.id,
                tostring(before_item_id)
            )
        )
        return
    end
    remove_value(menu.items, node)
    table.insert(menu.items, anchor_position(state, menu, before_item_id), node)
    local builder = state.builders[owner]
    local entry = state.entries_by_id[node.id]
    if not builder or not entry then
        return
    end
    local from = index_of(builder.entries, entry) - 1
    local to = entry_index(state, builder, before_item_id)
    changes:structure(builder)
    builder:move(entry, to > from and to - 1 or to)
end

local function clear_menu(state, menu)
    for _, node in ipairs(menu.items) do
        Validation.unindex(state, node)
    end
    menu.items = {}
    state.menu_filters[menu.id] = nil
    local builder = state.builders[menu.id]
    if builder then
        state:forget_items_of(builder)
        builder:clear_entries()
    end
end

local function add_keys(state, menu, keys, changes)
    local report = new_report()
    local builder = state.builders[menu.id]
    for _, key in ipairs(keys) do
        if type(key) == 'table' and Validation.index_late_key(state, key, report) then
            menu.keys = menu.keys or {}
            menu.keys[#menu.keys + 1] = key
            if builder then
                builder:add_key(Factory.create_key(state, key, menu.id))
                changes:menu(menu.id)
            end
        end
    end
    log_report(state, report)
end

-- Ops that only change one field of an item node.
local PRESENT = {
    setText = function(node, op)
        node.text = op.textValue
    end,
    setDescription = function(node, op)
        node.description = op.textValue
    end,
    setLabel = function(node, op)
        node.label = op.textValue
    end,
    setLockedDescription = function(node, op)
        node.lockedDescription = op.textValue
    end,
    setConfirmationDescription = function(node, op)
        node.confirmationDescription = op.textValue
    end,
    setIcons = function(node, op)
        node.leftIcon = op.leftIcon
        node.rightIcon = op.rightIcon
    end,
    setChecked = function(node, op)
        node.checked = op.flag == true
    end,
    setSelectedIndex = function(node, op)
        node.selectedIndex = op.index or 0
    end,
    setSliderPosition = function(node, op)
        node.position = op.index or 0
    end,
    setValue = function(node, op)
        node.value = op.value or ''
    end,
    setEnabled = function(node, op)
        node.enabled = default(op.flag, true)
    end,
    setBehaviour = function(node, op)
        node.behaviour = op.value
    end,
    setGate = function(node, op)
        node.gate = op.gate
    end,
}

local OPS = {}

function OPS.setOptions(state, op, changes)
    local node = find_item(state, op)
    if not node then
        return
    end
    node.options = op.options or {}
    if op.index ~= nil then
        node.selectedIndex = op.index
    end
    local live = state.options_by_item_id[node.id]
    if live then
        Factory.fill_options(state, node, live)
    end
    changes:item(node)
end

function OPS.setVisible(state, op, changes)
    local node = find_item(state, op)
    if node then
        node.visible = default(op.flag, true)
        changes:visibility(node)
    end
end

function OPS.setLog(state, op)
    local node = find_item(state, op)
    if node then
        node.log = op.flag == true
    end
end

function OPS.setItemEvents(state, op)
    local node = find_item(state, op)
    if node then
        node.events = op.events
    end
end

function OPS.setMenuTitle(state, op, changes)
    local menu = find_menu(state, op)
    if menu then
        menu.title = op.textValue
        changes:menu(menu.id)
    end
end

function OPS.setMenuSubtitle(state, op, changes)
    local menu = find_menu(state, op)
    if menu then
        menu.subtitle = op.textValue
        changes:menu(menu.id)
    end
end

function OPS.setMenuEvents(state, op)
    local menu = find_menu(state, op)
    if menu then
        menu.events = op.events
    end
end

function OPS.addItems(state, op, changes)
    local menu = find_menu(state, op)
    if menu and type(op.items) == 'table' and #op.items > 0 then
        add_items(state, menu, op, changes)
    end
end

function OPS.removeItems(state, op, changes)
    if type(op.itemIds) == 'table' then
        remove_items(state, op.itemIds, changes)
    end
end

function OPS.moveItem(state, op, changes)
    local node = find_item(state, op)
    if node then
        move_item(state, node, op.beforeItemId, changes)
    end
end

function OPS.clearMenu(state, op)
    local menu = find_menu(state, op)
    if menu then
        clear_menu(state, menu)
    end
end

function OPS.setFilter(state, op, changes)
    local menu = find_menu(state, op)
    if not menu then
        return
    end
    local hidden = op.flag == true and state.menu_filters[menu.id]
    if not hidden then
        hidden = {}
        state.menu_filters[menu.id] = hidden
    end
    for _, id in ipairs(op.itemIds or {}) do
        hidden[id] = true
    end
    changes.filter[menu.id] = true
end

function OPS.clearFilter(state, op, changes)
    local menu = find_menu(state, op)
    if menu and state.menu_filters[menu.id] then
        state.menu_filters[menu.id] = nil
        changes.filter[menu.id] = true
    end
end

function OPS.addPlayerActions(state, op)
    if type(op.items) ~= 'table' then
        return
    end
    local report = new_report()
    for _, node in ipairs(op.items) do
        if type(node) == 'table' and Validation.index_player_action(state, node, report) then
            state.player_actions[#state.player_actions + 1] = node
        end
    end
    log_report(state, report)
end

function OPS.openMenu(state, op, changes)
    local builder = State.is_text(op.menuId) and state.menus_by_id[op.menuId] and state.builders[op.menuId]
    if not builder then
        warn_unknown(state, 'menu', op.menuId, op)
        changes:answer(op.requestId, 'unknownMenu')
        return
    end
    changes:supersede()
    changes.open_after = { builder = builder, op = op }
    changes.close_after = false
end

function OPS.closeMenu(_, _, changes)
    changes:supersede()
    changes.open_after = nil
    changes.close_after = true
end

function OPS.selectItem(state, op, changes)
    local node = find_item(state, op)
    local builder = node and state.builders[state.item_owners[node.id]]
    local entry = node and state.entries_by_id[node.id]
    if builder and entry then
        changes.select_after = { builder = builder, entry = entry }
    end
end

function OPS.addStandaloneMenu(state, op)
    if type(op.menu) == 'table' then
        local report = new_report()
        host().add_standalone(state, op.menu, report)
        log_report(state, report)
    end
end

function OPS.addKeys(state, op, changes)
    local menu = find_menu(state, op)
    if menu and type(op.keys) == 'table' and #op.keys > 0 then
        add_keys(state, menu, op.keys, changes)
    end
end

function OPS.setKeyText(state, op, changes)
    local key, menu_id = find_key(state, op)
    if key then
        key.text = op.textValue
        changes:menu(menu_id)
    end
end

function OPS.setKeyEnabled(state, op, changes)
    local key, menu_id = find_key(state, op)
    if key then
        key.enabled = default(op.flag, true)
        changes:menu(menu_id)
    end
end

function OPS.setKeyGate(state, op, changes)
    local key, menu_id = find_key(state, op)
    if key then
        key.gate = op.gate
        changes:menu(menu_id)
    end
end

function OPS.mergeTranslations(state, op, changes)
    if not State.is_text(op.language) or type(op.entries) ~= 'table' then
        return
    end
    local code = op.language:match('^%s*(.-)%s*$'):lower()
    local table_for = state.translations[code] or {}
    state.translations[code] = table_for
    for key, text in pairs(op.entries) do
        table_for[key] = text
    end
    changes.everything = true
end

local function apply_one(state, op, changes)
    local present = PRESENT[op.op]
    if present then
        local node = find_item(state, op)
        if node then
            present(node, op)
            changes:item(node)
            changes.gates_changed = changes.gates_changed or op.op == 'setGate'
        end
        return
    end
    local apply = OPS[op.op]
    if apply then
        apply(state, op, changes)
        return
    end
    Log.warning(("[Plugins] '%s' sent unknown update op '%s', skipping it."):format(state.resource, tostring(op.op)))
end

function UpdateOps.apply(state, batch)
    local changes = new_changes(state)
    local ok, err = pcall(function()
        for _, op in ipairs(type(batch.ops) == 'table' and batch.ops or {}) do
            if type(op) == 'table' then
                apply_one(state, op, changes)
            end
        end
    end)
    local settled, settle_err = pcall(changes.settle, changes)
    changes:send_replies()
    if not ok then
        error(err, 0)
    end
    if not settled then
        error(settle_err, 0)
    end
end

return UpdateOps
