-- Ports of vMenu.Enhanced.Menus/Vehicles/VehicleRepair.cs, VehicleWash.cs,
-- VehicleSeatCycle.cs and the server half of VehicleDeletion.cs: the one-shot
-- things Vehicle Options does to the vehicle the player sits in.

local Localization = require('shared.localization')
local Notifications = require('client.framework.notifications')
local Actions = require('client.actions')
local Spawning = require('client.menus.vehicles.spawning')
local Targeting = require('client.menus.vehicles.targeting')

local VehicleActions = {}

local DRIVER_SEAT = -1
local SECOND_PASS_DELAY_MS = 100

local function fix(vehicle)
    if DoesEntityExist(vehicle) and IsEntityAVehicle(vehicle) then
        SetVehicleFixed(vehicle)
        SetVehicleDeformationFixed(vehicle)
        SetVehicleUndriveable(vehicle, false)
    end
end

-- Twice: the game sometimes undoes part of the first pass. Waits.
function VehicleActions.repair(vehicle)
    fix(vehicle)
    Wait(SECOND_PASS_DELAY_MS)
    fix(vehicle)
end

function VehicleActions.repair_current()
    local vehicle = Targeting.require_driven(
        Localization.key('vehicleoptions.repair.novehicle'),
        Localization.key('vehicleoptions.repair.notdriver')
    )
    if vehicle then
        VehicleActions.repair(vehicle)
        Notifications.success(Localization.key('vehicleoptions.repair.success'))
    end
end

function VehicleActions.wash_current()
    local vehicle = Targeting.require_driven(
        Localization.key('vehicleoptions.wash.novehicle'),
        Localization.key('vehicleoptions.wash.notdriver')
    )
    if vehicle then
        SetVehicleDirtLevel(vehicle, 0.0)
        RemoveDecalsFromVehicle(vehicle)
        Notifications.success(Localization.key('vehicleoptions.wash.success'))
    end
end

-- Seats -----------------------------------------------------------------------------

local function seated()
    local ped = PlayerPedId()
    if ped == 0 or IsPedDeadOrDying(ped, true) then
        return nil
    end
    local vehicle = Targeting.current()
    return vehicle and ped, vehicle
end

function VehicleActions.can_cycle_seat()
    return seated() ~= nil
end

function VehicleActions.cycle_seat()
    local ped, vehicle = seated()
    if not ped then
        Notifications.error(Localization.key('vehicleoptions.cycleseat.novehicle'))
        return
    end
    local seats = GetVehicleModelNumberOfSeats(GetEntityModel(vehicle))
    local order = { DRIVER_SEAT }
    for seat = 0, seats - 2 do
        order[#order + 1] = seat
    end
    local from = 1
    for index, seat in ipairs(order) do
        if GetPedInVehicleSeat(vehicle, seat) == ped then
            from = index
            break
        end
    end
    for step = 1, #order - 1 do
        local seat = order[(from - 1 + step) % #order + 1]
        if IsVehicleSeatFree(vehicle, seat) then
            SetPedIntoVehicle(ped, vehicle, seat)
            return
        end
    end
    Notifications.error(Localization.key('vehicleoptions.cycleseat.nofreeseat'))
end

-- Deleting ---------------------------------------------------------------------------

local deleting = false

local function failure_key(status)
    if status == Actions.DENIED then
        return 'vehicleoptions.delete.denied'
    elseif status == Actions.TOO_FAR then
        return 'vehicleoptions.delete.toofar'
    elseif status == Actions.REFUSED then
        return 'vehicleoptions.delete.notdriver'
    end
    return 'vehicleoptions.delete.failed'
end

local function send_delete(action, vehicle)
    if not NetworkGetEntityIsNetworked(vehicle) then
        return Spawning.delete_locally(vehicle) and Actions.OK or Actions.FAILED
    end
    return (Actions.invoke(action, tostring(NetworkGetNetworkIdFromEntity(vehicle))))
end

-- Upstream's staff delete also reaches a vehicle in front of the player; it
-- comes with the Admin menu.
local function run_delete()
    local ped = PlayerPedId()
    if ped == 0 or IsPedDeadOrDying(ped, true) then
        return
    end
    local vehicle, kind = Targeting.current()
    if kind == Targeting.PASSENGER then
        Notifications.error(Localization.key('vehicleoptions.delete.notdriver'))
        return
    end
    if not vehicle then
        Notifications.error(Localization.key('vehicleoptions.delete.notdriving'))
        return
    end
    local status = send_delete('VehicleOptions.DeleteVehicle', vehicle)
    if status == Actions.OK then
        Notifications.success(Localization.key('vehicleoptions.delete.success'))
        return
    end
    Notifications.error(Localization.key(failure_key(status)))
end

-- Waits, so call it from a thread.
function VehicleActions.delete_driven()
    if deleting then
        return
    end
    deleting = true
    local ok, err = pcall(run_delete)
    deleting = false
    if not ok then
        error(err, 0)
    end
end

return VehicleActions
