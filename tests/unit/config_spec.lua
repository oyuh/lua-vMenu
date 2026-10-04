-- Specs for shared/config.lua and shared/data/configuration_example.lua.
-- The example file is a contract with server owners (they diff it against
-- their copy after an update), so it is compared byte for byte with the file
-- upstream vMenu Enhanced generated at the pinned release.

local CfxMock = require('tests.mocks.cfx')

local function read(path)
    local file = assert(io.open(path, 'rb'))
    local contents = file:read('a')
    file:close()
    return contents
end

local function fresh(modules)
    for _, name in ipairs(modules) do
        package.loaded[name] = nil
    end
end

local MODULES = { 'shared.log', 'shared.platform', 'shared.config', 'shared.data.configuration_example' }

describe('configuration.cfg.example', function()
    local cfx

    before_each(function()
        cfx = CfxMock.new({ resource_name = 'vMenu.Enhanced', is_server = true }):install()
        fresh(MODULES)
    end)

    after_each(function()
        cfx:uninstall()
    end)

    it('matches the file upstream generates', function()
        local Example = require('shared.data.configuration_example')
        assert.are.equal(read('tests/fixtures/upstream/configuration.cfg.example'), Example.render())
    end)
end)

describe('shared/config', function()
    local cfx, Config

    before_each(function()
        cfx = CfxMock.new({ resource_name = 'vMenu.Enhanced' }):install()
        fresh(MODULES)
        Config = require('shared.config')
    end)

    after_each(function()
        cfx:uninstall()
    end)

    -- ConvarValue.cs semantics: owners hand-type these, quotes and all.
    it('parses convar text the way upstream does', function()
        assert.is_true(Config.parse_bool(' "Yes" '))
        assert.is_false(Config.parse_bool('off'))
        assert.is_nil(Config.parse_bool('maybe'))
        assert.are.equal(-12, Config.parse_int(' -12 '))
        assert.is_nil(Config.parse_int('1.5'))
        assert.is_nil(Config.parse_int('2147483648'))
        assert.are.equal(2.5, Config.parse_float('"2.5"'))
        assert.is_nil(Config.parse_float('0x10'))
        assert.is_nil(Config.normalise('  ""  '))
    end)

    it('falls back to the default when a setting is unset or unparseable', function()
        Config.init()
        assert.are.equal(1, Config.value('vMenu.Enhanced.Gameplay.PvpMode'))
        cfx:set_convar('vMenu.Enhanced.Gameplay.PvpMode', 'two')
        assert.are.equal(1, Config.value('vMenu.Enhanced.Gameplay.PvpMode'))
        cfx:set_convar('vMenu.Enhanced.Gameplay.PvpMode', '2')
        assert.are.equal(2, Config.value('vMenu.Enhanced.Gameplay.PvpMode'))
    end)

    -- Webhook URLs and API keys use plain 'set' so no client can read them.
    it('never tracks server-only settings on a client', function()
        Config.init()
        for _, name in ipairs(Config.tracked()) do
            assert.is_not_true(Config.setting(name).server_only, name)
        end
    end)

    it('runs only the listeners for a setting that actually changed', function()
        Config.init()
        local named, broad = 0, 0
        Config.watch({ 'vMenu.Enhanced.Gameplay.PvpMode' }, function()
            named = named + 1
        end)
        Config.watch_except({ 'vMenu.Enhanced.Gameplay.PvpMode' }, function()
            broad = broad + 1
        end)

        Config.notify_changed('vMenu.Enhanced.Gameplay.PvpMode') -- value unchanged
        cfx:set_convar('vMenu.Enhanced.Gameplay.PvpMode', '2')
        Config.notify_changed('vMenu.Enhanced.Gameplay.PvpMode')
        cfx:set_convar('vMenu.Enhanced.Admin.ClearAreaRadius', '50')
        Config.notify_changed('vMenu.Enhanced.Admin.ClearAreaRadius')

        assert.are.equal(1, named)
        assert.are.equal(1, broad)
    end)
end)
