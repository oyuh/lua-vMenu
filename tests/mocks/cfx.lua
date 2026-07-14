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
        players = {}, -- [handle] = { aces = { [ace] = true } }
        event_handlers = {},
        triggered = {}, -- log of every TriggerEvent/Server/Client call, for assertions
        _find_handles = {},
        _next_handle = 1,
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

function Cfx:add_player(handle)
    self.players[tostring(handle)] = { aces = {} }
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

    _G.IsDuplicityVersion = function()
        return mock.is_server
    end

    _G.DoesPlayerExist = function(handle)
        return mock.players[tostring(handle)] ~= nil
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
        mock:_dispatch(name, ...)
    end

    _G.TriggerServerEvent = function(name, ...)
        mock:_record('to_server', name, ...)
        mock:_dispatch(name, ...)
    end

    _G.TriggerClientEvent = function(name, _target, ...)
        mock:_record('to_client', name, ...)
        mock:_dispatch(name, ...)
    end

    return self
end

function Cfx:uninstall()
    for _, name in ipairs(INSTALLED_GLOBALS) do
        _G[name] = self._saved_globals[name]
    end
end

-- Internals -------------------------------------------------------------------

function Cfx:_add_handler(name, handler)
    self.event_handlers[name] = self.event_handlers[name] or {}
    table.insert(self.event_handlers[name], handler)
end

function Cfx:_dispatch(name, ...)
    for _, handler in ipairs(self.event_handlers[name] or {}) do
        handler(...)
    end
end

function Cfx:_record(direction, name, ...)
    table.insert(self.triggered, { direction = direction, name = name, args = table.pack(...) })
end

return Cfx
