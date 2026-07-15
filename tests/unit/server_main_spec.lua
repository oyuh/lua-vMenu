-- MainServer port specs (server/main.lua): startup wiring, weather/time
-- logic, the vmenuserver console command, and the permission-gated event
-- handlers. Contract: docs/contracts/events.md + convars.md.

local CfxMock = require('tests.mocks.cfx')

describe('server main', function()
    local cfx, Main, Bans, DateTime, Json, Permissions

    local function fresh_modules()
        for _, name in ipairs({
            'shared.config',
            'shared.json_compat',
            'shared.util',
            'shared.permissions',
            'server.log',
            'server.datetime',
            'server.bans',
            'server.main',
        }) do
            package.loaded[name] = nil
        end
        Main = require('server.main')
        Bans = require('server.bans')
        DateTime = require('server.datetime')
        Json = require('shared.json_compat')
        Permissions = require('shared.permissions')
    end

    before_each(function()
        cfx = CfxMock.new({ is_server = true }):install()
        -- keep the boot-time "permissions are ignored" warning out of the way
        cfx:set_convar('vmenu_use_permissions', 'true')
        fresh_modules()
    end)

    after_each(function()
        cfx:uninstall()
    end)

    local function triggers(name)
        local found = {}
        for _, entry in ipairs(cfx.triggered) do
            if entry.name == name then
                found[#found + 1] = entry
            end
        end
        return found
    end

    local function last_trigger(name)
        local found = triggers(name)
        return found[#found]
    end

    describe('boot', function()
        it('registers the restricted vmenuserver command', function()
            assert.is_table(cfx.commands.vmenuserver)
            assert.is_true(cfx.commands.vmenuserver.restricted)
        end)

        it('replicates the onesync state into GlobalState', function()
            assert.is_false(cfx.global_state.vmenu_onesync)
        end)

        it('spawns the first-tick permission sweep thread', function()
            assert.is_true(#cfx.threads >= 1)
        end)

        it('does not start sync loops unless the convars enable them', function()
            local baseline = #cfx.threads -- first boot: just the first-tick sweep
            cfx:set_convar('vmenu_enable_weather_sync', 'true')
            cfx:set_convar('vmenu_enable_time_sync', 'true')
            fresh_modules()
            -- second boot adds its own sweep plus the two sync loops
            assert.equal(baseline + 3, #cfx.threads)
        end)

        it('writes the supplementary permission template with whitelist perms', function()
            cfx:set_resource_file(
                'config/model-whitelists.json',
                '{ "whitelistedvehicle": ["adder"], "whitelistedweapons": ["WEAPON_PISTOL"], '
                    .. '"whitelistedpeds": ["a_m_y_skater_01"] }'
            )
            fresh_modules()

            local template = cfx.resource_files['config/templates/SupplementaryPermissionTemplate.cfg']
            assert.is_string(template)
            assert.is_truthy(
                template:find('add_ace builtin.everyone "vMenu.VehicleSpawner.WhitelistedModels.All" allow', 1, true)
            )
            assert.is_truthy(template:find('"vMenu.VehicleSpawner.WhitelistedModels.adder"', 1, true))
            assert.is_truthy(template:find('"vMenu.WeaponOptions.WhitelistedModels.pistol"', 1, true))
            assert.is_truthy(template:find('"vMenu.PlayerAppearance.WhitelistedModels.a_m_y_skater_01"', 1, true))

            local found = false
            for _, name in ipairs(Permissions.supplementary_list) do
                if name == 'VWadder' then
                    found = true
                end
            end
            assert.is_true(found)
        end)
    end)

    describe('weather refresh', function()
        local function weather()
            return GetConvar('vmenu_current_weather', 'CLEAR')
        end

        it('always clears up after rain and thunder', function()
            cfx:set_convar('vmenu_current_weather', 'RAIN')
            Main._refresh_weather(0)
            assert.equal('CLEARING', weather())
            Main._refresh_weather(0)
            assert.equal('CLOUDS', weather())

            cfx:set_convar('vmenu_current_weather', 'THUNDER')
            Main._refresh_weather(19)
            assert.equal('CLEARING', weather())
        end)

        it('maps the roll ranges like the C# switch', function()
            cfx:set_convar('vmenu_current_weather', 'CLEAR')
            Main._refresh_weather(0)
            assert.equal('EXTRASUNNY', weather())
            Main._refresh_weather(5)
            assert.equal('CLEAR', weather()) -- EXTRASUNNY flips back

            cfx:set_convar('vmenu_current_weather', 'OVERCAST')
            Main._refresh_weather(15)
            assert.equal('THUNDER', weather())

            cfx:set_convar('vmenu_current_weather', 'CLOUDS')
            Main._refresh_weather(16)
            assert.equal('EXTRASUNNY', weather())
            cfx:set_convar('vmenu_current_weather', 'CLEAR')
            Main._refresh_weather(16)
            assert.equal('RAIN', weather())

            cfx:set_convar('vmenu_current_weather', 'FOGGY')
            Main._refresh_weather(19)
            assert.equal('SMOG', weather())
            Main._refresh_weather(17)
            assert.equal('FOGGY', weather())
        end)
    end)

    describe('time tick', function()
        it('advances and wraps the clock via replicated convars', function()
            cfx:set_convar('vmenu_current_hour', '23')
            cfx:set_convar('vmenu_current_minute', '59')
            local delay = Main._time_tick()
            assert.equal(2000, delay) -- unset duration falls back to 2000ms
            assert.equal('0', GetConvar('vmenu_current_hour', ''))
            assert.equal('0', GetConvar('vmenu_current_minute', ''))

            Main._time_tick()
            assert.equal('1', GetConvar('vmenu_current_minute', ''))
        end)

        it('does not advance while time is frozen', function()
            cfx:set_convar('vmenu_current_minute', '10')
            cfx:set_convar('vmenu_freeze_time', 'true')
            Main._time_tick()
            assert.equal('10', GetConvar('vmenu_current_minute', ''))
        end)

        it('follows machine time when vmenu_sync_to_machine_time is set', function()
            cfx:set_convar('vmenu_sync_to_machine_time', 'true')
            local delay = Main._time_tick()
            assert.equal(60000, delay)
            local machine_time = os.date('*t')
            assert.equal(tostring(machine_time.hour), GetConvar('vmenu_current_hour', ''))
        end)

        it('respects a configured minute duration', function()
            cfx:set_convar('vmenu_ingame_minute_duration', '5000')
            assert.equal(5000, Main._time_tick())
            cfx:set_convar('vmenu_ingame_minute_duration', '50') -- < 100 → default
            assert.equal(2000, Main._time_tick())
        end)
    end)

    describe('weather & time events', function()
        it('applies weather changes for authorized players', function()
            cfx:add_player('1')
            cfx:grant_ace('1', 'vMenu.WeatherOptions.SetWeather')

            cfx:trigger_from('1', 'vMenu:UpdateServerWeather', 'thunder', true, false)

            assert.equal('THUNDER', GetConvar('vmenu_current_weather', ''))
            assert.equal('true', GetConvar('vmenu_enable_dynamic_weather', ''))
            assert.equal('false', GetConvar('vmenu_enable_snow', ''))
        end)

        it('forces snow on for snowy weather types', function()
            cfx:add_player('1')
            cfx:grant_ace('1', 'vMenu.WeatherOptions.SetWeather')
            cfx:trigger_from('1', 'vMenu:UpdateServerWeather', 'XMAS', false, false)
            assert.equal('true', GetConvar('vmenu_enable_snow', ''))
        end)

        it('treats unauthorized weather changes as cheating', function()
            cfx:set_convar('vmenu_auto_ban_cheaters', 'true')
            cfx:add_player('1', { identifiers = { 'license:s' } })

            cfx:trigger_from('1', 'vMenu:UpdateServerWeather', 'CLEAR', false, false)

            assert.equal('', GetConvar('vmenu_current_weather', ''))
            assert.equal(1, #Bans.get_ban_list())
            assert.is_truthy(last_trigger('vMenu:GoodBye'))
        end)

        it('sets the time directly when smooth transitions are off', function()
            cfx:add_player('1')
            cfx:grant_ace('1', 'vMenu.TimeOptions.SetTime')
            cfx:trigger_from('1', 'vMenu:UpdateServerTime', 14, 30, false)
            assert.equal('14', GetConvar('vmenu_current_hour', ''))
            assert.equal('30', GetConvar('vmenu_current_minute', ''))
        end)

        it('walks the clock forward under smooth transitions', function()
            cfx:set_convar('vmenu_smooth_time_transitions', 'true')
            cfx:set_convar('vmenu_current_hour', '10')
            cfx:set_convar('vmenu_current_minute', '0')
            cfx:add_player('1')
            cfx:grant_ace('1', 'vMenu.TimeOptions.SetTime')

            cfx:trigger_from('1', 'vMenu:UpdateServerTime', 12, 15, true)

            assert.equal('12', GetConvar('vmenu_current_hour', ''))
            assert.equal('15', GetConvar('vmenu_current_minute', ''))
            assert.equal('true', GetConvar('vmenu_freeze_time', ''))
        end)

        it('freezes time via vMenu:FreezeServerTime', function()
            cfx:add_player('1')
            cfx:grant_ace('1', 'vMenu.TimeOptions.FreezeTime')
            cfx:trigger_from('1', 'vMenu:FreezeServerTime', true)
            assert.equal('true', GetConvar('vmenu_freeze_time', ''))
        end)

        it('randomizes or removes clouds for all clients', function()
            cfx:add_player('1')
            cfx:grant_ace('1', 'vMenu.WeatherOptions.RemoveClouds')
            cfx:trigger_from('1', 'vMenu:UpdateServerWeatherCloudsType', true)
            local removed = last_trigger('vMenu:SetClouds')
            assert.equal(0.0, removed.args[1])
            assert.equal('removed', removed.args[2])

            cfx:grant_ace('1', 'vMenu.WeatherOptions.RandomizeClouds')
            cfx:trigger_from('1', 'vMenu:UpdateServerWeatherCloudsType', false)
            local randomized = last_trigger('vMenu:SetClouds')
            assert.is_number(randomized.args[1])
            assert.is_string(randomized.args[2])
            assert.not_equal('removed', randomized.args[2])
        end)
    end)

    describe('online player actions', function()
        it('kicks a target and logs when enabled', function()
            cfx:set_convar('vmenu_log_kick_actions', 'true')
            cfx:add_player('1', { name = 'Staff' })
            cfx:grant_ace('1', 'vMenu.OnlinePlayers.Kick')
            cfx:add_player('2', { name = 'Rowdy' })

            cfx:trigger_from('1', 'vMenu:KickPlayer', 2, 'calm down')

            assert.equal(1, #cfx.dropped)
            assert.equal('2', cfx.dropped[1].handle)
            assert.equal('calm down', cfx.dropped[1].reason)
            assert.is_truthy(cfx.resource_files['vmenu.log']:find('[KICK ACTION]', 1, true))
            assert.is_truthy(last_trigger('vMenu:Notify').args[1]:find('has been kicked', 1, true))
        end)

        it('protects targets with vMenu.DontKickMe', function()
            cfx:add_player('1', { name = 'Staff' })
            cfx:grant_ace('1', 'vMenu.OnlinePlayers.Kick')
            cfx:add_player('2', { name = 'Protected' })
            cfx:grant_ace('2', 'vMenu.DontKickMe')

            cfx:trigger_from('1', 'vMenu:KickPlayer', 2, 'nope')

            assert.same({}, cfx.dropped)
            assert.is_truthy(last_trigger('vMenu:Notify').args[1]:find('can ~r~not ~w~be kicked', 1, true))
        end)

        it('relays kill requests to the target client', function()
            cfx:add_player('1', { name = 'Staff' })
            cfx:grant_ace('1', 'vMenu.OnlinePlayers.Kill')
            cfx:add_player('2')

            cfx:trigger_from('1', 'vMenu:KillPlayer', 2)

            local kill = last_trigger('vMenu:KillMe')
            assert.is_truthy(kill)
            assert.equal('Staff', kill.args[1])
        end)

        it('delivers private messages and the staff log copy', function()
            cfx:add_player('1', { name = 'Sender' })
            cfx:grant_ace('1', 'vMenu.OnlinePlayers.SendMessage')
            cfx:add_player('2', { name = 'Receiver' })
            cfx:add_player('3', { name = 'Mod' })
            cfx:grant_ace('3', 'vMenu.OnlinePlayers.SeePrivateMessages')
            -- mark 3 as having completed the join flow
            cfx:trigger_from('3', 'playerJoining')

            cfx:trigger_from('1', 'vMenu:SendMessageToPlayer', 2, 'hello there')

            local pm = last_trigger('vMenu:PrivateMessage')
            assert.equal('1', pm.args[1])
            assert.equal('hello there', pm.args[2])

            local staff_log = nil
            for _, entry in ipairs(triggers('vMenu:Notify')) do
                if entry.args[1]:find('[vMenu Staff Log]', 1, true) then
                    staff_log = entry.args[1]
                end
            end
            assert.is_truthy(staff_log)
            assert.is_truthy(staff_log:find('sent a PM to', 1, true))
        end)

        it('respects disabled private messages on the target', function()
            cfx:add_player('1', { name = 'Sender' })
            cfx:grant_ace('1', 'vMenu.OnlinePlayers.SendMessage')
            cfx:add_player('2', { name = 'Receiver', state = { vmenu_pms_disabled = true } })

            cfx:trigger_from('1', 'vMenu:SendMessageToPlayer', 2, 'hello?')

            assert.is_nil(last_trigger('vMenu:PrivateMessage'))
            assert.is_truthy(last_trigger('vMenu:Notify').args[1]:find('could not be delivered', 1, true))
        end)
    end)

    describe('teleport locations', function()
        it('appends new locations and broadcasts the update', function()
            cfx:set_resource_file(
                'config/locations.json',
                '{ "teleports": [ { "name": "Old", "coordinates": { "x": 1.0, "y": 2.0, "z": 3.0 }, '
                    .. '"heading": 0.0 } ], "blips": [] }'
            )
            cfx:add_player('1')
            cfx:grant_ace('1', 'vMenu.MiscSettings.TeleportSaveLocation')

            cfx:trigger_from(
                '1',
                'vMenu:SaveTeleportLocation',
                '{ "name": "New", "coordinates": { "x": 4.0, "y": 5.0, "z": 6.0 }, "heading": 90.0 }'
            )

            local saved = Json.decode(cfx.resource_files['config/locations.json'])
            assert.equal(2, #saved.teleports)
            assert.equal('New', saved.teleports[2].name)

            local update = last_trigger('vMenu:UpdateTeleportLocations')
            local broadcast = Json.decode(update.args[1])
            assert.equal(2, #broadcast)
        end)

        it('rejects duplicate names', function()
            cfx:set_resource_file(
                'config/locations.json',
                '{ "teleports": [ { "name": "Spot", "coordinates": { "x": 1.0, "y": 2.0, "z": 3.0 }, '
                    .. '"heading": 0.0 } ], "blips": [] }'
            )
            cfx:add_player('1')
            cfx:grant_ace('1', 'vMenu.MiscSettings.TeleportSaveLocation')

            cfx:trigger_from('1', 'vMenu:SaveTeleportLocation', '{ "name": "Spot", "coordinates": {}, "heading": 0.0 }')

            local saved = Json.decode(cfx.resource_files['config/locations.json'])
            assert.equal(1, #saved.teleports)
        end)
    end)

    describe('player list & coords', function()
        it('answers vMenu:RequestPlayerList with {n, s} entries', function()
            cfx:add_player('1', { name = 'Alice' })
            cfx:add_player('2', { name = 'Bob' })

            cfx:trigger_from('1', 'vMenu:RequestPlayerList')

            local list = last_trigger('vMenu:ReceivePlayerList').args[1]
            assert.equal(2, #list)
            assert.equal('Alice', list[1].n)
            assert.equal(1, list[1].s)
        end)

        it('replies with target coords only when OPTeleport is allowed', function()
            cfx:add_player('1')
            cfx:add_player('2', { coords = { x = 10.0, y = 20.0, z = 30.0 } })

            cfx:trigger_from('1', 'vMenu:GetPlayerCoords', 77, 2, function() end)
            local denied = last_trigger('vMenu:GetPlayerCoords:reply')
            assert.equal(77, denied.args[1])
            assert.equal(0.0, denied.args[2].x)

            cfx:grant_ace('1', 'vMenu.OnlinePlayers.Teleport')
            cfx:trigger_from('1', 'vMenu:GetPlayerCoords', 78, 2, function() end)
            local allowed = last_trigger('vMenu:GetPlayerCoords:reply')
            assert.equal(10.0, allowed.args[2].x)
        end)
    end)

    describe('join & quit flow', function()
        it('pushes the full permission bundle on playerJoining', function()
            cfx:add_player('5')
            cfx:trigger_from('5', 'playerJoining')

            assert.is_truthy(last_trigger('vMenu:SetPermissions'))
            assert.is_truthy(last_trigger('vMenu:SetConfigOptions'))
            assert.equal('[]', last_trigger('vMenu:UpdateTeleportLocations').args[1])
            local supplementary = Json.decode(last_trigger('vMenu:SetSupplementaryPermissions').args[1])
            assert.is_false(supplementary.VWAll)
        end)

        it('fans join/quit notifications out to MSJoinQuitNotifs holders', function()
            cfx:add_player('9', { name = 'Watcher' })
            cfx:grant_ace('9', 'vMenu.MiscSettings.JoinQuitNotifs')
            cfx:trigger_from('9', 'playerJoining')

            cfx:add_player('10', { name = 'Newbie' })
            cfx:trigger_from('10', 'playerJoining')
            local join = last_trigger('vMenu:PlayerJoinQuit')
            assert.equal('Newbie', join.args[1])
            assert.is_nil(join.args[2])

            cfx:trigger_from('10', 'playerDropped', 'Quit.')
            local quit = last_trigger('vMenu:PlayerJoinQuit')
            assert.equal('Newbie', quit.args[1])
            assert.equal('Quit.', quit.args[2])
        end)

        it('ignores playerDropped for players that never joined', function()
            cfx:add_player('9', { name = 'Watcher' })
            cfx:grant_ace('9', 'vMenu.MiscSettings.JoinQuitNotifs')
            cfx:trigger_from('9', 'playerJoining')
            local before = #triggers('vMenu:PlayerJoinQuit')

            cfx:trigger_from('99', 'playerDropped', 'Ghost.')
            assert.equal(before, #triggers('vMenu:PlayerJoinQuit'))
        end)
    end)

    describe('clear area', function()
        it('broadcasts the source position to everyone', function()
            cfx:add_player('1', { coords = { x = 7.0, y = 8.0, z = 9.0 } })
            cfx:trigger_from('1', 'vMenu:ClearArea')
            local broadcast = last_trigger('vMenu:ClearArea')
            assert.equal(7.0, broadcast.args[1].x)
        end)
    end)

    describe('vmenuserver command', function()
        local function run(args)
            cfx.commands.vmenuserver.handler(0, args, table.concat(args or {}, ' '))
        end

        it('toggles debug mode', function()
            local Log = require('server.log')
            assert.is_false(Log.debug_mode)
            run({ 'debug' })
            assert.is_true(Log.debug_mode)
            run({ 'debug' })
            assert.is_false(Log.debug_mode)
        end)

        it('forwards weather changes through the shared event', function()
            run({ 'weather', 'rain' })
            local event = last_trigger('vMenu:UpdateServerWeather')
            assert.equal('RAIN', event.args[1])

            run({ 'weather', 'dynamic', 'true' })
            event = last_trigger('vMenu:UpdateServerWeather')
            assert.is_true(event.args[2])
        end)

        it('forwards time changes through the shared event', function()
            run({ 'time', '14', '45' })
            local event = last_trigger('vMenu:UpdateServerTime')
            assert.equal(14, event.args[1])
            assert.equal(45, event.args[2])

            local before = #triggers('vMenu:UpdateServerTime')
            run({ 'time', '99', '45' }) -- out of range
            assert.equal(before, #triggers('vMenu:UpdateServerTime'))
        end)

        it('console-bans an online player by name with Guid.Empty', function()
            cfx:add_player('4', { name = 'Griefer', identifiers = { 'license:g' } })

            run({ 'ban', 'name', 'griefer', 'being', 'a', 'griefer' })

            local list = Bans.get_ban_list()
            assert.equal(1, #list)
            assert.equal('Server Console', list[1].bannedBy)
            assert.equal(Bans.GUID_EMPTY, list[1].uuid)
            assert.equal('Banned by staff for: being a griefer', list[1].banReason)
            assert.equal(DateTime.PERM_BAN_ISO, list[1].bannedUntil)
            assert.equal(1, #cfx.dropped)
        end)

        it('unbans by uuid from the console', function()
            Bans.add_ban(Bans.new_record('Old', { 'license:o' }, DateTime.PERM_BAN_ISO, 'r', 'Admin', 'u-1'))
            run({ 'unban', 'u-1' })
            assert.same({}, Bans.get_ban_list())
        end)

        it('migrates bans.json records into KVP with fresh uuids', function()
            cfx:set_resource_file(
                'bans.json',
                '[ { "playerName": "Legacy", "identifiers": ["license:l"], "bannedUntil": "3000-01-01T00:00:00", '
                    .. '"banReason": "old system", "bannedBy": "Admin" } ]'
            )

            run({ 'migrate' })

            local list = Bans.get_ban_list()
            assert.equal(1, #list)
            assert.equal('Legacy', list[1].playerName)
            assert.not_equal(Bans.GUID_EMPTY, list[1].uuid)
            assert.is_truthy(list[1].banReason:find('Your ban id: ' .. list[1].uuid, 1, true))
        end)
    end)
end)
