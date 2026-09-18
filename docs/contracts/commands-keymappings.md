# Contract: commands and key mappings

Source: `vMenu/MainMenu.cs`, `vMenu/EntitySpawner.cs`, `vMenu/menus/MiscSettings.cs`,
`vMenuServer/MainServer.cs` (upstream @ `e0f3b92a`).

## Key mappings (the names are persistence keys)

FiveM stores each player's rebound keys **against the mapping command name**. Register
different names and every player's binds quietly reset, so these are exact:

| Mapping command | Description shown in GTA settings | Mapper | Default |
|---|---|---|---|
| `vMenu:{id}:NoClip` | `vMenu NoClip Toggle Button` | `keyboard` | `vmenu_noclip_toggle_key` (`F2`) |
| `vMenu:{id}:MenuToggle` | `vMenu Toggle Button` | `keyboard` | `vmenu_menu_toggle_key` (`M`) |
| `vMenu:{id}:MenuToggle` | `vMenu Toggle Button Controller` | `pad_digitalbuttonany` | `start_index` |

`{id}` is the `vmenu_keymapping_id` convar, default `"Default"`, and whitespace falls back to
`"Default"`. The MenuAPI-level toggle key is off (`MenuToggleKey = -1`), so toggling only
happens through these registered commands. Both mapping commands register as
**non-restricted**, and their handlers re-check permissions (`NoClip` perm, menu enabled
state).

## Client commands

| Command | Behavior |
|---|---|
| `vMenu:DV` | delete current vehicle, gated on `VODelete` |
| `vmenuclient` | utility/debug subcommands, args-based |
| `disconnect` | a no-op stub registered by MiscSettings' connection menu |
| `testEntity`, `endTest` | only when `experimental_features_enabled '1'` in fxmanifest |
| `testped`, `tattoo` | experimental-only debug commands |

## Server commands

| Command | Behavior |
|---|---|
| `vmenuserver` | **restricted** console command. Subcommands come from args (weather, time, ban management, and so on), and the full arg grammar lives in `server/main.lua`, ported from MainServer |

## fxmanifest metadata knobs (not convars)

| Key | Values | Purpose |
|---|---|---|
| `client_debug_mode` / `server_debug_mode` | `'true'`/`'false'` | debug logging |
| `experimental_features_enabled` | `'0'`/`'1'` | dev/test commands |
