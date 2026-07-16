-- Port of vMenu/menus/PlayerOptions.cs: player toggles, wanted/armor/blood,
-- the vehicle auto-pilot submenu, and scenarios. The toggles set public
-- fields here; the per-frame enforcement (god mode etc.) is the
-- FunctionsController port (M9).

local Permissions = require('shared.permissions')
local Common = require('client.common')
local Notification = require('client.notify')
local UserDefaults = require('client.user_defaults')
local NoClip = require('client.noclip')
local PedScenarios = require('client.data.ped_scenarios')
local Controller = require('menu.controller')
local Items = require('menu.items')
local Menu = require('menu.menu')

local Notify = Notification.Notify

local PlayerOptions = {}

local BLOOD_LIST = {
    'BigHitByVehicle',
    'SCR_Torture',
    'SCR_TrevorTreeBang',
    'HOSPITAL_0',
    'HOSPITAL_1',
    'HOSPITAL_2',
    'HOSPITAL_3',
    'HOSPITAL_4',
    'HOSPITAL_5',
    'HOSPITAL_6',
    'HOSPITAL_7',
    'HOSPITAL_8',
    'HOSPITAL_9',
    'Explosion_Med',
    'Skin_Melee_0',
    'Explosion_Large',
    'Car_Crash_Light',
    'Car_Crash_Heavy',
    'Fall_Low',
    'Fall',
    'HitByVehicle',
    'BigRunOverByVehicle',
    'RunOverByVehicle',
    'TD_KNIFE_FRONT',
    'TD_KNIFE_FRONT_VA',
    'TD_KNIFE_FRONT_VB',
    'TD_KNIFE_REAR',
    'TD_KNIFE_REAR_VA',
    'TD_KNIFE_REAR_VB',
    'TD_KNIFE_STEALTH',
    'TD_MELEE_FRONT',
    'TD_MELEE_REAR',
    'TD_MELEE_STEALTH',
    'TD_MELEE_BATWAIST',
    'TD_melee_face_l',
    'MTD_melee_face_r',
    'MTD_melee_face_jaw',
    'TD_PISTOL_FRONT',
    'TD_PISTOL_FRONT_KILL',
    'TD_PISTOL_REAR',
    'TD_PISTOL_REAR_KILL',
    'TD_RIFLE_FRONT_KILL',
    'TD_RIFLE_NONLETHAL_FRONT',
    'TD_RIFLE_NONLETHAL_REAR',
    'TD_SHOTGUN_FRONT_KILL',
    'TD_SHOTGUN_REAR_KILL',
}

-- The 32 custom driving style flags (index 0-31); unknown ones show red.
local DRIVING_FLAG_NAMES = {
    [0] = 'Stop for vehicles',
    [1] = 'Stop for pedestrians',
    [2] = 'Swerve around all vehicles',
    [3] = 'Steer around stationary vehicles',
    [4] = 'Steer around pedestrians',
    [5] = 'Steer around objects',
    [6] = "Don't steer around Player",
    [7] = 'Stop at lights',
    [8] = 'Go off road when avoiding',
    [9] = 'Drive into oncoming traffic',
    [10] = 'Drive in reverse',
    [11] = 'Use wander fallback instead of straight line',
    [12] = 'Avoid restricted areas',
    [13] = 'Prevent background pathfinding',
    [14] = 'Adjust speed for current road',
    [15] = 'Prevent join in road direction when moving',
    [16] = "Don't avoid target",
    [17] = 'Target position overrides entity',
    [18] = 'Use shortcut links (Use shortest path)',
    [19] = 'Change lanes around obstructions',
    [20] = 'Avoid target coords',
    [21] = 'Use switched-off nodes',
    [22] = 'Prefer navmesh route',
    [23] = 'Plane taxi mode',
    [24] = 'Force straight line',
    [25] = 'Use string pulling at junctions',
    [26] = 'Avoid Adverse Conditions',
    [27] = 'Avoid turns',
    [28] = 'Extend route with wander results',
    [29] = 'Avoid highways (if possible)',
    [30] = 'Force join in road direction',
    [31] = "Don't terminate task when achieved",
}

