-- Port of vMenu/CommonFunctions.cs, split by topic: the name sanitizer, the
-- private-message display, the server-event wrappers, user input, and the
-- session helpers the menus use. The vehicle save/apply half lives in
-- client/vehicle_common.lua and the ped half in client/ped_common.lua.

local Config = require('shared.config')
local Util = require('shared.util')
local Notification = require('client.notify')
local PlayerLists = require('client.player_lists')
local State = require('client.state')

local Common = {}

-- ---------------------------------------------------------------------------
-- Weather / time / session (thin server-event wrappers)
-- ---------------------------------------------------------------------------

function Common.update_server_weather(new_weather, dynamic_changes, is_snow_enabled)
    TriggerServerEvent('vMenu:UpdateServerWeather', new_weather, dynamic_changes, is_snow_enabled)
end

function Common.update_server_blackout(value)
    TriggerServerEvent('vMenu:UpdateServerBlackout', value)
end

function Common.update_server_vehicle_blackout(value)
    TriggerServerEvent('vMenu:UpdateServerVehicleBlackout', value)
end

-- ModifyClouds: true removes all clouds, false randomizes them.
function Common.modify_clouds(remove_clouds)
    TriggerServerEvent('vMenu:UpdateServerWeatherCloudsType', remove_clouds)
end

-- UpdateServerTime: invalid values collapse to 0 like upstream.
function Common.update_server_time(hours, minutes)
    local real_hours = (hours > 23 or hours < 0) and 0 or hours
    local real_minutes = (minutes > 59 or minutes < 0) and 0 or minutes
    TriggerServerEvent('vMenu:UpdateServerTime', real_hours, real_minutes, Common.is_server_time_frozen())
end

function Common.freeze_server_time(freeze_time)
    TriggerServerEvent('vMenu:FreezeServerTime', freeze_time)
end

-- EventManager's convar-backed getters that menus read.
function Common.is_server_time_frozen()
    return GetConvar('vmenu_freeze_time', 'false') == 'true'
end

function Common.quit_session()
    NetworkSessionEnd(true, true)
end

-- QuitGame: 5 second warning, then the "fun" exit.
function Common.quit_game()
    Notification.Notify.info('The game will exit in 5 seconds.')
    print('Game will be terminated in 5 seconds, because the player used the Quit Game option in vMenu.')
    CreateThread(function()
        Wait(5000)
        ForceSocialClubUpdate() -- bye bye
    end)
end

-- ---------------------------------------------------------------------------
-- Vehicles & driving tasks
-- ---------------------------------------------------------------------------

-- GetVehicle: the vehicle the local ped is in (or last vehicle), 0 if none.
function Common.get_vehicle(last_vehicle)
    if last_vehicle then
        return GetPlayersLastVehicle()
    end
    if IsPedInAnyVehicle(PlayerPedId(), false) then
        return GetVehiclePedIsIn(PlayerPedId(), false)
    end
    return 0
end

-- Read by FunctionsController to know a driving task is running.
Common.drive_to_wp_task_active = false
Common.drive_wander_task_active = false

function Common.drive_to_wp(style)
    style = style or 0
    ClearPedTasks(PlayerPedId())
    Common.drive_wander_task_active = false
    Common.drive_to_wp_task_active = true

    local waypoint = GetBlipInfoIdCoord(GetFirstBlipInfoId(8))
    local vehicle = Common.get_vehicle()
    local model = GetEntityModel(vehicle)

    SetDriverAbility(PlayerPedId(), 1.0)
    SetDriverAggressiveness(PlayerPedId(), 0.0)

    TaskVehicleDriveToCoordLongrange(
        PlayerPedId(),
        vehicle,
        waypoint.x,
        waypoint.y,
        waypoint.z,
        GetVehicleModelMaxSpeed(model),
        style,
        10.0
    )
end

function Common.drive_wander(style)
    style = style or 0
    ClearPedTasks(PlayerPedId())
    Common.drive_wander_task_active = true
    Common.drive_to_wp_task_active = false

    local vehicle = Common.get_vehicle()
    local model = GetEntityModel(vehicle)

    SetDriverAbility(PlayerPedId(), 1.0)
    SetDriverAggressiveness(PlayerPedId(), 0.0)

    TaskVehicleDriveWander(PlayerPedId(), vehicle, GetVehicleModelMaxSpeed(model), style)
end

-- ---------------------------------------------------------------------------
-- Vehicle spawning (the heart of the vehicle spawner + saved vehicles)
-- ---------------------------------------------------------------------------

-- GetVehDisplayNameFromModel.
function Common.get_veh_display_name_from_model(name)
    return GetLabelText(GetDisplayNameFromVehicleModel(GetHashKey(name)))
end

-- Map(value, min_in, max_in, min_out, max_out).
function Common.map(value, min_in, max_in, min_out, max_out)
    return (value - min_in) / (max_in - min_in) * (max_out - min_out) + min_out
end

-- LoadModel: false when the model isn't in the cd image.
function Common.load_model(model_hash)
    if not IsModelInCdimage(model_hash) then
        return false
    end
    RequestModel(model_hash)
    while not HasModelLoaded(model_hash) do
        Wait(0)
    end
    return true
end

local previous_vehicle = nil -- CommonFunctions._previousVehicle
local last_spawn_time = 0
local spawn_delay_ms = nil

local function vehicle_spawn_delay()
    if spawn_delay_ms == nil then
        spawn_delay_ms = Config.get_int('vmenu_vehicle_spawn_delay', 5) * 1000
    end
    return spawn_delay_ms
