-- VehicleOptions menu specs: permission gating, the C#-compatible radio KVP,
-- plate style mapping, multipliers, the dynamic mod menu, underglow, extras
-- (incl. the damage gate), and the shared custom-RGB submenu.

local CfxMock = require('tests.mocks.cfx')

describe('vehicle options menu', function()
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
            'client.vehicle_common',
            'client.vehicle_mod_names',
            'client.storage',
            'client.user_defaults',
            'client.menus.vehicle_options',
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

    -- last recorded call's arguments, without table.pack's n field
    local function last_call(native_name)
        local calls = cfx:calls(native_name)
        local call = calls[#calls]
        return { table.unpack(call, 1, call.n) }
    end

    local function find_item(menu, text)
        for _, item in ipairs(menu:GetMenuItems()) do
            if item.Text == text then
                return item
            end
        end
        return nil
    end

    -- puts the local ped (900) in the driver seat of vehicle 500
    local function enter_vehicle()
        cfx:stub_native('IsPedInAnyVehicle', function()
            return true
        end)
        cfx:stub_native('GetVehiclePedIsIn', function()
            return 500
        end)
        cfx:stub_native('GetPedInVehicleSeat', function(_vehicle, seat)
            if seat == -1 then
                return 900
            end
            return 0
        end)
    end

    local function create_instance()
        local VehicleOptionsMenu = require('client.menus.vehicle_options')
        local instance = VehicleOptionsMenu.create()
        State.menus.vehicle_options = instance
        return instance
    end

    before_each(function()
        cfx = CfxMock.new():install()
        cfx:add_player('0', { name = 'LocalPlayer' })
        cfx.game_timer = 100000
        cfx.entity_coords[500] = { x = 0.0, y = 0.0, z = 0.0 }
        fresh_modules()
    end)

    after_each(function()
        cfx:uninstall()
    end)

    it('builds the full menu tree when everything is allowed', function()
        grant({ VOAll = true })
        local instance = create_instance()

        for _, text in ipairs({
            'Vehicle God Mode',
            'God Mode Options',
            'Repair Vehicle',
            'Wash Vehicle',
            'Mod Menu',
            'Vehicle Colors',
            'Vehicle Neon Kits',
            'Vehicle Liveries',
            'Vehicle Extras',
            'Toggle Engine On/Off',
            'Set License Plate Text',
            'License Plate Type',
            'Vehicle Doors',
            'Vehicle Windows',
            'Speed Limiter',
            'Enable Torque Multiplier',
            'Enable Power Multiplier',
            'Cycle Through Vehicle Seats',
            'Fix / Destroy Tires',
            'Destroy Engine',
            'Show Vehicle Health',
            'Enable Default Radio Station',
            'Set Default Radio Station',
            'Disable Siren',
            'No Bike Helmet',
            '~r~Delete Vehicle',
        }) do
            assert.is_not_nil(find_item(instance.menu, text), 'missing item: ' .. text)
        end

        assert.is_not_nil(instance.VehicleModMenu)
        assert.is_not_nil(instance.DeleteConfirmMenu)
        assert.equal(2, instance.DeleteConfirmMenu:Size())
    end)

    it('shows only the always-available items without permissions', function()
        grant({})
        local instance = create_instance()
        assert.equal(3, instance.menu:Size())
        assert.is_not_nil(find_item(instance.menu, 'Show Vehicle Health'))
        assert.is_not_nil(find_item(instance.menu, 'Enable Default Radio Station'))
        assert.is_not_nil(find_item(instance.menu, 'Set Default Radio Station'))
    end)

    it('persists the default radio station exactly like C# (enum ints)', function()
        grant({ VOAll = true })
        enter_vehicle()
        cfx:stub_native('DoesPlayerVehHaveRadio', function()
            return true
        end)
        local instance = create_instance()
        local menu = instance.menu

        -- unset KVP reads 0 (LosSantosRockRadio) → override on, like upstream
        assert.is_true(instance.VehicleRadioOverride)

        local override = find_item(menu, 'Enable Default Radio Station')
        local stations = find_item(menu, 'Set Default Radio Station')
        assert.equal(22, #stations.ListItems)
        assert.equal('RadioOff', stations.ListItems[22])

        -- disabling the override stores -1
        menu.OnCheckboxChange(menu, override, 0, false)
        assert.is_false(instance.VehicleRadioOverride)
        assert.equal(-1, GetResourceKvpInt('settings_vehicleDefaultRadio'))
        assert.is_false(stations.Enabled)

        -- re-enabling stores the starter channel (LosSantosRockRadio = 0)
        menu.OnCheckboxChange(menu, override, 0, true)
        assert.equal(0, GetResourceKvpInt('settings_vehicleDefaultRadio'))
        assert.equal(0, stations.ListIndex)

        -- RadioOff is enum value 255, not its list position
        menu.OnListIndexChange(menu, stations, 0, 21, 0)
        assert.equal(255, GetResourceKvpInt('settings_vehicleDefaultRadio'))
        local radio_calls = cfx:calls('SetVehRadioStation')
        assert.equal('OFF', radio_calls[#radio_calls][2])

        -- a normal station uses the internal game name
        menu.OnListIndexChange(menu, stations, 21, 1, 0)
        assert.equal(1, GetResourceKvpInt('settings_vehicleDefaultRadio'))
        radio_calls = cfx:calls('SetVehRadioStation')
        assert.equal('RADIO_02_POP', radio_calls[#radio_calls][2])
    end)

    it('maps license plate list positions to LicensePlateStyle values', function()
        grant({ VOAll = true })
        enter_vehicle()
        local instance = create_instance()
        local menu = instance.menu
        local plate_type = find_item(menu, 'License Plate Type')

        -- list position 1 is BlueOnWhite2 = 3
        menu.OnListIndexChange(menu, plate_type, 0, 1, 0)
        assert.same({ 500, 3 }, last_call('SetVehicleNumberPlateTextIndex'))

        -- refresh on menu open maps the style back to the list position
        cfx:stub_native('GetPlayersLastVehicle', function()
            return 500
        end)
        cfx:stub_native('GetVehicleNumberPlateTextIndex', function()
            return 4 -- BlueOnWhite3
        end)
        menu.OnMenuOpen(menu)
        assert.equal(2, plate_type.ListIndex)
    end)

    it('applies the power multiplier when enabled', function()
        grant({ VOAll = true })
        enter_vehicle()
        local instance = create_instance()
        local menu = instance.menu

        local power_enabled = find_item(menu, 'Enable Power Multiplier')
        local power_list = find_item(menu, 'Set Engine Power Multiplier')

        menu.OnCheckboxChange(menu, power_enabled, 0, true)
        assert.is_true(instance.VehiclePowerMultiplier)
        assert.same({ 500, 2.0 }, last_call('SetVehicleEnginePowerMultiplier'))

        -- x8 is list index 2
        menu.OnListIndexChange(menu, power_list, 0, 2, 0)
        assert.equal(8.0, instance.VehiclePowerMultiplierAmount)
        assert.same({ 500, 8.0 }, last_call('SetVehicleEnginePowerMultiplier'))

        menu.OnCheckboxChange(menu, power_enabled, 0, false)
        assert.same({ 500, 1.0 }, last_call('SetVehicleEnginePowerMultiplier'))
    end)

    it('builds the dynamic mod menu and applies mod selections', function()
        grant({ VOAll = true })
        enter_vehicle()
        cfx:stub_native('GetNumVehicleMods', function(_vehicle, mod_type)
            if mod_type == 0 then -- Spoilers
                return 2
            end
            return 0
        end)
        local instance = create_instance()
        instance.update_mods()

        local mod_menu = instance.VehicleModMenu
        local spoilers = find_item(mod_menu, 'Spoilers')
        assert.is_not_nil(spoilers)
        assert.same({ 'Stock Spoilers [1/3]', 'Spoilers 1 [2/3]', 'Spoilers 2 [3/3]' }, spoilers.ListItems)
        assert.equal(0, spoilers.ItemData)

        for _, text in ipairs({
            'Wheel Type',
            'Headlights',
            'Toggle Custom Wheels',
            'Turbo',
            'Bullet Proof Tires',
            'Low Grip Tires',
            'Tire Smoke',
            'Window Tint',
        }) do
            assert.is_not_nil(find_item(mod_menu, text), 'missing mod menu item: ' .. text)
        end

        -- picking upgrade #2 (list position 2) applies mod index 1
        spoilers.ListIndex = 2
        mod_menu.OnListIndexChange(mod_menu, spoilers, 0, 2, 0)
        assert.same({ 500, 0, 1, false }, last_call('SetVehicleMod'))

        -- turbo checkbox toggles mod 18
        local turbo = find_item(mod_menu, 'Turbo')
        mod_menu.OnCheckboxChange(mod_menu, turbo, 0, true)
        assert.same({ 500, 18, true }, last_call('ToggleVehicleMod'))
    end)

    it('resets and toggles neon underglow', function()
        grant({ VOAll = true })
        enter_vehicle()
        cfx:stub_native('GetEntityBoneIndexByName', function()
            return 4 -- every neon bone exists
        end)
        local instance = create_instance()
        local menu = instance.menu
        local underglow_menu = instance.VehicleUnderglowMenu

        -- opening the underglow submenu re-reads the vehicle state
        local underglow_btn = find_item(menu, 'Vehicle Neon Kits')
        menu.OnItemSelect(menu, underglow_btn, 0)

        local front = find_item(underglow_menu, 'Enable Front Light')
        assert.is_true(front.Enabled)
        assert.is_false(front.Checked)

        -- checking the front light enables neon index 2 (VehicleNeonLight.Front)
        underglow_menu.OnCheckboxChange(underglow_menu, front, 0, true)
        assert.same({ 500, 2, true }, last_call('SetVehicleNeonLightEnabled'))

        -- the custom RGB sliders from CreateCustomColourMenu are appended
        local red_slider = find_item(underglow_menu, 'Red Color')
        assert.is_not_nil(red_slider)
        underglow_menu.OnSliderPositionChange(underglow_menu, red_slider, 128, 200, 0)
        -- mock neon colour reads back 255,255,255; red channel replaced
        assert.same({ 500, 200, 255, 255 }, last_call('SetVehicleNeonLightsColour'))
    end)

    it('locks the underglow checkboxes when the vehicle has no neon kit', function()
        grant({ VOAll = true })
        enter_vehicle()
        local instance = create_instance()
        local menu = instance.menu

        menu.OnItemSelect(menu, find_item(menu, 'Vehicle Neon Kits'), 0)
        local front = find_item(instance.VehicleUnderglowMenu, 'Enable Front Light')
        assert.is_false(front.Enabled)
        assert.equal(require('menu.items').Icon.LOCK, front.LeftIcon)
    end)

    it('builds the extras menu from config labels and toggles extras', function()
        grant({ VOAll = true })
        enter_vehicle()
        State.vehicle_extras[0] = { ['1'] = 'Roof Rack' } -- GetEntityModel default is 0
        cfx:stub_native('DoesExtraExist', function(_vehicle, extra)
            return extra == 1 or extra == 3
        end)
        local instance = create_instance()
        local menu = instance.menu
        local components_menu = instance.VehicleComponentsMenu

        menu.OnItemSelect(menu, find_item(menu, 'Vehicle Extras'), 0)
        assert.is_not_nil(find_item(components_menu, 'Roof Rack'))
        assert.is_not_nil(find_item(components_menu, 'Extra #3'))
        assert.is_not_nil(find_item(components_menu, 'Go Back'))

        -- Vehicle.ToggleExtra inverts the flag for SetVehicleExtra
        local roof_rack = find_item(components_menu, 'Roof Rack')
        components_menu.OnCheckboxChange(components_menu, roof_rack, 0, true)
        assert.same({ 500, 1, false }, last_call('SetVehicleExtra'))
    end)

    it('disables extras when the vehicle is too damaged', function()
        grant({ VOMenu = true, VOComponents = true }) -- no VOBypassExtraDamage
        enter_vehicle()
        cfx:set_convar('vmenu_prevent_extras_when_damaged', 'true')
        cfx:set_convar('vmenu_allowed_body_damage_for_extra_change', '900')
        cfx:set_convar('vmenu_allowed_engine_damage_for_extra_change', '900')
        cfx:stub_native('GetVehicleBodyHealth', function()
            return 500.0
        end)
        cfx:stub_native('DoesExtraExist', function(_vehicle, extra)
            return extra == 1
        end)
        local instance = create_instance()
        local menu = instance.menu
        local components_menu = instance.VehicleComponentsMenu

        menu.OnItemSelect(menu, find_item(menu, 'Vehicle Extras'), 0)
        components_menu.OnMenuOpen(components_menu)

        local items = components_menu:GetMenuItems()
        assert.is_truthy(items[1].Text:find('too damaged', 1, true))
        local extra_checkbox = find_item(components_menu, 'Extra #1')
        assert.is_false(extra_checkbox.Enabled)

        -- toggling anyway is refused with an alert and a GoBack
        components_menu.OnCheckboxChange(components_menu, extra_checkbox, 0, true)
        assert.equal(0, #cfx:calls('SetVehicleExtra'))
    end)

    it('cycles seats without needing to be the driver', function()
        grant({ VOAll = true })
        enter_vehicle()
        -- sit in a passenger seat instead of the driver seat
        cfx:stub_native('GetPedInVehicleSeat', function(_vehicle, seat)
            if seat == 0 then
                return 900
            end
            return 0
        end)
        cfx:stub_native('AreAnyVehicleSeatsFree', function()
            return true
        end)
        cfx:stub_native('IsVehicleSeatFree', function(_vehicle, seat)
            return seat ~= 0
        end)
        local instance = create_instance()
        local menu = instance.menu

        menu.OnItemSelect(menu, find_item(menu, 'Cycle Through Vehicle Seats'), 0)
        assert.equal(1, #cfx:calls('TaskWarpPedIntoVehicle'))
        assert.same({ 900, 500, 1 }, last_call('TaskWarpPedIntoVehicle'))
    end)
end)
