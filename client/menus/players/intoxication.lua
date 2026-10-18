-- Ports of vMenu.Enhanced.Menus/Players/PlayerIntoxication.cs,
-- Intoxication.cs and DrunkSteering.cs: being drunk or drugged, with each
-- part (screen, walk, sprinting, steering) switchable on its own.
--
-- Upstream also hands the screen back to the Bully menu's color pranks, the
-- World menu's timecycle and the player's walking style. Those menus are not
-- ported yet; this gets wired to them when they are.

local Permissions = require('client.permissions')
local UserDefaults = require('client.user_defaults')
local Ticks = require('menu.ticks')
local PlayerEvents = require('client.events.player_events')
local Streaming = require('client.streaming')

local Intoxication = {}

Intoxication.STRENGTH_LEVELS = 10

local PERMISSION = 'vMenu.Enhanced.Menus.PlayerOptions.Intoxication'
local SPRINT = 21
local BLEND_SECONDS = 1.0
local WATCH_MS = 1000
local DRUNK_WALK = 'move_m@drunk@verydrunk'
local SHAKE = 'DRUNK_SHAKE'
local DRUGS_IN = 'DrugsMichaelAliensFightIn'

local screen, walk, drunk, timecycle = false, false, false, -1

local function preference(name)
    return UserDefaults.get(name)
end

function Intoxication.enabled()
    return preference('playerIntoxication') == true and Permissions.is_allowed(PERMISSION)
end

function Intoxication.drugged()
    return preference('playerIntoxicationDrugged') == true
end

function Intoxication.screen_effects()
    return preference('playerIntoxicationScreen') == true
end

-- 1 to STRENGTH_LEVELS.
function Intoxication.strength()
    return math.max(1, math.min(Intoxication.STRENGTH_LEVELS, preference('playerIntoxicationStrength')))
end

function Intoxication.walking_style()
    return preference('playerIntoxicationWalk') == true
end

function Intoxication.prevent_sprint()
    return preference('playerIntoxicationNoSprint') == true
end

function Intoxication.driving()
    return preference('playerIntoxicationDriving') == true
end

-- Drunk steering ---------------------------------------------------------------------

local REROLL_MS = 1000
local STOPPED_SPEED = 0.04
local CAR_SCALE = 0.35
local BIKE_SCALE = 1.5

local steering = { vehicle = 0, bias = 0.0, reroll_at = 0 }

local function release_steering()
    if steering.vehicle ~= 0 and DoesEntityExist(steering.vehicle) then
        SetVehicleSteerBias(steering.vehicle, 0.0)
    end
    steering.vehicle, steering.bias, steering.reroll_at = 0, 0.0, 0
end

local function driven_vehicle()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
        return vehicle
    end
    return 0
end

local function random_between(low, high)
    return low + math.random() * (high - low)
end

local function roll(vehicle, drugged)
    local range = drugged and 0.06 or 0.05
    local bias = random_between(-range, range)
    local offset = random_between(0.0, drugged and 0.025 or 0.02)
    local scale = IsThisModelABike(GetEntityModel(vehicle)) and BIKE_SCALE or CAR_SCALE
    bias = bias < 0 and bias - offset or bias + offset
    return math.max(-1.0, math.min(1.0, bias * scale))
end

local function steer(drugged)
    local driven = driven_vehicle()
    if driven ~= steering.vehicle then
        release_steering()
        steering.vehicle = driven
    end
    if steering.vehicle == 0 or not NetworkHasControlOfEntity(steering.vehicle) then
        return
    end
    local now = GetGameTimer()
    if now >= steering.reroll_at then
        steering.reroll_at = now + REROLL_MS
        steering.bias = GetEntitySpeed(steering.vehicle) < STOPPED_SPEED and 0.0 or roll(steering.vehicle, drugged)
    end
    SetVehicleSteerBias(steering.vehicle, steering.bias)
end

-- Effects ----------------------------------------------------------------------------

local function clear_screen()
    screen, timecycle = false, -1
    AnimpostfxStop(DRUGS_IN)
    StopGameplayCamShaking(true)
    ClearTimecycleModifier()
end