end

-- SpawnVehicle (main overload). opts: spawn_inside, replace_previous,
-- skip_load, vehicle_info, save_name, x, y, z, heading. Returns the vehicle
-- handle, or 0 on failure. Mod re-application for saved vehicles
-- (vehicle_info/save_name) hooks in from the SavedVehicles menu.
function Common.spawn_vehicle(vehicle_hash, opts)
    opts = opts or {}
    local ped = PlayerPedId()

    -- Carry momentum over from the current vehicle.
    local speed = 0.0
    local rpm = 0.0
    if IsPedInAnyVehicle(ped, false) then
        local old_vehicle = Common.get_vehicle()
        speed = GetEntitySpeedVector(old_vehicle, true).y -- forward/backward speed only
        rpm = GetVehicleCurrentRpm(old_vehicle)
    end

    local model_class = GetVehicleClassFromName(vehicle_hash)
    if State.allowed_vehicle_categories[model_class + 1] == false then
        Notification.Notify.alert(
            'You are not allowed to spawn this vehicle, because it belongs to a category which is '
                .. 'restricted by the server owner.'
        )
        return 0
    end

    for model_name, hash in pairs(State.whitelist_vehicles) do
        if hash == vehicle_hash then
            local Permissions = require('shared.permissions')
            if not Permissions.is_supplementary_allowed('VW' .. model_name:lower()) then
                Notification.Notify.alert(
                    'You are not allowed to spawn this vehicle, because it is restricted by the server owner.'
                )
                return 0
            end
        end
    end

    local game_time = GetGameTimer()
    do
        local Permissions = require('shared.permissions')
        if not Permissions.is_allowed('VSBypassRateLimit') then
            if last_spawn_time + vehicle_spawn_delay() > game_time then
                Notification.Notify.error(
                    ('You are spawning vehicles too quickly. Please wait %d second(s) before trying again.'):format(
                        math.ceil((last_spawn_time + vehicle_spawn_delay() - game_time) / 1000)
                    )
                )
                return 0
            end
        end
    end
    last_spawn_time = game_time

    if not opts.skip_load then
        if not Common.load_model(vehicle_hash) or not IsModelAVehicle(vehicle_hash) then
            Notification.Notify.error(Notification.error_message('InvalidModel'))
            return 0
        end
    end

    -- Spawn position & heading.
    local x, y, z = opts.x or 0.0, opts.y or 0.0, opts.z or 0.0
    local pos
    if x == 0.0 and y == 0.0 and z == 0.0 then
        if opts.spawn_inside then
            pos = GetEntityCoords(ped, true)
        else
            pos = GetOffsetFromEntityInWorldCoords(ped, 0.0, 8.0, 0.0)
        end
        pos = vector3(pos.x, pos.y, pos.z + 1.0)
    else
        pos = vector3(x, y, z)
    end
    local heading = opts.heading or -1.0
    if heading == -1.0 then
        heading = GetEntityHeading(ped) + (opts.spawn_inside and 0.0 or 90.0)
    end

    local Permissions = require('shared.permissions')

    -- Handle the previously spawned vehicle.
    if previous_vehicle ~= nil then
        local occupants_empty = GetVehicleNumberOfPassengers(previous_vehicle) == 0
            and IsVehicleSeatFree(previous_vehicle, -1)
        local we_drive = GetPedInVehicleSeat(previous_vehicle, -1) == ped
        if DoesEntityExist(previous_vehicle) and (occupants_empty or we_drive) then
            if opts.replace_previous or not Permissions.is_allowed('VSDisableReplacePrevious') then
                SetVehicleHasBeenOwnedByPlayer(previous_vehicle, false)
                SetEntityAsMissionEntity(previous_vehicle, true, true)
                DeleteVehicle(previous_vehicle)
            elseif not Config.get_bool('vmenu_keep_spawned_vehicles_persistent') then
                SetEntityAsMissionEntity(previous_vehicle, false, false)
            end
            previous_vehicle = nil
        end
    end

    -- Delete the vehicle the player is sitting in (it would glitch into the
    -- new one).
    if
        IsPedInAnyVehicle(ped, false)
        and (opts.replace_previous or not Permissions.is_allowed('VSDisableReplacePrevious'))
    then
        local tmp_vehicle = Common.get_vehicle()
        if GetPedInVehicleSeat(tmp_vehicle, -1) == ped then
            SetVehicleHasBeenOwnedByPlayer(tmp_vehicle, false)
            SetEntityAsMissionEntity(tmp_vehicle, true, true)
            if previous_vehicle ~= nil and previous_vehicle == tmp_vehicle then
                previous_vehicle = nil
            end
            DeleteVehicle(tmp_vehicle)
            Notification.Notify.info(
                'Your old car was removed to prevent your new car from glitching inside it. Next time, get out '
                    .. 'of your vehicle before spawning a new one if you want to keep your old one.'
            )
        end
    end

    if previous_vehicle ~= nil then
        SetVehicleHasBeenOwnedByPlayer(previous_vehicle, false)
    end

    if IsPedInAnyVehicle(ped, false) and x == 0.0 and y == 0.0 and z == 0.0 then
        local offset = GetOffsetFromEntityInWorldCoords(ped, 0.0, 8.0, 0.1)
        pos = vector3(offset.x, offset.y, offset.z + 1.0)
    end

    -- Create the new vehicle, no hotwiring needed.
    local vehicle = CreateVehicle(vehicle_hash, pos.x, pos.y, pos.z, heading, true, false)
    SetVehicleNeedsToBeHotwired(vehicle, false)
    SetVehicleHasBeenOwnedByPlayer(vehicle, true)
    SetEntityAsMissionEntity(vehicle, true, false)
    SetVehicleIsStolen(vehicle, false)
    SetVehicleIsWanted(vehicle, false)

    Util.debug_log(
        ('New vehicle, hash:%s, handle:%s, created at x:%.2f y:%.2f z:%.2f heading:%.2f'):format(
            tostring(vehicle_hash),
            tostring(vehicle),
            pos.x,
            pos.y,
            pos.z + 1.0,
            heading
        )
    )

    if opts.spawn_inside then
        SetVehicleEngineOn(vehicle, true, true, true)
        SetPedIntoVehicle(ped, vehicle, -1)

        -- Helicopters mid-air get full blade speed; everything else lands.
        if GetVehicleClass(vehicle) == 15 and GetEntityHeightAboveGround(ped) > 10.0 then
            SetHeliBladesFullSpeed(vehicle)
        else
            SetVehicleOnGroundProperly(vehicle)
        end

        if not IsThisModelATrain(GetEntityModel(vehicle)) then
            SetVehicleForwardSpeed(vehicle, speed)
        end
        SetVehicleCurrentRpm(vehicle, rpm)
    end

    -- Saved-vehicle mod application (SavedVehicles port).
    if opts.save_name ~= nil and opts.apply_mods ~= nil then
        opts.apply_mods(vehicle, opts.vehicle_info)
    end

    previous_vehicle = vehicle

    local UserDefaults = require('client.user_defaults')
    local default_radio = UserDefaults.get_int('vehicleDefaultRadio')
    Wait(1) -- mandatory delay: the radio check always fails without it
    if default_radio >= 0 and DoesPlayerVehHaveRadio() then
        while IsRadioRetuning() do
            Wait(10)
        end
        SetVehRadioStation(vehicle, GetRadioStationName(default_radio))
    end

    SetModelAsNoLongerNeeded(vehicle_hash)
    return vehicle
