-- Port of vMenu/Noclip.cs: the noclip movement controller. While active it
-- moves the player (or their vehicle) with camera-relative controls, shows
-- the instructional-buttons scaleform, and resets entity state every frame
-- so other players never see the entity frozen/invisible for long.

local Config = require('shared.config')
local State = require('client.state')

local NoClip = {}

local SPEEDS = {
    'Very Slow',
    'Slow',
    'Normal',
    'Fast',
    'Very Fast',
    'Extremely Fast',
    'Extremely Fast v2.0',
    'Max Speed',
}

-- Control ids (CitizenFX.Core Control enum).
local CONTROLS = {
    MultiplayerInfo = 20,
    Sprint = 21,
    MoveLeftRight = 30,
    MoveUpDown = 31,
    MoveUpOnly = 32,
    MoveDownOnly = 33,
    MoveLeftOnly = 34,
    MoveRightOnly = 35,
    Cover = 44,
    VehicleHeadlight = 74,
    VehicleRadioWheel = 85,
    MoveLeft = 266,
    MoveRight = 267,
    MoveUp = 268,
    MoveDown = 269,
}

local active = false
local moving_speed = 0 -- 0-based index into SPEEDS
local scale = -1
local follow_cam_mode = true

function NoClip.is_noclip_active()
    return active
end

-- C#'s JOAAT helper: hex string of the joaat hash, used to resolve the
-- ~INPUT_...~ instructional label for the registered noclip key mapping.
local function joaat_hex(command)
    local hash = 0
    local str = command:lower()
    for i = 1, #str do
        hash = (hash + str:byte(i)) & 0xFFFFFFFF
        hash = (hash + (hash << 10)) & 0xFFFFFFFF
        hash = hash ~ (hash >> 6)
    end
    hash = (hash + (hash << 3)) & 0xFFFFFFFF
    hash = hash ~ (hash >> 11)
    hash = (hash + (hash << 15)) & 0xFFFFFFFF
    return ('%X'):format(hash)
end

local function key_mapping_id()
    local id = Config.get_string('vmenu_keymapping_id')
    if id == nil or id:gsub('%s', '') == '' then
        return 'Default'
    end
    return id
end

local function push_data_slot(slot, button, label)
    BeginScaleformMovieMethod(scale, 'SET_DATA_SLOT')
    ScaleformMovieMethodAddParamInt(slot)
    PushScaleformMovieMethodParameterString(button)
    PushScaleformMovieMethodParameterString(label)
    EndScaleformMovieMethod()
end

local function draw_instructional_buttons()
    BeginScaleformMovieMethod(scale, 'CLEAR_ALL')
    EndScaleformMovieMethod()

    push_data_slot(0, '~INPUT_SPRINT~', ('Change Speed (%s)'):format(SPEEDS[moving_speed + 1]))
    push_data_slot(1, '~INPUT_MOVE_LR~', 'Turn Left/Right')
    push_data_slot(2, '~INPUT_MOVE_UD~', 'Move')
    push_data_slot(3, '~INPUT_MULTIPLAYER_INFO~', 'Down')
    push_data_slot(4, '~INPUT_COVER~', 'Up')
    push_data_slot(5, '~INPUT_VEH_HEADLIGHT~', 'Cam Mode')
    push_data_slot(6, ('~INPUT_%s~'):format(joaat_hex(('vMenu:%s:NoClip'):format(key_mapping_id()))), 'Toggle NoClip')

    BeginScaleformMovieMethod(scale, 'DRAW_INSTRUCTIONAL_BUTTONS')
    ScaleformMovieMethodAddParamInt(0)
    EndScaleformMovieMethod()

    DrawScaleformMovieFullscreen(scale, 255, 255, 255, 255, 0)
end

