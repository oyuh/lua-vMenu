-- Port of vMenu.Enhanced.Menus/World/SnowballPickup.cs: while there is snow on
-- the ground, a key scoops up snowballs with GTA Online's animation.

local Permissions = require('client.permissions')
local Controller = require('menu.controller')
local Effects = require('client.menus.world.effects')

local Snowball = {}

local COMMAND = 'vmenu:snowball'
local DICTIONARY = 'anim@mp_snowball'
local ANIMATION = 'pickup_snowball'
local PER_PICKUP = 2
local FALLBACK_MAX_AMMO = 10
local START_TIMEOUT_MS = 1000

local running = false

local function can_pick_up()
    if not Effects.snow_wanted() or not Permissions.is_allowed('vMenu.Enhanced.Menus.WeaponOptions.Snowball') then
        return false
    end
    if Controller.IsAnyMenuOpen() or IsPauseMenuActive() or IsPlayerSwitchInProgress() or not IsScreenFadedIn() then
        return false
    end
    local ped = PlayerPedId()
    if IsPedDeadOrDying(ped, true) or IsPedInAnyVehicle(ped, false) or not IsPedOnFoot(ped) then
        return false
    end
    if GetInteriorFromEntity(ped) ~= 0 then
        return false
    end
    if
        IsPedFalling(ped)
        or IsPedInParachuteFreeFall(ped)
        or IsPedBeingStunned(ped, 0)
        or IsPedWalking(ped)
        or IsPedRunning(ped)
        or IsPedSprinting(ped)
        or IsPedSwimming(ped)
        or IsPedSwimmingUnderWater(ped)
        or IsPedDiving(ped)
    then
        return false
    end
    local selected = GetSelectedPedWeapon(ped)
    return selected == GetHashKey('weapon_unarmed') or selected == GetHashKey('weapon_snowball')
end

local function load_dictionary()
    if HasAnimDictLoaded(DICTIONARY) then
        return true
    end
    RequestAnimDict(DICTIONARY)
    local started = GetGameTimer()
    while not HasAnimDictLoaded(DICTIONARY) do
        if GetGameTimer() - started > START_TIMEOUT_MS then
            return false
        end
        Wait(0)
    end
    return true
end

local function grant(ped, weapon, max)
    AddAmmoToPed(ped, weapon, PER_PICKUP)
    GiveWeaponToPed(ped, weapon, 0, true, true)
    if GetAmmoInPedWeapon(ped, weapon) > max then
        SetPedAmmo(ped, weapon, max)
    end
end

-- Hands the snowballs over when the animation reaches its "CreateObject" event.
local function play(ped, weapon, max)
    local granted = false
    local started = GetGameTimer()
    local limit = math.floor(GetAnimDuration(DICTIONARY, ANIMATION) * 1000) + START_TIMEOUT_MS
    while GetGameTimer() - started < limit do
        Wait(0)
        if HasAnimEventFired(ped, GetHashKey('Interrupt')) then
            return
        end
        if not granted and HasAnimEventFired(ped, GetHashKey('CreateObject')) then
            granted = true
            grant(ped, weapon, max)
        end
        if granted and GetEntityAnimCurrentTime(ped, DICTIONARY, ANIMATION) >= 0.97 then
            return
        end
    end
end

local function scoop()
    local ped = PlayerPedId()
    local weapon = GetHashKey('weapon_snowball')
    local has_max, reported = GetMaxAmmo(ped, weapon)
    local max = has_max and reported or FALLBACK_MAX_AMMO
    if GetAmmoInPedWeapon(ped, weapon) >= max or not load_dictionary() then
        return
    end
    ClearPedTasks(ped)
    SetPedCurrentWeaponVisible(ped, false, true, false, false)
    TaskPlayAnim(ped, DICTIONARY, ANIMATION, 8.0, 1.0, -1, 0, 0.0, false, false, false)
    play(ped, weapon, max)
    RemoveAnimDict(DICTIONARY)
end

local function on_pressed()
    if running or not can_pick_up() then
        return
    end
    running = true
    CreateThread(function()
        local ok, err = pcall(scoop)
        running = false
        if not ok then
            error(err, 0)
        end
    end)
end

function Snowball.init()
    RegisterCommand(COMMAND, on_pressed, false)
    RegisterCommand(COMMAND .. ':pad', on_pressed, false)
    RegisterKeyMapping(COMMAND, 'vMenu: Pick up a snowball', 'keyboard', 'G')
    RegisterKeyMapping(COMMAND .. ':pad', 'vMenu: Pick up a snowball (controller)', 'PAD_ANALOGBUTTON', 'LRIGHT_INDEX')
end

return Snowball
