-- Ports of vMenu.Enhanced.Menus/Weapons/Saved (WeaponLoadout.cs,
-- WeaponLoadoutStore.cs, WeaponLoadoutApply.cs, WeaponLoadoutRespawn.cs) and
-- WeaponCarryOver.cs. A loadout is saved under vmenu_weaponloadout_<name> as
-- upstream's camelCase JSON, so saves move between the two builds:
--   { name, weapons = { { spawnName, ammo, tint, components = { ... } } } }

local Log = require('shared.log')
local Json = require('shared.json_compat')
local Permissions = require('client.permissions')
local UserDefaults = require('client.user_defaults')
local Storage = require('client.storage')
local PlayerEvents = require('client.events.player_events')
local Catalog = require('client.menus.weapons.catalog')
local Inventory = require('client.menus.weapons.inventory')

local Loadouts = {}

local PREFIX = 'vmenu_weaponloadout_'
local PENDING_KEY = 'vmenu_pendingweaponloadout'
local VERSION = Storage.INITIAL_VERSION
local UNARMED = 'weapon_unarmed'
local COMPONENT_TIMEOUT_MS = 1000
local VISIBLE_TIMEOUT_MS = 60000
local VISIBLE_CHECK_MS = 100
local PERMISSION = 'vMenu.Enhanced.Menus.WeaponLoadouts.'

Loadouts.SAVED = 'saved'
Loadouts.NAME_TAKEN = 'nameTaken'
Loadouts.REFUSED = 'refused'

-- Store ------------------------------------------------------------------------------

