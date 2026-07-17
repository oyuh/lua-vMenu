-- FunctionsController specs: the vMenu:SetupTickFunctions registration gates
-- (permission/convar driven tick counts) and the join/quit notification
-- event handler. The tick loops themselves are frame-bound game code and are
-- verified in-game (M10 checklist); the mock queues threads without running
-- them, so registration is observable and safe.

local CfxMock = require('tests.mocks.cfx')

describe('functions controller', function()
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
            'client.ped_common',
            'client.vehicle_common',
            'client.storage',
            'client.user_defaults',
            'client.weapons',
            'client.functions_controller.main',
            'client.functions_controller.hud',
            'client.functions_controller.creator_camera',
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

    before_each(function()
        cfx = CfxMock.new():install()
        cfx:add_player('0', { name = 'LocalPlayer' })
        cfx.game_timer = 100000
        fresh_modules()
    end)

    after_each(function()
        cfx:uninstall()
    end)

    it('registers the always-on ticks with no permissions', function()
        grant({})
        local FunctionsController = require('client.functions_controller.main')
        FunctionsController.setup_tick_functions()
        -- 6 always-on ticks + the two config-default ticks
        -- (restore-after-death + the two entity outline ticks are enabled by
        -- default because their disable-convars default to false)
        assert.equal(9, #cfx.threads)
    end)

    it('registers permission-gated ticks only when allowed', function()
        grant({})
        local FunctionsController = require('client.functions_controller.main')
        FunctionsController.setup_tick_functions()
        local baseline = #cfx.threads

        fresh_modules()
        grant({ VOMenu = true, VOFlashHighbeamsOnHonk = true })
        FunctionsController = require('client.functions_controller.main')
        FunctionsController.setup_tick_functions()
        -- vehicle options + show health + highbeams + shared player/vehicle checks
        assert.equal(baseline + 4, #cfx.threads - baseline)
    end)

    it('fires the tick setup through the vMenu:SetupTickFunctions event', function()
        grant({})
        require('client.functions_controller.main')
        assert.equal(0, #cfx.threads)
        TriggerEvent('vMenu:SetupTickFunctions')
        assert.is_true(#cfx.threads > 0)
    end)

    it('shows join/quit notifications when enabled', function()
        grant({ MSJoinQuitNotifs = true })
        require('client.functions_controller.main')
        State.config_options_setup_complete = true
        State.menus.misc_settings = { JoinQuitNotifications = true }

        local notified = {}
        cfx:stub_native('AddTextComponentSubstringPlayerName', function(text)
            notified[#notified + 1] = text
        end)

        TriggerEvent('vMenu:PlayerJoinQuit', 'NewPlayer', nil)
        local found_join = false
        for _, text in ipairs(notified) do
            if text:find('NewPlayer', 1, true) and text:find('joined', 1, true) then
                found_join = true
            end
        end
        assert.is_true(found_join, 'join notification missing')

        TriggerEvent('vMenu:PlayerJoinQuit', 'OldPlayer', 'Disconnected.')
        local found_quit = false
        for _, text in ipairs(notified) do
            if text:find('OldPlayer', 1, true) and text:find('left', 1, true) then
                found_quit = true
            end
        end
        assert.is_true(found_quit, 'quit notification missing')
    end)

    it('skips join/quit notifications when the setting is off', function()
        grant({ MSJoinQuitNotifs = true })
        require('client.functions_controller.main')
        State.config_options_setup_complete = true
        State.menus.misc_settings = { JoinQuitNotifications = false }

        local notified = {}
        cfx:stub_native('AddTextComponentSubstringPlayerName', function(text)
            notified[#notified + 1] = text
        end)
        TriggerEvent('vMenu:PlayerJoinQuit', 'NewPlayer', nil)
        assert.equal(0, #notified)
    end)
end)
