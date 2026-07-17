-- PlayerAppearance specs: menu gating, the PedInfo save/load round-trip
-- against the golden fixture, spawn guards (whitelist, water-only animals),
-- and the saved-peds management flow.

local CfxMock = require('tests.mocks.cfx')

local function read_fixture(name)
    local file = assert(io.open('tests/fixtures/' .. name, 'r'))
    local contents = file:read('a')
    file:close()
    return contents
end

describe('player appearance menu', function()
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
            'client.storage',
            'client.user_defaults',
            'client.weapons',
            'client.menus.player_appearance',
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

    local function grant(grants, supplementary)
        Permissions.set_from_json(Json.encode(grants))
        Permissions.set_supplementary_from_json(Json.encode(supplementary or {}))
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
        local PlayerAppearanceMenu = require('client.menus.player_appearance')
        local instance = PlayerAppearanceMenu.create()
        State.menus.player_appearance = instance
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

    it('builds the appearance menu with full permissions', function()
        grant({ PAAll = true })
        local instance = create_instance()

        for _, text in ipairs({
            'Ped Customization',
            'Ped Collections',
            'Save Ped',
            'Saved Peds',
            'Spawn Peds',
            'Walking Style',
            'Illuminated Clothing Style',
        }) do
            assert.is_not_nil(find_item(instance.menu, text), 'missing item: ' .. text)
        end

        -- spawn peds submenu got the by-name button and the five categories
        for _, text in ipairs({ 'Spawn By Name', 'Main Peds', 'Animals', 'Male Peds', 'Female Peds', 'Other Peds' }) do
            assert.is_not_nil(find_item(instance.SpawnPedsMenu, text), 'missing spawn item: ' .. text)
        end

        -- the main peds list holds the five story/freemode models
        assert.equal(5, instance.MainPedsMenu:Size())
        assert.is_not_nil(find_item(instance.MainPedsMenu, 'player_zero'))
    end)

    it('drops the customization entries without PACustomize', function()
        grant({ PAMenu = true, PASpawnNew = true })
        local instance = create_instance()
        assert.is_nil(find_item(instance.menu, 'Ped Customization'))
        assert.is_nil(find_item(instance.menu, 'Ped Collections'))
        assert.is_not_nil(find_item(instance.menu, 'Save Ped'))
    end)

    it('locks the animals submenu unless the server enables it', function()
        grant({ PAAll = true })
        -- convar defaults to false
        local instance = create_instance()
        local animals_btn = find_item(instance.SpawnPedsMenu, 'Animals')
        assert.is_false(animals_btn.Enabled)

        cfx:set_convar('vmenu_enable_animals_spawn_menu', 'true')
        fresh_modules()
        grant({ PAAll = true })
        instance = create_instance()
        animals_btn = find_item(instance.SpawnPedsMenu, 'Animals')
        assert.is_true(animals_btn.Enabled)
    end)

    it('locks whitelisted peds without the supplementary permission', function()
        -- no PAAll: the PW<name> supplementary fallback must not kick in
        grant({ PAMenu = true, PASpawnNew = true, PACustomize = true })
        State.whitelisted_peds['a_c_boar'] = GetHashKey('a_c_boar')
        local instance = create_instance()

        local boar = find_item(instance.AnimalsPedsMenu, 'a_c_boar')
        assert.is_not_nil(boar)
        assert.is_false(boar.Enabled)
        assert.equal('Access to this has been restricted by the server owner.', boar.Description)
    end)

    it('refuses water-only animals on land', function()
        grant({ PAAll = true })
        cfx:set_convar('vmenu_enable_animals_spawn_menu', 'true')
        local instance = create_instance()
        local menu = instance.AnimalsPedsMenu

        menu.OnItemSelect(menu, find_item(menu, 'a_c_dolphin'), 0)
        assert.equal(0, #cfx:calls('SetPlayerModel'))
    end)

    it('spawns a ped model and preserves health and armor', function()
        grant({ PAAll = true })
        cfx:stub_native('GetEntityHealth', function()
            return 175
        end)
        cfx:stub_native('GetPedArmour', function()
            return 42
        end)
        local instance = create_instance()
        local menu = instance.MainPedsMenu

        menu.OnItemSelect(menu, find_item(menu, 'player_zero'), 2)

        assert.same({ 0, GetHashKey('player_zero') }, last_call('SetPlayerModel'))
        assert.same({ 900, 175 }, last_call('SetEntityHealth'))
        assert.same({ 900, 42 }, last_call('SetPedArmour'))
        -- fresh skins reset to defaults
        assert.is_true(#cfx:calls('SetPedDefaultComponentVariation') > 0)
    end)

    it('round-trips the golden PedInfo fixture through load', function()
        grant({ PAAll = true })
        local fixture_json = read_fixture('ped_info.json')
        SetResourceKvp('ped_TestPed', fixture_json)

        local PedCommon = require('client.ped_common')
        PedCommon.load_saved_ped('TestPed', false)

        local fixture = Json.decode(fixture_json)
        assert.same({ 0, fixture.model }, last_call('SetPlayerModel'))

        -- drawable 4 restored with variation 33 (texture from the fixture)
        local found = false
        for _, call in ipairs(cfx:calls('SetPedComponentVariation')) do
            if call[2] == 4 and call[3] == 33 then
                found = true
                break
            end
        end
        assert.is_true(found, 'fixture drawable was not applied')

        -- prop 0 = 8 applied, missing props cleared
        local prop_applied = false
        for _, call in ipairs(cfx:calls('SetPedPropIndex')) do
            if call[2] == 0 and call[3] == 8 then
                prop_applied = true
                break
            end
        end
        assert.is_true(prop_applied, 'fixture prop was not applied')
        assert.is_true(#cfx:calls('ClearPedProp') > 0)
    end)

    it('saves the current ped in the C# PedInfo shape', function()
        grant({ PAAll = true })
        cfx:stub_native('GetPedDrawableVariation', function(_ped, component)
            return component == 4 and 33 or 0
        end)
        cfx:stub_native('GetPedPropIndex', function(_ped, prop)
            return prop == 0 and 8 or -1
        end)

        local PedCommon = require('client.ped_common')
        assert.is_true(PedCommon.save_ped('SpecSave', false))

        local record = Json.decode(GetResourceKvpString('ped_SpecSave'))
        assert.equal(1, record.version)
        assert.is_false(record.isMpPed)
        assert.equal(33, record.drawableVariations['4'])
        assert.equal(8, record.props['0'])
        -- all 21 component/prop slots persisted
        local count = 0
        for _ in pairs(record.drawableVariations) do
            count = count + 1
        end
        assert.equal(21, count)
    end)

    it('lists, renames, and deletes saved peds', function()
        grant({ PAAll = true })
        SetResourceKvp('ped_Zulu', read_fixture('ped_info.json'))
        SetResourceKvp('ped_Alpha', read_fixture('ped_info.json'))
        local instance = create_instance()
        local saved_menu = instance.SavedPedsMenu

        saved_menu.OnMenuOpen(saved_menu)
        assert.equal(2, saved_menu:Size())
        -- sorted case-insensitively
        assert.equal('Alpha', saved_menu:GetMenuItems()[1].Text)

        -- select a record, then delete it (two-step confirm)
        local selected = instance.SelectedSavedPedMenu
        saved_menu.OnItemSelect(saved_menu, saved_menu:GetMenuItems()[1], 0)
        assert.equal('Alpha', selected.MenuSubtitle)

        local delete_btn = find_item(selected, '~r~Delete Saved Ped')
        selected.OnItemSelect(selected, delete_btn, 4)
        assert.equal('Are you sure?', delete_btn.Label)
        selected.OnItemSelect(selected, delete_btn, 4)
        assert.is_nil(GetResourceKvpString('ped_Alpha'))

        saved_menu.OnMenuOpen(saved_menu)
        assert.equal(1, saved_menu:Size())
        assert.equal('Zulu', saved_menu:GetMenuItems()[1].Text)
    end)

    it('applies walking styles only to freemode models', function()
        grant({ PAAll = true })
        local instance = create_instance()
        local menu = instance.menu
        local walking_style = find_item(menu, 'Walking Style')

        -- not a freemode model: no anim applied
        menu.OnListItemSelect(menu, walking_style, 8, 5)
        assert.equal(0, #cfx:calls('SetPedAlternateMovementAnim'))

        -- freemode male, "Drunk" (list index 8) applies the male drunk dict
        cfx:stub_native('IsPedModel', function(_ped, model)
            return model == GetHashKey('mp_m_freemode_01')
        end)
        menu.OnListItemSelect(menu, walking_style, 8, 5)
        local calls = cfx:calls('SetPedAlternateMovementAnim')
        assert.equal(3, #calls)
        assert.equal('move_m@drunk@a', calls[1][3])
    end)
end)
