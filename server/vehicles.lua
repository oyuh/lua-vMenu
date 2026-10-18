-- Ports of vMenu.Enhanced.Actions.Server/Handlers/VehicleSpawnActions.cs,
-- SpawnedVehicleRegistry.cs and VehicleOrphanMode.cs: remembers which player
-- spawned which vehicle, and tells the server what to do with it once its
-- owner leaves (vMenu.Enhanced.VehicleSpawner.OrphanMode).

local Log = require('shared.log')
local Config = require('shared.config')
local Platform = require('shared.platform')

local Vehicles = {}

local EVENT_SPAWNED = 'vMenu.Enhanced:Vehicles:Spawned'
local ORPHAN_SETTING = 'vMenu.Enhanced.VehicleSpawner.OrphanMode'
local DELETE_WHEN_NOT_RELEVANT = 0
local KNOWN_MODES = { [0] = true, [1] = true, [2] = true }
local MAX_REMEMBERED = 32
local DRAIN_MS = 250
local GIVE_UP_AFTER_MS = 2000
local MAX_WAITING = 64
local VEHICLE_ENTITY_TYPE = 2

local spawned = {} -- server id -> network ids, oldest first
local waiting = {} -- server id -> { { network_id, deadline } }
local reported = {}

local function report_once(key, message)
    if not reported[key] then
        reported[key] = true
        Log.warning(message)
    end
end

local function remember(player, network_id)
    local list = spawned[player] or {}
    spawned[player] = list
    for index = #list, 1, -1 do
        if list[index] == network_id then
            table.remove(list, index)
        end
    end
    list[#list + 1] = network_id
    while #list > MAX_REMEMBERED do
        table.remove(list, 1)
    end
end

function Vehicles.was_spawned_by(player, network_id)
    for _, id in ipairs(spawned[player] or {}) do
        if id == network_id then
            return true
        end
    end
    return false
end

local function configured_mode()
    local mode = Config.value(ORPHAN_SETTING)
    if not KNOWN_MODES[mode] then
        local default = Config.default_value(Config.setting(ORPHAN_SETTING))
        report_once(
            'mode',
            ('[Vehicles] %s is set to %s, which is not 0, 1 or 2. Using %s.'):format(
                ORPHAN_SETTING,
                tostring(mode),
                tostring(default)
            )
        )
        return default
    end
    return mode
end

local function queue(player, network_id)
    if configured_mode() == DELETE_WHEN_NOT_RELEVANT then
        return
    end
    if not Platform.has('SetEntityOrphanMode') then
        report_once('native', '[Vehicles] This server build has no SetEntityOrphanMode, so OrphanMode is ignored.')
        return
    end
    local list = waiting[player] or {}
    waiting[player] = list
    list[#list + 1] = { network_id = network_id, deadline = GetGameTimer() + GIVE_UP_AFTER_MS }
    while #list > MAX_WAITING do
        report_once(
            'full',
            ('[Vehicles] A player has more than %d vehicles waiting for an orphan mode at once. '):format(MAX_WAITING)
                .. 'Dropping their oldest ones.'
        )
        table.remove(list, 1)
    end
end

-- The vehicle reaches the server a moment after the client reports it.
local function drain()
    local mode = configured_mode()
    local now = GetGameTimer()
    for player, list in pairs(waiting) do
        for index = #list, 1, -1 do
            local pending = list[index]
            local entity = NetworkGetEntityFromNetworkId(pending.network_id)
            if entity ~= 0 and DoesEntityExist(entity) and GetEntityType(entity) == VEHICLE_ENTITY_TYPE then
                SetEntityOrphanMode(entity, mode)
                table.remove(list, index)
            elseif now >= pending.deadline then
                Log.debug(
                    ('[Vehicles] Network id %d never reached the server, so it keeps the default orphan mode.'):format(
                        pending.network_id
                    )
                )
                table.remove(list, index)
            end
        end
        if #list == 0 then
            waiting[player] = nil
        end
    end
end

function Vehicles.register_events()
    RegisterNetEvent(EVENT_SPAWNED, function(network_id)
        if math.type(network_id) ~= 'integer' or network_id == 0 then
            return
        end
        remember(source, network_id)
        queue(source, network_id)
    end)
    -- The orphan mode still goes on a vehicle whose owner left before it arrived.
    AddEventHandler('playerDropped', function()
        spawned[source] = nil
    end)
    CreateThread(function()
        while true do
            if next(waiting) then
                drain()
            end
            Wait(DRAIN_MS)
        end
    end)
end

return Vehicles
