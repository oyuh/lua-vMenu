# Migrating from C# vMenu

This resource drops in on top of [vMenu by Tom Grobbe](https://github.com/tomgrobbe/vMenu).
Stop the server, swap the folder, start the server. Your config, your permissions, and your
players' saves all stay where they are.

## Steps

1. **Stop your server**, or at least `stop vMenu`.
2. **Back up** your existing `resources/vMenu` folder. You probably won't need it. Back it up
   anyway.
3. **Copy your config across.** From the old vMenu folder into this one:
   - `config/addons.json`
   - `config/extras.json`
   - `config/locations.json`
   - `config/model-whitelists.json`
   - `config/tattoos.json`

   Skip any you never customized, defaults ship with this resource.
4. **Replace the folder.** Delete the old `resources/vMenu`, drop this resource in its place,
   folder still named `vMenu`. That name matters: client save data (KVP) is keyed by resource
   name, so renaming the folder orphans every player's saved vehicles, peds, and loadouts.
5. **Start the server.** Your existing `permissions.cfg` is read unchanged. Every `vmenu_*`
   convar and `vMenu.*` ace, including `vMenu.Staff.All` style groups and the supplementary
   `vMenu.VehicleWhitelist.*` / `PedWhitelist.*` / `WeaponWhitelist.*` aces.

## What carries over on its own

| Data | How |
|---|---|
| `permissions.cfg` / server.cfg convars | identical convar + ace names, read the same way |
| `config/*.json` | identical schemas, loaded from the same paths |
| Saved vehicles (`veh_*` KVPs) | identical Newtonsoft-compatible `VehicleInfo` JSON |
| Saved peds (`ped_*` KVPs) | identical `PedInfo` JSON |
| Saved MP characters (`mp_ped_*` KVPs) | identical `MultiplayerPedData` JSON, `PedTatttoos` typo and all |
| MP character categories (`mp_character_category_*`) | identical |
| Weapon loadouts (`vmenu_string_saved_weapon_loadout_*`) | identical `ValidWeapon` list JSON |
| Personal settings (`settings_*` KVPs) | identical keys and value encodings ("True"/"False" strings) |
| Menu / NoClip keybinds | identical `vMenu:{id}:MenuToggle` / `vMenu:{id}:NoClip` key mappings (FiveM stores each player's binding against the command name, so bindings survive) |
| Bans (`vmenu_ban_*` KVPs) | identical ban record JSON; `vmenuserver` unban/migrate commands work the same |
| Third-party integrations | the full `vMenu:*` client/server event protocol is identical |

## What's different on purpose

- **No .NET runtime.** Pure CfxLua 5.4. No `vMenu.net.dll`, no mono overhead.
- **The upstream dev backdoor is gone** (the hardcoded-identifier `vMenu.Dev` bypass).
- **A few upstream bugs are fixed**, the ones where the code plainly contradicts its own
  intent, like the Ped Collections menu that could never populate. Each fix carries a comment
  in the source. Load-bearing quirks (serialization typos, swapped assignments that affect
  saved data) stay exactly as they are.
- **Menu input is arrow keys only on keyboard.** Upstream, through MenuAPI, also drives the
  menu with WASD, because the game binds its nav controls to WASD as well as the arrows. This
  resource reads the physical arrow keys, so WASD stays free for movement. Full scheme: arrows
  to move, Enter to select, Backspace/Escape to go back, left-click to select, right-click to
  go back, scroll wheel up/down. Controller navigation is unchanged.
- **Some server events are gated that upstream leaves open.** Ban list, identifiers, player
  list, and clear-area now check aces server side. A stock client notices nothing, since it
  only sends those when the player holds the permission. Details in
  [contracts/events.md](contracts/events.md).

## Downgrading back to C# vMenu

Saves written here are readable by C# vMenu, with one caveat: records holding *empty* lists,
say an MP character with no tattoos saved by this resource, can serialize as `{}` where
Newtonsoft expects `[]`. Characters saved by C# vMenu are untouched unless you re-save them
here. If you plan to A/B test, back up player KVPs first.

## Troubleshooting

- **Menu doesn't open.** Check `vmenu_use_permissions`. With permissions on, a player needs at
  least one `vMenu.*` ace, and staff-only mode (`vmenu_menu_staff_only`) wants `vMenu.Staff`.
- **Fresh install, nobody has admin.** The shipped `permissions.cfg` ships its example
  `add_principal` lines commented out, matching upstream. Uncomment them with your own
  identifiers, or let TxAdmin or whatever else manages your aces handle it. Servers migrating
  from C# vMenu keep their own `permissions.cfg` and aren't affected.
- **Players lost their saves.** The resource folder isn't named `vMenu`. Rename it back and
  the saves return, the KVPs are still sitting on the clients under the old name.
- **Addon vehicles/peds/weapons missing.** Copy your `config/addons.json` over, step 3.
- **`vmenuserver` commands.** Same syntax as upstream (`vmenuserver ban/unban/weather/time/
  migrate...`), restricted to console and ace-permitted principals.
