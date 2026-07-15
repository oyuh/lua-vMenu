-- StorageManager port specs (client/storage.lua) against the KVP save
-- contract (docs/contracts/kvp-saves.md) and the golden fixtures.

local CfxMock = require('tests.mocks.cfx')

local function read_fixture(name)
    local file = assert(io.open('tests/fixtures/' .. name, 'r'))
    local contents = file:read('a')
    file:close()
    return contents
end

describe('storage manager', function()
    local cfx, Storage

    before_each(function()
        cfx = CfxMock.new():install()
        for _, name in ipairs({ 'shared.json_compat', 'shared.util', 'client.storage' }) do
            package.loaded[name] = nil
        end
        Storage = require('client.storage')
    end)

    after_each(function()
        cfx:uninstall()
    end)

    describe('json data', function()
        it('saves, reads back, and refuses silent overwrites', function()
            assert.is_true(Storage.save_json_data('vmenu_temp', '{"a":1}', false))
            assert.equal('{"a":1}', Storage.get_json_data('vmenu_temp'))

            assert.is_false(Storage.save_json_data('vmenu_temp', '{"a":2}', false))
            assert.equal('{"a":1}', Storage.get_json_data('vmenu_temp'))

            assert.is_true(Storage.save_json_data('vmenu_temp', '{"a":2}', true))
            assert.equal('{"a":2}', Storage.get_json_data('vmenu_temp'))
        end)

        it('rejects empty names and empty data', function()
            assert.is_false(Storage.save_json_data(nil, '{}', true))
            assert.is_false(Storage.save_json_data('', '{}', true))
            assert.is_false(Storage.save_json_data('x', nil, true))
            assert.is_nil(Storage.get_json_data(nil))
            assert.is_nil(Storage.get_json_data('missing'))
        end)
    end)

    describe('vehicles', function()
        it('requires a real name after the veh_ prefix (length > 4)', function()
            assert.is_false(Storage.save_vehicle_info('veh_', { model = 123 }, true))
            assert.is_true(Storage.save_vehicle_info('veh_X', { model = 123 }, true))
        end)

        it('round-trips the C# golden VehicleInfo fixture', function()
            cfx.kvp['veh_Adder'] = read_fixture('vehicle_info.json')
            local info = Storage.get_saved_vehicle_info('veh_Adder')
            assert.is_table(info)
            assert.is_table(info.colors)
            assert.is_number(info.model)
            -- Dictionary<int,...> stays string-keyed (json contract)
            for key in pairs(info.mods) do
                assert.is_string(key)
            end
        end)
    end)

    describe('peds', function()
        it('lists saved peds by full kvp name', function()
            cfx.kvp['ped_Cool Ped'] = read_fixture('ped_info.json')
            cfx.kvp['veh_NotAPed'] = '{}'
            local peds = Storage.get_saved_peds()
            assert.is_table(peds['ped_Cool Ped'])
            assert.is_nil(peds['veh_NotAPed'])
        end)
    end)

    describe('mp characters', function()
        it('normalizes names with or without the mp_ped_ prefix', function()
            cfx.kvp['mp_ped_Mine'] = read_fixture('mp_ped_data.json')
            local by_short = Storage.get_saved_mp_character_data('Mine')
            local by_full = Storage.get_saved_mp_character_data('mp_ped_Mine')
            assert.equal(by_short.SaveName, by_full.SaveName)
            -- the load-bearing triple-t typo must survive the round trip
            assert.is_table(by_full.PedTatttoos)
        end)

        it('returns an empty record for missing or corrupt saves', function()
            assert.same({}, Storage.get_saved_mp_character_data('nope'))
            cfx.kvp['mp_ped_bad'] = '{ not json'
            assert.same({}, Storage.get_saved_mp_character_data('bad'))
        end)

        it('sorts the saved list case-insensitively by SaveName', function()
            cfx.kvp['mp_ped_b'] = '{"SaveName":"mp_ped_bravo"}'
            cfx.kvp['mp_ped_A'] = '{"SaveName":"mp_ped_Alpha"}'
            cfx.kvp['mp_ped_c'] = '{"SaveName":"mp_ped_Charlie"}'
            local peds = Storage.get_saved_mp_peds()
            assert.equal(3, #peds)
            assert.equal('mp_ped_Alpha', peds[1].SaveName)
            assert.equal('mp_ped_bravo', peds[2].SaveName)
            assert.equal('mp_ped_Charlie', peds[3].SaveName)
        end)
    end)

    describe('categories', function()
        it('normalizes category record prefixes', function()
            cfx.kvp['saved_veh_category_Cars'] = read_fixture('category.json')
            local record = Storage.get_saved_vehicle_category_data('Cars')
            assert.is_string(record.Name)
            assert.same({}, Storage.get_saved_mp_character_category_data('Missing'))
        end)
    end)
end)
