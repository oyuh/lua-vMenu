-- Port of vMenu/menus/WeaponLoadouts.cs: saving, equipping, renaming,
-- cloning, defaulting, replacing, and deleting weapon loadouts.

local Permissions = require('shared.permissions')
local Common = require('client.common')
local Notification = require('client.notify')
local UserDefaults = require('client.user_defaults')
local Weapons = require('client.weapons')
local Controller = require('menu.controller')
local Items = require('menu.items')
local Menu = require('menu.menu')

local Notify = Notification.Notify

local WeaponLoadouts = {}

local PREFIX = 'vmenu_string_saved_weapon_loadout_'

function WeaponLoadouts.create()
    local self = {}
    self.WeaponLoadoutsSetLoadoutOnRespawn = UserDefaults.get_bool('weaponLoadoutsSetLoadoutOnRespawn')

    -- The playerSpawned restore path (client/events.lua) calls this.
    function self.spawn_weapon_loadout(save_name, append, ignore_settings_and_perms, dont_notify)
        Weapons.spawn_weapon_loadout(save_name, append, ignore_settings_and_perms, dont_notify)
    end

    local menu = Menu.new(GetPlayerName(PlayerId()), 'weapon loadouts management')
    local saved_loadouts_menu = Menu.new('Saved Loadouts', 'saved weapon loadouts list')
    local manage_loadout_menu = Menu.new('Mange Loadout', 'Manage saved weapon loadout')

    Controller.AddSubmenu(menu, saved_loadouts_menu)
    Controller.AddSubmenu(saved_loadouts_menu, manage_loadout_menu)

    local saved_weapons = {}
    local selected_saved_loadout_name = ''

    local save_loadout = Items.MenuItem.new('Save Loadout', 'Save your current weapons into a new loadout slot.')
    local saved_loadouts_menu_btn = Items.MenuItem.new('Manage Loadouts', 'Manage saved weapon loadouts.')
    saved_loadouts_menu_btn.Label = '→→→'
    local enable_default_loadouts = Items.MenuCheckboxItem.new(
        'Restore Default Loadout On Respawn',
        "If you've set a loadout as default loadout, then your loadout will be equipped automatically whenever "
            .. 'you (re)spawn.',
        self.WeaponLoadoutsSetLoadoutOnRespawn
    )

    menu:AddMenuItem(save_loadout)
    menu:AddMenuItem(saved_loadouts_menu_btn)
    Controller.BindMenuItem(menu, saved_loadouts_menu, saved_loadouts_menu_btn)
    if Permissions.is_allowed('WLEquipOnRespawn') then
        menu:AddMenuItem(enable_default_loadouts)
        menu.OnCheckboxChange = function(_, _checkbox, _index, checked)
            self.WeaponLoadoutsSetLoadoutOnRespawn = checked
        end
    end

    local function refresh_saved_weapons_menu()
        local old_count = saved_loadouts_menu:Size()
        saved_loadouts_menu:ClearMenuItems(true)

        saved_weapons = Weapons.get_saved_weapons()
        local names = {}
        for name in pairs(saved_weapons) do
            names[#names + 1] = name
        end
        table.sort(names)

        for _, name in ipairs(names) do
            local btn = Items.MenuItem.new(name:gsub(PREFIX, ''), 'Click to manage this loadout.')
            btn.Label = '→→→'
            saved_loadouts_menu:AddMenuItem(btn)
            Controller.BindMenuItem(saved_loadouts_menu, manage_loadout_menu, btn)
        end

        local count = 0
        for _ in pairs(saved_weapons) do
            count = count + 1
        end
        if old_count > count then
            saved_loadouts_menu:RefreshIndex()
        end
    end

    local spawn_loadout = Items.MenuItem.new(
        'Equip Loadout',
        'Spawn this saved weapons loadout. This will remove all your current weapons and replace them with '
            .. 'this saved slot.'
    )
    local rename_loadout = Items.MenuItem.new('Rename Loadout', 'Rename this saved loadout.')
    local clone_loadout = Items.MenuItem.new('Clone Loadout', 'Clones this saved loadout to a new slot.')
    local set_default_loadout = Items.MenuItem.new(
        'Set As Default Loadout',
        'Set this loadout to be your default loadout for whenever you (re)spawn. This will override the '
            .. "'Restore Weapons' option inside the Misc Settings menu. You can toggle this option in the main "
            .. 'Weapon Loadouts menu.'
    )
    local replace_loadout = Items.MenuItem.new(
        '~r~Replace Loadout',
        '~r~This replaces this saved slot with the weapons that you currently have in your inventory. '
            .. 'This action can not be undone!'
    )
    local delete_loadout = Items.MenuItem.new(
        '~r~Delete Loadout',
        '~r~This will delete this saved loadout. This action can not be undone!'
    )

    if Permissions.is_allowed('WLEquip') then
        manage_loadout_menu:AddMenuItem(spawn_loadout)
    end
    manage_loadout_menu:AddMenuItem(rename_loadout)
    manage_loadout_menu:AddMenuItem(clone_loadout)
    manage_loadout_menu:AddMenuItem(set_default_loadout)
    manage_loadout_menu:AddMenuItem(replace_loadout)
    manage_loadout_menu:AddMenuItem(delete_loadout)

    menu.OnItemSelect = function(_, item, _index)
        if item == save_loadout then
            local name = Common.get_user_input('Enter a save name', nil, 30)
            if name == nil or name == '' then
                Notify.error(Notification.error_message('InvalidInput'))
            elseif saved_weapons[PREFIX .. name] ~= nil then
                Notify.error(Notification.error_message('SaveNameAlreadyExists'))
            elseif Weapons.save_weapon_loadout(PREFIX .. name) then
                Notify.success(('Your weapons have been saved as ~g~<C>%s</C>~s~.'):format(name))
            else
                Notify.error(Notification.error_message('UnknownError'))
            end
        end
    end

    manage_loadout_menu.OnItemSelect = function(_, item, _index)
        local weapons = saved_weapons[selected_saved_loadout_name]
        if weapons == nil then
            return
        end
        if item == spawn_loadout then
            Weapons.spawn_weapon_loadout(selected_saved_loadout_name, false, true, false)
        elseif item == rename_loadout or item == clone_loadout then
            local new_name =
                Common.get_user_input('Enter a save name', selected_saved_loadout_name:gsub(PREFIX, ''), 30)
            if new_name == nil or new_name == '' then
                Notify.error(Notification.error_message('InvalidInput'))
            elseif saved_weapons[PREFIX .. new_name] ~= nil then
                Notify.error(Notification.error_message('SaveNameAlreadyExists'))
            else
                local Json = require('shared.json_compat')
                SetResourceKvp(PREFIX .. new_name, #weapons == 0 and '[]' or Json.encode(weapons))
                Notify.success(
                    ('Your weapons loadout has been %s to ~g~<C>%s</C>~s~.'):format(
                        item == rename_loadout and 'renamed' or 'cloned',
                        new_name
                    )
                )
                if item == rename_loadout then
                    DeleteResourceKvp(selected_saved_loadout_name)
                end
                manage_loadout_menu:GoBack()
            end
        elseif item == set_default_loadout then
            SetResourceKvp('vmenu_string_default_loadout', selected_saved_loadout_name)
            Notify.success('This is now your default loadout.')
            item.LeftIcon = Items.Icon.TICK
        elseif item == replace_loadout then
            if replace_loadout.Label == 'Are you sure?' then
                replace_loadout.Label = ''
                Weapons.save_weapon_loadout(selected_saved_loadout_name)
                Notify.success('Your saved loadout has been replaced with your current weapons.')
            else
                replace_loadout.Label = 'Are you sure?'
            end
        elseif item == delete_loadout then
            if delete_loadout.Label == 'Are you sure?' then
                delete_loadout.Label = ''
                DeleteResourceKvp(selected_saved_loadout_name)
                manage_loadout_menu:GoBack()
                Notify.success('Your saved loadout has been deleted.')
            else
                delete_loadout.Label = 'Are you sure?'
            end
        end
    end

    manage_loadout_menu.OnMenuClose = function(_)
        delete_loadout.Label = ''
        rename_loadout.Label = ''
    end
    manage_loadout_menu.OnIndexChange = function(_, _old_item, _new_item, _old_index, _new_index)
        delete_loadout.Label = ''
        rename_loadout.Label = ''
    end

    saved_loadouts_menu.OnMenuOpen = function(_)
        refresh_saved_weapons_menu()
    end

    saved_loadouts_menu.OnItemSelect = function(_, item, _index)
        if saved_weapons[PREFIX .. item.Text] ~= nil then
            selected_saved_loadout_name = PREFIX .. item.Text
        else
            manage_loadout_menu:GoBack()
        end
    end

    manage_loadout_menu.OnMenuOpen = function(_)
        manage_loadout_menu:RefreshIndex()
        local kvp = GetResourceKvpString('vmenu_string_default_loadout')
        if kvp == nil or kvp == '' or kvp ~= selected_saved_loadout_name then
            set_default_loadout.LeftIcon = Items.Icon.NONE
        else
            set_default_loadout.LeftIcon = Items.Icon.TICK
        end
    end

    refresh_saved_weapons_menu()

    self.menu = menu
    return self
end

return WeaponLoadouts
