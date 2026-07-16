-- Port of vMenu/menus/MiscSettings.cs: personal settings, teleport options,
-- keybind toggles, developer tools, connection options, and saving.
-- Per-frame consumers of these flags (speedometers, location display, entity
-- outlines, ...) are the FunctionsController port (M9); the entity spawner
-- submenu appears once client/entity_spawner.lua lands (M9).

local Config = require('shared.config')
local Permissions = require('shared.permissions')
local State = require('client.state')
local Common = require('client.common')
local Notification = require('client.notify')
local UserDefaults = require('client.user_defaults')
local TimeCycles = require('client.data.time_cycles')
local Controller = require('menu.controller')
local Items = require('menu.items')
local Menu = require('menu.menu')

local Notify = Notification.Notify

local MiscSettings = {}

local function try_require(module_name)
    local ok, module = pcall(require, module_name)
    if ok then
        return module
    end
    return nil
end

function MiscSettings.create()
    local self = {}

    -- Public state (FunctionsController M9 + save_settings + events.lua).
    self.ShowSpeedoKmh = UserDefaults.get_bool('miscSpeedoKmh')
    self.ShowSpeedoMph = UserDefaults.get_bool('miscSpeedoMph')
    self.ShowCoordinates = false
    self.HideHud = false
    self.HideRadar = false
    self.ShowLocation = UserDefaults.get_bool('miscShowLocation')
    self.DeathNotifications = UserDefaults.get_bool('miscDeathNotifications')
    self.JoinQuitNotifications = UserDefaults.get_bool('miscJoinQuitNotifications')
    self.LockCameraX = false
    self.LockCameraY = false
    self.MPPedPreviews = UserDefaults.get_bool('mpPedPreviews')
    self.ShowLocationBlips = UserDefaults.get_bool('miscLocationBlips')
    self.ShowPlayerBlips = UserDefaults.get_bool('miscShowPlayerBlips')
    self.MiscShowOverheadNames = UserDefaults.get_bool('miscShowOverheadNames')
    self.ShowVehicleModelDimensions = false
    self.ShowPedModelDimensions = false
    self.ShowPropModelDimensions = false
    self.ShowEntityHandles = false
    self.ShowEntityModels = false
    self.ShowEntityNetOwners = false
    self.MiscRespawnDefaultCharacter = UserDefaults.get_bool('miscRespawnDefaultCharacter')
    self.RestorePlayerAppearance = UserDefaults.get_bool('miscRestorePlayerAppearance')
    self.RestorePlayerWeapons = UserDefaults.get_bool('miscRestorePlayerWeapons')
    self.DrawTimeOnScreen = UserDefaults.get_bool('miscShowTime')
    self.MiscRightAlignMenu = UserDefaults.get_bool('miscRightAlignMenu')
    self.MiscDisableControllerSupport = UserDefaults.get_bool('miscDisableControllerSupport')

    self.TimecycleEnabled = false
    self.LastTimeCycleModifierIndex = UserDefaults.get_int('miscLastTimeCycleModifierIndex')
    self.LastTimeCycleModifierStrength = UserDefaults.get_int('miscLastTimeCycleModifierStrength')

    -- The pms-disabled flag replicates through the local player statebag.
    local function set_disable_pms(value)
        self.MiscDisablePrivateMessages = value
        LocalPlayer.state:set('vmenu_pms_disabled', value, true)
    end
    set_disable_pms(UserDefaults.get_bool('miscDisablePrivateMessages'))

    -- Keybind states.
    self.KbTpToWaypoint = UserDefaults.get_bool('kbTpToWaypoint')
    local configured_tp_key = Config.get_int('vmenu_teleport_to_wp_keybind_key')
    self.KbTpToWaypointKey = configured_tp_key ~= -1 and configured_tp_key or 168 -- F7 by default
    self.KbDriftMode = UserDefaults.get_bool('kbDriftMode')
    self.KbRecordKeys = UserDefaults.get_bool('kbRecordKeys')
    self.KbRadarKeys = UserDefaults.get_bool('kbRadarKeys')
    self.KbPointKeys = UserDefaults.get_bool('kbPointKeys')

    -- Menu alignment (the setter refuses Right on ultra-wide ratios).
    local effective = Controller.SetMenuAlignment(self.MiscRightAlignMenu and 'Right' or 'Left')
    if effective ~= (self.MiscRightAlignMenu and 'Right' or 'Left') then
        Notify.error(Notification.error_message('RightAlignedNotSupported'))
        Controller.SetMenuAlignment('Left')
        self.MiscRightAlignMenu = false
        UserDefaults.set_bool('miscRightAlignMenu', false)
    end

    local player_name = GetPlayerName(PlayerId())
    local menu = Menu.new(player_name, 'Misc Settings')
    local teleport_options_menu = Menu.new(player_name, 'Teleport Options')
    local developer_tools_menu = Menu.new(player_name, 'Development Tools')

    -- Teleport locations submenu.
    local teleport_menu = Menu.new(player_name, 'Teleport Locations')
    local teleport_menu_btn =
        Items.MenuItem.new('Teleport Locations', 'Teleport to pre-configured locations, added by the server owner.')
    Controller.AddSubmenu(menu, teleport_menu)
    Controller.BindMenuItem(menu, teleport_menu, teleport_menu_btn)

    -- Keybind settings submenu.
    local keybind_menu = Menu.new(player_name, 'Keybind Settings')
    local keybind_menu_btn = Items.MenuItem.new('Keybind Settings', 'Enable or disable keybinds for some options.')
    Controller.AddSubmenu(menu, keybind_menu)
    Controller.BindMenuItem(menu, keybind_menu, keybind_menu_btn)

    local kb_tp_to_waypoint = Items.MenuCheckboxItem.new(
        'Teleport To Waypoint',
        'Teleport to your waypoint when pressing the keybind. By default, this keybind is set to ~r~F7~s~, '
            .. "server owners are able to change this however so ask them if you don't know what it is.",
        self.KbTpToWaypoint
    )
    local kb_drift_mode = Items.MenuCheckboxItem.new(
        'Drift Mode',
        'Makes your vehicle have almost no traction while holding left shift on keyboard, or X on controller.',
        self.KbDriftMode
    )
    local kb_record_keys = Items.MenuCheckboxItem.new(
        'Recording Controls',
        'Enables or disables the recording (gameplay recording for the Rockstar editor) hotkeys on both '
            .. 'keyboard and controller.',
        self.KbRecordKeys
    )
    local kb_radar_keys = Items.MenuCheckboxItem.new(
        'Minimap Controls',
        'Press the Multiplayer Info (z on keyboard, down arrow on controller) key to switch between expanded '
            .. 'radar and normal radar.',
        self.KbRadarKeys
    )
    local kb_point_keys = Items.MenuCheckboxItem.new(
        'Finger Point Controls',
        "Enables the finger point toggle key. The default QWERTY keyboard mapping for this is 'B', or for "
            .. 'controller quickly double tap the right analog stick.',
        self.KbPointKeys
    )
    local back_btn = Items.MenuItem.new('Back')

    local right_align_menu = Items.MenuCheckboxItem.new(
        'Right Align Menu',
        'If you want vMenu to appear on the left side of your screen, disable this option. This option will be '
            .. "saved immediately. You don't need to click save preferences.",
        self.MiscRightAlignMenu
    )
    local disable_pms = Items.MenuCheckboxItem.new(
        'Disable Private Messages',
        'Prevent others from sending you a private message via the Online Players menu. This also prevents you '
            .. 'from sending messages to other players.',
        self.MiscDisablePrivateMessages
    )
    local disable_controller_key = Items.MenuCheckboxItem.new(
        'Disable Controller Support',
        'This disables the controller menu toggle key. This does NOT disable the navigation buttons.',
        self.MiscDisableControllerSupport
    )
    local speed_kmh = Items.MenuCheckboxItem.new(
        'Show Speed KM/H',
        'Show a speedometer on your screen indicating your speed in KM/h.',
        self.ShowSpeedoKmh
    )
    local speed_mph = Items.MenuCheckboxItem.new(
        'Show Speed MPH',
        'Show a speedometer on your screen indicating your speed in MPH.',
        self.ShowSpeedoMph
    )
    local coords = Items.MenuCheckboxItem.new(
        'Show Coordinates',
        'Show your current coordinates at the top of your screen.',
        self.ShowCoordinates
    )
    local hide_radar = Items.MenuCheckboxItem.new('Hide Radar', 'Hide the radar/minimap.', self.HideRadar)
    local hide_hud = Items.MenuCheckboxItem.new('Hide Hud', 'Hide all hud elements.', self.HideHud)
    local show_location = Items.MenuCheckboxItem.new(
        'Location Display',
        'Shows your current location and heading, as well as the nearest cross road. Similar like PLD. '
            .. '~r~Warning: This feature (can) take(s) up to -4.6 FPS when running at 60 Hz.',
        self.ShowLocation
    )
    show_location.LeftIcon = Items.Icon.WARNING
    local draw_time = Items.MenuCheckboxItem.new(
        'Show Time On Screen',
        'Shows you the current time on screen.',
        self.DrawTimeOnScreen
    )
    local save_settings_btn = Items.MenuItem.new(
        'Save Personal Settings',
        'Save your current settings. All saving is done on the client side, if you re-install windows you will '
            .. 'lose your settings. Settings are shared across all servers using vMenu.'
    )
    save_settings_btn.RightIcon = Items.Icon.TICK
    local join_quit_notifs = Items.MenuCheckboxItem.new(
        'Join / Quit Notifications',
        'Receive notifications when someone joins or leaves the server.',
        self.JoinQuitNotifications
    )
    local death_notifs = Items.MenuCheckboxItem.new(
        'Death Notifications',
        'Receive notifications when someone dies or gets killed.',
        self.DeathNotifications
    )
    local night_vision = Items.MenuCheckboxItem.new('Toggle Night Vision', 'Enable or disable night vision.', false)
    local thermal_vision =
        Items.MenuCheckboxItem.new('Toggle Thermal Vision', 'Enable or disable thermal vision.', false)
    local veh_dimensions = Items.MenuCheckboxItem.new(
        'Show Vehicle Dimensions',
        "Draws the model outlines for every vehicle that's currently close to you.",
        self.ShowVehicleModelDimensions
    )
    local prop_dimensions = Items.MenuCheckboxItem.new(
        'Show Prop Dimensions',
        "Draws the model outlines for every prop that's currently close to you.",
        self.ShowPropModelDimensions
    )
    local ped_dimensions = Items.MenuCheckboxItem.new(
        'Show Ped Dimensions',
        "Draws the model outlines for every ped that's currently close to you.",
        self.ShowPedModelDimensions
    )
    local entity_handles = Items.MenuCheckboxItem.new(
        'Show Entity Handles',
        'Draws the the entity handles for all close entities (you must enable the outline functions above for '
            .. 'this to work).',
        self.ShowEntityHandles
    )
    local entity_models = Items.MenuCheckboxItem.new(
        'Show Entity Models',
        'Draws the the entity models for all close entities (you must enable the outline functions above for '
            .. 'this to work).',
        self.ShowEntityModels
    )
    local entity_net_owners = Items.MenuCheckboxItem.new(
        'Show Network Owners',
        'Draws the the entity net owner for all close entities (you must enable the outline functions above '
            .. 'for this to work).',
        self.ShowEntityNetOwners
    )
    local dimensions_distance_slider =
        Items.MenuSliderItem.new('Show Dimensions Radius', 0, 20, 20, 'Show entity model/handle/dimension draw range.')

    local clear_area = Items.MenuItem.new(
        'Clear Area',
        'Clears the area around your player (100 meters). Damage, dirt, peds, props, vehicles, etc. Everything '
            .. 'gets cleaned up, fixed and reset to the default world state.'
    )
    local lock_cam_x = Items.MenuCheckboxItem.new(
        'Lock Camera Horizontal Rotation',
        'Locks your camera horizontal rotation. Could be useful in helicopters I guess.',
        false
    )
    local lock_cam_y = Items.MenuCheckboxItem.new(
        'Lock Camera Vertical Rotation',
        'Locks your camera vertical rotation. Could be useful in helicopters I guess.',
        false
    )
    local mp_ped_preview = Items.MenuCheckboxItem.new(
        '3D MP Ped Preview',
        'Shows a 3D Ped preview when viewing saved MP Peds.',
        self.MPPedPreviews
    )

    -- Connection options submenu.
    local connection_submenu = Menu.new(player_name, 'Connection Options')
    local connection_submenu_btn = Items.MenuItem.new('Connection Options', 'Server connection/game quit options.')

    local quit_session = Items.MenuItem.new(
        'Quit Session',
        'Leaves you connected to the server, but quits the network session. ~r~Can not be used when you are '
            .. 'the host.'
    )
    local rejoin_session = Items.MenuItem.new(
        'Re-join Session',
        'This may not work in all cases, but you can try to use this if you want to re-join the previous '
            .. "session after clicking 'Quit Session'."
    )
    local quit_game = Items.MenuItem.new('Quit Game', 'Exits the game after 5 seconds.')
    local disconnect = Items.MenuItem.new(
        'Disconnect From Server',
        'Disconnects you from the server and returns you to the serverlist. ~r~This feature is not recommended, '
            .. 'quit the game completely instead and restart it for a better experience.'
    )
    connection_submenu:AddMenuItem(quit_session)
    connection_submenu:AddMenuItem(rejoin_session)
    connection_submenu:AddMenuItem(quit_game)
    connection_submenu:AddMenuItem(disconnect)

    -- Timecycle modifiers (labels get " (i/total)" suffixes).
    local enable_timecycle = Items.MenuCheckboxItem.new(
        'Enable Timecycle Modifier',
        'Enable or disable the timecycle modifier from the list below.',
        self.TimecycleEnabled
    )
    local timecycle_labels = {}
    for i, name in ipairs(TimeCycles.timecycles) do
        timecycle_labels[i] = ('%s (%d/%d)'):format(name, i, #TimeCycles.timecycles)
    end
    local start_index = math.min(math.max(self.LastTimeCycleModifierIndex, 0), math.max(0, #timecycle_labels - 1))
    local timecycles = Items.MenuListItem.new(
        'TM',
        timecycle_labels,
        start_index,
        'Select a timecycle modifier and enable the checkbox above.'
    )
    local timecycle_intensity = Items.MenuSliderItem.new(
        'Timecycle Modifier Intensity',
        0,
        20,
        self.LastTimeCycleModifierStrength,
        'Set the timecycle modifier intensity.'
    )

    local location_blips = Items.MenuCheckboxItem.new(
        'Location Blips',
        'Shows blips on the map for some common locations.',
        self.ShowLocationBlips
    )
    local player_blips = Items.MenuCheckboxItem.new(
        'Show Player Blips',
        'Shows blips on the map for all players. ~y~Note for when the server is using OneSync Infinity: this '
            .. "won't work for players that are too far away.",
        self.ShowPlayerBlips
    )
    local player_names = Items.MenuCheckboxItem.new(
        'Show Player Names',
        'Enables or disables player overhead names.',
        self.MiscShowOverheadNames
    )
    local respawn_default_character = Items.MenuCheckboxItem.new(
        'Respawn As Default MP Character',
        'If you enable this, then you will (re)spawn as your default saved MP character. Note the server owner '
            .. 'can globally disable this option. To set your default character, go to one of your saved MP '
            .. "Characters and click the 'Set As Default Character' button.",
        self.MiscRespawnDefaultCharacter
    )
    local restore_appearance = Items.MenuCheckboxItem.new(
        'Restore Player Appearance',
        "Restore your player's skin whenever you respawn after being dead. Re-joining a server will not restore "
            .. 'your previous skin.',
        self.RestorePlayerAppearance
    )
    local restore_weapons = Items.MenuCheckboxItem.new(
        'Restore Player Weapons',
        'Restore your weapons whenever you respawn after being dead. Re-joining a server will not restore your '
            .. 'previous weapons.',
        self.RestorePlayerWeapons
    )

    Controller.AddSubmenu(menu, connection_submenu)
    Controller.BindMenuItem(menu, connection_submenu, connection_submenu_btn)

    keybind_menu.OnCheckboxChange = function(_, item, _index, checked)
        if item == kb_tp_to_waypoint then
            self.KbTpToWaypoint = checked
        elseif item == kb_drift_mode then
            self.KbDriftMode = checked
        elseif item == kb_record_keys then
            self.KbRecordKeys = checked
        elseif item == kb_radar_keys then
            self.KbRadarKeys = checked
        elseif item == kb_point_keys then
            self.KbPointKeys = checked
        end
    end
    keybind_menu.OnItemSelect = function(_, item, _index)
        if item == back_btn then
            keybind_menu:GoBack()
        end
    end

    connection_submenu.OnItemSelect = function(_, item, _index)
        if item == quit_game then
            Common.quit_game()
        elseif item == quit_session then
            if NetworkIsSessionActive() then
                if NetworkIsHost() then
                    Notify.error(
                        'Sorry, you cannot leave the session when you are the host. This would prevent other '
                            .. 'players from joining/staying on the server.'
                    )
                else
                    Common.quit_session()
                end
            else
                Notify.error('You are currently not in any session.')
            end
        elseif item == rejoin_session then
            if NetworkIsSessionActive() then
                Notify.error('You are already connected to a session.')
            else
                Notify.info('Attempting to re-join the session.')
                NetworkSessionHost(-1, 32, false)
            end
        elseif item == disconnect then
            RegisterCommand('disconnect', function() end, false)
            ExecuteCommand('disconnect')
        end
    end

    -- Teleport options.
    if
        Permissions.is_allowed('MSTeleportToWp')
        or Permissions.is_allowed('MSTeleportLocations')
        or Permissions.is_allowed('MSTeleportToCoord')
    then
        local teleport_options_menu_btn = Items.MenuItem.new('Teleport Options', 'Various teleport options.')
        teleport_options_menu_btn.Label = '→→→'
        menu:AddMenuItem(teleport_options_menu_btn)
        Controller.BindMenuItem(menu, teleport_options_menu, teleport_options_menu_btn)

        local tp_to_wp = Items.MenuItem.new('Teleport To Waypoint', 'Teleport to the waypoint on your map.')
        local tp_to_coord = Items.MenuItem.new(
            'Teleport To Coords',
            'Enter x, y, z coordinates and you will be teleported to that location.'
        )
        local save_location_btn = Items.MenuItem.new(
            'Save Teleport Location',
            'Adds your current location to the teleport locations menu and saves it on the server.'
        )

        teleport_options_menu.OnItemSelect = function(_, item, _index)
            if item == tp_to_wp then
                Common.teleport_to_wp()
            elseif item == tp_to_coord then
                local function read_coord(axis)
                    local value = Common.get_user_input(('Enter %s coordinate.'):format(axis))
                    if value == nil or value == '' then
                        Notify.error(Notification.error_message('InvalidInput'))
                        return nil
                    end
                    local parsed = tonumber(value)
                    if parsed == nil then
                        Notify.error(('You did not enter a valid %s coordinate.'):format(axis))
                        return nil
                    end
                    return parsed + 0.0
                end
                local pos_x = read_coord('X')
                if pos_x == nil then
                    return
                end
                local pos_y = read_coord('Y')
                if pos_y == nil then
                    return
                end
                local pos_z = read_coord('Z')
                if pos_z == nil then
                    return
                end
                Common.teleport_to_coords({ x = pos_x, y = pos_y, z = pos_z }, true)
            elseif item == save_location_btn then
                Common.save_player_location_to_locations_file()
            end
        end

        if Permissions.is_allowed('MSTeleportToWp') then
            teleport_options_menu:AddMenuItem(tp_to_wp)
            keybind_menu:AddMenuItem(kb_tp_to_waypoint)
        end
        if Permissions.is_allowed('MSTeleportToCoord') then
            teleport_options_menu:AddMenuItem(tp_to_coord)
        end
        if Permissions.is_allowed('MSTeleportLocations') then
            teleport_options_menu:AddMenuItem(teleport_menu_btn)
            Controller.AddSubmenu(teleport_options_menu, teleport_menu)
            Controller.BindMenuItem(teleport_options_menu, teleport_menu, teleport_menu_btn)
            teleport_menu_btn.Label = '→→→'

            teleport_menu.OnMenuOpen = function(_)
                if teleport_menu:Size() ~= #State.teleport_locations then
                    teleport_menu:ClearMenuItems()
                    for _, location in ipairs(State.teleport_locations) do
                        local c = location.coordinates or {}
                        local description = ('Teleport to ~y~%s~n~~s~x: ~y~%.2f~n~~s~y: ~y~%.2f'):format(
                            location.name,
                            c.x or 0.0,
                            c.y or 0.0
                        ) .. ('~n~~s~z: ~y~%.2f~n~~s~heading: ~y~%.2f'):format(
                            c.z or 0.0,
                            location.heading or 0.0
                        )
                        local tp_btn = Items.MenuItem.new(location.name, description)
                        tp_btn.ItemData = location
                        teleport_menu:AddMenuItem(tp_btn)
                    end
                end
            end

            teleport_menu.OnItemSelect = function(_, item, _index)
                local location = item.ItemData
                if type(location) == 'table' and location.coordinates ~= nil then
                    Common.teleport_to_coords(location.coordinates, true)
                    SetEntityHeading(PlayerPedId(), location.heading or 0.0)
                    SetGameplayCamRelativeHeading(0.0)
                end
            end

            if Permissions.is_allowed('MSTeleportSaveLocation') then
                teleport_options_menu:AddMenuItem(save_location_btn)
            end
        end
    end

    -- Developer tools.
    local dev_tools_btn = Items.MenuItem.new('Developer Tools', 'Various development/debug tools.')
    dev_tools_btn.Label = '→→→'
    menu:AddMenuItem(dev_tools_btn)
    Controller.AddSubmenu(menu, developer_tools_menu)
    Controller.BindMenuItem(menu, developer_tools_menu, dev_tools_btn)

    if Permissions.is_allowed('MSClearArea') then
        developer_tools_menu:AddMenuItem(clear_area)
    end
    if Permissions.is_allowed('MSShowCoordinates') then
        developer_tools_menu:AddMenuItem(coords)
    end

    -- Model outlines (disabled server-wide via convar).
    if not Config.get_bool('vmenu_disable_entity_outlines_tool') and Permissions.is_allowed('MSDevTools') then
        developer_tools_menu:AddMenuItem(veh_dimensions)
        developer_tools_menu:AddMenuItem(prop_dimensions)
        developer_tools_menu:AddMenuItem(ped_dimensions)
        developer_tools_menu:AddMenuItem(entity_handles)
        developer_tools_menu:AddMenuItem(entity_models)
        developer_tools_menu:AddMenuItem(entity_net_owners)
        developer_tools_menu:AddMenuItem(dimensions_distance_slider)
    end

    developer_tools_menu:AddMenuItem(timecycles)
    developer_tools_menu:AddMenuItem(enable_timecycle)
    developer_tools_menu:AddMenuItem(timecycle_intensity)

    local function apply_timecycle()
        ClearTimecycleModifier()
        if self.TimecycleEnabled then
            SetTimecycleModifier(TimeCycles.timecycles[timecycles.ListIndex + 1])
            SetTimecycleModifierStrength(timecycle_intensity.Position / 20)
        end
        UserDefaults.set_int('miscLastTimeCycleModifierIndex', timecycles.ListIndex)
        UserDefaults.set_int('miscLastTimeCycleModifierStrength', timecycle_intensity.Position)
        self.LastTimeCycleModifierIndex = timecycles.ListIndex
        self.LastTimeCycleModifierStrength = timecycle_intensity.Position
    end

    developer_tools_menu.OnSliderPositionChange = function(_, item, _old_pos, new_pos, _item_index)
        if item == timecycle_intensity then
            apply_timecycle()
        elseif item == dimensions_distance_slider then
            State.entity_range = new_pos / 20 * 2000.0 -- max radius = 2000
        end
    end

    developer_tools_menu.OnListIndexChange = function(_, item, _old_index, _new_index, _item_index)
        if item == timecycles then
            apply_timecycle()
        end
    end

    developer_tools_menu.OnItemSelect = function(_, item, _index)
        if item == clear_area then
            TriggerServerEvent('vMenu:ClearArea')
        end
    end

    developer_tools_menu.OnCheckboxChange = function(_, item, _index, checked)
        if item == veh_dimensions then
            self.ShowVehicleModelDimensions = checked
        elseif item == prop_dimensions then
            self.ShowPropModelDimensions = checked
        elseif item == ped_dimensions then
            self.ShowPedModelDimensions = checked
        elseif item == entity_handles then
            self.ShowEntityHandles = checked
        elseif item == entity_models then
            self.ShowEntityModels = checked
        elseif item == entity_net_owners then
            self.ShowEntityNetOwners = checked
        elseif item == enable_timecycle then
            self.TimecycleEnabled = checked
            ClearTimecycleModifier()
            if self.TimecycleEnabled then
                SetTimecycleModifier(TimeCycles.timecycles[timecycles.ListIndex + 1])
                SetTimecycleModifierStrength(timecycle_intensity.Position / 20)
            end
        elseif item == coords then
            self.ShowCoordinates = checked
        end
    end

    -- Entity spawner (appears once the M9 module lands).
    if Permissions.is_allowed('MSEntitySpawner') then
        local EntitySpawner = try_require('client.entity_spawner')
        if EntitySpawner then
            local entity_spawner_menu = Menu.new(player_name, 'Entity Spawner')
            local ent_spawner_btn = Items.MenuItem.new('Entity Spawner', 'Spawn and move entities')
            ent_spawner_btn.Label = '→→→'
            developer_tools_menu:AddMenuItem(ent_spawner_btn)
            Controller.BindMenuItem(developer_tools_menu, entity_spawner_menu, ent_spawner_btn)
            EntitySpawner.fill_menu(entity_spawner_menu)
        end
    end

    -- Keybind options.
    if Permissions.is_allowed('MSDriftMode') then
        keybind_menu:AddMenuItem(kb_drift_mode)
    end
    keybind_menu:AddMenuItem(kb_record_keys)
    keybind_menu:AddMenuItem(kb_radar_keys)
    keybind_menu:AddMenuItem(kb_point_keys)
    keybind_menu:AddMenuItem(back_btn)

    -- Always allowed.
    menu:AddMenuItem(right_align_menu)
    menu:AddMenuItem(disable_pms)
    menu:AddMenuItem(disable_controller_key)
    menu:AddMenuItem(speed_kmh)
    menu:AddMenuItem(speed_mph)
    menu:AddMenuItem(keybind_menu_btn)
    keybind_menu_btn.Label = '→→→'
    if Permissions.is_allowed('MSConnectionMenu') then
        menu:AddMenuItem(connection_submenu_btn)
        connection_submenu_btn.Label = '→→→'
    end
    if Permissions.is_allowed('MSShowLocation') then
        menu:AddMenuItem(show_location)
    end
    menu:AddMenuItem(draw_time)
    if Permissions.is_allowed('MSJoinQuitNotifs') then
        menu:AddMenuItem(join_quit_notifs)
    end
    if Permissions.is_allowed('MSDeathNotifs') then
        menu:AddMenuItem(death_notifs)
    end
    if Permissions.is_allowed('MSNightVision') then
        menu:AddMenuItem(night_vision)
    end
    if Permissions.is_allowed('MSThermalVision') then
        menu:AddMenuItem(thermal_vision)
    end

    -- Location blips (with toggling on/off).
    local active_blips = {}
    local function toggle_blips(enable)
        if enable then
            local blips_data = Config.get_location_blips()
            for _, bl in ipairs(blips_data) do
                local c = bl.coordinates or {}
                local blip_id = AddBlipForCoord(c.x or 0.0, c.y or 0.0, c.z or 0.0)
                SetBlipSprite(blip_id, bl.spriteID or 1)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentSubstringPlayerName(bl.name or '')
                EndTextCommandSetBlipName(blip_id)
                SetBlipColour(blip_id, bl.color or 0)
                SetBlipAsShortRange(blip_id, true)
                active_blips[#active_blips + 1] = blip_id
            end
        else
            for _, blip_id in ipairs(active_blips) do
                if DoesBlipExist(blip_id) then
                    RemoveBlip(blip_id)
                end
            end
            active_blips = {}
        end
    end

    if Permissions.is_allowed('MSLocationBlips') then
        menu:AddMenuItem(location_blips)
        toggle_blips(self.ShowLocationBlips)
    end
    if Permissions.is_allowed('MSPlayerBlips') then
        menu:AddMenuItem(player_blips)
    end
    if Permissions.is_allowed('MSOverheadNames') then
        menu:AddMenuItem(player_names)
    end
    -- Always allowed: it just does nothing if the server disabled it.
    menu:AddMenuItem(respawn_default_character)
    if Permissions.is_allowed('MSRestoreAppearance') then
        menu:AddMenuItem(restore_appearance)
    end
    if Permissions.is_allowed('MSRestoreWeapons') then
        menu:AddMenuItem(restore_weapons)
    end

    menu:AddMenuItem(hide_radar)
    menu:AddMenuItem(hide_hud)
    menu:AddMenuItem(lock_cam_x)
    menu:AddMenuItem(lock_cam_y)

    -- Hidden entirely when disabled at the server level.
    if Config.get_bool('vmenu_mp_ped_preview') then
        menu:AddMenuItem(mp_ped_preview)
    end

    menu:AddMenuItem(save_settings_btn)

    menu.OnCheckboxChange = function(_, item, _index, checked)
        if item == right_align_menu then
            local wanted = checked and 'Right' or 'Left'
            self.MiscRightAlignMenu = checked
            UserDefaults.set_bool('miscRightAlignMenu', checked)
            if Controller.SetMenuAlignment(wanted) ~= wanted then
                Notify.error(Notification.error_message('RightAlignedNotSupported'))
                Controller.SetMenuAlignment('Left')
                self.MiscRightAlignMenu = false
                UserDefaults.set_bool('miscRightAlignMenu', false)
            end
        elseif item == disable_pms then
            set_disable_pms(checked)
        elseif item == disable_controller_key then
            self.MiscDisableControllerSupport = checked
            Controller.EnableMenuToggleKeyOnController = not checked
        elseif item == speed_kmh then
            self.ShowSpeedoKmh = checked
        elseif item == speed_mph then
            self.ShowSpeedoMph = checked
        elseif item == hide_hud then
            self.HideHud = checked
            DisplayHud(not checked)
        elseif item == hide_radar then
            self.HideRadar = checked
            if not checked then
                DisplayRadar(true)
            end
        elseif item == show_location then
            self.ShowLocation = checked
        elseif item == draw_time then
            self.DrawTimeOnScreen = checked
        elseif item == death_notifs then
            self.DeathNotifications = checked
        elseif item == join_quit_notifs then
            self.JoinQuitNotifications = checked
        elseif item == night_vision then
            SetNightvision(checked)
        elseif item == thermal_vision then
            SetSeethrough(checked)
        elseif item == lock_cam_x then
            self.LockCameraX = checked
        elseif item == lock_cam_y then
            self.LockCameraY = checked
        elseif item == mp_ped_preview then
            self.MPPedPreviews = checked
        elseif item == location_blips then
            toggle_blips(checked)
            self.ShowLocationBlips = checked
        elseif item == player_blips then
            self.ShowPlayerBlips = checked
        elseif item == player_names then
            self.MiscShowOverheadNames = checked
        elseif item == respawn_default_character then
            self.MiscRespawnDefaultCharacter = checked
        elseif item == restore_appearance then
            self.RestorePlayerAppearance = checked
        elseif item == restore_weapons then
            self.RestorePlayerWeapons = checked
        end
    end

    menu.OnItemSelect = function(_, item, _index)
        if item == save_settings_btn then
            UserDefaults.save_settings()
        end
    end

    self.menu = menu
    return self
end

return MiscSettings