end

-- SpawnVehicle (string overload): "custom" asks the player for a model name.
function Common.spawn_vehicle_by_name(vehicle_name, spawn_inside, replace_previous)
    if vehicle_name == 'custom' then
        local result = Common.get_user_input('Enter Vehicle Name')
        if result ~= nil and result ~= '' then
            return Common.spawn_vehicle(GetHashKey(result), {
                spawn_inside = spawn_inside,
                replace_previous = replace_previous,
            })
        end
        Notification.Notify.error(Notification.error_message('InvalidInput'))
        return 0
    end
    return Common.spawn_vehicle(GetHashKey(vehicle_name), {
        spawn_inside = spawn_inside,
        replace_previous = replace_previous,
    })
end

-- Test hook: the tracked previously-spawned vehicle handle.
function Common.get_previous_vehicle()
    return previous_vehicle
end

-- ---------------------------------------------------------------------------
-- Scenarios
-- ---------------------------------------------------------------------------

local current_scenario = ''

-- PlayScenario: starts (or, when re-selected, stops) a scenario. The magic
-- "forcestop" name force-clears tasks.
function Common.play_scenario(scenario_name)
    local ped = PlayerPedId()
    if current_scenario == '' or current_scenario ~= scenario_name then
        current_scenario = scenario_name
        ClearPedTasks(ped)

        local can_play = true
        if IsPedRunning(ped) then
            Notification.Notify.alert("You can't start a scenario when you are running.", true, false)
            can_play = false
        end
        if IsEntityDead(ped) then
            Notification.Notify.alert("You can't start a scenario when you are dead.", true, false)
            can_play = false
        end
        if IsPlayerInCutscene(ped) then
            Notification.Notify.alert("You can't start a scenario when you are in a cutscene.", true, false)
            can_play = false
        end
        if IsPedFalling(ped) then
            Notification.Notify.alert("You can't start a scenario when you are falling.", true, false)
            can_play = false
        end
        if IsPedRagdoll(ped) then
            Notification.Notify.alert(
                "You can't start a scenario when you are currently in a ragdoll state.",
                true,
                false
            )
            can_play = false
        end
        if not IsPedOnFoot(ped) then
            Notification.Notify.alert('You must be on foot to start a scenario.', true, false)
            can_play = false
        end
        if NetworkIsInSpectatorMode() then
            Notification.Notify.alert("You can't start a scenario when you are currently spectating.", true, false)
            can_play = false
        end
        if GetEntitySpeed(ped) > 5.0 then
            Notification.Notify.alert("You can't start a scenario when you are moving too fast.", true, false)
            can_play = false
        end

        if can_play then
            local PedScenarios = require('client.data.ped_scenarios')
            local position_based = false
            for _, name in ipairs(PedScenarios.position_based_scenarios) do
                if name == scenario_name then
                    position_based = true
                    break
                end
            end
            if position_based then
                -- 0.5m behind and below the player works for most scenarios.
                local pos = GetOffsetFromEntityInWorldCoords(ped, 0.0, -0.5, -0.5)
                local heading = GetEntityHeading(ped)
                TaskStartScenarioAtPosition(ped, scenario_name, pos.x, pos.y, pos.z, heading, -1, true, false)
            else
                TaskStartScenarioInPlace(ped, scenario_name, 0, true)
            end
        end
    else
        -- Re-selecting the running scenario stops it.
        current_scenario = ''
        ClearPedTasks(ped)
        ClearPedSecondaryTask(ped)
    end

    if scenario_name == 'forcestop' then
        current_scenario = ''
        ClearPedTasks(ped)
        ClearPedTasksImmediately(ped)
    end
