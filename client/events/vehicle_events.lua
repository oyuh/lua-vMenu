-- Port of vMenu.Enhanced.Events/LocalVehicleTicks.cs: events about the vehicle
-- the local player sits in, found by polling. Each poll only runs while
-- something listens. Upstream's entered, exited, swapped and seat-changed
-- events join when a feature needs them; 'changed' covers all four.
--
-- VehicleEvents.on(name, handler) returns a function that unsubscribes.
--   'changed'  { vehicle, previous, seat, previous_seat } (nil when absent)
--   'damaged'  { vehicle, body, engine, tank, body_lost, engine_lost, tank_lost }
--   'dirtied'  { vehicle, dirt, gained }

local Log = require('shared.log')
local Ticks = require('menu.ticks')

local VehicleEvents = {}

local DRIVER_SEAT = -1
local NO_SEAT = -2
local SEAT_INTERVAL_MS = 250
local DAMAGE_INTERVAL_MS = 100
local DIRT_INTERVAL_MS = 500
local DAMAGE_THRESHOLD = 1.0
local DIRT_THRESHOLD = 0.01

local handlers = { changed = {}, damaged = {}, dirtied = {} }

local seat_state = { vehicle = 0, seat = NO_SEAT }
local damage_state = { vehicle = 0, body = 0.0, engine = 0.0, tank = 0.0 }
local dirt_state = { vehicle = 0, dirt = 0.0 }

local function raise(name, event)
    for _, handler in ipairs(handlers[name]) do
        local ok, err = pcall(handler, event)
        if not ok then
            Log.error(("[Events] A vehicle '%s' handler threw: %s"):format(name, tostring(err)))
        end
    end
end

local function find_seat(vehicle, ped)
    if GetPedInVehicleSeat(vehicle, DRIVER_SEAT) == ped then
        return DRIVER_SEAT
    end
    local seats = GetVehicleModelNumberOfSeats(GetEntityModel(vehicle))
    for seat = 0, seats - 2 do
        if GetPedInVehicleSeat(vehicle, seat) == ped then
            return seat
        end
    end
    return NO_SEAT
end

-- vehicle (0 for none), seat
local function read()
    local ped = PlayerPedId()
    if ped == 0 or not DoesEntityExist(ped) or not IsPedInAnyVehicle(ped, false) then
        return 0, NO_SEAT
    end
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return 0, NO_SEAT
    end
    return vehicle, find_seat(vehicle, ped)
end

local function absent(value, none)
    if value == (none or 0) then
        return nil
    end
    return value
end

local function poll_seat()
    local vehicle, seat = read()
    if vehicle == seat_state.vehicle and seat == seat_state.seat then
        return
    end
    local previous, previous_seat = seat_state.vehicle, seat_state.seat
    seat_state.vehicle, seat_state.seat = vehicle, seat
    raise('changed', {
        vehicle = absent(vehicle),
        previous = absent(previous),
        seat = absent(seat, NO_SEAT),
        previous_seat = absent(previous_seat, NO_SEAT),
    })
end

local function condition(vehicle)
    if vehicle == 0 then
        return 0.0, 0.0, 0.0
    end
    return GetVehicleBodyHealth(vehicle), GetVehicleEngineHealth(vehicle), GetVehiclePetrolTankHealth(vehicle)
end

local function poll_damage()
    local vehicle = read()
    local body, engine, tank = condition(vehicle)
    local state = damage_state
    if vehicle ~= state.vehicle then
        state.vehicle, state.body, state.engine, state.tank = vehicle, body, engine, tank
        return
    end
    local body_lost, engine_lost, tank_lost = state.body - body, state.engine - engine, state.tank - tank
    state.body, state.engine, state.tank = body, engine, tank
    if
        vehicle == 0
        or (body_lost < DAMAGE_THRESHOLD and engine_lost < DAMAGE_THRESHOLD and tank_lost < DAMAGE_THRESHOLD)
    then
        return
    end
    raise('damaged', {
        vehicle = vehicle,
        body = body,
        engine = engine,
        tank = tank,
        body_lost = math.max(body_lost, 0.0),
        engine_lost = math.max(engine_lost, 0.0),
        tank_lost = math.max(tank_lost, 0.0),
    })
end

local function poll_dirt()
    local vehicle = read()
    local dirt = vehicle == 0 and 0.0 or GetVehicleDirtLevel(vehicle)
    local state = dirt_state
    if vehicle ~= state.vehicle then
        state.vehicle, state.dirt = vehicle, dirt
        return
    end
    local gained = dirt - state.dirt
    if vehicle == 0 or gained < DIRT_THRESHOLD then
        if gained < 0 then
            state.dirt = dirt
        end
        return
    end
    state.dirt = dirt
    raise('dirtied', { vehicle = vehicle, dirt = dirt, gained = gained })
end

local registered = false

local function register_ticks()
    if registered then
        return
    end
    registered = true
    local function wanted(name)
        return function()
            return #handlers[name] > 0
        end
    end
    Ticks.register('Events.Vehicle.Seat', poll_seat, {
        rate = SEAT_INTERVAL_MS,
        condition = wanted('changed'),
        on_started = function()
            seat_state.vehicle, seat_state.seat = read()
        end,
    })
    Ticks.register('Events.Vehicle.Damage', poll_damage, {
        rate = DAMAGE_INTERVAL_MS,
        condition = wanted('damaged'),
        on_started = function()
            local vehicle = read()
            damage_state.vehicle = vehicle
            damage_state.body, damage_state.engine, damage_state.tank = condition(vehicle)
        end,
    })
    Ticks.register('Events.Vehicle.Dirt', poll_dirt, {
        rate = DIRT_INTERVAL_MS,
        condition = wanted('dirtied'),
        on_started = function()
            local vehicle = read()
            dirt_state.vehicle, dirt_state.dirt = vehicle, vehicle == 0 and 0.0 or GetVehicleDirtLevel(vehicle)
        end,
    })
end

function VehicleEvents.on(name, handler)
    local list = assert(handlers[name], ('unknown vehicle event %s'):format(tostring(name)))
    register_ticks()
    list[#list + 1] = handler
    Ticks.reevaluate()
    return function()
        for index = #list, 1, -1 do
            if list[index] == handler then
                table.remove(list, index)
            end
        end
        Ticks.reevaluate()
    end
end

return VehicleEvents
