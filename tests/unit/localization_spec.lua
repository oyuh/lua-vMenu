-- Specs for shared/localization.lua. A translation key that is not in the
-- English table renders as "!!key!!" in game, in a menu nobody may open for
-- weeks, so every literal key the source asks for is checked here instead.

local CfxMock = require('tests.mocks.cfx')

local function lua_files(directory, out)
    local pipe = io.popen(('find %s -name "*.lua"'):format(directory))
    for path in pipe:lines() do
        out[#out + 1] = path
    end
    pipe:close()
    return out
end

describe('shared/localization', function()
    local cfx, Localization

    before_each(function()
        cfx = CfxMock.new({ resource_name = 'vMenu.Enhanced' }):install()
        package.loaded['shared.localization'] = nil
        Localization = require('shared.localization')
    end)

    after_each(function()
        cfx:uninstall()
    end)

    it('has English text for every key the source asks for', function()
        local English = require('shared.data.english')
        local missing = {}
        local files = lua_files('client', lua_files('shared', lua_files('server', {})))
        for _, path in ipairs(files) do
            local file = assert(io.open(path, 'r'))
            local source = file:read('a')
            file:close()
            for key in source:gmatch("Localization%.key%(%s*'([^']+)'") do
                if English[key] == nil then
                    missing[#missing + 1] = path .. ': ' .. key
                end
            end
            for key in source:gmatch("Localization%.get%(%s*'([^']+)'") do
                if English[key] == nil then
                    missing[#missing + 1] = path .. ': ' .. key
                end
            end
            -- Menu definitions: title_key, subtitle_key and description_key.
            for _, field in ipairs({ 'title_key', 'subtitle_key', 'description_key' }) do
                for key in source:gmatch(field .. "%s*=%s*'([^']+)'%s*,") do
                    if English[key] == nil then
                        missing[#missing + 1] = path .. ': ' .. key
                    end
                end
            end
        end
        assert.same({}, missing)
    end)

    it('fills named placeholders, including nested translated ones', function()
        Localization.register('xx', 'Test', { ['a'] = 'Hello {name}, {{literal}}', ['b'] = 'World' })
        Localization.set_language('xx')
        assert.are.equal(
            'Hello World, {literal}',
            Localization.resolve(Localization.key('a', { name = Localization.key('b') }))
        )
    end)

    it('falls back to English, then to a visible marker', function()
        Localization.register('xx', 'Test', {})
        Localization.set_language('xx')
        assert.are.equal('No Permissions', Localization.get('framework.emptymenu'))
        assert.are.equal('!!no.such.key!!', Localization.get('no.such.key'))
    end)
end)
