# Contract: convars

Source: `SharedClasses/ConfigManager.cs` + shipped `permissions.cfg` template (upstream @
`49e53065`). Implemented by `shared/config.lua`; the machine-readable list is
`Config.settings` (47 entries) with a spec asserting the count.

All settings are **replicated convars** (`setr`) read at runtime with `GetConvar*`. An existing
server config must behave identically, so the coercion rules are part of the contract:

| Accessor | Rule (must match C# exactly) |
|---|---|
| bool | `GetConvar(name, "false") == "true"`, so only the lowercase literal `true` counts |
| int | `GetConvarInt(name, default)`; if that returns the default, re-read as string and parse with `int.TryParse` semantics (optional sign, digits only, surrounding whitespace OK, **no fractions/hex**); on parse failure keep `GetConvarInt`'s answer. Default `-1` unless a call site passes one |
| float | parse `GetConvar(name, tostring(default))`; on failure use the default. Default `-1.0` |
| string | `GetConvar(name, default or "")`; empty or unset means **nil** (C# returns null) |

Debug modes are **not** convars: `client_debug_mode` / `server_debug_mode` are fxmanifest
metadata read via `GetResourceMetadata("vMenu", key, 0) == "true"` (case-insensitive compare).

## Settings and template defaults

Types are how the code reads them; "template default" is the value in the shipped
`permissions.cfg`. Where it says "(not in template)" the code default applies.

| Convar | Type | Template default |
|---|---|---|
| `vmenu_use_permissions` | bool | `true` |
| `vmenu_menu_staff_only` | bool | `false` |
| `vmenu_menu_toggle_key` | string (keyboard input id) | `"M"` |
| `vmenu_noclip_toggle_key` | string (keyboard input id) | `"F2"` |
| `vmenu_keymapping_id` | string (one word) | `"Default"` |
| `vmenu_keep_spawned_vehicles_persistent` | bool | `false` |
| `vmenu_use_els_compatibility_mode` | bool | `false` |
| `vmenu_handle_invisibility` | bool | `true` |
| `vmenu_quit_session_in_rockstar_editor` | bool | `false` |
| `vmenu_server_info_message` | string | vespura example text |
| `vmenu_server_info_website_url` | string | `"www.vespura.com"` |
| `vmenu_teleport_to_wp_keybind_key` | int (control id) | `168` |
| `vmenu_disable_spawning_as_default_character` | bool | `false` |
| `vmenu_enable_animals_spawn_menu` | bool | `false` |
| `vmenu_pvp_mode` | int (0/1/2) | `0` |
| `keep_player_head_props` | bool (no vmenu_ prefix!) | `true` |
| `vmenu_player_names_distance` | float | `500.0` |
| `vmenu_disable_entity_outlines_tool` | bool | `false` |
| `vmenu_disable_player_stats_setup` | bool | `false` |
| `vmenu_using_chameleon_colours` | bool | `false` |
| `vmenu_vehicle_spawn_delay` | int (seconds, default 5) | (not in template) |
| `vmenu_delete_vehicle_distance` | float | `5.0` |
| `vmenu_prevent_extras_when_damaged` | bool | `false` |
| `vmenu_allowed_engine_damage_for_extra_change` | int | `800` |
| `vmenu_allowed_body_damage_for_extra_change` | int | `800` |
| `vmenu_mp_ped_preview` | bool | `true` |
| `vmenu_default_ban_message_information` | string | appeal example text |
| `vmenu_auto_ban_cheaters` | bool | `false` |
| `vmenu_auto_ban_cheaters_ban_message` | string | example text |
| `vmenu_log_ban_actions` | bool | `true` |
| `vmenu_log_kick_actions` | bool | `true` |
| `vmenu_enable_weather_sync` | bool | `true` |
| `vmenu_enable_dynamic_weather` | bool | `true` |
| `vmenu_dynamic_weather_timer` | int (minutes) | `15` |
| `vmenu_current_weather` | string | `"clear"` |
| `vmenu_blackout_enabled` | bool | `false` |
| `vmenu_vehicle_blackout_enabled` | bool | (not in template) |
| `vmenu_weather_change_duration` | int (seconds) | `30` |
| `vmenu_enable_snow` | bool | `false` |
| `vmenu_smooth_time_transitions` | bool | `true` |
| `vmenu_enable_time_sync` | bool | `true` |
| `vmenu_freeze_time` | bool | `false` |
| `vmenu_ingame_minute_duration` | int (ms) | `2000` |
| `vmenu_current_hour` | int | `7` |
| `vmenu_current_minute` | int | `0` |
| `vmenu_sync_to_machine_time` | bool | `false` |
| `vmenu_override_voicechat_default_range` | float (meters, 0.0 = off) | `0.0` |

### Known template oddity

`vmenu_vehicle_spawn_rate_limit` appears in the shipped `permissions.cfg` but is **never read**
by the code at the pinned commit (rate limiting is the `VSBypassRateLimit` ace). We keep it in
the template for byte-compatibility and likewise don't read it.
