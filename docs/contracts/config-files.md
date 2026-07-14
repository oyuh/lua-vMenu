# Contract: config JSON files

Source: `SharedClasses/ConfigManager.cs` (locations), `vMenuServer/config/*` and the client
addon/whitelist loaders (upstream @ `49e53065`). Files ship verbatim in `config/` and are read
with `LoadResourceFile(GetCurrentResourceName(), "config/<file>.json")`.

**Error tolerance is part of the contract:** a missing/empty/corrupt file must log a warning
(client: `vMenu:Notify` error; server: console) and degrade to empty data — never abort the
resource.

## `config/locations.json`

```json
{
    "teleports": [
        { "name": "Legion Square", "coordinates": { "x": 215.8, "y": -810.1, "z": 30.7 }, "heading": 158.0 }
    ],
    "blips": [
        { "name": "Legion Square", "coordinates": { "x": 215.8, "y": -810.1, "z": 30.7 }, "spriteID": 280, "color": 0 }
    ]
}
```

- Field names lowercase as shown (`spriteID` has the capital ID).
- `coordinates` deserializes into CitizenFX `Vector3` — accepts `x`/`y`/`z` (Newtonsoft is
  case-insensitive on match; we accept both cases, write lowercase).
- `vMenu:SaveTeleportLocation` **appends** to this file server-side via `SaveResourceFile` —
  the Lua server must preserve the existing structure when rewriting.

## `config/addons.json`

```json
{
    "vehicles": [ "spawn_name1", "spawn_name2" ],
    "peds": [ "model_name" ],
    "weapons": [ "weapon_name" ]
}
```

Unknown keys ignored; missing keys = empty lists.

## `config/extras.json`

Extra menu entries/toggles (shape owned by the extras loader — port 1:1 during M7 and extend
this doc then).

## `config/model-whitelists.json`

```json
{
    "vehicles": [ "adder" ],
    "peds": [ "a_f_y_beach_01" ],
    "weapons": [ "weapon_pistol" ]
}
```

Each listed model requires the matching supplementary ace
(`vMenu.<Category>.WhitelistedModels.<model>` or `.All`) — see
[permissions.md](permissions.md).

## `config/tattoos.json` and `data/overlays.json`

Tattoo/overlay collection metadata consumed by `TattoosData.cs` — schema documented when
`scripts/gen-data` ports the data tables (M6). Ship the files unchanged.

## `vmenu.log`

Not config, but file I/O contract: when `vmenu_log_ban_actions` / `vmenu_log_kick_actions` are
enabled the server appends `[\t<dd-MM-yyyy HH:mm:ss>\t] [BAN ACTION] <message>` lines to
`vmenu.log` via `SaveResourceFile` (read-modify-write of the whole file).
