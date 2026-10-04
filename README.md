# lua-vMenu (stable)

This branch is a Lua port of [vMenu Enhanced](https://github.com/TomGrobbe/vMenu/tree/enhanced), Tom Grobbe's rewrite of vMenu. It aims to be a drop-in for the C# build, with the same folder name, permissions, settings, player saves and plugins. Unlike upstream, it runs on both FiveM Legacy and FiveM Enhanced.

The port is in progress and not ready for a live server yet. For the classic vMenu in Lua, use the [`original` branch](https://github.com/oyuh/lua-vMenu/tree/original), which is finished and tracks upstream's `legacy` branch.

## Credits

- **vMenu and vMenu Enhanced**: Tom Grobbe (Vespura), <https://github.com/TomGrobbe/vMenu>
- **MenuAPI**: Tom Grobbe, <https://github.com/TomGrobbe/MenuAPI>
- **Lua port**: Lawson ([oyuh](https://github.com/oyuh))

## License

vMenu Enhanced is GPL-3.0-or-later, so this port is too. If you hand a modified copy to anyone, you have to give them the source. Files copied from MenuAPI keep their LGPL-3.0-or-later license. [LICENSE.md](LICENSE.md) has the full text.

## Progress

The port follows the phases in [docs/BRANCH-PLAN.md](docs/BRANCH-PLAN.md):

0. Branch setup: done
1. Foundation (platform layer, settings, permissions, example files, storage): done
2. Menu engine (MenuAPI with native and NUI rendering, themes, languages): in progress
3. Plugins
4. Menus, wave 1
5. Menus, wave 2
6. Server extras (webhooks, update checker, integrations)
7. Parity and `stable-v1.0.0`

## Install

Builds aren't published yet. Once they are, each `stable-v*` release ships a zip that extracts as one `vMenu.Enhanced` folder. Keep that name, because the resource refuses to start under any other. Then add these lines to your `server.cfg`, in this order:

```ini
add_filesystem_permission vMenu.Enhanced write vMenu.Enhanced
ensure vMenu.Enhanced
```

FiveM Enhanced needs the first line before vMenu can write its example config files. FiveM Legacy already lets a resource write to its own folder, so the line is harmless there.

## Development

The code is Lua 5.4. Tests run on [busted](https://lunarmodules.github.io/busted/) with the FiveM natives mocked, so you don't need a game server. Lint with [luacheck](https://github.com/lunarmodules/luacheck) and format with [StyLua](https://github.com/JohnnyMorganz/StyLua):

```sh
busted
luacheck .
stylua --check .
```

[docs/UPSTREAM.md](docs/UPSTREAM.md) explains how this branch follows upstream's `enhanced` releases.
