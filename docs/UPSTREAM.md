# Upstream tracking

This branch (`original`) targets parity with one specific commit on upstream's `legacy` branch,
the classic C# vMenu. The `stable` branch tracks upstream's `enhanced` branch instead, see
[BRANCH-PLAN.md](BRANCH-PLAN.md). When upstream moves, run `scripts/upstream-diff.ps1` to see what
changed and which Lua modules it touches, port the diffs, then bump the pin below.

## Pinned upstream

| | |
|---|---|
| Repo | https://github.com/tomgrobbe/vMenu |
| Branch | `legacy` |
| Commit | `f615b15b38df4e67742658e36a52a160dbcd88c6` |
| Date | 2026-10-02 |

## File to module map

| Upstream (C#) | Here (Lua) |
|---|---|
| `SharedClasses/ConfigManager.cs` | `shared/config.lua` |
| `SharedClasses/PermissionsManager.cs` | `shared/permissions.lua` |
| `SharedClasses/SupplementaryPermissionManager.cs` | `shared/permissions.lua` |
| `vMenu/MainMenu.cs` | `client/main.lua` |
| `vMenu/EventManager.cs` | `client/events.lua` (parsed config + cross-module statics live in `client/state.lua`) |
| `vMenu/CommonFunctions.cs` | `client/common.lua` (vehicle save/apply half in `client/vehicle_common.lua`, ped skin/save half in `client/ped_common.lua`) |
| CitizenFX.Core `VehicleMod` (localized mod names the Mod Menu relies on) | `client/vehicle_mod_names.lua` |
| `vMenu/FunctionsController.cs` | `client/functions_controller/*.lua` |
| `vMenu/StorageManager.cs` | `client/storage.lua` |
| `vMenu/UserDefaults.cs` | `client/user_defaults.lua` |
| `vMenu/Notification.cs` | `client/notify.lua` |
| `vMenu/Noclip.cs` | `client/noclip.lua` |
| `vMenu/PlayerLists.cs` | `client/player_lists.lua` |
| `vMenu/MpPedDataManager.cs` | `client/mp_ped_data.lua` |
| `vMenu/EntitySpawner.cs` | `client/entity_spawner.lua` |
| `vMenu/menus/<Name>.cs` | `client/menus/<name>.lua`, one file per upstream menu |
| `vMenu/data/*.cs`, `vMenu/data/overlays.json` | `client/data/*.lua`, **generated** by `scripts/gen-data.ps1`, don't hand-edit. Runtime halves (ValidWeapons list building, TattoosData sorting) live in `client/weapons.lua` / `client/tattoos.lua` |
| `vMenuServer/MainServer.cs` | `server/main.lua` (DebugLog class becomes `server/log.lua`) |
| `vMenuServer/BanManager.cs` | `server/bans.lua`, plus `server/datetime.lua` for the C# DateTime semantics |
| `MenuAPI.dll` (TomGrobbe/MenuAPI) | `menu/*.lua`, a full reimplementation with a 1:1 API |
| `vMenuServer/config/*` | `config/*`, shipped verbatim |

## Porting workflow

1. `pwsh scripts/upstream-diff.ps1` fetches upstream, diffs the pin against the head of the
   pinned branch, and lists the affected Lua modules.
2. Port each hunk into the mapped module. Menu diffs land nearly line for line, since `menu/`
   mirrors MenuAPI's API.
3. If a diff touches `vMenu/data/`, re-run `scripts/gen-data` instead of porting by hand.
4. If a diff changes a save schema, config schema, event signature, ace name, or convar:
   update the matching `docs/contracts/*` spec and its fixtures **first**, then the code.
5. Bump the pinned commit in the table above.
