-- Loads both entrypoints under the native mock. Every module is reached
-- through require at load time, so a misspelled module path, a module that
-- errors while loading, or a startup step that throws fails here instead of
-- on a live server.

local CfxMock = require('tests.mocks.cfx')

local function read(path)
    local file = assert(io.open(path, 'rb'))
    local contents = file:read('a')
    file:close()
    return contents
end

local function reset_modules()
    for name in pairs(package.loaded) do
        if name:match('^shared%.') or name:match('^client%.') or name:match('^server%.') or name:match('^menu%.') then
            package.loaded[name] = nil
        end
    end
end

describe('entrypoints', function()
    local cfx

    after_each(function()
        cfx:uninstall()
    end)

    it('starts the server and writes both example files', function()
        cfx = CfxMock.new({ resource_name = 'vMenu.Enhanced', is_server = true }):install()
        for _, path in ipairs({ 'config/weapons.json', 'config/ped-models.json', 'config/vehicle-categories.json' }) do
            cfx:set_resource_file(path, read(path))
        end
        reset_modules()
        require('server.main')

        assert.are.equal(
            read('tests/fixtures/upstream/configuration.cfg.example'),
            cfx.resource_files['config/configuration.cfg.example']
        )
        assert.is_string(cfx.resource_files['config/permissions.cfg.example'])
        assert.is_not_nil(cfx.commands.vmenu_refresh_permissions)
    end)

    it('starts the client and registers its commands', function()
        cfx = CfxMock.new({ resource_name = 'vMenu.Enhanced' }):install()
        reset_modules()
        require('client.main')

        assert.is_not_nil(cfx.commands.vmenu_config)
        assert.is_not_nil(cfx.commands['menuapi:vmenu.enhanced:ticks'])
    end)

    it('refuses to start under another folder name', function()
        cfx = CfxMock.new({ resource_name = 'vMenu', is_server = true }):install()
        reset_modules()
        require('server.main')
        assert.is_nil(cfx.resource_files['config/configuration.cfg.example'])
    end)
end)
