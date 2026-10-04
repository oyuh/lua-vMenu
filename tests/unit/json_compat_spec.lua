-- Specs for shared/json_compat.lua.

local CfxMock = require('tests.mocks.cfx')

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
