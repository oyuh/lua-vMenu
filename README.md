# lua-vMenu

A ground-up rewrite of **[vMenu](https://github.com/tomgrobbe/vMenu)** in pure **CfxLua (Lua 5.4)**,
built as a **drop-in replacement** for the original C# resource. Same resource name, same config,
same permissions, same player saves — no .NET runtime required.

## Credits

- **Original vMenu** by **Tom Grobbe (Vespura)** — <https://www.vespura.com/vmenu> —
  <https://github.com/tomgrobbe/vMenu>, with contributions from Deltanic, Brigliar, IllusiveTea,
  Shayan Doust, zr0iq, and Golden.
- **Lua rewrite** by **Lawson ([oyuh](https://github.com/oyuh))** — <https://github.com/oyuh/lua-vMenu>.

This project is a derivative rewrite released with credit per the original license. It is not for
sale. All original vMenu functionality and the `vMenu` name belong to Tom Grobbe; this repository
only reimplements the resource in Lua.

## Drop-in means drop-in

Deploy this folder as `vMenu` (keep the folder name) and everything a server already relies on
keeps working:

- your existing `permissions.cfg` — every `vmenu_*` convar and `vMenu.*` ace permission — is read
  unchanged
- your `config/*.json` (addons, extras, locations, model whitelists, tattoos) loads from the same
  paths with the same schemas
- players keep their saved vehicles, peds, MP characters, and weapon loadouts — client KVP is keyed
  by resource name and the save formats are byte-compatible with the C# version (Newtonsoft JSON,
  quirks and all)
- players keep their menu / noclip keybinds (identical key-mapping registration)
- third-party resources built on the `vMenu:*` event protocol keep working unchanged

Migrating an existing server is: stop it, swap the folder, start it. See
[docs/MIGRATION.md](docs/MIGRATION.md) for the full walkthrough and the "what carries over"
table.

## Why a Lua rewrite

The original vMenu ships as a compiled .NET assembly and runs on the server's mono/.NET runtime.
This rewrite is plain CfxLua, which means:

- **No .NET / mono dependency** — no `vMenu.net.dll`, nothing to compile, no runtime to keep in
  sync with your FiveM artifacts. Unzip and `ensure vMenu`.
- **Readable, hackable source** — every menu and feature is plain Lua you can open and edit in
  place, rather than a DLL you'd have to fork and rebuild.
- **Faithful behavior** — load-bearing quirks (serialization typos, save-schema details) are
  preserved on purpose so saves and integrations behave exactly like upstream. The handful of
  places where upstream code plainly contradicted its own intent are fixed and marked with a
  comment in the source.

## Performance

The resource is built to stay out of the way when nobody is using it:

- **Menu ticks early-out** every frame while the menu is closed, so the idle cost is designed to
  sit at ~`0.00ms` on resmon (matching upstream's idle profile).
- **On-demand threads** — noclip and the entity spawner only spin up a thread while they're
  actually active, and tear it down afterward.
- **No per-frame work on the server** beyond the same weather/time sync loops upstream runs.

Exact idle/active resmon numbers depend on your server and are part of the live-deployment
checklist in [docs/VERIFY.md](docs/VERIFY.md).

## Features

Full parity with upstream vMenu: the player / vehicle / world menu trees, the vehicle spawner
(all classes, addon vehicles, whitelist locks, stats panels), saved vehicles with the C#-compatible
capture/apply engine, vehicle options (dynamic mod menu, colors, neon, plates, extras, liveries),
weapon options and loadouts, player appearance and the full MP character creator/editor, online /
banned player management (spectate, teleport, kick, ban/tempban, unban), noclip, the entity
spawner, time / weather / voice-chat options, misc settings and developer tools, and the
FunctionsController tick engine (god modes, speedometers, blips and overhead names, notifications,
restore-on-respawn, keybinds, the MP creator camera, and more).

## Installation

1. Download the latest `vMenu-vX.Y.Z.zip` from the
   [Releases](https://github.com/oyuh/lua-vMenu/releases) page.
2. Unzip it into your server's `resources/` folder — it extracts as a single `vMenu` folder.
   **Keep that folder name** (player saves are keyed to it).
3. Migrating from C# vMenu? Copy your existing `config/*.json` across and follow
   [docs/MIGRATION.md](docs/MIGRATION.md).
4. `ensure vMenu` in your `server.cfg`.

## Development

Toolchain: Lua 5.4, [busted](https://lunarmodules.github.io/busted/) (tests),
[luacheck](https://github.com/lunarmodules/luacheck) (lint),
[StyLua](https://github.com/JohnnyMorganz/StyLua) (format). The unit suite runs in pure Lua with
the FiveM natives mocked — no game server needed.

```sh
busted            # run unit tests
luacheck .        # lint
stylua --check .  # format check
```

The compatibility contracts (permissions, convars, events, KVP save schemas) are documented under
[docs/contracts/](docs/contracts/README.md), and [docs/UPSTREAM.md](docs/UPSTREAM.md) covers how
this tracks the upstream C# project when it changes.
