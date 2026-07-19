-- Port of vMenu/menus/PlayerAppearance.cs: ped model spawning (main/animals/
-- male/female/other/addon lists + spawn by name), the drawable/prop
-- customization menu, ped collections (gen9 collection-indexed variations),
-- saved peds (spawn/clone/rename/replace/delete), and walking styles.

local Config = require('shared.config')
local Permissions = require('shared.permissions')
local Common = require('client.common')
local PedCommon = require('client.ped_common')
local Notification = require('client.notify')
local UserDefaults = require('client.user_defaults')
local Storage = require('client.storage')
local State = require('client.state')
local Models = require('client.data.ped_appearance_models')
local Controller = require('menu.controller')
local Items = require('menu.items')
local Menu = require('menu.menu')

local Notify = Notification.Notify
local Subtitle = Notification.Subtitle

local PlayerAppearance = {}

local JUMP = 22 -- Control.Jump
local DUCK = 36 -- Control.Duck

local TEXTURE_NAMES = {
    'Head',
    'Mask / Facial Hair',
    'Hair Style / Color',
    'Hands / Upper Body',
    'Legs / Pants',
    'Bags / Parachutes',
    'Shoes',
    'Neck / Scarfs',
    'Shirt / Accessory',
    'Body Armor / Accessory 2',
    'Badges / Logos',
    'Shirt Overlay / Jackets',
}

local PROP_NAMES = {
    'Hats / Helmets', -- id 0
    'Glasses', -- id 1
    'Misc', -- id 2
    'Watches', -- id 6
    'Bracelets', -- id 7
}

-- Animals that die instantly out of water.
local WATER_ONLY_ANIMALS = {
    a_c_dolphin = true,
    a_c_fish = true,
    a_c_humpback = true,
    a_c_killerwhale = true,
    a_c_sharkhammer = true,
    a_c_sharktiger = true,
}

-- Locks the button when the ped is whitelist-restricted for this player.
local function check_ped_whitelist(ped_name, ped_btn)
    if State.whitelisted_peds[tostring(ped_name):lower()] ~= nil then
        if not Permissions.is_supplementary_allowed('PW' .. tostring(ped_name):lower()) then
            ped_btn.Enabled = false
            ped_btn.LeftIcon = Items.Icon.LOCK
            ped_btn.Description = 'Access to this has been restricted by the server owner.'
        end
    end
end
PlayerAppearance.check_ped_whitelist = check_ped_whitelist

-- The repeated "Selected texture: #x (of y)" description suffix.
local function texture_cycle_description(texture_number, texture_total)
    return ('← & → to select, ~r~enter~s~ to cycle textures. Selected texture: #%d (of %d).'):format(
        texture_number,
        texture_total
    )
end

local function show_visor_text(ped_handle)
    local component = GetPedPropIndex(ped_handle, 0) -- helmet index
    local texture = GetPedPropTextureIndex(ped_handle, 0)
    local comp_hash = GetHashNameForProp(ped_handle, 0, component, texture)
    if GetShopPedApparelVariantPropCount(comp_hash) > 0 then -- helmet has visor
        if not IsHelpMessageBeingDisplayed() then
            BeginTextCommandDisplayHelp('TWOSTRINGS')
            AddTextComponentSubstringPlayerName('Hold ~INPUT_SWITCH_VISOR~ to flip your helmet visor open or closed')
            AddTextComponentSubstringPlayerName('when on foot or on a motorcycle and when vMenu is closed.')
            EndTextCommandDisplayHelp(0, false, true, 6000)
        end
    end
end

