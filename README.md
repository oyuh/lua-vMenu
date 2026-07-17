# lua-vmenu

A ground-up rewrite of **[vMenu](https://github.com/tomgrobbe/vMenu)** by Tom Grobbe in pure Lua
(CfxLua 5.4), designed as a **drop-in replacement** for the original C# resource.

> Original vMenu © Tom Grobbe — https://www.vespura.com/ — https://github.com/tomgrobbe/vMenu
> This project is a derivative rewrite released with credit per the original license. Not for sale.

## Drop-in means drop-in

Deploy this folder as `vMenu` (same resource name) and:

- your existing `permissions.cfg` (all `vmenu_*` convars and `vMenu.*` ace permissions) works unchanged
- your `config/*.json` (addons, extras, locations, model whitelists, tattoos) works unchanged
- players keep their saved vehicles, peds, MP characters, and weapon loadouts (client KVP is keyed
  by resource name, and this rewrite preserves the exact save schemas)
- players keep their menu/noclip keybinds (identical key-mapping registration)
- third-party resources using `vMenu:*` events keep working (identical event protocol)

See [PLAN.md](PLAN.md) for the full rewrite plan and [docs/UPSTREAM.md](docs/UPSTREAM.md) for how
this tracks the upstream C# project.

## Status

✅ **v1.0.0 — code complete.** All 17 menus, noclip, the entity spawner, and the full
FunctionsController tick engine are ported; the parity audit against the pinned upstream
(`49e53065`) found every file, event, command, and public function accounted for. See
[docs/MIGRATION.md](docs/MIGRATION.md) to migrate a server, and
[docs/VERIFY.md](docs/VERIFY.md) for the remaining in-game verification checklist (things
only a live FiveM server can confirm: visuals, native-name risks, multi-client sync).

- ✅ M0: toolchain, scaffold, CI, first specs
- ✅ M1: the six [compatibility contracts](docs/contracts/README.md) documented from the C#
  source — 297 ACE permissions, 47 convars, the full event protocol, KVP save schemas with
  golden fixtures — plus `shared/config.lua` and `shared/permissions.lua` ports with 41 specs
- ✅ M2: shared core — require() bootstrap for CfxLua, JSON compat layer, full permission
  sync flow (server ACE collection → client resolution with staff gate), locations loader
- ✅ M3: menu framework (MenuAPI port) — **code complete**: items + navigation core, full
  rendering pipeline (header/subtitle/gradient/items/overflow/description/stats/color panels),
  input ticks with hold-to-scroll acceleration, instructional buttons, control disabling, and
  client/server entrypoints with the permission push wired up. A demo menu covering every item
  type ships behind `experimental_features_enabled '1'` (`/vmenu_demo`) for the remaining
  in-game side-by-side check against C# vMenu (visuals, sprite metrics, control ids)
- ✅ M4: server port — MainServer.cs and BanManager.cs in full: weather/time sync loops over
  replicated convars, every server event handler with ACE re-checks + auto-ban on fake
  events, the `vmenuserver` console command (debug/weather/time/ban/unban/migrate), the ban
  system on `vmenu_ban_<uuid>` KVPs (C# ban records keep working), vmenu.log writers,
  teleport-location saving, and the join/quit + permission push flow
- ✅ M5: client foundation — MainMenu.cs and EventManager.cs ported: key mappings under the
  compatible `vMenu:{id}:MenuToggle`/`NoClip` names (existing player keybinds survive), KVP
  cleanup, the `vmenuclient` command, every client event handler, weather/time sync ticks,
  addon/whitelist/extras/tattoos config parsing, notifications (Notify/Subtitle/HelpMessage),
  UserDefaults (`settings_` KVPs, C#-compatible True/False strings), the StorageManager
  save/load layer (C# saves round-trip against golden fixtures), player lists (native +
  OneSync Infinity), and the permission-gated main menu tree with the staff-only gate
- ✅ M6: data codegen — `scripts/gen-data.ps1` mechanically extracts `vMenu/data/*.cs` into
  `client/data/*.lua` (deterministic; regen after upstream bumps): 23 vehicle class lists,
  vehicle/neon colors with label fixups, ~120 weapons with descriptions + per-weapon ACE
  permissions + 780 component names + tints, animal peds, scenarios, timecycles, vehicle
  blip sprites, plus `overlays.json` (3429 tattoo records) shipped verbatim. Runtime
  consumers: `client/weapons.lua` (valid/addon weapon list building) and
  `client/tattoos.lua` (gendered per-zone tattoo collections)
- ✅ M7: menus wave 1 — About, Recording, Time Options, Weather Options, Voice Chat,
  Player Options (with the auto-pilot + custom driving style submenus and scenarios),
  Vehicle Spawner (spawn by name, addon vehicles, all 23 class submenus with stats panels,
  whitelist locks, spawn rate limiting), and Misc Settings (teleport options + server
  locations, keybind toggles, developer tools with timecycle modifiers, connection options,
  location blips, and Save Personal Settings). Backed by the CommonFunctions ports: safe
  teleporting, vehicle spawning with previous-vehicle replacement, scenarios, suicide,
  driving tasks, and onscreen-keyboard input
- ✅ M8: menus wave 2 — the stateful menus. Saved Vehicles (the drop-in flagship: C#-era
  saves load, spawn, and re-save byte-compatibly, backed by the VehicleInfo capture/apply
  engine in `client/vehicle_common.lua`), Vehicle Options (the 2.6k-line C# menu in full:
  god-mode submenu, repair/wash, the dynamic per-vehicle Mod Menu with localized mod names,
  colors with paint-finish statebags + custom RGB submenus, neon underglow, doors/windows/
  extras/liveries, plates, speed limiter, torque/power multipliers, and the C#-compatible
  default-radio KVP), Personal Vehicle (key-fob remote actions), Online Players (spectate,
  teleport, kick/ban, private messages), Banned Players (record view, filter, unban),
  Weapon Options and Weapon Loadouts (PascalCase ValidWeapon saves with enum-ordinal
  permissions round-trip against C# fixtures)
- ✅ M9: menus wave 3 + runtime features — NoClip (camera-relative movement, speed
  cycling, instructional buttons), the Entity Spawner (raycast placement), Player
  Appearance (spawn lists from generated data, drawable/prop customization, gen9 ped
  collections, saved peds with the PedInfo KVP round-trip), MP Ped Customization (the
  full character creator/editor: inheritance, appearance overlays, face shape, tattoos,
  clothing, props, categories, and the pixel-identical mp_ped_<name> spawn path), and
  the FunctionsController tick engine (`client/functions_controller/`): god modes,
  vehicle god/freeze/torque/power/no-helmet/infinite-fuel, never wanted, speedometers &
  location & time display, player blips & overhead names, death + join/quit
  notifications, voice chat, restore appearance/weapons on respawn, keybinds (waypoint
  tp, drift mode, finger pointing, recording, bigmap), the MP creator camera, spectate
  recovery, snowball pickups, and helmet visor toggles

- ✅ M10: parity audit & release — full sweep vs pinned upstream (all 42 .cs files mapped,
  18 client + 23 server event handlers, commands, and every CommonFunctions public method
  accounted for; one real bug found and fixed: `IsPedPointing` is an upstream helper over
  `IsTaskMoveNetworkActive`, not a native), perf review (menu ticks early-out closed;
  noclip/spawner threads only exist while active), `docs/MIGRATION.md`, `docs/VERIFY.md`,
  and the v1.0.0 tag

See PLAN.md §8 for the full roadmap.

## Development

Toolchain: Lua 5.4, [busted](https://lunarmodules.github.io/busted/) (tests),
[luacheck](https://github.com/lunarmodules/luacheck) (lint),
[StyLua](https://github.com/JohnnyMorganz/StyLua) (format).

```sh
busted            # run unit tests (pure Lua, no FiveM needed — natives are mocked)
luacheck .        # lint
stylua --check .  # format check
```
