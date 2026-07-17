-- Port of vMenu/FunctionsController.cs (part 2 of 3): HUD/world ticks —
-- misc settings text (coords/location/time/speed), radar & camera locks,
-- keybinds (waypoint tp, drift, pointing, recording, bigmap), death
-- notifications, voice chat, time/weather menu sync, player blips, overhead
-- names, online player waypoints, and the entity outlines tool.

local Config = require('shared.config')
local Permissions = require('shared.permissions')
local Common = require('client.common')
local Notification = require('client.notify')
local PlayerLists = require('client.player_lists')
local State = require('client.state')
local BlipInfo = require('client.data.blip_info')
local Controller = require('menu.controller')
local Items = require('menu.items')

local Notify = Notification.Notify
local HelpMessage = Notification.HelpMessage

local Hud = {}

-- Control ids.
local CONTROLS = {
    MultiplayerInfo = 20,
    Sprint = 21,
    Jump = 22,
    LookLeftOnly = 5,
    LookRightOnly = 6,
    SpecialAbilitySecondary = 29,
    VehicleCinCam = 80,
    SaveReplayClip = 170,
    ReplayStartStopRecording = 288,
    ReplayClipDelete = 297,
}

-- show location state
local safe_zone_size_x = (1 / GetSafeZoneSize() / 3.0) - 0.358
local zone_display = ''
local street_display = ''
local heading_display = ''

local dead_players = {}
local voice_timer = 0
local voice_cycle = 1
local VOICE_INDICATOR_WIDTH = 0.02
local VOICE_INDICATOR_HEIGHT = 0.041
local VOICE_INDICATOR_MUTED_WIDTH = VOICE_INDICATOR_WIDTH + 0.0021

local camera_rotation_heading = 0.0
local radar_switch_timer = 0
local last_pressed_point = 0

local stop_props_loop = false
local stop_vehicles_loop = false
local stop_peds_loop = false
local props = {}
local vehicles = {}
local peds = {}

local waypoint_player_ids_to_remove = {}

local function misc_menu()
    return State.menus.misc_settings
end

local function keyboard_input()
    return IsInputDisabled(2)
end

-- ---------------------------------------------------------------------------
-- Misc settings text drawing
-- ---------------------------------------------------------------------------

local function round2(value)
    return math.floor(value * 100 + 0.5) / 100
end

local function show_location()
    Common.draw_text_on_screen(
        street_display,
        0.234 + safe_zone_size_x,
        GetSafeZoneSize() - GetTextScaleHeight(0.48, 6) - GetTextScaleHeight(0.48, 6),
        0.48
    )
    Common.draw_text_on_screen(
        zone_display,
        0.234 + safe_zone_size_x,
        GetSafeZoneSize() - GetTextScaleHeight(0.45, 6) - GetTextScaleHeight(0.95, 6),
        0.45
    )
    Common.draw_text_on_screen(
        '~t~|',
        0.188 + safe_zone_size_x,
        GetSafeZoneSize() - GetTextScaleHeight(1.2, 6) - GetTextScaleHeight(0.4, 6),
        1.2,
        Common.ALIGN_LEFT
    )
    Common.draw_text_on_screen(
        heading_display,
        0.208 + safe_zone_size_x,
        GetSafeZoneSize() - GetTextScaleHeight(1.2, 6) - GetTextScaleHeight(0.4, 6),
        1.2,
        Common.ALIGN_CENTER
    )
    Common.draw_text_on_screen(
        '~t~|',
        0.228 + safe_zone_size_x,
        GetSafeZoneSize() - GetTextScaleHeight(1.2, 6) - GetTextScaleHeight(0.4, 6),
        1.2,
        Common.ALIGN_RIGHT
    )
end

local function show_speed_kmh()
    local speed = math.floor(GetEntitySpeed(Common.get_vehicle()) * 3.6 + 0.5)
    Common.draw_text_on_screen(('%d KM/h'):format(speed), 0.995, 0.955, 0.7, Common.ALIGN_RIGHT, 4)
end

local function show_speed_mph(misc)
    local speed = math.floor(GetEntitySpeed(Common.get_vehicle()) * 2.23694 + 0.5)
    if misc.ShowSpeedoKmh then
        Common.draw_text_on_screen(('%d MPH'):format(speed), 0.995, 0.925, 0.7, Common.ALIGN_RIGHT, 4)
        HideHudComponentThisFrame(7) -- HudComponent.StreetName
    else
        Common.draw_text_on_screen(('%d MPH'):format(speed), 0.995, 0.955, 0.7, Common.ALIGN_RIGHT, 4)
    end
