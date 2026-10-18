-- Specs for client/menus/weapons/loadouts.lua and server/weapons.lua. Saved
-- loadouts are KVP saves shared with upstream's C# build, and the component
-- list is a file server owners edit by hand.

local CfxMock = require('tests.mocks.cfx')
local dkjson = require('dkjson')

local function reset_modules()
    for name in pairs(package.loaded) do
        if name:match('^shared%.') or name:match('^server%.') or name:match('^client%.') or name:match('^menu%.') then
            package.loaded[name] = nil
        end
    end
end

describe('saved weapon loadouts', function()
    local cfx, Loadouts, UserDefaults

    before_each(function()
        cfx = CfxMock.new({ resource_name = 'vMenu.Enhanced' }):install()
        reset_modules()
        Loadouts = require('client.menus.weapons.loadouts')
        UserDefaults = require('client.user_defaults')
    end)

    after_each(function()
        cfx:uninstall()
    end)

    it("reads a loadout upstream's build saved", function()
        cfx.kvp.vmenu_weaponloadout_Range = '{"key":"vmenu_weaponloadout_Range","value":{"name":"Range",'
            .. '"weapons":[{"spawnName":"weapon_pistol","ammo":120,"tint":2,'
            .. '"components":["COMPONENT_AT_PI_SUPP_02"]}]},"type":"json","version":1}'
        local all = Loadouts.all()
        assert.are.equal(1, #all)
        assert.same({
            name = 'Range',
            weapons = {
                { spawnName = 'weapon_pistol', ammo = 120, tint = 2, components = { 'COMPONENT_AT_PI_SUPP_02' } },
            },
        }, all[1])
    end)

    it('saves in the same shape and keeps the default through a rename', function()
        local loadout = {
            name = 'Range',
            weapons = { { spawnName = 'weapon_pistol', ammo = 120, tint = 0, components = {} } },
        }
        assert.are.equal(Loadouts.SAVED, Loadouts.save(loadout, false))
        assert.are.equal(Loadouts.NAME_TAKEN, Loadouts.save(loadout, false))
        local envelope = dkjson.decode(cfx.kvp.vmenu_weaponloadout_Range)
        assert.are.equal('json', envelope.type)
        assert.same({ 'weapon_pistol' }, { envelope.value.weapons[1].spawnName })

        Loadouts.set_default('Range')
        assert.is_true(Loadouts.rename(loadout, 'Practice'))
        assert.is_nil(cfx.kvp.vmenu_weaponloadout_Range)
        assert.are.equal('Practice', UserDefaults.get('weaponLoadoutDefaultName'))
    end)
end)

describe('weapon components file', function()
    local cfx

    before_each(function()
        cfx = CfxMock.new({ resource_name = 'vMenu.Enhanced', is_server = true }):install()
        reset_modules()
    end)

    after_each(function()
        cfx:uninstall()
    end)

    it('keeps file order, upper-cases names and takes the first of a duplicate', function()
        cfx:set_resource_file(
            'config/weapon-components.json',
            '{\n  // comment\n  "component_b": "Second",\n  "COMPONENT_A": " ",\n'
                .. '  "Component_B": "Dupe",\n  "BAD": 5\n}'
        )
        cfx:add_player(2)
        require('server.permissions').init()
        require('server.weapons').init()
        cfx:trigger_from(2, 'vMenu.Enhanced:Weapons:Request')
        local reply = cfx.triggered[#cfx.triggered]
        assert.are.equal('vMenu.Enhanced:Weapons:Set', reply.name)
        assert.same({
            { spawnName = 'COMPONENT_B', label = 'Second' },
            { spawnName = 'COMPONENT_A', label = 'COMPONENT_A' },
        }, dkjson.decode(reply.args[2]))
    end)
end)
