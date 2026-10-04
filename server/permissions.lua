-- Ports of vMenu.Enhanced.Permissions.Server/ServerPermissions.cs,
-- PermissionsSync.cs and PermissionsExampleFile.cs: permission checks with
-- inheritance, the grant list sent to each client, the refresh command and
-- event, and the generated permissions.cfg.example.

local Log = require('shared.log')
local Platform = require('shared.platform')
local PermissionPath = require('shared.permission_path')
local PermissionsExample = require('shared.data.permissions_example')
local Registry = require('server.permission_registry')
local Catalogs = require('server.catalogs')

local Permissions = {}

local EVENT_REQUEST = 'vMenu.Enhanced:Permissions:Request'
local EVENT_SET = 'vMenu.Enhanced:Permissions:Set'
local EVENT_REFRESH = 'vMenu.Enhanced:Permissions:Refresh'
local REFRESH_COMMAND = 'vmenu_refresh_permissions'
local STAFF = 'vMenu.Enhanced.Staff'
local STAFF_STATE_KEY = 'vMenu:staff'
local PLUGINS_PREFIX = 'vMenu.Enhanced.Plugins'

local ready = false
local synced_at = {} -- server id -> game timer of the last send

function Permissions.is_ready()
    return ready
end

-- Call once, first, from the server entrypoint.
function Permissions.init()
    ready = false
    Registry.build()
    Catalogs.load()
    ready = true
end

local function any_granted(source, permission, probed)
    for _, ace in ipairs(Registry.ancestor_chain(permission)) do
        local allowed = probed and probed[ace]
        if allowed == nil then
            allowed = IsPlayerAceAllowed(source, ace)
            if probed then
                probed[ace] = allowed
            end
        end
        if allowed then
            return true
        end
    end
    return false
end

-- Inheritance is applied here, so callers never name a parent themselves.
-- Nothing is cached, so an add_ace takes effect on the next call.
function Permissions.is_allowed(source, permission)
    source = tostring(source)
    if source == '' or not DoesPlayerExist(source) then
        return false
    end
    return any_granted(source, permission)
end

-- For deferrals, where DoesPlayerExist is not true yet.
function Permissions.is_connecting_player_allowed(source, permission)
    source = tostring(source)
    return source ~= '' and any_granted(source, permission)
end

