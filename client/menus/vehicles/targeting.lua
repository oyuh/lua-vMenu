-- Ports of vMenu.Enhanced.Menus/Vehicles/VehicleTarget.cs, VehicleTargeting.cs
-- and OwnVehicle.cs: which vehicle the player means, and whether they drive it.

local Notifications = require('client.framework.notifications')

local Targeting = {}

-- Target kinds.
Targeting.DRIVING = 'driving'
Targeting.PASSENGER = 'passenger'
Targeting.IN_FRONT = 'inFront'

local DRIVER_SEAT = -1
local SEARCH_RADIUS = 1.25
local VEHICLES_ONLY = 2
local SHAPE_TEST_OPTIONS = 7
local SHAPE_TEST_NOT_READY = 1
local SHAPE_TEST_READY = 2
local MAX_RESULT_FRAMES = 10

local function alive_ped()
    local ped = PlayerPedId()
    if ped == 0 or not DoesEntityExist(ped) or IsPedDeadOrDying(ped, true) then
        return nil
    end
    return ped
end

-- The vehicle the player sits in and how, or nil.
function Targeting.current()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then
        return nil
    end
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return nil
    end
    local kind = GetPedInVehicleSeat(vehicle, DRIVER_SEAT) == ped and Targeting.DRIVING or Targeting.PASSENGER
    return vehicle, kind
end

local function find_in_front(ped, reach)
    local start = GetEntityCoords(ped, true)
    local finish = GetOffsetFromEntityInWorldCoords(ped, 0.0, reach, 0.0)
    local test = StartShapeTestCapsule(
        start.x,
        start.y,
        start.z,
        finish.x,
        finish.y,
        finish.z,
        SEARCH_RADIUS,
        VEHICLES_ONLY,
        ped,
        SHAPE_TEST_OPTIONS
    )
    for _ = 1, MAX_RESULT_FRAMES do
        local status, hit, _, _, entity = GetShapeTestResult(test)
        if status ~= SHAPE_TEST_NOT_READY then
            if status ~= SHAPE_TEST_READY or hit == 0 or hit == false then
                return nil
            end
            return (DoesEntityExist(entity) and IsEntityAVehicle(entity)) and entity or nil
        end
        Wait(0)
    end
    return nil
end

-- The vehicle the player sits in, else one up to reach metres ahead. Waits.
function Targeting.resolve(reach)
    local vehicle, kind = Targeting.current()
    if vehicle then
        return vehicle, kind
    end
    local ped = alive_ped()
    local found = ped and find_in_front(ped, reach)
    if found then
        return found, Targeting.IN_FRONT
    end
    return nil
end

-- The vehicle the player drives, or 0.
function Targeting.driven()
    if not alive_ped() then
        return 0
    end
    local vehicle, kind = Targeting.current()
    return (vehicle and kind == Targeting.DRIVING) and vehicle or 0
end

-- The driven vehicle, or nil after telling the player why there is none.
-- The two arguments are menu text, such as Localization.key(...).
function Targeting.require_driven(no_vehicle, not_driver)
    if not alive_ped() then
        return nil
    end
    local vehicle, kind = Targeting.current()
    if not vehicle then
        Notifications.error(no_vehicle)
        return nil
    end
    if kind == Targeting.PASSENGER then
        Notifications.error(not_driver)
        return nil
    end
    return vehicle
end

return Targeting
