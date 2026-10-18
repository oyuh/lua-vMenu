-- Specs for client/menus/players/toggles.lua and protection.lua: a player
-- feature is on only while the saved choice and the permission agree, and the
-- ped flags several features share stay set while any of them wants them.

local CfxMock = require('tests.mocks.cfx')

local function reset_modules()
    for name in pairs(package.loaded) do
        if name:match('^shared%.') or name:match('^client%.') or name:match('^menu%.') then
            package.loaded[name] = nil
        end
    end
end

local PED = 900

describe('player toggles', function()
    local cfx, Permissions, Toggles

    before_each(function()
        cfx = CfxMock.new({ resource_name = 'vMenu.Enhanced' }):install()
        cfx.entity_coords[PED] = { x = 0.0, y = 0.0, z = 0.0 }
        reset_modules()
        Permissions = require('client.permissions')
        Toggles = require('client.menus.players.toggles')
        Permissions.apply({})
        Toggles.init()
    end)

    after_each(function()
        cfx:uninstall()
    end)

    local function last(native)
        local calls = cfx:calls(native)
        return calls[#calls]
    end

    it('switches god mode off when the permission goes, and back on when it returns', function()
        Permissions.apply({ 'vMenu.Enhanced.Menus.PlayerOptions.Godmode' })
        Toggles.god_mode:set_enabled(true)
        assert.is_true(last('SetPlayerInvincibleKeepRagdollEnabled')[2])

        Permissions.apply({})
        assert.is_false(last('SetPlayerInvincibleKeepRagdollEnabled')[2])

        Permissions.apply({ 'vMenu.Enhanced.Menus.PlayerOptions.Godmode' })
        assert.is_true(last('SetPlayerInvincibleKeepRagdollEnabled')[2])
    end)

    it('refuses to switch a feature on without its permission', function()
        Toggles.invisible:set_enabled(true)
        assert.is_false(Toggles.invisible:enabled())
        Permissions.apply({ 'vMenu.Enhanced.Menus.PlayerOptions.Invisible' })
        assert.is_false(Toggles.invisible:enabled())
    end)

    it('keeps god mode protecting the player after stay in vehicle goes off', function()
        Permissions.apply({ 'vMenu.Enhanced.Menus.PlayerOptions.All' })
        Toggles.god_mode:set_enabled(true)
        Toggles.stay_in_vehicle:set_enabled(true)
        Toggles.stay_in_vehicle:set_enabled(false)

        assert.same({ PED, false, n = 2 }, last('SetPedCanBeDraggedOut'))
        assert.same({ PED, false, n = 2 }, last('SetPedCanBeShotInVehicle'))
    end)
end)