end

-- ---------------------------------------------------------------------------
-- Teleporting
-- ---------------------------------------------------------------------------

-- TeleportToCoords: the "safe" teleport with the alternating ground-z search
-- loop and screen fading; safe_mode_disabled goes straight to the coords.
function Common.teleport_to_coords(pos, safe_mode_disabled)
    local ped = PlayerPedId()

    if safe_mode_disabled then
        RequestCollisionAtCoord(pos.x, pos.y, pos.z)
        local vehicle = Common.get_vehicle()
        if IsPedInAnyVehicle(ped, false) and GetPedInVehicleSeat(vehicle, -1) == ped then
            SetEntityCoords(vehicle, pos.x, pos.y, pos.z, false, false, false, true)
        else
            SetEntityCoords(ped, pos.x, pos.y, pos.z, false, false, false, true)
        end
        return
    end

    local vehicle = Common.get_vehicle()
    local function in_vehicle()
        return vehicle ~= 0 and DoesEntityExist(vehicle) and GetPedInVehicleSeat(vehicle, -1) == ped
    end

    local vehicle_restore_visibility = in_vehicle() and IsEntityVisible(vehicle)
    local ped_restore_visibility = IsEntityVisible(ped)

    -- Freeze + network-fade the entity out.
    if in_vehicle() then
        FreezeEntityPosition(vehicle, true)
        if IsEntityVisible(vehicle) then
            NetworkFadeOutEntity(vehicle, true, false)
        end
    else
        ClearPedTasksImmediately(ped)
        FreezeEntityPosition(ped, true)
        if IsEntityVisible(ped) then
            NetworkFadeOutEntity(ped, true, false)
        end
    end

    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do
        Wait(0)
    end

    -- Alternating top/bottom ground-z search (minimizes average tries for
    -- any location on the map).
    local ground_z
    local found = false
    for zz = 950.0, 0.0, -25.0 do
        local z = zz
        if zz % 2 ~= 0 then
            z = 950.0 - zz
        end

        RequestCollisionAtCoord(pos.x, pos.y, z)
        SetFocusPosAndVel(pos.x, pos.y, pos.z, 0.0, 0.0, 0.0)
        NewLoadSceneStart(pos.x, pos.y, pos.z, pos.x, pos.y, pos.z, 50.0, 0)
        local temp_timer = GetGameTimer()
        while not IsNewLoadSceneLoaded() and GetGameTimer() - temp_timer < 3000 do
            Wait(0)
        end
        ClearFocus()
        -- Without this, areas outside the scene stay unrendered ("city mud").
        NewLoadSceneStop()

        if in_vehicle() then
            SetEntityCoords(vehicle, pos.x, pos.y, z, false, false, false, true)
        else
            SetEntityCoords(ped, pos.x, pos.y, z, false, false, false, true)
        end

        temp_timer = GetGameTimer()
        while not HasCollisionLoadedAroundEntity(ped) do
            if GetGameTimer() - temp_timer > 1000 then
                Util.debug_log('Waiting for the collision is taking too long (more than 1s). Breaking from wait loop.')
                break
            end
            Wait(0)
        end

        local ok, z_result = GetGroundZFor_3dCoord(pos.x, pos.y, z, false)
        if ok then
            found = true
            ground_z = z_result
            Util.debug_log(('Ground coordinate found: %s'):format(tostring(ground_z)))
            if in_vehicle() then
                SetEntityCoords(vehicle, pos.x, pos.y, ground_z, false, false, false, true)
                -- Unfreeze so it settles on the ground properly, then
                -- re-freeze until the screen fades back in.
                FreezeEntityPosition(vehicle, false)
                SetVehicleOnGroundProperly(vehicle)
                FreezeEntityPosition(vehicle, true)
            else
                SetEntityCoords(ped, pos.x, pos.y, ground_z, false, false, false, true)
            end
            break
        end
        Wait(10)
    end

    -- Fail-safe: nearest vehicle node.
    if not found then
        local _, safe_pos = GetNthClosestVehicleNode(pos.x, pos.y, pos.z, 0, 0, 0, 0)
        safe_pos = safe_pos or pos
        Notification.Notify.alert('Could not find a safe ground coord. Placing you on the nearest road instead.')
        if in_vehicle() then
            SetEntityCoords(vehicle, safe_pos.x, safe_pos.y, safe_pos.z, false, false, false, true)
            FreezeEntityPosition(vehicle, false)
            SetVehicleOnGroundProperly(vehicle)
            FreezeEntityPosition(vehicle, true)
        else
            SetEntityCoords(ped, safe_pos.x, safe_pos.y, safe_pos.z, false, false, false, true)
        end
    end

    -- Unfreeze + fade back in.
    if in_vehicle() then
        if vehicle_restore_visibility then
            NetworkFadeInEntity(vehicle, true)
            if not ped_restore_visibility then
                SetEntityVisible(ped, false, false)
            end
        end
        FreezeEntityPosition(vehicle, false)
    else
        if ped_restore_visibility then
            NetworkFadeInEntity(ped, true)
        end
        FreezeEntityPosition(ped, false)
    end

    DoScreenFadeIn(500)
    SetGameplayCamRelativePitch(0.0, 1.0)
end

-- TeleportToWp.
function Common.teleport_to_wp()
    if IsWaypointActive() then
        local pos = GetBlipInfoIdCoord(GetFirstBlipInfoId(8))
        Common.teleport_to_coords(pos)
    else
        Notification.Notify.error('You need to set a waypoint first!')
    end
