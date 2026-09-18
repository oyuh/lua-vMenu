# Contract: config JSON files

Source: `SharedClasses/ConfigManager.cs` (locations), `vMenuServer/config/*`, and the client
addon/whitelist loaders (upstream @ `e0f3b92a`). The files ship verbatim in `config/` and get
read with `LoadResourceFile(GetCurrentResourceName(), "config/<file>.json")`.

**Error tolerance is part of the contract.** A missing, empty, or corrupt file logs a warning
(client: `vMenu:Notify` error, server: console) and degrades to empty data. It never aborts
the resource.

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

- Field names are lowercase as shown, and yes, `spriteID` has the capital ID.
- `coordinates` deserializes into a CitizenFX `Vector3`. Newtonsoft matches case-insensitively,
  so we accept either case and write lowercase.
- `vMenu:SaveTeleportLocation` **appends** to this file server side through `SaveResourceFile`,
  so the Lua server has to preserve the existing structure when it rewrites.

## `config/addons.json`

```json
{
    "vehicles": [ "spawn_name1", "spawn_name2" ],
    "peds": [ "model_name" ],
    "weapons": [ "weapon_name" ]
}
```

Unknown keys are ignored. Missing keys mean empty lists.

## `config/extras.json`

Per-vehicle extra labels: `{ "<model name>": { "<extra index>": "label" } }`. The loader,
`set_extras` in `client/events.lua`, keys the result by model hash and keeps the indexes as
string keys, matching how C#'s `Dictionary<int,string>` arrives in JSON. Duplicate extra
indexes on the same model get a warning.

## `config/model-whitelists.json`

```json
{
    "vehicles": [ "adder" ],
    "peds": [ "a_f_y_beach_01" ],
    "weapons": [ "weapon_pistol" ]
}
```

Each listed model needs the matching supplementary ace
(`vMenu.<Category>.WhitelistedModels.<model>` or `.All`). See [permissions.md](permissions.md).

## `config/tattoos.json` and `data/overlays.json`

Tattoo and overlay collection metadata, the same schema upstream's `TattoosData.cs` eats.
Loaded by `set_tattoos` in `client/events.lua`, with the sorting half in `client/tattoos.lua`.
Ship the files unchanged.

## `vmenu.log`

Not config, but it is a file I/O contract. With `vmenu_log_ban_actions` or
`vmenu_log_kick_actions` enabled, the server appends
`[\t<dd-MM-yyyy HH:mm:ss>\t] [BAN ACTION] <message>` lines to `vmenu.log` through
`SaveResourceFile`, which rewrites the whole file each time.