end

local function draw_misc_settings_text(misc)
    if misc.ShowCoordinates and Permissions.is_allowed('MSShowCoordinates') then
        local pos = GetEntityCoords(PlayerPedId())
        local heading = round2(GetEntityHeading(PlayerPedId()))
        SetScriptGfxAlign(0, 84)
        SetScriptGfxAlignParams(0.0, 0.0, 0.0, 0.0)
        local width = GetActiveScreenResolution()
        Common.draw_text_on_screen(
            ('~r~X~s~ \t\t%s\n~r~Y~s~ \t\t%s\n~r~Z~s~ \t\t%s\n~r~Heading~s~ \t%s'):format(
                round2(pos.x),
                round2(pos.y),
                round2(pos.z),
                heading
            ),
            0.5 - (30 / width),
            0.0,
            0.5,
            Common.ALIGN_LEFT,
            6,
            false
        )
        ResetScriptGfxAlign()
    end

    if misc.ShowLocation and Permissions.is_allowed('MSShowLocation') then
        SetScriptGfxAlign(0, 84)
        SetScriptGfxAlignParams(0.0, 0.0, 0.0, 0.0)
        show_location()
        ResetScriptGfxAlign()
    end

    if misc.DrawTimeOnScreen then
        local timestring = ('%02d:%02d'):format(GetClockHours(), GetClockMinutes())
        SetScriptGfxAlign(0, 84)
        SetScriptGfxAlignParams(0.0, 0.0, 0.0, 0.0)
        Common.draw_text_on_screen(
            '~c~' .. timestring,
            0.208 + safe_zone_size_x,
            GetSafeZoneSize() - GetTextScaleHeight(0.4, 1),
            0.40,
            Common.ALIGN_CENTER
        )
        ResetScriptGfxAlign()
    end

    if misc.ShowSpeedoKmh and IsPedInAnyVehicle(PlayerPedId(), false) then
        show_speed_kmh()
    end
    if misc.ShowSpeedoMph and IsPedInAnyVehicle(PlayerPedId(), false) then
        show_speed_mph(misc)
    end
end

-- ---------------------------------------------------------------------------
-- Misc settings tick (radar, camera locks, keybinds, pointing, bigmap)
-- ---------------------------------------------------------------------------

local function toggle_pointing()
    local ped = PlayerPedId()
    if IsPedPointing(ped) then
        ClearPedSecondaryTask(ped)
    else
        if not HasAnimDictLoaded('anim@mp_point') then
            RequestAnimDict('anim@mp_point')
        end
        while not HasAnimDictLoaded('anim@mp_point') do
            Wait(0)
        end
        TaskMoveNetworkByName(ped, 'task_mp_pointing', 0.5, false, 'anim@mp_point', 24)
        RemoveAnimDict('anim@mp_point')
    end
end

