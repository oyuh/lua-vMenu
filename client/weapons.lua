-- Port of the runtime halves of vMenu/data/ValidWeapon.cs and
-- ValidAddonWeapon.cs: building the valid-weapon lists against the game
-- (which components each weapon accepts) and merging addon weapon
-- components from config/addons.json. The static tables live in the
-- generated client/data/weapons_data.lua.

local Json = require('shared.json_compat')
local Util = require('shared.util')
local Data = require('client.data.weapons_data')

local Weapons = {}

-- GetWeaponComponents: the generated component-name map extended with the
-- addons.json "weapon_components" entries (each mapping to itself).
local components_cache = nil
local components_order_cache = nil

function Weapons.get_weapon_components()
    if components_cache ~= nil then
        return components_cache, components_order_cache
    end
    local components = {}
    local order = {}
    for _, key in ipairs(Data.weapon_component_names_order) do
        components[key] = Data.weapon_component_names[key]
        order[#order + 1] = key
    end

    local addons = LoadResourceFile(GetCurrentResourceName(), 'config/addons.json') or '{}'
    local decoded = Json.decode(addons)
    if decoded == nil then
        Util.debug_log('[WARNING] The addons.json contains invalid JSON.')
    elseif type(decoded.weapon_components) == 'table' then
        for _, key in ipairs(decoded.weapon_components) do
            if components[key] == nil then
                order[#order + 1] = key
            end
            components[key] = key
        end
    end

    components_cache = components
    components_order_cache = order
    return components, order
end

-- The component map for one weapon hash: localized name -> component hash,
-- for every component the game says this weapon accepts. Also returns the
-- localized names in discovery order (menus preserve it).
local function components_for(weapon_hash)
    local component_hashes = {}
    local component_names = {}
    local components, order = Weapons.get_weapon_components()
    for _, component in ipairs(order) do
        local component_hash = GetHashKey(component)
        if DoesWeaponTakeWeaponComponent(weapon_hash, component_hash) then
            local component_name = components[component]
            if component_hashes[component_name] == nil then
                component_hashes[component_name] = component_hash
                component_names[#component_names + 1] = component_name
            end
        end
    end
    return component_hashes, component_names
end

-- ValidWeapons.WeaponList: every known weapon except weapon_unarmed, with
-- hash, localized name, permission, and accepted components.
local weapons_list = nil

function Weapons.weapon_list()
    if weapons_list ~= nil then
        return weapons_list
    end
    weapons_list = {}
    for _, spawn_name in ipairs(Data.weapon_names_order) do
        if spawn_name ~= 'weapon_unarmed' then
            local hash = GetHashKey(spawn_name)
            local components, component_names = components_for(hash)
            weapons_list[#weapons_list + 1] = {
                hash = hash,
                spawn_name = spawn_name,
                name = Data.weapon_names[spawn_name],
                components = components,
                component_names = component_names,
                perm = Data.weapon_permissions[spawn_name],
                current_ammo = 0,
                current_tint = 0,
            }
        end
    end
    return weapons_list
end

-- ValidAddonWeapons.AddonWeaponsList: addon weapons from config/addons.json,
-- localized via GetLabelText, all behind the WPSpawn permission.
local addon_weapons_list = nil

function Weapons.addon_weapon_list()
    if addon_weapons_list ~= nil then
        return addon_weapons_list
    end
    addon_weapons_list = {}
    local addons = LoadResourceFile(GetCurrentResourceName(), 'config/addons.json') or '{}'
    local decoded = Json.decode(addons)
    if decoded == nil or type(decoded.weapons) ~= 'table' then
        return addon_weapons_list
    end
    for _, spawn_name in ipairs(decoded.weapons) do
        if spawn_name ~= 'weapon_unarmed' then
            local hash = GetHashKey(spawn_name)
            local components, component_names = components_for(hash)
            addon_weapons_list[#addon_weapons_list + 1] = {
                hash = hash,
                spawn_name = spawn_name,
                name = GetLabelText(spawn_name),
                components = components,
                component_names = component_names,
                perm = 'WPSpawn',
                current_ammo = 0,
                current_tint = 0,
            }
        end
    end
    return addon_weapons_list
end

-- ValidWeapon.GetMaxAmmo (CfxLua appends the native's out-param to returns).
function Weapons.get_max_ammo(weapon_hash)
    local _, ammo = GetMaxAmmo(PlayerPedId(), weapon_hash)
    return ammo or 0
end

-- ValidWeapon.Accuracy/Damage/Range/Speed come from GetWeaponHudStats, a
-- struct-pointer native CfxLua can't marshal directly. Wired up during the
-- M8 in-game pass (Citizen.InvokeNative + DataView buffer); until then the
-- weapon stat panels draw zeroed bars.
function Weapons.get_hud_stats(_weapon_hash)
    return { accuracy = 0.0, damage = 0.0, range = 0.0, speed = 0.0 }
end

-- ---------------------------------------------------------------------------
-- Weapon loadouts (vmenu_string_saved_weapon_loadout_ KVPs)
-- ---------------------------------------------------------------------------

-- The loadout JSON is a C# List<ValidWeapon>: PascalCase keys, Perm as the
-- Permission enum ordinal, and the serialize-only readonly stats included
-- (docs/contracts/kvp-saves.md + tests/fixtures/weapon_loadout.json).

local perm_numbers = nil -- [name] = 0-based enum ordinal

local function perm_to_number(name)
    if perm_numbers == nil then
        local Permissions = require('shared.permissions')
        perm_numbers = {}
        for i, permission in ipairs(Permissions.list) do
            perm_numbers[permission] = i - 1
        end
    end
    return perm_numbers[name] or 0
end

local function number_to_perm(number)
    local Permissions = require('shared.permissions')
    return Permissions.list[(math.tointeger(tonumber(number)) or 0) + 1]
end

Weapons.perm_to_number = perm_to_number
Weapons.number_to_perm = number_to_perm

-- GetSavedWeaponLoadout: decoded list, {} when missing/corrupt. Names get
-- the loadout prefix added unless it's the temp respawn save.
function Weapons.get_saved_weapon_loadout(save_name)
    local key = save_name
    if save_name ~= 'vmenu_temp_weapons_loadout_before_respawn' then
        if save_name:sub(1, 34) ~= 'vmenu_string_saved_weapon_loadout_' then
            key = 'vmenu_string_saved_weapon_loadout_' .. save_name
        end
    end
    local kvp = GetResourceKvpString(key)
    if kvp == nil or kvp == '' then
        return {}
    end
    return Json.decode(kvp) or {}
end

-- GetSavedWeapons: every saved loadout, keyed by the full kvp name.
function Weapons.get_saved_weapons()
    local saves = {}
    local handle = StartFindKvp('vmenu_string_saved_weapon_loadout_')
    while true do
        local kvp = FindKvp(handle)
        if kvp == nil or kvp == '' then
            break
        end
        saves[kvp] = Json.decode(GetResourceKvpString(kvp)) or {}
    end
    EndFindKvp(handle)
    return saves
end

-- One serialized ValidWeapon entry for the ped's copy of this weapon.
local function capture_weapon(ped, weapon, components)
    local entry = {
        Hash = weapon.hash,
        Name = weapon.name,
        Components = {},
        Perm = perm_to_number(weapon.perm),
        SpawnName = weapon.spawn_name,
        GetMaxAmmo = Weapons.get_max_ammo(weapon.hash),
        CurrentAmmo = GetAmmoInPedWeapon(ped, weapon.hash),
        CurrentTint = GetPedWeaponTintIndex(ped, weapon.hash),
        -- Serialize-only stats (ignored on load by both implementations).
        Accuracy = 0.0,
        Damage = 0.0,
        Range = 0.0,
        Speed = 0.0,
    }
    for component_name, component_hash in pairs(components or {}) do
        if
            DoesWeaponTakeWeaponComponent(weapon.hash, component_hash)
            and HasPedGotWeaponComponent(ped, weapon.hash, component_hash)
        then
            entry.Components[component_name] = component_hash
        end
    end
    return entry
end

-- SaveWeaponLoadout: captures every weapon (incl. addons) the ped carries.
function Weapons.save_weapon_loadout(save_name)
    if save_name == nil or save_name == '' then
        return false
    end
    local ped = PlayerPedId()
    local ped_weapons = {}

    for _, weapon in ipairs(Weapons.weapon_list()) do
        if HasPedGotWeapon(ped, weapon.hash, false) then
            ped_weapons[#ped_weapons + 1] = capture_weapon(ped, weapon, weapon.components)
        end
    end
    for _, weapon in ipairs(Weapons.addon_weapon_list()) do
        if HasPedGotWeapon(ped, weapon.hash, false) then
            ped_weapons[#ped_weapons + 1] = capture_weapon(ped, weapon, weapon.components)
        end
    end

    local json = #ped_weapons == 0 and '[]' or Json.encode(ped_weapons)
    SetResourceKvp(save_name, json)
    return (GetResourceKvpString(save_name) or '{}') == json
end

-- SpawnWeaponLoadoutAsync: equips a saved loadout. The special
-- vmenu_temp_weapons_loadout_before_respawn save routes through the default
-- loadout / restore-weapons settings unless ignore_settings_and_perms.
function Weapons.spawn_weapon_loadout(save_name, append_weapons, ignore_settings_and_perms, dont_notify)
    local Permissions = require('shared.permissions')
    local State = require('client.state')
    local Notification = require('client.notify')
    local ped = PlayerPedId()

    local loadout = Weapons.get_saved_weapon_loadout(save_name)

    if not ignore_settings_and_perms and save_name == 'vmenu_temp_weapons_loadout_before_respawn' then
        local name = GetResourceKvpString('vmenu_string_default_loadout') or save_name
        local kvp = GetResourceKvpString(name) or GetResourceKvpString('vmenu_temp_weapons_loadout_before_respawn')

        local loadouts_menu = State.menus.weapon_loadouts
        if
            loadouts_menu == nil
            or not loadouts_menu.WeaponLoadoutsSetLoadoutOnRespawn
            or not Permissions.is_allowed('WLEquipOnRespawn')
        then
            kvp = GetResourceKvpString('vmenu_temp_weapons_loadout_before_respawn')
            -- Upstream empties the loadout here when normal weapon
            -- restoring is also off, but the kvp branch below overwrites it
            -- unconditionally anyway — dead store dropped, behavior kept.
        end

        if kvp == nil or kvp == '' then
            loadout = {}
        else
            loadout = Json.decode(kvp) or {}
        end
    end

    if #loadout == 0 then
        return
    end

    if not append_weapons then
        RemoveAllPedWeapons(ped, true)
    end

    if not ignore_settings_and_perms then
        for _, w in ipairs(loadout) do
            if not Permissions.is_allowed(number_to_perm(w.Perm)) then
                Notification.Notify.alert(
                    'One or more weapon(s) in this saved loadout are not allowed on this server. '
                        .. 'Those weapons will not be loaded.'
                )
                break
            end
        end
    end

    for _, w in ipairs(loadout) do
        -- Skip weapons no longer present in the game files (e.g. removed
        -- addon resources).
        if not IsWeaponValid(w.Hash) then
            Util.debug_log(
                ('Skipping weapon %s (%s) - not valid in current game files.'):format(
                    tostring(w.SpawnName),
                    tostring(w.Hash)
                )
            )
        elseif ignore_settings_and_perms or Permissions.is_allowed(number_to_perm(w.Perm)) then
            local max_ammo = Weapons.get_max_ammo(w.Hash)
            GiveWeaponToPed(ped, w.Hash, (w.CurrentAmmo or -1) > -1 and w.CurrentAmmo or max_ammo, false, false)

            for _, component_hash in pairs(w.Components or {}) do
                if DoesWeaponTakeWeaponComponent(w.Hash, component_hash) then
                    GiveWeaponComponentToPed(ped, w.Hash, component_hash)
                    local timer = GetGameTimer()
                    while not HasPedGotWeaponComponent(ped, w.Hash, component_hash) do
                        Wait(0)
                        if GetGameTimer() - timer > 1000 then
                            break
                        end
                    end
                end
            end

            SetPedWeaponTintIndex(ped, w.Hash, w.CurrentTint or 0)

            if (w.CurrentAmmo or 0) > 0 then
                local ammo = w.CurrentAmmo
                if ammo > max_ammo then
                    ammo = max_ammo
                end
                local do_it = false
                while GetAmmoInPedWeapon(ped, w.Hash) ~= ammo and w.CurrentAmmo ~= -1 do
                    if do_it then
                        SetCurrentPedWeapon(ped, w.Hash, true)
                    end
                    do_it = true
                    local ammo_in_clip = GetMaxAmmoInClip(ped, w.Hash, false)
                    if ammo_in_clip > ammo then
                        ammo_in_clip = ammo
                    end
                    SetAmmoInClip(ped, w.Hash, ammo_in_clip)
                    SetPedAmmo(ped, w.Hash, ammo > -1 and ammo or max_ammo)
                    Wait(0)
                end
            end
        end
    end

    SetCurrentPedWeapon(ped, GetHashKey('weapon_unarmed'), true)

    if not (save_name == 'vmenu_temp_weapons_loadout_before_respawn' or dont_notify) then
        Notification.Notify.success('Weapon loadout spawned.')
    end
end

-- Test hook: caches depend on config files and game natives.
function Weapons._reset()
    components_cache = nil
    components_order_cache = nil
    weapons_list = nil
    addon_weapons_list = nil
    perm_numbers = nil
end

return Weapons
