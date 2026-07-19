-- Port of vMenu/EventManager.cs: every client-side event handler plus the
-- weather/time sync ticks. Contract: docs/contracts/events.md; names and
-- payloads are fixed.

local Config = require('shared.config')
local Json = require('shared.json_compat')
local Util = require('shared.util')
local State = require('client.state')
local Notification = require('client.notify')
local Common = require('client.common')

local Events = {}

-- Convar-backed properties (EventManager's static getters).
local function is_snow_enabled()
    return Config.get_bool('vmenu_enable_snow')
end

local function clamp(value, min, max)
    if value < min then
        return min
    elseif value > max then
        return max
    end
    return value
end

local function server_minutes()
    return clamp(Config.get_int('vmenu_current_minute'), 0, 59)
end

local function server_hours()
    return clamp(Config.get_int('vmenu_current_hour'), 0, 23)
end

local function server_weather()
    return Config.get_string('vmenu_current_weather', 'CLEAR') or 'CLEAR'
end

local function weather_change_time()
    return clamp(Config.get_int('vmenu_weather_change_duration'), 0, 45)
end

-- ---------------------------------------------------------------------------
-- Config options (addons.json / model-whitelists.json / extras.json /
-- tattoos.json), parsed into client/state.lua for the menus.
-- ---------------------------------------------------------------------------

local function config_error(file_name)
    print(
        ('\n\n^1[vMenu] [ERROR] ^7Your %s file contains a problem! Error details: invalid JSON\n\n'):format(file_name)
    )
end

local function load_json_config(path, default)
    local raw = LoadResourceFile(GetCurrentResourceName(), path) or default
    local decoded = Json.decode(raw)
    if decoded == nil then
        config_error(path:match('([^/]+)$'))
    end
    return decoded
end

-- SetAddons: model names → hashes, with duplicate warnings.
local function fill_hash_map(target, names, file_name, kind)
    for _, name in ipairs(names or {}) do
        if target[name] == nil then
            target[name] = GetHashKey(name)
        else
            print(
                (
                    '[vMenu] [Error] Your %s file contains 2 or more entries with the same %s name! (%s) '
                    .. 'Please remove duplicate lines!'
                ):format(file_name, kind, name)
            )
        end
    end
end

local function set_addons()
    State.addon_vehicles = {}
    State.addon_weapons = {}
    State.addon_peds = {}
    State.extra_blendable_faces = {}

    local addons = load_json_config('config/addons.json', '{}')
    if addons == nil then
        return
    end
    fill_hash_map(State.addon_vehicles, addons.vehicles, 'addons.json', 'vehicle')
    fill_hash_map(State.addon_weapons, addons.weapons, 'addons.json', 'weapon')
    fill_hash_map(State.addon_peds, addons.peds, 'addons.json', 'ped')
    for _, face in ipairs(addons.extra_blendable_faces or {}) do
        local exists = false
        for _, existing in ipairs(State.extra_blendable_faces) do
            if existing == face then
                exists = true
            end
        end
        if not exists then
            State.extra_blendable_faces[#State.extra_blendable_faces + 1] = face
        else
            print(
                (
                    '[vMenu] [Error] Your addons.json file contains 2 or more entries with the same extra blendable '
                    .. 'face name! (%s) Please remove duplicate lines!'
                ):format(face)
            )
        end
    end
end

local function set_whitelists()
    State.whitelist_vehicles = {}
    State.whitelisted_peds = {}
    State.weapon_whitelist = {}

    local whitelists = load_json_config('config/model-whitelists.json', '{}')
    if whitelists == nil then
        return
    end
    fill_hash_map(State.whitelist_vehicles, whitelists.whitelistedvehicle, 'model-whitelists.json', 'vehicle')
    -- upstream reports "ped name" for both peds and weapons here; preserved
    fill_hash_map(State.whitelisted_peds, whitelists.whitelistedpeds, 'model-whitelists.json', 'ped')
    fill_hash_map(State.weapon_whitelist, whitelists.whitelistedweapons, 'model-whitelists.json', 'ped')
end

-- SetExtras: { [model name] = { [extra index string] = label } } → keyed by
-- model hash. (C# Dictionary<int,string> arrives string-keyed in JSON; kept
-- string-keyed per the json_compat contract.)
local function set_extras()
    State.vehicle_extras = {}

    local extras = load_json_config('config/extras.json', '{}')
    if extras == nil then
        return
    end
    for model, labels in pairs(extras) do
        local model_hash = GetHashKey(model)
        if type(labels) == 'table' and next(labels) ~= nil then
            if State.vehicle_extras[model_hash] == nil then
                State.vehicle_extras[model_hash] = labels
            else
                for extra, label in pairs(labels) do
                    if State.vehicle_extras[model_hash][extra] == nil then
                        State.vehicle_extras[model_hash][extra] = label
                    else
                        print(
                            (
                                '[vMenu] [Warning] Your extras.json file contains 2 or more entries with the same '
                                .. 'extra index! (%s, Extra %s) Please remove duplicate!'
                            ):format(model, extra)
                        )
                    end
                end
            end
        end
    end
end

local function set_tattoos()
    State.tattoos = {}

    local tattoos = load_json_config('config/tattoos.json', '[]')
    if tattoos == nil then
        return
    end
    for _, tattoo in ipairs(tattoos) do
        local exists = false
        for _, existing in ipairs(State.tattoos) do
            if existing.collectionName == tattoo.collectionName and existing.name == tattoo.name then
                exists = true
            end
        end
        if not exists then
            State.tattoos[#State.tattoos + 1] = tattoo
        else
            print(
                (
                    '[vMenu] [Error] Your tattoos.json file contains 2 or more entries with the same collection and '
                    .. 'tattoo names! (%s & %s) Please remove duplicate lines!'
                ):format(tostring(tattoo.collectionName), tostring(tattoo.name))
            )
        end
    end
end

local function set_config_options()
    set_addons()
    set_whitelists()
    set_extras()
    set_tattoos()
    State.config_options_setup_complete = true
end

Events.set_config_options = set_config_options

-- ---------------------------------------------------------------------------
-- Weather & time sync ticks
-- ---------------------------------------------------------------------------

-- UpdateWeatherParticles: snow fx assets on/off.
local function update_weather_particles()
    local snow = is_snow_enabled()
    ForceSnowPass(snow)
    SetForceVehicleTrails(snow)
    SetForcePedFootstepsTracks(snow)
    if snow then
        if not HasNamedPtfxAssetLoaded('core_snow') then
            RequestNamedPtfxAsset('core_snow')
            while not HasNamedPtfxAssetLoaded('core_snow') do
                Wait(0)
            end
        end
        UseParticleFxAssetNextCall('core_snow')
    else
        RemoveNamedPtfxAsset('core_snow')
    end
end

-- WeatherSync tick body; returns the delay before the next run.
local function weather_sync()
    update_weather_particles()
    SetArtificialLightsState(Config.get_bool('vmenu_blackout_enabled'))
    SetArtificialLightsStateAffectsVehicles(not Config.get_bool('vmenu_vehicle_blackout_enabled'))

    if GetNextWeatherType() ~= GetHashKey(server_weather()) then
        SetWeatherTypeOvertimePersist(server_weather(), weather_change_time() + 0.0)
        Wait(weather_change_time() * 1000 + 2000)
        TriggerEvent('vMenu:WeatherChangeComplete', server_weather())
    end
    return 1000
end

Events._weather_sync = weather_sync

-- TimeSync tick body; returns the delay before the next run.
local function time_sync()
    NetworkOverrideClockTime(server_hours(), server_minutes(), 0)
    if Config.get_bool('vmenu_freeze_time') or Config.get_bool('vmenu_sync_to_machine_time') then
        return 5
    end
    return clamp(Config.get_int('vmenu_ingame_minute_duration'), 100, 2000)
end

Events._time_sync = time_sync

-- ---------------------------------------------------------------------------
-- Registration (the EventManager constructor)
-- ---------------------------------------------------------------------------

-- opts carries the two handlers owned by client/main.lua (MainMenu.cs):
--   set_permissions(json), set_supplementary_permissions(json)
function Events.register(opts)
    opts = opts or {}

    -- DEPRECATED alias kept for third-party resources; same handler.
    RegisterNetEvent('vMenu:SetAddons', set_config_options)
    RegisterNetEvent('vMenu:SetConfigOptions', set_config_options)

    RegisterNetEvent('vMenu:SetPermissions', function(payload)
        if opts.set_permissions then
            opts.set_permissions(payload)
        end
    end)
    RegisterNetEvent('vMenu:SetSupplementaryPermissions', function(payload)
        if opts.set_supplementary_permissions then
            opts.set_supplementary_permissions(payload)
        end
    end)

    RegisterNetEvent('vMenu:KillMe', function(source_name)
        Notification.Notify.alert(
            ('You have been killed by <C>%s</C>~s~ using the ~r~Kill Player~s~ option in vMenu.'):format(
                Common.get_safe_player_name(source_name)
            )
        )
        SetEntityHealth(PlayerPedId(), 0)
    end)

    RegisterNetEvent('vMenu:Notify', function(message)
        Notification.Notify.custom(message, true, true)
    end)

    RegisterNetEvent('vMenu:SetClouds', function(opacity, clouds_type)
        if opacity == 0.0 and clouds_type == 'removed' then
            ClearCloudHat()
        else
            SetCloudHatOpacity(opacity)
            SetCloudHatTransition(clouds_type, 4.0)
        end
    end)

    RegisterNetEvent('vMenu:GoodBye', function()
        ForceSocialClubUpdate() -- used for cheaters
    end)

    RegisterNetEvent('vMenu:SetBanList', function(list)
        local banned_players = State.menus.banned_players
        if banned_players and banned_players.update_ban_list then
            banned_players.update_ban_list(list)
        end
    end)

    RegisterNetEvent('vMenu:ClearArea', function(position)
        ClearAreaOfEverything(position.x, position.y, position.z, 100.0, false, false, false, false)
    end)

    -- note the lowercase 'u'; exact casing is part of the event contract
    RegisterNetEvent('vMenu:updatePedDecors', function()
        local player_appearance = State.menus.player_appearance
        if player_appearance and player_appearance.refresh_clothing_animation then
            player_appearance.refresh_clothing_animation()
        end
    end)

    RegisterNetEvent('vMenu:PrivateMessage', function(source, message)
        Common.private_message(source, message, false)
    end)

    RegisterNetEvent('vMenu:UpdateTeleportLocations', function(json_data)
        State.teleport_locations = Json.decode(json_data) or {}
    end)

    -- First-spawn: restore the default MP character and weapon loadout.
    local first_spawn = true
    AddEventHandler('playerSpawned', function()
        if not first_spawn then
            return
        end
        first_spawn = false

        local mp_ped = State.menus.mp_ped_customization
        local misc = State.menus.misc_settings
        if
            misc ~= nil
            and mp_ped ~= nil
            and misc.MiscRespawnDefaultCharacter
            and (GetResourceKvpString('vmenu_default_character') or '') ~= ''
            and not Config.get_bool('vmenu_disable_spawning_as_default_character')
        then
            mp_ped.spawn_this_character(GetResourceKvpString('vmenu_default_character'), false)
        end
        while
            not IsScreenFadedIn()
            or IsPlayerSwitchInProgress()
            or IsPauseMenuActive()
            or GetIsLoadingScreenActive()
        do
            Wait(0)
        end
        local loadouts = State.menus.weapon_loadouts
        local Permissions = require('shared.permissions')
        if
            loadouts ~= nil
            and loadouts.WeaponLoadoutsSetLoadoutOnRespawn
            and Permissions.is_allowed('WLEquipOnRespawn')
        then
            local save_name = GetResourceKvpString('vmenu_string_default_loadout')
            if save_name ~= nil and save_name ~= '' then
                loadouts.spawn_weapon_loadout(save_name, true, false, true)
            end
        end
    end)

    -- Sync loops (gated on the same convars as the server's loops).
    if Config.get_bool('vmenu_enable_weather_sync') then
        CreateThread(function()
            while true do
                Wait(weather_sync())
            end
        end)
    end

    if Config.get_bool('vmenu_enable_time_sync') then
        CreateThread(function()
            while true do
                Wait(time_sync())
            end
        end)
    end

    Util.debug_log('event handlers registered')
end

return Events
