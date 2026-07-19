# Contract: event protocol

Source: `vMenuServer/MainServer.cs`, `vMenuServer/BanManager.cs`, `vMenu/EventManager.cs`,
`vMenu/MainMenu.cs`, `vMenu/FunctionsController.cs` (upstream @ `49e53065`).

Third-party resources integrate with vMenu through these events. Every name, argument order,
and argument type must match. JSON-string payloads (not tables!) stay JSON strings, since
upstream serializes with Newtonsoft and the shapes are part of the contract (see
[kvp-saves.md](kvp-saves.md) for record schemas).

Types are the msgpack types on the wire: `int`, `float`, `bool`, `string`, `vector3`
(CitizenFX Vector3), `funcref` (net callback), `object[]`.

## Client → Server

| Event | Arguments | Behavior notes |
|---|---|---|
| `vMenu:KickPlayer` | `int target, string reason` | perm `OPKick`; `DontKickMe` exempts target; unauthorized trigger ⇒ BanCheater |
| `vMenu:KillPlayer` | `int target` | perm `OPKill`; fires `vMenu:KillMe` on target |
| `vMenu:SummonPlayer` | `int target, int numberOfSeats` | perm `OPSummon` |
| `vMenu:TempBanPlayer` | `int target, double banDurationHours, string banReason` | perm `OPTempBan`/`OPAll`/`Everything`; duration capped at 720h; `DontBanMe` exempts |
| `vMenu:PermBanPlayer` | `int target, string banReason` | ban-until = 3000-01-01; same perms as temp ban |
| `vMenu:RequestPlayerUnban` | `string banUuid` | perm `OPUnban`/`OPAll`/`Everything`; unauthorized ⇒ BanCheater |
| `vMenu:RequestBanList` | *(none)* | **hardening deviation:** perm `OPViewBannedPlayers`/`OPUnban`/`OPAll`/`Everything`; unauthorized ⇒ BanCheater (upstream sends to any caller). Replies to source with `vMenu:SetBanList` |
| `vMenu:SendMessageToPlayer` | `int target, string message` | PM system; staff with `OPSeePrivateMessages` get a copy |
| `vMenu:UpdateServerWeather` | `string weather, bool dynamicEnabled, bool snowEnabled` | perm `WOSetWeather`-family |
| `vMenu:UpdateServerBlackout` | `bool enabled` | |
| `vMenu:UpdateServerVehicleBlackout` | `bool enabled` | |
| `vMenu:UpdateServerWeatherCloudsType` | `bool removeClouds` | server picks random cloud type unless removing |
| `vMenu:UpdateServerTime` | `int hour, int minute, bool freezeTime` | |
| `vMenu:FreezeServerTime` | `bool freezeTime` | |
| `vMenu:SaveTeleportLocation` | `string locationJson` | appends TeleportLocation to locations.json + broadcasts `vMenu:UpdateTeleportLocations` |
| `vMenu:RequestPlayerList` | *(none)* | **hardening deviation:** perm `OPMenu`/`OPAll`/`Everything`; unauthorized callers get an empty list (read-only path, no ban). Replies with `vMenu:ReceivePlayerList` |
| `vMenu:GetPlayerCoords` | `long rpcId, int playerId, funcref callback` | perm `OPTeleport` (else replies `0,0,0`); calls back with coords; falls back to `vMenu:GetPlayerCoords:reply` event |
| `vMenu:GetPlayerIdentifiers` | `int target, funcref callback` | **hardening deviation:** perm `OPIdentifiers`/`OPAll`/`Everything`; unauthorized callers get an empty list (read-only path, no ban). `ip:` identifiers are always stripped. Callback receives identifier list |
| `vMenu:GetOutOfCar` | `int vehicleNetId` | personal-vehicle passenger kick; targets get `vMenu:Notify` |
| `vMenu:ClearArea` | *(none; uses source position)* | **hardening deviation:** perm `MSClearArea`; unauthorized ⇒ BanCheater (upstream has **no** server-side check). Broadcasts `vMenu:ClearArea` with source `vector3` to all clients |

## Server → Client

