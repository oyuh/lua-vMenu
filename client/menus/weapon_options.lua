-- Port of vMenu/menus/WeaponOptions.cs: get/remove/refill weapons, per-weapon
-- menus (components, tints) grouped into the 8 weapon categories, addon
-- weapons, and the parachute options submenu.

local Permissions = require('shared.permissions')
local Common = require('client.common')
local Notification = require('client.notify')
local UserDefaults = require('client.user_defaults')
local Weapons = require('client.weapons')
local WeaponsData = require('client.data.weapons_data')
local Controller = require('menu.controller')
local Items = require('menu.items')
local Menu = require('menu.menu')

local Notify = Notification.Notify
local Subtitle = Notification.Subtitle

local WeaponOptions = {}

-- GetWeapontypeGroup hashes → category menus.
local GROUP_RIFLES = 970310034
local GROUP_HANDGUNS = 416676503
local GROUP_STUNGUN = 690389602
local GROUP_SHOTGUNS = 860033945
local GROUP_SMGS = 3337201093
local GROUP_LMGS = 1159398588
local GROUP_THROWABLES = 1548507267
local GROUP_FIRE_EXTINGUISHER = 4257178988
local GROUP_JERRY_CAN = 1595662460
local GROUP_MELEE = 3566412244
local GROUP_KNUCKLE_DUSTER = 2685387236
local GROUP_HEAVY = 2725924767
local GROUP_SNIPERS = 3082541095