function Hud.misc_settings_tick()
    local misc = misc_menu()
    if misc == nil then
        Wait(100)
        return
    end

    draw_misc_settings_text(misc)

    -- radar
    if misc.HideRadar then
        DisplayRadar(false)
    elseif not IsRadarHidden() then
        DisplayRadar(IsRadarPreferenceSwitchedOn())
    end

    -- camera angle locking
    if misc.LockCameraY then
        SetGameplayCamRelativePitch(0.0, 0.0)
    end
    if misc.LockCameraX then
        if IsControlPressed(0, CONTROLS.LookLeftOnly) then
            camera_rotation_heading = camera_rotation_heading + 1
        elseif IsControlPressed(0, CONTROLS.LookRightOnly) then
            camera_rotation_heading = camera_rotation_heading - 1
        end
        SetGameplayCamRelativeHeading(camera_rotation_heading)
    end

    -- teleport to waypoint keybind
    if misc.KbTpToWaypoint and Permissions.is_allowed('MSTeleportToWp') then
        if
            IsControlJustReleased(0, misc.KbTpToWaypointKey or 168)
            and IsScreenFadedIn()
            and not IsPlayerSwitchInProgress()
            and keyboard_input()
        then
            if IsWaypointActive() then
                Common.teleport_to_wp()
                Notify.success('Teleported to waypoint.')
            else
                Notify.error('You need to set a waypoint first.')
            end
        end
    end

    -- drift mode keybind
    if misc.KbDriftMode and Permissions.is_allowed('MSDriftMode') then
        if IsPedInAnyVehicle(PlayerPedId(), false) then
            local veh = Common.get_vehicle()
            if veh ~= 0 and DoesEntityExist(veh) and not IsEntityDead(veh) then
                if
                    (IsControlPressed(0, CONTROLS.Sprint) and keyboard_input())
                    or (IsControlPressed(0, CONTROLS.Jump) and not keyboard_input())
                then
                    SetVehicleReduceGrip(veh, true)
                elseif
                    (IsControlJustReleased(0, CONTROLS.Sprint) and keyboard_input())
                    or (IsControlJustReleased(0, CONTROLS.Jump) and not keyboard_input())
                then
                    SetVehicleReduceGrip(veh, false)
                end
            end
        end
    end

    -- finger pointing keybind
    if misc.KbPointKeys then
        local ped = PlayerPedId()
        if not keyboard_input() then
            -- double press the right analog stick for controllers
            if IsControlJustReleased(0, CONTROLS.SpecialAbilitySecondary) and not IsPedInAnyVehicle(ped, false) then
                if GetGameTimer() - last_pressed_point < 300 then
                    last_pressed_point = GetGameTimer()
                    toggle_pointing()
                else
                    last_pressed_point = GetGameTimer()
                end
            end
        else
            if
                IsControlJustReleased(0, CONTROLS.SpecialAbilitySecondary)
                and UpdateOnscreenKeyboard() ~= 0
                and not IsPedInAnyVehicle(ped, false)
            then
                toggle_pointing()
            end
        end

        if IsPedPointing(ped) then
            if IsPedInAnyVehicle(ped, false) then
                ClearPedSecondaryTask(ped)
            else
                SetTaskMoveNetworkSignalFloat(ped, 'Pitch', Common.get_pointing_pitch())
                SetTaskMoveNetworkSignalFloat(ped, 'Heading', Common.get_pointing_heading())
                SetTaskMoveNetworkSignalBool(ped, 'isBlocked', Common.get_pointing_is_blocked())
                SetTaskMoveNetworkSignalBool(ped, 'isFirstPerson', GetFollowPedCamViewMode() == 4)
                SetTaskMoveNetworkSignalFloat(ped, 'Speed', 0.25)
            end
        end
    end

    -- expanded radar / bigmap
    if GetProfileSetting(221) == 1 then -- settings > display > expanded radar
        SetBigmapActive(true, false)
    else
        if IsBigmapActive() and GetGameTimer() - radar_switch_timer > 8000 then
            SetBigmapActive(false, false)
        end
        if
            IsControlJustReleased(0, CONTROLS.MultiplayerInfo)
            and IsControlEnabled(0, CONTROLS.MultiplayerInfo)
            and misc.KbRadarKeys
            and not Controller.IsAnyMenuOpen()
            and not IsPauseMenuActive()
        then
            if IsBigmapActive() then
                SetBigmapActive(false, false)
            else
                SetBigmapActive(true, false)
                radar_switch_timer = GetGameTimer()
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Recording keybinds
-- ---------------------------------------------------------------------------

function Hud.misc_recording_keybinds()
    local misc = misc_menu()
    if misc == nil or not misc.KbRecordKeys then
        return
    end
    if IsPauseMenuActive() or not IsScreenFadedIn() or IsPlayerSwitchInProgress() or Controller.IsAnyMenuOpen() then
        return
    end

    if keyboard_input() then
        local record_key = CONTROLS.ReplayStartStopRecording
        if not IsRecording() then
            if IsControlJustReleased(0, record_key) then
                StartRecording(1)
                HelpMessage.custom(
                    'Press ~INPUT_REPLAY_START_STOP_RECORDING~ to save the recording, press '
                        .. '~INPUT_REPLAY_CLIP_DELETE~ to discard the recording.'
                )
            end
        else
            if IsControlJustReleased(0, record_key) then
                StopRecordingAndSaveClip()
            end
            if IsControlJustPressed(0, CONTROLS.ReplayClipDelete) then
                StopRecordingAndDiscardClip()
            end
        end
    else
        -- gamepad: hold MultiplayerInfo, then use the record/save buttons
        if IsControlPressed(0, CONTROLS.MultiplayerInfo) then
            local timer = GetGameTimer()
            local long_enough = false
            local notif_one = -1
            local notif_two = -1
            while IsControlPressed(0, CONTROLS.MultiplayerInfo) do
                if GetGameTimer() - timer > 400 and not long_enough then
                    long_enough = true
                    if IsRecording() then
                        SetNotificationTextEntry('STRING')
                        notif_one = DrawNotificationWithButton(
                            1,
                            '~INPUT_REPLAY_START_STOP_RECORDING~',
                            'Stop recording and save clip.'
                        )
                        SetNotificationTextEntry('STRING')
                        notif_two =
                            DrawNotificationWithButton(1, '~INPUT_SAVE_REPLAY_CLIP~', 'Stop recording and delete clip.')
                    else
                        SetNotificationTextEntry('STRING')
                        notif_one =
                            DrawNotificationWithButton(1, '~INPUT_REPLAY_START_STOP_RECORDING~', 'Start recording.')
                    end
                end

                if long_enough then
                    DisableControlAction(0, CONTROLS.VehicleCinCam, true)
                    if IsRecording() then
                        if IsControlJustReleased(0, CONTROLS.SaveReplayClip) then
                            StopRecordingAndDiscardClip()
                            break
                        end
                        if IsControlJustReleased(0, CONTROLS.ReplayStartStopRecording) then
                            StopRecordingAndSaveClip()
                            break
                        end
                    else
                        if IsControlJustReleased(0, CONTROLS.ReplayStartStopRecording) then
                            StartRecording(1)
                            HelpMessage.custom(
                                'Hold down ~INPUT_MULTIPLAYER_INFO~ and press ~INPUT_REPLAY_START_STOP_RECORDING~ '
                                    .. 'to save the recording, press ~INPUT_SAVE_REPLAY_CLIP~ to discard the recording.'
                            )
                            break
                        end
                    end
                end
                Wait(0)
            end

            if notif_one ~= -1 then
                RemoveNotification(notif_one)
            end
            if notif_two ~= -1 then
                RemoveNotification(notif_two)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Location display updater