end

-- SavePlayerLocationToLocationsFile: name prompt → vMenu:SaveTeleportLocation.
function Common.save_player_location_to_locations_file()
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local location_name = Common.get_user_input('Enter location save name', nil, 30)
    if location_name == nil or location_name == '' then
        Notification.Notify.error(Notification.error_message('InvalidInput'))
        return
    end
    for _, location in ipairs(State.teleport_locations) do
        if location.name == location_name then
            Notification.Notify.error('This location name is already used, please use a different name.')
            return
        end
    end
    local Json = require('shared.json_compat')
    TriggerServerEvent(
        'vMenu:SaveTeleportLocation',
        Json.encode({
            name = location_name,
            coordinates = { x = pos.x, y = pos.y, z = pos.z },
            heading = heading,
        })
    )
    Notification.Notify.success('The location was successfully saved.')
end

-- ---------------------------------------------------------------------------
-- Suicide
-- ---------------------------------------------------------------------------

-- The pistols the suicide animation can use, in upstream's priority order.
local SUICIDE_PISTOLS = {
    'WEAPON_PISTOL_MK2',
    'WEAPON_COMBATPISTOL',
    'WEAPON_PISTOL',
    'WEAPON_SNSPISTOL_MK2',
    'WEAPON_SNSPISTOL',
    'WEAPON_PISTOL50',
    'WEAPON_HEAVYPISTOL',
    'WEAPON_VINTAGEPISTOL',
}

-- CommitSuicide: pill or pistol, depending on what the ped carries.
function Common.commit_suicide()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        SetEntityHealth(ped, 0)
        return
    end

    RequestAnimDict('mp_suicide')
    while not HasAnimDictLoaded('mp_suicide') do
        Wait(0)
    end

    local weapon_hash = nil
    for _, weapon in ipairs(SUICIDE_PISTOLS) do
        if HasPedGotWeapon(ped, GetHashKey(weapon), false) then
            weapon_hash = GetHashKey(weapon)
            break
        end
    end
    local take_pill = weapon_hash == nil

    if take_pill then
        SetCurrentPedWeapon(ped, GetHashKey('weapon_unarmed'), true)
    else
        SetCurrentPedWeapon(ped, weapon_hash, true)
        SetPedDropsWeaponsWhenDead(ped, true)
    end

    ClearPedTasks(ped)
    TaskPlayAnim(ped, 'MP_SUICIDE', take_pill and 'pill' or 'pistol', 8.0, -8.0, -1, 270540800, 0, false, false, false)

    local shot = false
    while true do
        local time = GetEntityAnimCurrentTime(ped, 'MP_SUICIDE', take_pill and 'pill' or 'pistol')
        if HasAnimEventFired(ped, GetHashKey('Fire')) and not shot then
            ClearEntityLastDamageEntity(ped)
            SetPedShootsAtCoord(ped, 0.0, 0.0, 0.0, false)
            shot = true
        end
        if time > (take_pill and 0.536 or 0.365) then
            ClearEntityLastDamageEntity(ped)
            SetEntityHealth(ped, 0)
            break
        end
        Wait(0)
    end
    RemoveAnimDict('mp_suicide')
end

-- ---------------------------------------------------------------------------
-- Player actions (Online Players menu backend)
-- ---------------------------------------------------------------------------

-- KillPlayer: the server does the killing (with the staff log).
function Common.kill_player(player)
    TriggerServerEvent('vMenu:KillPlayer', player.server_id)
end

-- SummonPlayer: seat count travels along so the server can warp the target
-- into our vehicle when there's room.
function Common.summon_player(player)
    local current_vehicle = Common.get_vehicle()
    local number_of_seats = 0
    if current_vehicle ~= 0 then
        number_of_seats = GetVehicleModelNumberOfSeats(GetEntityModel(current_vehicle))
    end
    TriggerServerEvent('vMenu:SummonPlayer', player.server_id, number_of_seats)
end

-- KickPlayer: optionally asks for a reason (appended to the default).
function Common.kick_player(player, ask_user_for_reason, provided_reason)
    if player == nil then
        Notification.Notify.error('The selected player is somehow invalid, action aborted.')
        return
    end
    local default_reason = 'You have been kicked.'
    provided_reason = provided_reason or default_reason
    if ask_user_for_reason and provided_reason == default_reason then
        local user_input = Common.get_user_input('Enter Kick Message', nil, 100)
        if user_input ~= nil and user_input ~= '' then
            default_reason = default_reason .. (' Reason: %s'):format(user_input)
        else
            Notification.Notify.error('An invalid kick reason was provided. Action cancelled.')
            return
        end
    end
    TriggerServerEvent('vMenu:KickPlayer', player.server_id, default_reason)
    Util.debug_log(('Attempting to kick player %s (server id: %d).'):format(tostring(player.name), player.server_id))
end

