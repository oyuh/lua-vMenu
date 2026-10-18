-- Port of vMenu.Enhanced.Menus/Vehicles/VehicleGodMode.cs: protection for the
-- vehicle the player drives, with each part (invincible, engine, looks,
-- wheels, tyres, ramps, auto repair) switchable on its own. Also keeps the
-- player in it, through the same ped protection claims as Player Options.

local Config = require('shared.config')
local Permissions = require('client.permissions')
local UserDefaults = require('client.user_defaults')
local VehicleEvents = require('client.events.vehicle_events')
local Protection = require('client.menus.players.protection')
local Targeting = require('client.menus.vehicles.targeting')
local VehicleActions = require('client.menus.vehicles.actions')
local NoClip = require('client.noclip')

local GodMode = {}

local PERMISSION = 'vMenu.Enhanced.Menus.VehicleOptions.God'
local FULL_ENGINE_HEALTH = 1000.0
local PROTECTIONS = Protection.NOT_DRAGGED_OUT | Protection.NOT_SHOT_IN_VEHICLE | Protection.NOT_KNOCKED_OFF_BIKE

local claim = Protection.claim()
local written = 0
local tyres = { vehicle = 0, could_burst = true }
local unsubscribers

local function preference(name)
    return UserDefaults.get(name) == true
end

function GodMode.enabled()
    return preference('vehicleGodMode') and Permissions.is_allowed(PERMISSION)
end

-- The parts, as { preference, text key }, in menu order.
GodMode.PARTS = {
    { 'vehicleGodInvincible', 'invincible' },
    { 'vehicleGodEngine', 'engine' },
    { 'vehicleGodVisual', 'visual' },
    { 'vehicleGodStrongWheels', 'strongwheels' },
    { 'vehicleGodBulletproofTyres', 'bulletprooftyres' },
    { 'vehicleGodRamp', 'ramp' },
    { 'vehicleGodAutoRepair', 'autorepair' },
}

local function write_tyres(vehicle, bulletproof)
    if bulletproof then
        if tyres.vehicle ~= vehicle then
            tyres.vehicle, tyres.could_burst = vehicle, GetVehicleTyresCanBurst(vehicle)
        end
        SetVehicleTyresCanBurst(vehicle, false)
        return
    end
    if tyres.vehicle == vehicle then
        tyres.vehicle = 0
        SetVehicleTyresCanBurst(vehicle, tyres.could_burst)
    end
end

local function write(vehicle, on)
    if not DoesEntityExist(vehicle) or not IsEntityAVehicle(vehicle) then
        if tyres.vehicle == vehicle then
            tyres.vehicle = 0
        end
        return
    end
    local invincible = on and preference('vehicleGodInvincible')
    local engine = on and preference('vehicleGodEngine')
    local visual = on and preference('vehicleGodVisual')
    local wheels = on and preference('vehicleGodStrongWheels')
    local ramp = on and preference('vehicleGodRamp')
    SetEntityInvincible(vehicle, invincible, false)
    SetEntityProofs(vehicle, invincible, invincible, invincible, invincible, invincible, invincible, false, invincible)
    for door = 0, GetNumberOfVehicleDoors(vehicle) - 1 do
        SetVehicleDoorCanBreak(vehicle, door, not invincible)
    end
    SetVehicleEngineCanDegrade(vehicle, not engine)
    SetVehicleCanBeVisiblyDamaged(vehicle, not visual)
    SetVehicleWheelsCanBreak(vehicle, not wheels)
    SetVehicleHasStrongAxles(vehicle, wheels)
    SetRampVehicleReceivesRampDamage(vehicle, not ramp)
    write_tyres(vehicle, on and preference('vehicleGodBulletproofTyres'))
    if not on then
        return
    end
    if engine and GetVehicleEngineHealth(vehicle) < FULL_ENGINE_HEALTH then
        SetVehicleEngineHealth(vehicle, FULL_ENGINE_HEALTH)
    end
    if visual and IsVehicleDamaged(vehicle) then
        RemoveDecalsFromVehicle(vehicle)
    end
end

local function repair_if_wanted(vehicle)
    if preference('vehicleGodAutoRepair') and DoesEntityExist(vehicle) and IsVehicleDamaged(vehicle) then
        CreateThread(function()
            VehicleActions.repair(vehicle)
        end)
    end
end

local apply

local function on_damaged(event)
    if GodMode.enabled() and event.vehicle == written then
        write(event.vehicle, true)
        repair_if_wanted(event.vehicle)
    end
end

local function watch(on)
    if on and not unsubscribers then
        unsubscribers = {
            VehicleEvents.on('changed', function()
                apply()
            end),
            VehicleEvents.on('damaged', on_damaged),
        }
    elseif not on and unsubscribers then
        for _, unsubscribe in ipairs(unsubscribers) do
            unsubscribe()
        end
        unsubscribers = nil
    end
end

apply = function()
    local on = GodMode.enabled()
    claim:set(on, PROTECTIONS)
    watch(on)
    if tyres.vehicle ~= 0 and not DoesEntityExist(tyres.vehicle) then
        tyres.vehicle = 0
    end
    local vehicle = Targeting.driven()
    if written ~= 0 and written ~= vehicle and Config.value('vMenu.Enhanced.VehicleOptions.ClearGodModeOnExit') then
        write(written, false)
    end
    written = 0
    if vehicle == 0 then
        return
    end
    write(vehicle, on)
    if on then
        written = vehicle
        repair_if_wanted(vehicle)
    end
end

local function set(name, value)
    UserDefaults.set(name, value)
    apply()
end

function GodMode.set_enabled(on)
    if on and not Permissions.is_allowed(PERMISSION) then
        return
    end
    set('vehicleGodMode', on)
end

function GodMode.part(name)
    return preference(name)
end

function GodMode.set_part(name, on)
    set(name, on)
end

-- After something else (noclip) reset the vehicle's flags.
function GodMode.reapply()
    written = 0
    tyres.vehicle = 0
    apply()
end

function GodMode.init()
    Permissions.on_changed(apply)
    NoClip.on_released(GodMode.reapply)
    apply()
end

return GodMode
