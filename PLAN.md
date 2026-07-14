# lua-vmenu — Full Rewrite Plan

A ground-up rewrite of [vMenu](https://github.com/tomgrobbe/vMenu) (C#/.NET, ~29,700 lines) as a
pure Lua FiveM resource, designed as a **drop-in replacement**: a server owner deletes the C#
vMenu folder, drops this one in (same resource name), keeps their existing `permissions.cfg` and
`config/*.json`, and everything — including every player's saved vehicles, peds, and weapon
loadouts — keeps working.

**Upstream pinned at:** `tomgrobbe/vMenu @ 49e53065b66f1fe82b19a825c41866a3e7fb9663` (2026-07-07)

---

## 1. Goals and non-goals

### Goals
1. **Feature parity** with upstream vMenu at the pinned commit. Same menus, same behavior, same
   look and feel.
2. **Zero-migration drop-in.** All six compatibility contracts (§3) honored exactly.
3. **Idiomatic, sophisticated Lua** — not transliterated C#. Module system, no globals leaking,
   allocation-free tick loops, data-driven menu definitions where the C# used copy-paste.
4. **Tested.** Pure-logic code covered by `busted` unit tests running outside the game; a mock
   CitizenFX layer for everything that touches natives/events/KVP; static analysis via `luacheck`.
5. **Trackable against upstream.** Upstream keeps shipping features; we need a repeatable
   diff-and-port workflow (§9).

### Non-goals (v1)
- No new features beyond upstream parity. Feature ideas go to a post-parity backlog.
- No NUI/HTML UI. Upstream draws with game natives/scaleforms; we replicate that (§5).
- No database backends. Upstream uses convars + JSON files + KVP; so do we.

---

## 2. What's actually in upstream (source survey)

| Area | Files | Lines | Notes |
|---|---|---|---|
| `SharedClasses/` | 3 | 1,076 | ConfigManager (convars), PermissionsManager (ACE), SupplementaryPermissionManager |
| `vMenu/` (client core) | 11 | 9,676 | CommonFunctions (3,355), FunctionsController (3,032), MainMenu (848), UserDefaults, EventManager, StorageManager, Noclip, Notification, PlayerLists, MpPedDataManager, EntitySpawner |
| `vMenu/menus/` | 17 | 13,425 | MpPedCustomization (3,012), VehicleOptions (2,643), PlayerAppearance (2,379), + 14 more |
| `vMenu/data/` | 8 | 3,885 | Static data tables: VehicleData, ValidWeapon, TimeCycles, PedScenarios, TattoosData, BlipInfo, PedModels, ValidAddonWeapon |
| `vMenuServer/` | 2 | 1,548 | MainServer (weather/time sync, player list, admin actions), BanManager |
| **Total C#** | **41** | **~29,700** | Plus `MenuAPI.dll` (external menu framework, TomGrobbe/MenuAPI) and Newtonsoft.Json |

Non-code assets we inherit as-is: `config/addons.json`, `extras.json`, `locations.json`,
`model-whitelists.json`, `tattoos.json`, `permissions.cfg` template, `vMenu/data/overlays.json`.

Expected Lua footprint: **~22–30k lines** (data tables shrink as plain Lua tables; menu code
shrinks with data-driven definitions; the menu framework itself adds ~3–4k new lines).

---

## 3. The six compatibility contracts (the heart of "drop-in")

Everything below is observable by servers, players, or third-party resources. Each contract gets
a spec document in `docs/contracts/` (written in Milestone 1) and conformance tests.

### 3.1 Convars (`permissions.cfg` settings)
All ~50 `vmenu_*` settings read via `GetConvar` (e.g. `vmenu_use_permissions`,
`vmenu_menu_toggle_key`, `vmenu_enable_dynamic_weather`, `vmenu_keymapping_id`, …).
Same names, same defaults, same string/int/float/bool coercion quirks — upstream's
`GetSettingsInt` falls back to parsing the string form when `GetConvarInt` returns the default;
we replicate that exactly.

### 3.2 ACE permissions
Every `vMenu.*` ace (~190 of them: `vMenu.Everything`, `vMenu.OnlinePlayers.*`,
`vMenu.PlayerOptions.*`, `vMenu.VehicleOptions.*`, …) checked server-side with
`IsPlayerAceAllowed` and pushed to clients, exactly as `PermissionsManager.cs` does. An existing
`permissions.cfg` must produce identical menu visibility. The supplementary-permissions event
(`vMenu:SetSupplementaryPermissions`) is also preserved for third-party integrations.

### 3.3 Network/local events (third-party integration surface)
The full `vMenu:*` event protocol, same names and same argument order/types:
- **client→server:** `KickPlayer`, `KillPlayer`, `SummonPlayer`, `TempBanPlayer`, `PermBanPlayer`,
  `RequestPlayerUnban`, `RequestBanList`, `UpdateServerWeather`, `UpdateServerBlackout`,
  `UpdateServerVehicleBlackout`, `UpdateServerWeatherCloudsType`, `UpdateServerTime`,
  `FreezeServerTime`, `SaveTeleportLocation`, `SendMessageToPlayer`, `GetPlayerIdentifiers`,
  `RequestPlayerList`, `GetPlayerCoords`, `GetOutOfCar`, `ClearArea`
- **server→client:** `SetAddons`, `SetPermissions`, `SetSupplementaryPermissions`,
  `SetConfigOptions`, `Notify`, `KillMe`, `GoodBye`, `SetBanList`, `SetClouds`, `ClearArea`,
  `updatePedDecors`, `PrivateMessage`, `UpdateTeleportLocations`, `PlayerJoinQuit`,
  `ReceivePlayerList`, `GetPlayerCoords:reply`, `UpdateServerWeather`, `UpdateServerTime`,
  `BanSuccessful`, `UnbanSuccessful`, `BanCheaterSuccessful`, `InfiniteFuelToggled`,
  `WeatherChangeComplete`, `SetupTickFunctions`
- **standard events:** `playerConnecting` (ban enforcement), `playerSpawned`, `chatMessage`.

### 3.4 Client KVP save data (players' saved stuff survives)
FiveM client KVP is keyed by **resource name** — since we ship as `vMenu`, every player's
existing saves load into the Lua version automatically, *provided the JSON matches
Newtonsoft's output byte-shape* (field names, casing, nesting). Known key prefixes:
`veh_` (saved vehicles), `ped_` (classic saved peds), `mp_ped_` (MP character saves),
`mp_character_category_`, `saved_veh_category_`, `vmenu_string_saved_weapon_loadout_`,
plus all `UserDefaults` per-player setting keys. Milestone 1 extracts **golden JSON fixtures**
from the C# structs (`VehicleInfo`, `PedInfo`, `MultiplayerPedData`, `ValidWeapon`, …) so
round-trip tests can prove `lua_load(csharp_save)` and `csharp_load(lua_save)` both work.
Server-side KVP (ban list, dynamic weather state, saved teleport locations) gets the same
treatment.

### 3.5 Config JSON files
`config/addons.json`, `extras.json`, `locations.json`, `model-whitelists.json`, `tattoos.json`
and `data/overlays.json` parsed with identical schemas and identical error tolerance (bad JSON
must degrade with a warning, not break the resource — upstream notifies and continues).

### 3.6 Commands & key mappings
`RegisterKeyMapping("vMenu:{vmenu_keymapping_id}:MenuToggle", …)` and
`vMenu:{id}:NoClip` — **exact mapping command names**, because FiveM persists user keybinds per
mapping name; players keep their bound keys. Also the `vMenu:DV` style commands, chat commands,
and controller (`pad_digitalbuttonany`) bindings.

---

## 4. Target architecture & repo layout

```
lua-vmenu/
├── fxmanifest.lua              -- lua54 'yes'; resource name stays "vMenu" when deployed
├── PLAN.md / README.md / LICENSE.md (credit + link to upstream, per license)
├── config/                     -- shipped verbatim from upstream (user-editable)
│   ├── addons.json  extras.json  locations.json  model-whitelists.json  tattoos.json
│   └── permissions.cfg (template)
├── shared/
│   ├── config.lua              -- ConfigManager port: typed convar getters, locations loader
│   ├── permissions.lua         -- Permission enum + ace-name mapping (single source of truth)
│   └── util.lua                -- logging, debug mode, math/string helpers
├── vendor/
│   └── json_compat.lua         -- thin wrapper over cfx `json` enforcing Newtonsoft shapes
├── menu/                       -- MenuAPI reimplementation (see §5)
│   ├── menu.lua  items.lua  controls.lua  draw.lua  sounds.lua  controller.lua
├── client/
│   ├── main.lua                -- MainMenu port: boot, key mappings, menu tree wiring
│   ├── events.lua              -- EventManager port
│   ├── common.lua              -- CommonFunctions port (split into common/*.lua by topic)
│   ├── functions_controller/   -- the 3k-line tick monolith, split per feature ticks
│   ├── storage.lua  user_defaults.lua  noclip.lua  notify.lua
│   ├── player_lists.lua  mp_ped_data.lua  entity_spawner.lua
│   ├── data/                   -- generated Lua data tables (see §6)
│   └── menus/                  -- one file per upstream menu class (17 files)
├── server/
│   ├── main.lua                -- MainServer port (weather/time loops, admin, player list)
│   └── bans.lua                -- BanManager port
├── tests/                      -- never shipped; excluded from fxmanifest
│   ├── mocks/cfx.lua           -- fake natives: convars, KVP store, event bus, players
│   ├── fixtures/               -- golden JSON from C# serialization
│   └── unit/*_spec.lua         -- busted specs
├── scripts/
│   ├── gen-data.ps1|lua        -- codegen: C# data files → Lua tables
│   └── upstream-diff.ps1       -- fetch upstream, diff vs pinned SHA, map to Lua modules
├── docs/contracts/             -- the six contracts, as reviewable specs
├── .luacheckrc  stylua.toml  .busted
└── .github/workflows/ci.yml    -- luacheck + stylua --check + busted on every push
```

Design rules for "sophisticated Lua":
- Every file is a module returning a table; zero accidental globals (`luacheck` enforces).
- Tick handlers allocate nothing per frame; feature ticks register/unregister dynamically the way
  upstream's `SetupTickFunctions` does, instead of one mega-loop of `if`s.
- Menus are **declared as data** (item specs + handler functions) and instantiated by the menu
  framework — this collapses a lot of upstream's repetitive C#.
- All game access goes through thin wrappers so unit tests can inject `tests/mocks/cfx.lua`.

---

## 5. The MenuAPI problem (biggest single risk)

All 13,425 lines of menu code sit on `MenuAPI.dll` (TomGrobbe/MenuAPI — same author, source
available on GitHub for reference). There is no maintained Lua equivalent with the same look, so
**we port MenuAPI itself** into `menu/` (~3–4k lines):

- Same visual result: native draw calls / scaleform header, description box with auto-wrap,
  left/right badges & icons, instructional buttons scaleform, sounds (`SoundFrontend`).
- Same item model: `Menu`, `MenuItem`, `MenuCheckboxItem`, `MenuListItem`, `MenuSliderItem`,
  `MenuDynamicListItem`, submenus, `OnItemSelect`/`OnCheckboxChange`/`OnListIndexChange`
  callbacks — a 1:1 Lua API so menu code ports mechanically and future upstream menu diffs map
  cleanly.
- Same controls behavior: controller support, disabled controls while menu open, hold-to-scroll
  acceleration, RT-fast-scroll, `vmenu_menu_toggle_key` handling.

Acceptance for this component: a side-by-side screenshot/behavior checklist against C# vMenu
running the same demo menu (navigation, wrap-around, sliders, list scroll accel, sounds).

---

## 6. Data tables: generate, don't hand-port

`vMenu/data/*.cs` (3,885 lines) is almost entirely static data (vehicle class lists, weapon
hashes/components, timecycle modifiers, scenarios, tattoo/overlay data). Hand-porting invites
typos. Instead `scripts/gen-data.*` parses the C# source (they're regular
collection-initializer blocks) and emits `client/data/*.lua`. The generator is kept in-repo and
re-run whenever upstream touches `vMenu/data/` — that entire directory stays effectively free to
maintain. Generated files get a `-- GENERATED from <file>@<sha>, do not edit` header and a CI
check that regeneration is clean.

