-- Port of vMenu/StorageManager.cs: the client KVP save/load layer for peds
-- (ped_*), vehicles (veh_*), MP characters (mp_ped_*), and category records.
-- The JSON shapes are Newtonsoft-compatible per docs/contracts/kvp-saves.md,
-- so saves created by the C# vMenu load here unchanged (and vice versa).

local Json = require('shared.json_compat')
local Util = require('shared.util')

local Storage = {}

local function log(message)
    Util.debug_log(message)
end

local function kvp_string(name)
    local value = GetResourceKvpString(name)
    if value == '' then
        return nil
    end
    return value
end

local function find_keys(prefix)
    local handle = StartFindKvp(prefix)
    local keys = {}
    while true do
        local key = FindKvp(handle)
        if key == nil or key == '' then
            break
        end
        keys[#keys + 1] = key
    end
    EndFindKvp(handle)
    return keys
end

-- SaveJsonData: writes raw json under saveName; refuses to overwrite unless
-- allowed; verifies the write like upstream.
function Storage.save_json_data(save_name, json_data, override_existing_data)
    if save_name == nil or save_name == '' or json_data == nil or json_data == '' then
        return false
    end
    local existing = kvp_string(save_name)
    if existing ~= nil and not override_existing_data then
        return false
    end
    SetResourceKvp(save_name, json_data)
    return (GetResourceKvpString(save_name) or '') == json_data
end

-- GetJsonData: raw json or nil.
function Storage.get_json_data(save_name)
    if save_name == nil or save_name == '' then
        return nil
    end
    return kvp_string(save_name)
end

-- DeleteSavedStorageItem.
function Storage.delete_saved_storage_item(save_name)
    DeleteResourceKvp(save_name)
end

-- SaveDictionary (legacy string-dictionary saves).
function Storage.save_dictionary(save_name, data, override_existing_data)
    if GetResourceKvpString(save_name) == nil or override_existing_data then
        local json_string = Json.encode(data)
        log(('Saving: [name: %s, json:%s]'):format(save_name, json_string))
        SetResourceKvp(save_name, json_string)
        return GetResourceKvpString(save_name) == json_string
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Peds (ped_ prefix, PedInfo records)
-- ---------------------------------------------------------------------------

-- GetSavedPeds: { [full kvp name] = PedInfo }.
function Storage.get_saved_peds()
    local saved_peds = {}
    for _, key in ipairs(find_keys('ped_')) do
        local decoded = Json.decode(GetResourceKvpString(key))
        if decoded then
            saved_peds[key] = decoded
        end
    end
    return saved_peds
end

-- GetSavedPedInfo (name includes the ped_ prefix).
function Storage.get_saved_ped_info(name)
    return Json.decode(GetResourceKvpString(name))
end

-- SavePedInfo.
function Storage.save_ped_info(save_name, ped_data, override_existing)
    if override_existing or kvp_string(save_name) == nil then
        local json = Json.encode(ped_data)
        SetResourceKvp(save_name, json)
        return GetResourceKvpString(save_name) == json
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Vehicles (veh_ prefix, VehicleInfo records)
-- ---------------------------------------------------------------------------

-- SaveVehicleInfo: save name must include the "veh_" prefix and have an
-- actual name after it (upstream's length > 4 check).
function Storage.save_vehicle_info(save_name, vehicle_info, override_old_version)
    if kvp_string(save_name) == nil or override_old_version then
        if save_name ~= nil and #save_name > 4 then
            local json = Json.encode(vehicle_info)
            log(('[vMenu] Saving!\nName: %s\nVehicle Data: %s\n'):format(save_name, json))
            SetResourceKvp(save_name, json)
            return GetResourceKvpString(save_name) == json
        end
    end
    return false
end

-- GetSavedVehicleInfo (name includes "veh_").
function Storage.get_saved_vehicle_info(save_name)
    return Json.decode(GetResourceKvpString(save_name))
end

-- ---------------------------------------------------------------------------
-- MP characters (mp_ped_ prefix, MultiplayerPedData records)
-- ---------------------------------------------------------------------------

-- GetSavedMpCharacterData: tolerates names with or without the prefix;
-- returns an empty table (upstream: empty struct) when missing or corrupt.
function Storage.get_saved_mp_character_data(name)
    if name == nil or name == '' then
        return {}
    end
    local key = name:sub(1, 7) == 'mp_ped_' and name or ('mp_ped_' .. name)
    local json_string = kvp_string(key)
    if json_string == nil then
        return {}
    end
    local decoded = Json.decode(json_string)
    if decoded == nil then
        return {}
    end
    log(json_string)
    return decoded
end

-- GetSavedMpPeds: list sorted case-insensitively by SaveName.
function Storage.get_saved_mp_peds()
    local peds = {}
    for _, key in ipairs(find_keys('mp_ped_')) do
        peds[#peds + 1] = Storage.get_saved_mp_character_data(key)
    end
    table.sort(peds, function(a, b)
        return tostring(a.SaveName or ''):lower() < tostring(b.SaveName or ''):lower()
    end)
    return peds
end

-- ---------------------------------------------------------------------------
-- Category records (menus organize saves into categories)
-- ---------------------------------------------------------------------------

local function get_prefixed_record(name, prefix)
    if name == nil or name == '' then
        return {}
    end
    local key = name:sub(1, #prefix) == prefix and name or (prefix .. name)
    local json_string = kvp_string(key)
    if json_string == nil then
        return {}
    end
    local decoded = Json.decode(json_string)
    if decoded == nil then
        return {}
    end
    log(json_string)
    return decoded
end

-- GetSavedMpCharacterCategoryData.
function Storage.get_saved_mp_character_category_data(name)
    return get_prefixed_record(name, 'mp_character_category_')
end

-- GetSavedVehicleCategoryData.
function Storage.get_saved_vehicle_category_data(name)
    return get_prefixed_record(name, 'saved_veh_category_')
end

return Storage
