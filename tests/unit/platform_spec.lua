-- Specs for shared/platform.lua.

describe('shared/platform', function()
    local Platform

    before_each(function()
        package.loaded['shared.platform'] = nil
        Platform = require('shared.platform')
    end)

    -- Current CfxLua defines a native the first time a script reads its name,
    -- through a metatable on _G, so a raw lookup misses every native the
    -- resource has not used yet (seen live: AddConvarChangeListener).
    it('finds natives the runtime defines on first use', function()
        local lazy = function() end
        setmetatable(_G, {
            __index = function(_, name)
                if name == 'LazyNative' then
                    return lazy
                end
            end,
        })
        local found = Platform.has('LazyNative')
        setmetatable(_G, nil)
        assert.is_true(found)
        assert.is_false(Platform.has('NoSuchNative'))
    end)
end)