-- The smallest set describing what a player may do. The walk stops at the
-- first granted node, because a granted parent grants everything under it,
-- which is also why the client can rebuild every answer from names alone.
function Permissions.granted(source)
    source = tostring(source)
    if source == '' or not DoesPlayerExist(source) then
        return {}
    end
    local probed = {}
    if any_granted(source, PermissionPath.EVERYTHING, probed) then
        return { PermissionPath.EVERYTHING }
    end
    local granted = {}
    local function collect(node)
        if any_granted(source, node.name, probed) then
            granted[#granted + 1] = node.name
            return
        end
        for _, child in ipairs(node.children) do
            collect(child)
        end
    end
    for _, root in ipairs(Registry.roots()) do
        collect(root)
    end
    return granted
end

function Permissions.synced_within(server_id, milliseconds)
    local at = synced_at[tonumber(server_id)]
    return at == nil or GetGameTimer() - at < milliseconds
end

function Permissions.send(server_id, latent_bytes_per_second)
    server_id = tonumber(server_id)
    local source = tostring(server_id)
    if not ready then
        Log.error(('[Permissions] Refusing to send permissions to %s: the registry is not ready yet.'):format(source))
        return
    end

    local granted = Permissions.granted(source)
    Player(server_id).state:set(STAFF_STATE_KEY, Permissions.is_allowed(source, STAFF), true)

    local categorised, category_names = Catalogs.categorised_vehicles()
    local args = {
        granted,
        Catalogs.whitelisted_models('vehicle'),
        categorised,
        category_names,
        Catalogs.whitelisted_models('ped'),
        Catalogs.whitelisted_models('weapon'),
    }
    if latent_bytes_per_second and latent_bytes_per_second > 0 then
        TriggerLatentClientEvent(EVENT_SET, server_id, latent_bytes_per_second, table.unpack(args))
    else
        TriggerClientEvent(EVENT_SET, server_id, table.unpack(args))
    end
    synced_at[server_id] = GetGameTimer()

    Log.debug(
        ('[Permissions] Sent %d permission(s) to %s: %s'):format(
            #granted,
            GetPlayerName(source),
            table.concat(granted, ', ')
        )
    )
end

function Permissions.refresh_all()
    if not ready then
        Log.error('[Permissions] Cannot refresh permissions: the registry is not ready yet.')
        return -1
    end
    local refreshed = 0
    for _, handle in ipairs(GetPlayers()) do
        Permissions.send(handle)
        refreshed = refreshed + 1
    end
    Log.info(('[Permissions] Refreshed permissions for %d player(s).'):format(refreshed))
    return refreshed
end

function Permissions.refresh_one(server_id)
    if not ready then
        Log.error('[Permissions] Cannot refresh permissions: the registry is not ready yet.')
        return false
    end
    server_id = math.tointeger(tonumber(server_id))
    if not server_id or server_id <= 0 or not DoesPlayerExist(tostring(server_id)) then
        return false
    end
    Permissions.send(server_id)
    Log.info(
        ('[Permissions] Refreshed permissions for %s (#%d).'):format(GetPlayerName(tostring(server_id)), server_id)
    )
    return true
end

-- Plugin permissions get templates of their own, so they are left out here.
-- The container above them stays: it grants every plugin at once.
local function belongs_to_a_plugin(permission)
    local lower = permission:lower()
    return lower:sub(1, #PLUGINS_PREFIX + 1) == (PLUGINS_PREFIX .. '.'):lower()
        and lower ~= (PLUGINS_PREFIX .. '.All'):lower()
end

local function to_entry(item)
    return {
        name = item.node.name,
        depth = item.depth,
        source = item.node.source,
        staff_only = item.node.staff_only,
        extra_parents = item.node.extra_parents,
    }
end

function Permissions.render_example()
    local entries = {}
    for _, item in ipairs(Registry.tree()) do
        if not belongs_to_a_plugin(item.node.name) then
            entries[#entries + 1] = to_entry(item)
        end
    end
    return PermissionsExample.render(entries)
end

-- One plugin's own permissions, depth counted from its container.
function Permissions.render_plugin_example(resource, display_name, plugin_all)
    local entries = {}
    for _, item in ipairs(Registry.subtree(plugin_all)) do
        entries[#entries + 1] = to_entry(item)
    end
    return PermissionsExample.render_for_plugin(resource, display_name, entries)
end

function Permissions.write_example()
    if Platform.save_file(PermissionsExample.RESOURCE_PATH, Permissions.render_example()) then
        Log.debug(
            ('[Permissions] Wrote %s, describing %d permission(s).'):format(
                PermissionsExample.RESOURCE_PATH,
                Registry.count()
            )
        )
    end
end

-- Call after init.
function Permissions.register_events()
    RegisterNetEvent(EVENT_REQUEST, function()
        Permissions.send(source)
    end)

    -- Local only: plugins call this through the server API to refresh after
    -- changing who holds their permissions. No ids refreshes everybody.
    AddEventHandler(EVENT_REFRESH, function(server_ids)
        if type(server_ids) ~= 'table' or #server_ids == 0 then
            Permissions.refresh_all()
            return
        end
        for _, server_id in ipairs(server_ids) do
            Permissions.refresh_one(server_id)
        end
    end)

    AddEventHandler('playerDropped', function()
        local dropped = tonumber(source)
        if dropped and dropped > 0 then
            synced_at[dropped] = nil
        end
    end)

    RegisterCommand(REFRESH_COMMAND, function(_, args)
        if #args == 0 then
            Permissions.refresh_all()
            return
        end
        local server_id = args[1]:match('^[+-]?%d+$') and math.tointeger(tonumber(args[1]))
        if not server_id then
            Log.error(
                ("[Permissions] '%s' is not a server id. Use %s on its own to refresh everybody."):format(
                    args[1],
                    REFRESH_COMMAND
                )
            )
        elseif not Permissions.refresh_one(server_id) then
            Log.error(('[Permissions] Nobody on this server has id %d.'):format(server_id))
        end
    end, true)
end

return Permissions
