-- Ports of the on-off vehicle features in vMenu.Enhanced.Menus/Vehicles that
-- keep running with the menu closed. Each is a saved preference behind a
-- permission, applied to the vehicle the player drives.

local Permissions = require('client.permissions')
local UserDefaults = require('client.user_defaults')
local Ticks = require('menu.ticks')
local VehicleEvents = require('client.events.vehicle_events')
local Targeting = require('client.menus.vehicles.targeting')

local Toggles = {}

local PERMISSION = 'vMenu.Enhanced.Menus.VehicleOptions.'

-- Keep clean (VehicleKeepClean.cs) -----------------------------------------------------

local SWEEP_MS = 10000
local keep_clean_unsubscribers

local function wash(vehicle)
    if vehicle ~= 0 and DoesEntityExist(vehicle) and GetVehicleDirtLevel(vehicle) > 0 then
        SetVehicleDirtLevel(vehicle, 0.0)
    end
end

local function wash_driven()
    wash(Targeting.driven())
end

function Toggles.keep_clean()
    return UserDefaults.get('vehicleKeepClean') == true and Permissions.is_allowed(PERMISSION .. 'KeepClean')
end

local function apply_keep_clean()
    local on = Toggles.keep_clean()
    if on and not keep_clean_unsubscribers then
        keep_clean_unsubscribers = {
            VehicleEvents.on('dirtied', wash_driven),
            VehicleEvents.on('changed', wash_driven),
        }
    elseif not on and keep_clean_unsubscribers then
        for _, unsubscribe in ipairs(keep_clean_unsubscribers) do
            unsubscribe()
        end
        keep_clean_unsubscribers = nil
    end
    Ticks.reevaluate()
    if on then
        wash_driven()
    end
end

function Toggles.set_keep_clean(on)
    if on and not Permissions.is_allowed(PERMISSION .. 'KeepClean') then
        return
    end
    UserDefaults.set('vehicleKeepClean', on)
    apply_keep_clean()
end

function Toggles.init()
    Ticks.register('Vehicle.KeepClean', wash_driven, { rate = SWEEP_MS, condition = Toggles.keep_clean })
    Permissions.on_changed(apply_keep_clean)
    apply_keep_clean()
end

return Toggles
