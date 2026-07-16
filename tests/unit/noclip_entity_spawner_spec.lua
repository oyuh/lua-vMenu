-- M9 part 1 specs: noclip toggling, the entity spawner placement flow, and
-- the MultiplayerPedData record shape (against the golden fixture).

local CfxMock = require('tests.mocks.cfx')

local function read_fixture(name)
    local file = assert(io.open('tests/fixtures/' .. name, 'r'))
    local contents = file:read('a')
    file:close()
    return contents
end

describe('noclip + entity spawner + mp ped data', function()
    local cfx

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
            'client.noclip',
            'client.entity_spawner',
            'client.mp_ped_data',
            'menu.controller',
            'menu.menu',
            'menu.items',
            'menu.sounds',
        }) do
            package.loaded[name] = nil
        end
    end

    local function last_call(native_name)
        local calls = cfx:calls(native_name)
        local call = calls[#calls]
        return { table.unpack(call, 1, call.n) }
    end

    before_each(function()
        cfx = CfxMock.new():install()
        cfx:add_player('0', { name = 'LocalPlayer' })
        cfx.game_timer = 100000
        cfx.entity_coords[3000] = { x = 0.0, y = 0.0, z = 0.0 } -- CreateObject handle
        cfx.entity_coords[1500] = { x = 0.0, y = 0.0, z = 0.0 } -- CreatePed handle
        fresh_modules()
    end)

    after_each(function()
        cfx:uninstall()
    end)

    describe('noclip', function()
        it('toggles and starts the movement thread once', function()
            local NoClip = require('client.noclip')
            assert.is_false(NoClip.is_noclip_active())

            NoClip.set_noclip_active(true)
            assert.is_true(NoClip.is_noclip_active())
            local threads_after_first = #cfx.threads

            -- re-activating while active must not spawn a second thread
            NoClip.set_noclip_active(true)
            assert.equal(threads_after_first, #cfx.threads)

            NoClip.set_noclip_active(false)
            assert.is_false(NoClip.is_noclip_active())
        end)
    end)

    describe('entity spawner', function()
        local function build_menu()
            local EntitySpawner = require('client.entity_spawner')
            local Menu = require('menu.menu')
            local menu = Menu.new('Test', 'Entity Spawner')
            EntitySpawner.fill_menu(menu)
            return EntitySpawner, menu
        end

        local function menu_item(menu, text)
            for _, item in ipairs(menu:GetMenuItems()) do
                if item.Text == text then
                    return item
                end
            end
            return nil
        end

        local function type_model_name(name)
            cfx:stub_native('UpdateOnscreenKeyboard', function()
                return 1
            end)
            cfx:stub_native('GetOnscreenKeyboardResult', function()
                return name
            end)
            -- the mock defaults this to true for the vehicle-spawn specs
            cfx:stub_native('IsModelAVehicle', function()
                return false
            end)
        end

        it('fills the menu with the four placement actions', function()
            local _, menu = build_menu()
            assert.equal(4, menu:Size())
            assert.is_not_nil(menu_item(menu, 'Spawn New Entity'))
            assert.is_not_nil(menu_item(menu, 'Confirm Entity Position'))
            assert.is_not_nil(menu_item(menu, 'Confirm Entity Position And Duplicate'))
            assert.is_not_nil(menu_item(menu, 'Cancel'))
        end)

        it('spawns an object for a non-ped, non-vehicle model', function()
            local EntitySpawner, menu = build_menu()
            type_model_name('prop_bench_01a')

            menu.OnItemSelect(menu, menu_item(menu, 'Spawn New Entity'), 0)

            assert.equal(1, #cfx:calls('CreateObject'))
            assert.is_true(EntitySpawner.Active)
            assert.equal(3000, EntitySpawner.CurrentEntity)
            -- mission entity so it doesn't despawn
            assert.same({ 3000, true, true }, last_call('SetEntityAsMissionEntity'))
        end)

        it('spawns a ped when the model is a ped', function()
            local EntitySpawner, menu = build_menu()
            type_model_name('a_m_y_hipster_01')
            cfx:stub_native('IsModelAPed', function()
                return true
            end)

            menu.OnItemSelect(menu, menu_item(menu, 'Spawn New Entity'), 0)

            local create = last_call('CreatePed')
            assert.equal(4, create[1])
            assert.equal(1500, EntitySpawner.CurrentEntity)
        end)

        it('refuses a second placement while one is active', function()
            local EntitySpawner, menu = build_menu()
            type_model_name('prop_bench_01a')

            menu.OnItemSelect(menu, menu_item(menu, 'Spawn New Entity'), 0)
            menu.OnItemSelect(menu, menu_item(menu, 'Spawn New Entity'), 0)

            assert.equal(1, #cfx:calls('CreateObject'))
            assert.is_true(EntitySpawner.Active)
        end)

        it('confirm ends the placement and keeps the entity', function()
            local EntitySpawner, menu = build_menu()
            type_model_name('prop_bench_01a')
            menu.OnItemSelect(menu, menu_item(menu, 'Spawn New Entity'), 0)

            menu.OnItemSelect(menu, menu_item(menu, 'Confirm Entity Position'), 1)

            assert.is_false(EntitySpawner.Active)
            assert.is_nil(EntitySpawner.CurrentEntity)
            assert.equal(0, #cfx:calls('DeleteEntity'))
        end)

        it('cancel deletes the entity', function()
            local _, menu = build_menu()
            type_model_name('prop_bench_01a')
            menu.OnItemSelect(menu, menu_item(menu, 'Spawn New Entity'), 0)

            menu.OnItemSelect(menu, menu_item(menu, 'Cancel'), 3)

            assert.same({ 3000 }, last_call('DeleteEntity'))
            -- Entity.Delete() unmarks the mission entity first
            assert.same({ 3000, false, true }, last_call('SetEntityAsMissionEntity'))
        end)

        it('rejects invalid models', function()
            local EntitySpawner, menu = build_menu()
            type_model_name('not_a_real_model')
            cfx:stub_native('IsModelValid', function()
                return false
            end)

            menu.OnItemSelect(menu, menu_item(menu, 'Spawn New Entity'), 0)

            assert.equal(0, #cfx:calls('CreateObject'))
            assert.is_false(EntitySpawner.Active)
            assert.is_nil(EntitySpawner.CurrentEntity)
        end)
    end)

    describe('mp ped data record', function()
        it('matches the golden fixture shape (incl. the PedTatttoos typo)', function()
            local Json = require('shared.json_compat')
            local MpPedData = require('client.mp_ped_data')
            local fixture = Json.decode(read_fixture('mp_ped_data.json'))

            local record = MpPedData.new()

            -- the load-bearing triple-t typo
            assert.is_table(record.PedTatttoos)
            assert.is_nil(record.PedTattoos)

            for zone in pairs(fixture.PedTatttoos) do
                assert.is_table(record.PedTatttoos[zone], 'missing tattoo zone: ' .. zone)
            end
            for field in pairs(fixture.PedHeadBlendData) do
                assert.is_not_nil(record.PedHeadBlendData[field], 'missing head blend field: ' .. field)
            end
            -- appearance fields: every non-KeyValuePair fixture field exists
            for field, value in pairs(fixture.PedAppearance) do
                if type(value) ~= 'table' then
                    assert.is_not_nil(record.PedAppearance[field], 'missing appearance field: ' .. field)
                end
            end
            assert.is_table(record.DrawableVariations.clothes)
            assert.is_table(record.PropVariations.props)
            assert.is_table(record.FaceShapeFeatures.features)
            assert.is_table(record.PedFacePaints)
        end)

        it('builds KeyValuePair-shaped entries', function()
            local MpPedData = require('client.mp_ped_data')
            assert.same(
                { Key = 'mpbeach_overlays', Value = 'FM_Hair_Fuzz' },
                MpPedData.kvp('mpbeach_overlays', 'FM_Hair_Fuzz')
            )
        end)
    end)
end)