-- Read case-insensitively; a save without a name or weapon list is ignored.
local function normalise(value)
    if type(value) ~= 'table' then
        return nil
    end
    local weapons = {}
    for _, weapon in ipairs(Json.field(value, 'weapons') or {}) do
        local components = {}
        for _, component in ipairs(Json.field(weapon, 'components') or {}) do
            components[#components + 1] = tostring(component)
        end
        weapons[#weapons + 1] = {
            spawnName = tostring(Json.field(weapon, 'spawnName') or ''),
            ammo = math.tointeger(Json.field(weapon, 'ammo')) or 0,
            tint = math.tointeger(Json.field(weapon, 'tint')) or 0,
            components = components,
        }
    end
    return { name = tostring(Json.field(value, 'name') or ''), weapons = weapons }
end

local function read(key)
    return normalise((Storage.read(key, 'json', VERSION)))
end

local function key_of(name)
    return PREFIX .. name
end

-- Every saved loadout, sorted by name.
function Loadouts.all()
    local all = {}
    for _, key in ipairs(Storage.keys(PREFIX)) do
        local loadout = read(key)
        if loadout then
            all[#all + 1] = loadout
        end
    end
    table.sort(all, function(left, right)
        return left.name:lower() < right.name:lower()
    end)
    return all
end

function Loadouts.load(name)
    return read(key_of(name))
end

function Loadouts.save(loadout, replacing)
    local key = key_of(loadout.name)
    if not replacing and read(key) then
        return Loadouts.NAME_TAKEN
    end
    return Storage.write(key, 'json', VERSION, loadout) and Loadouts.SAVED or Loadouts.REFUSED
end

function Loadouts.is_default(name)
    return name ~= '' and UserDefaults.get('weaponLoadoutDefaultName') == name
end

function Loadouts.set_default(name)
    UserDefaults.set('weaponLoadoutDefaultName', name)
end

function Loadouts.delete(name)
    Storage.delete(key_of(name))
    if Loadouts.is_default(name) then
        Loadouts.set_default('')
    end
end

-- False when the new name is taken or the save failed.
function Loadouts.rename(loadout, new_name)
    if Loadouts.load(new_name) then
        return false
    end
    local old_name = loadout.name
    loadout.name = new_name
    if Loadouts.save(loadout, false) ~= Loadouts.SAVED then
        loadout.name = old_name
        return false
    end
    local was_default = Loadouts.is_default(old_name)
    Storage.delete(key_of(old_name))
    if was_default then
        Loadouts.set_default(new_name)
    end
    return true
end

function Loadouts.duplicate(loadout, new_name)
    return Loadouts.save({ name = new_name, weapons = loadout.weapons }, false) == Loadouts.SAVED
end

-- What the player holds right now, as a loadout called name.
function Loadouts.capture(name)
    local loadout = { name = name, weapons = {} }
    for _, listed in ipairs(Catalog.listed()) do
        local hash = GetHashKey(listed.spawn_name)
        if Inventory.has(hash) then
            local components = {}
            for _, component in ipairs(Catalog.components_for(hash)) do
                if Inventory.has_component(hash, GetHashKey(component.spawn_name)) then
                    components[#components + 1] = component.spawn_name
                end
            end
            loadout.weapons[#loadout.weapons + 1] = {
                spawnName = listed.spawn_name,
                ammo = Inventory.ammo(hash),
                tint = Inventory.tint(hash),
                components = components,
            }
        end
    end
    return loadout
end

-- Applying ---------------------------------------------------------------------------

local function fit(ped, hash, component)
    local deadline = GetGameTimer() + COMPONENT_TIMEOUT_MS
    GiveWeaponComponentToPed(ped, hash, component)
    while not HasPedGotWeaponComponent(ped, hash, component) do
        if GetGameTimer() > deadline then
            return false
        end
        GiveWeaponComponentToPed(ped, hash, component)
        Wait(0)
    end
    return true
end

local function fill(ped, hash)
    SetAmmoInClip(ped, hash, GetMaxAmmoInClip(ped, hash, false))
    local wanted = Inventory.max_ammo(hash)
    SetPedAmmo(ped, hash, wanted)
    local missing = wanted - GetAmmoInPedWeapon(ped, hash)
    if missing > 0 then
        AddAmmoToPedByType(ped, GetPedAmmoTypeFromWeapon(ped, hash), missing)
    end
end

local function give(saved, hash)
    local ped = PlayerPedId()
    GiveWeaponToPed(ped, hash, Inventory.max_ammo(hash), false, false)
    for _, component in ipairs(saved.components) do
        local component_hash = GetHashKey(component)
        if not DoesWeaponTakeWeaponComponent(hash, component_hash) then
            Log.debug(("[Weapons] '%s' no longer takes '%s', so it was left off."):format(saved.spawnName, component))
        elseif not fit(ped, hash, component_hash) then
            Log.debug(
                ("[Weapons] '%s' would not fit on '%s' within %dms."):format(
                    component,
                    saved.spawnName,
                    COMPONENT_TIMEOUT_MS
                )
            )
        end
    end
    if saved.tint > 0 then
        SetPedWeaponTintIndex(ped, hash, saved.tint)
    end
    fill(ped, hash)
end

local function allowed(spawn_name)
    local weapon, category = Catalog.find(spawn_name)
    return weapon ~= nil and Permissions.can_use_weapon(weapon.spawn_name, category)
end

-- Gives the loadout's weapons, replacing what the player holds unless append.
-- Waits, so call it from a thread. Returns given, skipped and the names given.
function Loadouts.apply(loadout, append, ignore_permissions)
    if not append then
        Inventory.remove_all()
    end
    local given, skipped, names = 0, 0, {}
    for _, saved in ipairs(loadout.weapons) do
        local hash = GetHashKey(saved.spawnName)
        if not IsWeaponValid(hash) then
            Log.debug(
                ("[Weapons] Skipping '%s' from loadout '%s': this game no longer has that weapon."):format(
                    saved.spawnName,
                    loadout.name
                )
            )
            skipped = skipped + 1
        elseif not ignore_permissions and not allowed(saved.spawnName) then
            skipped = skipped + 1
        else
            give(saved, hash)
            local weapon = Catalog.find(saved.spawnName)
            names[#names + 1] = weapon and Catalog.weapon_name(weapon) or saved.spawnName
            given = given + 1
        end
    end
    SetCurrentPedWeapon(PlayerPedId(), GetHashKey(UNARMED), true)
    return given, skipped, names
end

-- Respawning -------------------------------------------------------------------------

function Loadouts.restore_on_respawn()
    return UserDefaults.get('weaponLoadoutOnRespawn') == true and Permissions.is_allowed(PERMISSION .. 'EquipOnRespawn')
end

function Loadouts.set_restore_on_respawn(on)
    if on and not Permissions.is_allowed(PERMISSION .. 'EquipOnRespawn') then
        return
    end
    UserDefaults.set('weaponLoadoutOnRespawn', on)
end

local function wait_until_visible()
    local deadline = GetGameTimer() + VISIBLE_TIMEOUT_MS
    while
        not NetworkIsSessionStarted()
        or IsPlayerSwitchInProgress()
        or not IsScreenFadedIn()
        or IsEntityDead(PlayerPedId(), false)
    do
        if GetGameTimer() > deadline then
            return
        end
        Wait(VISIBLE_CHECK_MS)
    end
end

local restored_on_join = false

-- Equips the default loadout once, when the player first spawns. Waits.
function Loadouts.restore_on_join()
    if restored_on_join then
        return
    end
    restored_on_join = true
    local name = UserDefaults.get('weaponLoadoutDefaultName')
    if not Loadouts.restore_on_respawn() or name == '' then
        return
    end
    Catalog.wait_for_first()
    local loadout = Loadouts.load(name)
    if not loadout then
        return
    end
    wait_until_visible()
    local given, skipped = Loadouts.apply(loadout, true, false)
    Log.debug(("[Weapons] Restored %d weapon(s) from loadout '%s' on join, %d skipped."):format(given, name, skipped))
end

local function on_died()
    if Loadouts.restore_on_respawn() then
        Storage.write(PENDING_KEY, 'json', VERSION, Loadouts.capture(''))
    end
end

local function on_revived(event)
    if not event.respawned or not Loadouts.restore_on_respawn() then
        return
    end
    CreateThread(function()
        local name = UserDefaults.get('weaponLoadoutDefaultName')
        local loadout = (name ~= '' and Loadouts.load(name)) or read(PENDING_KEY)
        if not loadout then
            return
        end
        wait_until_visible()
        local given, skipped = Loadouts.apply(loadout, true, true)
        Storage.delete(PENDING_KEY)
        Log.debug(('[Weapons] Restored %d weapon(s) after respawn, %d skipped.'):format(given, skipped))
    end)
end

-- Carrying weapons through a ped change -----------------------------------------------

function Loadouts.keep_on_ped_change()
    return UserDefaults.get('weaponsKeepOnPedChange') == true
        and Permissions.is_allowed(PERMISSION .. 'KeepOnPedChange')
end

function Loadouts.set_keep_on_ped_change(on)
    if on and not Permissions.is_allowed(PERMISSION .. 'KeepOnPedChange') then
        return
    end
    UserDefaults.set('weaponsKeepOnPedChange', on)
end

function Loadouts.init()
    PlayerEvents.on('died', on_died)
    PlayerEvents.on('revived', on_revived)
end

return Loadouts