---

## 7. Tooling & test suite

### Local toolchain (Windows — none of it is installed yet; scoop is available)
```powershell
scoop install lua luarocks       # Lua 5.4 + package manager
luarocks install busted          # test runner (+ luassert, penlight deps)
luarocks install luacheck        # static analysis / lint
scoop install stylua             # formatter
scoop install lua-language-server # editor intelligence (optional but recommended)
```
Fallback if luarocks misbehaves on Windows (it sometimes needs a C compiler for deps): run the
test stack in WSL/CI — the code under test is pure Lua either way. FiveM itself runs **CfxLua
5.4** (`lua54 'yes'` in the manifest), which adds `vector3`, `quat`, `json.encode/decode`, and
msgpack args on events; the mock layer reproduces those so tests behave like the runtime.

### Test suite design (`tests/`)
1. **Unit (busted, runs on plain Lua 5.4):** convar coercion rules, permission→ace mapping,
   KVP JSON round-trips against golden fixtures, config file parsing incl. malformed input,
   ban-record logic, weather/time state machines, menu framework navigation logic (index math,
   wrap, filtering), data-table integrity (every generated table non-empty, hashes numeric).
2. **Contract tests:** one spec per document in `docs/contracts/` — e.g. every event in §3.3
   has a registered handler with the right arity; every Permission has an ace name; every convar
   in the template `permissions.cfg` is read somewhere.
