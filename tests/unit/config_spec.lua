-- Specs for shared/config.lua against SharedClasses/ConfigManager.cs semantics.

local CfxMock = require('tests.mocks.cfx')

describe('shared/config', function()
    local cfx, Config

    before_each(function()
        cfx = CfxMock.new():install()
        package.loaded['shared.config'] = nil
        Config = require('shared.config')
    end)

    after_each(function()
        cfx:uninstall()
    end)

    describe('settings list', function()
        it('contains all 47 upstream settings', function()
            assert.equal(47, #Config.settings)
        end)

        it('matches upstream naming, including the unprefixed keep_player_head_props', function()
            local seen = {}
            for _, name in ipairs(Config.settings) do
                seen[name] = true
                assert.is_true(
                    name:sub(1, 6) == 'vmenu_' or name == 'keep_player_head_props',
                    ('unexpected setting name: %s'):format(name)
                )
            end
            assert.is_true(seen['vmenu_use_permissions'])
            assert.is_true(seen['vmenu_keymapping_id'])
        end)
    end)

    describe('get_bool (GetSettingsBool)', function()
        it('is true only for the literal string "true"', function()
            cfx:set_convar('vmenu_pvp_mode', 'true')
            assert.is_true(Config.get_bool('vmenu_pvp_mode'))
        end)

        it('is false when unset', function()
            assert.is_false(Config.get_bool('vmenu_pvp_mode'))
        end)

        it('is false for anything else, including "True" and "1"', function()
            cfx:set_convar('vmenu_pvp_mode', 'True')
            assert.is_false(Config.get_bool('vmenu_pvp_mode'))
            cfx:set_convar('vmenu_pvp_mode', '1')
            assert.is_false(Config.get_bool('vmenu_pvp_mode'))
        end)
    end)

    describe('get_int (GetSettingsInt)', function()
        it('returns the default when unset', function()
            assert.equal(-1, Config.get_int('vmenu_current_hour'))
            assert.equal(9, Config.get_int('vmenu_current_hour', 9))
        end)

        it('reads integer convars', function()
            cfx:set_convar('vmenu_current_hour', '18')
            assert.equal(18, Config.get_int('vmenu_current_hour'))
        end)

        it('falls back to string parsing when GetConvarInt yields the default', function()
            -- Upstream quirk: GetConvarInt can report the default even though the
            -- convar holds a parseable string; the string parse must win then.
            cfx:set_convar('vmenu_current_hour', '7')
            local original = GetConvarInt
            _G.GetConvarInt = function(_, default)
                return default
            end
            finally(function()
                _G.GetConvarInt = original
            end)
            assert.equal(7, Config.get_int('vmenu_current_hour'))
        end)

        it('does not int-parse fractional strings (int.TryParse rejects them)', function()
            cfx:set_convar('vmenu_current_hour', '7.5')
            local original = GetConvarInt
            _G.GetConvarInt = function(_, default)
                return default
            end
            finally(function()
                _G.GetConvarInt = original
            end)
            assert.equal(-1, Config.get_int('vmenu_current_hour'))
        end)

        it('accepts signs and surrounding whitespace like int.TryParse', function()
            cfx:set_convar('vmenu_current_minute', ' -30 ')
            local original = GetConvarInt
            _G.GetConvarInt = function(_, default)
                return default
            end
            finally(function()
                _G.GetConvarInt = original
            end)
            assert.equal(-30, Config.get_int('vmenu_current_minute'))
        end)
    end)

    describe('get_float (GetSettingsFloat)', function()
        it('returns the default when unset', function()
            assert.equal(-1.0, Config.get_float('vmenu_player_names_distance'))
            assert.equal(500.0, Config.get_float('vmenu_player_names_distance', 500.0))
        end)

        it('parses float convars', function()
            cfx:set_convar('vmenu_player_names_distance', '250.5')
            assert.equal(250.5, Config.get_float('vmenu_player_names_distance'))
        end)

        it('returns the default for unparseable values', function()
            cfx:set_convar('vmenu_player_names_distance', 'not-a-number')
            assert.equal(-1.0, Config.get_float('vmenu_player_names_distance'))
            assert.equal(3.5, Config.get_float('vmenu_player_names_distance', 3.5))
        end)

        it('always returns a float subtype', function()
            cfx:set_convar('vmenu_player_names_distance', '100')
            assert.equal('float', math.type(Config.get_float('vmenu_player_names_distance')))
        end)
    end)

    describe('get_string (GetSettingsString)', function()
        it('returns nil when unset and no default is given', function()
            assert.is_nil(Config.get_string('vmenu_server_info_message'))
        end)

        it('returns nil for empty values (C# returns null)', function()
            cfx:set_convar('vmenu_server_info_message', '')
            assert.is_nil(Config.get_string('vmenu_server_info_message'))
        end)

        it('returns the value when set', function()
            cfx:set_convar('vmenu_keymapping_id', 'MyServer')
            assert.equal('MyServer', Config.get_string('vmenu_keymapping_id'))
        end)

        it('returns the default when unset', function()
            assert.equal('Default', Config.get_string('vmenu_keymapping_id', 'Default'))
        end)
    end)
end)

describe('shared/util', function()
    local cfx, Util

    before_each(function()
        cfx = CfxMock.new():install()
        package.loaded['shared.util'] = nil
        Util = require('shared.util')
    end)

    after_each(function()
        cfx:uninstall()
    end)

    it('reads debug mode from resource metadata like upstream', function()
        assert.is_false(Util.is_debug_enabled())
        cfx:set_metadata('client_debug_mode', 'TRUE')
        assert.is_true(Util.is_debug_enabled())
    end)

    it('uses the server metadata key on the server side', function()
        cfx:uninstall()
        cfx = CfxMock.new({ is_server = true }):install()
        cfx:set_metadata('server_debug_mode', 'true')
        assert.is_true(Util.is_debug_enabled())
        assert.is_true(Util.is_server())
    end)
end)

describe('shared/json_compat', function()
    local cfx, Json

    before_each(function()
        cfx = CfxMock.new():install()
        package.loaded['shared.json_compat'] = nil
        Json = require('shared.json_compat')
    end)

    after_each(function()
        cfx:uninstall()
    end)

    -- The shipped config/*.json files carry `//` and `/* */` comments, which
    -- upstream's Newtonsoft tolerates. Decode must too, or config loads fail
    -- in-game ("model-whitelists.json ... invalid JSON").
    it('ignores // line comments like Newtonsoft', function()
        local decoded = Json.decode('{\n  // a comment\n  "a": 1\n}')
        assert.same({ a = 1 }, decoded)
    end)

    it('ignores /* */ block comments', function()
        local decoded = Json.decode('{ "a": 1, /* b is next */ "b": 2 }')
        assert.same({ a = 1, b = 2 }, decoded)
    end)

    it('leaves // sequences inside string values untouched', function()
        local decoded = Json.decode('{ "url": "https://example.com/x" }')
        assert.same({ url = 'https://example.com/x' }, decoded)
    end)

    it('parses the shipped model-whitelists.json shape (comments + arrays)', function()
        local text = [[{
  // whitelisted models generate supplementary permissions
  "whitelistedvehicle": ["a", "b"],
  "whitelistedpeds": ["c"]
}]]
        assert.same({ whitelistedvehicle = { 'a', 'b' }, whitelistedpeds = { 'c' } }, Json.decode(text))
    end)

    it('still returns nil for genuinely invalid JSON', function()
        assert.is_nil(Json.decode('{ not json'))
        assert.is_nil(Json.decode(''))
    end)
end)
