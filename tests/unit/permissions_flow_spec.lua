-- End-to-end permission flow specs: server-side ACE collection through the
-- mock event bus into client-side resolution. Mirrors PermissionsManager.cs
-- server/client regions. Contract: docs/contracts/permissions.md

local CfxMock = require('tests.mocks.cfx')

describe('permission sync flow', function()
    local cfx, Permissions, Json

    before_each(function()
        cfx = CfxMock.new():install()
        -- Fresh module per test: client grant/memo state must not leak.
        package.loaded['shared.permissions'] = nil
        package.loaded['shared.config'] = nil
        package.loaded['shared.json_compat'] = nil
        Permissions = require('shared.permissions')
        Json = require('shared.json_compat')
    end)

    after_each(function()
        cfx:uninstall()
    end)

    describe('server: is_allowed_server', function()
        it('denies unknown players', function()
            assert.is_false(Permissions.is_allowed_server('OPKick', '1'))
        end)

        it('grants via the exact ace', function()
            cfx:add_player('1')
            cfx:grant_ace('1', 'vMenu.OnlinePlayers.Kick')
            assert.is_true(Permissions.is_allowed_server('OPKick', '1'))
        end)

        it('grants via the category All ace', function()
            cfx:add_player('1')
            cfx:grant_ace('1', 'vMenu.OnlinePlayers.All')
            assert.is_true(Permissions.is_allowed_server('OPKick', '1'))
        end)

        it('grants via vMenu.Everything', function()
            cfx:add_player('1')
            cfx:grant_ace('1', 'vMenu.Everything')
            assert.is_true(Permissions.is_allowed_server('OPKick', '1'))
        end)

        it('does not grant Menu members via the All ace (upstream quirk)', function()
            cfx:add_player('1')
            cfx:grant_ace('1', 'vMenu.OnlinePlayers.All')
            assert.is_false(Permissions.is_allowed_server('OPMenu', '1'))
        end)
    end)

    describe('server: collect_for_player', function()
        it('with permissions disabled grants everything except the denylist (omitted, not false)', function()
            cfx:set_convar('vmenu_use_permissions', 'false')
            cfx:add_player('1')
            local perms = Permissions.collect_for_player('1')
            assert.is_true(perms.POGod)
            assert.is_true(perms.NoClip)
            assert.is_true(perms.OPMenu)
            assert.is_nil(perms.Everything)
            assert.is_nil(perms.OPKick)
            assert.is_nil(perms.OPPermBan)
        end)

        it('with permissions enabled reflects ace checks for all 297 permissions', function()
            cfx:set_convar('vmenu_use_permissions', 'true')
            cfx:add_player('1')
            cfx:grant_ace('1', 'vMenu.PlayerOptions.All')
            local perms = Permissions.collect_for_player('1')
            local count = 0
            for _ in pairs(perms) do
                count = count + 1
            end
            assert.equal(297, count)
            assert.is_true(perms.POGod)
            assert.is_true(perms.POAll)
            assert.is_false(perms.POMenu)
            assert.is_false(perms.OPKick)
            assert.is_false(perms.Everything)
        end)
    end)

    describe('client: is_allowed', function()
        it('denies everything before permissions arrive, unless check_anyway', function()
            assert.is_false(Permissions.is_allowed('POGod'))
            assert.is_false(Permissions.is_allowed('POGod', true))
        end)

        it('resolves direct grants and parent implication after sync', function()
            Permissions.set_from_json(Json.encode({ OPAll = true }))
            assert.is_true(Permissions.is_allowed('OPKick'))
            assert.is_true(Permissions.is_allowed('OPAll'))
            assert.is_false(Permissions.is_allowed('OPMenu'))
            assert.is_false(Permissions.is_allowed('POGod'))
        end)

        it('enforces the staff-only gate', function()
            cfx:set_convar('vmenu_menu_staff_only', 'true')
            Permissions.set_from_json(Json.encode({ POGod = true }))
            assert.is_false(Permissions.is_allowed('POGod'))

            Permissions.set_from_json(Json.encode({ POGod = true, Staff = true }))
            assert.is_true(Permissions.is_allowed('POGod'))
        end)

        it('memoizes positive answers (upstream static cache quirk)', function()
            Permissions.set_from_json(Json.encode({ OPAll = true }))
            assert.is_true(Permissions.is_allowed('OPKick'))
            -- Re-push without the grant: positive memo still short-circuits.
            Permissions.set_from_json(Json.encode({}))
            assert.is_true(Permissions.is_allowed('OPKick'))
        end)
    end)

    describe('client: supplementary fallback', function()
        it('falls back to the main All permission when whitelist perms are not granted', function()
            Permissions.set_from_json(Json.encode({ VSAll = true }))
            assert.is_true(Permissions.is_supplementary_allowed('VWadder'))
            assert.is_false(Permissions.is_supplementary_allowed('PWsome_ped'))
        end)

        it('uses supplementary grants when present', function()
            Permissions.set_from_json(Json.encode({}))
            Permissions.set_supplementary_from_json(Json.encode({ VWAll = true }))
            assert.is_true(Permissions.is_supplementary_allowed('VWadder'))
        end)
    end)

    it('round-trips server collection to client resolution over the event bus', function()
        cfx:set_convar('vmenu_use_permissions', 'true')
        cfx:add_player('42')
        cfx:grant_ace('42', 'vMenu.OnlinePlayers.All')
        cfx:grant_ace('42', 'vMenu.NoClip')

        -- Client registers its handler (as client/events.lua will in M5).
        RegisterNetEvent('vMenu:SetPermissions', function(payload)
            Permissions.set_from_json(payload)
        end)

        -- Server pushes on playerJoining (MainServer.OnPlayerJoining).
        TriggerClientEvent('vMenu:SetPermissions', 42, Json.encode(Permissions.collect_for_player('42')))

        assert.is_true(Permissions.are_setup)
        assert.is_true(Permissions.is_allowed('OPKick'))
        assert.is_true(Permissions.is_allowed('NoClip'))
        assert.is_false(Permissions.is_allowed('POGod'))
        assert.equal('to_client', cfx.triggered[1].direction)
        assert.equal('vMenu:SetPermissions', cfx.triggered[1].name)
    end)
end)

