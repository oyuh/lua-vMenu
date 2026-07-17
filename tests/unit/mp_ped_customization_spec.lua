-- MpPedCustomization specs: the golden-fixture spawn round-trip (the
-- pixel-identical contract), the creator save shape, and the saved
-- characters category/manage flows.

local CfxMock = require('tests.mocks.cfx')

local function read_fixture(name)
    local file = assert(io.open('tests/fixtures/' .. name, 'r'))
    local contents = file:read('a')
    file:close()
    return contents
end

describe('mp ped customization menu', function()
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
            'client.mp_ped_data',
            'client.tattoos',
            'client.storage',
            'client.user_defaults',
            'client.weapons',
            'client.menus.mp_ped_customization',
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
        Permissions.set_from_json(Json.encode({ PAAll = true }))
        Permissions.set_supplementary_from_json(Json.encode({}))
    end

    local function find_item(menu, text)
        for _, item in ipairs(menu:GetMenuItems()) do
            if item.Text == text then
                return item
            end
        end
        return nil
    end

    local function last_call(native_name)
        local calls = cfx:calls(native_name)
        local call = calls[#calls]
        return { table.unpack(call, 1, call.n) }
    end

    local function create_instance()
        local MpPed = require('client.menus.mp_ped_customization')
        local instance = MpPed.create()
        State.menus.mp_ped_customization = instance
        return instance
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

    it('builds the main menu and the saved characters listing', function()
        local instance = create_instance()
        assert.equal(3, instance.menu:Size())
        assert.is_not_nil(find_item(instance.menu, 'Create Male Character'))
        assert.is_not_nil(find_item(instance.menu, 'Create Female Character'))
        assert.is_not_nil(find_item(instance.menu, 'Saved Characters'))

        -- category listing: create btn + spacer + Uncategorized
        assert.equal(3, instance.SavedCharactersMenu:Size())
        assert.is_not_nil(find_item(instance.SavedCharactersMenu, 'Create Category'))
        assert.is_not_nil(find_item(instance.SavedCharactersMenu, 'Uncategorized'))
    end)

    it('spawns the golden fixture pixel-identically', function()
        local fixture_json = read_fixture('mp_ped_data.json')
        SetResourceKvp('mp_ped_TestChar', fixture_json)
        local fixture = Json.decode(fixture_json)
        local instance = create_instance()

        instance.spawn_this_character('TestChar', true)

        assert.same({ 0, fixture.ModelHash }, last_call('SetPlayerModel'))

        -- exact head blend data from the save
        local blend = last_call('SetPedHeadBlendData')
        assert.same({ 900, 4, 21, 0, 4, 21, 0, 0.5, 0.5, 0.0, false }, blend)

        -- clothes: component 4 → drawable 21, texture 0
        local found_clothes = false
        for _, call in ipairs(cfx:calls('SetPedComponentVariation')) do
            if call[2] == 4 and call[3] == 21 and call[4] == 0 then
                found_clothes = true
                break
            end
        end
        assert.is_true(found_clothes, 'saved clothes were not applied')

        -- appearance: beard style 10 at full opacity, color 29
        local found_beard = false
        for _, call in ipairs(cfx:calls('SetPedHeadOverlay')) do
            if call[2] == 1 and call[3] == 10 and math.abs(call[4] - 1.0) < 1e-9 then
                found_beard = true
                break
            end
        end
        assert.is_true(found_beard, 'beard overlay was not applied')

        -- face feature 19 → 0.55
        local found_feature = false
        for _, call in ipairs(cfx:calls('SetPedFaceFeature')) do
            if call[2] == 19 and math.abs(call[3] - 0.55) < 1e-9 then
                found_feature = true
                break
            end
        end
        assert.is_true(found_feature, 'face shape feature was not applied')

        -- prop 0 → 8
        local found_prop = false
        for _, call in ipairs(cfx:calls('SetPedPropIndex')) do
            if call[2] == 0 and call[3] == 8 then
                found_prop = true
                break
            end
        end
        assert.is_true(found_prop, 'saved prop was not applied')

        -- the hair + torso tattoos from the save
        assert.equal(2, #cfx:calls('AddPedDecorationFromHashes'))
        -- the hair facial decoration from PedAppearance.HairOverlay
        assert.equal(GetHashKey('mpbeach_overlays'), last_call('SetPedFacialDecoration')[2])
    end)

    it('creates and saves a male character in the C# record shape', function()
        local instance = create_instance()
        local menu = instance.menu
        local creator = instance.CreateCharacterMenu

        menu.OnItemSelect(menu, find_item(menu, 'Create Male Character'), 0)
        assert.same({ 0, GetHashKey('mp_m_freemode_01') }, last_call('SetPlayerModel'))

        -- the save handler waits for an open menu before going back
        creator:OpenMenu()

        -- save with a typed name
        cfx:stub_native('UpdateOnscreenKeyboard', function()
            return 1
        end)
        cfx:stub_native('GetOnscreenKeyboardResult', function()
            return 'SpecChar'
        end)
        creator.OnItemSelect(creator, find_item(creator, 'Save Character'), 9)

        local record = Json.decode(GetResourceKvpString('mp_ped_SpecChar'))
        assert.is_not_nil(record, 'character record was not saved')
        assert.equal(1, record.Version)
        assert.is_true(record.IsMale)
        assert.equal(GetHashKey('mp_m_freemode_01'), record.ModelHash)
        assert.equal('mp_ped_SpecChar', record.SaveName)
        -- default creator clothing captured with string-keyed components
        assert.same({ Key = 15, Value = 0 }, record.DrawableVariations.clothes['3'])
        assert.same({ Key = 34, Value = 0 }, record.DrawableVariations.clothes['6'])
        -- head blend + the load-bearing tattoo typo present
        assert.equal(0.0, record.PedHeadBlendData.ParentFaceShapePercent)
        assert.is_table(record.PedTatttoos)
    end)

    it('lists saved characters under their category and manages them', function()
        SetResourceKvp('mp_ped_TestChar', read_fixture('mp_ped_data.json'))
        local instance = create_instance()
        local saved_menu = instance.SavedCharactersMenu
        local category_menu = instance.SavedCharactersCategoryMenu
        local manage_menu = instance.ManageSavedCharacterMenu

        instance.update_saved_peds_menu()
        saved_menu.OnItemSelect(saved_menu, find_item(saved_menu, 'Uncategorized'), 2)

        -- 6 management items + the fixture character
        assert.equal(7, category_menu:Size())
        local char_btn = find_item(category_menu, 'TestChar')
        assert.is_not_nil(char_btn)
        assert.equal(require('menu.items').Icon.MALE, char_btn.LeftIcon)

        -- select the character: manage menu points at it
        category_menu.OnItemSelect(category_menu, char_btn, 6)
        assert.equal('TestChar', manage_menu.MenuSubtitle)
        assert.equal('(Male) ', manage_menu.CounterPreText)

        -- set as default character
        manage_menu.OnItemSelect(manage_menu, find_item(manage_menu, 'Set As Default Character'), 4)
        assert.equal('mp_ped_TestChar', GetResourceKvpString('vmenu_default_character'))

        -- delete with the two-step confirm
        local del_btn = find_item(manage_menu, 'Delete Saved Character')
        manage_menu.OnItemSelect(manage_menu, del_btn, 7)
        assert.equal('Are you sure?', del_btn.Label)
        manage_menu.OnItemSelect(manage_menu, del_btn, 7)
        assert.is_nil(GetResourceKvpString('mp_ped_TestChar'))
    end)

    it('creates categories and assigns characters to them', function()
        SetResourceKvp('mp_ped_TestChar', read_fixture('mp_ped_data.json'))
        local instance = create_instance()
        local saved_menu = instance.SavedCharactersMenu

        -- create a category through the "Create Category" button
        cfx:stub_native('UpdateOnscreenKeyboard', function()
            return 1
        end)
        local inputs = { 'Racing', 'My racing characters' }
        local input_index = 0
        cfx:stub_native('GetOnscreenKeyboardResult', function()
            input_index = input_index + 1
            return inputs[input_index]
        end)
        saved_menu.OnItemSelect(saved_menu, find_item(saved_menu, 'Create Category'), 0)

        local category = Json.decode(GetResourceKvpString('mp_character_category_Racing'))
        assert.equal('Racing', category.Name)
        assert.equal('My racing characters', category.Description)

        -- the listing now shows the new category
        instance.update_saved_peds_menu()
        assert.is_not_nil(find_item(saved_menu, 'Racing'))
    end)

    it('tracks inheritance changes into the head blend', function()
        local instance = create_instance()
        local menu = instance.menu
        local inheritance = instance.InheritanceMenu

        menu.OnItemSelect(menu, find_item(menu, 'Create Male Character'), 0)

        local parent_one = find_item(inheritance, 'Parent #1')
        parent_one.ListIndex = 3
        inheritance.OnListIndexChange(inheritance, parent_one, 0, 3, 0)
        local blend = last_call('SetPedHeadBlendData')
        assert.equal(3, blend[2]) -- first face shape parent

        local shape_mix = find_item(inheritance, 'Head Shape Mix')
        inheritance.OnSliderPositionChange(inheritance, shape_mix, 5, 8, 4)
        blend = last_call('SetPedHeadBlendData')
        assert.equal(0.8, blend[8])
    end)
end)
