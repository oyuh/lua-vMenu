-- Port of vMenu/menus/VehicleSpawner.cs: spawn by name, addon vehicles, and
-- the 23 vehicle class submenus with the stats panel.

local Permissions = require('shared.permissions')
local State = require('client.state')
local Common = require('client.common')
local UserDefaults = require('client.user_defaults')
local VehicleData = require('client.data.vehicle_data')
local Controller = require('menu.controller')
local Items = require('menu.items')
local Menu = require('menu.menu')

local VehicleSpawner = {}

-- Max speed / acceleration / braking / traction reference values per class
-- (used to normalize the stats panel bars).
-- stylua: ignore start
local SPEED_VALUES = {
    44.9374657, 50.0000038, 48.862133, 48.1321335, 50.7077942, 51.3333359, 52.3922348, 53.86687,
    52.03867, 49.2241631, 39.6176529, 37.5559425, 42.72843, 21.0, 45.0, 65.1952744, 109.764259,
    42.72843, 56.5962219, 57.5398865, 43.3140678, 26.66667, 53.0537224,
}
local ACCELERATION_VALUES = {
    0.34, 0.29, 0.335, 0.28, 0.395, 0.39, 0.66, 0.42, 0.425, 0.475, 0.21, 0.3, 0.32, 0.17, 18.0,
    5.88, 21.0700016, 0.33, 14.0, 6.86, 0.32, 0.2, 0.76,
}
local BRAKING_VALUES = {
    0.72, 0.95, 0.85, 0.9, 1.0, 1.0, 1.3, 1.25, 1.52, 1.1, 0.6, 0.7, 0.8, 3.0, 0.4, 3.5920403,
    20.58, 0.9, 2.93960738, 3.9472363, 0.85, 5.0, 1.3,
}
local TRACTION_VALUES = {
    2.3, 2.55, 2.3, 2.6, 2.625, 2.65, 2.8, 2.782, 2.9, 2.95, 2.0, 3.3, 2.175, 2.05, 0.0, 1.6,
    2.15, 2.55, 2.57, 3.7, 2.05, 2.5, 3.2925,
}
-- stylua: ignore end

-- Restricted-by-whitelist check shared by the addon + class lists.
local function apply_whitelist_lock(button, model_name)
    if State.whitelist_vehicles[model_name:lower()] ~= nil then
        if not Permissions.is_supplementary_allowed('VW' .. model_name:lower()) then
            button.Enabled = false
            button.LeftIcon = Items.Icon.LOCK
            button.Description = 'Access to this has been restricted by the server owner.'
        end
    end
end

