-- Ports of vMenu.Enhanced.Plugins.Server (PluginRegistry.cs,
-- PluginSettingFactory.cs, PluginTemplates.cs): the server half of upstream's
-- plugin protocol. A plugin is another resource; its server half declares
-- permissions (vMenu.Enhanced.Plugins.<Id>.<Name>), convar settings and the
-- rows it may log, over local events carrying JSON. The sender is always
-- GetInvokingResource(), which a payload cannot spoof.

local Log = require('shared.log')
local Json = require('shared.json_compat')
local Config = require('shared.config')
local Platform = require('shared.platform')
local PermissionPath = require('shared.permission_path')
local ConfigurationExample = require('shared.data.configuration_example')
local PermissionsExample = require('shared.data.permissions_example')
local Registry = require('server.permission_registry')
local Permissions = require('server.permissions')

local Plugins = {}

local SERVER_PROTOCOL_VERSION = 1
local PREFIX = 'vMenu.Enhanced:Plugins'
local EVENT_PROBE = PREFIX .. ':Server:Probe'
local EVENT_REGISTER = PREFIX .. ':Server:Register'
local EVENT_DENIED = PREFIX .. ':Server:Denied'
local EVENT_READY = PREFIX .. ':Server:Ready'
local PERMISSION_PREFIX = 'vMenu.Enhanced.Plugins'
local REFRESH_DEBOUNCE_MS = 500
local MAX_LOGGED_ITEMS = 100
local MAX_LOGGED_DESCRIPTION = 96

local registered = {} -- lowercased resource -> plugin
local id_owners = {} -- lowercased id -> resource
local last_accepted = {} -- lowercased resource -> payload, so a repeat costs nothing
local refresh_pending = false

local BAD_NAME = "%s '%s' was skipped: names may only contain letters, digits and underscores."