-- ---------------------------------------------------------------------------

function Hud.update_location()
    local misc = misc_menu()
    if misc ~= nil and misc.ShowLocation then
        local ped = PlayerPedId()
        local current_pos = GetEntityCoords(ped, true)
        local heading = GetEntityHeading(ped)
        zone_display = GetLabelText(GetNameOfZone(current_pos.x, current_pos.y, current_pos.z))

        local _, node_pos = GetNthClosestVehicleNode(current_pos.x, current_pos.y, current_pos.z, 0, 0, 0, 0)
        node_pos = node_pos or vector3(0.0, 0.0, 0.0)

        safe_zone_size_x = (1 / GetSafeZoneSize() / 3.0) - 0.358

        local _, main_st, cross_st = GetStreetNameAtCoord(current_pos.x, current_pos.y, current_pos.z)
        main_st = main_st or 0
        cross_st = cross_st or 0
        local main_name = GetStreetNameFromHashKey(main_st)
        local cross_name = GetStreetNameFromHashKey(cross_st)

        local dx = current_pos.x - node_pos.x
        local dy = current_pos.y - node_pos.y
        local dz = current_pos.z - node_pos.z
        local prefix = (dx * dx + dy * dy + dz * dz) > 1400.0 and '~m~Near ~s~' or '~s~'
        local suffix = cross_st ~= 0 and ('~t~ / ' .. cross_name) or ''
        street_display = prefix .. main_name .. suffix

        if heading > 320 or heading < 45 then
            heading_display = 'N'
        elseif heading >= 45 and heading <= 135 then
            heading_display = 'W'
        elseif heading > 135 and heading < 225 then
            heading_display = 'S'
        else
            heading_display = 'E'
        end

        Wait(200)
    else
        Wait(1000)
    end
end

-- ---------------------------------------------------------------------------
-- Death notifications
-- ---------------------------------------------------------------------------

function Hud.death_notifications()
    local misc = misc_menu()
    if misc == nil or not misc.DeathNotifications then
        return
    end
    local players = PlayerLists.players()
    for _, p in ipairs(players) do
        local ped = p.ped
        if ped ~= nil and ped ~= 0 and IsEntityDead(ped) then
            if dead_players[p.handle] then
                return -- upstream returns (not continues) here; quirk preserved
            end
            local killer = GetPedSourceOfDeath(ped)
            local name = Common.get_safe_player_name(p.name)
            if killer ~= nil and killer ~= 0 then
                if killer ~= ped then
                    if DoesEntityExist(killer) then
                        local found = nil
                        if IsEntityAVehicle(killer) then
                            for _, potential in ipairs(players) do
                                if
                                    potential.ped ~= 0
                                    and IsPedInAnyVehicle(potential.ped, false)
                                    and GetVehiclePedIsIn(potential.ped, false) == killer
                                then
                                    found = potential
                                    break
                                end
                            end
                        else
                            for _, potential in ipairs(players) do
                                if potential.ped == killer then
                                    found = potential
                                    break
                                end
                            end
                        end
                        if found ~= nil then
                            Notify.custom(
                                ('~o~<C>%s</C> ~s~has been murdered by ~y~<C>%s</C>~s~.'):format(
                                    name,
                                    Common.get_safe_player_name(found.name)
                                )
                            )
                        else
                            Notify.custom(('~o~<C>%s</C> ~s~has been murdered.'):format(name))
                        end
                    else
                        Notify.custom(('~o~<C>%s</C> ~s~has been murdered.'):format(name))
                    end
                else
                    Notify.custom(('~o~<C>%s</C> ~s~committed suicide.'):format(name))
                end
            else
                Notify.custom(('~o~<C>%s</C> ~s~died.'):format(name))
            end
            dead_players[p.handle] = true
        else
            dead_players[p.handle] = nil
        end
    end
