-- Port of vMenu/menus/SavedVehicles.cs: browsing saves by vehicle class or
-- custom category, spawning (the drop-in flagship: C#-era veh_ saves spawn
-- with all mods), renaming, replacing, deleting, and category management.

local Json = require('shared.json_compat')
local Util = require('shared.util')
local Common = require('client.common')
local VehicleCommon = require('client.vehicle_common')
local Notification = require('client.notify')
local Storage = require('client.storage')
local Controller = require('menu.controller')
local Items = require('menu.items')
local Menu = require('menu.menu')

local Notify = Notification.Notify

local SavedVehicles = {}

-- Icon names ordered by their numeric value (Enum.GetNames order).
local ICON_NAMES = {}
do
    local by_value = {}
    for name, value in pairs(Items.Icon) do
        by_value[value + 1] = name
    end
    for i = 1, #by_value do
        ICON_NAMES[i] = by_value[i]
    end
end

local FRONTEND_DELETE = 178 -- Control.FrontendDelete

function SavedVehicles.create()
    local self = {}

    local class_menu = Menu.new('Saved Vehicles', 'Manage Saved Vehicles')
    local type_menu = Menu.new('Saved Vehicles', 'Select from class or custom category')
    local vehicle_category_menu = Menu.new('Categories', 'Manage Saved Vehicles')
    local saved_vehicles_category_menu = Menu.new('Category', 'I get updated at runtime!')
    local selected_vehicle_menu = Menu.new('Manage Vehicle', 'Manage this saved vehicle.')
    local unavailable_vehicles_menu = Menu.new('Missing Vehicles', 'Unavailable Saved Vehicles')

    local saved_vehicles = {}
    local sub_menus = {}
    local currently_selected_vehicle = nil -- { key = save kvp name, value = VehicleInfo }
    local delete_button_pressed_count = 0
    local replace_button_pressed_count = 0
    local current_category = nil

    local set_category_btn =
        Items.MenuListItem.new('Set Vehicle Category', {}, 0, "Sets this Vehicle's category. Select to save.")

    -- ------------------------------------------------------------------
    -- Helpers
    -- ------------------------------------------------------------------

    local function get_all_category_names()
        local categories = {}
        local handle = StartFindKvp('saved_veh_category_')
        while true do
            local found = FindKvp(handle)
            if found == nil or found == '' then
                break
            end
            categories[#categories + 1] = found:sub(20)
        end
        EndFindKvp(handle)
        table.insert(categories, 1, 'Create New')
        table.insert(categories, 2, 'Uncategorized')
        return categories
    end

    local function get_category_icons(category_names)
        local icons = {}
        for i, name in ipairs(category_names) do
            local record = Storage.get_saved_vehicle_category_data('saved_veh_category_' .. name)
            icons[i] = record.Icon or 0
        end
        return icons
    end

    local function update_saved_vehicle_categories_menu()
        saved_vehicles = VehicleCommon.get_saved_vehicles()
        local categories = get_all_category_names()

        vehicle_category_menu:ClearMenuItems()

        local create_category_btn = Items.MenuItem.new('Create Category', 'Create a new vehicle category.')
        create_category_btn.Label = '→→→'
        vehicle_category_menu:AddMenuItem(create_category_btn)

        vehicle_category_menu:AddMenuItem(Common.get_spacer_menu_item('↓ Vehicle Categories ↓'))

        local uncategorized = {
            Name = 'Uncategorized',
            Description = 'All saved vehicles that have not been assigned to a category.',
            Icon = 0,
        }
        local uncategorized_btn = Items.MenuItem.new(uncategorized.Name, uncategorized.Description)
        uncategorized_btn.Label = '→→→'
        uncategorized_btn.ItemData = uncategorized
        vehicle_category_menu:AddMenuItem(uncategorized_btn)
        Controller.BindMenuItem(vehicle_category_menu, saved_vehicles_category_menu, uncategorized_btn)

        -- Skip "Create New" and "Uncategorized".
        local custom = {}
        for i = 3, #categories do
            custom[#custom + 1] = categories[i]
        end
        table.sort(custom, function(a, b)
            return a:lower() < b:lower()
        end)
        for _, name in ipairs(custom) do
            local category = Storage.get_saved_vehicle_category_data('saved_veh_category_' .. name)
            local btn = Items.MenuItem.new(category.Name or name, category.Description)
            btn.Label = '→→→'
            btn.LeftIcon = category.Icon or 0
            btn.ItemData = category
            vehicle_category_menu:AddMenuItem(btn)
            Controller.BindMenuItem(vehicle_category_menu, saved_vehicles_category_menu, btn)
        end

        vehicle_category_menu:RefreshIndex()
    end

    -- UpdateMenuAvailableCategories: refresh the per-class submenus + locks.
    local function update_menu_available_categories()
        saved_vehicles = VehicleCommon.get_saved_vehicles()

        local class_items = class_menu:GetMenuItems()
        for i = 0, class_menu:Size() - 2 do
            local item = class_items[i + 1]
            local has_any = false
            for _, info in pairs(saved_vehicles) do
                if GetVehicleClassFromName(info.model) == i and IsModelInCdimage(info.model) then
                    has_any = true
                    break
                end
            end
            if has_any then
                item.RightIcon = Items.Icon.NONE
                item.Label = '→→→'
                item.Enabled = true
                item.Description = ('All saved vehicles from the %s category.'):format(item.Text)
            else
                item.Label = ''
                item.RightIcon = Items.Icon.LOCK
                item.Enabled = false
                item.Description = ('You do not have any saved vehicles that belong to the %s category.'):format(
                    item.Text
                )
            end
        end

        -- Refresh the index of class submenus that shrank (a save was
        -- deleted); keep it otherwise for usability.
        for class_index, m in ipairs(sub_menus) do
            local count = 0
            for _, info in pairs(saved_vehicles) do
                if GetVehicleClassFromName(info.model) == class_index - 1 then
                    count = count + 1
                end
            end
            if count < m:Size() then
                m:RefreshIndex()
            end
        end
        for _, m in ipairs(sub_menus) do
            m:ClearMenuItems(true)
        end
        unavailable_vehicles_menu:ClearMenuItems()

        -- Stable iteration order for menu building.
        local save_names = {}
        for name in pairs(saved_vehicles) do
            save_names[#save_names + 1] = name
        end
        table.sort(save_names)

        for _, save_name in ipairs(save_names) do
            local info = saved_vehicles[save_name]
            local entry = { key = save_name, value = info }
            if IsModelInCdimage(info.model) then
                local vclass = GetVehicleClassFromName(info.model)
                local m = sub_menus[vclass + 1]
                local btn = Items.MenuItem.new(save_name:sub(5), 'Manage this saved vehicle.')
                btn.Label = ('(%s) →→→'):format(info.name or '')
                btn.ItemData = entry
                m:AddMenuItem(btn)
            else
                local btn = Items.MenuItem.new(
                    save_name:sub(5),
                    'This model could not be found in the game files. Most likely because this is an addon '
                        .. "vehicle and it's currently not streamed by the server."
                )
                btn.Label = ('(%s)'):format(info.name or '')
                btn.Enabled = false
                btn.LeftIcon = Items.Icon.LOCK
                btn.ItemData = entry
                unavailable_vehicles_menu:AddMenuItem(btn)
            end
        end

        for _, m in ipairs(sub_menus) do
            m:SortMenuItems(function(a, b)
                return a.Text:lower() < b.Text:lower()
            end)
        end
    end
    self.update_menu_available_categories = update_menu_available_categories

    -- Opens the manage-vehicle menu for one save.
    local function update_selected_vehicle_menu(selected_item, parent_menu)
        local entry = selected_item.ItemData
        if type(entry) ~= 'table' or entry.key == nil then
            return false
        end
        local category_names = get_all_category_names()
        local category_icons = get_category_icons(category_names)
        set_category_btn.ItemData = category_icons
        set_category_btn.ListItems = category_names
        set_category_btn.ListIndex = 0
        set_category_btn.RightIcon = category_icons[1]
        selected_vehicle_menu.MenuSubtitle = ('%s (%s)'):format(entry.key:sub(5), entry.value.name or '')
        currently_selected_vehicle = entry
        Controller.CloseAllMenus()
        selected_vehicle_menu:OpenMenu()
        if parent_menu ~= nil then
            Controller.AddSubmenu(parent_menu, selected_vehicle_menu)
        end
        return true
    end

    -- ------------------------------------------------------------------
    -- The class menu (23 class submenus + unavailable)
    -- ------------------------------------------------------------------

    for i = 0, 22 do
        local class_label = GetLabelText(('VEH_CLASS_%d'):format(i))
        local category_menu = Menu.new('Saved Vehicles', class_label)
        local class_button =
            Items.MenuItem.new(class_label, ('All saved vehicles from the %s category.'):format(class_label))
        sub_menus[#sub_menus + 1] = category_menu
        Controller.AddSubmenu(class_menu, category_menu)
        class_menu:AddMenuItem(class_button)
        class_button.Label = '→→→'
        Controller.BindMenuItem(class_menu, category_menu, class_button)

        category_menu.OnMenuClose = function(_)
            update_menu_available_categories()
        end
        category_menu.OnItemSelect = function(sender, item, _index)
            update_selected_vehicle_menu(item, sender)
        end
    end

    local unavailable_models = Items.MenuItem.new(
        'Unavailable Saved Vehicles',
        'These vehicles are currently unavailable because the models are not present in the game. '
            .. 'These vehicles are most likely not being streamed from the server.'
    )
    unavailable_models.Label = '→→→'
    class_menu:AddMenuItem(unavailable_models)
    Controller.BindMenuItem(class_menu, unavailable_vehicles_menu, unavailable_models)
    Controller.AddSubmenu(class_menu, unavailable_vehicles_menu)

    Controller.AddMenu(vehicle_category_menu)
    Controller.AddMenu(saved_vehicles_category_menu)
    Controller.AddMenu(selected_vehicle_menu)

    -- ------------------------------------------------------------------
    -- Category browsing
    -- ------------------------------------------------------------------

    local function create_new_category_flow()
        local name = Common.get_user_input('Enter a category name.', nil, 30)
        if name == nil or name == '' or name:lower() == 'uncategorized' or name:lower() == 'create new' then
            Notify.error(Notification.error_message('InvalidInput'))
            return nil
        end
        local description = Common.get_user_input('Enter a category description (optional).', nil, 120)
        local new_category = { Name = name, Description = description, Icon = 0 }
        if Storage.save_json_data('saved_veh_category_' .. name, Json.encode(new_category), false) then
            Notify.success(('Your category (~g~<C>%s</C>~s~) has been saved.'):format(name))
            Util.debug_log(('Saved Category %s.'):format(name))
            Controller.CloseAllMenus()
            update_saved_vehicle_categories_menu()
            saved_vehicles_category_menu:OpenMenu()
            current_category = new_category
            return new_category
        end
        Notify.error(('Saving failed, most likely because this name (~y~<C>%s</C>~s~) is already in use.'):format(name))
        return nil
    end

    vehicle_category_menu.OnItemSelect = function(_, item, _index)
        if type(item.ItemData) ~= 'table' or item.ItemData.Name == nil then
            -- "Create Category"
            if create_new_category_flow() == nil then
                return
            end
        else
            current_category = item.ItemData
        end

        local is_uncategorized = current_category.Name == 'Uncategorized'

        saved_vehicles_category_menu.MenuTitle = current_category.Name
        saved_vehicles_category_menu.MenuSubtitle = ('~s~Category: ~y~%s'):format(current_category.Name)
        saved_vehicles_category_menu:ClearMenuItems()

        local function icon_change_callback(dynamic_item, left)
            local current_index = 0
            for i, name in ipairs(ICON_NAMES) do
                if name == dynamic_item.CurrentItem then
                    current_index = i
                    break
                end
            end
            local new_index = left and current_index - 1 or current_index + 1
            if new_index < 1 then
                new_index = #ICON_NAMES
            elseif new_index > #ICON_NAMES then
                new_index = 1
            end
            dynamic_item.RightIcon = Items.Icon[ICON_NAMES[new_index]]
            return ICON_NAMES[new_index]
        end

        local rename_btn = Items.MenuItem.new('Rename Category', 'Rename this category.')
        rename_btn.Enabled = not is_uncategorized
        local description_btn = Items.MenuItem.new('Change Category Description', "Change this category's description.")
        description_btn.Enabled = not is_uncategorized
        local icon_btn = Items.MenuDynamicListItem.new(
            'Change Category Icon',
            ICON_NAMES[(current_category.Icon or 0) + 1],
            icon_change_callback,
            "Change this category's icon. Select to save."
        )
        icon_btn.Enabled = not is_uncategorized
        icon_btn.RightIcon = current_category.Icon or 0
        local delete_btn = Items.MenuItem.new('Delete Category', 'Delete this category. This can not be undone!')
        delete_btn.RightIcon = Items.Icon.WARNING
        delete_btn.Enabled = not is_uncategorized
        local delete_chars_btn = Items.MenuCheckboxItem.new(
            'Delete All Vehicles',
            'If checked, when "Delete Category" is pressed, all the saved vehicles in this category will be '
                .. 'deleted as well. If not checked, saved vehicles will be moved to "Uncategorized".',
            false
        )
        delete_chars_btn.Enabled = not is_uncategorized

        saved_vehicles_category_menu:AddMenuItem(rename_btn)
        saved_vehicles_category_menu:AddMenuItem(description_btn)
        saved_vehicles_category_menu:AddMenuItem(icon_btn)
        saved_vehicles_category_menu:AddMenuItem(delete_btn)
        saved_vehicles_category_menu:AddMenuItem(delete_chars_btn)
        saved_vehicles_category_menu:AddMenuItem(Common.get_spacer_menu_item('↓ Vehicles ↓'))

        -- Vehicles of this category: spawnable first, then unspawnable.
        local spawnable, unspawnable = {}, {}
        local save_names = {}
        for name in pairs(saved_vehicles) do
            save_names[#save_names + 1] = name
        end
        table.sort(save_names)
        for _, save_name in ipairs(save_names) do
            local info = saved_vehicles[save_name]
            local in_category
            if info.Category == nil or info.Category == '' then
                in_category = is_uncategorized
            else
                in_category = info.Category == current_category.Name
            end
            if in_category then
                local button_name = save_name:sub(5)
                local can_use = IsModelInCdimage(info.model)
                local button_description = 'Manage this saved vehicle.'
                if not can_use then
                    button_name = ('~italic~%s~italic~'):format(button_name)
                    button_description = button_description
                        .. '\n\n~r~NOTE~w~~s~: This model could not be found, and so cannot be spawned.'
                end
                local btn = Items.MenuItem.new(button_name, button_description)
                btn.Label = ('(%s) →→→'):format(info.name or '')
                btn.LeftIcon = can_use and Items.Icon.NONE or Items.Icon.LOCK
                btn.ItemData = { key = save_name, value = info }
                if can_use then
                    spawnable[#spawnable + 1] = btn
                else
                    unspawnable[#unspawnable + 1] = btn
                end
            end
        end
        for _, btn in ipairs(spawnable) do
            saved_vehicles_category_menu:AddMenuItem(btn)
        end
        for _, btn in ipairs(unspawnable) do
            saved_vehicles_category_menu:AddMenuItem(btn)
        end
    end

    saved_vehicles_category_menu.OnItemSelect = function(sender, item, index)
        if index == 0 then
            -- Rename Category
            local name = Common.get_user_input('Enter a new category name', current_category.Name, 30)
            if name == nil or name == '' or name:lower() == 'uncategorized' or name:lower() == 'create new' then
                Notify.error(Notification.error_message('InvalidInput'))
                return
            end
            if GetResourceKvpString('saved_veh_category_' .. name) ~= nil then
                Notify.error(Notification.error_message('SaveNameAlreadyExists'))
                return
            end

            local old_name = current_category.Name
            current_category.Name = name

            if Storage.save_json_data('saved_veh_category_' .. name, Json.encode(current_category), false) then
                Storage.delete_saved_storage_item('saved_veh_category_' .. old_name)
                local total, updated = 0, 0
                for save_name, info in pairs(saved_vehicles) do
                    if info.Category == old_name then
                        total = total + 1
                        info.Category = name
                        if Storage.save_vehicle_info(save_name, info, true) then
                            updated = updated + 1
                        end
                    end
                end
                Notify.success(
                    ('Your category has been renamed to ~g~<C>%s</C>~s~. %d/%d vehicles updated.'):format(
                        name,
                        updated,
                        total
                    )
                )
                Controller.CloseAllMenus()
                update_saved_vehicle_categories_menu()
                vehicle_category_menu:OpenMenu()
            else
                Notify.error(
                    'Something went wrong while renaming your category, your old category will NOT be deleted '
                        .. 'because of this.'
                )
            end
        elseif index == 1 then
            -- Change Category Description
            local description =
                Common.get_user_input('Enter a new category description', current_category.Description, 120)
            current_category.Description = description
            if
                Storage.save_json_data(
                    'saved_veh_category_' .. current_category.Name,
                    Json.encode(current_category),
                    true
                )
            then
                Notify.success('Your category description has been changed.')
                Controller.CloseAllMenus()
                update_saved_vehicle_categories_menu()
                vehicle_category_menu:OpenMenu()
            else
                Notify.error('Something went wrong while changing your category description.')
            end
        elseif index == 3 then
            -- Delete Category (double-press confirm)
            if item.Label == 'Are you sure?' then
                local delete_vehicles = sender:GetMenuItems()[5].Checked
                item.Label = ''
                DeleteResourceKvp('saved_veh_category_' .. current_category.Name)
                local total, updated = 0, 0
                for save_name, info in pairs(saved_vehicles) do
                    if info.Category == current_category.Name then
                        total = total + 1
                        if delete_vehicles then
                            updated = updated + 1
                            DeleteResourceKvp(save_name)
                        else
                            info.Category = 'Uncategorized'
                            if Storage.save_vehicle_info(save_name, info, true) then
                                updated = updated + 1
                            end
                        end
                    end
                end
                Notify.success(
                    ('Your saved category has been deleted. %d/%d vehicles %s.'):format(
                        updated,
                        total,
                        delete_vehicles and 'deleted' or 'updated'
                    )
                )
                Controller.CloseAllMenus()
                update_saved_vehicle_categories_menu()
                vehicle_category_menu:OpenMenu()
            else
                item.Label = 'Are you sure?'
            end
        else
            -- A saved vehicle entry.
            local entry = item.ItemData
            if type(entry) == 'table' and entry.key ~= nil then
                local category_names = get_all_category_names()
                local category_icons = get_category_icons(category_names)
                local name_index = 0
                for i, name in ipairs(category_names) do
                    if name == current_category.Name then
                        name_index = i - 1
                        break
                    end
                end
                set_category_btn.ItemData = category_icons
                set_category_btn.ListItems = category_names
                set_category_btn.ListIndex = name_index == 1 and 0 or name_index
                set_category_btn.RightIcon = category_icons[set_category_btn.ListIndex + 1]

                selected_vehicle_menu.MenuSubtitle = ('%s (%s)'):format(entry.key:sub(5), entry.value.name or '')
                currently_selected_vehicle = entry
                Controller.CloseAllMenus()
                selected_vehicle_menu:OpenMenu()
                Controller.AddSubmenu(saved_vehicles_category_menu, selected_vehicle_menu)
            end
        end
    end

    -- Change Category Icon (select on the dynamic list).
    saved_vehicles_category_menu.OnDynamicListItemSelect = function(_, _item, current_item)
        local icon_index = 0
        for i, name in ipairs(ICON_NAMES) do
            if name == current_item then
                icon_index = i - 1
                break
            end
        end
        current_category.Icon = icon_index
        if
            Storage.save_json_data('saved_veh_category_' .. current_category.Name, Json.encode(current_category), true)
        then
            Notify.success(('Your category icon been changed to ~g~<C>%s</C>~s~.'):format(ICON_NAMES[icon_index + 1]))
            update_saved_vehicle_categories_menu()
        else
            Notify.error('Something went wrong while changing your category icon.')
        end
    end

    -- ------------------------------------------------------------------
    -- The manage-vehicle menu
    -- ------------------------------------------------------------------

    local spawn_vehicle_btn = Items.MenuItem.new('Spawn Vehicle')
    local rename_vehicle = Items.MenuItem.new('Rename Vehicle', 'Rename your saved vehicle.')
    local replace_vehicle = Items.MenuItem.new(
        '~r~Replace Vehicle',
        'Your saved vehicle will be replaced with the vehicle you are currently sitting in. '
            .. '~r~Warning: this can NOT be undone!'
    )
    local delete_vehicle_btn = Items.MenuItem.new(
        '~r~Delete Vehicle',
        '~r~This will delete your saved vehicle. Warning: this can NOT be undone!'
    )
    selected_vehicle_menu:AddMenuItem(spawn_vehicle_btn)
    selected_vehicle_menu:AddMenuItem(rename_vehicle)
    selected_vehicle_menu:AddMenuItem(set_category_btn)
    selected_vehicle_menu:AddMenuItem(replace_vehicle)
    selected_vehicle_menu:AddMenuItem(delete_vehicle_btn)

    selected_vehicle_menu.OnMenuOpen = function(_)
        if currently_selected_vehicle == nil then
            return
        end
        local model_exists = IsModelInCdimage(currently_selected_vehicle.value.model)
        spawn_vehicle_btn.Enabled = model_exists
        spawn_vehicle_btn.Description = model_exists and 'Spawn this saved vehicle.'
            or 'This model could not be found in the game files. Most likely because this is an addon vehicle '
                .. "and it's currently not streamed by the server."
        spawn_vehicle_btn.Label = '('
            .. tostring(GetDisplayNameFromVehicleModel(currently_selected_vehicle.value.model)):lower()
            .. ')'
    end

    selected_vehicle_menu.OnMenuClose = function(_)
        selected_vehicle_menu:RefreshIndex()
        delete_button_pressed_count = 0
        delete_vehicle_btn.Label = ''
        replace_button_pressed_count = 0
        replace_vehicle.Label = ''
    end

    selected_vehicle_menu.OnItemSelect = function(_, item, _index)
        if item == spawn_vehicle_btn then
            VehicleCommon.spawn_saved_vehicle(currently_selected_vehicle.value, currently_selected_vehicle.key:sub(5))
        elseif item == rename_vehicle then
            local new_name = Common.get_user_input('Enter a new name for this vehicle.', nil, 30)
            if new_name == nil or new_name == '' then
                Notify.error(Notification.error_message('InvalidInput'))
            else
                if Storage.save_vehicle_info('veh_' .. new_name, currently_selected_vehicle.value, false) then
                    DeleteResourceKvp(currently_selected_vehicle.key)
                    Notify.success('Your vehicle has successfully been renamed.')
                    update_menu_available_categories()
                    selected_vehicle_menu:GoBack()
                    currently_selected_vehicle = nil
                else
                    Notify.error(
                        'This name is already in use or something unknown failed. Contact the server owner if '
                            .. 'you believe something is wrong.'
                    )
                end
            end
        elseif item == replace_vehicle then
            if IsPedInAnyVehicle(PlayerPedId(), false) then
                if replace_button_pressed_count == 0 then
                    replace_button_pressed_count = 1
                    item.Label = 'Press again to confirm.'
                    Notify.alert('Are you sure you want to replace this vehicle? Press the button again to confirm.')
                else
                    replace_button_pressed_count = 0
                    item.Label = ''
                    VehicleCommon.save_vehicle(
                        currently_selected_vehicle.key:sub(5),
                        currently_selected_vehicle.value.Category
                    )
                    selected_vehicle_menu:CloseMenu()
                    Notify.success('Your saved vehicle has been replaced with your current vehicle.')
                end
            else
                Notify.error('You need to be in a vehicle before you can replace your old vehicle.')
            end
        elseif item == delete_vehicle_btn then
            if delete_button_pressed_count == 0 then
                delete_button_pressed_count = 1
                item.Label = 'Press again to confirm.'
                Notify.alert('Are you sure you want to delete this vehicle? Press the button again to confirm.')
            else
                delete_button_pressed_count = 0
                item.Label = ''
                DeleteResourceKvp(currently_selected_vehicle.key)
                update_menu_available_categories()
                selected_vehicle_menu:GoBack()
                Notify.success('Your saved vehicle has been deleted.')
            end
        end
        if item ~= delete_vehicle_btn then
            delete_button_pressed_count = 0
            delete_vehicle_btn.Label = ''
        end
        if item ~= replace_vehicle then
            replace_button_pressed_count = 0
            replace_vehicle.Label = ''
        end
    end

    -- Category preview icon follows the list selection.
    selected_vehicle_menu.OnListIndexChange = function(_, list_item, _old_index, new_selection_index, _item_index)
        if type(list_item.ItemData) == 'table' and list_item == set_category_btn then
            list_item.RightIcon = list_item.ItemData[new_selection_index + 1]
        end
    end

    -- Assign the vehicle to a category.
    selected_vehicle_menu.OnListItemSelect = function(_, list_item, list_index, _item_index)
        if list_item ~= set_category_btn then
            return
        end
        local name = list_item.ListItems[list_index + 1]

        if name == 'Create New' then
            local created = create_new_category_flow()
            if created == nil then
                return
            end
            name = created.Name
        end

        local info = currently_selected_vehicle.value
        info.Category = name

        if Storage.save_vehicle_info(currently_selected_vehicle.key, info, true) then
            Notify.success('Your vehicle was saved successfully.')
        else
            Notify.error('Your vehicle could not be saved. Reason unknown. :(')
        end

        Controller.CloseAllMenus()
        update_saved_vehicle_categories_menu()
        vehicle_category_menu:OpenMenu()
    end

    -- ------------------------------------------------------------------
    -- Unavailable vehicles: delete with the frontend-delete key
    -- ------------------------------------------------------------------

    unavailable_vehicles_menu:AddInstructionalButton(FRONTEND_DELETE, 'Delete Vehicle!')
    unavailable_vehicles_menu:AddButtonPressHandler(FRONTEND_DELETE, 'JUST_RELEASED', function(m, _control)
        if m:Size() > 0 then
            local index = m.CurrentIndex
            if index < m:Size() then
                local item = m:GetMenuItems()[index + 1]
                if item ~= nil and type(item.ItemData) == 'table' and item.ItemData.key ~= nil then
                    if item.Label == '~r~Are you sure?' then
                        Util.debug_log('Unavailable saved vehicle deleted: ' .. item.ItemData.key)
                        DeleteResourceKvp(item.ItemData.key)
                        unavailable_vehicles_menu:GoBack()
                        update_menu_available_categories()
                    else
                        item.Label = '~r~Are you sure?'
                    end
                else
                    Notify.error('Somehow this vehicle could not be found.')
                end
            else
                Notify.error("You somehow managed to trigger deletion of a menu item that doesn't exist, how...?")
            end
        else
            Notify.error('There are currrently no unavailable vehicles to delete!')
        end
    end, true)

    local function reset_are_you_sure()
        for _, item in ipairs(unavailable_vehicles_menu:GetMenuItems()) do
            if type(item.ItemData) == 'table' and item.ItemData.value ~= nil then
                item.Label = ('(%s)'):format(item.ItemData.value.name or '')
            end
        end
    end
    unavailable_vehicles_menu.OnMenuClose = function(_)
        reset_are_you_sure()
    end
    unavailable_vehicles_menu.OnIndexChange = function(_, _old_item, _new_item, _old_index, _new_index)
        reset_are_you_sure()
    end

    -- ------------------------------------------------------------------
    -- The type menu (entrypoint bound in the main tree)
    -- ------------------------------------------------------------------

    local save_vehicle_btn =
        Items.MenuItem.new('Save Current Vehicle', 'Save the vehicle you are currently sitting in.')
    save_vehicle_btn.LeftIcon = Items.Icon.CAR
    local class_button = Items.MenuItem.new('Vehicle Class', 'Selected a saved vehicle by its class.')
    class_button.Label = '→→→'
    local category_button = Items.MenuItem.new('Vehicle Category', 'Selected a saved vehicle by its custom category.')
    category_button.Label = '→→→'

    type_menu:AddMenuItem(save_vehicle_btn)
    type_menu:AddMenuItem(class_button)
    type_menu:AddMenuItem(category_button)

    type_menu.OnItemSelect = function(_, item, _index)
        if item == save_vehicle_btn then
            if IsPedInAnyVehicle(PlayerPedId(), false) then
                VehicleCommon.save_vehicle()
            else
                Notify.error('You are currently not in any vehicle. Please enter a vehicle before trying to save it.')
            end
        elseif item == class_button then
            update_menu_available_categories()
        elseif item == category_button then
            update_saved_vehicle_categories_menu()
        end
    end

    Controller.BindMenuItem(type_menu, class_menu, class_button)
    Controller.BindMenuItem(type_menu, vehicle_category_menu, category_button)

    self.menu = class_menu
    self.type_menu = type_menu
    return self
end

return SavedVehicles
