-- Port of SharedClasses/ConfigManager.cs.
-- All server settings are convars (set in permissions.cfg with setr).
-- Contract: docs/contracts/convars.md; names, defaults, and coercion rules
-- must match upstream exactly so existing server configs keep working.

local Config = {}

-- Mirror of the C# ConfigManager.Setting enum (upstream @ 49e53065).
-- Order preserved. Note: keep_player_head_props really has no vmenu_ prefix upstream.
Config.settings = {
    -- General settings
    'vmenu_use_permissions',
    'vmenu_menu_staff_only',
    'vmenu_menu_toggle_key',
    'vmenu_noclip_toggle_key',
    'vmenu_keep_spawned_vehicles_persistent',
    'vmenu_use_els_compatibility_mode',
    'vmenu_handle_invisibility',
    'vmenu_quit_session_in_rockstar_editor',
    'vmenu_server_info_message',
    'vmenu_server_info_website_url',
    'vmenu_teleport_to_wp_keybind_key',
    'vmenu_disable_spawning_as_default_character',
    'vmenu_enable_animals_spawn_menu',
    'vmenu_pvp_mode',
    'keep_player_head_props',
    'vmenu_player_names_distance',
    'vmenu_disable_entity_outlines_tool',
    'vmenu_disable_player_stats_setup',
    -- Vehicle settings
    'vmenu_using_chameleon_colours',
    'vmenu_vehicle_spawn_delay',
    'vmenu_delete_vehicle_distance',
    -- Prevent extras abuse
    'vmenu_prevent_extras_when_damaged',
    'vmenu_allowed_engine_damage_for_extra_change',
    'vmenu_allowed_body_damage_for_extra_change',
    -- MP ped preview
    'vmenu_mp_ped_preview',
    -- Kick & ban settings
    'vmenu_default_ban_message_information',
    'vmenu_auto_ban_cheaters',
    'vmenu_auto_ban_cheaters_ban_message',
    'vmenu_log_ban_actions',
    'vmenu_log_kick_actions',
    -- Weather settings
    'vmenu_enable_weather_sync',
    'vmenu_enable_dynamic_weather',
    'vmenu_dynamic_weather_timer',
    'vmenu_current_weather',
    'vmenu_blackout_enabled',
    'vmenu_vehicle_blackout_enabled',
    'vmenu_weather_change_duration',
    'vmenu_enable_snow',
    'vmenu_smooth_time_transitions',
    -- Time settings
    'vmenu_enable_time_sync',
    'vmenu_freeze_time',
    'vmenu_ingame_minute_duration',
    'vmenu_current_hour',
    'vmenu_current_minute',
    'vmenu_sync_to_machine_time',
    -- Voice chat settings
    'vmenu_override_voicechat_default_range',
    -- Key mapping
    'vmenu_keymapping_id',
}

-- int.TryParse semantics: optional surrounding whitespace, optional sign,
-- decimal digits only (no hex, no fractions, no exponents).
local function parse_csharp_int(value)
    local digits = tostring(value):match('^%s*([%+%-]?%d+)%s*$')
    if not digits then
        return nil
    end
    return math.tointeger(tonumber(digits))
end

-- GetSettingsBool: unset, garbage, and anything but the literal "true" are false.
function Config.get_bool(setting)
    return GetConvar(setting, 'false') == 'true'
end

-- GetSettingsInt keeps upstream's quirk: when GetConvarInt comes back as the
-- default, re-read the convar as a string and int-parse it; only if that also
-- fails do we return GetConvarInt's answer.
function Config.get_int(setting, default)
    default = default or -1
    local convar_int = GetConvarInt(setting, default)
    if convar_int == default then
        local parsed = parse_csharp_int(GetConvar(setting, tostring(default)))
        if parsed then
            return parsed
        end
    end
    return convar_int
end

-- GetSettingsFloat: parse the string form; on failure return the default.
function Config.get_float(setting, default)
    default = default or -1.0
    local value = tonumber(GetConvar(setting, tostring(default)))
    if value then
        return value + 0.0
    end
    return default
end

-- GetSettingsString: empty and unset both collapse to nil (C# returns null).
function Config.get_string(setting, default)
    local value = GetConvar(setting, default or '')
    if value == nil or value == '' then
        return nil
    end
    return value
end

-- Port of ConfigManager.GetLocations: reads config/locations.json with the
-- contract's error tolerance: missing/empty/corrupt input degrades to empty
-- lists plus an error string for the caller to surface (client notifies,
-- server logs; this shared module does neither).
function Config.get_locations()
    local locations = { teleports = {}, blips = {} }

    local raw = LoadResourceFile(GetCurrentResourceName(), 'config/locations.json')
    if raw == nil or raw == '' then
        return locations, 'The locations.json file is empty or does not exist.'
    end

    local Json = require('shared.json_compat')
    local decoded = Json.decode(raw)
    if decoded == nil then
        return locations, 'An error occurred while processing the locations.json file.'
    end

    locations.teleports = decoded.teleports or {}
    locations.blips = decoded.blips or {}
    return locations, nil
end

function Config.get_teleport_locations()
    local locations, err = Config.get_locations()
    return locations.teleports, err
end

function Config.get_location_blips()
    local locations, err = Config.get_locations()
    return locations.blips, err
end

return Config
