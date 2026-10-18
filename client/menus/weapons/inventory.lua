-- Ports of vMenu.Enhanced.Menus/Weapons/WeaponInventory.cs, WeaponTints.cs and
-- WeaponStatistics.cs: what the player holds, and the changes Weapon Options
-- makes to it.

local Localization = require('shared.localization')
local Permissions = require('client.permissions')
local Natives = require('client.natives')
local Catalog = require('client.menus.weapons.catalog')

local Inventory = {}

local UNARMED = 'weapon_unarmed'
local FALLBACK_AMMO = 250
local MODIFY = 'vMenu.Enhanced.Menus.WeaponOptions.Modify'
local SPAWN = 'vMenu.Enhanced.Menus.WeaponOptions.Spawn'

function Inventory.has(hash)
    return HasPedGotWeapon(PlayerPedId(), hash, false)
end

function Inventory.tint_count(hash)
    return math.max(1, GetWeaponTintCount(hash))
end

function Inventory.tint(hash)
    return GetPedWeaponTintIndex(PlayerPedId(), hash)
end

function Inventory.set_tint(hash, tint)
    if Permissions.is_allowed(MODIFY) and Inventory.has(hash) then
        SetPedWeaponTintIndex(PlayerPedId(), hash, tint)
    end
end

function Inventory.max_ammo(hash)
    local known, ammo = GetMaxAmmo(PlayerPedId(), hash)
    return known and ammo or FALLBACK_AMMO
end

function Inventory.ammo(hash)
    return GetAmmoInPedWeapon(PlayerPedId(), hash)
end

-- False when the player does not hold it.
function Inventory.refill(hash)
    if not Inventory.has(hash) then
        return false
    end
    local ped = PlayerPedId()
    SetAmmoInClip(ped, hash, GetMaxAmmoInClip(ped, hash, false))
    SetPedAmmo(ped, hash, Inventory.max_ammo(hash))
    return true
end

function Inventory.give(hash)
    GiveWeaponToPed(PlayerPedId(), hash, Inventory.max_ammo(hash), false, true)
    Inventory.refill(hash)
end

-- True when it was given, false when it was taken away.
function Inventory.toggle(hash)
    if Inventory.has(hash) then
        RemoveWeaponFromPed(PlayerPedId(), hash)
        return false
    end
    Inventory.give(hash)
    return true
end

function Inventory.remove_all()
    RemoveAllPedWeapons(PlayerPedId(), true)
end

-- The listed weapons this player may have, as { spawn_name, category }.
function Inventory.allowed()
    local allowed = {}
    if not Permissions.is_allowed(SPAWN) then
        return allowed
    end
    for _, weapon in ipairs(Catalog.listed()) do
        if Permissions.can_use_weapon(weapon.spawn_name, weapon.category) and Catalog.is_valid(weapon.spawn_name) then
            allowed[#allowed + 1] = weapon
        end
    end
    return allowed
end

function Inventory.give_all()
    local given = 0
    for _, weapon in ipairs(Inventory.allowed()) do
        Inventory.give(GetHashKey(weapon.spawn_name))
        given = given + 1
    end
    SetCurrentPedWeapon(PlayerPedId(), GetHashKey(UNARMED), true)
    return given
end

function Inventory.refill_all()
    local refilled = 0
    for _, weapon in ipairs(Catalog.listed()) do
        if Inventory.refill(GetHashKey(weapon.spawn_name)) then
            refilled = refilled + 1
        end
    end
    return refilled
end

function Inventory.set_all_ammo(ammo)
    local ped = PlayerPedId()
    local changed = 0
    for _, weapon in ipairs(Catalog.listed()) do
        local hash = GetHashKey(weapon.spawn_name)
        if Inventory.has(hash) then
            SetPedAmmo(ped, hash, math.min(ammo, Inventory.max_ammo(hash)))
            changed = changed + 1
        end
    end
    return changed
end

function Inventory.has_component(hash, component)
    return HasPedGotWeaponComponent(PlayerPedId(), hash, component)
end

-- Fitting a component refills the gun, so the ammo is put back after.
function Inventory.toggle_component(hash, component)
    if not Permissions.is_allowed(MODIFY) or not Inventory.has(hash) then
        return
    end
    local ped = PlayerPedId()
    if Inventory.has_component(hash, component) then
        RemoveWeaponComponentFromPed(ped, hash, component)
        return
    end
    local reserve = GetAmmoInPedWeapon(ped, hash)
    local _, clip = GetAmmoInClip(ped, hash)
    GiveWeaponComponentToPed(ped, hash, component)
    SetAmmoInClip(ped, hash, clip)
    SetPedAmmo(ped, hash, reserve)
end

-- Tints ------------------------------------------------------------------------------

local STANDARD_TINTS = { 'black', 'green', 'gold', 'pink', 'army', 'lspd', 'orange', 'platinum' }

local MK2_TINTS = {
    'classicblack',
    'classicgray',
    'classictwotone',
    'classicwhite',
    'classicbeige',
    'classicgreen',
    'classicblue',
    'classicearth',
    'classicbrownblack',
    'redcontrast',
    'bluecontrast',
    'yellowcontrast',
    'orangecontrast',
    'boldpink',
    'boldpurpleyellow',
    'boldorange',
    'boldgreenpurple',
    'boldredfeatures',
    'boldgreenfeatures',
    'boldcyanfeatures',
    'boldyellowfeatures',
    'boldredwhite',
    'boldbluewhite',
    'metallicgold',
    'metallicplatinum',
    'metallicgraylilac',
    'metallicpurplelime',
    'metallicred',
    'metallicgreen',
    'metallicblue',
    'metallicwhiteaqua',
    'metallicredyellow',
}

-- A name for each of a weapon's count tints. Mk II weapons have the long list.
function Inventory.tint_options(count)
    local names = count > #STANDARD_TINTS and MK2_TINTS or STANDARD_TINTS
    local options = {}
    for index = 1, count do
        local key = names[index] and 'weaponoptions.tint.' .. names[index]
        options[index] = key and Localization.key(key) or tostring(index)
    end
    return options
end

-- Stats ------------------------------------------------------------------------------

local SCALE = 100.0
local weapon_stats, component_stats = {}, {}

local function stats(cache, read, hash)
    local known = cache[hash]
    if known == nil then
        local bars = read(hash)
        known = bars
                and {
                    bars.damage / SCALE,
                    bars.speed / SCALE,
                    bars.accuracy / SCALE,
                    bars.range / SCALE,
                }
            or false
        cache[hash] = known
    end
    return known or nil
end

-- The stat panel bars for a weapon, or nil when the game has none.
function Inventory.weapon_stats(hash)
    return stats(weapon_stats, Natives.weapon_hud_stats, hash)
end

-- What a component adds to (or takes from) those bars.
function Inventory.component_stats(hash)
    return stats(component_stats, Natives.weapon_component_hud_stats, hash)
end

return Inventory
