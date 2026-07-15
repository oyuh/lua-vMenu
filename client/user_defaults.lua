-- Port of vMenu/UserDefaults.cs: per-player persisted preferences under the
-- settings_ KVP prefix. Compatibility rules (docs/contracts/kvp-saves.md):
--   * bools are stored as the strings "True"/"False" (C# bool.ToString()),
--     read back case-insensitively
--   * ints and floats use the typed KVP natives (SetResourceKvpInt/Float)
--   * a fixed set of settings defaults to true and is written back on first
--     read, exactly like GetSettingsBool upstream
--
-- Callers use the raw camelCase KVP keys ("playerGodMode", "miscSpeedoKmh",
-- "autoEquipParachuteWhenInPlane", ...). The C# property names differ from a
-- few keys (MiscSpeedKmh → miscSpeedoKmh, AutoEquipChute →
-- autoEquipParachuteWhenInPlane, ShowCurrentSpeaker → voiceChatShowSpeaker,
-- PAClothingAnimationType → clothingAnimationType); menus port against the
-- key, not the property.
--
-- UserDefaults.SaveSettings() (the "Save Personal Settings" button) lands
-- with the MiscSettings menu in M7 — it just writes these same keys.

local UserDefaults = {}

local SETTINGS_PREFIX = 'settings_'

-- Settings that are enabled by default (GetSettingsBool's hardcoded list).
local DEFAULT_TRUE = {
    unlimitedStamina = true,
    miscDeathNotifications = true,
    miscJoinQuitNotifications = true,
    vehicleSpawnerSpawnInside = true,
    vehicleSpawnerReplacePrevious = true,
    neverWanted = true,
    voiceChatShowSpeaker = true,
    voiceChatEnabled = true,
    autoEquipParachuteWhenInPlane = true,
    miscRestorePlayerAppearance = true,
    miscRestorePlayerWeapons = true,
    miscRightAlignMenu = true,
    miscRespawnDefaultCharacter = true,
    vehicleGodInvincible = true,
    vehicleGodEngine = true,
    vehicleGodVisual = true,
    vehicleGodStrongWheels = true,
    vehicleGodRamp = true,
    mpPedPreviews = true,
}

function UserDefaults.set_bool(key, value)
    -- C# bool.ToString(): "True"/"False" with capital first letter.
    SetResourceKvp(SETTINGS_PREFIX .. key, value and 'True' or 'False')
end

function UserDefaults.get_bool(key)
    local saved = GetResourceKvpString(SETTINGS_PREFIX .. key)
    if saved == nil or saved == '' then
        -- First read: persist and return the default.
        local default = DEFAULT_TRUE[key] == true
        UserDefaults.set_bool(key, default)
        return default
    end
    return saved:lower() == 'true'
end

function UserDefaults.get_int(key)
    return GetResourceKvpInt(SETTINGS_PREFIX .. key)
end

function UserDefaults.set_int(key, value)
    SetResourceKvpInt(SETTINGS_PREFIX .. key, value)
end

function UserDefaults.get_float(key)
    return GetResourceKvpFloat(SETTINGS_PREFIX .. key)
end

function UserDefaults.set_float(key, value)
    SetResourceKvpFloat(SETTINGS_PREFIX .. key, value)
end

return UserDefaults