-- BanPlayer: reason prompt, then perm ban or duration prompt + temp ban.
function Common.ban_player(player, forever)
    local ban_reason = Common.get_user_input('Enter Ban Reason', 'Banned by staff.', 200)
    if ban_reason == nil or #ban_reason <= 1 then
        Notification.Notify.error(Notification.error_message('InvalidInput'))
        TriggerEvent('chatMessage', '[vMenu] The input is invalid or you cancelled the action, please try again.')
        return
    end
    if forever then
        TriggerServerEvent('vMenu:PermBanPlayer', player.server_id, ban_reason)
        return
    end
    local duration_input = Common.get_user_input('Ban Duration (in hours) - Max: 720 (1 month)', '1.5', 10)
    if duration_input == nil or duration_input == '' then
        Notification.Notify.error(Notification.error_message('InvalidInput'))
        TriggerEvent('chatMessage', '[vMenu] The input is invalid or you cancelled the action, please try again.')
        return
    end
    local ban_hours = tonumber(duration_input)
    if ban_hours == nil then
        Notification.Notify.error(Notification.error_message('InvalidInput'))
        TriggerEvent('chatMessage', '[vMenu] The input is invalid or you cancelled the action, please try again.')
        return
    end
    if ban_hours > 0.0 then
        TriggerServerEvent('vMenu:TempBanPlayer', player.server_id, ban_hours + 0.0, ban_reason)
    else
        Notification.Notify.error('You need to enter a ban duration, enter a value ~h~between~h~ 1 and 720!')
    end
end

-- TeleportToPlayer: teleports to a player (optionally into their vehicle);
-- OneSync-remote players get located via the coords RPC first.
function Common.teleport_to_player(player, in_vehicle)
    if not (player.is_active or player.handle == -1) then
        Notification.Notify.error(Notification.error_message('PlayerNotFound', 'So the teleport has been cancelled.'))
        return
    end

    local player_pos
    local was_active = true
    if player.is_active and player.ped ~= nil then
        if player.ped == PlayerPedId() then
            Notification.Notify.error('Sorry, you can ~r~~h~not~h~ ~s~teleport to yourself!')
            return
        end
        player_pos = GetEntityCoords(player.ped, true)
    else
        local request = State.request_player_coordinates
        player_pos = request ~= nil and request(player.server_id) or nil
        if player_pos == nil or (player_pos.x == 0.0 and player_pos.y == 0.0 and player_pos.z == 0.0) then
            Notification.Notify.error('Could not retrieve the coordinates of the specified player. Teleport cancelled.')
            return
        end
        was_active = false
    end

    Common.teleport_to_coords(player_pos)

    local player_id = player.handle >= 0 and player.handle or GetPlayerFromServerId(player.server_id)
    local player_ped = GetPlayerPed(player_id)

    if in_vehicle then
        -- Wait for the target's vehicle to stream in when they were remote.
        if not was_active then
            local start_wait = GetGameTimer()
            while not IsPedInAnyVehicle(player_ped, false) do
                Wait(0)
                if GetGameTimer() - start_wait > 1500 then
                    break
                end
            end
        end

        if IsPedInAnyVehicle(player_ped, false) then
            local vehicle = GetVehiclePedIsIn(player_ped, false)
            if vehicle ~= 0 then
                local total_seats = GetVehicleModelNumberOfSeats(GetEntityModel(vehicle))
                if DoesEntityExist(vehicle) and not IsEntityDead(vehicle) and IsAnyVehicleSeatEmpty(vehicle) then
                    TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, -2) -- VehicleSeat.Any
                    Notification.Notify.success(
                        ("Teleported into ~g~<C>%s</C>'s ~s~vehicle."):format(GetPlayerName(player_id))
                    )
                elseif total_seats == 1 then
                    Notification.Notify.error('This vehicle only has room for 1 player!')
                else
                    Notification.Notify.error('Not enough empty vehicle seats remaining!')
                end
            end
        end
    else
        Notification.Notify.success(('Teleported to ~y~<C>%s</C>~s~.'):format(GetPlayerName(player_id)))
    end
end

-- SpectatePlayer: toggles spectator mode; press again to stop. Remote
-- (OneSync) players get a temporary camera pointed at their coords so the
-- area streams in first.
local currently_spectating_player = -1

function Common.spectate_player(player, force_disable)
    if force_disable then
        NetworkSetInSpectatorMode(false, 0)
        return
    end

    local camera = nil
    if not player.is_active then
        local request = State.request_player_coordinates
        local player_pos = request ~= nil and request(player.server_id) or { x = 0.0, y = 0.0, z = 0.0 }

        DoScreenFadeOut(500)
        while IsScreenFadingOut() do
            Wait(0)
        end

        camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', false)
        SetCamCoord(camera, player_pos.x, player_pos.y - 5.0, player_pos.z)
        PointCamAtCoord(camera, player_pos.x, player_pos.y, player_pos.z)
        SetCamActive(camera, true)
        RenderScriptCams(true, false, 3000, true, false)

        local timeout = GetGameTimer() + 1000
        while (not player.is_active or player.ped == nil) and GetGameTimer() <= timeout do
            Wait(0)
        end

        if not player.is_active then
            DoScreenFadeIn(500)
        end
    end

    local ped = player.ped or GetPlayerPed(GetPlayerFromServerId(player.server_id))

    if player.is_local or player.server_id == GetPlayerServerId(PlayerId()) then
        if NetworkIsInSpectatorMode() then
            DoScreenFadeOut(500)
            while IsScreenFadingOut() do
                Wait(0)
            end
            NetworkSetInSpectatorMode(false, 0)
            DoScreenFadeIn(500)
            Notification.Notify.success('Stopped spectating.', false, true)
            currently_spectating_player = -1
        else
            Notification.Notify.error("You can't spectate yourself.", false, true)
        end
    elseif NetworkIsInSpectatorMode() then
        if currently_spectating_player ~= player.handle and ped ~= nil and ped ~= 0 then
            DoScreenFadeOut(500)
            while IsScreenFadingOut() do
                Wait(0)
            end
            NetworkSetInSpectatorMode(false, 0)
            NetworkSetInSpectatorMode(true, ped)
            DoScreenFadeIn(500)
            Notification.Notify.success(
                ('You are now spectating ~g~<C>%s</C>~s~.'):format(Common.get_safe_player_name(player.name)),
                false,
                true
            )
            currently_spectating_player = player.handle
        else
            DoScreenFadeOut(500)
            while IsScreenFadingOut() do
                Wait(0)
            end
            NetworkSetInSpectatorMode(false, 0)
            DoScreenFadeIn(500)
            Notification.Notify.success('Stopped spectating.', false, true)
            currently_spectating_player = -1
        end
    elseif ped ~= nil and ped ~= 0 then
        DoScreenFadeOut(500)
        while IsScreenFadingOut() do
            Wait(0)
        end
        NetworkSetInSpectatorMode(false, 0)
        NetworkSetInSpectatorMode(true, ped)
        DoScreenFadeIn(500)
        Notification.Notify.success(
            ('You are now spectating ~g~<C>%s</C>~s~.'):format(Common.get_safe_player_name(player.name)),
            false,
            true
        )
        currently_spectating_player = player.handle
    end

    if camera ~= nil then
        DestroyCam(camera, false)
        RenderScriptCams(false, false, 3000, true, false)
    end
