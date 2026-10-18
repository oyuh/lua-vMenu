-- Specs for the spawn limit in client/menus/vehicles/spawning.lua: server owners
-- set how many vehicles each tier may spawn per window, and an off-by-one here
-- either blocks honest players or lets spawn spam through.

local CfxMock = require('tests.mocks.cfx')

local function reset_modules()
    for name in pairs(package.loaded) do
        if name:match('^shared%.') or name:match('^client%.') or name:match('^menu%.') then
            package.loaded[name] = nil
        end
    end
end

describe('vehicle spawn limit', function()
    local cfx, Spawning, Permissions

    before_each(function()
        cfx = CfxMock.new({ resource_name = 'vMenu.Enhanced' }):install()
        reset_modules()
        Permissions = require('client.permissions')
        Spawning = require('client.menus.vehicles.spawning')
        Permissions.apply({})
    end)

    after_each(function()
        cfx:uninstall()
    end)

    local function spawns_allowed(count)
        local allowed = 0
        for _ = 1, count do
            if Spawning.take_spawn() then
                allowed = allowed + 1
            end
        end
        return allowed
    end

    it('lets tier 1 spawn five a minute, then frees a slot once the oldest ages out', function()
        cfx.game_timer = 1000
        assert.are.equal(5, spawns_allowed(6))

        cfx.game_timer = 1000 + 59999
        assert.is_false(Spawning.take_spawn())
        cfx.game_timer = 1000 + 60000
        assert.is_true(Spawning.take_spawn())
    end)

    it('uses the highest tier the player holds, where 0 means no limit', function()
        Permissions.apply({ 'vMenu.Enhanced.Menus.VehicleSpawner.SpawnLimitTier2' })
        assert.are.equal(15, spawns_allowed(16))

        Permissions.apply({
            'vMenu.Enhanced.Menus.VehicleSpawner.SpawnLimitTier2',
            'vMenu.Enhanced.Menus.VehicleSpawner.SpawnLimitTier3',
        })
        assert.are.equal(30, spawns_allowed(30))
    end)
end)
