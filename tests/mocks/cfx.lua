-- In-process fake of the CitizenFX runtime for busted tests.
-- Install one instance per test (before requiring modules under test),
-- uninstall in teardown. Grows alongside the modules being ported;
-- semantics deliberately mimic the real runtime, quirks included.

local Cfx = {}
Cfx.__index = Cfx

local INSTALLED_GLOBALS = {
    'GetConvar',
    'GetConvarInt',
    'GetResourceMetadata',
    'GetCurrentResourceName',
    'LoadResourceFile',
    'SaveResourceFile',
    'IsDuplicityVersion',
    'IsPlayerAceAllowed',
    'DoesPlayerExist',
    'SetResourceKvp',
    'GetResourceKvpString',
    'DeleteResourceKvp',
    'StartFindKvp',
    'FindKvp',
    'EndFindKvp',
    'RegisterNetEvent',
    'AddEventHandler',
    'TriggerEvent',
    'TriggerServerEvent',
    'TriggerClientEvent',
    -- server runtime
    'SetConvarReplicated',
    'GetPlayers',
    'GetPlayerName',
    'GetNumPlayerIdentifiers',
    'GetPlayerIdentifier',
    'DropPlayer',
    'CancelEvent',
    'Player',
    'GetGameTimer',
    'CreateThread',
    'Wait',
    'RegisterCommand',
    'GlobalState',
    'GetPlayerPed',
    'GetEntityCoords',
    'DoesEntityExist',
    'vector3',
    -- typed kvp + keymapping + misc client runtime
    'SetResourceKvpInt',
    'GetResourceKvpInt',
    'SetResourceKvpFloat',
    'GetResourceKvpFloat',
    'RegisterKeyMapping',
    'GetHashKey',
    'LocalPlayer',
}