function PlayerOptions.create()
    local self = {}

    -- Public state (FunctionsController M9 + UserDefaults.save_settings).
    self.PlayerGodMode = UserDefaults.get_bool('playerGodMode')
    self.PlayerInvisible = false
    self.PlayerStamina = UserDefaults.get_bool('unlimitedStamina')
    self.PlayerFastRun = UserDefaults.get_bool('fastRun')
    self.PlayerFastSwim = UserDefaults.get_bool('fastSwim')
    self.PlayerSuperJump = UserDefaults.get_bool('superJump')
    self.PlayerNoRagdoll = UserDefaults.get_bool('noRagdoll')
    self.PlayerNeverWanted = UserDefaults.get_bool('neverWanted')
    self.PlayerIsIgnored = UserDefaults.get_bool('everyoneIgnorePlayer')
    self.PlayerStayInVehicle = UserDefaults.get_bool('playerStayInVehicle')
    self.PlayerFrozen = false
    self.PlayerBlood = 0

    local menu = Menu.new(GetPlayerName(PlayerId()), 'Player Options')

    local god_mode = Items.MenuCheckboxItem.new('Godmode', 'Makes you invincible.', self.PlayerGodMode)
    local invisible =
        Items.MenuCheckboxItem.new('Invisible', 'Makes you invisible to yourself and others.', self.PlayerInvisible)
    local unlimited_stamina = Items.MenuCheckboxItem.new(
        'Unlimited Stamina',
        'Allows you to run forever without slowing down or taking damage.',
        self.PlayerStamina
    )
    local fast_run =
        Items.MenuCheckboxItem.new('Fast Run', 'Get ~g~Snail~s~ powers and run very fast!', self.PlayerFastRun)
    SetRunSprintMultiplierForPlayer(
        PlayerId(),
        (self.PlayerFastRun and Permissions.is_allowed('POFastRun')) and 1.49 or 1.0
    )
    local fast_swim =
        Items.MenuCheckboxItem.new('Fast Swim', 'Get ~g~Snail 2.0~s~ powers and swim super fast!', self.PlayerFastSwim)
    SetSwimMultiplierForPlayer(
        PlayerId(),
        (self.PlayerFastSwim and Permissions.is_allowed('POFastSwim')) and 1.49 or 1.0
    )
    local super_jump = Items.MenuCheckboxItem.new(
        'Super Jump',
        'Get ~g~Snail 3.0~s~ powers and jump like a champ!',
        self.PlayerSuperJump
    )
    local no_ragdoll = Items.MenuCheckboxItem.new(
        'No Ragdoll',
        'Disables player ragdoll, makes you not fall off your bike anymore.',
        self.PlayerNoRagdoll
    )
    local never_wanted =
        Items.MenuCheckboxItem.new('Never Wanted', 'Disables all wanted levels.', self.PlayerNeverWanted)
    local everyone_ignores =
        Items.MenuCheckboxItem.new('Everyone Ignore Player', 'Everyone will leave you alone.', self.PlayerIsIgnored)
    local stay_in_vehicle = Items.MenuCheckboxItem.new(
        'Stay In Vehicle',
        'When this is enabled, NPCs will not be able to drag you out of your vehicle if they get angry at you.',
        self.PlayerStayInVehicle
    )
    local frozen = Items.MenuCheckboxItem.new('Freeze Player', 'Freezes your current location.', self.PlayerFrozen)

    local set_wanted_level = Items.MenuListItem.new(
        'Set Wanted Level',
        { 'No Wanted Level', '1', '2', '3', '4', '5' },
        GetPlayerWantedLevel(PlayerId()),
        'Set your wanted level by selecting a value, and pressing enter.'
    )
    local set_armor = Items.MenuListItem.new('Set Armor Type', {
        'No Armor',
        GetLabelText('WT_BA_0'),
        GetLabelText('WT_BA_1'),
        GetLabelText('WT_BA_2'),
        GetLabelText('WT_BA_3'),
        GetLabelText('WT_BA_4'),
    }, 0, 'Set the armor level/type for your player.')

    local clear_blood = Items.MenuItem.new('Clear Blood', 'Clear the blood off your player.')
    local set_blood_level =
        Items.MenuListItem.new('Set Blood Level', BLOOD_LIST, self.PlayerBlood, 'Sets your players blood level.')

    local heal_player = Items.MenuItem.new('Heal Player', 'Give the player max health.')
    local clean_player = Items.MenuItem.new('Clean Player Clothes', 'Clean your player clothes.')
    local dry_player = Items.MenuItem.new('Dry Player Clothes', 'Make your player clothes dry.')
    local wet_player = Items.MenuItem.new('Wet Player Clothes', 'Make your player clothes wet.')
    local suicide = Items.MenuItem.new(
        '~r~Commit Suicide',
        'Kill yourself by taking the pill. Or by using a pistol if you have one.'
    )

    local auto_pilot_menu = Menu.new('Auto Pilot', 'Vehicle auto pilot options.')
    Controller.AddSubmenu(menu, auto_pilot_menu)
    local auto_pilot_btn = Items.MenuItem.new('Vehicle Auto Pilot Menu', 'Manage vehicle auto pilot options.')
    auto_pilot_btn.Label = '→→→'

    local driving_styles = { 'Normal', 'Rushed', 'Avoid highways', 'Drive in reverse', 'Custom' }
    local driving_style = Items.MenuListItem.new(
        'Driving Style',
        driving_styles,
        0,
        'Set the driving style that is used for the Drive to Waypoint and Drive Around Randomly functions.'
    )

    local player_scenarios = Items.MenuListItem.new(
        'Player Scenarios',
        PedScenarios.scenarios,
        0,
        'Select a scenario and hit enter to start it. Selecting another scenario will override the current scenario. '
            .. "If you're already playing the selected scenario, selecting it again will stop the scenario."
    )
    local stop_scenario = Items.MenuItem.new(
        'Force Stop Scenario',
        'This will force a playing scenario to stop immediately, without waiting for it to finish '
            .. "it's 'stopping' animation."
    )

    -- Permission-gated items, in upstream order.
    if Permissions.is_allowed('POGod') then
        menu:AddMenuItem(god_mode)
    end
    if Permissions.is_allowed('POInvisible') then
        menu:AddMenuItem(invisible)
    end
    if Permissions.is_allowed('POUnlimitedStamina') then
        menu:AddMenuItem(unlimited_stamina)
    end
    if Permissions.is_allowed('POFastRun') then
        menu:AddMenuItem(fast_run)
    end
    if Permissions.is_allowed('POFastSwim') then
        menu:AddMenuItem(fast_swim)
    end
    if Permissions.is_allowed('POSuperjump') then
        menu:AddMenuItem(super_jump)
    end
    if Permissions.is_allowed('PONoRagdoll') then
        menu:AddMenuItem(no_ragdoll)
    end
    if Permissions.is_allowed('PONeverWanted') then
        menu:AddMenuItem(never_wanted)
    end
    if Permissions.is_allowed('POSetWanted') then
        menu:AddMenuItem(set_wanted_level)
    end
    if Permissions.is_allowed('POClearBlood') then
        menu:AddMenuItem(clear_blood)
    end
    if Permissions.is_allowed('POSetBlood') then
        menu:AddMenuItem(set_blood_level)
    end
    if Permissions.is_allowed('POIgnored') then
        menu:AddMenuItem(everyone_ignores)
    end
    if Permissions.is_allowed('POStayInVehicle') then
        menu:AddMenuItem(stay_in_vehicle)
    end
    if Permissions.is_allowed('POMaxHealth') then
        menu:AddMenuItem(heal_player)
    end
    if Permissions.is_allowed('POMaxArmor') then
        menu:AddMenuItem(set_armor)
    end
    if Permissions.is_allowed('POCleanPlayer') then
        menu:AddMenuItem(clean_player)
    end
    if Permissions.is_allowed('PODryPlayer') then
        menu:AddMenuItem(dry_player)
    end
    if Permissions.is_allowed('POWetPlayer') then
        menu:AddMenuItem(wet_player)
    end

    menu:AddMenuItem(suicide)

    -- Auto pilot submenu.
    local custom_style_menu = Menu.new('Driving Style', 'Custom Driving Style')
    if Permissions.is_allowed('POVehicleAutoPilotMenu') then
        menu:AddMenuItem(auto_pilot_btn)
        Controller.BindMenuItem(menu, auto_pilot_menu, auto_pilot_btn)

        auto_pilot_menu:AddMenuItem(driving_style)

        local start_driving_waypoint =
            Items.MenuItem.new('Drive To Waypoint', 'Make your player ped drive your vehicle to your waypoint.')
        local start_driving_randomly = Items.MenuItem.new(
            'Drive Around Randomly',
            'Make your player ped drive your vehicle randomly around the map.'
        )
        local stop_driving = Items.MenuItem.new(
            'Stop Driving',
            'The player ped will find a suitable place to stop the vehicle. The task will be stopped once the '
                .. 'vehicle has reached the suitable stop location.'
        )
        local force_stop_driving = Items.MenuItem.new(
            'Force Stop Driving',
            'This will stop the driving task immediately without finding a suitable place to stop.'
        )
        local custom_driving_style = Items.MenuItem.new(
            'Custom Driving Style',
            "Select a custom driving style. Make sure to also enable it by selecting the 'Custom' driving style "
                .. 'in the driving styles list.'
        )
        custom_driving_style.Label = '→→→'
        Controller.AddSubmenu(auto_pilot_menu, custom_style_menu)
        auto_pilot_menu:AddMenuItem(custom_driving_style)
        Controller.BindMenuItem(auto_pilot_menu, custom_style_menu, custom_driving_style)

        for i = 0, 31 do
            local name = DRIVING_FLAG_NAMES[i] or '~r~Unknown Flag'
            custom_style_menu:AddMenuItem(Items.MenuCheckboxItem.new(name, 'Toggle this driving style flag.', false))
        end

        -- GetCustomDrivingStyle: checkbox i = bit i of the style value.
        local function get_custom_driving_style()
            local style = 0
            for i, item in ipairs(custom_style_menu:GetMenuItems()) do
                if item.Checked then
                    style = style + (1 << (i - 1))
                end
            end
            return style
        end

        local function get_style_from_index(index)
            if index == 0 then
                return 443 -- normal
            elseif index == 1 then
                return 575 -- rushed
            elseif index == 2 then
                return 536871355 -- avoid highways
            elseif index == 3 then
                return 1467 -- go in reverse
            elseif index == 4 then
                return get_custom_driving_style()
            end
            return 0
        end
        self._get_style_from_index = get_style_from_index

        custom_style_menu.OnCheckboxChange = function(_, _item, _index, _checked)
            local style = get_style_from_index(driving_style.ListIndex)
            custom_style_menu.MenuSubtitle = ('custom style: %d'):format(style)
            if driving_style.ListIndex == 4 then
                Notify.custom('Driving style updated.')
                SetDriveTaskDrivingStyle(PlayerPedId(), style)
            else
                Notify.custom(
                    "Driving style NOT updated because you haven't enabled the Custom driving style "
                        .. 'in the previous menu.'
                )
            end
        end

        auto_pilot_menu:AddMenuItem(start_driving_waypoint)
        auto_pilot_menu:AddMenuItem(start_driving_randomly)
        auto_pilot_menu:AddMenuItem(stop_driving)
        auto_pilot_menu:AddMenuItem(force_stop_driving)

        auto_pilot_menu:RefreshIndex()

        auto_pilot_menu.OnItemSelect = function(_, item, _index)
            local ped = PlayerPedId()
            if IsPedInAnyVehicle(ped, false) and item ~= stop_driving and item ~= force_stop_driving then
                local vehicle = Common.get_vehicle()
                if
                    vehicle ~= 0
                    and DoesEntityExist(vehicle)
                    and not IsEntityDead(vehicle)
                    and IsVehicleDriveable(vehicle, false)
                then
                    if GetPedInVehicleSeat(vehicle, -1) == ped then
                        if item == start_driving_waypoint then
                            if IsWaypointActive() then
                                Common.drive_to_wp(get_style_from_index(driving_style.ListIndex))
                                Notify.info(
                                    'Your player ped is now driving the vehicle for you. You can cancel any time by '
                                        .. 'pressing the Stop Driving button. The vehicle will stop when it has '
                                        .. 'reached the destination.'
                                )
                            else
                                Notify.error('You need a waypoint before you can drive to it!')
                            end
                        elseif item == start_driving_randomly then
                            Common.drive_wander(get_style_from_index(driving_style.ListIndex))
                            Notify.info(
                                'Your player ped is now driving the vehicle for you. You can cancel any time by '
                                    .. 'pressing the Stop Driving button.'
                            )
                        end
                    else
                        Notify.error('You must be the driver of this vehicle!')
                    end
                else
                    Notify.error('Your vehicle is broken or it does not exist!')
                end
            elseif item ~= stop_driving and item ~= force_stop_driving then
                Notify.error('You need to be in a vehicle first!')
            end
            if item == stop_driving then
                if IsPedInAnyVehicle(ped, false) then
                    local vehicle = Common.get_vehicle()
                    if vehicle ~= 0 and DoesEntityExist(vehicle) and not IsEntityDead(vehicle) then
                        local pos = GetEntityCoords(ped)
                        local found, out_pos = GetNthClosestVehicleNode(pos.x, pos.y, pos.z, 3, 0, 0, 0)
                        if found then
                            Notify.info(
                                'The player ped will find a suitable place to park the car and will then stop '
                                    .. 'driving. Please wait.'
                            )
                            ClearPedTasks(ped)
                            TaskVehiclePark(
                                ped,
                                vehicle,
                                out_pos.x,
                                out_pos.y,
                                out_pos.z,
                                GetEntityHeading(ped),
                                3,
                                60.0,
                                true
                            )
                            while true do
                                local current = GetEntityCoords(ped)
                                local dx, dy = current.x - out_pos.x, current.y - out_pos.y
                                if dx * dx + dy * dy <= 3.0 then
                                    break
                                end
                                Wait(0)
                            end
                            SetVehicleHalt(vehicle, 3.0, 0, false)
                            ClearPedTasks(ped)
                            Notify.info('The player ped has stopped driving.')
                        end
                    end
                else
                    ClearPedTasks(ped)
                    Notify.alert('Your ped is not in any vehicle.')
                end
            elseif item == force_stop_driving then
                ClearPedTasks(ped)
                Notify.info('Driving task cancelled.')
            end
        end

        auto_pilot_menu.OnListItemSelect = function(_, item, list_index, _item_index)
            if item == driving_style then
                local style = get_style_from_index(list_index)
                SetDriveTaskDrivingStyle(PlayerPedId(), style)
                Notify.info(('Driving task style is now set to: ~r~%s~s~.'):format(driving_styles[list_index + 1]))
            end
        end
    end

    if Permissions.is_allowed('POFreeze') then
        menu:AddMenuItem(frozen)
    end
    if Permissions.is_allowed('POScenarios') then
        menu:AddMenuItem(player_scenarios)
        menu:AddMenuItem(stop_scenario)
    end

    menu.OnCheckboxChange = function(_, item, _index, checked)
        local ped = PlayerPedId()
        if item == god_mode then
            self.PlayerGodMode = checked
        elseif item == invisible then
            self.PlayerInvisible = checked
            SetEntityVisible(ped, not self.PlayerInvisible, false)
        elseif item == unlimited_stamina then
            self.PlayerStamina = checked
            StatSetInt(GetHashKey('MP0_STAMINA'), checked and 100 or 0, true)
        elseif item == fast_run then
            self.PlayerFastRun = checked
            SetRunSprintMultiplierForPlayer(PlayerId(), checked and 1.49 or 1.0)
        elseif item == fast_swim then
            self.PlayerFastSwim = checked
            SetSwimMultiplierForPlayer(PlayerId(), checked and 1.49 or 1.0)
        elseif item == super_jump then
            self.PlayerSuperJump = checked
        elseif item == no_ragdoll then
            self.PlayerNoRagdoll = checked
        elseif item == never_wanted then
            self.PlayerNeverWanted = checked
            SetMaxWantedLevel(checked and 0 or 5)
        elseif item == everyone_ignores then
            self.PlayerIsIgnored = checked
            SetEveryoneIgnorePlayer(PlayerId(), self.PlayerIsIgnored)
            SetPoliceIgnorePlayer(PlayerId(), self.PlayerIsIgnored)
            SetPlayerCanBeHassledByGangs(PlayerId(), not self.PlayerIsIgnored)
        elseif item == stay_in_vehicle then
            self.PlayerStayInVehicle = checked
        elseif item == frozen then
            self.PlayerFrozen = checked
            if not NoClip.is_noclip_active() then
                FreezeEntityPosition(ped, self.PlayerFrozen)
            end
        end
    end

    menu.OnListItemSelect = function(_, list_item, list_index, _item_index)
        local ped = PlayerPedId()
        if list_item == set_wanted_level then
            SetPlayerWantedLevel(PlayerId(), list_index, false)
            SetPlayerWantedLevelNow(PlayerId(), false)
        elseif list_item == set_blood_level then
            ApplyPedDamagePack(ped, BLOOD_LIST[list_index + 1], 100, 100)
        elseif list_item == player_scenarios then
            Common.play_scenario(PedScenarios.scenario_names[PedScenarios.scenarios[list_index + 1]])
        elseif list_item == set_armor then
            SetPedArmour(ped, list_item.ListIndex * 20)
        end
    end

    menu.OnItemSelect = function(_, item, _index)
        local ped = PlayerPedId()
        if item == stop_scenario then
            -- "forcestop" is the magic name play_scenario force-clears on.
            Common.play_scenario('forcestop')
        elseif item == clear_blood then
            ClearPedBloodDamage(ped)
            ResetPedVisibleDamage(ped)
            for zone = 0, 5 do
                ClearPedDamageDecalByZone(ped, zone, 'ALL')
            end
        elseif item == heal_player then
            SetEntityHealth(ped, GetEntityMaxHealth(ped))
            Notify.success('Player healed.')
        elseif item == clean_player then
            ClearPedBloodDamage(ped)
            Notify.success('Player clothes have been cleaned.')
        elseif item == dry_player then
            SetPedWetnessHeight(ped, 0.0)
            Notify.success('Player is now dry.')
        elseif item == wet_player then
            SetPedWetnessHeight(ped, 2.0)
            Notify.success('Player is now wet.')
        elseif item == suicide then
            Common.commit_suicide()
        end
    end

    self.menu = menu
    return self
end

return PlayerOptions
