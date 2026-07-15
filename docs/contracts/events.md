# Contract: event protocol

Source: `vMenuServer/MainServer.cs`, `vMenuServer/BanManager.cs`, `vMenu/EventManager.cs`,
`vMenu/MainMenu.cs`, `vMenu/FunctionsController.cs` (upstream @ `49e53065`).

Third-party resources integrate with vMenu through these events. Every name, argument order,
and argument type must match. JSON-string payloads (not tables!) stay JSON strings — upstream
serializes with Newtonsoft and the shapes are part of the contract (see
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
| `vMenu:RequestBanList` | *(none)* | replies to source with `vMenu:SetBanList` |
| `vMenu:SendMessageToPlayer` | `int target, string message` | PM system; staff with `OPSeePrivateMessages` get a copy |
| `vMenu:UpdateServerWeather` | `string weather, bool dynamicEnabled, bool snowEnabled` | perm `WOSetWeather`-family |
| `vMenu:UpdateServerBlackout` | `bool enabled` | |
| `vMenu:UpdateServerVehicleBlackout` | `bool enabled` | |
| `vMenu:UpdateServerWeatherCloudsType` | `bool removeClouds` | server picks random cloud type unless removing |
| `vMenu:UpdateServerTime` | `int hour, int minute, bool freezeTime` | |
| `vMenu:FreezeServerTime` | `bool freezeTime` | |
| `vMenu:SaveTeleportLocation` | `string locationJson` | appends TeleportLocation to locations.json + broadcasts `vMenu:UpdateTeleportLocations` |
| `vMenu:RequestPlayerList` | *(none)* | replies with `vMenu:ReceivePlayerList` |
| `vMenu:GetPlayerCoords` | `long rpcId, int playerId, funcref callback` | calls back with coords; falls back to `vMenu:GetPlayerCoords:reply` event |
| `vMenu:GetPlayerIdentifiers` | `int target, funcref callback` | callback receives identifier list |
| `vMenu:GetOutOfCar` | `int vehicleNetId` | personal-vehicle passenger kick; targets get `vMenu:Notify` |
| `vMenu:ClearArea` | *(none — uses source position)* | **no server-side perm check upstream** (quirk preserved); broadcasts `vMenu:ClearArea` with source `vector3` to all clients |

## Server → Client

| Event | Arguments | Notes |
|---|---|---|
| `vMenu:SetPermissions` | `string json` — `{ "<PermissionName>": bool, … }` | pushed on `playerJoining` + first-tick sweep (3s after resource start); **no client request event exists** |
| `vMenu:SetSupplementaryPermissions` | `string json` — same shape | follows SetPermissions |
| `vMenu:SetConfigOptions` | *(none)* | tells client to (re)load addons/config |
| `vMenu:SetAddons` | *(none)* | **deprecated alias** of SetConfigOptions; keep handling it |
| `vMenu:UpdateTeleportLocations` | `string json` — `TeleportLocation[]` | sent after perms + whenever a location is saved |
| `vMenu:Notify` | `string message` | GTA notification (supports `~r~` etc. + `<C>` tags) |
| `vMenu:KillMe` | `string killerName` | kills own ped |
| `vMenu:GoodBye` | *(none)* | the "fun" cheater drop |
| `vMenu:SetBanList` | `string json` — `BanRecord[]` | |
| `vMenu:BanSuccessful` | `string json` — `BanRecord` | fired to source after a ban |
| `vMenu:UnbanSuccessful` | `string json` — `BanRecord` | |
| `vMenu:BanCheaterSuccessful` | `string json` — `BanRecord` | |
| `vMenu:SetClouds` | `float opacity, string cloudsType` | |
| `vMenu:ClearArea` | `vector3 position` | broadcast to **all** clients |
| `vMenu:updatePedDecors` | *(none)* | note lowercase `u` — keep exact casing |
| `vMenu:PrivateMessage` | `string sourceServerId, string message` | source id as string (Handle) |
| `vMenu:PlayerJoinQuit` | `string playerName, string dropReason` | reason is `null` for joins |
| `vMenu:ReceivePlayerList` | `object[]` — `[{ n = string name, s = int serverId }, …]` | anonymous objects, field names `n`/`s` |
| `vMenu:GetPlayerCoords:reply` | `long rpcId, vector3 coords` | fallback RPC reply |
| `vMenu:UpdateServerWeather` | `string weather, bool dynamicEnabled, bool snowEnabled` | also reused as broadcast |
| `vMenu:UpdateServerTime` | `int hour, int minute, bool freezeTime` | third arg is `!FreezeTime` in the sync loop and `FreezeTime` in the setter path — port faithfully per call site |

## Client-local events (same-client TriggerEvent)

| Event | Arguments | Purpose |
|---|---|---|
| `vMenu:SetupTickFunctions` | *(none)* | (re)registers feature tick handlers |
| `vMenu:WeatherChangeComplete` | *(varies — port from EventManager)* | fired after weather transition |
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
