# Migrating from C# vMenu

This resource is a drop-in replacement for [vMenu by Tom Grobbe](https://github.com/tomgrobbe/vMenu).
The whole migration is: **stop the server, swap the resource folder, start the server.**
Nothing else changes — not your config, not your permissions, not your players' saves.

## Steps

1. **Stop your server** (or at least `stop vMenu`).
2. **Back up** your existing `resources/vMenu` folder (you won't need it, but be safe).
3. **Copy your config across.** Take these from your old vMenu folder and put them in this one:
   - `config/addons.json`
   - `config/extras.json`
   - `config/locations.json`
   - `config/model-whitelists.json`
   - `config/tattoos.json`
   (any of these you never customized can be skipped — defaults ship with this resource)
4. **Replace the folder.** Delete the old `resources/vMenu` and put this resource in its place,
   **keeping the folder name `vMenu`**. This matters: client save data (KVP) is keyed by resource
   name, so a different folder name would orphan every player's saved vehicles/peds/loadouts.
5. **Start the server.** Your existing `permissions.cfg` (every `vmenu_*` convar and `vMenu.*`
   ace permission, including `vMenu.Staff.All` style groups and the supplementary
   `vMenu.VehicleWhitelist.*` / `PedWhitelist.*` / `WeaponWhitelist.*` aces) is read unchanged.

## What carries over automatically

| Data | How |
|---|---|
| `permissions.cfg` / server.cfg convars | identical convar + ace names, read the same way |
| `config/*.json` | identical schemas, loaded from the same paths |
| Saved vehicles (`veh_*` KVPs) | identical Newtonsoft-compatible `VehicleInfo` JSON |
| Saved peds (`ped_*` KVPs) | identical `PedInfo` JSON |
| Saved MP characters (`mp_ped_*` KVPs) | identical `MultiplayerPedData` JSON (yes, including the `PedTatttoos` typo) |
| MP character categories (`mp_character_category_*`) | identical |
| Weapon loadouts (`vmenu_string_saved_weapon_loadout_*`) | identical `ValidWeapon` list JSON |
| Personal settings (`settings_*` KVPs) | identical keys and value encodings ("True"/"False" strings) |
| Menu / NoClip keybinds | identical `vMenu:{id}:MenuToggle` / `vMenu:{id}:NoClip` key mappings (FiveM stores the player's binding against the command name, so bindings survive) |
| Bans (`vmenu_ban_*` KVPs) | identical ban record JSON; `vmenuserver` unban/migrate commands work the same |
| Third-party integrations | the full `vMenu:*` client/server event protocol is identical |

## What's intentionally different

- **No .NET runtime.** This is pure CfxLua 5.4 — no `vMenu.net.dll`, no mono overhead.
- **The upstream dev backdoor is not ported** (the hardcoded-identifier `vMenu.Dev` bypass).
- A handful of upstream bugs where the code plainly contradicts its intent were fixed and are
  marked with comments in the source (e.g. the Ped Collections menu that could never populate).
  Load-bearing quirks (serialization typos, swapped assignments that affect saved data) are
  all preserved.
- **Menu input is arrow-keys-only on keyboard.** Upstream (via MenuAPI) also lets WASD drive the
  menu because the game binds its nav controls to WASD as well as the arrow keys. This resource
  reads the physical arrow keys directly, so WASD stays free for movement. The full keyboard/mouse
  scheme is: arrows to move, Enter to select, Backspace/Escape to go back, left-click to select,
  right-click to go back, scroll wheel to move up/down. Controller navigation is unchanged.

## Downgrading back to C# vMenu

Saves written by this resource are readable by C# vMenu with one caveat: records that contain
*empty* lists (e.g. an MP character with no tattoos saved by this resource) may serialize as `{}`
where Newtonsoft expects `[]`. Characters saved by C# vMenu are untouched unless you re-save
them here. If you plan to A/B test, back up player KVPs first.

## Troubleshooting

- **Menu doesn't open:** check `vmenu_use_permissions`; with permissions enabled a player needs
  at least one `vMenu.*` ace. Staff-only mode (`vmenu_menu_staff_only`) requires `vMenu.Staff`.
- **Players lost their saves:** the resource folder isn't named `vMenu`. Rename it back —
  the KVPs are still on the clients, keyed to the old name.
- **Addon vehicles/peds/weapons missing:** copy your `config/addons.json` over (step 3).
- **`vmenuserver` commands:** same syntax as upstream (`vmenuserver ban/unban/weather/time/
  migrate...`), restricted to console/ace-permitted principals.