describe('config locations loader', function()
    local cfx, Config

    before_each(function()
        cfx = CfxMock.new():install()
        package.loaded['shared.config'] = nil
        package.loaded['shared.json_compat'] = nil
        Config = require('shared.config')
    end)

    after_each(function()
        cfx:uninstall()
    end)

    it('returns empty lists plus an error for a missing file', function()
        local locations, err = Config.get_locations()
        assert.same({ teleports = {}, blips = {} }, locations)
        assert.is_string(err)
    end)

    it('returns empty lists plus an error for corrupt json', function()
        cfx:set_resource_file('config/locations.json', '{ not valid json')
        local locations, err = Config.get_locations()
        assert.same({ teleports = {}, blips = {} }, locations)
        assert.is_string(err)
    end)

    it('parses the upstream locations.json shape', function()
        cfx:set_resource_file(
            'config/locations.json',
            [[{
                "teleports": [
                    { "name": "Legion Square", "coordinates": { "x": 215.8, "y": -810.1, "z": 30.7 }, "heading": 158.0 }
                ],
                "blips": [
                    { "name": "Legion Square", "coordinates": { "x": 215.8, "y": -810.1, "z": 30.7 },
                      "spriteID": 280, "color": 0 }
                ]
            }]]
        )
        local locations, err = Config.get_locations()
        assert.is_nil(err)
        assert.equal(1, #locations.teleports)
        assert.equal('Legion Square', locations.teleports[1].name)
        assert.equal(158.0, locations.teleports[1].heading)
        assert.equal(280, locations.blips[1].spriteID)

        local teleports = Config.get_teleport_locations()
        assert.equal(1, #teleports)
    end)
end)