end

-- GetSpacerMenuItem: a disabled item with the title padded toward the
-- center of the menu (80-char field), used as a section divider.
function Common.get_spacer_menu_item(title, description)
    local length = #title
    local total_size = 80 - length
    local padding = string.rep(' ', math.max(0, math.floor(total_size / 2) - math.floor(length / 2)))
    local Items = require('menu.items')
    local item = Items.MenuItem.new('~h~' .. padding .. title, description or '')
    item.Enabled = false
    return item
end

-- ---------------------------------------------------------------------------
-- User input (onscreen keyboard)
-- ---------------------------------------------------------------------------

-- GetUserInput(window_title?, default_text?, max_input_length?): blocks
-- (yielding) until the keyboard closes; nil when cancelled.
function Common.get_user_input(window_title, default_text, max_input_length)
    max_input_length = max_input_length or 30
    local title_entry = ('%s_WINDOW_TITLE'):format(GetCurrentResourceName():upper())
    AddTextEntry(title_entry, ('%s:\t(MAX %d Characters)'):format(window_title or 'Enter', max_input_length))

    DisplayOnscreenKeyboard(1, title_entry, '', default_text or '', '', '', '', max_input_length)
    Wait(0)
    while true do
        local keyboard_status = UpdateOnscreenKeyboard()
        if keyboard_status == 3 or keyboard_status == 2 then
            -- not displaying anymore / cancelled
            return nil
        elseif keyboard_status == 1 then
            return GetOnscreenKeyboardResult()
        end
        Wait(0)
    end
end

-- Client-side GetSafePlayerName: escapes GTA markup instead of stripping it
-- (different from the server-side ban sanitizer!).
function Common.get_safe_player_name(name)
    if name == nil or name == '' then
        return ''
    end
    return (name:gsub('%^', '\\^'):gsub('~', '\\~'):gsub('<', '«'):gsub('>', '»'))
end

-- PrivateMessage(source, message, sent): shows the PM as a notification with
-- the sender's headshot; falls back to plain text when the headshot takes
-- longer than 2 seconds. The "PM From:"/"PM To:" fallback labels are swapped
-- for sent messages upstream; quirk preserved.
function Common.private_message(source, message, sent)
    sent = sent == true
    PlayerLists.request_player_list()
    PlayerLists.wait_requested()

    local name = '**Invalid**'
    for _, player in ipairs(PlayerLists.players()) do
        if tostring(player.server_id) == tostring(source) then
            name = player.name
            break
        end
    end

    local misc = State.menus.misc_settings
    if misc == nil or misc.MiscDisablePrivateMessages then
        return
    end

    local source_handle = GetPlayerFromServerId(math.tointeger(tonumber(source)) or -1)
    if source_handle == -1 then
        return
    end

    local headshot = RegisterPedheadshot(GetPlayerPed(source_handle))
    local timer = GetGameTimer()
    local took_too_long = false
    while not IsPedheadshotReady(headshot) or not IsPedheadshotValid(headshot) do
        Wait(0)
        if GetGameTimer() - timer > 2000 then
            took_too_long = true
            break
        end
    end

    local safe_name = ('<C>%s</C>'):format(Common.get_safe_player_name(name))
    if not took_too_long then
        local txd = GetPedheadshotTxdString(headshot)
        local subtitle = sent and 'Message Sent' or 'Message Received'
        Notification.Notify.custom_image(txd, txd, message, safe_name, subtitle, true, 1)
    else
        if sent then
            Notification.Notify.custom(('PM From: %s. Message: %s'):format(safe_name, message))
        else
            Notification.Notify.custom(('PM To: %s. Message: %s'):format(safe_name, message))
        end
    end
    UnregisterPedheadshot(headshot)
end

-- Alignment enum (CitizenFX.Core.UI): Center = 0, Left = 1, Right = 2.
Common.ALIGN_CENTER = 0
Common.ALIGN_LEFT = 1
Common.ALIGN_RIGHT = 2

