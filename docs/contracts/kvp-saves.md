# Contract: KVP save data

Sources: `vMenu/StorageManager.cs`, `vMenu/CommonFunctions.cs` (VehicleInfo/PedInfo, save/load),
`vMenu/MpPedDataManager.cs`, `vMenu/UserDefaults.cs`, `vMenu/menus/{SavedVehicles,MpPedCustomization,WeaponLoadouts}.cs`,
`vMenuServer/BanManager.cs` (upstream @ `49e53065`).

**Why this works at all:** FiveM KVP storage is keyed by *resource name*. Deployed as `vMenu`,
the Lua rewrite reads the same physical store the C# version wrote. Everything below is about
keeping the *values* byte-compatible with Newtonsoft.Json output.

Golden fixtures live in `tests/fixtures/`. They were derived from the struct definitions and
should be re-validated against a real C# vMenu save whenever the save schemas are touched.

## Newtonsoft encoding rules we must reproduce

- Public **fields** serialize under their exact C# names. That's mixed camelCase/PascalCase per
  struct, no renaming, and no ordering requirements (JSON objects are unordered).
- Public **read-only properties** are *also serialized* on save and *ignored* on load
  (ValidWeapon's `GetMaxAmmo`, `Accuracy`, `Damage`, `Range`, `Speed`).
- Enums serialize as **numbers** (`Perm`, `Icon` fields).
- `Dictionary<int, T>` becomes a JSON object with **string keys** (`"0": …`).
- `KeyValuePair<A, B>` becomes `{"Key": a, "Value": b}`.
- `DateTime` becomes ISO `"3000-01-01T00:00:00"` (no timezone suffix).
- `Guid` becomes a lowercase hyphenated string.
- `uint` model hashes are full 32-bit values (they can exceed 2^31, so Lua must not go through
  signed-32 truncation).
- Loader tolerance: upstream wraps loads in try/catch and returns empty/default on bad JSON.
  Never crash on a corrupt save.

## Client KVP keys

| Key pattern | Value | Fixture |
|---|---|---|
| `veh_<name>` | `VehicleInfo` JSON | `vehicle_info.json` |
| `saved_veh_category_<name>` | `{Name, Description, Icon:int}` | `category.json` |
| `ped_<name>` | `PedInfo` JSON (classic peds) | `ped_info.json` |
| `mp_ped_<name>` | `MultiplayerPedData` JSON | `mp_ped_data.json` |
| `mp_character_category_<name>` | `{Name, Description, Icon:int}` | `category.json` |
| `vmenu_string_saved_weapon_loadout_<name>` | `ValidWeapon[]` JSON | `weapon_loadout.json` |
| `vmenu_temp_weapons_loadout_before_respawn` | `ValidWeapon[]` JSON (transient) | same |
| `settings_<name>` | typed KVP, see below | (none) |

### `settings_*` (UserDefaults) encoding: mind the capital letters

| C# type | Storage call | Wire form |
|---|---|---|
| bool | `SetResourceKvp(key, value.ToString())` | string **`"True"` / `"False"`** (capitalized!) |
| int | `SetResourceKvpInt` | native int KVP |
| float | `SetResourceKvpFloat` | native float KVP |
| string | `SetResourceKvp` | plain string |

The Lua port must **write** `"True"`/`"False"` exactly and read them case-correctly, and must
use the matching typed getter (`GetResourceKvpInt` vs `...String` vs `...Float`) per key. The
key names (`settings_playerGodMode`, `settings_miscRightAlignMenu`, …) are enumerated in
`client/user_defaults.lua`.

## Server KVP keys

| Key pattern | Value | Fixture |
|---|---|---|
| `vmenu_ban_<uuid>` | `BanRecord` JSON | `ban_record.json` |

`BanRecord`: `{playerName, identifiers: string[], bannedUntil: DateTime, banReason, bannedBy,
uuid}`. Permanent bans use `bannedUntil` year ≥ 3000 (written as 3000-01-01), and the ban uuid
is appended to `banReason` as `"\nYour ban id: <uuid>"` at construction.

## Struct field references

### `VehicleInfo` (camelCase except `Category`!)
`colors` (object: primary/secondary/pearlescent/wheels/dash/trim, all ints), `customWheels`,
`extras` (int-keyed bools), `livery`, `model` (uint), `mods` (int-keyed ints), `name`,
`neonBack`, `neonFront`, `neonLeft`, `neonRight`, `plateText`, `plateStyle`, `turbo`,
`tyreSmoke`, `version`, `wheelType`, `windowTint`, `xenonHeadlights`, `bulletProofTires`,
`headlightColor`, `enveffScale` (float), `Category` (PascalCase, an upstream quirk).

### `PedInfo`
`version`, `model` (uint), `isMpPed`, `props`, `propTextures`, `drawableVariations`,
`drawableVariationTextures` (all int-keyed int objects).

### `MultiplayerPedData` (PascalCase)
`PedHeadBlendData` (CitizenFX struct; field names should be re-checked against a real save),
`DrawableVariations{clothes}`, `PropVariations{props}` (int-keyed `{Key,Value}` pairs),
`FaceShapeFeatures{features}` (int-keyed floats), `PedAppearance` (camelCase style/color/opacity
fields + `HairOverlay {Key,Value}`), **`PedTatttoos`** (the triple-t typo is load-bearing;
upstream comments "DO NOT RENAME"; nine `[{Key,Value}]` lists), `PedFacePaints` (empty object),
`IsMale`, `ModelHash` (uint), `SaveName`, `Version`, `WalkingStyle`, `FacialExpression`,
`Category`.

### `ValidWeapon`
Fields `Hash` (uint), `Name`, `Components` (object of name to uint hash), `Perm` (a **number**,
the Permission enum ordinal; recompute from weapon data on load, don't trust it), `SpawnName`,
`CurrentAmmo`, `CurrentTint`, plus the serialized read-only props `GetMaxAmmo`, `Accuracy`,
`Damage`, `Range`, `Speed` (write plausible values, ignore on read).

## Validation checklist (before declaring save-compat done)

- [ ] `vehicle_info.json` re-captured from a real C# vMenu save
- [ ] `weapon_loadout.json` re-captured from a real save
- [ ] `ped_info.json` re-captured from a real save
- [ ] `mp_ped_data.json` re-captured from a real save, esp. `PedHeadBlendData` field names
- [ ] `ban_record.json` re-captured from a real C# server
- [ ] Round-trip specs: Lua-load(fixture) → Lua-save → identical semantic content