function PlayerAppearance.create()
    local self = {}
    self.ClothingAnimationType = UserDefaults.get_int('clothingAnimationType')

    local player_name = Common.get_safe_player_name(GetPlayerName(PlayerId()))
    local menu = Menu.new(player_name, 'Player Appearance')
    local saved_peds_menu = Menu.new(player_name, 'Saved Peds')
    local ped_customization_menu = Menu.new(player_name, 'Customize Saved Ped')
    local ped_collections_menu = Menu.new(player_name, 'Ped Collections')
    local ped_collections_customization_menu = Menu.new(player_name, 'I get updated at runtime!')
    local spawn_peds_menu = Menu.new(player_name, 'Spawn Ped')
    local addon_peds_menu = Menu.new(player_name, 'Addon Peds')
    local main_peds_menu = Menu.new('Main Peds', 'Spawn A Ped')
    local animals_peds_menu = Menu.new('Animals', 'Spawn A Ped')
    local male_peds_menu = Menu.new('Male Peds', 'Spawn A Ped')
    local female_peds_menu = Menu.new('Female Peds', 'Spawn A Ped')
    local other_peds_menu = Menu.new('Other Peds', 'Spawn A Ped')

    Controller.AddSubmenu(menu, ped_customization_menu)
    Controller.AddSubmenu(menu, ped_collections_menu)
    Controller.AddSubmenu(ped_collections_menu, ped_collections_customization_menu)
    Controller.AddSubmenu(menu, saved_peds_menu)
    Controller.AddSubmenu(menu, spawn_peds_menu)
    Controller.AddSubmenu(spawn_peds_menu, addon_peds_menu)
    Controller.AddSubmenu(spawn_peds_menu, main_peds_menu)
    Controller.AddSubmenu(spawn_peds_menu, animals_peds_menu)
    Controller.AddSubmenu(spawn_peds_menu, male_peds_menu)
    Controller.AddSubmenu(spawn_peds_menu, female_peds_menu)
    Controller.AddSubmenu(spawn_peds_menu, other_peds_menu)

    -- item → drawable/prop id maps, rebuilt with the customization menus
    local drawables_menu_list_items = {}
    local props_menu_list_items = {}

    -- menu items
    local ped_customization = Items.MenuItem.new('Ped Customization', "Modify your ped's appearance.")
    ped_customization.Label = '→→→'
    local ped_collections = Items.MenuItem.new(
        'Ped Collections',
        "Modify your ped's appearance using collections, such as from the Base Game, Offical DLCs, and Custom "
            .. 'Collections.'
    )
    ped_collections.Label = '→→→'
    local save_current_ped = Items.MenuItem.new(
        'Save Ped',
        "Save your current ped. Note for the MP Male/Female peds this won't save most of their customization, just "
            .. "because that's impossible. Create those characters in the MP Character creator instead."
    )
    local saved_peds_btn = Items.MenuItem.new('Saved Peds', 'Edit, rename, clone, spawn or delete saved peds.')
    saved_peds_btn.Label = '→→→'
    local spawn_peds_btn = Items.MenuItem.new(
        'Spawn Peds',
        'Change ped model by selecting one from the list or by selecting an addon ped from the list.'
    )
    spawn_peds_btn.Label = '→→→'

    local spawn_by_name_btn = Items.MenuItem.new('Spawn By Name', "Spawn a ped by entering it's name manually.")
    local addon_peds_btn = Items.MenuItem.new('Addon Peds', 'Spawn a ped from the addon peds list.')
    addon_peds_btn.Label = '→→→'
    local main_peds_btn = Items.MenuItem.new('Main Peds', 'Select a new ped from the main player-peds list.')
    main_peds_btn.Label = '→→→'
    local animal_peds_btn = Items.MenuItem.new(
        'Animals',
        "Become an animal. ~r~Note this may crash your own or other players' game if you die as an animal, godmode "
            .. 'can NOT prevent this.'
    )
    animal_peds_btn.Label = '→→→'
    local male_peds_btn = Items.MenuItem.new('Male Peds', 'Select a male ped.')
    male_peds_btn.Label = '→→→'
    local female_peds_btn = Items.MenuItem.new('Female Peds', 'Select a female ped.')
    female_peds_btn.Label = '→→→'
    local other_peds_btn = Items.MenuItem.new('Other Peds', 'Select a ped.')
    other_peds_btn.Label = '→→→'

    local walkstyles =
        { 'Normal', 'Injured', 'Tough Guy', 'Femme', 'Gangster', 'Posh', 'Sexy', 'Business', 'Drunk', 'Hipster' }
    local walking_style = Items.MenuListItem.new(
        'Walking Style',
        walkstyles,
        0,
        'Change the walking style of your current ped. You need to re-apply this each time you change player model '
            .. 'or load a saved ped.'
    )

    local clothing_glow_type = Items.MenuListItem.new(
        'Illuminated Clothing Style',
        { 'On', 'Off', 'Fade', 'Flash' },
        self.ClothingAnimationType,
        "Set the style of the animation used on your player's illuminated clothing items."
    )

    menu:AddMenuItem(ped_customization)
    menu:AddMenuItem(ped_collections)
    menu:AddMenuItem(save_current_ped)
    menu:AddMenuItem(saved_peds_btn)
    menu:AddMenuItem(spawn_peds_btn)
    menu:AddMenuItem(walking_style)
    menu:AddMenuItem(clothing_glow_type)

    if Permissions.is_allowed('PACustomize') then
        Controller.BindMenuItem(menu, ped_customization_menu, ped_customization)
        Controller.BindMenuItem(menu, ped_collections_menu, ped_collections)
    else
        menu:RemoveMenuItem(ped_customization)
        menu:RemoveMenuItem(ped_collections)
    end

    -- always allowed
    Controller.BindMenuItem(menu, saved_peds_menu, saved_peds_btn)
    Controller.BindMenuItem(menu, spawn_peds_menu, spawn_peds_btn)

    -- -----------------------------------------------------------------------
    -- Saved peds
    -- -----------------------------------------------------------------------

    local selected_saved_ped_menu = Menu.new('Saved Ped', 'renameme')
    Controller.AddSubmenu(saved_peds_menu, selected_saved_ped_menu)
    local spawn_saved_ped = Items.MenuItem.new('Spawn Saved Ped', 'Spawn this saved ped.')
    local clone_saved_ped = Items.MenuItem.new('Clone Saved Ped', 'Clone this saved ped.')
    local rename_saved_ped = Items.MenuItem.new('Rename Saved Ped', 'Rename this saved ped.')
    rename_saved_ped.LeftIcon = Items.Icon.WARNING
    local replace_saved_ped = Items.MenuItem.new(
        '~r~Replace Saved Ped',
        'Replace this saved ped with your current ped. Note this can not be undone!'
    )
    replace_saved_ped.LeftIcon = Items.Icon.WARNING
    local delete_saved_ped =
        Items.MenuItem.new('~r~Delete Saved Ped', 'Delete this saved ped. Note this can not be undone!')
    delete_saved_ped.LeftIcon = Items.Icon.WARNING

    if not Permissions.is_allowed('PASpawnSaved') then
        spawn_saved_ped.Enabled = false
        spawn_saved_ped.RightIcon = Items.Icon.LOCK
        spawn_saved_ped.Description = 'You are not allowed to spawn saved peds.'
    end

    selected_saved_ped_menu:AddMenuItem(spawn_saved_ped)
    selected_saved_ped_menu:AddMenuItem(clone_saved_ped)
    selected_saved_ped_menu:AddMenuItem(rename_saved_ped)
    selected_saved_ped_menu:AddMenuItem(replace_saved_ped)
    selected_saved_ped_menu:AddMenuItem(delete_saved_ped)

    -- { key = kvp name (incl. ped_), value = PedInfo }
    local saved_ped = nil

    selected_saved_ped_menu.OnItemSelect = function(_, item, _index)
        if saved_ped == nil then
            return
        end
        if item == spawn_saved_ped then
            PedCommon.set_player_skin(saved_ped.value.model, saved_ped.value, true)
        elseif item == clone_saved_ped then
            local current_name = saved_ped.key:sub(5)
            local name = Common.get_user_input(('Enter a clone name (%s)'):format(current_name), current_name, 30)
            if name == nil or name == '' then
                Notify.error(Notification.error_message('InvalidSaveName'))
            else
                local existing = GetResourceKvpString('ped_' .. name)
                if existing ~= nil and existing ~= '' then
                    Notify.error(Notification.error_message('SaveNameAlreadyExists'))
                else
                    if Storage.save_ped_info('ped_' .. name, saved_ped.value, false) then
                        Notify.success(
                            ('Saved Ped has successfully been cloned. Clone name: ~g~<C>%s</C>~s~.'):format(name)
                        )
                    else
                        Notify.error(
                            Notification.error_message(
                                'UnknownError',
                                " Could not save your cloned ped. Don't worry, your original ped is unharmed."
                            )
                        )
                    end
                end
            end
        elseif item == rename_saved_ped then
            local current_name = saved_ped.key:sub(5)
            local name = Common.get_user_input(('Enter a new name for: %s'):format(current_name), current_name, 30)
            if name == nil or name == '' then
                Notify.error(Notification.error_message('InvalidSaveName'))
            else
                if 'ped_' .. name == saved_ped.key then
                    Notify.error(
                        "You need to choose a different name, you can't use the same name as your existing ped."
                    )
                    return
                end
                if Storage.save_ped_info('ped_' .. name, saved_ped.value, false) then
                    Notify.success(
                        ('Saved Ped has successfully been renamed. New ped name: ~g~<C>%s</C>~s~.'):format(name)
                    )
                    DeleteResourceKvp(saved_ped.key)
                    selected_saved_ped_menu.MenuSubtitle = name
                    saved_ped = { key = 'ped_' .. name, value = saved_ped.value }
                else
                    Notify.error(Notification.error_message('SaveNameAlreadyExists'))
                end
            end
        elseif item == replace_saved_ped then
            if item.Label == 'Are you sure?' then
                item.Label = ''
                local success = PedCommon.save_ped(saved_ped.key:sub(5), true)
                if not success then
                    Notify.error(
                        Notification.error_message(
                            'UnknownError',
                            " Could not save your replaced ped. Don't worry, your original ped is unharmed."
                        )
                    )
                else
                    Notify.success('Your saved ped has successfully been replaced.')
                    saved_ped = { key = saved_ped.key, value = Storage.get_saved_ped_info(saved_ped.key) }
                end
            else
                item.Label = 'Are you sure?'
            end
        elseif item == delete_saved_ped then
            if item.Label == 'Are you sure?' then
                DeleteResourceKvp(saved_ped.key)
                Notify.success('Your saved ped has been deleted.')
                selected_saved_ped_menu:GoBack()
            else
                item.Label = 'Are you sure?'
            end
        end
    end

    local function reset_saved_peds_menu(refresh_index)
        for _, item in ipairs(selected_saved_ped_menu:GetMenuItems()) do
            item.Label = ''
        end
        if refresh_index then
            selected_saved_ped_menu:RefreshIndex()
        end
    end

    selected_saved_ped_menu.OnIndexChange = function(_, _new_item, _old_item, _old_index, _new_index)
        reset_saved_peds_menu(false)
    end
    selected_saved_ped_menu.OnMenuOpen = function(_)
        reset_saved_peds_menu(true)
    end

    local function update_saved_peds_menu()
        local size = saved_peds_menu:Size()
        local saved_peds = Storage.get_saved_peds()

        for key, info in pairs(saved_peds) do
            local exists = false
            for _, item in ipairs(saved_peds_menu:GetMenuItems()) do
                if type(item.ItemData) ~= 'table' or item.ItemData.key == nil then
                    exists = true
                elseif item.ItemData.key == key then
                    exists = true
                end
                if exists then
                    break
                end
            end
            if size < 1 or not exists then
                local btn = Items.MenuItem.new(key:sub(5), 'Click to manage this saved ped.')
                btn.Label = '→→→'
                btn.ItemData = { key = key, value = info }
                saved_peds_menu:AddMenuItem(btn)
                Controller.BindMenuItem(saved_peds_menu, selected_saved_ped_menu, btn)
            end
        end

        if saved_peds_menu:Size() > 0 then
            -- copy: RemoveMenuItem mutates the list while we iterate
            local current_items = {}
            for _, item in ipairs(saved_peds_menu:GetMenuItems()) do
                current_items[#current_items + 1] = item
            end
            for _, item in ipairs(current_items) do
                if type(item.ItemData) == 'table' and item.ItemData.key ~= nil then
                    if saved_peds[item.ItemData.key] == nil then
                        saved_peds_menu:RemoveMenuItem(item)
                    else
                        -- keep the saved ped data up to date for this item
                        item.ItemData = { key = item.ItemData.key, value = saved_peds[item.ItemData.key] }
                    end
                end
            end
        end

        if saved_peds_menu:Size() > 0 then
            saved_peds_menu:SortMenuItems(function(a, b)
                return a.Text:lower() < b.Text:lower()
            end)
        end

        -- refresh index only if the size of the menu has changed
        if size ~= saved_peds_menu:Size() then
            saved_peds_menu:RefreshIndex()
        end
    end

    saved_peds_menu.OnMenuOpen = function(_)
        update_saved_peds_menu()
    end

    saved_peds_menu.OnItemSelect = function(_, item, _index)
        if type(item.ItemData) ~= 'table' or item.ItemData.key == nil then
            return
        end
        saved_ped = item.ItemData
        selected_saved_ped_menu.MenuSubtitle = item.Text
    end

    -- -----------------------------------------------------------------------
    -- Spawn peds
    -- -----------------------------------------------------------------------

    if next(State.addon_peds) ~= nil and Permissions.is_allowed('PAAddonPeds') then
        spawn_peds_menu:AddMenuItem(addon_peds_btn)
        Controller.BindMenuItem(spawn_peds_menu, addon_peds_menu, addon_peds_btn)

        local addons = {}
        for name, hash in pairs(State.addon_peds) do
            addons[#addons + 1] = { name = name, hash = hash }
        end
        table.sort(addons, function(a, b)
            return a.name:lower() < b.name:lower()
        end)

        for _, ped in ipairs(addons) do
            local label = GetLabelText(ped.name)
            if label == nil or label == '' or label == 'NULL' then
                label = ped.name
            end

            local ped_btn = Items.MenuItem.new(ped.name, 'Click to spawn this model.')
            ped_btn.Label = ('(%s)'):format(label)

            check_ped_whitelist(ped.name, ped_btn)

            if not IsModelInCdimage(ped.hash) or not IsModelAPed(ped.hash) then
                ped_btn.Enabled = false
                ped_btn.LeftIcon = Items.Icon.LOCK
                ped_btn.Description = 'This ped is not (correctly) streamed. If you are the server owner, please '
                    .. 'ensure that the ped name and model are valid!'
            else
                check_ped_whitelist(ped.name, ped_btn)
            end
            addon_peds_menu:AddMenuItem(ped_btn)
        end

        addon_peds_menu.OnItemSelect = function(_, item, _index)
            PedCommon.set_player_skin(GetHashKey(item.Text), { version = -1 }, true)
        end
    end

    if Permissions.is_allowed('PASpawnNew') then
        spawn_peds_menu:AddMenuItem(spawn_by_name_btn)
        spawn_peds_menu:AddMenuItem(main_peds_btn)
        spawn_peds_menu:AddMenuItem(animal_peds_btn)
        spawn_peds_menu:AddMenuItem(male_peds_btn)
        spawn_peds_menu:AddMenuItem(female_peds_btn)
        spawn_peds_menu:AddMenuItem(other_peds_btn)

        Controller.BindMenuItem(spawn_peds_menu, main_peds_menu, main_peds_btn)
        if Config.get_bool('vmenu_enable_animals_spawn_menu') then
            Controller.BindMenuItem(spawn_peds_menu, animals_peds_menu, animal_peds_btn)
        else
            animal_peds_btn.Enabled = false
            animal_peds_btn.Description = 'This is disabled by the server owner, probably for a good reason because '
                .. 'animals quite often crash the game.'
            animal_peds_btn.LeftIcon = Items.Icon.LOCK
        end

        Controller.BindMenuItem(spawn_peds_menu, male_peds_menu, male_peds_btn)
        Controller.BindMenuItem(spawn_peds_menu, female_peds_menu, female_peds_btn)
        Controller.BindMenuItem(spawn_peds_menu, other_peds_menu, other_peds_btn)

        local function fill_ped_menu(target_menu, models, order, description)
            for _, model in ipairs(order) do
                local ped_btn = Items.MenuItem.new(model, description)
                ped_btn.Label = ('(%s)'):format(models[model])
                check_ped_whitelist(model, ped_btn)
                target_menu:AddMenuItem(ped_btn)
            end
        end

        fill_ped_menu(
            animals_peds_menu,
            Models.animal_models,
            Models.animal_models_order,
            'Click to spawn this animal.'
        )
        fill_ped_menu(main_peds_menu, Models.main_models, Models.main_models_order, 'Click to spawn this ped.')
        fill_ped_menu(male_peds_menu, Models.male_models, Models.male_models_order, 'Click to spawn this ped.')
        fill_ped_menu(female_peds_menu, Models.female_models, Models.female_models_order, 'Click to spawn this ped.')
        fill_ped_menu(other_peds_menu, Models.other_peds, Models.other_peds_order, 'Click to spawn this ped.')

        local function filter_menu(m, _control)
            local input = Common.get_user_input('Filter by ped model name, leave this empty to reset the filter')
            if input ~= nil and input ~= '' then
                local needle = input:lower()
                m:FilterMenuItems(function(mb)
                    return tostring(mb.Label):lower():find(needle, 1, true) ~= nil
                        or tostring(mb.Text):lower():find(needle, 1, true) ~= nil
                end)
                Subtitle.custom('Filter applied.')
            else
                m:ResetFilter()
                Subtitle.custom('Filter cleared.')
            end
        end

        local function reset_menu_filter(m)
            m:ResetFilter()
        end

        other_peds_menu.OnMenuClose = reset_menu_filter
        male_peds_menu.OnMenuClose = reset_menu_filter
        female_peds_menu.OnMenuClose = reset_menu_filter

        for _, filterable in ipairs({ other_peds_menu, male_peds_menu, female_peds_menu }) do
            filterable:AddInstructionalButton(JUMP, 'Filter List')
            filterable:AddButtonPressHandler(JUMP, 'JUST_RELEASED', filter_menu, true)
        end

        local function spawn_ped(m, item, _index)
            local model = GetHashKey(item.Text)
            if m == animals_peds_menu and not IsEntityInWater(PlayerPedId()) then
                if WATER_ONLY_ANIMALS[item.Text] then
                    Notify.error(
                        'This animal can only be spawned when you are in water, otherwise you will die immediately.'
                    )
                    return
                end
            end

            if IsModelInCdimage(model) then
                if m == animals_peds_menu then
                    -- animals have their own weapons which you can't normally
                    -- select; clear ours to force that weapon to be equipped
                    RemoveAllPedWeapons(PlayerPedId(), true)
                    PedCommon.set_player_skin(model, { version = -1 }, false)
                    Wait(1000)
                    SetPedComponentVariation(PlayerPedId(), 0, 0, 0, 0)
                    Wait(1000)
                    SetPedComponentVariation(PlayerPedId(), 0, 0, 1, 0)
                    Wait(1000)
                    SetPedDefaultComponentVariation(PlayerPedId())
                else
                    PedCommon.set_player_skin(model, { version = -1 }, true)
                end
            else
                Notify.error(Notification.error_message('InvalidModel'))
            end
        end

        main_peds_menu.OnItemSelect = spawn_ped
        male_peds_menu.OnItemSelect = spawn_ped
        female_peds_menu.OnItemSelect = spawn_ped
        animals_peds_menu.OnItemSelect = spawn_ped
        other_peds_menu.OnItemSelect = spawn_ped

        spawn_peds_menu.OnItemSelect = function(_, item, _index)
            if item == spawn_by_name_btn then
                local model = Common.get_user_input('Ped Model Name', nil, 30)
                if model ~= nil and model ~= '' then
                    PedCommon.set_player_skin(model, { version = -1 }, true)
                else
                    Notify.error(Notification.error_message('InvalidInput'))
                end
            end
        end
    end

    -- -----------------------------------------------------------------------
    -- Customization menu (drawables & props)
    -- -----------------------------------------------------------------------

    local function refresh_customization_menu()
        drawables_menu_list_items = {}
        props_menu_list_items = {}
        ped_customization_menu:ClearMenuItems()

        local ped = PlayerPedId()

        for drawable = 0, 11 do
            local current_drawable = GetPedDrawableVariation(ped, drawable)
            local max_variations = GetNumberOfPedDrawableVariations(ped, drawable)

            if max_variations > 0 then
                local drawable_textures_list = {}
                for i = 1, max_variations do
                    drawable_textures_list[#drawable_textures_list + 1] = ('Drawable #%d (of %d)'):format(
                        i,
                        max_variations
                    )
                end

                local drawable_textures = Items.MenuListItem.new(
                    TEXTURE_NAMES[drawable + 1],
                    drawable_textures_list,
                    current_drawable,
                    (
                        'Use ← & → to select a ~o~%s Variation~s~, press ~r~enter~s~ to cycle through the available '
                        .. 'textures.'
                    ):format(TEXTURE_NAMES[drawable + 1])
                )
                drawables_menu_list_items[drawable_textures] = drawable
                ped_customization_menu:AddMenuItem(drawable_textures)
            end
        end

        for tmp_prop = 0, 4 do
            local real_prop = tmp_prop > 2 and tmp_prop + 3 or tmp_prop
            local current_prop = GetPedPropIndex(ped, real_prop)
            local max_prop_variations = GetNumberOfPedPropDrawableVariations(ped, real_prop)

            if max_prop_variations > 0 then
                local prop_textures_list = { ('Prop #1 (of %d)'):format(max_prop_variations + 1) }
                for i = 1, max_prop_variations do
                    prop_textures_list[#prop_textures_list + 1] = ('Prop #%d (of %d)'):format(
                        i + 1,
                        max_prop_variations + 1
                    )
                end

                local prop_textures = Items.MenuListItem.new(
                    PROP_NAMES[tmp_prop + 1],
                    prop_textures_list,
                    current_prop + 1,
                    (
                        'Use ← & → to select a ~o~%s Variation~s~, press ~r~enter~s~ to cycle through the available '
                        .. 'textures.'
                    ):format(PROP_NAMES[tmp_prop + 1])
                )
                props_menu_list_items[prop_textures] = real_prop
                ped_customization_menu:AddMenuItem(prop_textures)
            end
        end
        ped_customization_menu:RefreshIndex()
    end
    self.refresh_customization_menu = refresh_customization_menu

    local function change_list_item(item, new_list_index)
        local ped = PlayerPedId()
        if drawables_menu_list_items[item] ~= nil then
            local drawable_id = drawables_menu_list_items[item]
            SetPedComponentVariation(ped, drawable_id, new_list_index, 0, 0)
        elseif props_menu_list_items[item] ~= nil then
            local prop_id = props_menu_list_items[item]
            if new_list_index == 0 then
                SetPedPropIndex(ped, prop_id, new_list_index - 1, 0, false)
                ClearPedProp(ped, prop_id)
            else
                SetPedPropIndex(ped, prop_id, new_list_index - 1, 0, true)
            end
            if prop_id == 0 then
                show_visor_text(ped)
            end
        end
    end

    ped_customization_menu.OnListIndexChange = function(_, item, _old_list_index, new_list_index, _item_index)
        change_list_item(item, new_list_index)
    end

    ped_customization_menu.OnListItemSelect = function(_, item, list_index, _item_index)
        local ped = PlayerPedId()
        local is_drawable = drawables_menu_list_items[item] ~= nil

        if IsControlPressed(0, DUCK) then
            local user_input =
                Common.get_user_input(('Enter %s ID'):format(is_drawable and 'Drawable' or 'Prop'), nil, 5)
            local drawable_id = tonumber(user_input or '')
            if
                user_input == nil
                or user_input == ''
                or drawable_id == nil
                or drawable_id < 1
                or drawable_id > item:ItemsCount()
            then
                Notify.error('Invalid input')
                return
            end
            drawable_id = math.tointeger(drawable_id) - 1
            item.ListIndex = drawable_id
            change_list_item(item, drawable_id)
            return
        end

        if is_drawable then
            local current_drawable_id = drawables_menu_list_items[item]
            local current_texture_index = GetPedTextureVariation(ped, current_drawable_id)
            local max_drawable_textures = GetNumberOfPedTextureVariations(ped, current_drawable_id, list_index) - 1

            if current_texture_index == -1 then
                current_texture_index = 0
            end

            local new_texture = current_texture_index < max_drawable_textures and current_texture_index + 1 or 0
            SetPedComponentVariation(ped, current_drawable_id, list_index, new_texture, 0)
        else -- prop
            local current_prop_index = props_menu_list_items[item]
            local current_prop_variation_index = GetPedPropIndex(ped, current_prop_index)
            local current_prop_texture_variation = GetPedPropTextureIndex(ped, current_prop_index)
            local max_prop_texture_variations = GetNumberOfPedPropTextureVariations(
                ped,
                current_prop_index,
                current_prop_variation_index
            ) - 1

            local new_prop_texture_variation_index = current_prop_texture_variation < max_prop_texture_variations
                    and current_prop_texture_variation + 1
                or 0
            SetPedPropIndex(
                ped,
                current_prop_index,
                current_prop_variation_index,
                new_prop_texture_variation_index,
                true
            )
        end
    end

    -- -----------------------------------------------------------------------
    -- Collections menus
    -- -----------------------------------------------------------------------

    local function refresh_collections_menu()
        drawables_menu_list_items = {}
        props_menu_list_items = {}
        ped_collections_menu:ClearMenuItems()

        local ped = PlayerPedId()
        local collections_count = GetPedCollectionsCount(ped)

        -- in reverse so newest are at the top
        for i = collections_count - 1, 0, -1 do
            local collection_name = i == 0 and 'Base Collection' or GetPedCollectionName(ped, i)
            local collection_item = Items.MenuItem.new(
                collection_name,
                ('Customize your ped using the "%s" collection.'):format(collection_name)
            )
            collection_item.ItemData = collection_name
            collection_item.Label = ('(#%d)'):format(i)

            ped_collections_menu:AddMenuItem(collection_item)
            Controller.BindMenuItem(ped_collections_menu, ped_collections_customization_menu, collection_item)
        end

        ped_collections_menu:RefreshIndex()
    end
    self.refresh_collections_menu = refresh_collections_menu

    local function refresh_collections_drawables(collection_name)
        ped_collections_customization_menu:ClearMenuItems()
        ped_collections_customization_menu.MenuSubtitle = collection_name

        local ped = PlayerPedId()

        if collection_name == 'Base Collection' then
            collection_name = ''
        end

        for drawable = 0, 11 do
            local total_variations = GetNumberOfPedCollectionDrawableVariations(ped, drawable, collection_name)

            if total_variations > 0 then
                local suffix_text
                local current_local_index
                local drawable_textures_list = {}
                local current_drawable_global_id = GetPedDrawableVariation(ped, drawable)
                local current_collection = GetPedCollectionNameFromDrawable(ped, drawable, current_drawable_global_id)

                for i = 0, total_variations - 1 do
                    local is_valid = IsPedCollectionComponentVariationValid(ped, drawable, collection_name, i, 0)
                        and not IsPedCollectionComponentVariationGen9Exclusive(ped, drawable, collection_name, i)
                    drawable_textures_list[#drawable_textures_list + 1] = ('Drawable #%d%s (of %d)'):format(
                        i + 1,
                        not is_valid and ' (Invalid)' or '',
                        total_variations
                    )
                end

                local current_texture_id = GetPedTextureVariation(ped, drawable)

                if current_collection == collection_name then
                    current_local_index =
                        GetPedCollectionLocalIndexFromDrawable(ped, drawable, current_drawable_global_id)
                    suffix_text = ('Selected texture: #%d (of %d).'):format(
                        current_texture_id + 1,
                        GetNumberOfPedCollectionTextureVariations(ped, drawable, collection_name, current_local_index)
                    )
                else
                    drawable_textures_list[#drawable_textures_list + 1] = ('None Selected (of %d)'):format(
                        total_variations
                    )
                    current_local_index = #drawable_textures_list - 1
                    suffix_text = 'Current selection not part collection.'
                end

                local item = Items.MenuListItem.new(
                    TEXTURE_NAMES[drawable + 1],
                    drawable_textures_list,
                    current_local_index,
                    ('← & → to select, ~r~enter~s~ to cycle textures. %s'):format(suffix_text)
                )
                item.ItemData = { current_drawable_global_id, current_texture_id, collection_name }

                drawables_menu_list_items[item] = drawable
                ped_collections_customization_menu:AddMenuItem(item)
            end
        end

        for tmp_prop = 0, 4 do
            local real_prop = tmp_prop > 2 and tmp_prop + 3 or tmp_prop
            local total_variations = GetNumberOfPedCollectionPropDrawableVariations(ped, real_prop, collection_name)

            if total_variations > 0 then
                local suffix_text
                local current_local_index
                local current_prop_global_id = GetPedPropIndex(ped, real_prop)
                local prop_textures_list = { ('None Selected (of %d)'):format(total_variations) }
                local current_collection = GetPedCollectionNameFromProp(ped, real_prop, current_prop_global_id)

                for i = 0, total_variations - 1 do
                    prop_textures_list[#prop_textures_list + 1] = ('Prop #%d (of %d)'):format(i + 1, total_variations)
                end

                local current_texture_id = GetPedPropTextureIndex(ped, real_prop)

                if current_collection == collection_name then
                    current_local_index = GetPedCollectionLocalIndexFromProp(ped, real_prop, current_prop_global_id)
                    suffix_text = ('Selected texture: #%d (of %d).'):format(
                        current_texture_id + 1,
                        GetNumberOfPedCollectionPropTextureVariations(
                            ped,
                            real_prop,
                            collection_name,
                            current_local_index
                        )
                    )
                else
                    current_local_index = -1
                    suffix_text = 'Current selection not part collection.'
                end

                local prop_textures = Items.MenuListItem.new(
                    PROP_NAMES[tmp_prop + 1],
                    prop_textures_list,
                    current_local_index + 1,
                    ('← & → to select, ~r~enter~s~ to cycle textures. %s'):format(suffix_text)
                )
                prop_textures.ItemData = { current_prop_global_id, current_texture_id, collection_name }

                props_menu_list_items[prop_textures] = real_prop
                ped_collections_customization_menu:AddMenuItem(prop_textures)
            end
        end

        ped_collections_customization_menu:RefreshIndex()
    end

    ped_collections_customization_menu.OnListIndexChange = function(_, item, _old_list_index, new_list_index, _idx)
        if type(item.ItemData) ~= 'table' or #item.ItemData ~= 3 then
            return
        end
        local original_item_id = item.ItemData[1]
        local original_texture_id = item.ItemData[2]
        local collection_name = item.ItemData[3]
        local ped = PlayerPedId()

        if drawables_menu_list_items[item] ~= nil then
            local current_drawable_id = drawables_menu_list_items[item]
            local is_valid = IsPedCollectionComponentVariationValid(
                ped,
                current_drawable_id,
                collection_name,
                new_list_index,
                0
            ) and not IsPedCollectionComponentVariationGen9Exclusive(
                ped,
                current_drawable_id,
                collection_name,
                new_list_index
            )

            if is_valid then
                local max_drawable_textures =
                    GetNumberOfPedCollectionTextureVariations(ped, current_drawable_id, collection_name, new_list_index)
                SetPedCollectionComponentVariation(ped, current_drawable_id, collection_name, new_list_index, 0, 0)
                item.Description = texture_cycle_description(
                    GetPedTextureVariation(ped, current_drawable_id) + 1,
                    max_drawable_textures
                )
            elseif item.ListItems[new_list_index + 1]:sub(1, 4) == 'None' then
                SetPedComponentVariation(ped, current_drawable_id, original_item_id, original_texture_id, 0)
                item.Description =
                    '← & → to select, ~r~enter~s~ to cycle textures. Current selection not part collection.'
            else
                item.Description =
                    '← & → to select, ~r~enter~s~ to cycle textures. Selection is invalid (broken, Gen9, etc.)'
            end
        elseif props_menu_list_items[item] ~= nil then
            local prop_id = props_menu_list_items[item]

            if item.ListItems[new_list_index + 1]:sub(1, 4) == 'None' then
                SetPedPropIndex(ped, prop_id, original_item_id, original_texture_id, false)
                item.Description =
                    '← & → to select, ~r~enter~s~ to cycle textures. Current selection not part collection.'
            else
                local max_drawable_textures =
                    GetNumberOfPedCollectionPropTextureVariations(ped, prop_id, collection_name, new_list_index - 1)
                SetPedCollectionPropIndex(ped, prop_id, collection_name, new_list_index - 1, 0, true)
                item.Description =
                    texture_cycle_description(GetPedPropTextureIndex(ped, prop_id) + 1, max_drawable_textures)
            end

            if prop_id == 0 then
                show_visor_text(ped)
            end
        end
    end

    ped_collections_customization_menu.OnListItemSelect = function(_, item, list_index, _item_index)
        if
            type(item.ItemData) ~= 'table'
            or #item.ItemData ~= 3
            or item.ListItems[list_index + 1]:sub(1, 4) == 'None'
        then
            return
        end

        local collection_name = item.ItemData[3]
        local ped = PlayerPedId()

        if drawables_menu_list_items[item] ~= nil then
            local current_drawable_id = drawables_menu_list_items[item]
            local is_valid = IsPedCollectionComponentVariationValid(
                ped,
                current_drawable_id,
                collection_name,
                list_index,
                0
            ) and not IsPedCollectionComponentVariationGen9Exclusive(
                ped,
                current_drawable_id,
                collection_name,
                list_index
            )

            if not is_valid then
                return
            end

            local current_texture_index = GetPedTextureVariation(ped, current_drawable_id)
            local max_drawable_textures = GetNumberOfPedCollectionTextureVariations(
                ped,
                current_drawable_id,
                collection_name,
                list_index
            ) - 1

            if current_texture_index == -1 then
                current_texture_index = 0
            end

            local new_texture = current_texture_index < max_drawable_textures and current_texture_index + 1 or 0
            SetPedCollectionComponentVariation(ped, current_drawable_id, collection_name, list_index, new_texture, 0)
            item.Description = texture_cycle_description(new_texture + 1, max_drawable_textures + 1)
        elseif props_menu_list_items[item] ~= nil then
            local current_prop_id = props_menu_list_items[item]
            local current_prop_texture_variation = GetPedPropTextureIndex(ped, current_prop_id)
            local max_prop_texture_variations =
                GetNumberOfPedCollectionPropTextureVariations(ped, current_prop_id, collection_name, list_index - 1)
            local new_prop_texture_variation_index = current_prop_texture_variation + 1 < max_prop_texture_variations
                    and current_prop_texture_variation + 1
                or 0

            SetPedCollectionPropIndex(
                ped,
                current_prop_id,
                collection_name,
                list_index - 1,
                new_prop_texture_variation_index,
                true
            )
            item.Description =
                texture_cycle_description(new_prop_texture_variation_index + 1, max_prop_texture_variations)
        end
    end

    -- Upstream checks `ItemData is Tuple<int,int,string>` here, but the
    -- collection buttons carry a plain string, so the handler never fires
    -- and the submenu stays empty. Ported to the obvious intent instead.
    ped_collections_menu.OnItemSelect = function(_, item, _index)
        if type(item.ItemData) == 'string' then
            refresh_collections_drawables(item.ItemData)
        end
    end

    -- -----------------------------------------------------------------------
    -- Main menu handlers
    -- -----------------------------------------------------------------------

    menu.OnListItemSelect = function(_, item, list_index, _item_index)
        if item == walking_style then
            PedCommon.set_walking_style(walkstyles[list_index + 1])
        end
        if item == clothing_glow_type then
            self.ClothingAnimationType = item.ListIndex
        end
    end

    menu.OnItemSelect = function(_, item, _index)
        if item == ped_customization then
            refresh_customization_menu()
        end
        if item == ped_collections then
            refresh_collections_menu()
        elseif item == save_current_ped then
            if PedCommon.save_ped() then
                Notify.success('Successfully saved your new ped.')
            else
                Notify.error('Could not save your current ped, does that save name already exist?')
            end
        end
    end

    self.menu = menu
    self.PedCustomizationMenu = ped_customization_menu
    self.PedCollectionsMenu = ped_collections_menu
    self.PedCollectionsCustomizationMenu = ped_collections_customization_menu
    self.SavedPedsMenu = saved_peds_menu
    self.SelectedSavedPedMenu = selected_saved_ped_menu
    self.SpawnPedsMenu = spawn_peds_menu
    self.AddonPedsMenu = addon_peds_menu
    self.MainPedsMenu = main_peds_menu
    self.AnimalsPedsMenu = animals_peds_menu
    self.MalePedsMenu = male_peds_menu
    self.FemalePedsMenu = female_peds_menu
    self.OtherPedsMenu = other_peds_menu
    return self
end

return PlayerAppearance