-- DrawTextOnScreen(text, x, y, size?, justification?, font?, disable_outline?).
function Common.draw_text_on_screen(text, x_position, y_position, size, justification, font, disable_text_outline)
    size = size or 0.48
    justification = justification or Common.ALIGN_LEFT
    font = font or 6
    local misc = State.menus.misc_settings
    if
        IsHudPreferenceSwitchedOn()
        and not IsHudHidden()
        and (misc == nil or not misc.HideHud)
        and not IsPlayerSwitchInProgress()
        and IsScreenFadedIn()
        and not IsPauseMenuActive()
        and not IsFrontendFading()
        and not IsPauseMenuRestarting()
    then
        SetTextFont(font)
        SetTextScale(1.0, size)
        if justification == Common.ALIGN_RIGHT then
            SetTextWrap(0.0, x_position)
        end
        SetTextJustification(justification)
        if not disable_text_outline then
            SetTextOutline()
        end
        BeginTextCommandDisplayText('STRING')
        AddTextComponentSubstringPlayerName(text)
        EndTextCommandDisplayText(x_position, y_position)
    end
end

-- Finger pointing camera helpers (used by the keybind tick).
function Common.get_pointing_pitch()
    local pitch = GetGameplayCamRelativePitch()
    if pitch < -70.0 then
        pitch = -70.0
    end
    if pitch > 42.0 then
        pitch = 42.0
    end
    return (pitch + 70.0) / 112.0
end

function Common.get_pointing_heading()
    local heading = GetGameplayCamRelativeHeading()
    if heading < -180.0 then
        heading = -180.0
    end
    if heading > 180.0 then
        heading = 180.0
    end
    heading = (heading + 180.0) / 360.0
    return (heading * -1.0) + 1.0
end

function Common.get_pointing_is_blocked()
    local raw_heading = GetGameplayCamRelativeHeading() / 90.0
    local heading = raw_heading
    if heading < -180.0 then
        heading = -180.0
    elseif heading > 180.0 then
        heading = 180.0
    end
    heading = (heading + 180.0) / 360.0
    local v1 = ((0.7 - 0.3) * heading) + 0.3
    local x, y, z = -0.2, v1, 0.6
    local rot_z = raw_heading

    -- rotate around z (x/y rotations are zero upstream)
    local f0 = math.cos(rot_z)
    local f1 = math.sin(rot_z)
    x, y = (f0 * x) - (f1 * y), (f1 * x) + (f0 * y)

    local ped = PlayerPedId()
    local pos = GetOffsetFromEntityInWorldCoords(ped, x, y, z)
    local handle = StartShapeTestCapsule(pos.x, pos.y, pos.z - 0.2, pos.x, pos.y, pos.z + 0.2, 0.4, 95, ped, 7)
    local _, hit = GetShapeTestResult(handle)
    return hit == true or hit == 1
end

-- ToProperString: "PascalCaseString" → "Pascal Case String".
function Common.to_proper_string(input_string)
    local output = ''
    local prev_upper = true
    for character in tostring(input_string or ''):gmatch('.') do
        if character:match('%a') and character ~= ' ' and character == character:upper() then
            if prev_upper then
                output = output .. character
            else
                output = output .. ' ' .. character
            end
            prev_upper = true
        else
            prev_upper = false
            output = output .. character
        end
    end
    while output:find('  ', 1, true) do
        output = output:gsub('  ', ' ')
    end
    return output
end

-- CycleThroughSeats: warp to the next free seat in the current vehicle.
function Common.cycle_through_seats()
    local vehicle = Common.get_vehicle()
    local ped = PlayerPedId()

    if AreAnyVehicleSeatsFree(vehicle) then
        local max_seats = GetVehicleModelNumberOfSeats(GetEntityModel(vehicle))

        -- In the "last" seat: wrap around and take the first free seat.
        if GetPedInVehicleSeat(vehicle, max_seats - 2) == ped then
            for seat = -1, max_seats - 3 do
                if IsVehicleSeatFree(vehicle, seat) then
                    TaskWarpPedIntoVehicle(ped, vehicle, seat)
                    break
                end
            end
        else
            -- Take the first free seat *after* the current one; if there is
            -- none, wrap around to the first free seat overall.
            local switched_place = false
            local passed_current_seat = false
            for seat = -1, max_seats - 2 do
                if not passed_current_seat and GetPedInVehicleSeat(vehicle, seat) == ped then
                    passed_current_seat = true
                end
                if passed_current_seat and IsVehicleSeatFree(vehicle, seat) then
                    switched_place = true
                    TaskWarpPedIntoVehicle(ped, vehicle, seat)
                    break
                end
            end
            if not switched_place then
                for seat = -1, max_seats - 2 do
                    if IsVehicleSeatFree(vehicle, seat) then
                        TaskWarpPedIntoVehicle(ped, vehicle, seat)
                        break
                    end
                end
            end
        end
    else
        Notification.Notify.alert('There are no more available seats to cycle through.')
    end
end

-- SetLicensePlateCustomText: asks the driver for a new plate text.
function Common.set_license_plate_custom_text()
    local vehicle = Common.get_vehicle()
    if vehicle ~= 0 and DoesEntityExist(vehicle) then
        if GetPedInVehicleSeat(vehicle, -1) == PlayerPedId() then
            local text = Common.get_user_input('Enter License Plate', GetVehicleNumberPlateText(vehicle) or '', 8)
            if text ~= nil and text ~= '' then
                SetVehicleNumberPlateText(vehicle, text)
            else
                Notification.Notify.error(Notification.error_message('InvalidInput'))
            end
        else
            Notification.Notify.error(Notification.error_message('NeedToBeTheDriver'))
        end
    else
        Notification.Notify.error(Notification.error_message('NoVehicle'))
    end
end

return Common
