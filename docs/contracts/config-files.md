# Contract: config JSON files

Source: `SharedClasses/ConfigManager.cs` (locations), `vMenuServer/config/*` and the client
addon/whitelist loaders (upstream @ `49e53065`). Files ship verbatim in `config/` and are read
with `LoadResourceFile(GetCurrentResourceName(), "config/<file>.json")`.

**Error tolerance is part of the contract:** a missing/empty/corrupt file must log a warning
(client: `vMenu:Notify` error; server: console) and degrade to empty data. It should never
abort the resource.

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

- Field names are lowercase as shown (`spriteID` has the capital ID).
- `coordinates` deserializes into CitizenFX `Vector3`. Newtonsoft is case-insensitive on
  match, so we accept both cases and write lowercase.
- `vMenu:SaveTeleportLocation` **appends** to this file server-side via `SaveResourceFile`,
  so the Lua server must preserve the existing structure when rewriting.

## `config/addons.json`

```json
{
    "vehicles": [ "spawn_name1", "spawn_name2" ],
    "peds": [ "model_name" ],
    "weapons": [ "weapon_name" ]
}
```

Unknown keys are ignored; missing keys mean empty lists.

## `config/extras.json`

Per-vehicle extra labels: `{ "<model name>": { "<extra index>": "label" } }`. The loader
(`set_extras` in `client/events.lua`) keys the result by model hash, keeps the indexes as
string keys (matching how C#'s `Dictionary<int,string>` arrives in JSON), and warns about
duplicate extra indexes for the same model.

## `config/model-whitelists.json`

```json
{
    "vehicles": [ "adder" ],
    "peds": [ "a_f_y_beach_01" ],
    "weapons": [ "weapon_pistol" ]
}
```

Each listed model requires the matching supplementary ace
(`vMenu.<Category>.WhitelistedModels.<model>` or `.All`). See
[permissions.md](permissions.md).

## `config/tattoos.json` and `data/overlays.json`

Tattoo/overlay collection metadata, same schema upstream's `TattoosData.cs` consumes. Loaded
by `set_tattoos` in `client/events.lua` with the sorting half in `client/tattoos.lua`. Ship
the files unchanged.

## `vmenu.log`

Not config, but a file I/O contract: when `vmenu_log_ban_actions` / `vmenu_log_kick_actions`
are enabled the server appends `[\t<dd-MM-yyyy HH:mm:ss>\t] [BAN ACTION] <message>` lines to
`vmenu.log` via `SaveResourceFile` (a read-modify-write of the whole file).