-- Client-side game natives faked as recording no-ops. Each entry is
-- { name, default } where default may be a plain value or a function of the
-- call args. Calls are recorded in mock.native_calls for assertions.
local NATIVE_DEFAULTS = {
    -- notifications / text
    { 'SetNotificationTextEntry' },
    { 'AddTextComponentSubstringPlayerName' },
    { 'DrawNotification' },
    { 'SetNotificationMessage' },
    { 'BeginTextCommandPrint' },
    { 'EndTextCommandPrint' },
    { 'BeginTextCommandDisplayHelp' },
    { 'EndTextCommandDisplayHelp' },
    { 'IsHelpMessageBeingDisplayed', false },
    { 'ClearAllHelpMessages' },
    { 'AddTextEntry' },
    -- identity instead of 'NULL' so label-keyed dicts (VehicleClasses) keep
    -- distinct keys in specs
    {
        'GetLabelText',
        function(label)
            return label
        end,
    },
    { 'DisplayHelpTextThisFrame' },
    { 'ClearBrief' },
    { 'SetRichPresence' },
    -- stats / pvp
    { 'StatSetInt' },
    { 'StatSetFloat' },
    { 'NetworkSetFriendlyFireOption' },
    { 'SetCanAttackFriendly' },
    -- local player / players
    { 'PlayerId', 0 },
    { 'PlayerPedId', 900 },
    { 'IsPedInAnyVehicle', false },
    { 'GetVehiclePedIsIn', 0 },
    { 'GetPedInVehicleSeat', 0 },
    { 'NetworkIsPlayerActive', true },
    {
        'GetActivePlayers',
        function()
            return {}
        end,
    },
    { 'GetPlayerFromServerId', -1 },
    { 'GetPlayerServerId', 0 },
    -- world / entities
    { 'SetEntityHealth' },
    { 'ClearAreaOfEverything' },
    { 'ForceSocialClubUpdate' },
    -- clouds / snow / lights
    { 'ClearCloudHat' },
    { 'SetCloudHatOpacity' },
    { 'SetCloudHatTransition' },
    { 'ForceSnowPass' },
    { 'SetForceVehicleTrails' },
    { 'SetForcePedFootstepsTracks' },
    { 'HasNamedPtfxAssetLoaded', true },
    { 'RequestNamedPtfxAsset' },
    { 'UseParticleFxAssetNextCall' },
    { 'RemoveNamedPtfxAsset' },
    { 'SetArtificialLightsState' },
    { 'SetArtificialLightsStateAffectsVehicles' },
    -- weather / time sync
    { 'GetNextWeatherType', 0 },
    { 'SetWeatherTypeOvertimePersist' },
    { 'NetworkOverrideClockTime' },
    -- spawn / screen state
    { 'IsScreenFadedIn', true },
    { 'IsPlayerSwitchInProgress', false },
    { 'IsPauseMenuActive', false },
    { 'GetIsLoadingScreenActive', false },
    -- ped headshots (private messages)
    { 'RegisterPedheadshot', 1 },
    { 'IsPedheadshotReady', true },
    { 'IsPedheadshotValid', true },
    { 'GetPedheadshotTxdString', 'headshot_txd' },
    { 'UnregisterPedheadshot' },
    -- drawing / alignment
    { 'GetAspectRatio', 1.7777778 },
    -- weapons / models (data layer)
    { 'DoesWeaponTakeWeaponComponent', false },
    {
        'GetMaxAmmo',
        function()
            return true, 250
        end,
    },
    { 'GetEntityModel', 0 },
    { 'IsThisModelABike', false },
    { 'IsThisModelABoat', false },
    { 'IsThisModelAHeli', false },
    { 'IsThisModelAPlane', false },
    -- onscreen keyboard (default: "cancelled" so get_user_input returns nil
    -- instead of spinning forever in specs)
    { 'DisplayOnscreenKeyboard' },
    { 'UpdateOnscreenKeyboard', 2 },
    { 'GetOnscreenKeyboardResult', '' },
    -- recording / editor
    { 'IsRecording', false },
    { 'StartRecording' },
    { 'StopRecordingAndSaveClip' },
    { 'ActivateFrontendMenu' },
    { 'BeginTakeHighQualityPhoto' },
    { 'SaveHighQualityPhoto' },
    { 'FreeMemoryForHighQualityPhoto' },
    { 'ActivateRockstarEditor' },
    { 'AddTextEntryByHash' },
    { 'DoScreenFadeIn' },
    { 'DoScreenFadeOut' },
    { 'IsScreenFadedOut', true },
    -- session / connection
    { 'NetworkSessionEnd' },
    { 'NetworkSessionHost' },
    { 'NetworkIsSessionActive', false },
    { 'NetworkIsHost', false },
    { 'ExecuteCommand' },
    -- hud / vision / timecycle
    { 'DisplayHud' },
    { 'DisplayRadar' },
    { 'SetNightvision' },
    { 'SetSeethrough' },
    { 'SetTimecycleModifier' },
    { 'SetTimecycleModifierStrength' },
    { 'ClearTimecycleModifier' },
    -- blips
    { 'AddBlipForCoord', 1 },
    { 'SetBlipSprite' },
    { 'BeginTextCommandSetBlipName' },
    { 'EndTextCommandSetBlipName' },
    { 'SetBlipColour' },
    { 'SetBlipAsShortRange' },
    { 'DoesBlipExist', false },
    { 'RemoveBlip' },
    { 'IsWaypointActive', false },
    { 'GetFirstBlipInfoId', 0 },
    {
        'GetBlipInfoIdCoord',
        function()
            return { x = 0.0, y = 0.0, z = 0.0 }
        end,
    },
    -- player state / stats (player options)
    { 'GetPlayerWantedLevel', 0 },
    { 'SetPlayerWantedLevel' },
    { 'SetPlayerWantedLevelNow' },
    { 'SetMaxWantedLevel' },
    { 'SetRunSprintMultiplierForPlayer' },
    { 'SetSwimMultiplierForPlayer' },
    { 'SetEveryoneIgnorePlayer' },
    { 'SetPoliceIgnorePlayer' },
    { 'SetPlayerCanBeHassledByGangs' },
    { 'SetEntityVisible' },
    { 'IsEntityVisible', true },
    { 'FreezeEntityPosition' },
    { 'ApplyPedDamagePack' },
    { 'SetPedArmour' },
    { 'ClearPedBloodDamage' },
    { 'ResetPedVisibleDamage' },
    { 'ClearPedDamageDecalByZone' },
    { 'GetEntityMaxHealth', 200 },
    { 'SetPedWetnessHeight' },
    -- scenarios / tasks
    { 'IsPedRunning', false },
    { 'IsEntityDead', false },
    { 'IsPlayerInCutscene', false },
    { 'IsPedFalling', false },
    { 'IsPedRagdoll', false },
    { 'IsPedOnFoot', true },
    { 'NetworkIsInSpectatorMode', false },
    { 'GetEntitySpeed', 0.0 },
    {
        'GetOffsetFromEntityInWorldCoords',
        function()
            return { x = 0.0, y = 0.0, z = 0.0 }
        end,
    },
    { 'GetEntityHeading', 0.0 },
    { 'TaskStartScenarioAtPosition' },
    { 'TaskStartScenarioInPlace' },
    { 'ClearPedTasks' },
    { 'ClearPedSecondaryTask' },
    { 'ClearPedTasksImmediately' },
    { 'SetDriveTaskDrivingStyle' },
    { 'SetDriverAbility' },
    { 'SetDriverAggressiveness' },
    { 'TaskVehicleDriveToCoordLongrange' },
    { 'TaskVehicleDriveWander' },
    { 'TaskVehiclePark' },
    { 'SetVehicleHalt' },
    {
        'GetNthClosestVehicleNode',
        function()
            return false, { x = 0.0, y = 0.0, z = 0.0 }
        end,
    },
    -- suicide anims
    { 'RequestAnimDict' },
    { 'HasAnimDictLoaded', true },
    { 'RemoveAnimDict' },
    { 'HasPedGotWeapon', false },
    { 'SetCurrentPedWeapon' },
    { 'SetPedDropsWeaponsWhenDead' },
    { 'GiveWeaponToPed' },
    { 'TaskPlayAnim' },
    { 'GetEntityAnimCurrentTime', 1.0 },
    { 'HasAnimEventFired', false },
    { 'ClearEntityLastDamageEntity' },
    { 'SetPedShootsAtCoord' },
    -- vehicle spawning
    { 'GetVehicleClassFromName', 0 },
    { 'IsModelInCdimage', true },
    { 'DoesModelExist', true },
    { 'IsModelAVehicle', true },
    { 'RequestModel' },
    { 'HasModelLoaded', true },
    { 'SetModelAsNoLongerNeeded' },
    { 'GetDisplayNameFromVehicleModel', 'NULL' },
    { 'GetVehicleModelEstimatedMaxSpeed', 0.0 },
    { 'GetVehicleModelAcceleration', 0.0 },
    { 'GetVehicleModelMaxBraking', 0.0 },
    { 'GetVehicleModelMaxTraction', 0.0 },
    { 'GetVehicleModelMaxSpeed', 0.0 },
    { 'CreateVehicle', 2000 },
    { 'DeleteVehicle' },
    { 'SetEntityAsMissionEntity' },
    { 'SetVehicleNeedsToBeHotwired' },
    { 'SetVehicleHasBeenOwnedByPlayer' },
    { 'SetVehicleIsStolen' },
    { 'SetVehicleIsWanted' },
    { 'SetVehicleEngineOn' },
    { 'SetPedIntoVehicle' },
    { 'GetVehicleClass', 0 },
    { 'GetEntityHeightAboveGround', 0.0 },
    { 'SetVehicleOnGroundProperly' },
    { 'IsThisModelATrain', false },
    { 'SetVehicleForwardSpeed' },
    { 'GetVehicleCurrentRpm', 0.0 },
    { 'SetVehicleCurrentRpm' },
    {
        'GetEntitySpeedVector',
        function()
            return { x = 0.0, y = 0.0, z = 0.0 }
        end,
    },
    { 'GetVehicleNumberOfPassengers', 0 },
    { 'IsVehicleSeatFree', true },
    { 'IsVehicleDriveable', true },
    { 'DoesPlayerVehHaveRadio', false },
    { 'IsRadioRetuning', false },
    { 'SetVehRadioStation' },
    { 'GetRadioStationName', '' },
    { 'SetHeliBladesFullSpeed' },
    { 'GetPlayersLastVehicle', 0 },
    -- safe teleport
    { 'RequestCollisionAtCoord' },
    { 'SetFocusPosAndVel' },
    { 'NewLoadSceneStart' },
    { 'IsNewLoadSceneLoaded', true },
    { 'ClearFocus' },
    { 'NewLoadSceneStop' },
    { 'HasCollisionLoadedAroundEntity', true },
    {
        'GetGroundZFor_3dCoord',
        function()
            return true, 30.0
        end,
    },
    { 'NetworkFadeOutEntity' },
    { 'NetworkFadeInEntity' },
    { 'SetGameplayCamRelativePitch' },
    { 'SetGameplayCamRelativeHeading' },
    { 'SetEntityHeading' },
}

