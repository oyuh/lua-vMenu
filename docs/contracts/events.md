# Contract: event protocol

Source: `vMenuServer/MainServer.cs`, `vMenuServer/BanManager.cs`, `vMenu/EventManager.cs`,
`vMenu/MainMenu.cs`, `vMenu/FunctionsController.cs` (upstream @ `e0f3b92a`).

Third-party resources hook into vMenu through these events, so every name, argument order, and
argument type has to match. JSON-string payloads stay JSON strings, not tables: upstream
serializes with Newtonsoft and the shapes are part of the contract. Record schemas live in
[kvp-saves.md](kvp-saves.md).

Types below are the msgpack types on the wire: `int`, `float`, `bool`, `string`, `vector3`
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

## Security model (keep it)

Server handlers re-check ACE permissions on every call and treat an unauthorized trigger as a
cheating attempt. `BanCheater(source)` auto-bans when `vmenu_auto_ban_cheaters` is on. The Lua
server never trusts a client-supplied permission claim.

### Hardening deviations from upstream, on purpose

Upstream leaves a few server handlers ungated and trusts the stock client to only send them
when the player is authorized. A modded client walks straight through that, so the Lua rewrite
checks server side. These are deliberate behavior differences, same category as the removed dev
backdoor in [permissions.md](permissions.md). Stock clients notice nothing, since they already
only send these when the player holds the permission.

- **`vMenu:RequestBanList`** now wants `OPViewBannedPlayers`/`OPUnban`/`OPAll`/`Everything`.
  Upstream replied to anyone who asked, handing over every banned player's full identifier set
  (`ip:` included), ban reasons, and staff names. Unauthorized callers get BanCheater.
- **`vMenu:GetPlayerIdentifiers`** now wants `OPIdentifiers`. It's read-only, so unauthorized
  callers get `[]` and no auto-ban, matching the `GetPlayerCoords` pattern. `ip:` stays
  stripped.
- **`vMenu:RequestPlayerList`** now wants `OPMenu`, the only permission the client sends it
  under. Read-only again: unauthorized callers still get a reply, an empty list, so the
  client's request wait resolves instead of hanging.
- **`vMenu:ClearArea`** now wants `MSClearArea`. Upstream had no check at all, so any client
  could broadcast an area wipe of other players' nearby entities. Unauthorized callers get
  BanCheater.
- **`vMenu:UpdateServerTime`** clamps the client-supplied `hour` and `minute` to `0-23` and
  `0-59` integers before the smooth-transition loop. Out-of-range or non-integer values never
  match the clamped current hour, so the loop spins forever and hangs the thread. That's a DoS.
