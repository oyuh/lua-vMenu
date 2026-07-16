-- Wave-1 menu specs (client/menus/*): permission gating, state fields, and
-- the server events each interaction fires.

local CfxMock = require('tests.mocks.cfx')

describe('wave-1 menus', function()
    local cfx, Permissions, Json, State

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
            'client.user_defaults',
            'client.noclip',
            'client.menus.about',
            'client.menus.recording',
            'client.menus.time_options',
            'client.menus.weather_options',
            'client.menus.voice_chat',
            'client.menus.player_options',
            'client.menus.vehicle_spawner',
            'client.menus.misc_settings',
            'menu.controller',
            'menu.menu',
            'menu.items',
            'menu.sounds',
        }) do
            package.loaded[name] = nil
        end
        Permissions = require('shared.permissions')
        Json = require('shared.json_compat')
        State = require('client.state')
    end

    local function grant(grants)
        Permissions.set_from_json(Json.encode(grants))
        Permissions.set_supplementary_from_json(Json.encode({}))
    end

    local function last_server_event(name)
        for i = #cfx.triggered, 1, -1 do
            local entry = cfx.triggered[i]
            if entry.name == name and entry.direction == 'to_server' then
                return entry
            end
        end
        return nil
    end

    local function find_item(menu, text)
        for _, item in ipairs(menu:GetMenuItems()) do
            if item.Text == text then
                return item
            end
        end
        return nil
    end

    before_each(function()
        cfx = CfxMock.new():install()
        cfx:add_player('0', { name = 'LocalPlayer' })
        fresh_modules()
    end)

    after_each(function()
        cfx:uninstall()
    end)

    describe('about', function()
        it('shows the server info entry only when configured', function()
            local About = require('client.menus.about')
            local plain = About.create()
            assert.equal(2, plain.menu:Size())

            cfx:set_convar('vmenu_server_info_message', 'Welcome!')
            cfx:set_convar('vmenu_server_info_website_url', 'example.com')
            local with_info = About.create()
            assert.equal(3, with_info.menu:Size())
            assert.equal('Server Info', with_info.menu:GetMenuItems()[1].Text)
            assert.equal('example.com', with_info.menu:GetMenuItems()[1].Label)
        end)
    end)

    describe('time options', function()
        it('gates items by permission', function()
            grant({})
            local TimeOptions = require('client.menus.time_options')
            assert.equal(0, TimeOptions.create().menu:Size())

            grant({ TOFreezeTime = true })
            assert.equal(1, TimeOptions.create().menu:Size())

            grant({ TOAll = true })
            -- freeze + 8 presets + 2 custom lists
            assert.equal(11, TimeOptions.create().menu:Size())
        end)

        it('toggles time freezing through the server event', function()
            grant({ TOFreezeTime = true })
            local TimeOptions = require('client.menus.time_options')
            local instance = TimeOptions.create()
            cfx:set_convar('vmenu_freeze_time', 'false')

            instance.menu:OpenMenu()
            instance.menu:SelectItem(instance.freeze_time_toggle)

            local event = last_server_event('vMenu:FreezeServerTime')
            assert.is_true(event.args[1])
        end)

        it('maps preset indices to the right hours', function()
            grant({ TOAll = true })
            local TimeOptions = require('client.menus.time_options')
            local instance = TimeOptions.create()
            instance.menu:OpenMenu()

            -- index 1 = "Early Morning" (freeze item is index 0) → 06:00
            instance.menu:SelectItem(1)
            local event = last_server_event('vMenu:UpdateServerTime')
            assert.equal(6, event.args[1])
            assert.equal(0, event.args[2])

            -- index 7 = "Midnight" → 00:00
            instance.menu:SelectItem(7)
            event = last_server_event('vMenu:UpdateServerTime')
            assert.equal(0, event.args[1])
        end)
    end)

    describe('weather options', function()
        it('sends weather changes with the current dynamic/snow state', function()
            grant({ WOAll = true })
            cfx:set_convar('vmenu_enable_dynamic_weather', 'true')
            local WeatherOptions = require('client.menus.weather_options')
            local instance = WeatherOptions.create()
            instance.menu:OpenMenu()

            local thunder = find_item(instance.menu, 'Thunder')
            instance.menu:SelectItem(thunder)

            local event = last_server_event('vMenu:UpdateServerWeather')
            assert.equal('THUNDER', event.args[1])
            assert.is_true(event.args[2]) -- dynamic stays on
            assert.is_false(event.args[3])
        end)

        it('refuses disabling snow effects during snowy weather', function()
            grant({ WOAll = true })
            cfx:set_convar('vmenu_current_weather', 'XMAS')
            local WeatherOptions = require('client.menus.weather_options')
            local instance = WeatherOptions.create()
            instance.menu:OpenMenu()

            instance.menu:SelectItem(instance.snow_enabled) -- toggles the checkbox
            assert.is_nil(last_server_event('vMenu:UpdateServerWeather'))
        end)

        it('toggles blackout through its event', function()
            grant({ WOBlackout = true })
            local WeatherOptions = require('client.menus.weather_options')
            local instance = WeatherOptions.create()
            instance.menu:OpenMenu()

            instance.menu:SelectItem(instance.blackout)
            local event = last_server_event('vMenu:UpdateServerBlackout')
            assert.is_true(event.args[1])
        end)
    end)

    describe('voice chat', function()
        it('tracks checkbox state on the instance', function()
            grant({ VCEnable = true, VCShowSpeaker = true })
            local VoiceChat = require('client.menus.voice_chat')
            local instance = VoiceChat.create()
            instance.menu:OpenMenu()

            assert.is_true(instance.EnableVoicechat) -- default-true setting
            local enable = find_item(instance.menu, 'Enable Voice Chat')
            instance.menu:SelectItem(enable)
            assert.is_false(instance.EnableVoicechat)
        end)

        it('adds the staff channel only with the permission', function()
            grant({ VCEnable = true })
            local VoiceChat = require('client.menus.voice_chat')
            assert.equal(4, #VoiceChat.create().channels)

            grant({ VCEnable = true, VCStaffChannel = true })
            fresh_modules() -- clear the permission memo
            grant({ VCEnable = true, VCStaffChannel = true })
            local WithStaff = require('client.menus.voice_chat')
            assert.equal(5, #WithStaff.create().channels)
        end)
    end)

    describe('player options', function()
        it('gates items and always offers suicide', function()
            grant({})
            local PlayerOptions = require('client.menus.player_options')
            local instance = PlayerOptions.create()
            assert.equal(1, instance.menu:Size())
            assert.equal('~r~Commit Suicide', instance.menu:GetMenuItems()[1].Text)
        end)

        it('updates public fields and applies natives on toggle', function()
            grant({ POAll = true })
            local PlayerOptions = require('client.menus.player_options')
            local instance = PlayerOptions.create()
            instance.menu:OpenMenu()

            local god_mode = find_item(instance.menu, 'Godmode')
            instance.menu:SelectItem(god_mode)
            assert.is_true(instance.PlayerGodMode)

            local never_wanted = find_item(instance.menu, 'Never Wanted')
            -- default-true setting: first toggle turns it off
            instance.menu:SelectItem(never_wanted)
            assert.is_false(instance.PlayerNeverWanted)
            assert.equal(5, cfx:calls('SetMaxWantedLevel')[1][1])
        end)

        it('sets armor from the list selection', function()
            grant({ POAll = true })
            local PlayerOptions = require('client.menus.player_options')
            local instance = PlayerOptions.create()
            instance.menu:OpenMenu()

            local set_armor = find_item(instance.menu, 'Set Armor Type')
            set_armor.ListIndex = 3
            instance.menu:SelectItem(set_armor)
            assert.equal(60, cfx:calls('SetPedArmour')[1][2])
        end)

        it('starts scenarios in place', function()
            grant({ POAll = true })
            local PlayerOptions = require('client.menus.player_options')
            local instance = PlayerOptions.create()
            instance.menu:OpenMenu()

            local scenarios = find_item(instance.menu, 'Player Scenarios')
            instance.menu:SelectItem(scenarios)
            assert.equal(1, #cfx:calls('TaskStartScenarioInPlace'))
        end)
    end)

    describe('vehicle spawner', function()
        local function allow_all_categories()
            State.allowed_vehicle_categories = {}
            for i = 1, 23 do
                State.allowed_vehicle_categories[i] = true
            end
        end

        it('builds the 23 class submenus plus options', function()
            grant({ VSAll = true })
            allow_all_categories()
            local VehicleSpawner = require('client.menus.vehicle_spawner')
            local instance = VehicleSpawner.create()
            -- spawn-by-name + 2 checkboxes + addon button + 23 classes
            assert.equal(27, instance.menu:Size())
            assert.is_true(instance.SpawnInVehicle) -- default-true setting
            assert.is_true(instance.ReplaceVehicle)
        end)

        it('locks disabled categories', function()
            grant({ VSAll = true })
            allow_all_categories()
            State.allowed_vehicle_categories[1] = false -- Compacts
            local VehicleSpawner = require('client.menus.vehicle_spawner')
            local instance = VehicleSpawner.create()
            local compacts = find_item(instance.menu, 'VEH_CLASS_0')
            assert.is_false(compacts.Enabled)
        end)

        it('spawns a vehicle through the common spawn path', function()
            grant({ VSAll = true, VSSpawnByName = true })
            allow_all_categories()
            local Common = require('client.common')
            local handle = Common.spawn_vehicle_by_name('adder', false, true)
            assert.equal(2000, handle)
            assert.equal(1, #cfx:calls('CreateVehicle'))
        end)

        it('enforces the spawn rate limit', function()
            -- note: VSAll would imply VSBypassRateLimit, so grant nothing
            grant({})
            allow_all_categories()
            cfx.game_timer = 100000
            local Common = require('client.common')
            assert.equal(2000, Common.spawn_vehicle_by_name('adder', false, true))
            -- second spawn within the delay window is refused
            cfx.game_timer = 101000
            assert.equal(0, Common.spawn_vehicle_by_name('adder', false, true))
            -- after the delay it works again (default delay 5s)
            cfx.game_timer = 106000
            assert.equal(2000, Common.spawn_vehicle_by_name('adder', false, true))
        end)

        it('refuses restricted categories', function()
            grant({ VSAll = true })
            State.allowed_vehicle_categories = { false } -- class 0 disabled
            local Common = require('client.common')
            assert.equal(0, Common.spawn_vehicle_by_name('adder', false, true))
            assert.equal(0, #cfx:calls('CreateVehicle'))
        end)
    end)

    describe('misc settings', function()
        it('replicates the pms-disabled flag through the statebag', function()
            grant({})
            local MiscSettings = require('client.menus.misc_settings')
            local instance = MiscSettings.create()
            assert.is_false(cfx.local_player_state.vmenu_pms_disabled)

            instance.menu:OpenMenu()
            local disable_pms = find_item(instance.menu, 'Disable Private Messages')
            instance.menu:SelectItem(disable_pms)
            assert.is_true(instance.MiscDisablePrivateMessages)
            assert.is_true(cfx.local_player_state.vmenu_pms_disabled)
        end)

        it('shows teleport options only with a teleport permission', function()
            grant({})
            local MiscSettings = require('client.menus.misc_settings')
            assert.is_nil(find_item(MiscSettings.create().menu, 'Teleport Options'))

            fresh_modules()
            grant({ MSTeleportToWp = true })
            local WithTp = require('client.menus.misc_settings')
            assert.is_truthy(find_item(WithTp.create().menu, 'Teleport Options'))
        end)

        it('rebuilds the teleport locations submenu from server pushes', function()
            grant({ MSTeleportLocations = true })
            State.teleport_locations = {
                { name = 'Dock', coordinates = { x = 1.0, y = 2.0, z = 3.0 }, heading = 90.0 },
            }
            local MiscSettings = require('client.menus.misc_settings')
            local instance = MiscSettings.create()

            -- find the bound teleport locations submenu via the controller
            local Controller = require('menu.controller')
            local tp_btn
            for _, menu_obj in ipairs({ instance.menu }) do
                tp_btn = find_item(menu_obj, 'Teleport Options')
            end
            assert.is_truthy(tp_btn)
            local tp_options = Controller.MenuButtons[tp_btn]
            local locations_btn = find_item(tp_options, 'Teleport Locations')
            assert.is_truthy(locations_btn)
            local locations_menu = Controller.MenuButtons[locations_btn]

            locations_menu:OpenMenu()
            assert.equal(1, locations_menu:Size())
            assert.equal('Dock', locations_menu:GetMenuItems()[1].Text)
        end)

        it('save settings persists the menu state to settings_ kvps', function()
            grant({})
            local MiscSettings = require('client.menus.misc_settings')
            local instance = MiscSettings.create()
            State.menus.misc_settings = instance

            instance.menu:OpenMenu()
            local speed_kmh = find_item(instance.menu, 'Show Speed KM/H')
            instance.menu:SelectItem(speed_kmh)

            local save_btn = find_item(instance.menu, 'Save Personal Settings')
            instance.menu:SelectItem(save_btn)

            assert.equal('True', cfx.kvp['settings_miscSpeedoKmh'])
            assert.equal('True', cfx.kvp['settings_miscRestorePlayerAppearance'])
        end)
    end)
end)