3. **Mock CFX layer (`tests/mocks/cfx.lua`):** in-memory convar store, in-memory KVP with
   `StartFindKvp` iteration semantics, an event bus that bridges "client" and "server" module
   instances in one process (msgpack-like copy semantics), fake players. This lets us
   integration-test flows like *client requests ban list → server filters by ace → client
   receives `vMenu:SetBanList`* entirely in busted.
4. **In-game smoke (manual + optional CI stretch):** a `tests/ingame/` dev resource with a
   checklist runner; stretch goal is a headless FXServer boot in CI that asserts the resource
   starts clean with zero script errors.
5. **CI (GitHub Actions):** `luacheck .` + `stylua --check .` + `busted` + data-regen clean
   check, on every push/PR.

---

## 8. Milestones

Order is chosen so every milestone ends with something runnable/testable.

| # | Milestone | Contents | Exit criteria |
|---|---|---|---|
| 0 | **Bootstrap** | Fork upstream on GitHub (license requires fork or link-back), init this repo, layout from §4, fxmanifest, tooling installed, CI green on a hello-world spec | `busted`, `luacheck`, `stylua` all run locally & in CI |
| 1 | **Contract extraction** | Write all six `docs/contracts/*` specs from the C# source; capture golden KVP/JSON fixtures; enumerate all ~190 aces + ~50 convars + all UserDefaults keys | Contracts reviewed; fixtures committed; contract specs failing-by-design where code doesn't exist yet |
| 2 | **Shared core** | `shared/config.lua`, `shared/permissions.lua`, `shared/util.lua`, `vendor/json_compat.lua` | Unit tests green: convar coercion, ace mapping, JSON shapes |
| 3 | **Menu framework** | Full MenuAPI port (§5) | Demo menu visually & behaviorally matches C# vMenu side-by-side |
| 4 | **Server** | `server/main.lua` (weather/time sync loops, admin actions, player list, teleport-location saving), `server/bans.lua` incl. `playerConnecting` enforcement | Mock-bus integration tests for every server event; ban KVP round-trips with C# fixtures |
| 5 | **Client foundation** | `client/main.lua`, `events.lua`, `storage.lua`, `user_defaults.lua`, `notify.lua`, `player_lists.lua`, key mappings (§3.6) | Menu opens in-game, permissions gate top-level entries, notifications work |
| 6 | **Data codegen** | `scripts/gen-data`, generate all 8 data tables | Regen is deterministic; integrity specs green |
| 7 | **Menus wave 1** (simple) | About, TimeOptions, WeatherOptions, VoiceChat, Recording, MiscSettings, PlayerOptions, VehicleSpawner | Each menu checklist-verified in-game vs C# |
| 8 | **Menus wave 2** (stateful) | VehicleOptions, SavedVehicles, PersonalVehicle, WeaponOptions, WeaponLoadouts, OnlinePlayers, BannedPlayers + their CommonFunctions support code | Saved vehicles created in C# vMenu load & spawn correctly |
| 9 | **Menus wave 3** (hardest) | PlayerAppearance, MpPedCustomization + mp_ped_data, FunctionsController tick features, Noclip, EntitySpawner | MP characters saved in C# load pixel-identical; noclip parity |
| 10 | **Parity audit & release** | Full checklist sweep vs pinned upstream, perf pass (0.00ms idle when menu closed is the bar), migration guide (`docs/MIGRATION.md`: "delete old vMenu, drop this in, keep your config"), tag v1.0.0 | A C# vMenu server migrated in <5 minutes with nothing lost |