local function trim(text)
    return (tostring(text or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

local function ready_for(resource)
    return ('%s:%s:Server:Ready'):format(PREFIX, resource)
end

local function result_for(resource)
    return ('%s:%s:Server:RegisterResult'):format(PREFIX, resource)
end

local function all_for(id)
    return PERMISSION_PREFIX .. '.' .. id .. '.All'
end

local function permission_for(id, name)
    return PERMISSION_PREFIX .. '.' .. id .. '.' .. name
end

local function reply(resource, accepted, errors, warnings)
    TriggerEvent(
        result_for(resource),
        ('{"accepted":%s,"protocolVersion":%d,"errors":%s,"warnings":%s}'):format(
            accepted and 'true' or 'false',
            SERVER_PROTOCOL_VERSION,
            Json.string_array(errors),
            Json.string_array(warnings)
        )
    )
end

local function sender()
    local resource = GetInvokingResource()
    if resource == nil or resource == '' or resource == GetCurrentResourceName() then
        Log.warning('[Plugins] Ignored a plugin event without an invoking resource.')
        return nil
    end
    return resource
end

-- One permission resend for a whole burst of startup registrations.
local function schedule_refresh()
    if refresh_pending then
        return
    end
    refresh_pending = true
    SetTimeout(REFRESH_DEBOUNCE_MS, function()
        refresh_pending = false
        Permissions.refresh_all()
    end)
end

local function register_permissions(resource, id, declarations, warnings)
    local names = {}
    -- Dropped first, even when nothing is declared now: a plugin that renamed
    -- or removed a permission gets exactly what it declares this time.
    Registry.unregister_dynamic(all_for(id))
    if type(declarations) ~= 'table' or #declarations == 0 then
        return names
    end
    local source = 'plugin ' .. resource
    if not Registry.register_dynamic(all_for(id), source) then
        warnings[#warnings + 1] =
            "The plugin's own container grant could not be registered, so none of its permissions were."
        return names
    end
    for _, declaration in ipairs(declarations) do
        local name = tostring(Json.field(declaration, 'name') or '')
        if not PermissionPath.is_valid_segment(name) then
            warnings[#warnings + 1] = BAD_NAME:format('Permission', name)
        else
            local permission = permission_for(id, name)
            if Registry.register_dynamic(permission, source, Json.field(declaration, 'staffOnly') == true) then
                names[#names + 1] = permission
            else
                warnings[#warnings + 1] = ("Permission '%s' was refused by the permission registry."):format(name)
            end
        end
    end
    return names
end

-- PluginSettingFactory.Create: a declared setting as a catalog-style record.
local function create_setting(node, full_name)
    local name = tostring(Json.field(node, 'name') or '')
    local kind = tostring(Json.field(node, 'type') or 'bool')
    local default = tostring(Json.field(node, 'default') or '')
    local description = trim(Json.field(node, 'description'))
    if description == '' then
        description = 'No description was provided by the plugin.'
    end
    local function bad(expected)
        return nil, ("Setting '%s' has default '%s' where %s was expected."):format(name, default, expected)
    end
    local value
    if kind == 'bool' then
        if default:lower() == 'true' then
            value = true
        elseif default:lower() == 'false' or default == '' then
            value = false
        else
            return bad('true or false')
        end
    elseif kind == 'int' then
        value = Config.parse_int(default)
        if value == nil then
            return bad('a whole number')
        end
    elseif kind == 'float' then
        value = Config.parse_float(default)
        if value == nil then
            return bad('a number')
        end
    elseif kind == 'string' then
        value = default
    else
        return nil, ("Setting '%s' has unknown type '%s'."):format(name, kind)
    end
    return { name = full_name, type = kind, default = value, description = description }
end

local function build_settings(id, nodes, warnings)
    local settings = {}
    if type(nodes) ~= 'table' then
        return settings
    end
    local taken = {}
    for _, node in ipairs(nodes) do
        local name = tostring(Json.field(node, 'name') or '')
        if not Config.is_valid_segment(name) then
            warnings[#warnings + 1] = BAD_NAME:format('Setting', name)
        elseif taken[name:lower()] then
            warnings[#warnings + 1] = ("Setting '%s' was declared twice, the second one was skipped."):format(name)
        else
            taken[name:lower()] = true
            local setting, problem = create_setting(node, permission_for(id, name))
            if setting then
                settings[#settings + 1] = setting
            else
                warnings[#warnings + 1] = problem
            end
        end
    end
    return settings
end

-- vMenu's own list of what a plugin may log. A client saying a row is
-- loggable is not enough, or a modified client would pick what gets logged.
local function build_logged_items(declarations, warnings)
    local items, count = {}, 0
    if type(declarations) ~= 'table' then
        return items
    end
    for _, declaration in ipairs(declarations) do
        local item_id = trim(Json.field(declaration, 'itemId'))
        local description = trim(Json.field(declaration, 'description'))
        if item_id == '' then
            warnings[#warnings + 1] = 'A logged item without an id was skipped.'
        elseif count >= MAX_LOGGED_ITEMS then
            warnings[#warnings + 1] = ("Logged item '%s' was skipped: a plugin may declare %d of them."):format(
                item_id,
                MAX_LOGGED_ITEMS
            )
        elseif description == '' then
            warnings[#warnings + 1] = ("Logged item '%s' was skipped: it needs a description to log."):format(item_id)
        elseif items[item_id] then
            warnings[#warnings + 1] = ("Logged item '%s' was declared twice, the second one was skipped."):format(
                item_id
            )
        else
            if utf8.len(description) and utf8.len(description) > MAX_LOGGED_DESCRIPTION then
                description = description:sub(1, utf8.offset(description, MAX_LOGGED_DESCRIPTION + 1) - 1)
            end
            items[item_id] = description
            count = count + 1
        end
    end
    return items
end

-- PluginTemplates.Write: rewritten on every registration, even when empty,
-- so an owner never reads a template the running plugin no longer matches.
local function write_templates(plugin)
    local paths = {
        {
            PermissionsExample.plugin_resource_path(plugin.resource),
            Permissions.render_plugin_example(plugin.resource, plugin.display_name, all_for(plugin.id)),
        },
        {
            ConfigurationExample.plugin_resource_path(plugin.resource),
            ConfigurationExample.render_for_plugin(plugin.resource, plugin.display_name, plugin.settings),
        },
    }
    for _, entry in ipairs(paths) do
        if Platform.save_file(entry[1], entry[2]) then
            Log.debug('[Plugins] Wrote ' .. entry[1] .. '.')
        end
    end
end

local function register(resource, payload)
    local key = resource:lower()
    if last_accepted[key] == payload then
        reply(resource, true, {}, {})
        return
    end
    local request = Json.decode(payload)
    if type(request) ~= 'table' then
        reply(resource, false, { 'The registration payload did not parse.' }, {})
        return
    end
    local version = tonumber(Json.field(request, 'protocolVersion')) or 0
    if version > SERVER_PROTOCOL_VERSION then
        reply(resource, false, {
            (
                'The plugin speaks protocol %d but this vMenu only knows %d. '
                .. 'Update vMenu or use an older plugin API package.'
            ):format(version, SERVER_PROTOCOL_VERSION),
        }, {})
        return
    end
    local id = PermissionPath.plugin_id(resource)
    if not PermissionPath.is_valid_segment(id) then
        reply(
            resource,
            false,
            { ("The resource name '%s' cannot be turned into a usable identity."):format(resource) },
            {}
        )
        return
    end
    local owner = id_owners[id:lower()]
    if owner and owner:lower() ~= key then
        reply(resource, false, {
            ("The identity '%s' is already taken by resource '%s'. Rename one of the two resources."):format(id, owner),
        }, {})
        return
    end

    local warnings = {}
    local display_name = trim(Json.field(request, 'displayName'))
    if display_name == '' then
        display_name = resource
    end
    local plugin = {
        resource = resource,
        id = id,
        display_name = display_name,
        permissions = register_permissions(resource, id, Json.field(request, 'permissions'), warnings),
        settings = build_settings(id, Json.field(request, 'settings'), warnings),
        logged_items = build_logged_items(Json.field(request, 'loggedItems'), warnings),
    }
    local first = registered[key] == nil
    id_owners[id:lower()] = resource
    registered[key] = plugin
    last_accepted[key] = payload
    write_templates(plugin)
    schedule_refresh()

    local logged = 0
    for _ in pairs(plugin.logged_items) do
        logged = logged + 1
    end
    local summary = ("'%s' from resource '%s' with %d permission(s), %d setting(s) and %d logged item(s)."):format(
        display_name,
        resource,
        #plugin.permissions,
        #plugin.settings,
        logged
    )
    if first then
        Log.info('[Plugins] Registered ' .. summary)
    else
        Log.debug('[Plugins] Re-registered ' .. summary)
    end
    reply(resource, true, {}, warnings)
end

-- Its templates stay on disk: no native deletes a file. Their first line says
-- they are only written while the plugin runs.
local function on_resource_stop(stopped)
    local key = stopped:lower()
    local plugin = registered[key]
    if not plugin then
        return
    end
    registered[key] = nil
    last_accepted[key] = nil
    id_owners[plugin.id:lower()] = nil
    local removed = Registry.unregister_dynamic(all_for(plugin.id))
    Log.info(("[Plugins] '%s' stopped, dropping its %d permission(s)."):format(stopped, removed))
    schedule_refresh()
end

-- A plugin reports a refusal only where a legitimate client could not have
-- asked while lacking the permission, so it is worth a line in the console.
local function on_denied(player_source, permission_name)
    local resource = sender()
    local plugin = resource and registered[resource:lower()]
    local server_id = math.tointeger(tonumber(player_source))
    if not plugin or not server_id or server_id <= 0 then
        return
    end
    local permission = permission_for(plugin.id, tostring(permission_name))
    local declared = false
    for _, name in ipairs(plugin.permissions) do
        declared = declared or name:lower() == permission:lower()
    end
    if not declared then
        Log.warning(
            ("[Plugins] '%s' reported a refusal for '%s', which it never declared."):format(
                resource,
                tostring(permission_name)
            )
        )
        return
    end
    local message = "[Plugins] %s (#%d) was refused '%s' by plugin '%s', "
        .. 'which only offers it to people allowed to use it.'
    Log.warning(message:format(GetPlayerName(tostring(server_id)) or '?', server_id, permission, resource))
end

-- The item's log phrase, or nil when the plugin never declared it.
function Plugins.logged_item(resource, item_id)
    local plugin = registered[tostring(resource):lower()]
    return plugin and plugin.logged_items[item_id] or nil
end

function Plugins.register_events()
    AddEventHandler(EVENT_PROBE, function()
        local resource = sender()
        if resource then
            TriggerEvent(ready_for(resource), SERVER_PROTOCOL_VERSION)
        end
    end)
    AddEventHandler(EVENT_REGISTER, function(payload)
        local resource = sender()
        if not resource then
            return
        end
        local ok, err = pcall(register, resource, tostring(payload or ''))
        if not ok then
            Log.error(("[Plugins] Registration from '%s' failed: %s"):format(resource, tostring(err)))
            reply(resource, false, { 'vMenu hit an internal error: ' .. tostring(err) }, {})
        end
    end)
    AddEventHandler(EVENT_DENIED, on_denied)
    AddEventHandler('onResourceStop', on_resource_stop)
end

-- Call once startup is done, so plugins that started first register now.
function Plugins.announce_ready()
    TriggerEvent(EVENT_READY, SERVER_PROTOCOL_VERSION)
end

return Plugins
