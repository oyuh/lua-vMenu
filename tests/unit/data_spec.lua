-- Integrity specs for the generated data tables (client/data/*.lua,
-- produced by scripts/gen-data.ps1) and their runtime consumers.

local CfxMock = require('tests.mocks.cfx')

describe('generated data', function()
    local cfx

    local DATA_MODULES = {
        'client.data.vehicle_data',
        'client.data.weapons_data',
        'client.data.ped_models',
        'client.data.ped_scenarios',
        'client.data.time_cycles',
        'client.data.blip_info',
    }

    local function fresh(name)
        package.loaded[name] = nil
        return require(name)
    end

    before_each(function()
        cfx = CfxMock.new():install()
        for _, name in ipairs(DATA_MODULES) do
            package.loaded[name] = nil
        end
    end)

    after_each(function()
        cfx:uninstall()
    end)

    describe('vehicle data', function()
        it('has all 23 vehicle categories, each non-empty', function()
            local Data = fresh('client.data.vehicle_data')
            assert.equal(23, #Data.VehicleClasses_order)
            local total = 0
            for _, class_label in ipairs(Data.VehicleClasses_order) do
                local list = Data.VehicleClasses[class_label]
                assert.is_table(list)
                assert.is_true(#list > 0, 'empty class: ' .. class_label)
                total = total + #list
            end
            assert.equal(total, #Data.GetAllVehicles())
        end)

        it('keeps the color ids and labels from upstream', function()
            local Data = fresh('client.data.vehicle_data')
            assert.same({ id = 0, label = 'BLACK' }, Data.ClassicColors[1])
            assert.is_true(#Data.ClassicColors > 50)
            assert.is_true(#Data.ChameleonColors > 0)
            -- chameleon labels got their text entries registered at load
            assert.is_true(#cfx:calls('AddTextEntry') >= 16)
        end)

        it('has the 13 neon light color triples', function()
            local Data = fresh('client.data.vehicle_data')
            assert.same({ 255, 255, 255 }, Data.NeonLightColors[1])
            for _, rgb in ipairs(Data.NeonLightColors) do
                assert.equal(3, #rgb)
            end
        end)
    end)

    describe('weapons data', function()
        it('gives every weapon a name, description order, and a valid permission', function()
            local Data = fresh('client.data.weapons_data')
            local Permissions = require('shared.permissions')
            local known = {}
            for _, name in ipairs(Permissions.list) do
                known[name] = true
            end

            assert.is_true(#Data.weapon_names_order > 90)
            for _, spawn_name in ipairs(Data.weapon_names_order) do
                assert.is_string(Data.weapon_names[spawn_name])
                local perm = Data.weapon_permissions[spawn_name]
                assert.is_string(perm, 'missing permission for ' .. spawn_name)
                assert.is_true(known[perm] == true, 'unknown permission ' .. tostring(perm))
            end
        end)

        it('has the base and mk2 tint tables in order', function()
            local Data = fresh('client.data.weapons_data')
            assert.equal(8, #Data.weapon_tints_order)
            assert.equal(0, Data.weapon_tints.Black)
            assert.equal('Black', Data.weapon_tints_order[1])
            assert.is_true(#Data.weapon_tints_mk2_order > 8)
            assert.equal(0, Data.weapon_tints_mk2['Classic Black'])
        end)

        it('has component display names for every component key', function()
            local Data = fresh('client.data.weapons_data')
            assert.is_true(#Data.weapon_component_names_order > 300)
            for _, key in ipairs(Data.weapon_component_names_order) do
                assert.is_string(Data.weapon_component_names[key])
            end
        end)
    end)

    describe('ped and world data', function()
        it('animal model hashes line up with their names', function()
            local Data = fresh('client.data.ped_models')
            assert.is_true(#Data.animals > 40)
            assert.equal(#Data.animals, #Data.animal_hashes)
            assert.equal(GetHashKey(Data.animals[1]), Data.animal_hashes[1])
        end)

        it('exposes scenarios with readable names', function()
            local Data = fresh('client.data.ped_scenarios')
            assert.is_true(#Data.position_based_scenarios > 10)
            assert.is_true(#Data.scenario_names_order > 50)
            assert.equal('WORLD_HUMAN_AA_COFFEE', Data.scenario_names[Data.scenario_names_order[1]])
            assert.is_true(#Data.scenarios > 50)
        end)

        it('exposes the timecycle modifier list', function()
            local Data = fresh('client.data.time_cycles')
            assert.is_true(#Data.timecycles > 100)
            assert.equal('AmbientPUSH', Data.timecycles[1])
        end)

        it('resolves vehicle blip sprites with model-type fallbacks', function()
            local Data = fresh('client.data.blip_info')
            assert.equal(56, Data.vehicle_sprites[GetHashKey('taxi')])

            -- unknown model → default sprite
            assert.equal(225, Data.get_blip_sprite_for_vehicle(1))

            cfx:stub_native('IsThisModelABike', function()
                return true
            end)
            assert.equal(348, Data.get_blip_sprite_for_vehicle(1))
        end)
    end)
end)

describe('weapons runtime', function()
    local cfx, Weapons, Data

    before_each(function()
        cfx = CfxMock.new():install()
        for _, name in ipairs({
            'shared.json_compat',
            'shared.util',
            'client.data.weapons_data',
            'client.weapons',
        }) do
            package.loaded[name] = nil
        end
        Weapons = require('client.weapons')
        Data = require('client.data.weapons_data')
    end)

    after_each(function()
        cfx:uninstall()
    end)

    it('builds the weapon list without weapon_unarmed', function()
        local list = Weapons.weapon_list()
        assert.equal(#Data.weapon_names_order - 1, #list)
        for _, weapon in ipairs(list) do
            assert.not_equal('weapon_unarmed', weapon.spawn_name)
            assert.is_string(weapon.perm)
            assert.equal(GetHashKey(weapon.spawn_name), weapon.hash)
        end
    end)

    it('maps accepted components per weapon', function()
        -- pretend every weapon accepts exactly the pistol clip component
        cfx:stub_native('DoesWeaponTakeWeaponComponent', function(_hash, component_hash)
            return component_hash == GetHashKey('COMPONENT_PISTOL_CLIP_01')
        end)
        Weapons._reset()
        local list = Weapons.weapon_list()
        local component_name = Data.weapon_component_names.COMPONENT_PISTOL_CLIP_01
        assert.equal(GetHashKey('COMPONENT_PISTOL_CLIP_01'), list[1].components[component_name])
    end)

    it('merges addon weapon components from addons.json', function()
        cfx:set_resource_file('config/addons.json', '{ "weapon_components": ["COMPONENT_CUSTOM_SCOPE"] }')
        local components = Weapons.get_weapon_components()
        assert.equal('COMPONENT_CUSTOM_SCOPE', components.COMPONENT_CUSTOM_SCOPE)
        assert.is_string(components.COMPONENT_PISTOL_CLIP_01)
    end)

    it('lists addon weapons behind WPSpawn', function()
        cfx:set_resource_file('config/addons.json', '{ "weapons": ["weapon_mycustom", "weapon_unarmed"] }')
        local list = Weapons.addon_weapon_list()
        assert.equal(1, #list)
        assert.equal('weapon_mycustom', list[1].spawn_name)
        assert.equal('WPSpawn', list[1].perm)
    end)

    it('reads max ammo through the out-param native', function()
        assert.equal(250, Weapons.get_max_ammo(123))
    end)
end)

describe('tattoos runtime', function()
    local cfx, Tattoos, State

    before_each(function()
        cfx = CfxMock.new():install()
        for _, name in ipairs({ 'shared.json_compat', 'client.state', 'client.tattoos' }) do
            package.loaded[name] = nil
        end
        State = require('client.state')
        Tattoos = require('client.tattoos')
    end)

    after_each(function()
        cfx:uninstall()
    end)

    it('sorts overlays into gendered zone collections', function()
        cfx:set_resource_file(
            'client/data/overlays.json',
            [=[[
                { "gender": 0, "name": "tat_m", "collectionName": "c", "zoneId": 0, "type": "TYPE_TATTOO" },
                { "gender": 1, "name": "tat_f", "collectionName": "c", "zoneId": 1, "type": "TYPE_TATTOO" },
                { "gender": 2, "name": "badge_both", "collectionName": "c", "zoneId": 6, "type": "TYPE_BADGE" },
                { "gender": 2, "name": "hair_style", "collectionName": "c", "zoneId": 6, "type": "TYPE_TATTOO" },
                { "gender": 0, "name": "", "collectionName": "c", "zoneId": 0, "type": "TYPE_TATTOO" }
            ]]=]
        )
        State.tattoos = { { gender = 2, name = 'addon_tat', collectionName = 'x', zoneId = 0, type = 'TYPE_TATTOO' } }

        Tattoos.generate()

        assert.equal('tat_m', Tattoos.male.TORSO[1].name)
        assert.same({}, Tattoos.female.TORSO)
        assert.equal('tat_f', Tattoos.female.HEAD[1].name)
        assert.equal('badge_both', Tattoos.male.BADGES[1].name)
        assert.equal('badge_both', Tattoos.female.BADGES[1].name)
        assert.equal('hair_style', Tattoos.male.HAIR[1].name)
        assert.equal('addon_tat', Tattoos.male.ADDONS[1].name)
        assert.equal('addon_tat', Tattoos.female.ADDONS[1].name)
    end)

    it('generates only once', function()
        cfx:set_resource_file('client/data/overlays.json', '[]')
        Tattoos.generate()
        cfx:set_resource_file(
            'client/data/overlays.json',
            '[{ "gender": 0, "name": "late", "collectionName": "c", "zoneId": 0, "type": "TYPE_TATTOO" }]'
        )
        Tattoos.generate()
        assert.same({}, Tattoos.male.TORSO)
    end)

    it('parses the real shipped overlays.json', function()
        local file = assert(io.open('client/data/overlays.json', 'r'))
        cfx:set_resource_file('client/data/overlays.json', file:read('a'))
        file:close()

        Tattoos.generate()

        local male_total = 0
        for _, list in pairs(Tattoos.male) do
            male_total = male_total + #list
        end
        assert.is_true(male_total > 1000)
        assert.is_true(#Tattoos.female.TORSO > 100)
    end)
end)
