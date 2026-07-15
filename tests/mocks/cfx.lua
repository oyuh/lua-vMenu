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
}

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

    _G.GlobalState = {
        set = function(_, key, value, _replicated)
            mock.global_state[key] = value
        end,
    }

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
    end

    _G.StartFindKvp = function(prefix)
        local keys = {}
        for key in pairs(mock.kvp) do
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

    return self
end

function Cfx:uninstall()
    for _, name in ipairs(INSTALLED_GLOBALS) do
        _G[name] = self._saved_globals[name]
    end
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
