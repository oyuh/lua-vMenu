-- Ports of vMenu.Enhanced.Menus/Weapons/WeaponUnlimitedAmmo.cs,
-- WeaponNoReload.cs and ParachuteOptions.cs: the weapon switches that keep
-- running with the menu closed.

local Localization = require('shared.localization')
local Permissions = require('client.permissions')
local UserDefaults = require('client.user_defaults')
local Catalog = require('client.menus.weapons.catalog')
local Ticks = require('menu.ticks')

local Features = {}

local PERMISSION = 'vMenu.Enhanced.Menus.WeaponOptions.'

local function preference_on(name, permission)
    return UserDefaults.get(name) == true and Permissions.is_allowed(PERMISSION .. permission)
end

local function setter(name, permission, after)
    return function(on)
        if on and not Permissions.is_allowed(PERMISSION .. permission) then
            return
        end
        UserDefaults.set(name, on)
        if after then
            after(on)
        end
        Ticks.reevaluate()
    end
end

-- Unlimited ammo ---------------------------------------------------------------------

local infinite = {}

function Features.unlimited_ammo()
    return preference_on('weaponsUnlimitedAmmo', 'UnlimitedAmmo')
end

local function clear_infinite()
    local ped = PlayerPedId()
    for weapon in pairs(infinite) do
        SetPedInfiniteAmmo(ped, false, weapon)
    end
    infinite = {}
end

Features.set_unlimited_ammo = setter('weaponsUnlimitedAmmo', 'UnlimitedAmmo', function(on)
    if not on then
        clear_infinite()
    end
end)

-- No reload --------------------------------------------------------------------------

function Features.no_reload()
    return preference_on('weaponsNoReload', 'NoReload')
end

Features.set_no_reload = setter('weaponsNoReload', 'NoReload')

-- Parachutes -------------------------------------------------------------------------

local PARACHUTE = 'gadget_parachute'
local CHECK_MS = 500
local SMOKE_CHANGE_MS = 4000

local STYLE_LABELS = {
    'PM_TINT0',
    'PM_TINT1',
    'PM_TINT2',
    'PM_TINT3',
    'PM_TINT4',
    'PM_TINT5',
    'PM_TINT6',
    'PM_TINT7',
    'PS_CAN_0',
    'PS_CAN_1',
    'PS_CAN_2',
    'PS_CAN_3',
    'PS_CAN_4',
    'PS_CAN_5',
}
local SMOKE_LABELS = { 'PM_TINT8', 'PM_TINT9', 'PM_TINT10', 'PM_TINT11', 'PM_TINT12', 'PM_TINT13' }
local SMOKE_COLORS = {
    { 255, 255, 255 },
    { 255, 0, 0 },
    { 255, 165, 0 },
    { 255, 255, 0 },
    { 0, 0, 255 },
    { 20, 20, 20 },
}

local changing_smoke = false

local function parachutes_allowed()
    return Permissions.is_allowed(PERMISSION .. 'Parachute')
end

function Features.auto_equip()
    return preference_on('weaponsAutoEquipParachute', 'Parachute')
end

function Features.unlimited_parachutes()
    return preference_on('weaponsUnlimitedParachutes', 'Parachute')
end

Features.set_auto_equip = setter('weaponsAutoEquipParachute', 'Parachute')
Features.set_unlimited_parachutes = setter('weaponsUnlimitedParachutes', 'Parachute')

local function has_primary()
    return HasPedGotWeapon(PlayerPedId(), GetHashKey(PARACHUTE), false)
end

-- True when it was given, false when it was taken away.
function Features.toggle_primary()
    local ped, hash = PlayerPedId(), GetHashKey(PARACHUTE)
    if has_primary() then
        RemoveWeaponFromPed(ped, hash)
        return false
    end
    GiveWeaponToPed(ped, hash, 1, false, false)
    return true
end

function Features.enable_reserve()
    SetPlayerHasReserveParachute(PlayerId())
end

-- The game's own names, read when the menu shows them.
local function names(labels)
    local list = {}
    for index, label in ipairs(labels) do
        list[index] = Localization.from(function()
            return Catalog.resolve_name(label, '')
        end)
    end
    return list
end

function Features.style_names()
    return names(STYLE_LABELS)
end

function Features.smoke_names()
    return names(SMOKE_LABELS)
end

-- 0-based, like the game.
function Features.set_primary_style(index)
    if parachutes_allowed() then
        SetPlayerParachuteTintIndex(PlayerId(), index)
    end
end

function Features.set_reserve_style(index)
    if parachutes_allowed() then
        SetPlayerReserveParachuteTintIndex(PlayerId(), index)
    end
end

-- The trail goes off for a few seconds first, or the game keeps the old color.
-- Waits, so call it from a thread. 1-based.
function Features.set_smoke_color(index)
    local color = SMOKE_COLORS[index]
    if not parachutes_allowed() or changing_smoke or not color then
        return
    end
    changing_smoke = true
    local player = PlayerId()
    SetPlayerCanLeaveParachuteSmokeTrail(player, false)
    Wait(SMOKE_CHANGE_MS)
    SetPlayerParachuteSmokeTrailColor(player, color[1], color[2], color[3])
    SetPlayerCanLeaveParachuteSmokeTrail(player, index ~= 1)
    changing_smoke = false
end

local function top_up_parachutes()
    if not has_primary() then
        GiveWeaponToPed(PlayerPedId(), GetHashKey(PARACHUTE), 1, false, false)
    end
    if not GetPlayerHasReserveParachute(PlayerId()) then
        SetPlayerHasReserveParachute(PlayerId())
    end
end

function Features.init()
    Ticks.register('Weapons.UnlimitedAmmo', function()
        local ped = PlayerPedId()
        local weapon = GetSelectedPedWeapon(ped)
        SetPedInfiniteAmmo(ped, true, weapon)
        infinite[weapon] = true
    end, { condition = Features.unlimited_ammo })
    Ticks.register('Weapons.NoReload', function()
        SetPedInfiniteAmmoClip(PlayerPedId(), true)
    end, {
        rate = 500,
        condition = Features.no_reload,
        on_stopped = function()
            SetPedInfiniteAmmoClip(PlayerPedId(), false)
        end,
    })
    Ticks.register('Weapons.AutoEquipParachute', function()
        local ped = PlayerPedId()
        if IsPedInAnyHeli(ped) or IsPedInAnyPlane(ped) then
            top_up_parachutes()
        end
    end, { rate = CHECK_MS, condition = Features.auto_equip })
    Ticks.register('Weapons.UnlimitedParachutes', top_up_parachutes, {
        rate = CHECK_MS,
        condition = Features.unlimited_parachutes,
    })
end

return Features
