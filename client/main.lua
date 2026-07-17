-- Port of vMenu/MainMenu.cs: the client entrypoint. KVP cleanup, key
-- mappings, the vmenuclient command, the permission-driven menu tree, and
-- the coords RPC. Menu submodules (client/menus/*) land in waves M7-M9;
-- until a module exists its top-level entry simply doesn't appear, but every
-- permission gate, button text, and binding below is already the exact
-- upstream structure.

local Util = require('shared.util')
local Json = require('shared.json_compat')
local Config = require('shared.config')
local Permissions = require('shared.permissions')
local State = require('client.state')
local Notification = require('client.notify')
local Events = require('client.events')
local PlayerLists = require('client.player_lists')
local NoClip = require('client.noclip')
local Controller = require('menu.controller')
local Menu = require('menu.menu')
local Items = require('menu.items')
local Process = require('menu.process')

local Notify = Notification.Notify

local Main = {}

local RESOURCE = GetCurrentResourceName()
local CURRENT_CLEANUP_VERSION = 2

local debug_mode = (GetResourceMetadata(RESOURCE, 'client_debug_mode', 0) or '') == 'true'
local experimental_features = (GetResourceMetadata(RESOURCE, 'experimental_features_enabled', 0) or '0') == '1'

local function version()
    return GetResourceMetadata(RESOURCE, 'version', 0)
end

-- GetKeyMappingId: vmenu_keymapping_id convar, "Default" when blank. FiveM
-- persists user keybinds per mapping name, so this id keeps existing binds.
local function get_key_mapping_id()
    local id = Config.get_string('vmenu_keymapping_id')
    if id == nil or id:match('^%s*$') then
        return 'Default'
    end
    return id
end

-- ---------------------------------------------------------------------------
-- KVP cleanup (old save formats from previous vMenu versions)
-- ---------------------------------------------------------------------------

local function starts_with(value, prefix)
    return value:sub(1, #prefix) == prefix
end

local function cleanup_old_kvps()
    local handle = StartFindKvp('')
    local cleanup_version_checked = false
    local names = {}
    while true do
        local key = FindKvp(handle)
        if key == nil or key == '' then
            break
        end
        if key == 'vmenu_cleanup_version' and GetResourceKvpInt('vmenu_cleanup_version') >= CURRENT_CLEANUP_VERSION then
            cleanup_version_checked = true
        end
        names[#names + 1] = key
    end
    EndFindKvp(handle)

    if cleanup_version_checked then
        return
    end
    SetResourceKvpInt('vmenu_cleanup_version', CURRENT_CLEANUP_VERSION)
    for _, kvp in ipairs(names) do
        if
            not starts_with(kvp, 'settings_')
            and not starts_with(kvp, 'vmenu')
            and not starts_with(kvp, 'veh_')
            and not starts_with(kvp, 'ped_')
            and not starts_with(kvp, 'mp_ped_')
        then
            DeleteResourceKvp(kvp)
            print(('[vMenu] [cleanup id: 1] Removed unused (old) KVP: %s.'):format(kvp))
        end
        if starts_with(kvp, 'mp_char') then
            DeleteResourceKvp(kvp)
            print(('[vMenu] [cleanup id: 2] Removed unused (old) KVP: %s.'):format(kvp))
        end
    end
    print('[vMenu] Cleanup of old unused KVP items completed.')
end

Main._cleanup_old_kvps = cleanup_old_kvps

-- ---------------------------------------------------------------------------
-- Coords RPC (vMenu:GetPlayerCoords round-trip)
-- ---------------------------------------------------------------------------

local rpc_queue = {}
local rpc_id_counter = 0

local function register_rpc_handlers()
    RegisterNetEvent('vMenu:ReceivePlayerList', function(players)
        PlayerLists.received_player_list(players)
    end)

    RegisterNetEvent('vMenu:GetPlayerCoords:reply', function(rpc_id, coords)
        if rpc_queue[rpc_id] ~= nil then
            rpc_queue[rpc_id] = { completed = true, coords = coords }
        else
            print(('[vMenu] Warning: Received player coordinates for unknown RPC ID: %s'):format(tostring(rpc_id)))
        end
    end)
end

-- RequestPlayerCoordinates: blocks (yielding) until the server replies.
-- Registered into State so require-cycle-free modules (client/common.lua)
-- can locate OneSync-remote players.
function Main.request_player_coordinates(server_id)
    local rpc_id = rpc_id_counter
    rpc_id_counter = rpc_id_counter + 1
    rpc_queue[rpc_id] = { completed = false, coords = vector3(0.0, 0.0, 0.0) }

    TriggerServerEvent('vMenu:GetPlayerCoords', rpc_id, server_id)

    while not rpc_queue[rpc_id].completed do
        Wait(0)
    end
    local coords = rpc_queue[rpc_id].coords
    rpc_queue[rpc_id] = nil
    return coords
end

-- ---------------------------------------------------------------------------
-- Menu creation (PostPermissionsSetup + CreateSubmenus)
-- ---------------------------------------------------------------------------

-- Menu modules load on demand; a missing module (not yet ported) simply
-- leaves its entry out of the tree.
local function try_require(module_name)
    local ok, module = pcall(require, module_name)
    if ok then
        return module
    end
    return nil
end

-- MainMenu.AddMenu: bind a submenu behind a button on the parent.
local function add_menu(parent_menu, submenu, menu_button)
    parent_menu:AddMenuItem(menu_button)
    Controller.AddSubmenu(parent_menu, submenu)
    Controller.BindMenuItem(parent_menu, submenu, menu_button)
    submenu:RefreshIndex()
end

local function arrow_button(text, description)
    local button = Items.MenuItem.new(text, description)
    button.Label = '→→→'
    return button
end

-- Creates all the submenus depending on the permissions of the user.
-- Structure, order, permission gates, and button texts are the exact
-- CreateSubmenus() port; each block additionally requires its menu module to
-- exist. The C# multicast OnItemSelect handlers become one dispatcher table.
local function create_submenus(menu, player_submenu, vehicle_submenu, world_submenu)
    local main_item_handlers = {} -- [item] = fn, replaces C# multicast +=
    menu.OnItemSelect = function(_, item, index)
        local handler = main_item_handlers[item]
        if handler then
            handler(item, index)
        end
    end

    -- Online Players
    if Permissions.is_allowed('OPMenu') then
        local OnlinePlayers = try_require('client.menus.online_players')
        if OnlinePlayers then
            local instance = OnlinePlayers.create()
            State.menus.online_players = instance
            local button = arrow_button('Online Players', 'All currently connected players.')
            add_menu(menu, instance.menu, button)
            main_item_handlers[button] = function()
                PlayerLists.request_player_list()
                instance.update_player_list()
                instance.menu:RefreshIndex()
            end
        end
    end

    -- Banned Players
    if Permissions.is_allowed('OPUnban') or Permissions.is_allowed('OPViewBannedPlayers') then
        local BannedPlayers = try_require('client.menus.banned_players')
        if BannedPlayers then
            local instance = BannedPlayers.create()
            State.menus.banned_players = instance
            local button = arrow_button('Banned Players', 'View and manage all banned players in this menu.')
            add_menu(menu, instance.menu, button)
            main_item_handlers[button] = function()
                TriggerServerEvent('vMenu:RequestBanList', PlayerId())
                instance.menu:RefreshIndex()
            end
        end
    end

    local player_submenu_btn =
        arrow_button('Player Related Options', 'Open this submenu for player related subcategories.')
    menu:AddMenuItem(player_submenu_btn)

    -- Player Options
    if Permissions.is_allowed('POMenu') then
        local PlayerOptions = try_require('client.menus.player_options')
        if PlayerOptions then
            local instance = PlayerOptions.create()
            State.menus.player_options = instance
            add_menu(
                player_submenu,
                instance.menu,
                arrow_button('Player Options', 'Common player options can be accessed here.')
            )
        end
    end

    local vehicle_submenu_btn =
        arrow_button('Vehicle Related Options', 'Open this submenu for vehicle related subcategories.')
    menu:AddMenuItem(vehicle_submenu_btn)

    -- Vehicle Options
    if Permissions.is_allowed('VOMenu') then
        local VehicleOptions = try_require('client.menus.vehicle_options')
        if VehicleOptions then
            local instance = VehicleOptions.create()
            State.menus.vehicle_options = instance
            add_menu(
                vehicle_submenu,
                instance.menu,
                arrow_button(
                    'Vehicle Options',
                    'Here you can change common vehicle options, as well as tune & style your vehicle.'
                )
            )
        end
    end

    -- Vehicle Spawner
    if Permissions.is_allowed('VSMenu') then
        local VehicleSpawner = try_require('client.menus.vehicle_spawner')
        if VehicleSpawner then
            local instance = VehicleSpawner.create()
            State.menus.vehicle_spawner = instance
            add_menu(
                vehicle_submenu,
                instance.menu,
                arrow_button('Vehicle Spawner', 'Spawn a vehicle by name or choose one from a specific category.')
            )
        end
    end

    -- Saved Vehicles
    if Permissions.is_allowed('SVMenu') then
        local SavedVehicles = try_require('client.menus.saved_vehicles')
        if SavedVehicles then
            local instance = SavedVehicles.create()
            State.menus.saved_vehicles = instance
            add_menu(
                vehicle_submenu,
                instance.type_menu,
                arrow_button('Saved Vehicles', 'Save new vehicles, or spawn or delete already saved vehicles.')
            )
        end
    end

    -- Personal Vehicle
    if Permissions.is_allowed('PVMenu') then
        local PersonalVehicle = try_require('client.menus.personal_vehicle')
        if PersonalVehicle then
            local instance = PersonalVehicle.create()
            State.menus.personal_vehicle = instance
            add_menu(
                vehicle_submenu,
                instance.menu,
                arrow_button(
                    'Personal Vehicle',
                    'Set a vehicle as your personal vehicle, and control some things about that vehicle '
                        .. "when you're not inside."
                )
            )
        end
    end

    -- Player Appearance + MP Ped Customization (both behind PAMenu)
    if Permissions.is_allowed('PAMenu') then
        local PlayerAppearance = try_require('client.menus.player_appearance')
        if PlayerAppearance then
            local instance = PlayerAppearance.create()
            State.menus.player_appearance = instance
            add_menu(
                player_submenu,
                instance.menu,
                arrow_button(
                    'Player Appearance',
                    'Choose a ped model, customize it and save & load your customized characters.'
                )
            )
        end

        local MpPedCustomization = try_require('client.menus.mp_ped_customization')
        if MpPedCustomization then
            local instance = MpPedCustomization.create()
            State.menus.mp_ped_customization = instance
            add_menu(
                player_submenu,
                instance.menu,
                arrow_button(
                    'MP Ped Customization',
                    'Create, edit, save and load multiplayer peds. ~r~Note, you can only save peds created in this '
                        .. 'submenu. vMenu can NOT detect peds created outside of this submenu. Simply due to GTA '
                        .. 'limitations.'
                )
            )
        end
    end

    local world_submenu_btn =
        arrow_button('World Related Options', 'Open this submenu for world related subcategories.')
    menu:AddMenuItem(world_submenu_btn)

    -- Time Options (only when time sync is enabled)
    if Permissions.is_allowed('TOMenu') and Config.get_bool('vmenu_enable_time_sync') then
        local TimeOptions = try_require('client.menus.time_options')
        if TimeOptions then
            local instance = TimeOptions.create()
            State.menus.time_options = instance
            add_menu(
                world_submenu,
                instance.menu,
                arrow_button('Time Options', 'Change the time, and edit other time related options.')
            )
        end
    end

    -- Weather Options (only when weather sync is enabled)
    if Permissions.is_allowed('WOMenu') and Config.get_bool('vmenu_enable_weather_sync') then
        local WeatherOptions = try_require('client.menus.weather_options')
        if WeatherOptions then
            local instance = WeatherOptions.create()
            State.menus.weather_options = instance
            add_menu(
                world_submenu,
                instance.menu,
                arrow_button('Weather Options', 'Change all weather related options here.')
            )
        end
    end

    -- Weapon Options
    if Permissions.is_allowed('WPMenu') then
        local WeaponOptions = try_require('client.menus.weapon_options')
        if WeaponOptions then
            local instance = WeaponOptions.create()
            State.menus.weapon_options = instance
            add_menu(
                player_submenu,
                instance.menu,
                arrow_button('Weapon Options', 'Add/remove weapons, modify weapons and set ammo options.')
            )
        end
    end

    -- Weapon Loadouts
    if Permissions.is_allowed('WLMenu') then
        local WeaponLoadouts = try_require('client.menus.weapon_loadouts')
        if WeaponLoadouts then
            local instance = WeaponLoadouts.create()
            State.menus.weapon_loadouts = instance
            add_menu(
                player_submenu,
                instance.menu,
                arrow_button('Weapon Loadouts', 'Mange, and spawn saved weapon loadouts.')
            )
        end
    end

    -- NoClip toggle
    if Permissions.is_allowed('NoClip') then
        local toggle_noclip = Items.MenuItem.new('Toggle NoClip', 'Toggle NoClip on or off.')
        player_submenu:AddMenuItem(toggle_noclip)
        player_submenu.OnItemSelect = function(_, item, _index)
            if item == toggle_noclip then
                NoClip.set_noclip_active(not NoClip.is_noclip_active())
            end
        end
    end

    -- Voice Chat
    if Permissions.is_allowed('VCMenu') then
        local VoiceChat = try_require('client.menus.voice_chat')
        if VoiceChat then
            local instance = VoiceChat.create()
            State.menus.voice_chat = instance
            add_menu(menu, instance.menu, arrow_button('Voice Chat Settings', 'Change Voice Chat options here.'))
        end
    end

    -- Recording (no permission gate upstream)
    do
        local Recording = try_require('client.menus.recording')
        if Recording then
            local instance = Recording.create()
            State.menus.recording = instance
            add_menu(menu, instance.menu, arrow_button('Recording Options', 'In-game recording options.'))
        end
    end

    -- Misc Settings (no permission gate upstream)
    do
        local MiscSettings = try_require('client.menus.misc_settings')
        if MiscSettings then
            local instance = MiscSettings.create()
            State.menus.misc_settings = instance
            add_menu(
                menu,
                instance.menu,
                arrow_button(
                    'Misc Settings',
                    'Miscellaneous vMenu options/settings can be configured here. You can also save your settings in '
                        .. 'this menu.'
                )
            )
        end
    end

    -- About vMenu (no permission gate upstream)
    do
        local About = try_require('client.menus.about')
        if About then
            local instance = About.create()
            State.menus.about = instance
            add_menu(menu, instance.menu, arrow_button('About vMenu', 'Information about vMenu.'))
        end
    end

    -- Refresh everything.
    for _, m in ipairs(Controller.Menus) do
        m:RefreshIndex()
    end

    if not Config.get_bool('vmenu_use_permissions') then
        Notify.alert('vMenu is set up to ignore permissions, default permissions will be used.')
    end

    -- Bind (or remove) the category buttons depending on content.
    if player_submenu:Size() > 0 then
        Controller.BindMenuItem(menu, player_submenu, player_submenu_btn)
    else
        menu:RemoveMenuItem(player_submenu_btn)
    end

    if vehicle_submenu:Size() > 0 then
        Controller.BindMenuItem(menu, vehicle_submenu, vehicle_submenu_btn)
    else
        menu:RemoveMenuItem(vehicle_submenu_btn)
    end

    if world_submenu:Size() > 0 then
        Controller.BindMenuItem(menu, world_submenu, world_submenu_btn)
    else
        menu:RemoveMenuItem(world_submenu_btn)
    end

    local misc = State.menus.misc_settings
    if misc ~= nil then
        Controller.EnableMenuToggleKeyOnController = not misc.MiscDisableControllerSupport
    end
end

-- PostPermissionsSetup: pvp flags, the staff-only gate, menu creation,
-- player stats, and the menu toggle command.
local function post_permissions_setup()
    local pvp_mode = Config.get_int('vmenu_pvp_mode')
    if pvp_mode == 1 then
        NetworkSetFriendlyFireOption(true)
        SetCanAttackFriendly(PlayerPedId(), true, false)
    elseif pvp_mode == 2 then
        NetworkSetFriendlyFireOption(false)
        SetCanAttackFriendly(PlayerPedId(), false, false)
    end

    local can_use_menu = not Config.get_bool('vmenu_menu_staff_only') or Permissions.is_allowed('Staff')
    if not can_use_menu then
        Controller.MainMenu = nil
        Controller.DisableMenuButtons = true
        Controller.DontOpenAnyMenu = true
        State.menu_enabled = false
        return
    end

    local player_name = GetPlayerName(PlayerId())
    local menu = Menu.new(player_name, 'Main Menu')
    State.menus.main = menu
    local player_submenu = Menu.new(player_name, 'Player Related Options')
    local vehicle_submenu = Menu.new(player_name, 'Vehicle Related Options')
    local world_submenu = Menu.new(player_name, 'World Options')

    Controller.AddMenu(menu)
    Controller.MainMenu = menu
    Controller.AddSubmenu(menu, player_submenu)
    Controller.AddSubmenu(menu, vehicle_submenu)
    Controller.AddSubmenu(menu, world_submenu)

    State.menu = menu
    State.player_submenu = player_submenu
    State.vehicle_submenu = vehicle_submenu
    State.world_submenu = world_submenu

    create_submenus(menu, player_submenu, vehicle_submenu, world_submenu)

    if not Config.get_bool('vmenu_disable_player_stats_setup') then
        local player_options = State.menus.player_options
        if player_options ~= nil and player_options.PlayerStamina and Permissions.is_allowed('POUnlimitedStamina') then
            StatSetInt(GetHashKey('MP0_STAMINA'), 100, true)
        else
            StatSetInt(GetHashKey('MP0_STAMINA'), 0, true)
        end

        StatSetInt(GetHashKey('MP0_SHOOTING_ABILITY'), 100, true) -- Shooting
        StatSetInt(GetHashKey('MP0_STRENGTH'), 100, true) -- Strength
        StatSetInt(GetHashKey('MP0_STEALTH_ABILITY'), 100, true) -- Stealth
        StatSetInt(GetHashKey('MP0_FLYING_ABILITY'), 100, true) -- Flying
        StatSetInt(GetHashKey('MP0_WHEELIE_ABILITY'), 100, true) -- Driving
        StatSetInt(GetHashKey('MP0_LUNG_CAPACITY'), 100, true) -- Lung Capacity
        StatSetFloat(GetHashKey('MP0_PLAYER_MENTAL_STATE'), 0.0, true) -- Mental State

        Util.debug_log('player stats set up')
    end

    RegisterCommand(('vMenu:%s:MenuToggle'):format(get_key_mapping_id()), function()
        if State.menu_enabled then
            if not Controller.IsAnyMenuOpen() then
                menu:OpenMenu()
            else
                Controller.CloseAllMenus()
            end
        end
    end, false)

    -- FunctionsController registers its vMenu:SetupTickFunctions handler on load.
    try_require('client.functions_controller.main')

    TriggerEvent('vMenu:SetupTickFunctions')
end

Main._post_permissions_setup = post_permissions_setup

-- ---------------------------------------------------------------------------
-- Permission handlers (MainMenu.SetPermissions / SetSupplementaryPermissions)
-- ---------------------------------------------------------------------------

-- The 23 vehicle spawner categories, in upstream's fixed order.
local VEHICLE_CATEGORY_PERMISSIONS = {
    'VSCompacts',
    'VSSedans',
    'VSSUVs',
    'VSCoupes',
    'VSMuscle',
    'VSSportsClassic',
    'VSSports',
    'VSSuper',
    'VSMotorcycles',
    'VSOffRoad',
    'VSIndustrial',
    'VSUtility',
    'VSVans',
    'VSCycles',
    'VSBoats',
    'VSHelicopters',
    'VSPlanes',
    'VSService',
    'VSEmergency',
    'VSMilitary',
    'VSCommercial',
    'VSTrains',
    'VSOpenWheel',
}

function Main.set_permissions(payload)
    Permissions.set_from_json(payload)

    State.allowed_vehicle_categories = {}
    for i, permission in ipairs(VEHICLE_CATEGORY_PERMISSIONS) do
        State.allowed_vehicle_categories[i] = Permissions.is_allowed(permission, true)
    end

    -- Wait for the config options push, then build the menus. (Upstream's
    -- loop condition is `!ConfigOptionsSetupComplete && !AddonPermissionSetup`
    -- — either one completes the wait; quirk preserved.)
    CreateThread(function()
        while not State.config_options_setup_complete and not State.addon_permission_setup do
            Wait(100)
        end
        post_permissions_setup()
    end)
end

function Main.set_supplementary_permissions(payload)
    Permissions.set_supplementary_from_json(payload)
    State.addon_permission_setup = true
end

-- ---------------------------------------------------------------------------
-- Commands & key mappings
-- ---------------------------------------------------------------------------

local function register_keymappings()
    local key_mapping_id = get_key_mapping_id()

    RegisterCommand(('vMenu:%s:NoClip'):format(key_mapping_id), function()
        if Permissions.is_allowed('NoClip') then
            if IsPedInAnyVehicle(PlayerPedId(), false) then
                local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
                if vehicle ~= 0 and DoesEntityExist(vehicle) and GetPedInVehicleSeat(vehicle, -1) == PlayerPedId() then
                    NoClip.set_noclip_active(not NoClip.is_noclip_active())
                else
                    NoClip.set_noclip_active(false)
                    Notify.error(
                        'This vehicle does not exist (somehow) or you need to be the driver of this vehicle '
                            .. 'to enable noclip!'
                    )
                end
            else
                NoClip.set_noclip_active(not NoClip.is_noclip_active())
            end
        end
    end, false)

    RegisterCommand('vMenu:DV', function()
        if Permissions.is_allowed('VODelete') then
            local common = try_require('client.vehicle_common')
            if common and common.delete_vehicle then
                common.delete_vehicle()
            else
                Notify.alert('Vehicle deletion has not been ported to this build yet.')
            end
        end
    end, false)

    local noclip_key = Config.get_string('vmenu_noclip_toggle_key') or 'F2'
    local menu_toggle_key = Config.get_string('vmenu_menu_toggle_key') or 'M'

    Controller.MenuToggleKey = -1 -- disables MenuAPI's own toggle key

    RegisterKeyMapping(('vMenu:%s:NoClip'):format(key_mapping_id), 'vMenu NoClip Toggle Button', 'keyboard', noclip_key)
    RegisterKeyMapping(
        ('vMenu:%s:MenuToggle'):format(key_mapping_id),
        'vMenu Toggle Button',
        'keyboard',
        menu_toggle_key
    )
    RegisterKeyMapping(
        ('vMenu:%s:MenuToggle'):format(key_mapping_id),
        'vMenu Toggle Button Controller',
        'pad_digitalbuttonany',
        'start_index'
    )
end

local function register_vmenuclient_command()
    RegisterCommand('vmenuclient', function(_source, args, _raw)
        args = args or {}
        if #args == 0 then
            Notify.custom(('vMenu is currently running version: %s.'):format(version()))
            return
        end
        local sub = tostring(args[1]):lower()

        if sub == 'debug' then
            debug_mode = not debug_mode
            Notify.custom(('Debug mode is now set to: %s.'):format(debug_mode and 'True' or 'False'))
            if debug_mode then
                SetRichPresence(('Debugging vMenu %s!'):format(version()))
            else
                SetRichPresence('Enjoying FiveM!')
            end
        elseif sub == 'gc' then
            collectgarbage()
            print('Cleared memory.\n')
        elseif sub == 'dump' then
            Notify.info('A full config dump will be made to the console. Check the log file. This can cause lag!')
            print('\n\n\n########################### vMenu ###########################')
            print(
                ('Running vMenu Version: %s, Experimental features: %s, Debug mode: %s.'):format(
                    version(),
                    tostring(experimental_features),
                    tostring(debug_mode)
                )
            )
            print('\nDumping a list of all KVPs:')
            local handle = StartFindKvp('')
            local names = {}
            while true do
                local key = FindKvp(handle)
                if key == nil or key == '' then
                    break
                end
                names[#names + 1] = key
            end
            EndFindKvp(handle)

            local kvps = {}
            for _, kvp in ipairs(names) do
                local kind = 0 -- 0 = string, 1 = float, 2 = int
                if starts_with(kvp, 'settings_') then
                    if kvp == 'settings_voiceChatProximity' then
                        kind = 1
                    elseif
                        kvp == 'settings_clothingAnimationType'
                        or kvp == 'settings_miscLastTimeCycleModifierIndex'
                        or kvp == 'settings_miscLastTimeCycleModifierStrength'
                    then
                        kind = 2
                    end
                elseif kvp == 'vmenu_cleanup_version' then
                    kind = 2
                end
                if kind == 0 then
                    local value = GetResourceKvpString(kvp) or ''
                    if starts_with(value, '{') or starts_with(value, '[') then
                        kvps[kvp] = Json.decode(value)
                    else
                        kvps[kvp] = value
                    end
                elseif kind == 1 then
                    kvps[kvp] = GetResourceKvpFloat(kvp)
                else
                    kvps[kvp] = GetResourceKvpInt(kvp)
                end
            end
            print(Json.encode(kvps) .. '\n')

            print('\n\nDumping a list of allowed permissions:')
            print(Json.encode(Permissions.raw_grants()))

            print('\n\nDumping vmenu server configuration settings:')
            local settings = {}
            for _, setting in ipairs(Config.settings) do
                settings[setting] = Config.get_string(setting) or ''
            end
            print(Json.encode(settings))
            print('\nEnd of vMenu dump!')
            print('\n########################### vMenu ###########################')
        end
    end, false)
end

-- ---------------------------------------------------------------------------
-- OnTick (menu open/close guards; the MpPedCustomization protections)
-- ---------------------------------------------------------------------------

local function on_tick()
    if not State.config_options_setup_complete then
        return
    end
    local mp_ped = State.menus.mp_ped_customization
    if mp_ped == nil then
        return
    end
    -- The create-character back-button protections land with the
    -- MpPedCustomization menu port (M9); this tick gains that logic then.
end

-- ---------------------------------------------------------------------------
-- Boot (the MainMenu constructor)
-- ---------------------------------------------------------------------------

cleanup_old_kvps()
register_keymappings()
register_vmenuclient_command()
register_rpc_handlers()
State.request_player_coordinates = Main.request_player_coordinates

Events.register({
    set_permissions = Main.set_permissions,
    set_supplementary_permissions = Main.set_supplementary_permissions,
})

if RESOURCE ~= 'vMenu' then
    Controller.MainMenu = nil
    Controller.DontOpenAnyMenu = true
    Controller.DisableMenuButtons = true
    print(
        (
            '\n[vMenu] INSTALLATION ERROR!\nThe name of the resource is not valid. Please change the folder name from '
            .. "'%s' to 'vMenu' (case sensitive)!\n"
        ):format(RESOURCE)
    )
else
    Process.start()
    CreateThread(function()
        while true do
            on_tick()
            Wait(0)
        end
    end)
end

-- Clear all previous pause menu info/brief messages on resource start.
ClearBrief()

if GlobalState.vmenu_onesync == true then
    PlayerLists.set_infinity_mode(true)
end

Util.debug_log('client booted')

-- ---------------------------------------------------------------------------
-- M3 verification demo: a menu exercising every item type, for side-by-side
-- comparison against C# vMenu + MenuAPI. Gated behind the same fxmanifest
-- flag upstream uses for its dev commands.
-- ---------------------------------------------------------------------------

if experimental_features then
    local demo = nil

    local function build_demo_menu()
        local demo_menu = Menu.new('vMenu', 'Framework demo')
        local submenu = Menu.new('vMenu', 'A submenu')
        submenu:AddMenuItem(Items.MenuItem.new('Nested item', 'Go back with backspace/right stick.'))

        local button = Items.MenuItem.new('Plain button', 'Fires OnItemSelect.')
        local locked = Items.MenuItem.new('Disabled item', 'Should play the error sound.')
        locked.Enabled = false
        locked.LeftIcon = Items.Icon.LOCK
        local checkbox = Items.MenuCheckboxItem.new('Checkbox', 'Toggles on select and on right-press.', true)
        local list = Items.MenuListItem.new('List item', { 'Alpha', 'Beta', 'Gamma' }, 0, 'Wraps both directions.')
        local slider = Items.MenuSliderItem.new('Slider', 0, 10, 5, 'Clamps at min/max.')
        local dynamic = Items.MenuDynamicListItem.new('Dynamic list', '50', function(item, left)
            local value = tonumber(item.CurrentItem) or 0
            return tostring(left and value - 5 or value + 5)
        end, 'Callback-driven values.')
        local opener = Items.MenuItem.new('Open submenu', 'Bound submenu navigation.')
        opener.Label = '→→→'

        for _, item in ipairs({ button, locked, checkbox, list, slider, dynamic }) do
            demo_menu:AddMenuItem(item)
        end
        for i = 1, 12 do
            demo_menu:AddMenuItem(Items.MenuItem.new(('Filler %d'):format(i), 'Scroll overflow test.'))
        end
        demo_menu:AddMenuItem(opener)

        Controller.AddMenu(demo_menu)
        Controller.BindMenuItem(demo_menu, submenu, opener)
        demo_menu.OnItemSelect = function(_, item, index)
            Util.debug_log(('demo select: %s (index %d)'):format(item.Text or '?', index))
        end
        return demo_menu
    end

    RegisterCommand('vmenu_demo', function()
        demo = demo or build_demo_menu()
        if not demo.Visible then
            demo:OpenMenu()
        else
            demo:CloseMenu()
        end
    end, false)
end

return Main
