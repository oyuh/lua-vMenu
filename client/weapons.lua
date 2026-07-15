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
-- for every component the game says this weapon accepts.
local function components_for(weapon_hash)
    local component_hashes = {}
    local components, order = Weapons.get_weapon_components()
    for _, component in ipairs(order) do
        local component_hash = GetHashKey(component)
        if DoesWeaponTakeWeaponComponent(weapon_hash, component_hash) then
            local component_name = components[component]
            if component_hashes[component_name] == nil then
                component_hashes[component_name] = component_hash
            end
        end
    end
    return component_hashes
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
            weapons_list[#weapons_list + 1] = {
                hash = hash,
                spawn_name = spawn_name,
                name = Data.weapon_names[spawn_name],
                components = components_for(hash),
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
            addon_weapons_list[#addon_weapons_list + 1] = {
                hash = hash,
                spawn_name = spawn_name,
                name = GetLabelText(spawn_name),
                components = components_for(hash),
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

-- Test hook: caches depend on config files and game natives.
function Weapons._reset()
    components_cache = nil
    components_order_cache = nil
    weapons_list = nil
    addon_weapons_list = nil
end

return Weapons
