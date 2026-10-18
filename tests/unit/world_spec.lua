-- Specs for shared/world and server/world.lua. The schedule is worked out
-- separately on the server and every client from upstream's tables, so an
-- off-by-one here shows players different weather. Expected values are read
-- off upstream's EntriesNormal by hand.

local CfxMock = require('tests.mocks.cfx')

local function reset_modules()
    for name in pairs(package.loaded) do
        if name:match('^shared%.') or name:match('^server%.') then
            package.loaded[name] = nil
        end
    end
end

describe('world', function()
    local cfx

    before_each(function()
        cfx = CfxMock.new({ resource_name = 'vMenu.Enhanced', is_server = true }):install()
        reset_modules()
    end)

    after_each(function()
        cfx:uninstall()
    end)

    describe('the weather schedule', function()
        local WeatherCycle

        before_each(function()
            WeatherCycle = require('shared.world.weather_cycle')
            WeatherCycle.use('default')
        end)

        it('resolves the weather in force and the next different one', function()
            -- 2 CLEAR, 3 SMOG
            assert.same({ current = 'CLEAR', next = 'SMOG', hours_until_next = 0.5 }, WeatherCycle.resolve(2.5))
            -- 11 EXTRASUNNY, 13 EXTRASUNNY (no change), 14 OVERCAST
            assert.same({ current = 'EXTRASUNNY', next = 'OVERCAST', hours_until_next = 2 }, WeatherCycle.resolve(12))
            -- 381 SMOG, then the loop starts over at 0 EXTRASUNNY after 384 hours
            assert.same({ current = 'SMOG', next = 'EXTRASUNNY', hours_until_next = 2 }, WeatherCycle.resolve(382))
        end)

        it('forecasts the next weathers with how long each lasts', function()
            assert.same({
                { weather = 'SMOG', hours_until_start = 0.5, hours_long = 4 },
                { weather = 'EXTRASUNNY', hours_until_start = 4.5, hours_long = 1 },
            }, WeatherCycle.forecast(2.5, 2))
        end)

        it("packs a custom cycle the way upstream's server does", function()
            local custom = WeatherCycle.build_custom({
                snowPass = true,
                cycle = {
                    { hours = 2, weather = 'extrasunny' },
                    { hours = 1.5, weather = 'CLEAR', blackout = 'city' },
                    { hours = 0, weather = 'RAIN' },
                },
            }, function() end)
            assert.are.equal('1|2B1.5Ac', WeatherCycle.pack(custom))

            local back = WeatherCycle.build_custom(WeatherCycle.unpack('1|2B1.5Ac'), function() end)
            assert.same(custom, back)
        end)
    end)

    it('reads the times players type', function()
        local TimeText = require('shared.world.time_text')
        local cases = {
            ['15:25'] = 55500,
            ['1525'] = 55500,
            ['9'] = 32400,
            ['3pm'] = 54000,
            ['3:25 p'] = 55500,
            ['12am'] = 0,
            ['12 PM'] = 43200,
            ['7.05'] = 25500,
        }
        for input, expected in pairs(cases) do
            assert.are.equal(expected, TimeText.parse(input), input)
        end
        for _, input in ipairs({ '25:00', '13pm', '12:60', 'noon', '' }) do
            assert.is_nil(TimeText.parse(input), input)
        end
    end)

    describe('server actions', function()
        local PLAYER = 7

        before_each(function()
            cfx:set_convar('vMenu.Enhanced.WeatherOptions.Enabled', 'true')
            cfx:add_player(PLAYER)
            require('server.permissions').init()
            require('shared.config').init()
            require('server.world').init()
            require('server.actions').register_events()
        end)

        local function invoke(action, ...)
            cfx:trigger_from(PLAYER, 'vMenu.Enhanced:Action:Invoke', action, 1, { ... })
            local reply = cfx.triggered[#cfx.triggered]
            assert.are.equal('vMenu.Enhanced:Action:Result', reply.name)
            return reply.args[2]
        end

        it('refuses a player without the permission and leaves the weather alone', function()
            assert.are.equal(1, invoke('WeatherOptions.SetWeather', 'RAIN'))
            assert.are.equal('dynamic', cfx.convars['vMenu.Enhanced.State.Weather'])
        end)

        it('sets the weather for a player with the permission', function()
            cfx:grant_ace(PLAYER, 'vMenu.Enhanced.Menus.WeatherOptions.SetWeather')
            assert.are.equal(0, invoke('WeatherOptions.SetWeather', 'rain'))
            assert.are.equal('RAIN', cfx.convars['vMenu.Enhanced.State.Weather'])
            assert.are.equal(3, invoke('WeatherOptions.SetWeather', 'SUNNY'))
        end)
    end)
end)