end

-- ---------------------------------------------------------------------------
-- Voice chat
-- ---------------------------------------------------------------------------

function Hud.voice_chat_tick()
    local vc = State.menus.voice_chat
    if vc == nil then
        Wait(100)
        return
    end
    if vc.EnableVoicechat and Permissions.is_allowed('VCEnable') then
        NetworkSetVoiceActive(true)
        NetworkSetTalkerProximity(vc.currentProximity)
        local channel = 0
        for i, name in ipairs(vc.channels) do
            if name == vc.currentChannel then
                channel = i - 1
                break
            end
        end
        if channel < 1 then
            NetworkClearVoiceChannel()
        else
            NetworkSetVoiceChannel(channel)
        end

        if vc.ShowCurrentSpeaker and Permissions.is_allowed('VCShowSpeaker') then
            local i = 1
            local currently_talking = false
            for _, p in ipairs(PlayerLists.players()) do
                if NetworkIsPlayerTalking(p.handle) then
                    if not currently_talking then
                        Common.draw_text_on_screen('~s~Currently Talking', 0.5, 0.00, 0.5, Common.ALIGN_CENTER, 6)
                        currently_talking = true
                    end
                    Common.draw_text_on_screen('~b~' .. p.name, 0.5, 0.00 + (i * 0.03), 0.5, Common.ALIGN_CENTER, 6)
                    i = i + 1
                end
            end
        end

        if vc.ShowVoiceStatus then
            if GetGameTimer() - voice_timer > 150 then
                voice_timer = GetGameTimer()
                voice_cycle = voice_cycle + 1
                if voice_cycle > 3 then
                    voice_cycle = 1
                end
            end
            if not HasStreamedTextureDictLoaded('mpleaderboard') then
                RequestStreamedTextureDict('mpleaderboard', false)
                while not HasStreamedTextureDictLoaded('mpleaderboard') do
                    Wait(0)
                end
            end
            if NetworkIsPlayerTalking(PlayerId()) then
                DrawSprite(
                    'mpleaderboard',
                    ('leaderboard_audio_%d'):format(voice_cycle),
                    0.008,
                    0.985,
                    VOICE_INDICATOR_WIDTH,
                    VOICE_INDICATOR_HEIGHT,
                    0.0,
                    255,
                    55,
                    0,
                    255
                )
            else
                DrawSprite(
                    'mpleaderboard',
                    'leaderboard_audio_mute',
                    0.008,
                    0.985,
                    VOICE_INDICATOR_MUTED_WIDTH,
                    VOICE_INDICATOR_HEIGHT,
                    0.0,
                    255,
                    55,
                    0,
                    255
                )
            end
        else
            if HasStreamedTextureDictLoaded('mpleaderboard') then
                SetStreamedTextureDictAsNoLongerNeeded('mpleaderboard')
            end
        end
    else
        NetworkSetVoiceActive(false)
        NetworkClearVoiceChannel()
    end
end

-- ---------------------------------------------------------------------------
-- Time / weather menu sync
-- ---------------------------------------------------------------------------

function Hud.time_options_tick()
    local to = State.menus.time_options
    if to ~= nil and to.freeze_time_toggle ~= nil and to.menu.Visible and Permissions.is_allowed('TOFreezeTime') then
        to.freeze_time_toggle.Label = ('(Current Time %02d:%02d)'):format(GetClockHours(), GetClockMinutes())
    end
    Wait(2000)
end