-- Exported so .luacheckrc can declare every faked native as a known global
-- (one source of truth for the native surface used by the ported code).
Cfx.NATIVE_NAMES = {}
for _, spec in ipairs(NATIVE_DEFAULTS) do
    Cfx.NATIVE_NAMES[#Cfx.NATIVE_NAMES + 1] = spec[1]
end
for _, name in ipairs(INSTALLED_GLOBALS) do
    Cfx.NATIVE_NAMES[#Cfx.NATIVE_NAMES + 1] = name
end

function Cfx.new(opts)
    opts = opts or {}
    return setmetatable({
        resource_name = opts.resource_name or 'vMenu',
        is_server = opts.is_server or false,
        convars = {},
        metadata = {},
        resource_files = {},
        kvp = {},
        players = {}, -- [handle] = { aces = {}, name = ..., identifiers = {}, state = {}, ped = int }
        event_handlers = {},
        triggered = {}, -- log of every TriggerEvent/Server/Client call, for assertions
        commands = {}, -- [name] = { handler = fn, restricted = bool }
        threads = {}, -- functions passed to CreateThread (recorded, not run)
        dropped = {}, -- { handle = ..., reason = ... } per DropPlayer call
        global_state = {},
        entity_coords = {}, -- [entity handle] = vector3-like table
        game_timer = 0,
        event_cancelled = false,
        kvp_typed = {}, -- [key] = { kind = 'int'|'float', value = ... }
        key_mappings = {}, -- { command, description, mapper, key } per RegisterKeyMapping
        native_calls = {}, -- [native name] = list of arg packs
        local_player_state = {}, -- LocalPlayer.state statebag
        _find_handles = {},
        _next_handle = 1,
        _next_ped = 100,
        _saved_globals = {},
    }, Cfx)
end

-- Test setup helpers ---------------------------------------------------------

function Cfx:set_convar(name, value)
    self.convars[name] = tostring(value)
end

function Cfx:set_metadata(key, value)
    self.metadata[key] = tostring(value)
end

function Cfx:set_resource_file(path, contents)
    self.resource_files[path] = contents
end

function Cfx:add_player(handle, opts)
    opts = opts or {}
    local ped = self._next_ped
    self._next_ped = self._next_ped + 1
    self.players[tostring(handle)] = {
        aces = {},
        name = opts.name or ('Player' .. tostring(handle)),
        identifiers = opts.identifiers or {},
        state = opts.state or {},
        ped = ped,
    }
    self.entity_coords[ped] = opts.coords or { x = 0.0, y = 0.0, z = 0.0 }
end

function Cfx:grant_ace(handle, ace)
    local player = self.players[tostring(handle)]
    assert(player, 'add_player first')
    player.aces[ace] = true
end

-- Global installation --------------------------------------------------------

function Cfx:install()
    local mock = self
    for _, name in ipairs(INSTALLED_GLOBALS) do
        mock._saved_globals[name] = _G[name]
    end

    -- convars / metadata / files

    _G.GetConvar = function(name, default)
        local value = mock.convars[name]
        if value == nil then
            return default
        end
        return value
    end

    -- Real runtime behaves atoi-like on non-numeric values (yields 0),
    -- and returns the default only when the convar is unset.
    _G.GetConvarInt = function(name, default)
        local value = mock.convars[name]
        if value == nil then
            return default
        end
        local leading_int = value:match('^%s*(%-?%d+)')
        return leading_int and math.tointeger(tonumber(leading_int)) or 0
    end

    _G.SetConvarReplicated = function(name, value)
        mock.convars[name] = tostring(value)
    end

    _G.GetResourceMetadata = function(resource, key, _index)
        if resource ~= mock.resource_name then
            return nil
        end
        return mock.metadata[key]
    end

    _G.GetCurrentResourceName = function()
        return mock.resource_name
    end

    _G.LoadResourceFile = function(resource, path)
        if resource ~= mock.resource_name then
            return nil
        end
        return mock.resource_files[path]
    end

    _G.SaveResourceFile = function(resource, path, contents, _length)
        if resource ~= mock.resource_name then
            return false
        end
        mock.resource_files[path] = contents
        return true
    end

    _G.IsDuplicityVersion = function()
        return mock.is_server
    end

    _G.DoesPlayerExist = function(handle)
        return mock.players[tostring(handle)] ~= nil
    end

    _G.GetPlayers = function()
        local handles = {}
        for handle in pairs(mock.players) do
            handles[#handles + 1] = handle
        end
        table.sort(handles)
        return handles
    end

    _G.GetPlayerName = function(handle)
        local player = mock.players[tostring(handle)]
        return player and player.name or nil
    end

    _G.GetNumPlayerIdentifiers = function(handle)
        local player = mock.players[tostring(handle)]
        return player and #player.identifiers or 0
    end

    _G.GetPlayerIdentifier = function(handle, index)
        local player = mock.players[tostring(handle)]
        return player and player.identifiers[index + 1] or nil
    end

    _G.DropPlayer = function(handle, reason)
        table.insert(mock.dropped, { handle = tostring(handle), reason = reason })
        mock.players[tostring(handle)] = nil
    end

    _G.CancelEvent = function()
        mock.event_cancelled = true
    end

    -- Statebag access: Player(id).state.key
    _G.Player = function(handle)
        local player = mock.players[tostring(handle)]
        return { state = player and player.state or {} }
    end

    _G.GetGameTimer = function()
        return mock.game_timer
    end

    -- Threads are recorded, never run: loops with Wait would hang the specs.
    _G.CreateThread = function(fn)
        table.insert(mock.threads, fn)
    end

    _G.Wait = function() end

    _G.RegisterCommand = function(name, handler, restricted)
        mock.commands[name] = { handler = handler, restricted = restricted }
    end

    _G.GlobalState = setmetatable({
        set = function(_, key, value, _replicated)
            mock.global_state[key] = value
        end,
    }, {
        __index = function(_, key)
            return mock.global_state[key]
        end,
    })

    _G.RegisterKeyMapping = function(command, description, mapper, key)
        table.insert(mock.key_mappings, { command = command, description = description, mapper = mapper, key = key })
    end

    -- Local player statebag: LocalPlayer.state.key / LocalPlayer.state:set().
    _G.LocalPlayer = {
        state = setmetatable({
            set = function(_, key, value, _replicated)
                mock.local_player_state[key] = value
            end,
        }, {
            __index = function(_, key)
                return mock.local_player_state[key]
            end,
        }),
    }

    -- Deterministic stand-in for joaat; stable across runs, distinct enough
    -- for table keys in specs.
    _G.GetHashKey = function(input)
        local text = tostring(input)
        local hash = 0
        for i = 1, #text do
            hash = (hash * 31 + text:byte(i)) % 4294967296
        end
        return hash
    end

    _G.GetPlayerPed = function(handle)
        local player = mock.players[tostring(handle)]
        return player and player.ped or 0
    end

    _G.GetEntityCoords = function(entity)
        return mock.entity_coords[entity] or { x = 0.0, y = 0.0, z = 0.0 }
    end

    _G.DoesEntityExist = function(entity)
        return mock.entity_coords[entity] ~= nil
    end

    _G.vector3 = function(x, y, z)
        return { x = x, y = y, z = z }
    end

    _G.IsPlayerAceAllowed = function(handle, ace)
        local player = mock.players[tostring(handle)]
        return player ~= nil and player.aces[ace] == true
    end

    -- KVP (with StartFindKvp/FindKvp/EndFindKvp iteration semantics)

    _G.SetResourceKvp = function(key, value)
        mock.kvp[key] = tostring(value)
    end

    _G.GetResourceKvpString = function(key)
        return mock.kvp[key]
    end

    _G.DeleteResourceKvp = function(key)
        mock.kvp[key] = nil
        mock.kvp_typed[key] = nil
    end

    -- Typed KVPs share the key namespace with string KVPs (find iterates all).
    _G.SetResourceKvpInt = function(key, value)
        mock.kvp_typed[key] = { kind = 'int', value = math.tointeger(value) or 0 }
    end

    _G.GetResourceKvpInt = function(key)
        local entry = mock.kvp_typed[key]
        return (entry and entry.kind == 'int') and entry.value or 0
    end

    _G.SetResourceKvpFloat = function(key, value)
        mock.kvp_typed[key] = { kind = 'float', value = value + 0.0 }
    end

    _G.GetResourceKvpFloat = function(key)
        local entry = mock.kvp_typed[key]
        return (entry and entry.kind == 'float') and entry.value or 0.0
    end

    _G.StartFindKvp = function(prefix)
        local keys = {}
        for key in pairs(mock.kvp) do
            if key:sub(1, #prefix) == prefix then
                keys[#keys + 1] = key
            end
        end
        for key in pairs(mock.kvp_typed) do
            if key:sub(1, #prefix) == prefix then
                keys[#keys + 1] = key
            end
        end
        table.sort(keys)
        local handle = mock._next_handle
        mock._next_handle = mock._next_handle + 1
        mock._find_handles[handle] = { keys = keys, index = 0 }
        return handle
    end

    _G.FindKvp = function(handle)
        local it = mock._find_handles[handle]
        if not it then
            return nil
        end
        it.index = it.index + 1
        return it.keys[it.index]
    end

    _G.EndFindKvp = function(handle)
        mock._find_handles[handle] = nil
    end

    -- Events: one in-process bus. Client/server distinction is recorded in the
    -- trigger log so specs can assert on direction and payloads.

    _G.RegisterNetEvent = function(name, handler)
        if handler then
            mock:_add_handler(name, handler)
        end
        return name
    end

    _G.AddEventHandler = function(name, handler)
        mock:_add_handler(name, handler)
    end

    _G.TriggerEvent = function(name, ...)
        mock:_record('local', name, ...)
        mock:_dispatch(mock.is_server and 'server' or 'client', name, ...)
    end

    _G.TriggerServerEvent = function(name, ...)
        mock:_record('to_server', name, ...)
        mock:_dispatch('server', name, ...)
    end

    _G.TriggerClientEvent = function(name, _target, ...)
        mock:_record('to_client', name, ...)
        mock:_dispatch('client', name, ...)
    end

    -- Recording no-op natives with canned defaults.
    for _, spec in ipairs(NATIVE_DEFAULTS) do
        local name, default = spec[1], spec[2]
        if mock._saved_globals[name] == nil then
            mock._saved_globals[name] = _G[name]
        end
        _G[name] = function(...)
            mock.native_calls[name] = mock.native_calls[name] or {}
            table.insert(mock.native_calls[name], table.pack(...))
            if type(default) == 'function' then
                return default(...)
            end
            return default
        end
    end

    return self
end

function Cfx:uninstall()
    for _, name in ipairs(INSTALLED_GLOBALS) do
        _G[name] = self._saved_globals[name]
    end
    for _, spec in ipairs(NATIVE_DEFAULTS) do
        _G[spec[1]] = self._saved_globals[spec[1]]
    end
    for _, name in ipairs(self._extra_stubs or {}) do
        _G[name] = self._saved_globals[name]
    end
end

-- All recorded calls to a faked native (empty list when never called).
function Cfx:calls(native_name)
    return self.native_calls[native_name] or {}
end

-- Replaces one native with a custom function for this test (restored on
-- uninstall like everything else).
function Cfx:stub_native(name, fn)
    if self._saved_globals[name] == nil then
        self._saved_globals[name] = _G[name]
    end
    self._extra_stubs = self._extra_stubs or {}
    table.insert(self._extra_stubs, name)
    _G[name] = fn
end

-- Triggers a server event as if a client sent it: the `source` global is set
-- to the given handle for the duration of the dispatch, like the real runtime.
function Cfx:trigger_from(source_handle, name, ...)
    self:_record('to_server', name, ...)
    local previous = rawget(_G, 'source')
    _G.source = source_handle
    self:_dispatch('server', name, ...)
    _G.source = previous
end

-- Internals -------------------------------------------------------------------

-- Handlers register on the side the mock is running as, so a server-side
-- handler never catches its own TriggerClientEvent broadcast (e.g. the
-- vMenu:ClearArea request/broadcast pair sharing one event name).
function Cfx:_add_handler(name, handler)
    local side = self.is_server and 'server' or 'client'
    self.event_handlers[side] = self.event_handlers[side] or {}
    self.event_handlers[side][name] = self.event_handlers[side][name] or {}
    table.insert(self.event_handlers[side][name], handler)
end

function Cfx:_dispatch(side, name, ...)
    local handlers = self.event_handlers[side] and self.event_handlers[side][name] or nil
    for _, handler in ipairs(handlers or {}) do
        handler(...)
    end
end

function Cfx:_record(direction, name, ...)
    table.insert(self.triggered, { direction = direction, name = name, args = table.pack(...) })
end

return Cfx