| Event | Arguments | Notes |
|---|---|---|
| `vMenu:SetPermissions` | `string json`: `{ "<PermissionName>": bool, … }` | pushed on `playerJoining` + first-tick sweep (3s after resource start); **no client request event exists** |
| `vMenu:SetSupplementaryPermissions` | `string json`: same shape | follows SetPermissions |
| `vMenu:SetConfigOptions` | *(none)* | tells client to (re)load addons/config |
| `vMenu:SetAddons` | *(none)* | **deprecated alias** of SetConfigOptions; keep handling it |
| `vMenu:UpdateTeleportLocations` | `string json`: `TeleportLocation[]` | sent after perms + whenever a location is saved |
| `vMenu:Notify` | `string message` | GTA notification (supports `~r~` etc. + `<C>` tags) |
| `vMenu:KillMe` | `string killerName` | kills own ped |
| `vMenu:GoodBye` | *(none)* | the "fun" cheater drop |
| `vMenu:SetBanList` | `string json`: `BanRecord[]` | |
| `vMenu:BanSuccessful` | `string json`: `BanRecord` | fired to source after a ban |
| `vMenu:UnbanSuccessful` | `string json`: `BanRecord` | |
| `vMenu:BanCheaterSuccessful` | `string json`: `BanRecord` | |
| `vMenu:SetClouds` | `float opacity, string cloudsType` | |
| `vMenu:ClearArea` | `vector3 position` | broadcast to **all** clients |
| `vMenu:updatePedDecors` | *(none)* | note the lowercase `u`, keep the exact casing |
| `vMenu:PrivateMessage` | `string sourceServerId, string message` | source id as string (Handle) |
| `vMenu:PlayerJoinQuit` | `string playerName, string dropReason` | reason is `null` for joins |
| `vMenu:ReceivePlayerList` | `object[]`: `[{ n = string name, s = int serverId }, …]` | anonymous objects, field names `n`/`s` |
| `vMenu:GetPlayerCoords:reply` | `long rpcId, vector3 coords` | fallback RPC reply |
| `vMenu:UpdateServerWeather` | `string weather, bool dynamicEnabled, bool snowEnabled` | also reused as broadcast |
| `vMenu:UpdateServerTime` | `int hour, int minute, bool freezeTime` | third arg is `!FreezeTime` in the sync loop and `FreezeTime` in the setter path; port faithfully per call site |

## Client-local events (same-client TriggerEvent)

| Event | Arguments | Purpose |
|---|---|---|
| `vMenu:SetupTickFunctions` | *(none)* | (re)registers feature tick handlers |
| `vMenu:WeatherChangeComplete` | *(varies; port from EventManager)* | fired after weather transition |
| `vMenu:InfiniteFuelToggled` | *(bool)* | integration hook for fuel resources |

## Standard events consumed

| Event | Side | Use |
|---|---|---|
| `playerConnecting` | server | ban enforcement; `CancelEvent()` + kick callback with ban message |
| `playerJoining` | server | push permissions, join notification fan-out |
| `playerDropped` | server | quit notification fan-out |
| `playerSpawned` | client | first-spawn appearance/default-character restore |
| `chatMessage` | both | staff-log and PM display via chat resource |

## Security model (must be preserved)

Server handlers re-check ACE permissions on every call and treat an unauthorized trigger as a
cheating attempt: `BanCheater(source)` auto-bans when `vmenu_auto_ban_cheaters` is enabled.
The Lua server must never trust a client-supplied permission claim.

### Intentional hardening deviations from upstream

Upstream leaves a handful of server handlers ungated, relying on the stock client to only send
them when authorized. A modded client bypasses that, so the Lua rewrite adds server-side checks.
These are deliberate behavioral differences (like the removed dev backdoor in
[permissions.md](permissions.md)); the stock client is unaffected because it already only sends
these when the player holds the permission.

- **`vMenu:RequestBanList`** now requires `OPViewBannedPlayers`/`OPUnban`/`OPAll`/`Everything`.
  Upstream replied to any caller, leaking every banned player's full identifier set (including
  `ip:`), ban reasons, and staff names. Unauthorized ⇒ BanCheater.
- **`vMenu:GetPlayerIdentifiers`** now requires `OPIdentifiers`. Read-only, so unauthorized
  callers get `[]` (no auto-ban), matching the `GetPlayerCoords` pattern. `ip:` stays stripped.
- **`vMenu:RequestPlayerList`** now requires `OPMenu` (the only place the client sends it).
  Read-only: unauthorized callers still get a reply (empty list) so the client's request wait
  resolves.
- **`vMenu:ClearArea`** now requires `MSClearArea`. Upstream had no check, letting any client
  broadcast an area wipe of other players' nearby entities. Unauthorized ⇒ BanCheater.
- **`vMenu:UpdateServerTime`** clamps the client-supplied `hour`/`minute` to `0-23`/`0-59`
  integers before the smooth-transition loop. Out-of-range or non-integer values would otherwise
  never match the clamped current hour and spin the loop forever, hanging the thread (DoS).
