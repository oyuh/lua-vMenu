-- Wave-2 menu specs: the vehicle save/load round-trip (the drop-in flagship),
-- weapon loadouts, and the stateful menus' permission gating and flows.

local CfxMock = require('tests.mocks.cfx')

local function read_fixture(name)
    local file = assert(io.open('tests/fixtures/' .. name, 'r'))
    local contents = file:read('a')
    file:close()
    return contents
end

describe('wave-2 menus', function()
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
            'client.storage',
            'client.user_defaults',
            'client.noclip',
            'client.weapons',
            'client.menus.saved_vehicles',
            'client.menus.online_players',
            'client.menus.banned_players',
            'client.menus.weapon_loadouts',
            'client.menus.weapon_options',
            'client.menus.personal_vehicle',
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

    local function find_item(menu, text)
        for _, item in ipairs(menu:GetMenuItems()) do
            if item.Text == text then
                return item
            end
        end
        return nil
    end

    before_each(function()
        cfx = CfxMock.new():install()
        cfx:add_player('0', { name = 'LocalPlayer' })
        cfx.game_timer = 100000
        -- test vehicle handles pass DoesEntityExist (coords-backed in the mock)
        cfx.entity_coords[500] = { x = 0.0, y = 0.0, z = 0.0 }
        cfx.entity_coords[2000] = { x = 0.0, y = 0.0, z = 0.0 }
        fresh_modules()
    end)

    after_each(function()
        cfx:uninstall()
    end)

    describe('vehicle info capture + application (drop-in flagship)', function()
        it('captures the exact Newtonsoft VehicleInfo shape', function()
            local VehicleCommon = require('client.vehicle_common')
            local info = VehicleCommon.get_vehicle_info(500)

            -- every contract field present
            for _, field in ipairs({
                'colors',
                'customWheels',
                'extras',
                'livery',
                'model',
                'mods',
                'name',
                'neonBack',
                'neonFront',
                'neonLeft',
                'neonRight',
                'plateText',
                'plateStyle',
                'turbo',
                'tyreSmoke',
                'version',
                'wheelType',
                'windowTint',
                'xenonHeadlights',
                'bulletProofTires',
                'headlightColor',
                'enveffScale',
                'Category',
            }) do
                assert.is_not_nil(info[field], 'missing field: ' .. field)
            end
            assert.equal(1, info.version)
            assert.equal('Uncategorized', info.Category)
            assert.equal(255, info.colors.neonR)
            assert.equal(-1, info.colors.customPrimaryR)
        end)

        it('applies a C#-era saved vehicle fixture (all mods land on the vehicle)', function()
            local VehicleCommon = require('client.vehicle_common')
            local info = Json.decode(read_fixture('vehicle_info.json'))

            VehicleCommon.apply_vehicle_mods_delayed(2000, info, 0)

            assert.is_true(#cfx:calls('SetVehicleModKit') > 0)
            -- plate text from the fixture reached the native
            local plate_call = cfx:calls('SetVehicleNumberPlateText')[1]
            assert.equal(info.plateText, plate_call[2])
            -- string-keyed mods were converted back to ints for SetVehicleMod
            local saw_mod = false
            for _, call in ipairs(cfx:calls('SetVehicleMod')) do
                if type(call[2]) == 'number' and call[2] ~= 23 and call[2] ~= 24 then
                    saw_mod = true
                end
            end
            assert.is_true(saw_mod)
            -- neon colors + window tint applied
            assert.equal(info.windowTint, cfx:calls('SetVehicleWindowTint')[1][2])
        end)

        it('spawns a saved vehicle end-to-end from the KVP', function()
            grant({ VSAll = true })
            State.allowed_vehicle_categories = {}
            for i = 1, 23 do
                State.allowed_vehicle_categories[i] = true
            end

            cfx.kvp['veh_MyCar'] = read_fixture('vehicle_info.json')
            local VehicleCommon = require('client.vehicle_common')
            local saved = VehicleCommon.get_saved_vehicles()
            assert.is_table(saved['veh_MyCar'])

            local handle = VehicleCommon.spawn_saved_vehicle(saved['veh_MyCar'], 'MyCar')
            assert.equal(2000, handle)
            assert.equal(1, #cfx:calls('CreateVehicle'))
            -- the mods pass ran against the new vehicle
            assert.is_true(#cfx:calls('SetVehicleModKit') > 0)
        end)

        it('round-trips its own captures byte-compatibly', function()
            local VehicleCommon = require('client.vehicle_common')
            local Storage = require('client.storage')
            local info = VehicleCommon.get_vehicle_info(500, 'Drift Cars')
            assert.is_true(Storage.save_vehicle_info('veh_RT', info, false))
            local reloaded = Storage.get_saved_vehicle_info('veh_RT')
            assert.same(info, reloaded)
        end)
    end)

    describe('saved vehicles menu', function()
        it('creates the type menu with save/class/category entries', function()
            grant({ SVMenu = true })
            local SavedVehicles = require('client.menus.saved_vehicles')
            local instance = SavedVehicles.create()
            assert.equal(3, instance.type_menu:Size())
            assert.equal('Save Current Vehicle', instance.type_menu:GetMenuItems()[1].Text)
            -- 23 classes + unavailable
            assert.equal(24, instance.menu:Size())
        end)

        it('lists saves in their class submenus after refresh', function()
            grant({ SVMenu = true })
            cfx.kvp['veh_Racer'] = read_fixture('vehicle_info.json')
            local SavedVehicles = require('client.menus.saved_vehicles')
            local instance = SavedVehicles.create()

            instance.update_menu_available_categories()

            -- mock class 0: the save lands in the first class submenu
            local Controller = require('menu.controller')
            local first_class_btn = instance.menu:GetMenuItems()[1]
            assert.is_true(first_class_btn.Enabled)
            local class_menu = Controller.MenuButtons[first_class_btn]
            assert.equal(1, class_menu:Size())
            assert.equal('Racer', class_menu:GetMenuItems()[1].Text)
        end)
    end)

    describe('weapon loadouts', function()
        it('permission ordinals round-trip against the generated enum', function()
            local Weapons = require('client.weapons')
            assert.equal('WPPistol', Weapons.number_to_perm(Weapons.perm_to_number('WPPistol')))
            assert.equal(213, Weapons.perm_to_number('WPPistol'))
            assert.equal('WPCarbineRifle', Weapons.number_to_perm(166))
        end)

        it('saves held weapons in the C# ValidWeapon list shape', function()
            local Weapons = require('client.weapons')
            local pistol_hash = GetHashKey('weapon_pistol')
            cfx:stub_native('HasPedGotWeapon', function(_, hash, _)
                return hash == pistol_hash
            end)
            cfx:stub_native('GetAmmoInPedWeapon', function()
                return 80
            end)
            cfx:stub_native('GetPedWeaponTintIndex', function()
                return 2
            end)

            assert.is_true(Weapons.save_weapon_loadout('vmenu_string_saved_weapon_loadout_test'))
            local saved = Json.decode(cfx.kvp['vmenu_string_saved_weapon_loadout_test'])
            assert.equal(1, #saved)
            assert.equal('weapon_pistol', saved[1].SpawnName)
            assert.equal(pistol_hash, saved[1].Hash)
            assert.equal(80, saved[1].CurrentAmmo)
            assert.equal(2, saved[1].CurrentTint)
            assert.equal(213, saved[1].Perm)
            assert.is_not_nil(saved[1].GetMaxAmmo)
        end)

        it('equips a C#-era loadout fixture', function()
            local Weapons = require('client.weapons')
            cfx.kvp['vmenu_string_saved_weapon_loadout_Fix'] = read_fixture('weapon_loadout.json')

            -- Stateful ammo: the top-up loop reads back what SetPedAmmo set.
            local ammo_by_weapon = {}
            cfx:stub_native('SetPedAmmo', function(_, hash, ammo)
                ammo_by_weapon[hash] = ammo
            end)
            cfx:stub_native('GetAmmoInPedWeapon', function(_, hash)
                return ammo_by_weapon[hash] or 0
            end)

            Weapons.spawn_weapon_loadout('Fix', false, true, true)

            local gives = cfx:calls('GiveWeaponToPed')
            assert.equal(2, #gives)
            assert.equal(453432689, gives[1][2]) -- pistol hash from the fixture
            assert.equal(80, gives[1][3]) -- saved ammo restored
            local tints = cfx:calls('SetPedWeaponTintIndex')
            assert.equal(2, tints[1][3])
        end)

        it('builds the loadouts menu with the respawn toggle gated', function()
            grant({})
            local WeaponLoadouts = require('client.menus.weapon_loadouts')
            assert.equal(2, WeaponLoadouts.create().menu:Size())

            fresh_modules()
            grant({ WLEquipOnRespawn = true })
            local WithRespawn = require('client.menus.weapon_loadouts')
            assert.equal(3, WithRespawn.create().menu:Size())
        end)
    end)

    describe('online players', function()
        it('gates staff actions by permission', function()
            grant({})
            local OnlinePlayers = require('client.menus.online_players')
            local instance = OnlinePlayers.create()
            instance.update_player_list()
            -- no players in the mock's active list, so the list menu is empty
            assert.equal(0, instance.menu:Size())

            fresh_modules()
            grant({ OPAll = true })
            local WithPerms = require('client.menus.online_players')
            WithPerms.create()
        end)
    end)

    describe('banned players', function()
        it('builds ban records from the server push and unbans', function()
            grant({ OPUnban = true })
            local BannedPlayers = require('client.menus.banned_players')
            local instance = BannedPlayers.create()

            instance.update_ban_list(Json.encode({
                {
                    playerName = 'Bad',
                    identifiers = { 'license:1' },
                    bannedUntil = '3000-01-01T00:00:00',
                    banReason = 'r',
                    bannedBy = 'Admin',
                    uuid = 'u-1',
                },
            }))
            assert.equal(1, instance.menu:Size())
            assert.equal('Bad', instance.menu:GetMenuItems()[1].Text)

            -- open the record, then double-press unban (register the list
            -- menu like create_submenus does in production)
            local RegController = require('menu.controller')
            RegController.AddMenu(instance.menu)
            instance.menu:OpenMenu()
            instance.menu:SelectItem(0)
            local Controller = require('menu.controller')
            local record_menu = Controller.MenuButtons[instance.menu:GetMenuItems()[1]]
            assert.equal('Forever', record_menu:GetMenuItems()[3].Label)

            local unban_btn = record_menu:GetMenuItems()[6]
            record_menu:OpenMenu()
            record_menu:SetCurrentIndex(5)
            record_menu:SelectItem(unban_btn)
            assert.equal('Are you sure?', unban_btn.Label)
            record_menu:SelectItem(unban_btn)

            local found = nil
            for _, entry in ipairs(cfx.triggered) do
                if entry.name == 'vMenu:RequestPlayerUnban' then
                    found = entry
                end
            end
            assert.is_truthy(found)
            assert.equal('u-1', found.args[1])
        end)
    end)

    describe('weapon options + personal vehicle', function()
        it('creates the weapon options menu with gated items', function()
            grant({ WPAll = true })
            local WeaponOptions = require('client.menus.weapon_options')
            local instance = WeaponOptions.create()
            assert.is_truthy(find_item(instance.menu, 'Get All Weapons'))
            assert.is_truthy(find_item(instance.menu, 'Parachute Options'))
            -- 8 category buttons exist (all locked: mock group = 0)
            assert.is_truthy(find_item(instance.menu, 'Handguns'))
            assert.is_truthy(find_item(instance.menu, 'Sniper Rifles'))
        end)

        it('personal vehicle requires a vehicle before actions work', function()
            grant({ PVAll = true })
            local PersonalVehicle = require('client.menus.personal_vehicle')
            local instance = PersonalVehicle.create()
            assert.equal('Current Vehicle: None', instance.menu:GetMenuItems()[1].Label)

            instance.menu:OpenMenu()
            local toggle_engine = find_item(instance.menu, 'Toggle Engine')
            instance.menu:SelectItem(toggle_engine)
            -- errored (no personal vehicle), engine native untouched
            assert.equal(0, #cfx:calls('SetVehicleEngineOn'))
        end)
    end)
end)