local function noclip_tick()
    scale = RequestScaleformMovie('INSTRUCTIONAL_BUTTONS')
    while not HasScaleformMovieLoaded(scale) do
        Wait(0)
    end
    DrawScaleformMovieFullscreen(scale, 255, 255, 255, 0, 0)

    while active do
        if not IsHudHidden() then
            draw_instructional_buttons()
        end

        local ped = PlayerPedId()
        local noclip_entity = ped
        if IsPedInAnyVehicle(ped, false) then
            noclip_entity = GetVehiclePedIsIn(ped, false)
        end

        FreezeEntityPosition(noclip_entity, true)
        SetEntityInvincible(noclip_entity, true)

        DisableControlAction(0, CONTROLS.MoveUpOnly, true)
        DisableControlAction(0, CONTROLS.MoveUp, true)
        DisableControlAction(0, CONTROLS.MoveUpDown, true)
        DisableControlAction(0, CONTROLS.MoveDown, true)
        DisableControlAction(0, CONTROLS.MoveDownOnly, true)
        DisableControlAction(0, CONTROLS.MoveLeft, true)
        DisableControlAction(0, CONTROLS.MoveLeftOnly, true)
        DisableControlAction(0, CONTROLS.MoveLeftRight, true)
        DisableControlAction(0, CONTROLS.MoveRight, true)
        DisableControlAction(0, CONTROLS.MoveRightOnly, true)
        DisableControlAction(0, CONTROLS.Cover, true)
        DisableControlAction(0, CONTROLS.MultiplayerInfo, true)
        DisableControlAction(0, CONTROLS.VehicleHeadlight, true)
        if IsPedInAnyVehicle(ped, false) then
            DisableControlAction(0, CONTROLS.VehicleRadioWheel, true)
        end

        local yoff = 0.0
        local zoff = 0.0

        -- Game.CurrentInputMode == MouseAndKeyboard, keyboard closed, not paused.
        if IsInputDisabled(2) and UpdateOnscreenKeyboard() ~= 0 and not IsPauseMenuActive() then
            if IsControlJustPressed(0, CONTROLS.Sprint) then
                moving_speed = moving_speed + 1
                if moving_speed == #SPEEDS then
                    moving_speed = 0
                end
            end

            if IsDisabledControlPressed(0, CONTROLS.MoveUpOnly) then
                yoff = 0.5
            end
            if IsDisabledControlPressed(0, CONTROLS.MoveDownOnly) then
                yoff = -0.5
            end
            if not follow_cam_mode and IsDisabledControlPressed(0, CONTROLS.MoveLeftOnly) then
                SetEntityHeading(ped, GetEntityHeading(ped) + 3.0)
            end
            if not follow_cam_mode and IsDisabledControlPressed(0, CONTROLS.MoveRightOnly) then
                SetEntityHeading(ped, GetEntityHeading(ped) - 3.0)
            end
            if IsDisabledControlPressed(0, CONTROLS.Cover) then
                zoff = 0.21
            end
            if IsDisabledControlPressed(0, CONTROLS.MultiplayerInfo) then
                zoff = -0.21
            end
            if IsDisabledControlJustPressed(0, CONTROLS.VehicleHeadlight) then
                follow_cam_mode = not follow_cam_mode
            end
        end

        local move_speed = moving_speed + 0.0
        if moving_speed > #SPEEDS // 2 then
            move_speed = move_speed * 1.8
        end
        move_speed = move_speed / (1.0 / GetFrameTime()) * 60

        local new_pos =
            GetOffsetFromEntityInWorldCoords(noclip_entity, 0.0, yoff * (move_speed + 0.3), zoff * (move_speed + 0.3))

        local heading = GetEntityHeading(noclip_entity)
        SetEntityVelocity(noclip_entity, 0.0, 0.0, 0.0)
        SetEntityRotation(noclip_entity, 0.0, 0.0, 0.0, 0, false)
        SetEntityHeading(noclip_entity, follow_cam_mode and GetGameplayCamRelativeHeading() or heading)
        SetEntityCollision(noclip_entity, false, false)
        SetEntityCoordsNoOffset(noclip_entity, new_pos.x, new_pos.y, new_pos.z, true, true, true)

        SetEntityVisible(noclip_entity, false, false)
        SetLocalPlayerVisibleLocally(true)
        SetEntityAlpha(noclip_entity, 51, 0) -- 255 * 0.2

        SetEveryoneIgnorePlayer(ped, true)
        SetPoliceIgnorePlayer(ped, true)

        -- After the next game tick, reset the entity properties.
        Wait(0)
        FreezeEntityPosition(noclip_entity, false)
        SetEntityInvincible(noclip_entity, false)
        SetEntityCollision(noclip_entity, true, true)

        -- Keep the entity hidden only if PlayerOptions set the player
        -- invisible and the noclip entity is not the player ped itself.
        local player_options = State.menus.player_options
        if
            player_options == nil
            or not player_options.PlayerInvisible
            or (player_options.PlayerInvisible and noclip_entity == PlayerPedId())
        then
            SetEntityVisible(noclip_entity, true, false)
            SetLocalPlayerVisibleLocally(true)
        end

        ResetEntityAlpha(noclip_entity)

        SetEveryoneIgnorePlayer(ped, false)
        SetPoliceIgnorePlayer(ped, false)
    end
end

function NoClip.set_noclip_active(value)
    local was_active = active
    active = value == true

    if not active then
        if scale ~= -1 then
            SetScaleformMovieAsNoLongerNeeded(scale)
            scale = -1
        end
        return
    end

    if not was_active then
        CreateThread(noclip_tick)
    end
end

return NoClip
