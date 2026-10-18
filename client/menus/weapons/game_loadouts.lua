-- Port of vMenu.Enhanced.Menus/Weapons/GameLoadouts.cs: the loadouts the game
-- gives its own peds. Weapons a player may not have are taken away again.

local Localization = require('shared.localization')
local Catalog = require('client.menus.weapons.catalog')
local Inventory = require('client.menus.weapons.inventory')

local GameLoadouts = {}

local function plain(name)
    local key = 'weaponoptions.gameloadout.' .. name
    return Localization.key(key)
end

local function level(key, number)
    return Localization.key('weaponoptions.gameloadout.level', { name = plain(key), level = tostring(number) })
end

local function cheat(number)
    return Localization.key('weaponoptions.gameloadout.cheat', { number = tostring(number) })
end

-- { heading, loadouts = { { name, label } } }
GameLoadouts.GROUPS = {
    {
        heading = plain('services'),
        loadouts = {
            { 'LOADOUT_COP', plain('cop') },
            { 'LOADOUT_COP_L1', level('cop', 1) },
            { 'LOADOUT_COP_L2', level('cop', 2) },
            { 'LOADOUT_COP_L3', level('cop', 3) },
            { 'LOADOUT_COP_SHOTGUN', plain('copshotgun') },
            { 'LOADOUT_COP_HELI', plain('copheli') },
            { 'LOADOUT_COP_BOAT', plain('copboat') },
            { 'LOADOUT_SWAT', plain('swat') },
            { 'LOADOUT_SWAT_NO_LASER', plain('swatnolaser') },
            { 'LOADOUT_ARMY', plain('army') },
            { 'LOADOUT_FIREMAN', plain('fireman') },
            { 'LOADOUT_POLICE_GUARD', plain('policeguard') },
            { 'LOADOUT_SECUR', plain('security') },
            { 'LOADOUT_GUARD', plain('guard') },
        },
    },
    {
        heading = plain('gangs'),
        loadouts = {
            { 'LOADOUT_LOST', plain('lost') },
            { 'LOADOUT_LOST_L1', level('lost', 1) },
            { 'LOADOUT_LOST_L2', level('lost', 2) },
            { 'LOADOUT_LOST_L3', level('lost', 3) },
            { 'LOADOUT_MEXICAN', plain('mexican') },
            { 'LOADOUT_MEXICAN_L1', level('mexican', 1) },
            { 'LOADOUT_MEXICAN_L2', level('mexican', 2) },
            { 'LOADOUT_MEXICAN_L3', level('mexican', 3) },
            { 'LOADOUT_FAMILY', plain('family') },
            { 'LOADOUT_ASIAN', plain('asian') },
            { 'LOADOUT_HILLBILLY', plain('hillbilly') },
            { 'LOADOUT_CULT', plain('cult') },
        },
    },
    {
        heading = plain('cheats'),
        loadouts = {
            { 'LOADOUT_CHEAT_0', cheat(1) },
            { 'LOADOUT_CHEAT_1', cheat(2) },
        },
    },
    {
        heading = plain('animals'),
        loadouts = {
            { 'LOADOUT_ANIMAL', plain('animal') },
            { 'LOADOUT_COUGAR', plain('cougar') },
            { 'LOADOUT_ANIMAL_RETRIEVER', plain('retriever') },
            { 'LOADOUT_SMALL_DOG', plain('smalldog') },
            { 'LOADOUT_CAT', plain('cat') },
            { 'LOADOUT_COYOTE', plain('coyote') },
            { 'LOADOUT_BOAR', plain('boar') },
            { 'LOADOUT_PIG', plain('pig') },
            { 'LOADOUT_COW', plain('cow') },
            { 'LOADOUT_DEER', plain('deer') },
            { 'LOADOUT_RABBIT', plain('rabbit') },
            { 'LOADOUT_HEN', plain('hen') },
            { 'LOADOUT_TIGER_SHARK', plain('tigershark') },
            { 'LOADOUT_HAMMERHEAD_SHARK', plain('hammerheadshark') },
            { 'LOADOUT_KILLER_WHALE', plain('killerwhale') },
        },
    },
}

local ANIMAL_WEAPONS = {
    'weapon_animal',
    'weapon_cougar',
    'weapon_animal_retriever',
    'weapon_small_dog',
    'weapon_cat',
    'weapon_coyote',
    'weapon_boar',
    'weapon_pig',
    'weapon_cow',
    'weapon_deer',
    'weapon_rabbit',
    'weapon_hen',
    'weapon_tiger_shark',
    'weapon_hammerhead_shark',
    'weapon_killer_whale',
}

-- Returns how many weapons the player kept and how many were taken away.
function GameLoadouts.apply(name)
    local ped = PlayerPedId()
    local unarmed = GetHashKey('weapon_unarmed')
    local allowed = {}
    for _, weapon in ipairs(Inventory.allowed()) do
        allowed[weapon.spawn_name:lower()] = true
    end
    local given, removed = 0, 0
    Inventory.remove_all()
    GiveLoadoutToPed(ped, GetHashKey(name))
    for _, listed in ipairs(Catalog.listed()) do
        local hash = GetHashKey(listed.spawn_name)
        if hash ~= unarmed and Inventory.has(hash) then
            if allowed[listed.spawn_name:lower()] then
                Inventory.refill(hash)
                given = given + 1
            else
                RemoveWeaponFromPed(ped, hash)
                removed = removed + 1
            end
        end
    end
    local animal = unarmed
    for _, weapon in ipairs(ANIMAL_WEAPONS) do
        local hash = GetHashKey(weapon)
        if Inventory.has(hash) then
            animal = hash
            given = given + 1
        end
    end
    SetCurrentPedWeapon(ped, animal, true)
    return given, removed
end

return GameLoadouts