Rough sizing: milestones 3, 8, 9 are the heavy ones; the whole plan is a few weeks of focused
sessions, very parallelizable after M3 since menus are independent.

---

## 9. Tracking upstream (the "periodically add their features" workflow)

- `docs/UPSTREAM.md` records the pinned SHA (`49e53065`, 2026-07-07) and a **file→module map**
  (every upstream `.cs` → its Lua module(s)).
- `scripts/upstream-diff.ps1`: clones/fetches upstream, `git diff <pinned>..HEAD --stat`, and
  prints which *Lua modules* are affected using the map. Porting a new upstream release =
  run script → port mapped diffs → update fixtures if schemas moved → bump pinned SHA.
- Because our menu framework mirrors MenuAPI's API 1:1 and menus stay one-file-per-upstream-class,
  upstream menu diffs translate nearly line-for-line.

---

## 10. Risks & honest notes

1. **MenuAPI port (M3) is the long pole.** Mitigation: MenuAPI source is public reference;
   scope strictly to what vMenu uses.
2. **JSON shape drift** breaks save compat silently. Mitigation: golden fixtures from real C#
   saves in M1, round-trip specs both directions, treated as release blockers.
3. **FunctionsController (3k lines of per-frame logic)** hides subtle behaviors (seatbelt, ELS
   compat, invisibility handling, PvP mode…). Mitigation: split per feature, port with the C#
   open side-by-side, checklist each toggle in-game.
4. **Performance expectations:** CfxLua is fast and avoids the mono runtime's GC hitches and
   startup cost, so a *well-written* Lua vMenu should idle at ~0.00ms and feel snappier to load —
   but sloppy per-frame allocation would erase that. The tick-discipline rules in §4 are the
   actual performance plan; "Lua = faster" only holds if we write it with intent (your words!).
5. **License compliance:** release as a GitHub fork of tomgrobbe/vMenu (or with a prominent
   link), keep Tom Grobbe's credit in LICENSE/README, never sell it. All three are explicit
   license conditions and all three are easy.

---

## 11. Immediate next steps (Milestone 0, ready to execute on your go)

1. Fork `tomgrobbe/vMenu` on your GitHub account, then point this directory's repo at it (new
   orphan branch `lua-rewrite`) — or keep `lua-vmenu` standalone with a link-back; both satisfy
   the license.
2. `scoop install lua luarocks stylua` + `luarocks install busted luacheck`; commit
   `.luacheckrc`, `stylua.toml`, CI workflow.
3. Scaffold §4 layout, copy `config/` from upstream verbatim, write first passing spec.
4. Start Milestone 1 contract extraction.
