-- Specs for client/storage.lua and client/user_defaults.lua. KVP envelopes are
-- a storage contract shared with upstream vMenu Enhanced: a player switching
-- between the C# build and this one keeps their saves only if both read and
-- write the same shape.

local CfxMock = require('tests.mocks.cfx')

local MODULES = { 'shared.log', 'shared.platform', 'shared.json_compat', 'shared.config', 'client.storage' }

describe('client/storage', function()
    local cfx, Storage

    before_each(function()
        cfx = CfxMock.new({ resource_name = 'vMenu.Enhanced' }):install()
        for _, name in ipairs(MODULES) do
            package.loaded[name] = nil
        end
        Storage = require('client.storage')
    end)

    after_each(function()
        cfx:uninstall()
    end)

    it('writes the envelope upstream writes', function()
        Storage.write('vmenu_default_language', 'string', 1, 'nl')
        assert.are.equal(
            '{"key":"vmenu_default_language","value":"nl","type":"string","version":1}',
            cfx.kvp.vmenu_default_language
        )
    end)

    it('reads an upstream envelope regardless of property case and order', function()
        cfx.kvp.vmenu_default_playerGodMode =
            '{"Version":1,"Type":"bool","Value":true,"Key":"vmenu_default_playerGodMode"}'
        assert.is_true(Storage.read('vmenu_default_playerGodMode', 'bool', 1))
    end)

    it('ignores a value stored as a different type', function()
        cfx.kvp.vmenu_x = '{"key":"vmenu_x","value":"1","type":"string","version":1}'
        assert.is_nil(Storage.read('vmenu_x', 'int', 1))
    end)

    -- A save written by a newer vMenu keeps the fields this build cannot see.
    it("carries a newer build's unknown fields through a save", function()
        cfx.kvp.vmenu_car =
            '{"key":"vmenu_car","value":{"name":"old","plate":"ABC","future":{"a":1}},"type":"json","version":3}'
        assert.is_true(Storage.write('vmenu_car', 'json', 1, { name = 'new', plate = 'ABC' }))

        local Json = require('shared.json_compat')
        local saved = Json.decode_ordered(cfx.kvp.vmenu_car)
        assert.are.equal(3, saved.version)
        assert.are.equal(1, saved.mergedBy)
        assert.same({ name = 'new', plate = 'ABC', future = { a = 1 } }, saved.value)
    end)

    it("refuses a save that would drop a newer build's data", function()
        local before = '{"key":"vmenu_car","value":{"mods":[1,2,3]},"type":"json","version":3}'
        cfx.kvp.vmenu_car = before
        assert.is_false(Storage.write('vmenu_car', 'json', 1, { mods = { 1 } }))
        assert.are.equal(before, cfx.kvp.vmenu_car)
    end)
end)

describe('client/user_defaults', function()
    local cfx, UserDefaults

    before_each(function()
        cfx = CfxMock.new({ resource_name = 'vMenu.Enhanced' }):install()
        for _, name in ipairs(MODULES) do
            package.loaded[name] = nil
        end
        package.loaded['client.user_defaults'] = nil
        UserDefaults = require('client.user_defaults')
    end)

    after_each(function()
        cfx:uninstall()
    end)

    it('stores the default on first read and notifies only on real changes', function()
        assert.is_true(UserDefaults.get('displayRightAlignMenu'))
        assert.is_not_nil(cfx.kvp.vmenu_default_displayRightAlignMenu)

        local changes = 0
        UserDefaults.on_changed('displaySpeedometer', function()
            changes = changes + 1
        end)
        UserDefaults.set('displaySpeedometer', 3) -- already the default
        UserDefaults.set('displaySpeedometer', 1)
        assert.are.equal(1, UserDefaults.get('displaySpeedometer'))
        UserDefaults.reset('displaySpeedometer')
        assert.are.equal(3, UserDefaults.get('displaySpeedometer'))
        assert.are.equal(2, changes)
    end)
end)
