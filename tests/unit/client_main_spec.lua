-- MainMenu port specs (client/main.lua): KVP cleanup, key mappings, the
-- permission-driven menu tree, and the staff-only gate.

local CfxMock = require('tests.mocks.cfx')

describe('client main', function()
    local cfx, Main, State, Controller, Json

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
            'client.noclip',
            'client.storage',
            'client.user_defaults',
            'client.weapons',
            'client.tattoos',
            'client.menus.about',
            'client.menus.recording',
            'client.menus.time_options',
            'client.menus.weather_options',
            'client.menus.voice_chat',
            'client.menus.player_options',
            'client.menus.vehicle_spawner',
            'client.menus.misc_settings',
            'client.main',
            'menu.controller',
            'menu.menu',
            'menu.items',
            'menu.sounds',
            'menu.draw',
            'menu.render',
            'menu.process',
        }) do
            package.loaded[name] = nil
        end
        Main = require('client.main')
        State = require('client.state')
        Controller = require('menu.controller')
        Json = require('shared.json_compat')
    end

    before_each(function()
        cfx = CfxMock.new():install()
        cfx:set_convar('vmenu_use_permissions', 'true')
        cfx:add_player('0', { name = 'LocalPlayer' })
    end)

    after_each(function()
        cfx:uninstall()
    end)

    describe('kvp cleanup', function()
        it('removes unrecognized keys but keeps all save prefixes', function()
            cfx.kvp['some_old_junk'] = 'x'
            cfx.kvp['mp_char_legacy'] = 'x'
            cfx.kvp['settings_keep'] = 'True'
            cfx.kvp['veh_keep'] = '{}'
            cfx.kvp['ped_keep'] = '{}'
            cfx.kvp['mp_ped_keep'] = '{}'
            cfx.kvp['vmenu_ban_keep'] = '{}'

            fresh_modules()

            assert.is_nil(cfx.kvp['some_old_junk'])
            assert.is_nil(cfx.kvp['mp_char_legacy'])
            assert.equal('True', cfx.kvp['settings_keep'])
            assert.equal('{}', cfx.kvp['veh_keep'])
            assert.equal('{}', cfx.kvp['ped_keep'])
            assert.equal('{}', cfx.kvp['mp_ped_keep'])
            assert.equal('{}', cfx.kvp['vmenu_ban_keep'])
            assert.equal(2, GetResourceKvpInt('vmenu_cleanup_version'))
        end)

        it('runs only once per cleanup version', function()
            fresh_modules()
            cfx.kvp['some_old_junk'] = 'x'
            fresh_modules()
            assert.equal('x', cfx.kvp['some_old_junk'])
        end)
    end)

    describe('key mappings', function()
        it('registers the persistent mapping names with defaults', function()
            fresh_modules()
            local by_command = {}
            for _, mapping in ipairs(cfx.key_mappings) do
                by_command[mapping.command .. '|' .. mapping.mapper] = mapping
            end
            assert.equal('F2', by_command['vMenu:Default:NoClip|keyboard'].key)
            assert.equal('M', by_command['vMenu:Default:MenuToggle|keyboard'].key)
            assert.equal('start_index', by_command['vMenu:Default:MenuToggle|pad_digitalbuttonany'].key)
        end)

        it('honors the keymapping id and key convars', function()
            cfx:set_convar('vmenu_keymapping_id', 'srv1')
            cfx:set_convar('vmenu_noclip_toggle_key', 'K')
            cfx:set_convar('vmenu_menu_toggle_key', 'F9')
            fresh_modules()
            local found = {}
            for _, mapping in ipairs(cfx.key_mappings) do
                found[mapping.command .. '|' .. mapping.mapper] = mapping.key
            end
            assert.equal('K', found['vMenu:srv1:NoClip|keyboard'])
            assert.equal('F9', found['vMenu:srv1:MenuToggle|keyboard'])
        end)

        it('registers the client commands', function()
            fresh_modules()
            assert.is_table(cfx.commands['vMenu:Default:NoClip'])
            assert.is_table(cfx.commands['vMenu:DV'])
            assert.is_table(cfx.commands['vmenuclient'])
        end)
    end)

    describe('permission flow', function()
        local function push(grants)
            TriggerClientEvent('vMenu:SetConfigOptions', 0)
            TriggerClientEvent('vMenu:SetPermissions', 0, Json.encode(grants))
            TriggerClientEvent('vMenu:SetSupplementaryPermissions', 0, Json.encode({}))
        end

        it('collects the 23 vehicle spawner category flags', function()
            fresh_modules()
            push({ VSAll = true })
            local count = 0
            for _, allowed in ipairs(State.allowed_vehicle_categories) do
                count = count + 1
                assert.is_true(allowed)
            end
            assert.equal(23, count)
        end)

        local function menu_texts()
            local texts = {}
            for _, item in ipairs(State.menu:GetMenuItems()) do
                texts[item.Text] = true
            end
            return texts
        end

        it('builds the menu tree gated by permissions', function()
            fresh_modules()
            push({ NoClip = true })
            Main._post_permissions_setup()

            assert.is_truthy(State.menu)
            assert.equal(State.menu, Controller.MainMenu)
            -- The player category stays (NoClip toggle lives there) plus the
            -- three upstream-ungated menus; the empty vehicle/world category
            -- buttons are removed.
            local texts = menu_texts()
            assert.is_true(texts['Player Related Options'])
            assert.is_true(texts['Recording Options'])
            assert.is_true(texts['Misc Settings'])
            assert.is_true(texts['About vMenu'])
            assert.is_nil(texts['Vehicle Related Options'])
            assert.is_nil(texts['World Related Options'])
            assert.equal(4, State.menu:Size())
            assert.equal(1, State.player_submenu:Size())
            assert.equal('Toggle NoClip', State.player_submenu:GetMenuItems()[1].Text)

            -- the menu toggle command is registered once the menu exists
            assert.is_table(cfx.commands['vMenu:Default:MenuToggle'])
        end)

        it('adds permission-gated menus when granted', function()
            cfx:set_convar('vmenu_enable_time_sync', 'true')
            cfx:set_convar('vmenu_enable_weather_sync', 'true')
            fresh_modules()
            push({ POMenu = true, VSMenu = true, TOMenu = true, WOMenu = true, VCMenu = true })
            Main._post_permissions_setup()

            local texts = menu_texts()
            assert.is_true(texts['Player Related Options'])
            assert.is_true(texts['Vehicle Related Options'])
            assert.is_true(texts['World Related Options'])
            assert.is_true(texts['Voice Chat Settings'])

            local player_texts = {}
            for _, item in ipairs(State.player_submenu:GetMenuItems()) do
                player_texts[item.Text] = true
            end
            assert.is_true(player_texts['Player Options'])
        end)

        it('removes every category button without any grants', function()
            fresh_modules()
            push({})
            Main._post_permissions_setup()
            -- only the three ungated menus remain
            assert.equal(3, State.menu:Size())
            local texts = menu_texts()
            assert.is_nil(texts['Player Related Options'])
            assert.is_nil(texts['Vehicle Related Options'])
            assert.is_nil(texts['World Related Options'])
        end)

        it('enforces the staff-only gate', function()
            cfx:set_convar('vmenu_menu_staff_only', 'true')
            fresh_modules()
            push({ NoClip = true })
            Main._post_permissions_setup()

            assert.is_nil(Controller.MainMenu)
            assert.is_true(Controller.DontOpenAnyMenu)
            assert.is_false(State.menu_enabled)
            assert.is_nil(State.menu)
        end)

        it('lets staff through the gate', function()
            cfx:set_convar('vmenu_menu_staff_only', 'true')
            fresh_modules()
            push({ NoClip = true, Staff = true })
            Main._post_permissions_setup()
            assert.is_truthy(State.menu)
            assert.is_true(State.menu_enabled)
        end)
    end)

    describe('misc wiring', function()
        it('enables infinity player lists from the onesync global state', function()
            cfx.global_state.vmenu_onesync = true
            fresh_modules()
            local PlayerLists = require('client.player_lists')
            assert.is_true(PlayerLists.is_infinity_mode())
        end)

        it('warns on coords replies for unknown rpc ids without crashing', function()
            fresh_modules()
            TriggerClientEvent('vMenu:GetPlayerCoords:reply', 0, 999, { x = 0.0, y = 0.0, z = 0.0 })
        end)

        it('the vmenuclient dump command completes', function()
            fresh_modules()
            cfx.kvp['settings_playerGodMode'] = 'True'
            cfx.kvp['veh_Test'] = '{"model":123}'
            cfx.commands.vmenuclient.handler(0, { 'dump' }, 'vmenuclient dump')
        end)

        it('the vmenuclient debug command toggles rich presence', function()
            fresh_modules()
            cfx.commands.vmenuclient.handler(0, { 'debug' }, 'vmenuclient debug')
            assert.is_truthy(cfx:calls('SetRichPresence')[1][1]:find('Debugging vMenu', 1, true))
        end)
    end)
end)
