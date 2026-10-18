-- Ports of vMenu.Enhanced.Menus/Players/PlayerTeleport.cs and GroundHeight.cs:
-- moves the player (or the vehicle they drive) behind a screen fade, waits for
-- the world to load there, and can find the ground under a map position.
-- Waits, so call it from a thread.

local Log = require('shared.log')
local Locks = require('client.framework.locks')
local Natives = require('client.natives')

local Teleport = {}

local LOAD_SCENE_TIMEOUT_MS = 3000
local COLLISION_TIMEOUT_MS = 2000
local LOAD_SCENE_RADIUS = 50.0
local FADE_MS = 500

-- Ground ---------------------------------------------------------------------------

local CLEARANCE = 1.0
local CEILING = 1200.0
local COLUMN_TOP = 1500.0
local COLUMN_BOTTOM = -300.0
local MAP = 1
local MAP_AND_OBJECTS = 1 | 16
local SHAPE_TEST_OPTIONS = 7
local SHAPE_TEST_NOT_READY = 1
local SHAPE_TEST_READY = 2
local MAX_RESULT_FRAMES = 10

-- The game only streams the ground near the player, so the probe climbs.
local PROBE_HEIGHTS = {
    0.0,
    25.0,
    50.0,
    75.0,
    100.0,
    150.0,
    200.0,
    250.0,
    300.0,
    350.0,
    400.0,
    450.0,
    500.0,
    550.0,
    600.0,
    650.0,
    700.0,
    750.0,
    800.0,
    CEILING,
}

local function cast(entity, x, y, flags)
    local test = StartExpensiveSynchronousShapeTestLosProbe(
        x,
        y,
        COLUMN_TOP,
        x,
        y,
        COLUMN_BOTTOM,
        flags,
        entity,
        SHAPE_TEST_OPTIONS
    )
    for _ = 1, MAX_RESULT_FRAMES do
        local status, hit, finish = GetShapeTestResult(test)
        if status ~= SHAPE_TEST_NOT_READY then
            return (status == SHAPE_TEST_READY and hit ~= 0 and hit ~= false) and finish.z or nil
        end
        Wait(0)
    end
    return nil
end

local function ask(entity, x, y)
    local ground = cast(entity, x, y, MAP_AND_OBJECTS) or cast(entity, x, y, MAP)
    if not ground then
        return nil
    end
    local water = Natives.test_vertical_probe_against_all_water(x, y, COLUMN_TOP)
    if water and water > ground then
        return water
    end
    return ground
end

local function from_entity(entity, x, y)
    SetEntityCoords(entity, x, y, CEILING, false, false, false, true)
    local above = GetEntityHeightAboveGround(entity)
    if above > 0 and above < CEILING then
        return CEILING - above + CLEARANCE
    end
    return nil
end

-- The height to stand at x, y, or nil. Moves entity while it looks.
function Teleport.find_ground(entity, x, y)
    local origin = GetEntityCoords(entity, false)
    local ok, found = pcall(function()
        for _, height in ipairs(PROBE_HEIGHTS) do
            SetEntityCoords(entity, x, y, height, false, false, false, true)
            Wait(0)
            local ground = ask(entity, x, y)
            if ground then
                return ground + CLEARANCE
            end
        end
        return from_entity(entity, x, y)
    end)
    if not ok then
        Log.error(('[Teleport] Looking for the ground at %.1f, %.1f threw: %s'):format(x, y, tostring(found)))
    end
    if ok and found then
        return found
    end
    SetEntityCoords(entity, origin.x, origin.y, origin.z, false, false, false, true)
    return nil
end

-- Moving ---------------------------------------------------------------------------

local function wait_until(done, timeout_ms)
    local started = GetGameTimer()
    while not done() and (not timeout_ms or GetGameTimer() - started < timeout_ms) do
        Wait(0)
    end
end

local function place(ped, moving, driving, x, y, z, find_ground, heading)
    RequestCollisionAtCoord(x, y, z)
    SetFocusPosAndVel(x, y, z, 0.0, 0.0, 0.0)
    NewLoadSceneStart(x, y, z, x, y, z, LOAD_SCENE_RADIUS, 0)
    wait_until(IsNewLoadSceneLoaded, LOAD_SCENE_TIMEOUT_MS)
    ClearFocus()
    NewLoadSceneStop()
    if find_ground then
        z = Teleport.find_ground(moving, x, y)
        if not z then
            return false
        end
    end
    SetEntityCoords(moving, x, y, z, false, false, false, true)
    if heading then
        SetEntityHeading(moving, heading)
    end
    wait_until(function()
        return HasCollisionLoadedAroundEntity(ped)
    end, COLLISION_TIMEOUT_MS)
    if driving then
        FreezeEntityPosition(moving, false)
        Natives.set_vehicle_on_ground_properly(moving, 5.0)
        FreezeEntityPosition(moving, true)
    end
    return true
end

local function go(x, y, z, find_ground, heading)
    local ped = PlayerPedId()
    if Locks.scene_active() or ped == 0 or not DoesEntityExist(ped) then
        return false
    end
    local vehicle = GetVehiclePedIsIn(ped, false)
    local driving = vehicle ~= 0 and DoesEntityExist(vehicle) and GetPedInVehicleSeat(vehicle, -1) == ped
    local moving = driving and vehicle or ped
    if not driving then
        ClearPedTasksImmediately(ped)
    end
    FreezeEntityPosition(moving, true)
    NetworkFadeOutEntity(moving, true, false)
    DoScreenFadeOut(FADE_MS)
    wait_until(IsScreenFadedOut)
    local ok, placed = pcall(place, ped, moving, driving, x, y, z, find_ground, heading)
    FreezeEntityPosition(moving, false)
    NetworkFadeInEntity(moving, true, false)
    DoScreenFadeIn(FADE_MS)
    if not ok then
        error(placed, 0)
    end
    return placed
end

function Teleport.to_coords(x, y, z, heading)
    return go(x, y, z, false, heading)
end

-- False when no ground was found there.
function Teleport.to_ground(x, y, heading)
    return go(x, y, 0.0, true, heading)
end

return Teleport
