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

🚧 **Milestone 0 — bootstrap.** Not yet usable. See PLAN.md §8 for the roadmap.

## Development

Toolchain: Lua 5.4, [busted](https://lunarmodules.github.io/busted/) (tests),
[luacheck](https://github.com/lunarmodules/luacheck) (lint),
[StyLua](https://github.com/JohnnyMorganz/StyLua) (format).

```sh
busted            # run unit tests (pure Lua, no FiveM needed — natives are mocked)
luacheck .        # lint
stylua --check .  # format check
```
