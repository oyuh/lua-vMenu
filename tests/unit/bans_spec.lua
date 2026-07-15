-- BanManager port specs (server/bans.lua) against vMenuServer/BanManager.cs
-- behaviors. Record shape contract: docs/contracts/kvp-saves.md +
-- tests/fixtures/ban_record.json.

local CfxMock = require('tests.mocks.cfx')

describe('ban manager', function()
    local cfx, Bans, DateTime, Json

    local function fresh_modules()
        for _, name in ipairs({
            'shared.config',
            'shared.json_compat',
            'shared.util',
            'server.log',
            'server.datetime',
            'server.bans',
        }) do
            package.loaded[name] = nil
        end
        Bans = require('server.bans')
        DateTime = require('server.datetime')
        Json = require('shared.json_compat')
    end

    before_each(function()
        cfx = CfxMock.new({ is_server = true }):install()
        fresh_modules()
    end)

    after_each(function()
        cfx:uninstall()
    end)

    local function last_trigger(name)
        for i = #cfx.triggered, 1, -1 do
            if cfx.triggered[i].name == name then
                return cfx.triggered[i]
            end
        end
        return nil
    end

    describe('uuids', function()
        it('generates version-4 lowercase guids', function()
            local uuid = Bans.new_uuid()
            assert.is_truthy(
                uuid:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89ab]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$')
            )
            assert.equal(uuid:lower(), uuid)
            assert.not_equal(Bans.new_uuid(), uuid)
        end)
    end)

    describe('record construction', function()
        it('appends the ban id suffix to the reason', function()
            local record = Bans.new_record('Name', {}, DateTime.PERM_BAN_ISO, 'Cheating.', 'Admin', 'abc-123')
            assert.equal('Cheating.\nYour ban id: abc-123', record.banReason)
        end)

        it('does not append the suffix twice or for Guid.Empty', function()
            local record = Bans.new_record(
                'Name',
                {},
                DateTime.PERM_BAN_ISO,
                'Cheating.\nYour ban id: abc-123',
                'Admin',
                'abc-123'
            )
            assert.equal('Cheating.\nYour ban id: abc-123', record.banReason)

            local console =
                Bans.new_record('Name', {}, DateTime.PERM_BAN_ISO, 'Bad.', 'Server Console', Bans.GUID_EMPTY)
            assert.equal('Bad.', console.banReason)
        end)
    end)

    describe('storage', function()
        it('stores records under vmenu_ban_<uuid> and refreshes the cache on change', function()
            assert.same({}, Bans.get_ban_list())

            local record = Bans.new_record('Name', { 'license:1' }, DateTime.PERM_BAN_ISO, 'r', 'Admin', 'uuid-1')
            Bans.add_ban(record)
            assert.is_string(cfx.kvp['vmenu_ban_uuid-1'])

            local list = Bans.get_ban_list()
            assert.equal(1, #list)
            assert.equal('Name', list[1].playerName)

            Bans.remove_ban(record)
            assert.is_nil(cfx.kvp['vmenu_ban_uuid-1'])
            assert.same({}, Bans.get_ban_list())
        end)

        it('refuses to overwrite an existing record with the same uuid', function()
            Bans.add_ban(Bans.new_record('First', {}, DateTime.PERM_BAN_ISO, 'r', 'A', 'dup'))
            Bans.add_ban(Bans.new_record('Second', {}, DateTime.PERM_BAN_ISO, 'r', 'A', 'dup'))
            assert.equal(1, #Bans.get_ban_list())
            assert.equal('First', Bans.get_ban_list()[1].playerName)
        end)

        it('round-trips the C# golden fixture', function()
            local file = assert(io.open('tests/fixtures/ban_record.json', 'r'))
            local fixture = file:read('a')
            file:close()
            cfx.kvp['vmenu_ban_6f9619ff-8b86-d011-b42d-00cf4fc964ff'] = fixture

            local list = Bans.get_ban_list()
            assert.equal(1, #list)
            assert.equal('SomeCheater', list[1].playerName)
            assert.is_true(DateTime.is_permanent(list[1].bannedUntil))
        end)
    end)

    describe('remaining time message', function()
        it('formats days/hours/minutes with upstream spacing and plurals', function()
            assert.equal('Less than 1 minute', Bans.get_remaining_time_message(0))
            assert.equal('Less than 1 minute', Bans.get_remaining_time_message(59))
            assert.equal('1 minute', Bans.get_remaining_time_message(60))
            assert.equal('1 hour 1 minute', Bans.get_remaining_time_message(3661))
            assert.equal('1 day 1 hour 1 minute', Bans.get_remaining_time_message(90061))
            -- trailing space when minutes are zero: quirk preserved
            assert.equal('2 days 3 hours ', Bans.get_remaining_time_message(2 * 86400 + 3 * 3600))
        end)
    end)

    describe('safe player names', function()
        it('strips markup, non-ascii, and trims punctuation', function()
            -- only the four literal chars ^ < > ~ are removed (C# Replace)
            assert.equal('1CBob/Cs', Bans.get_safe_player_name('^1<C>Bob</C>~s~'))
            assert.equal('Bob', Bans.get_safe_player_name('<B>ob!'))
            assert.equal('caf', Bans.get_safe_player_name('café'))
            assert.equal('name', Bans.get_safe_player_name('...name!?'))
            assert.equal('InvalidPlayerName', Bans.get_safe_player_name('???'))
            assert.equal('InvalidPlayerName', Bans.get_safe_player_name(nil))
            assert.equal('InvalidPlayerName', Bans.get_safe_player_name(''))
        end)
    end)

    describe('ban log', function()
        it('appends to vmenu.log only when vmenu_log_ban_actions is set', function()
            Bans.ban_log('quiet')
            assert.is_nil(cfx.resource_files['vmenu.log'])

            cfx:set_convar('vmenu_log_ban_actions', 'true')
            Bans.ban_log('first entry')
            Bans.ban_log('second entry')
            local log = cfx.resource_files['vmenu.log']
            assert.is_truthy(log:find('[BAN ACTION] first entry', 1, true))
            assert.is_truthy(log:find('[BAN ACTION] second entry', 1, true))
        end)
    end)

    describe('ban_cheater', function()
        it('does nothing when vmenu_auto_ban_cheaters is off', function()
            cfx:add_player('3', { identifiers = { 'license:abc' } })
            Bans.ban_cheater('3')
            assert.same({}, Bans.get_ban_list())
        end)

        it('permanently bans with the default reason and says goodbye', function()
            cfx:set_convar('vmenu_auto_ban_cheaters', 'true')
            cfx:add_player('3', { name = 'Cheater', identifiers = { 'license:abc' } })

            Bans.ban_cheater('3')

            local list = Bans.get_ban_list()
            assert.equal(1, #list)
            assert.equal('Cheater', list[1].playerName)
            assert.equal('vMenu Auto Ban', list[1].bannedBy)
            assert.equal(DateTime.PERM_BAN_ISO, list[1].bannedUntil)
            assert.is_truthy(list[1].banReason:find('You have been automatically banned', 1, true))
            assert.same({ 'license:abc' }, list[1].identifiers)

            assert.is_truthy(last_trigger('vMenu:BanCheaterSuccessful'))
            assert.is_truthy(last_trigger('vMenu:GoodBye'))
        end)
    end)

    describe('event flow', function()
        before_each(function()
            Bans.register()
        end)

        it('temp-bans a target, capping the duration at 720 hours', function()
            cfx:add_player('1', { name = 'Staff' })
            cfx:grant_ace('1', 'vMenu.OnlinePlayers.TempBan')
            cfx:add_player('2', { name = 'Target', identifiers = { 'license:t' } })

            cfx:trigger_from('1', 'vMenu:TempBanPlayer', 2, 10000.0, 'Being rude')

            local list = Bans.get_ban_list()
            assert.equal(1, #list)
            local record = list[1]
            assert.equal('Target', record.playerName)
            assert.equal('Staff', record.bannedBy)
            assert.is_truthy(record.banReason:find('Being rude', 1, true))
            assert.is_truthy(record.banReason:find('Your ban id: ' .. record.uuid, 1, true))

            local remaining = DateTime.seconds_until(record.bannedUntil)
            assert.is_true(remaining > 720 * 3600 - 60 and remaining <= 720 * 3600 + 60)

            assert.equal(1, #cfx.dropped)
            assert.equal('2', cfx.dropped[1].handle)
            assert.is_truthy(cfx.dropped[1].reason:find('You are banned from this server', 1, true))
            assert.is_truthy(last_trigger('vMenu:BanSuccessful'))
        end)

        it('perm-bans via vMenu:PermBanPlayer', function()
            cfx:add_player('1', { name = 'Staff' })
            cfx:grant_ace('1', 'vMenu.Everything')
            cfx:add_player('2', { name = 'Target' })

            cfx:trigger_from('1', 'vMenu:PermBanPlayer', 2, 'Forever')

            assert.equal(DateTime.PERM_BAN_ISO, Bans.get_ban_list()[1].bannedUntil)
        end)

        it('respects vMenu.DontBanMe', function()
            cfx:add_player('1', { name = 'Staff' })
            cfx:grant_ace('1', 'vMenu.OnlinePlayers.TempBan')
            cfx:add_player('2', { name = 'Protected' })
            cfx:grant_ace('2', 'vMenu.DontBanMe')

            cfx:trigger_from('1', 'vMenu:TempBanPlayer', 2, 1.0, 'nope')

            assert.same({}, Bans.get_ban_list())
            assert.same({}, cfx.dropped)
            local notify = last_trigger('vMenu:Notify')
            assert.is_truthy(notify.args[1]:find('exempt from being banned', 1, true))
        end)

        it('bans the source as a cheater on unauthorized ban attempts', function()
            cfx:set_convar('vmenu_auto_ban_cheaters', 'true')
            cfx:add_player('1', { name = 'Sneaky', identifiers = { 'license:s' } })
            cfx:add_player('2', { name = 'Target' })

            cfx:trigger_from('1', 'vMenu:TempBanPlayer', 2, 1.0, 'gotcha')

            local list = Bans.get_ban_list()
            assert.equal(1, #list)
            assert.equal('Sneaky', list[1].playerName)
            assert.equal('vMenu Auto Ban', list[1].bannedBy)
        end)

        it('blocks banned identifiers on playerConnecting and cancels the event', function()
            Bans.add_ban(Bans.new_record('Old', { 'license:banned' }, DateTime.PERM_BAN_ISO, 'r', 'Admin', 'u1'))
            cfx:add_player('9', { identifiers = { 'steam:x', 'license:banned' } })

            local kick_message = nil
            cfx:trigger_from('9', 'playerConnecting', 'Old', function(message)
                kick_message = message
            end)

            assert.is_truthy(kick_message:find('You have been permanently banned', 1, true))
            assert.is_true(cfx.event_cancelled)
        end)

        it('removes expired bans on connect and lets the player in', function()
            local expired = DateTime.to_iso(DateTime.now() - 3600)
            Bans.add_ban(Bans.new_record('Old', { 'license:was_banned' }, expired, 'r', 'Admin', 'u2'))
            cfx:add_player('9', { identifiers = { 'license:was_banned' } })

            local kick_message = nil
            cfx:trigger_from('9', 'playerConnecting', 'Old', function(message)
                kick_message = message
            end)

            assert.is_nil(kick_message)
            assert.is_false(cfx.event_cancelled)
            assert.same({}, Bans.get_ban_list())
        end)

        it('unbans by uuid for authorized players', function()
            local record = Bans.new_record('Old', { 'license:b' }, DateTime.PERM_BAN_ISO, 'r', 'Admin', 'u3')
            Bans.add_ban(record)
            cfx:add_player('1', { name = 'Staff' })
            cfx:grant_ace('1', 'vMenu.OnlinePlayers.Unban')

            cfx:trigger_from('1', 'vMenu:RequestPlayerUnban', 'u3')

            assert.same({}, Bans.get_ban_list())
            assert.is_truthy(last_trigger('vMenu:UnbanSuccessful'))
        end)

        it('treats unauthorized unban attempts as cheating', function()
            cfx:set_convar('vmenu_auto_ban_cheaters', 'true')
            Bans.add_ban(Bans.new_record('Old', { 'license:b' }, DateTime.PERM_BAN_ISO, 'r', 'Admin', 'u4'))
            cfx:add_player('1', { name = 'Sneaky', identifiers = { 'license:s' } })

            cfx:trigger_from('1', 'vMenu:RequestPlayerUnban', 'u4')

            -- original ban still present + the cheater's new ban
            assert.equal(2, #Bans.get_ban_list())
        end)

        it('sends the ban list as a JSON array', function()
            cfx:add_player('1')
            cfx:trigger_from('1', 'vMenu:RequestBanList')
            assert.equal('[]', last_trigger('vMenu:SetBanList').args[1])

            Bans.add_ban(Bans.new_record('Old', { 'license:b' }, DateTime.PERM_BAN_ISO, 'r', 'Admin', 'u5'))
            cfx:trigger_from('1', 'vMenu:RequestBanList')
            local payload = Json.decode(last_trigger('vMenu:SetBanList').args[1])
            assert.equal(1, #payload)
            assert.equal('Old', payload[1].playerName)
        end)
    end)
end)
