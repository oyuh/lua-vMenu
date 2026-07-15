-- UserDefaults port specs (client/user_defaults.lua): the settings_ KVP
-- contract from docs/contracts/kvp-saves.md.

local CfxMock = require('tests.mocks.cfx')

describe('user defaults', function()
    local cfx, UserDefaults

    before_each(function()
        cfx = CfxMock.new():install()
        package.loaded['client.user_defaults'] = nil
        UserDefaults = require('client.user_defaults')
    end)

    after_each(function()
        cfx:uninstall()
    end)

    it('stores bools as capital True/False strings (C# bool.ToString())', function()
        UserDefaults.set_bool('playerGodMode', true)
        assert.equal('True', cfx.kvp['settings_playerGodMode'])
        UserDefaults.set_bool('playerGodMode', false)
        assert.equal('False', cfx.kvp['settings_playerGodMode'])
    end)

    it('reads C#-written values case-insensitively', function()
        cfx.kvp['settings_fastRun'] = 'True'
        assert.is_true(UserDefaults.get_bool('fastRun'))
        cfx.kvp['settings_fastRun'] = 'true'
        assert.is_true(UserDefaults.get_bool('fastRun'))
        cfx.kvp['settings_fastRun'] = 'False'
        assert.is_false(UserDefaults.get_bool('fastRun'))
    end)

    it('persists the default on first read: false for most settings', function()
        assert.is_false(UserDefaults.get_bool('playerGodMode'))
        assert.equal('False', cfx.kvp['settings_playerGodMode'])
    end)

    it('persists the default on first read: true for the hardcoded list', function()
        assert.is_true(UserDefaults.get_bool('unlimitedStamina'))
        assert.equal('True', cfx.kvp['settings_unlimitedStamina'])
        assert.is_true(UserDefaults.get_bool('autoEquipParachuteWhenInPlane'))
        assert.is_true(UserDefaults.get_bool('mpPedPreviews'))
        assert.is_true(UserDefaults.get_bool('vehicleGodInvincible'))
    end)

    it('round-trips ints and floats through the typed KVP natives', function()
        UserDefaults.set_int('clothingAnimationType', 2)
        assert.equal(2, UserDefaults.get_int('clothingAnimationType'))
        assert.equal(2, cfx.kvp_typed['settings_clothingAnimationType'].value)

        UserDefaults.set_float('voiceChatProximity', 15.5)
        assert.equal(15.5, UserDefaults.get_float('voiceChatProximity'))

        -- unset values come back as 0 / 0.0, like the real natives
        assert.equal(0, UserDefaults.get_int('miscLastTimeCycleModifierIndex'))
        assert.equal(0.0, UserDefaults.get_float('someUnsetFloat'))
    end)
end)
