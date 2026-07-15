# Upstream tracking

This rewrite targets feature parity with a specific upstream commit. When upstream moves, run
`scripts/upstream-diff.ps1` to see what changed and which Lua modules are affected, port the
diffs, then bump the pin here.

## Pinned upstream

| | |
|---|---|
| Repo | https://github.com/tomgrobbe/vMenu |
| Commit | `49e53065b66f1fe82b19a825c41866a3e7fb9663` |
| Date | 2026-07-07 |

## File → module map

| Upstream (C#) | Here (Lua) |
|---|---|
| `SharedClasses/ConfigManager.cs` | `shared/config.lua` |
| `SharedClasses/PermissionsManager.cs` | `shared/permissions.lua` |
| `SharedClasses/SupplementaryPermissionManager.cs` | `shared/permissions.lua` |
| `vMenu/MainMenu.cs` | `client/main.lua` |
| `vMenu/EventManager.cs` | `client/events.lua` (parsed config + cross-module statics live in `client/state.lua`) |
| `vMenu/CommonFunctions.cs` | `client/common.lua` (split by topic as it grows) |
| `vMenu/FunctionsController.cs` | `client/functions_controller/*.lua` |
| `vMenu/StorageManager.cs` | `client/storage.lua` |
| `vMenu/UserDefaults.cs` | `client/user_defaults.lua` |
| `vMenu/Notification.cs` | `client/notify.lua` |
| `vMenu/Noclip.cs` | `client/noclip.lua` |
| `vMenu/PlayerLists.cs` | `client/player_lists.lua` |
| `vMenu/MpPedDataManager.cs` | `client/mp_ped_data.lua` |
| `vMenu/EntitySpawner.cs` | `client/entity_spawner.lua` |
| `vMenu/menus/<Name>.cs` | `client/menus/<name>.lua` (one file per upstream menu) |
| `vMenu/data/*.cs`, `vMenu/data/overlays.json` | `client/data/*.lua` — **generated** by `scripts/gen-data`, do not hand-edit |
| `vMenuServer/MainServer.cs` | `server/main.lua` (DebugLog class → `server/log.lua`) |
| `vMenuServer/BanManager.cs` | `server/bans.lua` (+ `server/datetime.lua` for the C# DateTime semantics) |
| `MenuAPI.dll` (TomGrobbe/MenuAPI) | `menu/*.lua` (full reimplementation, 1:1 API) |
| `vMenuServer/config/*` | `config/*` (shipped verbatim) |

## Porting workflow

1. `pwsh scripts/upstream-diff.ps1` — fetches upstream, diffs pinned..HEAD, lists affected Lua modules.
2. Port each diff hunk into the mapped module(s). Menu diffs map nearly line-for-line because
   `menu/` mirrors MenuAPI's API.
3. If a diff touches `vMenu/data/`, just re-run `scripts/gen-data` instead of porting by hand.
4. If a diff changes a save schema, config schema, event signature, ace name, or convar:
   update the matching `docs/contracts/*` spec and its fixtures **first**, then the code.
5. Update the pinned commit table above.