function Hud.weather_options_tick()
    Wait(100)
    local wo = State.menus.weather_options
    if wo == nil then
        return
    end
    local weather_menu = wo.menu
    if weather_menu ~= nil and weather_menu.Visible then
        if Permissions.is_allowed('WODynamic') and wo.dynamic_weather_enabled ~= nil then
            wo.dynamic_weather_enabled.Checked = Config.get_bool('vmenu_dynamic_weather')
        end
        if Permissions.is_allowed('WOBlackout') and wo.blackout ~= nil then
            wo.blackout.Checked = Config.get_bool('vmenu_blackout_enabled')
        end
        if Permissions.is_allowed('WOSetWeather') then
            if wo.snow_enabled ~= nil then
                wo.snow_enabled.Checked = Config.get_bool('vmenu_enable_snow')
            end
            local server_weather = Config.get_string('vmenu_current_weather', 'CLEAR') or 'CLEAR'
            for _, item in ipairs(weather_menu:GetMenuItems()) do
                if type(item.ItemData) == 'string' then
                    if item.ItemData == server_weather then
                        item.RightIcon = Items.Icon.TICK
                    else
                        item.RightIcon = Items.Icon.NONE
                    end
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Player blips + overhead names
-- ---------------------------------------------------------------------------

local BLIP_DECOR = 'vmenu_player_blip_sprite_id'

function Hud.player_blips_control()
    if DecorIsRegisteredAsType(BLIP_DECOR, 3) then
        local ped = PlayerPedId()
        local sprite = 1
        if IsPedInAnyVehicle(ped, false) then
            local veh = Common.get_vehicle()
            if veh ~= 0 and DoesEntityExist(veh) then
                sprite = BlipInfo.get_blip_sprite_for_vehicle(veh)
            end
        end
        DecorSetInt(ped, BLIP_DECOR, sprite)

        local misc = misc_menu()
        if misc ~= nil then
            local enabled = misc.ShowPlayerBlips
            local my_pos = GetEntityCoords(ped)
            for _, p in ipairs(PlayerLists.players()) do
                if p ~= nil and NetworkIsPlayerActive(p.handle) and p.ped ~= 0 and DoesEntityExist(p.ped) then
                    if enabled then
                        if not p.is_local then
                            local other = p.ped
                            local blip = GetBlipFromEntity(other)
                            if blip < 1 then
                                blip = AddBlipForEntity(other)
                            end
                            local other_pos = GetEntityCoords(other)
                            local dx = other_pos.x - my_pos.x
                            local dy = other_pos.y - my_pos.y
                            if (dx * dx + dy * dy) < 500000 or IsPauseMenuActive() then
                                SetBlipColour(blip, 0)
                                if DecorExistOn(other, BLIP_DECOR) then
                                    local decor_sprite = DecorGetInt(other, BLIP_DECOR)
                                    SetBlipSprite(blip, decor_sprite)
                                    ShowHeadingIndicatorOnBlip(blip, decor_sprite == 1)
                                    if decor_sprite ~= 422 then
                                        SetBlipRotation(blip, math.floor(GetEntityHeading(other)))
                                    end
                                else
                                    -- backup: derive the sprite locally
                                    if IsPedInAnyVehicle(other, false) then
                                        SetBlipSprite(
                                            blip,
                                            BlipInfo.get_blip_sprite_for_vehicle(GetVehiclePedIsIn(other, false))
                                        )
                                        ShowHeadingIndicatorOnBlip(blip, false)
                                        if not IsPedInAnyHeli(other) then
                                            SetBlipRotation(blip, math.floor(GetEntityHeading(other)))
                                        end
                                    else
                                        SetBlipSprite(blip, 1)
                                        ShowHeadingIndicatorOnBlip(blip, true)
                                    end
                                end
                                SetBlipNameToPlayerName(blip, p.handle)
                                -- groups blips under "Other Players:" (thanks Lambda Menu)
                                SetBlipCategory(blip, 7)
                                SetBlipDisplay(blip, 6)
                            else
                                SetBlipDisplay(blip, 3)
                            end
                        end
                    else
                        local blip = GetBlipFromEntity(p.ped)
                        local online_players = State.menus.online_players
                        local has_waypoint = false
                        if online_players ~= nil then
                            for _, server_id in ipairs(online_players.players_waypoint_list) do
                                if server_id == p.server_id then
                                    has_waypoint = true
                                    break
                                end
                            end
                        end
                        if DoesBlipExist(blip) and not has_waypoint then
                            RemoveBlip(blip)
                        end
                    end
                end
            end
        else
            Wait(1000)
        end
    else
        DecorRegister(BLIP_DECOR, 3)
        while not DecorIsRegisteredAsType(BLIP_DECOR, 3) do
            Wait(0)
        end
    end
end

local gamer_tags = {} -- [player handle] = tag id
local player_names_distance = nil