-- Shared per-weapon submenu builder (weapons + addon weapons differ only in
-- the whitelist/permission checks the caller applies to the opener button).
local function build_weapon_menu(weapon)
    local ped = PlayerPedId()
    local weapon_menu = Menu.new('Weapon Options', weapon.name)
    weapon_menu.ShowWeaponStatsPanel = true
    local stats = Weapons.get_hud_stats(weapon.hash)
    weapon_menu:SetWeaponStats(stats.damage / 100, stats.speed / 100, stats.accuracy / 100, stats.range / 100)

    local weapon_item = Items.MenuItem.new(weapon.name, ('Open the options for ~y~%s~s~.'):format(weapon.name))
    weapon_item.Label = '→→→'
    weapon_item.LeftIcon = Items.Icon.GUN
    weapon_item.ItemData = { is_weapon_stats = true, stats = stats }

    local get_or_remove = Items.MenuItem.new('Equip/Remove Weapon', 'Add or remove this weapon to/form your inventory.')
    get_or_remove.LeftIcon = Items.Icon.GUN
    weapon_menu:AddMenuItem(get_or_remove)
    if not Permissions.is_allowed('WPSpawn') then
        get_or_remove.Enabled = false
        get_or_remove.Description = 'You do not have permission to use this option.'
        get_or_remove.LeftIcon = Items.Icon.LOCK
    end

    local fill_ammo = Items.MenuItem.new('Re-fill Ammo', 'Get max ammo for this weapon.')
    fill_ammo.LeftIcon = Items.Icon.AMMO
    weapon_menu:AddMenuItem(fill_ammo)

    local tints = {}
    if weapon.name:find(' Mk II', 1, true) or weapon.spawn_name:find('MK_II', 1, true) then
        for _, tint_name in ipairs(WeaponsData.weapon_tints_mk2_order) do
            tints[#tints + 1] = tint_name
        end
    else
        for _, tint_name in ipairs(WeaponsData.weapon_tints_order) do
            tints[#tints + 1] = tint_name
        end
    end
    local weapon_tints = Items.MenuListItem.new('Tints', tints, 0, 'Select a tint for your weapon.')
    weapon_menu:AddMenuItem(weapon_tints)

    -- Component items (in discovery order).
    local component_items = {} -- [item] = localized component name
    for _, component_name in ipairs(weapon.component_names or {}) do
        local comp_item = Items.MenuItem.new(component_name, 'Click to equip or remove this component.')
        component_items[comp_item] = component_name
        weapon_menu:AddMenuItem(comp_item)
    end

    weapon_menu.OnListIndexChange = function(_, item, _old_index, new_index, _item_index)
        if item == weapon_tints then
            if HasPedGotWeapon(ped, weapon.hash, false) then
                SetPedWeaponTintIndex(ped, weapon.hash, new_index)
            else
                Notify.error('You need to get the weapon first!')
            end
        end
    end

    local function equip_weapon_component(weapon_hash, component_hash)
        local ammo = GetAmmoInPedWeapon(ped, weapon_hash)
        local clip_ammo = GetMaxAmmoInClip(ped, weapon_hash, false)
        GiveWeaponComponentToPed(ped, weapon_hash, component_hash)
        SetAmmoInClip(ped, weapon_hash, clip_ammo)
        SetPedAmmo(ped, weapon_hash, ammo)
    end

    weapon_menu.OnItemSelect = function(_, item, _index)
        ped = PlayerPedId()
        local hash = weapon.hash
        SetCurrentPedWeapon(ped, hash, true)
        if item == get_or_remove then
            if HasPedGotWeapon(ped, hash, false) then
                RemoveWeaponFromPed(ped, hash)
                Subtitle.custom('Weapon removed.')
            else
                GiveWeaponToPed(ped, hash, Weapons.get_max_ammo(hash), false, true)
                Subtitle.custom('Weapon added.')
            end
        elseif item == fill_ammo then
            if HasPedGotWeapon(ped, hash, false) then
                SetPedAmmo(ped, hash, Weapons.get_max_ammo(hash))
            else
                Notify.error('You need to get the weapon first before re-filling ammo!')
            end
        elseif component_items[item] ~= nil then
            local component_hash = weapon.components[component_items[item]]
            if HasPedGotWeapon(ped, hash, false) then
                SetCurrentPedWeapon(ped, hash, true)
                if HasPedGotWeaponComponent(ped, hash, component_hash) then
                    RemoveWeaponComponentFromPed(ped, hash, component_hash)
                    Subtitle.custom('Component removed.')
                else
                    equip_weapon_component(hash, component_hash)
                    Subtitle.custom('Component equipped.')
                end
            else
                Notify.error('You need to get the weapon first before you can modify it.')
            end
        end
    end

    weapon_menu:RefreshIndex()
    return weapon_menu, weapon_item
end

-- Stats panel follows the highlighted weapon.
local function handle_stats_panel(m, item)
    if item ~= nil and type(item.ItemData) == 'table' and item.ItemData.is_weapon_stats then
        local stats = item.ItemData.stats
        m:SetWeaponStats(stats.damage / 100, stats.speed / 100, stats.accuracy / 100, stats.range / 100)
        m.ShowWeaponStatsPanel = true
    else
        m.ShowWeaponStatsPanel = false
    end
end

local function wire_stats_panel(m)
    m.OnIndexChange = function(sender, _old_item, new_item, _old_index, _new_index)
        handle_stats_panel(sender, new_item)
    end
    m.OnMenuOpen = function(sender)
        handle_stats_panel(sender, sender:GetCurrentMenuItem())
    end
end

function WeaponOptions.create()
    local self = {}
    self.UnlimitedAmmo = UserDefaults.get_bool('weaponsUnlimitedAmmo')
    self.NoReload = UserDefaults.get_bool('weaponsNoReload')
    self.AutoEquipChute = UserDefaults.get_bool('autoEquipParachuteWhenInPlane')
    self.UnlimitedParachutes = UserDefaults.get_bool('weaponsUnlimitedParachutes')

    local menu = Menu.new(GetPlayerName(PlayerId()), 'Weapon Options')

    local get_all_weapons = Items.MenuItem.new('Get All Weapons', 'Get all weapons.')
    local remove_all_weapons = Items.MenuItem.new('Remove All Weapons', 'Removes all weapons in your inventory.')
    local unlimited_ammo =
        Items.MenuCheckboxItem.new('Unlimited Ammo', 'Unlimited ammunition supply.', self.UnlimitedAmmo)
    local no_reload = Items.MenuCheckboxItem.new('No Reload', 'Never reload.', self.NoReload)
    local set_ammo = Items.MenuItem.new('Set All Ammo Count', 'Set the amount of ammo in all your weapons.')
    local refill_max_ammo = Items.MenuItem.new('Refill All Ammo', 'Give all your weapons max ammo.')
    local spawn_by_name = Items.MenuItem.new('Spawn Weapon By Name', 'Enter a weapon mode name to spawn.')

    if Permissions.is_allowed('WPGetAll') then
        menu:AddMenuItem(get_all_weapons)
    end
    if Permissions.is_allowed('WPRemoveAll') then
        menu:AddMenuItem(remove_all_weapons)
    end
    if Permissions.is_allowed('WPUnlimitedAmmo') then
        menu:AddMenuItem(unlimited_ammo)
    end
    if Permissions.is_allowed('WPNoReload') then
        menu:AddMenuItem(no_reload)
    end
    if Permissions.is_allowed('WPSetAllAmmo') then
        menu:AddMenuItem(set_ammo)
        menu:AddMenuItem(refill_max_ammo)
    end
    if Permissions.is_allowed('WPSpawnByName') then
        menu:AddMenuItem(spawn_by_name)
    end

    -- Addon weapons submenu.
    local addon_weapons_btn =
        Items.MenuItem.new('Addon Weapons', 'Equip / remove addon weapons available on this server.')
    local addon_weapons_menu = Menu.new('Addon Weapons', 'Equip/Remove Addon Weapons')
    Controller.AddSubmenu(menu, addon_weapons_menu)
    addon_weapons_btn.Label = '→→→'
    menu:AddMenuItem(addon_weapons_btn)
    Controller.BindMenuItem(menu, addon_weapons_menu, addon_weapons_btn)

    for _, addon_weapon in ipairs(Weapons.addon_weapon_list()) do
        if Permissions.is_allowed('WPSpawn') and addon_weapon.name ~= nil and addon_weapon.name ~= '' then
            local addon_menu, addon_item = build_weapon_menu(addon_weapon)
            local ww_name = 'WW' .. addon_weapon.spawn_name:lower():gsub('weapon_', '')
            if not Permissions.is_supplementary_allowed(ww_name) then
                addon_item.Enabled = false
                addon_item.LeftIcon = Items.Icon.LOCK
                addon_item.Description = 'Access to this has been restricted by the server owner.'
            end
            Controller.AddSubmenu(addon_weapons_menu, addon_menu)
            Controller.BindMenuItem(addon_weapons_menu, addon_menu, addon_item)
            addon_weapons_menu:AddMenuItem(addon_item)
        end
    end

    if addon_weapons_menu:Size() == 0 then
        addon_weapons_btn.LeftIcon = Items.Icon.LOCK
        addon_weapons_btn.Description = "This option is not available on this server because you don't have "
            .. 'permission to use it, or it is not setup correctly.'
        addon_weapons_btn.Enabled = false
    end

    -- Parachute options.
    if Permissions.is_allowed('WPParachute') then
        local parachute_menu = Menu.new('Parachute Options', 'Parachute Options')
        local parachute_btn =
            Items.MenuItem.new('Parachute Options', 'All parachute related options can be changed here.')
        parachute_btn.Label = '→→→'

        Controller.AddSubmenu(menu, parachute_menu)
        menu:AddMenuItem(parachute_btn)
        Controller.BindMenuItem(menu, parachute_menu, parachute_btn)

        local chutes = {}
        local chute_descriptions = {}
        for i = 0, 7 do
            chutes[#chutes + 1] = GetLabelText(('PM_TINT%d'):format(i))
            chute_descriptions[#chute_descriptions + 1] = GetLabelText(('PD_TINT%d'):format(i))
        end
        -- broken in FiveM for some weird reason:
        for i = 0, 5 do
            chutes[#chutes + 1] = GetLabelText(('PS_CAN_%d'):format(i))
            chute_descriptions[#chute_descriptions + 1] = GetLabelText(('PSD_CAN_%d'):format(i))
                .. " ~r~For some reason this one doesn't seem to work in FiveM."
        end

        local toggle_primary = Items.MenuItem.new('Toggle Primary Parachute', 'Equip or remove the primary parachute')
        local toggle_reserve = Items.MenuItem.new(
            'Enable Reserve Parachute',
            'Enables the reserve parachute. Only works if you enabled the primary parachute first. Reserve '
                .. "parachute can not be removed from the player once it's activated."
        )
        local primary_chutes = Items.MenuListItem.new(
            'Primary Chute Style',
            chutes,
            0,
            ('Primary chute: %s'):format(chute_descriptions[1])
        )
        local secondary_chutes = Items.MenuListItem.new(
            'Reserve Chute Style',
            chutes,
            0,
            ('Reserve chute: %s'):format(chute_descriptions[1])
        )
        local unlimited_parachutes = Items.MenuCheckboxItem.new(
            'Unlimited Parachutes',
            'Enable unlimited parachutes and reserve parachutes.',
            self.UnlimitedParachutes
        )
        local auto_equip_parachutes = Items.MenuCheckboxItem.new(
            'Auto Equip Parachutes',
            'Automatically equip a parachute and reserve parachute when entering planes/helicopters.',
            self.AutoEquipChute
        )

        local smoke_colors_list = {}
        for i = 8, 13 do
            smoke_colors_list[#smoke_colors_list + 1] = GetLabelText(('PM_TINT%d'):format(i))
        end
        local smoke_rgb = {
            { 255, 255, 255 },
            { 255, 0, 0 },
            { 255, 165, 0 },
            { 255, 255, 0 },
            { 0, 0, 255 },
            { 20, 20, 20 },
        }
        local smoke_colors = Items.MenuListItem.new(
            'Smoke Trail Color',
            smoke_colors_list,
            0,
            'Choose a smoke trail color, then press select to change it. Changing colors takes 4 seconds, you '
                .. 'can not use your smoke while the color is being changed.'
        )

        parachute_menu:AddMenuItem(toggle_primary)
        parachute_menu:AddMenuItem(toggle_reserve)
        parachute_menu:AddMenuItem(auto_equip_parachutes)
        parachute_menu:AddMenuItem(unlimited_parachutes)
        parachute_menu:AddMenuItem(smoke_colors)
        parachute_menu:AddMenuItem(primary_chutes)
        parachute_menu:AddMenuItem(secondary_chutes)

        parachute_menu.OnItemSelect = function(_, item, _index)
            if item == toggle_primary then
                if HasPedGotWeapon(PlayerPedId(), GetHashKey('gadget_parachute'), false) then
                    Subtitle.custom('Primary parachute removed.')
                    RemoveWeaponFromPed(PlayerPedId(), GetHashKey('gadget_parachute'))
                else
                    Subtitle.custom('Primary parachute added.')
                    GiveWeaponToPed(PlayerPedId(), GetHashKey('gadget_parachute'), 0, false, false)
                end
            elseif item == toggle_reserve then
                SetPlayerHasReserveParachute(PlayerId())
                Subtitle.custom('Reserve parachute has been added.')
            end
        end

        parachute_menu.OnCheckboxChange = function(_, item, _index, checked)
            if item == unlimited_parachutes then
                self.UnlimitedParachutes = checked
            elseif item == auto_equip_parachutes then
                self.AutoEquipChute = checked
            end
        end

        local switching = false
        local function index_changed_handler(_, item, old_index, new_index, _item_index)
            if item == smoke_colors and old_index == -1 then
                if not switching then
                    switching = true
                    SetPlayerCanLeaveParachuteSmokeTrail(PlayerId(), false)
                    Wait(4000)
                    local color = smoke_rgb[new_index + 1]
                    SetPlayerParachuteSmokeTrailColor(PlayerId(), color[1], color[2], color[3])
                    SetPlayerCanLeaveParachuteSmokeTrail(PlayerId(), new_index ~= 0)
                    switching = false
                end
            elseif item == primary_chutes then
                item.Description = ('Primary chute: %s'):format(chute_descriptions[new_index + 1])
                SetPlayerParachuteTintIndex(PlayerId(), new_index)
            elseif item == secondary_chutes then
                item.Description = ('Reserve chute: %s'):format(chute_descriptions[new_index + 1])
                SetPlayerReserveParachuteTintIndex(PlayerId(), new_index)
            end
        end

        parachute_menu.OnListItemSelect = function(sender, item, index, item_index)
            index_changed_handler(sender, item, -1, index, item_index)
        end
        parachute_menu.OnListIndexChange = index_changed_handler
    end

    -- Weapon category submenus.
    menu:AddMenuItem(Common.get_spacer_menu_item('↓ Weapon Categories ↓'))

    local categories = {
        { 'Handguns', {} },
        { 'Assault Rifles', {} },
        { 'Shotguns', {} },
        { 'Sub-/Light Machine Guns', {} },
        { 'Throwables', {} },
        { 'Melee', {} },
        { 'Heavy Weapons', {} },
        { 'Sniper Rifles', {} },
    }
    local category_menus = {}
    local category_buttons = {}
    for i, entry in ipairs(categories) do
        local cat_menu = Menu.new('Weapons', entry[1])
        local cat_btn = Items.MenuItem.new(entry[1])
        Controller.AddSubmenu(menu, cat_menu)
        cat_btn.Label = '→→→'
        menu:AddMenuItem(cat_btn)
        Controller.BindMenuItem(menu, cat_menu, cat_btn)
        category_menus[i] = cat_menu
        category_buttons[i] = cat_btn
    end

    local GROUP_TO_CATEGORY = {
        [GROUP_HANDGUNS] = 1,
        [GROUP_STUNGUN] = 1,
        [GROUP_RIFLES] = 2,
        [GROUP_SHOTGUNS] = 3,
        [GROUP_SMGS] = 4,
        [GROUP_LMGS] = 4,
        [GROUP_THROWABLES] = 5,
        [GROUP_FIRE_EXTINGUISHER] = 5,
        [GROUP_JERRY_CAN] = 5,
        [GROUP_MELEE] = 6,
        [GROUP_KNUCKLE_DUSTER] = 6,
        [GROUP_HEAVY] = 7,
        [GROUP_SNIPERS] = 8,
    }

    for _, weapon in ipairs(Weapons.weapon_list()) do
        if weapon.name ~= nil and weapon.name ~= '' and Permissions.is_allowed(weapon.perm) then
            local category_index = GROUP_TO_CATEGORY[GetWeapontypeGroup(weapon.hash)]
            if category_index ~= nil then
                local weapon_menu, weapon_item = build_weapon_menu(weapon)
                local cat_menu = category_menus[category_index]
                Controller.AddSubmenu(cat_menu, weapon_menu)
                Controller.BindMenuItem(cat_menu, weapon_menu, weapon_item)
                cat_menu:AddMenuItem(weapon_item)
            end
        end
    end

    for i, cat_btn in ipairs(category_buttons) do
        local cat_menu = category_menus[i]
        if cat_menu:Size() == 0 then
            cat_btn.LeftIcon = Items.Icon.LOCK
            cat_btn.Description = 'The server owner removed the permissions for all weapons in this category.'
            cat_btn.Enabled = false
        end
        wire_stats_panel(cat_menu)
    end
    wire_stats_panel(addon_weapons_menu)

    -- SetAllWeaponsAmmo (CommonFunctions).
    local function set_all_weapons_ammo()
        local input_ammo = Common.get_user_input('Enter Ammo Amount', '100')
        if input_ammo == nil or input_ammo == '' then
            Notify.error(Notification.error_message('InvalidInput'))
            return
        end
        local ammo = math.tointeger(tonumber(input_ammo))
        if ammo == nil then
            Notify.error('You did not enter a valid number.')
            return
        end
        for _, vw in ipairs(Weapons.weapon_list()) do
            if HasPedGotWeapon(PlayerPedId(), vw.hash, false) then
                SetPedAmmo(PlayerPedId(), vw.hash, ammo)
            end
        end
    end

    -- SpawnCustomWeapon (CommonFunctions).
    local function spawn_custom_weapon()
        local ammo = 900
        local input_name = Common.get_user_input('Enter Weapon Model Name', nil, 30)
        if input_name == nil or input_name == '' then
            Notify.error(Notification.error_message('InvalidInput'))
            return
        end
        local perm = WeaponsData.weapon_permissions[input_name:lower()]
        if perm == nil then
            if not Permissions.is_allowed('WPSpawn') then
                Notify.error('Sorry, you do not have permission to spawn this weapon.')
                return
            end
        elseif not Permissions.is_allowed(perm) then
            Notify.error("Sorry, you are not allowed to spawn that weapon by name because it's a restricted weapon.")
            return
        end
        local model = GetHashKey(input_name:upper())
        if IsWeaponValid(model) then
            GiveWeaponToPed(PlayerPedId(), model, ammo, false, true)
            Notify.success('Added weapon to inventory.')
        else
            Notify.error(
                (
                    'This (%s) is not a valid weapon model name, or the model hash (%s) could not be found in the '
                    .. 'game files.'
                ):format(input_name, tostring(model))
            )
        end
    end

    menu.OnItemSelect = function(_, item, _index)
        local ped = PlayerPedId()
        if item == get_all_weapons then
            for _, vw in ipairs(Weapons.weapon_list()) do
                if Permissions.is_allowed(vw.perm) then
                    GiveWeaponToPed(ped, vw.hash, Weapons.get_max_ammo(vw.hash), false, true)
                    SetAmmoInClip(ped, vw.hash, GetMaxAmmoInClip(ped, vw.hash, false))
                    SetPedAmmo(ped, vw.hash, Weapons.get_max_ammo(vw.hash))
                end
            end
            for _, avw in ipairs(Weapons.addon_weapon_list()) do
                GiveWeaponToPed(ped, avw.hash, Weapons.get_max_ammo(avw.hash), false, true)
                SetAmmoInClip(ped, avw.hash, GetMaxAmmoInClip(ped, avw.hash, false))
                SetPedAmmo(ped, avw.hash, Weapons.get_max_ammo(avw.hash))
            end
            SetCurrentPedWeapon(ped, GetHashKey('weapon_unarmed'), true)
        elseif item == remove_all_weapons then
            RemoveAllPedWeapons(ped, true)
        elseif item == set_ammo then
            set_all_weapons_ammo()
        elseif item == refill_max_ammo then
            for _, vw in ipairs(Weapons.weapon_list()) do
                if HasPedGotWeapon(ped, vw.hash, false) then
                    SetAmmoInClip(ped, vw.hash, GetMaxAmmoInClip(ped, vw.hash, false))
                    SetPedAmmo(ped, vw.hash, Weapons.get_max_ammo(vw.hash))
                end
            end
            for _, avw in ipairs(Weapons.addon_weapon_list()) do
                if HasPedGotWeapon(ped, avw.hash, false) then
                    SetAmmoInClip(ped, avw.hash, GetMaxAmmoInClip(ped, avw.hash, false))
                    SetPedAmmo(ped, avw.hash, Weapons.get_max_ammo(avw.hash))
                end
            end
        elseif item == spawn_by_name then
            spawn_custom_weapon()
        end
    end

    menu.OnCheckboxChange = function(_, item, _index, checked)
        if item == no_reload then
            self.NoReload = checked
            Subtitle.custom(('No reload is now %s.'):format(checked and 'enabled' or 'disabled'))
        elseif item == unlimited_ammo then
            self.UnlimitedAmmo = checked
            Subtitle.custom(('Unlimited ammo is now %s.'):format(checked and 'enabled' or 'disabled'))
        end
    end

    self.menu = menu
    return self
end

return WeaponOptions
