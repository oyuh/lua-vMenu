# lua-vMenu

A ground-up rewrite of [vMenu](https://github.com/tomgrobbe/vMenu) in pure CfxLua (Lua 5.4),
built as a drop-in replacement for the original C# resource. Same resource name, same config,
same permissions, same player saves. No .NET runtime needed.

## Credits

- Original vMenu by Tom Grobbe (Vespura): <https://www.vespura.com/vmenu> /
  <https://github.com/tomgrobbe/vMenu>, with contributions from Deltanic, Brigliar, IllusiveTea,
  Shayan Doust, zr0iq, and Golden.
- Lua rewrite by Lawson ([oyuh](https://github.com/oyuh)): <https://github.com/oyuh/lua-vMenu>.

This is a derivative rewrite released with credit per the original license, and it's not for
sale. All the original vMenu functionality and the vMenu name belong to Tom Grobbe. This repo
just reimplements the resource in Lua.

## Drop-in means drop-in

Deploy this folder as `vMenu` (keep the folder name) and everything a server already relies on
keeps working:

- your existing `permissions.cfg` is read unchanged, every `vmenu_*` convar and `vMenu.*` ace
  permission included
- your `config/*.json` files (addons, extras, locations, model whitelists, tattoos) load from
  the same paths with the same schemas
- players keep their saved vehicles, peds, MP characters, and weapon loadouts. Client KVP is
  keyed by resource name and the save formats are byte-compatible with the C# version
  (Newtonsoft JSON, quirks and all)
- players keep their menu and noclip keybinds (same key-mapping registration)
- third-party resources built on the `vMenu:*` event protocol keep working unchanged

Migrating an existing server really is just: stop it, swap the folder, start it. See
[docs/MIGRATION.md](docs/MIGRATION.md) for the full walkthrough and the "what carries over"
table.

## Why a Lua rewrite

The original vMenu ships as a compiled .NET assembly and runs on the server's mono/.NET
runtime. This rewrite is plain CfxLua, which gets you a few things:

- **No .NET or mono dependency.** There's no `vMenu.net.dll`, nothing to compile, and no
  runtime to keep in sync with your FiveM artifacts. Unzip and `ensure vMenu`.
- **Source you can actually read and hack on.** Every menu and feature is plain Lua you can
  open and edit in place, instead of a DLL you'd have to fork and rebuild.
- **Faithful behavior.** Load-bearing quirks (serialization typos, save-schema details) are
  kept on purpose so saves and integrations behave exactly like upstream. The few places where
  upstream code plainly contradicted its own intent are fixed and marked with a comment in the
  source.

## Performance

The resource is built to stay out of the way when nobody is using it:

- Menu ticks early-out every frame while the menu is closed, so the idle cost should sit at
  around 0.00ms on resmon, matching upstream's idle profile.
- Noclip and the entity spawner only spin up a thread while they're actually active, and tear
  it down afterward.
- The server does no per-frame work beyond the same weather/time sync loops upstream runs.

Exact idle/active resmon numbers depend on your server. Checking them is part of the
live-deployment checklist in [docs/VERIFY.md](docs/VERIFY.md).

## Features

Full parity with upstream vMenu: the player / vehicle / world menu trees, the vehicle spawner
(all classes, addon vehicles, whitelist locks, stats panels), saved vehicles with the
C#-compatible capture/apply engine, vehicle options (dynamic mod menu, colors, neon, plates,
extras, liveries), weapon options and loadouts, player appearance and the full MP character
creator/editor, online and banned player management (spectate, teleport, kick, ban/tempban,
unban), noclip, the entity spawner, time / weather / voice-chat options, misc settings and
developer tools, and the FunctionsController tick engine (god modes, speedometers, blips and
overhead names, notifications, restore-on-respawn, keybinds, the MP creator camera, and more).

## Installation

1. Download the latest `vMenu-vX.Y.Z.zip` from the
   [Releases](https://github.com/oyuh/lua-vMenu/releases) page.
2. Unzip it into your server's `resources/` folder. It extracts as a single `vMenu` folder,
   and you want to keep that folder name (player saves are keyed to it).
3. Migrating from C# vMenu? Copy your existing `config/*.json` across and follow
   [docs/MIGRATION.md](docs/MIGRATION.md).
4. `ensure vMenu` in your `server.cfg`.

## Development

Toolchain: Lua 5.4, [busted](https://lunarmodules.github.io/busted/) for tests,
[luacheck](https://github.com/lunarmodules/luacheck) for lint, and
[StyLua](https://github.com/JohnnyMorganz/StyLua) for formatting. The unit suite runs in pure
Lua with the FiveM natives mocked, so you don't need a game server to run it.

```sh
busted            # run unit tests
luacheck .        # lint
stylua --check .  # format check
```

The compatibility contracts (permissions, convars, events, KVP save schemas) are documented
under [docs/contracts/](docs/contracts/README.md), and [docs/UPSTREAM.md](docs/UPSTREAM.md)
covers how this tracks the upstream C# project when it changes.