function Hud.player_overhead_names_control()
    Wait(500)

    if player_names_distance == nil then
        local configured = Config.get_float('vmenu_player_names_distance', 0.0)
        player_names_distance = configured > 10.0 and configured or 500.0
    end

    local misc = misc_menu()
    if misc == nil then
        return
    end
    if not misc.MiscShowOverheadNames then
        for _, tag in pairs(gamer_tags) do
            RemoveMpGamerTag(tag)
        end
        gamer_tags = {}
        return
    end

    local my_pos = GetEntityCoords(PlayerPedId())
    for _, p in ipairs(PlayerLists.players()) do
        if not p.is_local and p.ped ~= 0 then
            local pos = GetEntityCoords(p.ped)
            local dx, dy, dz = pos.x - my_pos.x, pos.y - my_pos.y, pos.z - my_pos.z
            local dist = dx * dx + dy * dy + dz * dz
            local close_enough = dist < player_names_distance
            if gamer_tags[p.handle] ~= nil then
                if not close_enough then
                    RemoveMpGamerTag(gamer_tags[p.handle])
                    gamer_tags[p.handle] = nil
                else
                    gamer_tags[p.handle] =
                        CreateMpGamerTag(p.ped, ('%s [%d]'):format(p.name, p.server_id), false, false, '', 0)
                end
            elseif close_enough then
                gamer_tags[p.handle] =
                    CreateMpGamerTag(p.ped, ('%s [%d]'):format(p.name, p.server_id), false, false, '', 0)
            end
            if close_enough and gamer_tags[p.handle] ~= nil then
                SetMpGamerTagVisibility(gamer_tags[p.handle], 2, true) -- healthArmor
                local wanted = GetPlayerWantedLevel(p.handle)
                if wanted > 0 then
                    SetMpGamerTagVisibility(gamer_tags[p.handle], 7, true) -- wantedStars
                    SetMpGamerTagWantedLevel(gamer_tags[p.handle], wanted)
                else
                    SetMpGamerTagVisibility(gamer_tags[p.handle], 7, false)
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Online players waypoint routes
-- ---------------------------------------------------------------------------

