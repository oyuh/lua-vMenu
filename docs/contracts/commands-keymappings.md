# Contract: commands & key mappings

Source: `vMenu/MainMenu.cs`, `vMenu/EntitySpawner.cs`, `vMenu/menus/MiscSettings.cs`,
`vMenuServer/MainServer.cs` (upstream @ `49e53065`).

## Key mappings — names are persistence keys

FiveM stores each player's rebound keys **per mapping command name**. Registering different names
would silently reset every player's binds, so these are exact:

| Mapping command | Description shown in GTA settings | Mapper | Default |
|---|---|---|---|
| `vMenu:{id}:NoClip` | `vMenu NoClip Toggle Button` | `keyboard` | `vmenu_noclip_toggle_key` (`F2`) |
| `vMenu:{id}:MenuToggle` | `vMenu Toggle Button` | `keyboard` | `vmenu_menu_toggle_key` (`M`) |
| `vMenu:{id}:MenuToggle` | `vMenu Toggle Button Controller` | `pad_digitalbuttonany` | `start_index` |

`{id}` = `vmenu_keymapping_id` convar (default `"Default"`, whitespace ⇒ `"Default"`). The
MenuAPI-level toggle key is disabled (`MenuToggleKey = -1`); toggling happens only through these
registered commands. Both mapping commands are registered as **non-restricted** commands whose
handlers re-check permissions (`NoClip` perm; menu enabled state).

## Client commands

| Command | Behavior |
|---|---|
| `vMenu:DV` | delete current vehicle, gated on `VODelete` |
| `vmenuclient` | utility/debug subcommands (args-based) |
| `disconnect` | registered as a no-op stub by MiscSettings' connection menu |
| `testEntity`, `endTest` | only when `experimental_features_enabled '1'` in fxmanifest |
| `testped`, `tattoo` | experimental-only debug commands |

## Server commands

| Command | Behavior |
|---|---|
| `vmenuserver` | **restricted** console command; subcommands parsed from args (weather/time/ban management etc. — port the full arg grammar with MainServer in M4) |

## fxmanifest metadata knobs (not convars)

| Key | Values | Purpose |
|---|---|---|
| `client_debug_mode` / `server_debug_mode` | `'true'`/`'false'` | debug logging |
| `experimental_features_enabled` | `'0'`/`'1'` | dev/test commands |
