-- Ports of vMenu.Enhanced.Menus/Vehicles/VehicleSpawning.cs,
-- VehicleSpawnOptions.cs, VehicleSpawnLimit.cs, VehicleClassStats.cs,
-- VehicleModelNames.cs and the local half of VehicleDeletion.cs: putting a
-- vehicle in the world, and the rules around it.

local Config = require('shared.config')
local Localization = require('shared.localization')
local Ceilings = require('shared.data.vehicle_class_ceilings')
local Permissions = require('client.permissions')
local UserDefaults = require('client.user_defaults')
local Notifications = require('client.framework.notifications')
local Natives = require('client.natives')

local Spawning = {}

local DRIVER_SEAT = -1
local EVENT_SPAWNED = 'vMenu.Enhanced:Vehicles:Spawned'
local KEEP_PREVIOUS = 'vMenu.Enhanced.Menus.VehicleSpawner.AllowKeepPreviousVehicle'
local DELETE_WHEN_NOT_RELEVANT = 0
local KNOWN_ORPHAN_MODES = { [0] = true, [1] = true, [2] = true }
local DEFAULT_ORPHAN_MODE = 1

local previous_vehicle = 0

-- Options ----------------------------------------------------------------------------

function Spawning.spawn_inside()
    return UserDefaults.get('vehicleSpawnerSpawnInside') == true
end

function Spawning.set_spawn_inside(on)
    UserDefaults.set('vehicleSpawnerSpawnInside', on)
end

function Spawning.can_keep_previous()
    return Permissions.is_allowed(KEEP_PREVIOUS)
end

-- Without the permission to keep it, the previous vehicle always goes.
function Spawning.replace_previous()
    return UserDefaults.get('vehicleSpawnerReplacePrevious') == true or not Spawning.can_keep_previous()
end

function Spawning.set_replace_previous(on)
    if not on and not Spawning.can_keep_previous() then
        return
    end
    UserDefaults.set('vehicleSpawnerReplacePrevious', on)
end

-- Names and stats --------------------------------------------------------------------

-- Like .NET's ToTitleCase: an all-capitals word (BMX) is left alone.
local function title_case(text)
    return (
        text:gsub('%a[%w]*', function(word)
            if word == word:upper() then
                return word
            end
            return word:sub(1, 1):upper() .. word:sub(2):lower()
        end)
    )
end

function Spawning.display_name(hash)
    local display_name = GetDisplayNameFromVehicleModel(hash)
    local label = GetLabelText(display_name)
    return title_case(label == 'NULL' and display_name or label)
end

local model_names

-- The spawn name of a model hash, for logs and saves.
function Spawning.model_name(hash)
    if not model_names then
        model_names = {}
        for _, model in ipairs(GetAllVehicleModels() or {}) do
            local name = model:match('^%s*(.-)%s*$')
            if name ~= '' then
                model_names[GetHashKey(name)] = name
            end
        end
    end
    return model_names[hash] or GetDisplayNameFromVehicleModel(hash)
end

local function scale(value, ceiling)
    return ceiling == 0 and 0.0 or value / ceiling
end

-- The four stat bars of a model, scaled to the best of its class.
function Spawning.class_stats(hash, vehicle_class)
    local index = vehicle_class + 1
    if not Ceilings.top_speed[index] then
        return nil
    end
    return {
        scale(GetVehicleModelEstimatedMaxSpeed(hash), Ceilings.top_speed[index]),
        scale(GetVehicleModelAcceleration(hash), Ceilings.acceleration[index]),
        scale(GetVehicleModelMaxBraking(hash), Ceilings.braking[index]),
        scale(GetVehicleModelMaxTraction(hash), Ceilings.traction[index]),
    }
end

-- Spawn limit ------------------------------------------------------------------------

local stamps = {}

local function allowance()
    local tier = 'SpawnLimitTier1'
    if Permissions.is_allowed('vMenu.Enhanced.Menus.VehicleSpawner.SpawnLimitTier3') then
        tier = 'SpawnLimitTier3'
    elseif Permissions.is_allowed('vMenu.Enhanced.Menus.VehicleSpawner.SpawnLimitTier2') then
        tier = 'SpawnLimitTier2'
    end
    return Config.value('vMenu.Enhanced.VehicleSpawner.' .. tier)
end

