-- Specs for server/plugins.lua, the server half of upstream's plugin
-- protocol. Plugins are separate resources built on upstream's plugin API,
-- so the event names, payload fields and answers are the contract.

local CfxMock = require('tests.mocks.cfx')
local dkjson = require('dkjson')

local function reset_modules()
    for name in pairs(package.loaded) do
        if name:match('^shared%.') or name:match('^server%.') then
            package.loaded[name] = nil
        end
    end
end

describe('server plugin registry', function()
    local cfx, Registry, Permissions

    before_each(function()
        cfx = CfxMock.new({ resource_name = 'vMenu.Enhanced', is_server = true }):install()
        reset_modules()
        Permissions = require('server.permissions')
        Permissions.init()
        local Plugins = require('server.plugins')
        Plugins.register_events()
        Registry = require('server.permission_registry')
    end)

    after_each(function()
        cfx:uninstall()
    end)

    -- Sends a registration as plugin resource and returns vMenu's decoded answer.
    local function register(resource, request)
        cfx.invoking_resource = resource
        TriggerEvent('vMenu.Enhanced:Plugins:Server:Register', dkjson.encode(request))
        cfx.invoking_resource = nil
        local answer = cfx.triggered[#cfx.triggered]
        assert.are.equal(('vMenu.Enhanced:Plugins:%s:Server:RegisterResult'):format(resource), answer.name)
        return dkjson.decode(answer.args[1])
    end

    local REQUEST = {
        protocolVersion = 1,
        displayName = 'Routing Buckets',
        permissions = { { name = 'Manage', staffOnly = true }, { name = 'View' }, { name = 'bad name' } },
        settings = { { name = 'MaxWorlds', type = 'int', default = '8', description = 'How many worlds.' } },
        loggedItems = { { itemId = 'create', description = 'a new world' } },
    }

    it('accepts a registration and adds its permissions under Plugins.All', function()
        local answer = register('vMenu.RoutingBuckets', REQUEST)
        assert.is_true(answer.accepted)
        assert.are.equal(1, answer.protocolVersion)
        assert.same({}, answer.errors)
        assert.are.equal(1, #answer.warnings) -- 'bad name'

        assert.is_not_nil(Registry.get('vMenu.Enhanced.Plugins.vMenu_RoutingBuckets.Manage'))
        cfx:add_player(1)
        cfx:grant_ace(1, 'vMenu.Enhanced.Plugins.All')
        assert.is_true(Permissions.is_allowed(1, 'vMenu.Enhanced.Plugins.vMenu_RoutingBuckets.View'))
    end)

    it('writes the plugin its own templates', function()
        register('vMenu.RoutingBuckets', REQUEST)
        local permissions = cfx.resource_files['config/plugins/vMenu.RoutingBuckets.permissions.cfg.example']
        local settings = cfx.resource_files['config/plugins/vMenu.RoutingBuckets.configuration.cfg.example']
        assert.matches(
            'add_ace group.admin "vMenu.Enhanced.Plugins.vMenu_RoutingBuckets.Manage" allow',
            permissions,
            1,
            true
        )
        assert.matches('setr vMenu.Enhanced.Plugins.vMenu_RoutingBuckets.MaxWorlds 8', settings, 1, true)
    end)

    it('drops permissions a re-registration no longer declares, and all of them on stop', function()
        register('vMenu.RoutingBuckets', REQUEST)
        register('vMenu.RoutingBuckets', { protocolVersion = 1, permissions = { { name = 'View' } } })
        assert.is_nil(Registry.get('vMenu.Enhanced.Plugins.vMenu_RoutingBuckets.Manage'))
        assert.is_not_nil(Registry.get('vMenu.Enhanced.Plugins.vMenu_RoutingBuckets.View'))

        TriggerEvent('onResourceStop', 'vMenu.RoutingBuckets')
        assert.is_nil(Registry.get('vMenu.Enhanced.Plugins.vMenu_RoutingBuckets.View'))
    end)

    it('refuses a second resource claiming the same identity, and a newer protocol', function()
        register('my.plugin', REQUEST)
        local clash = register('my_plugin', REQUEST)
        assert.is_false(clash.accepted)
        assert.matches("already taken by resource 'my.plugin'", clash.errors[1], 1, true)

        local newer = register('other', { protocolVersion = 2 })
        assert.is_false(newer.accepted)
    end)

    it('ignores registrations that do not come from another resource', function()
        local before = #cfx.triggered
        TriggerEvent('vMenu.Enhanced:Plugins:Server:Register', dkjson.encode(REQUEST))
        assert.are.equal(before + 1, #cfx.triggered) -- only the trigger itself, no answer
    end)
end)
