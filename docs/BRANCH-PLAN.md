# Branch plan: original and stable

Upstream vMenu split in two. `legacy` is the vMenu everyone knows. `enhanced` is a from-scratch
rewrite called vMenu Enhanced, and it's the default branch now. This repo follows with two
branches of its own:

| | `original` | `stable` |
|---|---|---|
| What it is | This repo as it is today | A Lua port of vMenu Enhanced |
| Tracks upstream | `legacy` (pin `f615b15b`, no code changes since our `e0f3b92a`) | `enhanced` (pin release tag `enhanced-v1.0.3`, `ee284020`) |
| Look | MenuAPI drawn with natives | MenuAPI drawn natively or in the browser (NUI), with themes |
| Resource folder | `vMenu` | `vMenu.Enhanced` |
| Permissions, settings | `vMenu.*` aces, `vmenu_*` convars, one `permissions.cfg` | `vMenu.Enhanced.*` aces, `permissions.cfg` and `configuration.cfg`, examples written by the resource |
| Player saves | Legacy KVP keys and formats | Enhanced KVP envelope format, `VME1` transfer codes |
| Plugins | No | Yes, upstream's protocol v1, so C# and Lua plugins both work |
| Runs on | FiveM Legacy and FiveM Enhanced | FiveM Legacy and FiveM Enhanced |
| License | Original vMenu license (unchanged) | GPL-3.0-or-later (required, it's a port of GPL code). The MenuAPI web files are LGPL-3.0 |
| Release tags | `v1.x.y` (keeps the existing series) | `stable-v0.x.y` until parity, then `stable-v1.0.0` |

Each branch is a drop-in for its upstream counterpart: same folder name, same config, same
permissions, same saves. That's the promise `original` already makes, and `stable` makes the
same one for vMenu Enhanced. On top of that, `stable` runs on FiveM Legacy, which upstream's
version doesn't.

## Why the stable folder has to be `vMenu.Enhanced`

- Plugins hardcode it. Every protocol event starts with `vMenu.Enhanced:Plugins`, plugin
  permissions are `vMenu.Enhanced.Plugins.<Id>.<Name>`, and the C# client API watches
  `onResourceStop` for `vMenu.Enhanced` to notice vMenu going away.
- KVP is scoped to the resource name, so player saves from upstream's build only show up under
  that name.
- Upstream refuses to start under any other name. We match that check.

## Branch mechanics

1. Rename `main` to `original` on GitHub (`gh api -X POST repos/oyuh/lua-vMenu/branches/main/rename -f new_name=original`).
   GitHub redirects old links and open PRs. Update `ci.yml` (`branches: [main]`) and the
   `blob/main` links in `release.yml` and the docs.
2. Create `stable` from `original`. That keeps the history and everything both branches share:
   the `require` shim in `shared/bootstrap.lua`, `shared/json_compat.lua` (comment tolerant JSON,
   which the plugin protocol needs too), the busted harness and native mocks, luacheck, StyLua
   and CI. Fix a shared file on one branch, then cherry-pick it to the other. No submodule or
   shared package. Two branches don't need one.
3. Release workflows: `original` keeps `on: push: tags: ['v*']`. `stable` gets its own
   `release.yml` on `stable-v*` that zips a `vMenu.Enhanced/` folder. `v*` doesn't match
   `stable-v*`, so neither workflow catches the other's tags.
4. Default branch stays `original` until `stable` has a release people can actually run, then
   switches to `stable`.
5. Each branch gets its own `docs/UPSTREAM.md` pin. `scripts/upstream-diff.ps1` stops
   hardcoding `origin/master` and reads the upstream branch from that file (`legacy` or
   `enhanced`). Ignore upstream's `develop`. Port from `enhanced` release tags, not every commit,
   because upstream lands dozens of commits a week (266 in August alone).

## original: what's left

Small, because upstream `legacy` has no code changes since our pin.

1. Bump the pin to `f615b15b` and point the diff script at `origin/legacy`.
2. Run on FiveM Enhanced too. The known gaps:
   - Writing files needs `add_filesystem_permission vMenu write vMenu` before `ensure`. We write
     in `server/main.lua` (the log, `locations.json`, the permission template) and
     `server/bans.lua` (the log). Check the `SaveResourceFile` result and print a message naming
     the missing line.
   - Server IDs get reused after a disconnect on Enhanced. Legacy never reused them. Check
     everything keyed by server ID and clear it on `playerDropped`.
   - Steam identifiers are gone. Ban matching is generic, so nothing to do beyond a docs note.
   - KVP files need Cfx's migration script, and on Enhanced they aren't shared between server
     addresses. Docs only.
   - Mumble natives are deprecated (`NetworkSetVoiceChannel` in `functions_controller/hud.lua`).
     Leave them alone until Cfx removes them.
   - Add an "Installing on FiveM Enhanced" section to the README and `docs/MIGRATION.md`.
3. Optional: a txAdmin recipe like upstream's (`assets/txadmin/`) that installs our zip.
4. Optional: export a `VME1` transfer code so players can carry their saves into `stable`.
   `stable` runs under a different resource name and can't read `original`'s KVP, so this would
   be the only bridge. It needs research first: the code is compressed, and Lua has no built-in
   deflate.

## stable: architecture

Upstream Enhanced is about 95,000 lines of C# across 33 projects, plus 200 KB of web UI.
Upstream legacy was 28,500 lines and became about 23,000 lines of Lua, so expect `stable` to land
somewhere around 70,000 to 80,000. It's about three times the size of the first port.

### Project to module map

| Upstream (C#) | Lines | Here (Lua) | Notes |
|---|---|---|---|
| `MenuAPI.FiveM.Enhanced` 1.0.28 (TomGrobbe/MenuAPI `fivem-enhanced`) | 8,500 | `menu/` | Upgrade our MenuAPI port. Add the NUI render mode next to the native one. Ship upstream's `ui/menuapi/*.js|css` unchanged (LGPL). |
| `vMenu.Enhanced.MenuFramework` | 11,300 | `client/framework/` | Menu definitions, builder, entries, gates, confirm rows, input prompt, notifications, HUD anchors, localization. |
| `vMenu.Enhanced.Menus` | 47,900 | `client/menus/` | Same folder layout as upstream (`Players/`, `Vehicles/`, `Weapons/`, `World/`, `Admin/`, `Props/`, `Teleport/`, `Misc/`, `Developer/`). |
| `vMenu.Enhanced.Data` | 7,300 | `shared/data/` | The permission and setting catalogs, event names, weather and time tables. |
| `vMenu.Enhanced.Storage` + `Serialization` | 1,600 | `client/storage.lua` | KVP envelope, merge-preserving-newer writes, transfer codes. |
| `vMenu.Enhanced.Permissions` + `.Server` | 2,100 | `shared/permissions.lua`, `server/permissions.lua` | Permission tree, example file writer, sync, supplemental vehicle, ped and weapon permissions. |
| `vMenu.Enhanced.Configuration` + `.Server` | 800 | `shared/config.lua`, `server/config.lua` | Settings as convars, example file writer, server clock and world snapshot. |
| `vMenu.Enhanced.Actions` + `.Server` | 7,400 | `server/actions/` | Server-side action handlers, rate limiting, security log, spawned entity registries. |
| `vMenu.Enhanced.Plugins` + `.Server` | 3,200 | `client/plugins/`, `server/plugins.lua` | See Plugins below. |
| `vMenu.Enhanced.Webhooks.Server` | 1,700 | `server/webhooks.lua` | `PerformHttpRequest`, queue and throttle. |
| `vMenu.Enhanced.Http.Server` + `Integration.Server` | 4,200 | `server/integration/` | HTTP endpoints through `SetHttpHandler`. Lua can't open WebSockets, so ship upstream's `server/net_bridge.js` and talk to it. |
| `vMenu.Enhanced.Updates.Server` | 600 | `server/updates.lua` | Point it at our releases, not upstream's. |
| `vMenu.Enhanced.Events`, `Ticks`, `NoClip`, `Core` | 2,600 | `client/events.lua`, `client/ticks.lua`, `client/noclip.lua`, `client/main.lua` | Keep `original`'s pattern: a tick only exists while its feature is on. |
| `vMenu.Enhanced.BrokenNatives`, `NativeHooks` | 470 | mostly nothing | Almost all of it works around the C# runtime (MessagePack byte arrays, function references). Keep only the 8-byte-per-field struct layouts for head blend, shop ped and weapon HUD stats. |
| `assets/enhanced/ui`, `language`, `config` | | `ui/`, `language/`, `config/` | Copied unchanged. Lua sends the same NUI messages the C# does, so upstream's JS runs as is. |
| `EnglishStrings.cs` | | `shared/data/english.lua` | Generated by a script, like `scripts/gen-data.ps1`. |

### Platform layer

One codebase and one zip for both platforms. `shared/platform.lua` stays small and only covers
differences we've actually confirmed:

- `Platform.is_enhanced`: no documented way to detect it yet. Find out on a real server by
  printing `GetGameBuildNumber()`, `GetGameName()` and `GetConvar('version', '')` on each
  platform. Upstream still gates drift tyres on build `2372` inside Enhanced code, so build
  numbers seem to line up, but that's unverified.
- `Platform.has(native_name)`: CfxLua defines natives as globals from each platform's native
  database, so a native the Legacy game lacks shows up as `nil`. Gate the menu rows that need one
  with it. Upstream calls about 680 distinct natives, and nearly all are plain GTA natives found
  in both games.
- `Platform.save_file(path, contents)`: wraps `SaveResourceFile` and prints the missing
  `add_filesystem_permission` line on failure.
- Differences the code has to tolerate without a branch:
  - Enhanced only fires state bag callbacks for entities that exist. Legacy fires them anyway.
  - Enhanced reuses server IDs. Key per-player state by license identifier, or clear it on
    `playerDropped`.
  - Enhanced has no Steam identifiers.
  - KVP is per server address on Enhanced. That's why the transfer codes exist.
- `net_bridge.js` declares `node_version '22'`. Check that current Legacy artifacts support it.
  Only integrations need it, so if they don't, integrations become Enhanced-only and nothing else
  changes.

### Plugins

Plugins are separate resources that talk to vMenu through local events carrying JSON strings.
Protocol version 1, straight from upstream's `PluginContracts`:

- **Client, plugin to vMenu:** `vMenu.Enhanced:Plugins:Probe`, `Register`, `Unregister`,
  `Update`, `Notify`, `Prompt`, `SetTheme`, `RegisterThemes`.
- **Client, vMenu to plugins:** `vMenu.Enhanced:Plugins:Ready` to everyone, plus per-resource
  events (`vMenu.Enhanced:Plugins:<resource>:Ready`, `RegisterResult`, `Event`, `PromptResult`,
  `Themes`, `ThemesRegistered`).
- **Server:** `vMenu.Enhanced:Plugins:Server:Probe`, `Server:Register`, `Server:Denied`, and
  `Server:Ready` plus the per-resource replies.
- **Payloads:** camelCase JSON with case-insensitive reads. A menu tree of `button`, `checkbox`,
  `list`, `slider`, `dynamicList`, `submenu`, `separator`, `confirmButton` and `confirmList`
  rows. Gates (`permission`, `setting`, `all`, `any`), translations, Online Players actions, and
  update batches (`setText`, `addItems`, `openMenu` and the rest of `UpdateOps`).
- **Server declarations:** permissions become `vMenu.Enhanced.Plugins.<Id>.<Name>` and settings
  become convars with the same prefix. Example files go into `config/plugins/<resource>.*.cfg.example`.
  Logged items feed the webhooks.
- **Sender identity:** always taken from `GetInvokingResource()`, never from the payload.
  Upstream's limits apply: 2,000 items, nesting 8 deep, 100 logged items. One plugin can't claim
  another's sanitized ID.

What ships:

1. The host, in `client/plugins/` and `server/plugins.lua`: a Plugins submenu in the main menu
   and a Plugin Actions submenu in Online Players.
2. A Lua helper so Lua plugins don't have to build JSON by hand. A plugin resource adds
   `client_script '@vMenu.Enhanced/plugin/client.lua'` and `server_script '@vMenu.Enhanced/plugin/server.lua'`
   and gets a small API shaped like upstream's `ClientAPI`/`ServerAPI`. Lua plugins run on both
   platforms.
3. C# plugins built on `vMenu.Enhanced.ClientAPI` should work unchanged. They need FiveM
   Enhanced's C# runtime, so in practice they're Enhanced-only.
4. Test against the official plugins: Example, Routing Buckets, Theme Picker and Custom Themes.
   The last two need the NUI themes from phase 2.

## stable: phases

Each phase ends with something that runs on both a Legacy and an Enhanced server.

0. **Branch setup.** Everything under Branch mechanics. Swap in the GPL-3.0 `LICENSE.md` and
   upstream's notice, and credit MenuAPI's LGPL files. Strip the old modules `stable` won't keep
   so it starts clean.
1. **Foundation.** The platform layer, logging, the settings and permission catalogs, and the
   example `permissions.cfg.example` and `configuration.cfg.example` writers. Golden-file tests
   compare them to upstream's generated output. Also the KVP envelope store. Milestone: the
   server boots and writes the same example files upstream does.
2. **Menu engine.** The MenuAPI port in both render modes, the MenuFramework, themes and banners,
   and the language loader (translations live in the framework's menu text). Milestone: an empty
   main menu opens on both platforms with every theme.
3. **Plugins.** The host, the server registry and the Lua helper. This comes early because the
   protocol is self-contained and gives the framework a real workout. Player actions wait for
   Online Players. Milestone: the Example plugin works.
4. **Menus, wave 1.** Player options, ped models, saved peds, appearance. Vehicle spawner,
   options, saved and personal vehicles. Weapons and loadouts. World (time, weather, forecast).
   Teleport, noclip, recording.
5. **Menus, wave 2.** Character creator and outfit presets. Online Players and the Admin menu
   (freeze, hold, report, announcements, clear area). Staff alerts. Prop spawner and saved prop
   sets. Display, misc and developer settings. Auto pilot. Data transfer.
6. **Server extras.** Webhooks, the update checker, integrations.
7. **Parity.** Audit against upstream, run the `docs/VERIFY.md` checklist on both platforms, tag
   `stable-v1.0.0`, make `stable` the default branch.

## Risks and open questions

- **Platform detection.** Unknown until we test on a FiveM Enhanced server. Nothing in phases 0
  to 2 depends on it.
- **Upstream moves fast.** Pin a release tag, port release to release, and keep one diff list
  per pin bump.
- **License.** `stable` has to be GPL-3.0-or-later. Anyone redistributing a modified copy has to
  publish the source. `original` keeps its current license.
- **Node 22 on Legacy artifacts.** Only integrations need it.
- **Saves from `original` to `stable`.** Different resource names, so no shared KVP. The `VME1`
  export in `original` is the only bridge, and it isn't scoped yet.