-- Counts a spawn against the player's limit, or warns and returns false.
function Spawning.take_spawn()
    local limit = allowance()
    local window = Config.value('vMenu.Enhanced.VehicleSpawner.SpawnLimitSeconds') * 1000
    if limit <= 0 or window <= 0 then
        stamps = {}
        return true
    end
    local now = GetGameTimer()
    while #stamps > 0 and now - stamps[1] >= window do
        table.remove(stamps, 1)
    end
    if #stamps < limit then
        stamps[#stamps + 1] = now
        return true
    end
    local retry = math.max(1, math.ceil((window - (now - stamps[1])) / 1000))
    Notifications.warning(Localization.key('vehiclespawner.toomanyspawns', { seconds = tostring(retry) }))
    return false
end

-- Removing ---------------------------------------------------------------------------

-- True once the vehicle is gone.
function Spawning.delete_locally(vehicle)
    SetVehicleHasBeenOwnedByPlayer(vehicle, false)
    SetEntityAsMissionEntity(vehicle, true, true)
    DeleteVehicle(vehicle)
    return not DoesEntityExist(vehicle)
end

local function remove(vehicle, notify)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return
    end
    Spawning.delete_locally(vehicle)
    if notify then
        Notifications.info(Localization.key('vehiclespawner.oldvehicleremoved'))
    end
end

local function may_remove(vehicle, ped)
    if vehicle == 0 or not DoesEntityExist(vehicle) or not IsEntityAVehicle(vehicle) then
        return false
    end
    local driver = GetPedInVehicleSeat(vehicle, DRIVER_SEAT)
    return driver == 0 or driver == ped
end

local function will_remove_current(ped, current)
    if not Spawning.replace_previous() or current == 0 or not DoesEntityExist(current) then
        return false
    end
    return GetPedInVehicleSeat(current, DRIVER_SEAT) == ped
end

local function remove_previous(ped, current, removing_current)
    if may_remove(previous_vehicle, ped) then
        if Spawning.replace_previous() then
            remove(previous_vehicle, false)
        elseif not Config.value('vMenu.Enhanced.VehicleSpawner.KeepSpawnedVehiclesPersistent') then
            SetEntityAsNoLongerNeeded(previous_vehicle)
        end
        previous_vehicle = 0
    end
    if removing_current then
        if previous_vehicle == current then
            previous_vehicle = 0
        end
        remove(current, true)
    end
end

-- Spawning ---------------------------------------------------------------------------

local function length_of(hash)
    local minimum, maximum = GetModelDimensions(hash)
    return math.abs(minimum.y - maximum.y) / 2
end

local function spawn_position(ped, current, hash, inside, removing_current)
    if inside and current == 0 then
        return GetEntityCoords(ped, true)
    end
    local clearance = length_of(hash) + 1.0
    if current ~= 0 and removing_current then
        return GetEntityCoords(current, true)
    end
    if current == 0 then
        return GetOffsetFromEntityInWorldCoords(ped, 0.0, clearance + 2.0, 0.0)
    end
    clearance = clearance + length_of(GetEntityModel(current))
    return GetOffsetFromEntityInWorldCoords(current, 0.0, clearance, 0.0)
end

local function orphan_mode()
    local mode = Config.value('vMenu.Enhanced.VehicleSpawner.OrphanMode')
    return KNOWN_ORPHAN_MODES[mode] and mode or DEFAULT_ORPHAN_MODE
end

local function report_spawn(vehicle)
    if vehicle ~= 0 and NetworkGetEntityIsNetworked(vehicle) then
        TriggerServerEvent(EVENT_SPAWNED, NetworkGetNetworkIdFromEntity(vehicle))
    end
end

-- Spawns model next to (or under) the player. Waits, so call it from a
-- thread. The new vehicle, or nil.
function Spawning.spawn(model)
    local hash = type(model) == 'number' and model or GetHashKey(model)
    if not IsModelValid(hash) then
        return nil
    end
    RequestModel(hash)
    while not HasModelLoaded(hash) do
        Wait(0)
    end
    local ped = PlayerPedId()
    local inside = Spawning.spawn_inside()
    local current = IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false) or 0
    local velocity, speed, rpm
    if inside and current ~= 0 then
        velocity = GetEntityVelocity(current)
        speed = GetEntitySpeedVector(current, true).y
        rpm = GetVehicleCurrentRpm(current)
    end
    local removing_current = will_remove_current(ped, current)
    local position = spawn_position(ped, current, hash, inside, removing_current)
    local heading = GetEntityHeading(ped) + (inside and 0.0 or 90.0)
    remove_previous(ped, current, removing_current)

    local script_host = orphan_mode() ~= DELETE_WHEN_NOT_RELEVANT
    local vehicle = Natives.create_vehicle(hash, position.x, position.y, position.z, heading, true, script_host, true)
    SetModelAsNoLongerNeeded(hash)
    if vehicle == 0 then
        return nil
    end
    previous_vehicle = vehicle
    report_spawn(vehicle)
    if not inside then
        Natives.set_vehicle_on_ground_properly(vehicle, 5.0)
        return vehicle
    end
    SetVehicleEngineOn(vehicle, true, true, false)
    if IsThisModelAHeli(hash) or IsThisModelAPlane(hash) then
        SetHeliBladesSpeed(vehicle, 1.0)
    end
    SetVehicleForwardSpeed(vehicle, speed or 0.0)
    if velocity then
        SetEntityVelocity(vehicle, velocity.x, velocity.y, velocity.z)
    end
    if rpm and rpm > 0.2 then
        SetVehicleCurrentRpm(vehicle, rpm)
    end
    SetPedIntoVehicle(ped, vehicle, DRIVER_SEAT)
    return vehicle
end

-- The checks every spawn row makes, then the spawn and its notice. Waits.
function Spawning.spawn_checked(model, vehicle_class)
    if not Permissions.can_spawn_vehicle(model, vehicle_class) or not Spawning.take_spawn() then
        return nil
    end
    local vehicle = Spawning.spawn(model)
    if vehicle then
        Notifications.success(
            Localization.key('vehiclespawner.spawned', { vehicle = Spawning.display_name(GetHashKey(model)) }),
            Notifications.SPAWN_DURATION_MS
        )
    end
    return vehicle
end

return Spawning
