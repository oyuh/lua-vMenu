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

🚧 **Milestone 4 complete — the server side is fully ported.** Client menus land next.

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
