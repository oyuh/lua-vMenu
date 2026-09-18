# lua-vMenu

[vMenu](https://github.com/tomgrobbe/vMenu) rewritten from scratch in CfxLua (Lua 5.4). Same
resource name, same config, same permissions, same player saves, no .NET runtime. Swap the
folder and your server carries on like nothing happened.

## Credits

- Original vMenu by Tom Grobbe (Vespura): <https://www.vespura.com/vmenu> /
  <https://github.com/tomgrobbe/vMenu>, with contributions from Deltanic, Brigliar, IllusiveTea,
  Shayan Doust, zr0iq, and Golden.
- Lua rewrite by Lawson ([oyuh](https://github.com/oyuh)): <https://github.com/oyuh/lua-vMenu>.

A derivative rewrite, released with credit per the original license, not for sale. The vMenu
name and all of the original functionality belong to Tom Grobbe. This repo only reimplements
the resource in Lua.

## Drop-in means drop-in

Deploy this folder as `vMenu`, keep the folder name, and everything a server already leans on
keeps working:

- your existing `permissions.cfg` is read unchanged, every `vmenu_*` convar and `vMenu.*` ace
  permission included
- your `config/*.json` files (addons, extras, locations, model whitelists, tattoos) load from
  the same paths with the same schemas
- players keep their saved vehicles, peds, MP characters, and weapon loadouts. Client KVP is
  keyed by resource name and the save formats are byte-compatible with the C# version
  (Newtonsoft JSON, quirks and all)
- players keep their menu and noclip keybinds, same key-mapping registration
- third-party resources built on the `vMenu:*` event protocol keep working unchanged

Migrating is stop, swap, start. [docs/MIGRATION.md](docs/MIGRATION.md) has the walkthrough and
the table of what carries over.

## Why a Lua rewrite

Upstream vMenu ships as a compiled .NET assembly and runs on the server's mono/.NET runtime.
This one is plain CfxLua, which buys you:

- **No .NET or mono dependency.** No `vMenu.net.dll`, nothing to compile, no runtime to keep in
  sync with your FiveM artifacts. Unzip and `ensure vMenu`.
- **Source you can read.** Every menu and feature is Lua you can open and edit in place,
  instead of a DLL you would have to fork and rebuild.
- **The same quirks.** Serialization typos and save-schema oddities are kept on purpose, so
  saves and integrations behave exactly like upstream. The handful of spots where upstream code
  contradicted its own intent are fixed, each with a comment in the source saying so.

## Performance

Measured on my server with resmon, side by side against the C# build:

- **About 60% lower frame time overall.** Same features on, same player count.
- **About 40% cheaper noclip.** Upstream runs its noclip logic whether or not you are in it.
  Here the thread only exists while noclip is active, and it is torn down on exit.
- **Roughly 0.00ms idle.** Menu ticks early-out every frame while the menu is closed, and the
  entity spawner follows the same only-while-active pattern as noclip.
- **No per-frame server work** beyond the weather and time sync loops upstream already runs.

One server, one set of numbers. Yours will differ with player count, artifacts, and whatever
else you have loaded. Checking resmon is on the live-deployment list in
[docs/VERIFY.md](docs/VERIFY.md).

## Features

Everything upstream vMenu does: the player / vehicle / world menu trees, the vehicle spawner
(all classes, addon vehicles, whitelist locks, stats panels), saved vehicles with the
C#-compatible capture/apply engine, vehicle options (dynamic mod menu, colors, neon, plates,
extras, liveries), weapon options and loadouts, player appearance and the full MP character
creator/editor, online and banned player management (spectate, teleport, kick, ban/tempban,
unban), noclip, the entity spawner, time / weather / voice-chat options, misc settings and
developer tools, and the FunctionsController tick engine (god modes, speedometers, blips and
overhead names, notifications, restore-on-respawn, keybinds, the MP creator camera, the lot).

## Installation

1. Grab the latest `vMenu-vX.Y.Z.zip` from the
   [Releases](https://github.com/oyuh/lua-vMenu/releases) page.
2. Unzip it into your server's `resources/` folder. It extracts as a single `vMenu` folder.
   Keep that name, player saves are keyed to it.
3. Coming from C# vMenu? Copy your existing `config/*.json` across and read
   [docs/MIGRATION.md](docs/MIGRATION.md).
4. `ensure vMenu` in your `server.cfg`.

## Development

Lua 5.4, [busted](https://lunarmodules.github.io/busted/) for tests,
[luacheck](https://github.com/lunarmodules/luacheck) for lint,
[StyLua](https://github.com/JohnnyMorganz/StyLua) for formatting. The unit suite runs in pure
Lua with the FiveM natives mocked, so no game server needed.

```sh
busted            # run unit tests
luacheck .        # lint
stylua --check .  # format check
```

The compatibility contracts (permissions, convars, events, KVP save schemas) live under
[docs/contracts/](docs/contracts/README.md). [docs/UPSTREAM.md](docs/UPSTREAM.md) covers how
this tracks the upstream C# project when it moves.
