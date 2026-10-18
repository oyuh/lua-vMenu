-- Ports of vMenu.Enhanced.Plugins/PluginState.cs and PluginPlaceholders.cs:
-- what vMenu knows about one registered plugin. Nodes are the plugin's own
-- decoded JSON tables (camelCase, see client/plugins/host.lua), kept as they
-- are and changed in place by updates, so the menus read them live.

local Log = require('shared.log')
local Json = require('shared.json_compat')
local Config = require('shared.config')
local Localization = require('shared.localization')
local Permissions = require('client.permissions')

local State = {}
State.__index = State

State.PLAYER_ACTIONS_MENU_ID = 'playerActions'

local PREFIX = 'vMenu.Enhanced:Plugins'
local PERMISSION_PREFIX = 'vMenu.Enhanced.Plugins'

local function is_text(value)
    return type(value) == 'string' and value ~= ''
end

State.is_text = is_text

function State.new(resource, id)
    return setmetatable({
        resource = resource,
        id = id,
        event_name = ('%s:%s:Event'):format(PREFIX, resource),
        display_name = nil, -- TextRef
        description_ref = nil, -- TextRef
        translations = {}, -- lowercased language -> { key -> text }
        bool_settings = {}, -- lowercased name -> { convar, default }
        root_menu = nil,
        standalone = {}, -- { node, menu }
        player_actions = {},
        warned_placeholders = {},
        row = nil,
        -- Live indexes. Ids compare exactly, like upstream's StringComparer.Ordinal.
        items_by_id = {},
        item_count = 0,
        item_owners = {}, -- item id -> menu id
        player_action_ids = {},
        menus_by_id = {},
        keys_by_id = {},
        menu_depths = {},
        builders = {}, -- menu id -> host
        menu_ids = {}, -- MenuAPI menu -> menu id
        nodes_by_item = {}, -- MenuAPI item -> node
        entries_by_id = {},
        menu_filters = {}, -- menu id -> set of hidden item ids
        options_by_item_id = {}, -- item id -> the list entry's live options
    }, State)
end

function State:menu_id_of(menu)
    return self.menu_ids[menu]
end

function State:add_builder(menu_id, builder)
    self:remove_builder(menu_id)
    self.builders[menu_id] = builder
    self.menu_ids[builder.menu] = menu_id
end

function State:remove_builder(menu_id)
    local builder = self.builders[menu_id]
    if not builder then
        return nil
    end
    self.builders[menu_id] = nil
    self.menu_ids[builder.menu] = nil
    return builder
end

function State:forget_items_of(builder)
    for _, entry in ipairs(builder.entries) do
        if entry.item then
            self.nodes_by_item[entry.item] = nil
        end
    end
end

-- The builder filter: hidden by setVisible or by setFilter.
function State:is_visible(item)
    local node = self.nodes_by_item[item]
    if not node then
        return true
    end
    if node.visible == false then
        return false
    end
    local owner = self.item_owners[node.id]
    local hidden = owner and self.menu_filters[owner]
    return not (hidden and hidden[node.id])
end

function State:emit(callback)
    TriggerEvent(self.event_name, Json.encode(callback))
end

function State:reply_open(request_id, reason)
    TriggerEvent(
        ('%s:%s:OpenResult'):format(PREFIX, self.resource),
        Json.encode({ requestId = request_id, opened = reason == 'opened', reason = reason })
    )
end

-- Text -------------------------------------------------------------------------------

local function lookup(self, key)
    local current = self.translations[Localization.current_language()]
    if current and current[key] ~= nil then
        return tostring(current[key])
    end
    local english = self.translations.en
    if english and english[key] ~= nil then
        return tostring(english[key])
    end
    return '!!' .. key .. '!!'
end

local function argument(self, name, args)
    local wanted = name:lower()
    if type(args) == 'table' then
        for key, value in pairs(args) do
            if type(key) == 'string' and key:lower() == wanted then
                return self:resolve(value)
            end
        end
    end
    if not self.warned_placeholders[wanted] then
        self.warned_placeholders[wanted] = true
        Log.warning(
            ("[Plugins] '%s' used placeholder '{%s}' without supplying a value for it."):format(self.resource, name)
        )
    end
    return '!{' .. name .. '}!'
end

-- {name} takes an argument, {{ and }} are literal braces.
local function substitute(self, template, args)
    if not template:find('[{}]') then
        return template
    end
    local out = {}
    local index, length = 1, #template
    while index <= length do
        local c = template:sub(index, index)
        if c == '}' then
            if template:sub(index + 1, index + 1) == '}' then
                index = index + 1
            end
            out[#out + 1] = '}'
        elseif c ~= '{' then
            local stop = (template:find('[{}]', index) or length + 1) - 1
            out[#out + 1] = template:sub(index, stop)
            index = stop
        elseif template:sub(index + 1, index + 1) == '{' then
            out[#out + 1] = '{'
            index = index + 1
        else
            local close = template:find('}', index + 1, true)
            if not close then
                out[#out + 1] = template:sub(index)
                break
            end
            out[#out + 1] = argument(self, template:sub(index + 1, close - 1), args)
            index = close
        end
        index = index + 1
    end
    return table.concat(out)
end

-- A TextRef is { text } or { key, args }; a key reads the plugin's own tables.
function State:resolve(reference)
    if type(reference) ~= 'table' then
        return ''
    end
    if is_text(reference.key) then
        return substitute(self, lookup(self, reference.key), reference.args)
    end
    return reference.text ~= nil and tostring(reference.text) or ''
end

function State:display_name_text()
    local name = self.display_name and self:resolve(self.display_name)
    return is_text(name) and name or self.resource
end

-- Gates ------------------------------------------------------------------------------

local function setting_value(setting)
    local value = Config.parse_bool(Config.get(setting.convar))
    if value == nil then
        return setting.default
    end
    return value
end

function State:evaluate_gate(gate)
    if type(gate) ~= 'table' then
        return true
    end
    if is_text(gate.permission) then
        return Permissions.is_allowed(PERMISSION_PREFIX .. '.' .. self.id .. '.' .. gate.permission)
    end
    if is_text(gate.setting) then
        local setting = self.bool_settings[gate.setting:lower()]
        return setting ~= nil and setting_value(setting)
    end
    if type(gate.all) == 'table' and #gate.all > 0 then
        for _, child in ipairs(gate.all) do
            if not self:evaluate_gate(child) then
                return false
            end
        end
        return true
    end
    if type(gate.any) == 'table' and #gate.any > 0 then
        for _, child in ipairs(gate.any) do
            if self:evaluate_gate(child) then
                return true
            end
        end
        return false
    end
    -- A gate that names nothing fails closed.
    return false
end

return State