local function sync_screen(wanted)
    if not wanted then
        if screen then
            clear_screen()
        end
        return
    end
    local drugged = Intoxication.drugged()
    local strength = Intoxication.strength() / Intoxication.STRENGTH_LEVELS
    if not screen or GetTimecycleModifierIndex() ~= timecycle then
        SetTimecycleModifier(drugged and 'stoned_aliens' or 'DRUNK')
        SetTimecycleModifierStrength(strength)
        timecycle = GetTimecycleModifierIndex()
    end
    if not IsGameplayCamShaking() then
        ShakeGameplayCam(SHAKE, (drugged and 2.0 or 1.2) * strength)
    end
    if drugged and not AnimpostfxIsRunning(DRUGS_IN) then
        AnimpostfxPlay(DRUGS_IN, 0, true)
    end
    screen = true
end

-- Waits for the clip set, so it runs on a thread.
local function sync_walk(wanted)
    if wanted == walk then
        return
    end
    if not wanted then
        walk = false
        ResetPedMovementClipset(PlayerPedId(), BLEND_SECONDS)
        RemoveClipSet(DRUNK_WALK)
        return
    end
    if not Streaming.clip_set(DRUNK_WALK) then
        return
    end
    if not (Intoxication.enabled() and Intoxication.walking_style()) then
        RemoveClipSet(DRUNK_WALK)
        return
    end
    SetPedMovementClipset(PlayerPedId(), DRUNK_WALK, BLEND_SECONDS)
    walk = true
end

local function sync()
    local on = Intoxication.enabled()
    sync_screen(on and Intoxication.screen_effects())
    if on or drunk then
        SetPedIsDrunk(PlayerPedId(), on)
        drunk = on
    end
    sync_walk(on and Intoxication.walking_style())
end

local function refresh()
    CreateThread(sync)
    Ticks.reevaluate()
end

local function frame()
    if Intoxication.prevent_sprint() then
        DisableControlAction(0, SPRINT, true)
    end
    if Intoxication.driving() then
        steer(Intoxication.drugged())
    else
        release_steering()
    end
end

-- Setters ----------------------------------------------------------------------------

function Intoxication.set_enabled(on)
    if on and not Permissions.is_allowed(PERMISSION) then
        return
    end
    UserDefaults.set('playerIntoxication', on)
    refresh()
end

local function restart_screen()
    if screen then
        clear_screen()
    end
    refresh()
end

function Intoxication.set_drugged(on)
    UserDefaults.set('playerIntoxicationDrugged', on)
    restart_screen()
end

function Intoxication.set_strength(level)
    UserDefaults.set('playerIntoxicationStrength', math.max(1, math.min(Intoxication.STRENGTH_LEVELS, level)))
    restart_screen()
end

local function setter(name)
    return function(on)
        UserDefaults.set(name, on)
        refresh()
    end
end

Intoxication.set_screen_effects = setter('playerIntoxicationScreen')
Intoxication.set_walking_style = setter('playerIntoxicationWalk')
Intoxication.set_prevent_sprint = setter('playerIntoxicationNoSprint')
Intoxication.set_driving = setter('playerIntoxicationDriving')

function Intoxication.init()
    Ticks.register('Player.Intoxication', frame, {
        condition = function()
            return Intoxication.enabled() and (Intoxication.prevent_sprint() or Intoxication.driving())
        end,
        on_stopped = release_steering,
    })
    Ticks.register('Player.IntoxicationWatch', sync, { rate = WATCH_MS, condition = Intoxication.enabled })
    Permissions.on_changed(refresh)
    local function new_ped()
        walk, drunk = false, false
        refresh()
    end
    PlayerEvents.on('ped_changed', new_ped)
    PlayerEvents.on('revived', new_ped)
    AddEventHandler('onResourceStop', function(stopped)
        if stopped ~= GetCurrentResourceName() then
            return
        end
        local ped = PlayerPedId()
        if screen then
            clear_screen()
        end
        if walk then
            ResetPedMovementClipset(ped, 0.0)
        end
        if drunk then
            SetPedIsDrunk(ped, false)
        end
        release_steering()
    end)
end

return Intoxication
