-- EventManager port specs (client/events.lua): config option parsing into
-- client state, event handlers, and the sync tick bodies.

local CfxMock = require('tests.mocks.cfx')

describe('client events', function()
    local cfx, Events, State, Json

    local function fresh_modules()
        for _, name in ipairs({
            'shared.config',
            'shared.json_compat',
            'shared.util',
            'shared.permissions',
            'client.state',
            'client.notify',
            'client.player_lists',
            'client.common',
            'client.events',
        }) do
            package.loaded[name] = nil
        end
        Events = require('client.events')
        State = require('client.state')
        Json = require('shared.json_compat')
    end

    before_each(function()
        cfx = CfxMock.new():install()
        fresh_modules()
    end)

    after_each(function()
        cfx:uninstall()
    end)

    describe('set_config_options', function()
        it('parses addons.json into hash maps and flags setup complete', function()
            cfx:set_resource_file(
                'config/addons.json',
                '{ "vehicles": ["mycar"], "weapons": ["weapon_custom"], "peds": ["my_ped"], '
                    .. '"extra_blendable_faces": ["face_a"] }'
            )
            assert.is_false(State.config_options_setup_complete)

            Events.set_config_options()

            assert.equal(GetHashKey('mycar'), State.addon_vehicles.mycar)
            assert.equal(GetHashKey('weapon_custom'), State.addon_weapons.weapon_custom)
            assert.equal(GetHashKey('my_ped'), State.addon_peds.my_ped)
            assert.same({ 'face_a' }, State.extra_blendable_faces)
            assert.is_true(State.config_options_setup_complete)
        end)

        it('parses whitelists, extras, and tattoos', function()
            cfx:set_resource_file('config/model-whitelists.json', '{ "whitelistedvehicle": ["adder"] }')
            cfx:set_resource_file('config/extras.json', '{ "police": { "1": "Lightbar" } }')
            cfx:set_resource_file(
                'config/tattoos.json',
                '[ { "collectionName": "col_a", "name": "tat_1", "zone": "ZONE_TORSO" } ]'
            )

            Events.set_config_options()

            assert.equal(GetHashKey('adder'), State.whitelist_vehicles.adder)
            assert.equal('Lightbar', State.vehicle_extras[GetHashKey('police')]['1'])
            assert.equal(1, #State.tattoos)
            assert.equal('col_a', State.tattoos[1].collectionName)
        end)

        it('keeps the first entry on duplicates', function()
            cfx:set_resource_file('config/addons.json', '{ "vehicles": ["dupe", "dupe"] }')
            Events.set_config_options()
            assert.equal(GetHashKey('dupe'), State.addon_vehicles.dupe)
        end)

        it('tolerates corrupt config files', function()
            cfx:set_resource_file('config/addons.json', '{ nope')
            Events.set_config_options()
            assert.same({}, State.addon_vehicles)
            assert.is_true(State.config_options_setup_complete)
        end)
    end)

    describe('event handlers', function()
        before_each(function()
            Events.register({})
        end)

        it('handles vMenu:SetConfigOptions and its deprecated alias', function()
            TriggerClientEvent('vMenu:SetAddons', 0)
            assert.is_true(State.config_options_setup_complete)
        end)

        it('updates teleport locations from the server push', function()
            TriggerClientEvent(
                'vMenu:UpdateTeleportLocations',
                0,
                Json.encode({ { name = 'Spot', coordinates = { x = 1.0, y = 2.0, z = 3.0 }, heading = 0.0 } })
            )
            assert.equal(1, #State.teleport_locations)
            assert.equal('Spot', State.teleport_locations[1].name)
        end)

        it('kills the player on vMenu:KillMe with the safe killer name', function()
            TriggerClientEvent('vMenu:KillMe', 0, 'Bad<Guy>')
            local calls = cfx:calls('SetEntityHealth')
            assert.equal(1, #calls)
            assert.equal(0, calls[1][2])
            -- markup got escaped, not stripped (client-side sanitizer)
            local drawn = cfx:calls('AddTextComponentSubstringPlayerName')
            local combined = ''
            for _, call in ipairs(drawn) do
                combined = combined .. call[1]
            end
            assert.is_truthy(combined:find('Bad«Guy»', 1, true))
        end)

        it('removes or transitions cloud hats', function()
            TriggerClientEvent('vMenu:SetClouds', 0, 0.0, 'removed')
            assert.equal(1, #cfx:calls('ClearCloudHat'))

            TriggerClientEvent('vMenu:SetClouds', 0, 0.5, 'Wispy')
            assert.equal(0.5, cfx:calls('SetCloudHatOpacity')[1][1])
            assert.equal('Wispy', cfx:calls('SetCloudHatTransition')[1][1])
        end)

        it('clears the area around the broadcast position', function()
            TriggerClientEvent('vMenu:ClearArea', 0, { x = 7.0, y = 8.0, z = 9.0 })
            local call = cfx:calls('ClearAreaOfEverything')[1]
            assert.equal(7.0, call[1])
            assert.equal(100.0, call[4])
        end)

        it('survives a first spawn with no menus ported yet', function()
            TriggerClientEvent('playerSpawned', 0)
            -- second spawn is a no-op (first_spawn latch)
            TriggerClientEvent('playerSpawned', 0)
        end)
    end)

    describe('sync tick bodies', function()
        it('time sync overrides the clock and picks the right delay', function()
            cfx:set_convar('vmenu_current_hour', '13')
            cfx:set_convar('vmenu_current_minute', '37')
            cfx:set_convar('vmenu_ingame_minute_duration', '4000')

            local delay = Events._time_sync()
            local call = cfx:calls('NetworkOverrideClockTime')[1]
            assert.equal(13, call[1])
            assert.equal(37, call[2])
            assert.equal(2000, delay) -- clamped to [100, 2000]

            cfx:set_convar('vmenu_freeze_time', 'true')
            assert.equal(5, Events._time_sync())
        end)

        it('weather sync transitions to the server weather and reports back', function()
            cfx:set_convar('vmenu_current_weather', 'THUNDER')
            cfx:set_convar('vmenu_weather_change_duration', '15')

            local delay = Events._weather_sync()
            assert.equal(1000, delay)
            local transition = cfx:calls('SetWeatherTypeOvertimePersist')[1]
            assert.equal('THUNDER', transition[1])
            assert.equal(15.0, transition[2])

            local complete = nil
            for _, entry in ipairs(cfx.triggered) do
                if entry.name == 'vMenu:WeatherChangeComplete' then
                    complete = entry
                end
            end
            assert.is_truthy(complete)
            assert.equal('THUNDER', complete.args[1])
        end)

        it('weather sync toggles snow particles from the convar', function()
            cfx:set_convar('vmenu_enable_snow', 'true')
            Events._weather_sync()
            assert.is_true(cfx:calls('ForceSnowPass')[1][1])
            assert.is_true(#cfx:calls('UseParticleFxAssetNextCall') > 0)

            cfx:set_convar('vmenu_enable_snow', 'false')
            Events._weather_sync()
            assert.is_true(#cfx:calls('RemoveNamedPtfxAsset') > 0)
        end)
    end)
end)