function Hud.online_players_tasks()
    Wait(500)
    local online_players = State.menus.online_players
    if online_players == nil or #online_players.players_waypoint_list < 1 then
        return
    end

    for _, server_id in ipairs(online_players.players_waypoint_list) do
        local player = nil
        for _, p in ipairs(PlayerLists.players()) do
            if p.server_id == server_id then
                player = p
                break
            end
        end

        if player == nil then
            waypoint_player_ids_to_remove[#waypoint_player_ids_to_remove + 1] = server_id
        elseif player.ped ~= 0 then
            local pos1 = GetEntityCoords(GetPlayerPed(player.handle), true)
            local pos2 = GetEntityCoords(PlayerPedId())
            if Vdist2(pos1.x, pos1.y, pos1.z, pos2.x, pos2.y, pos2.z) < 20.0 then
                local blip = GetBlipFromEntity(GetPlayerPed(player.handle))
                if DoesBlipExist(blip) then
                    SetBlipRoute(blip, false)
                    RemoveBlip(blip)
                    -- upstream adds the local player *handle* here (not the
                    -- server id); quirk preserved
                    waypoint_player_ids_to_remove[#waypoint_player_ids_to_remove + 1] = player.handle
                    Notify.custom(
                        ("~g~You've reached ~s~<C>%s</C>'s~g~ location, disabling GPS route."):format(
                            GetPlayerName(player.handle)
                        )
                    )
                end
            end
        end
        Wait(10)
    end

    if #waypoint_player_ids_to_remove > 0 then
        for _, id in ipairs(waypoint_player_ids_to_remove) do
            local coord_blip = online_players.player_coord_waypoints[id]
            if coord_blip ~= nil and DoesBlipExist(coord_blip) then
                SetBlipRoute(coord_blip, false)
                RemoveBlip(coord_blip)
            end
            for i, server_id in ipairs(online_players.players_waypoint_list) do
                if server_id == id then
                    table.remove(online_players.players_waypoint_list, i)
                    break
                end
            end
        end
        Wait(10)
    end
    waypoint_player_ids_to_remove = {}
end

-- ---------------------------------------------------------------------------
-- Entity outlines tool (model dimensions)
-- ---------------------------------------------------------------------------

-- Draws the 12 bounding-box edges for an entity.
local function draw_entity_bounding_box(entity, r, g, b, a)
    local min, max = GetModelDimensions(GetEntityModel(entity))
    local corners = {}
    for _, corner in ipairs({
        { min.x, min.y, min.z },
        { max.x, min.y, min.z },
        { max.x, max.y, min.z },
        { min.x, max.y, min.z },
        { min.x, min.y, max.z },
        { max.x, min.y, max.z },
        { max.x, max.y, max.z },
        { min.x, max.y, max.z },
    }) do
        corners[#corners + 1] = GetOffsetFromEntityInWorldCoords(entity, corner[1], corner[2], corner[3])
    end
    local edges = {
        { 1, 2 },
        { 2, 3 },
        { 3, 4 },
        { 4, 1 },
        { 5, 6 },
        { 6, 7 },
        { 7, 8 },
        { 8, 5 },
        { 1, 5 },
        { 2, 6 },
        { 3, 7 },
        { 4, 8 },
    }
    for _, edge in ipairs(edges) do
        local p1, p2 = corners[edge[1]], corners[edge[2]]
        DrawLine(p1.x, p1.y, p1.z, p2.x, p2.y, p2.z, r, g, b, a)
    end
end

local function draw_entity_annotations(misc, entity, label)
    local pos = GetEntityCoords(entity)
    if misc.ShowEntityHandles and IsEntityOnScreen(entity) then
        SetDrawOrigin(pos.x, pos.y, pos.z, 0)
        Common.draw_text_on_screen(('%s %d'):format(label, entity), 0.0, 0.0, 0.3, Common.ALIGN_CENTER, 0)
        ClearDrawOrigin()
    end
    if misc.ShowEntityModels and IsEntityOnScreen(entity) then
        SetDrawOrigin(pos.x, pos.y, pos.z - 0.3, 0)
        local model = GetEntityModel(entity)
        Common.draw_text_on_screen(
            ('Hash %d / %d / 0x%08X'):format(model, model & 0xFFFFFFFF, model & 0xFFFFFFFF),
            0.0,
            0.0,
            0.3,
            Common.ALIGN_CENTER,
            0
        )
        ClearDrawOrigin()
    end
    if misc.ShowEntityNetOwners and IsEntityOnScreen(entity) then
        local net_owner = NetworkGetEntityOwner(entity)
        if net_owner ~= 0 then
            SetDrawOrigin(pos.x, pos.y, pos.z + 0.3, 0)
            Common.draw_text_on_screen(
                ('Owner ID %d (%s)'):format(GetPlayerServerId(net_owner), GetPlayerName(net_owner)),
                0.0,
                0.0,
                0.3,
                Common.ALIGN_CENTER,
                0
            )
            ClearDrawOrigin()
        end
    end
end

function Hud.model_draw_dimensions()
    local misc = misc_menu()
    if State.config_options_setup_complete and misc ~= nil then
        if misc.ShowVehicleModelDimensions then
            for _, v in ipairs(vehicles) do
                if stop_vehicles_loop then
                    break
                end
                draw_entity_bounding_box(v, 250, 150, 0, 100)
                draw_entity_annotations(misc, v, 'Veh')
            end
        end
        if misc.ShowPropModelDimensions then
            for _, p in ipairs(props) do
                if stop_props_loop then
                    break
                end
                draw_entity_bounding_box(p, 255, 0, 0, 100)
                draw_entity_annotations(misc, p, 'Prop')
            end
        end
        if misc.ShowPedModelDimensions then
            for _, p in ipairs(peds) do
                if stop_peds_loop then
                    break
                end
                draw_entity_bounding_box(p, 50, 255, 50, 100)
                draw_entity_annotations(misc, p, 'Ped')
            end
        end
    end
end

local function gather_close_entities(pool)
    local my_pos = GetEntityCoords(PlayerPedId())
    local list = {}
    for _, entity in ipairs(GetGamePool(pool)) do
        if IsEntityOnScreen(entity) then
            local pos = GetEntityCoords(entity)
            local dx, dy, dz = pos.x - my_pos.x, pos.y - my_pos.y, pos.z - my_pos.z
            if (dx * dx + dy * dy + dz * dz) < State.entity_range then
                list[#list + 1] = entity
            end
        end
    end
    return list
end

function Hud.slow_misc_tick()
    local delay = 50
    local misc = misc_menu()
    if State.config_options_setup_complete and misc ~= nil then
        if misc.ShowPropModelDimensions then
            stop_props_loop = true
            props = gather_close_entities('CObject')
            stop_props_loop = false
            Wait(delay)
        end
        if misc.ShowPedModelDimensions then
            stop_peds_loop = true
            peds = gather_close_entities('CPed')
            stop_peds_loop = false
            Wait(delay)
        end
        if misc.ShowVehicleModelDimensions then
            stop_vehicles_loop = true
            vehicles = gather_close_entities('CVehicle')
            stop_vehicles_loop = false
            Wait(delay)
        end
    end
end

return Hud
