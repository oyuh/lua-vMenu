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

-- SaveSettings ("Save Personal Settings"): reads the public fields off every
-- created menu instance and persists them. Menus not ported/created yet are
-- skipped, exactly like upstream's null checks.
function UserDefaults.save_settings()
    local State = require('client.state')
    local Notification = require('client.notify')

    local player_options = State.menus.player_options
    if player_options ~= nil then
        UserDefaults.set_bool('everyoneIgnorePlayer', player_options.PlayerIsIgnored)
        UserDefaults.set_bool('fastRun', player_options.PlayerFastRun)
        UserDefaults.set_bool('fastSwim', player_options.PlayerFastSwim)
        UserDefaults.set_bool('neverWanted', player_options.PlayerNeverWanted)
        UserDefaults.set_bool('noRagdoll', player_options.PlayerNoRagdoll)
        UserDefaults.set_bool('playerGodMode', player_options.PlayerGodMode)
        UserDefaults.set_bool('playerStayInVehicle', player_options.PlayerStayInVehicle)
        UserDefaults.set_bool('superJump', player_options.PlayerSuperJump)
        UserDefaults.set_bool('unlimitedStamina', player_options.PlayerStamina)
    end

    local misc = State.menus.misc_settings
    if misc ~= nil then
        UserDefaults.set_bool('miscDeathNotifications', misc.DeathNotifications)
        UserDefaults.set_bool('miscJoinQuitNotifications', misc.JoinQuitNotifications)
        UserDefaults.set_bool('miscSpeedoKmh', misc.ShowSpeedoKmh)
        UserDefaults.set_bool('miscSpeedoMph', misc.ShowSpeedoMph)
        UserDefaults.set_bool('miscShowLocation', misc.ShowLocation)
        UserDefaults.set_bool('miscLocationBlips', misc.ShowLocationBlips)
        UserDefaults.set_bool('miscShowPlayerBlips', misc.ShowPlayerBlips)
        UserDefaults.set_bool('miscShowOverheadNames', misc.MiscShowOverheadNames)
        UserDefaults.set_bool('miscRespawnDefaultCharacter', misc.MiscRespawnDefaultCharacter)
        UserDefaults.set_bool('miscRestorePlayerAppearance', misc.RestorePlayerAppearance)
        UserDefaults.set_bool('miscRestorePlayerWeapons', misc.RestorePlayerWeapons)
        UserDefaults.set_bool('miscShowTime', misc.DrawTimeOnScreen)
        UserDefaults.set_bool('miscRightAlignMenu', misc.MiscRightAlignMenu)
        UserDefaults.set_bool('miscDisablePrivateMessages', misc.MiscDisablePrivateMessages)
        UserDefaults.set_bool('miscDisableControllerSupport', misc.MiscDisableControllerSupport)
        UserDefaults.set_bool('kbTpToWaypoint', misc.KbTpToWaypoint)
        UserDefaults.set_bool('kbDriftMode', misc.KbDriftMode)
        UserDefaults.set_bool('kbRecordKeys', misc.KbRecordKeys)
        UserDefaults.set_bool('kbRadarKeys', misc.KbRadarKeys)
        UserDefaults.set_bool('kbPointKeys', misc.KbPointKeys)
        UserDefaults.set_bool('mpPedPreviews', misc.MPPedPreviews)
    end

    local vehicle_options = State.menus.vehicle_options
    if vehicle_options ~= nil then
        UserDefaults.set_bool('vehicleEngineAlwaysOn', vehicle_options.VehicleEngineAlwaysOn)
        UserDefaults.set_bool('vehicleGodMode', vehicle_options.VehicleGodMode)
        UserDefaults.set_bool('vehicleGodInvincible', vehicle_options.VehicleGodInvincible)
        UserDefaults.set_bool('vehicleGodEngine', vehicle_options.VehicleGodEngine)
        UserDefaults.set_bool('vehicleGodVisual', vehicle_options.VehicleGodVisual)
        UserDefaults.set_bool('vehicleGodStrongWheels', vehicle_options.VehicleGodStrongWheels)
        UserDefaults.set_bool('vehicleGodRamp', vehicle_options.VehicleGodRamp)
        UserDefaults.set_bool('vehicleGodAutoRepair', vehicle_options.VehicleGodAutoRepair)
        UserDefaults.set_bool('vehicleNeverDirty', vehicle_options.VehicleNeverDirty)
        UserDefaults.set_bool('vehicleNoBikeHelmet', vehicle_options.VehicleNoBikeHelemet)
        UserDefaults.set_bool('vehicleNoSiren', vehicle_options.VehicleNoSiren)
        UserDefaults.set_bool('vehicleHighbeamsOnHonk', vehicle_options.FlashHighbeamsOnHonk)
        UserDefaults.set_bool('vehicleDisablePlaneTurbulence', vehicle_options.DisablePlaneTurbulence)
        UserDefaults.set_bool('vehicleDisableHelicopterTurbulence', vehicle_options.DisableHelicopterTurbulence)
        UserDefaults.set_bool('vehicleAnchorBoat', vehicle_options.AnchorBoat)
        UserDefaults.set_bool('vehicleBikeSeatbelt', vehicle_options.VehicleBikeSeatbelt)
    end

    local vehicle_spawner = State.menus.vehicle_spawner
    if vehicle_spawner ~= nil then
        UserDefaults.set_bool('vehicleSpawnerReplacePrevious', vehicle_spawner.ReplaceVehicle)
        UserDefaults.set_bool('vehicleSpawnerSpawnInside', vehicle_spawner.SpawnInVehicle)
    end

    local voice_chat = State.menus.voice_chat
    if voice_chat ~= nil then
        UserDefaults.set_bool('voiceChatEnabled', voice_chat.EnableVoicechat)
        UserDefaults.set_float('voiceChatProximity', voice_chat.currentProximity)
        UserDefaults.set_bool('voiceChatShowSpeaker', voice_chat.ShowCurrentSpeaker)
        UserDefaults.set_bool('voiceChatShowVoiceStatus', voice_chat.ShowVoiceStatus)
    end

    local weapon_options = State.menus.weapon_options
    if weapon_options ~= nil then
        UserDefaults.set_bool('weaponsNoReload', weapon_options.NoReload)
        UserDefaults.set_bool('weaponsUnlimitedAmmo', weapon_options.UnlimitedAmmo)
        UserDefaults.set_bool('weaponsUnlimitedParachutes', weapon_options.UnlimitedParachutes)
        UserDefaults.set_bool('autoEquipParachuteWhenInPlane', weapon_options.AutoEquipChute)
    end

    local player_appearance = State.menus.player_appearance
    if player_appearance ~= nil and (player_appearance.ClothingAnimationType or -1) >= 0 then
        UserDefaults.set_int('clothingAnimationType', player_appearance.ClothingAnimationType)
    end

    local weapon_loadouts = State.menus.weapon_loadouts
    if weapon_loadouts ~= nil then
        UserDefaults.set_bool('weaponLoadoutsSetLoadoutOnRespawn', weapon_loadouts.WeaponLoadoutsSetLoadoutOnRespawn)
    end

    local personal_vehicle = State.menus.personal_vehicle
    if personal_vehicle ~= nil then
        UserDefaults.set_bool('pvEnableVehicleBlip', personal_vehicle.EnableVehicleBlip)
    end

    Notification.Notify.success('Your settings have been saved.')
end

return UserDefaults