function VehicleSpawner.create()
    local self = {}
    self.SpawnInVehicle = UserDefaults.get_bool('vehicleSpawnerSpawnInside')
    self.ReplaceVehicle = UserDefaults.get_bool('vehicleSpawnerReplacePrevious')

    local menu = Menu.new(GetPlayerName(PlayerId()), 'Vehicle Spawner')

    local spawn_by_name = Items.MenuItem.new('Spawn Vehicle By Model Name', 'Enter the name of a vehicle to spawn.')
    local spawn_in_veh = Items.MenuCheckboxItem.new(
        'Spawn Inside Vehicle',
        'This will teleport you into the vehicle when you spawn it.',
        self.SpawnInVehicle
    )
    local replace_prev = Items.MenuCheckboxItem.new(
        'Replace Previous Vehicle',
        'This will automatically delete your previously spawned vehicle when you spawn a new vehicle.',
        self.ReplaceVehicle
    )

    if Permissions.is_allowed('VSSpawnByName') then
        menu:AddMenuItem(spawn_by_name)
    end
    menu:AddMenuItem(spawn_in_veh)
    menu:AddMenuItem(replace_prev)

    -- Addon vehicles submenu.
    local addon_cars_menu = Menu.new('Addon Vehicles', 'Spawn An Addon Vehicle')
    local addon_cars_btn = Items.MenuItem.new('Addon Vehicles', 'A list of addon vehicles available on this server.')
    addon_cars_btn.Label = '→→→'
    menu:AddMenuItem(addon_cars_btn)

    if Permissions.is_allowed('VSAddon') then
        if next(State.addon_vehicles) ~= nil then
            Controller.BindMenuItem(menu, addon_cars_menu, addon_cars_btn)
            Controller.AddSubmenu(menu, addon_cars_menu)
            local unavailable_cars = Menu.new('Addon Spawner', 'Unavailable Vehicles')
            local unavailable_cars_btn = Items.MenuItem.new(
                'Unavailable Vehicles',
                'These addon vehicles are not currently being streamed (correctly) and are not able to be spawned.'
            )
            unavailable_cars_btn.Label = '→→→'
            Controller.AddSubmenu(addon_cars_menu, unavailable_cars)

            -- Addons sorted by name for a stable order (C# dictionary
            -- iteration over the parsed config preserves file order; the
            -- parsed table doesn't, so sort by model name).
            local addon_names = {}
            for name in pairs(State.addon_vehicles) do
                addon_names[#addon_names + 1] = name
            end
            table.sort(addon_names)

            for cat = 0, 22 do
                local class_label = GetLabelText(('VEH_CLASS_%d'):format(cat))
                local category_menu = Menu.new('Addon Spawner', class_label)
                local category_btn =
                    Items.MenuItem.new(class_label, ('Spawn an addon vehicle from the %s class.'):format(class_label))
                category_btn.Label = '→→→'
                addon_cars_menu:AddMenuItem(category_btn)

                if State.allowed_vehicle_categories[cat + 1] == false then
                    category_btn.Description = 'This vehicle class is disabled by the server.'
                    category_btn.Enabled = false
                    category_btn.LeftIcon = Items.Icon.LOCK
                    category_btn.Label = ''
                else
                    for _, model_name in ipairs(addon_names) do
                        local model = State.addon_vehicles[model_name]
                        if GetVehicleClassFromName(model) == cat then
                            local localized = GetLabelText(GetDisplayNameFromVehicleModel(model))
                            local name = localized ~= 'NULL' and localized or GetDisplayNameFromVehicleModel(model)
                            name = name ~= 'CARNOTFOUND' and name or model_name

                            local car_btn = Items.MenuItem.new(name, ('Click to spawn %s.'):format(name))
                            car_btn.Label = ('(%s)'):format(model_name)
                            car_btn.ItemData = model_name
                            apply_whitelist_lock(car_btn, model_name)

                            if IsModelInCdimage(model) then
                                category_menu:AddMenuItem(car_btn)
                            else
                                car_btn.Enabled = false
                                car_btn.Description = 'This vehicle is not available. Please ask the server owner '
                                    .. 'to check if the vehicle is being streamed correctly.'
                                car_btn.LeftIcon = Items.Icon.LOCK
                                unavailable_cars:AddMenuItem(car_btn)
                            end
                        end
                    end

                    if category_menu:Size() > 0 then
                        Controller.AddSubmenu(addon_cars_menu, category_menu)
                        Controller.BindMenuItem(addon_cars_menu, category_menu, category_btn)
                        category_menu.OnItemSelect = function(_, item, _index)
                            if type(item.ItemData) == 'string' then
                                Common.spawn_vehicle_by_name(item.ItemData, self.SpawnInVehicle, self.ReplaceVehicle)
                            end
                        end
                    else
                        category_btn.Description = 'There are no addon cars available in this category.'
                        category_btn.Enabled = false
                        category_btn.LeftIcon = Items.Icon.LOCK
                        category_btn.Label = ''
                    end
                end
            end

            if unavailable_cars:Size() > 0 then
                addon_cars_menu:AddMenuItem(unavailable_cars_btn)
                Controller.BindMenuItem(addon_cars_menu, unavailable_cars, unavailable_cars_btn)
            end
        else
            addon_cars_btn.Enabled = false
            addon_cars_btn.LeftIcon = Items.Icon.LOCK
            addon_cars_btn.Description = 'There are no addon vehicles available on this server.'
        end
    else
        addon_cars_btn.Enabled = false
        addon_cars_btn.LeftIcon = Items.Icon.LOCK
        addon_cars_btn.Description = 'Access to this list has been restricted by the server owner.'
    end

    -- The 23 vehicle class submenus.
    local function handle_stats_panel(opened_menu, current_item)
        if current_item ~= nil then
            if type(current_item.ItemData) == 'table' and current_item.ItemData.stats then
                local stats = current_item.ItemData.stats
                opened_menu.ShowVehicleStatsPanel = true
                opened_menu:SetVehicleStats(stats[1], stats[2], stats[3], stats[4])
                opened_menu:SetVehicleUpgradeStats(0.0, 0.0, 0.0, 0.0)
            else
                opened_menu.ShowVehicleStatsPanel = false
            end
        end
    end

    for veh_class = 0, 22 do
        local class_name = GetLabelText(('VEH_CLASS_%d'):format(veh_class))
        local btn = Items.MenuItem.new(class_name, ('Spawn a vehicle from the ~o~%s ~s~class.'):format(class_name))
        btn.Label = '→→→'

        local vehicle_class_menu = Menu.new('Vehicle Spawner', class_name)
        Controller.AddSubmenu(menu, vehicle_class_menu)
        menu:AddMenuItem(btn)

        if State.allowed_vehicle_categories[veh_class + 1] ~= false then
            Controller.BindMenuItem(menu, vehicle_class_menu, btn)
        else
            btn.LeftIcon = Items.Icon.LOCK
            btn.Description = 'This category has been disabled by the server owner.'
            btn.Enabled = false
        end

        local class_vehicles = VehicleData.VehicleClasses[class_name] or {}
        local duplicate_counts = {}

        for _, veh in ipairs(class_vehicles) do
            local proper_cased = veh:sub(1, 1):upper() .. veh:lower():sub(2)
            local display = Common.get_veh_display_name_from_model(veh)
            local veh_name = display ~= 'NULL' and display or proper_cased
            local model = GetHashKey(veh)

            local top_speed =
                Common.map(GetVehicleModelEstimatedMaxSpeed(model), 0.0, SPEED_VALUES[veh_class + 1], 0.0, 1.0)
            local acceleration =
                Common.map(GetVehicleModelAcceleration(model), 0.0, ACCELERATION_VALUES[veh_class + 1], 0.0, 1.0)
            local max_braking =
                Common.map(GetVehicleModelMaxBraking(model), 0.0, BRAKING_VALUES[veh_class + 1], 0.0, 1.0)
            local max_traction =
                Common.map(GetVehicleModelMaxTraction(model), 0.0, TRACTION_VALUES[veh_class + 1], 0.0, 1.0)

            -- Number duplicate display names: "Name (2)", "Name (3)", ...
            for _, existing in ipairs(vehicle_class_menu:GetMenuItems()) do
                if existing.Text == veh_name then
                    duplicate_counts[veh_name] = (duplicate_counts[veh_name] or 1) + 1
                    veh_name = ('%s (%d)'):format(veh_name, duplicate_counts[veh_name])
                    break
                end
            end

            if DoesModelExist(veh) then
                local veh_btn = Items.MenuItem.new(veh_name)
                veh_btn.Label = ('(%s)'):format(veh:lower())
                veh_btn.ItemData = { stats = { top_speed, acceleration, max_braking, max_traction } }
                vehicle_class_menu:AddMenuItem(veh_btn)
                apply_whitelist_lock(veh_btn, veh)
            else
                local veh_btn = Items.MenuItem.new(
                    veh_name,
                    'This vehicle is not available because the model could not be found in your game files. '
                        .. 'If this is a DLC vehicle, make sure the server is streaming it.'
                )
                veh_btn.Enabled = false
                veh_btn.Label = ('(%s)'):format(veh:lower())
                veh_btn.ItemData = { stats = { 0.0, 0.0, 0.0, 0.0 } }
                vehicle_class_menu:AddMenuItem(veh_btn)
                veh_btn.RightIcon = Items.Icon.LOCK
            end
        end

        vehicle_class_menu.ShowVehicleStatsPanel = true

        vehicle_class_menu.OnItemSelect = function(_, _item, index)
            Common.spawn_vehicle_by_name(class_vehicles[index + 1], self.SpawnInVehicle, self.ReplaceVehicle)
        end

        vehicle_class_menu.OnMenuOpen = function(m)
            handle_stats_panel(m, m:GetCurrentMenuItem())
        end
        vehicle_class_menu.OnIndexChange = function(m, _old_item, new_item, _old_index, _new_index)
            handle_stats_panel(m, new_item)
        end
    end

    menu.OnItemSelect = function(_, item, _index)
        if item == spawn_by_name then
            -- "custom" asks the player for a model name.
            Common.spawn_vehicle_by_name('custom', self.SpawnInVehicle, self.ReplaceVehicle)
        end
    end

    menu.OnCheckboxChange = function(_, item, _index, checked)
        if item == spawn_in_veh then
            self.SpawnInVehicle = checked
        elseif item == replace_prev then
            self.ReplaceVehicle = checked
        end
    end

    self.menu = menu
    return self
end

return VehicleSpawner
