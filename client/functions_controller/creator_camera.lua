-- Port of vMenu/FunctionsController.cs (part 3 of 3): the MP character
-- creator camera (per-menu framing, turn head/character, reverse), movement
-- blocking while the creator is open, and the world interactions: snowball
-- pickups and helmet visor toggles.

local Config = require('shared.config')
local Permissions = require('shared.permissions')
local Common = require('client.common')
local State = require('client.state')
local Controller = require('menu.controller')
local Items = require('menu.items')

local CreatorCamera = {}

local CONTROLS = {
    NextCamera = 0,
    LookLeftRight = 1,
    LookUpDown = 2,
    LookUpOnly = 3,
    LookDownOnly = 4,
    LookLeftOnly = 5,
    LookRightOnly = 6,
    WeaponWheelUpDown = 12,
    WeaponWheelLeftRight = 13,
    WeaponWheelNext = 14,
    WeaponWheelPrev = 15,
    SelectNextWeapon = 16,
    MultiplayerInfo = 20,
    Jump = 22,
    Enter = 23,
    Aim = 25,
    LookBehind = 26,
    MoveLeftRight = 30,
    MoveUpDown = 31,
    MoveUpOnly = 32,
    MoveDownOnly = 33,
    MoveLeftOnly = 34,
    MoveRightOnly = 35,
    Duck = 36,
    Cover = 44,
    Detonate = 47,
    AccurateAim = 50,
    WeaponSpecial = 53,
    WeaponSpecial2 = 54,
    VehicleHeadlight = 74,
    VehicleExit = 75,
    ParachuteBrakeLeft = 152,
    ParachuteBrakeRight = 153,
    PrevWeapon = 261,
    MoveLeft = 266,
    MoveRight = 267,
    MoveUp = 268,
    MoveDown = 269,
    LookLeft = 270,
    LookRight = 271,
    LookUp = 272,
    LookDown = 273,
    SwitchVisor = 344,
}

local reverse_camera = false
local current_cam = -1
local CAMERA_FOV = 45.0

-- CameraOffsets: { camera offset, point-at offset } per camera index.
local CAMERA_OFFSETS = {
    [0] = { { 0.0, 2.8, 0.3 }, { 0.0, 0.0, 0.0 } }, -- full body
    [1] = { { 0.0, 0.9, 0.65 }, { 0.0, 0.0, 0.6 } }, -- head level
    [2] = { { 0.0, 1.4, 0.5 }, { 0.0, 0.0, 0.3 } }, -- upper body
    [3] = { { 0.0, 1.6, -0.3 }, { 0.0, 0.0, -0.45 } }, -- lower body
    [4] = { { 0.0, 0.98, -0.7 }, { 0.0, 0.0, -0.90 } }, -- shoes
    [5] = { { 0.0, 0.98, 0.1 }, { 0.0, 0.0, 0.0 } }, -- lower arms
    [6] = { { 0.0, 1.3, 0.35 }, { 0.0, 0.0, 0.15 } }, -- full arms
}

local function is_mp_char_editor_open()
    local mp = State.menus.mp_ped_customization
    if mp == nil then
        return false
    end
    return mp.AppearanceMenu.Visible
        or mp.FaceShapeMenu.Visible
        or mp.CreateCharacterMenu.Visible
        or mp.InheritanceMenu.Visible
        or mp.PropsMenu.Visible
        or mp.ClothesMenu.Visible
        or mp.TattoosMenu.Visible
end

local function get_camera_index(menu)
    local mp = State.menus.mp_ped_customization
    if menu == nil or mp == nil then
        return 0
    end
    if menu == mp.InheritanceMenu then
        return 1
    elseif menu == mp.ClothesMenu then
        local index_map = { [0] = 1, [1] = 2, [2] = 3, [3] = 2, [4] = 4, [5] = 2, [6] = 2, [7] = 2, [8] = 0, [9] = 2 }
        return index_map[menu.CurrentIndex] or 0
    elseif menu == mp.PropsMenu then
        local i = menu.CurrentIndex
        if i == 0 or i == 1 or i == 2 then
            return 1
        elseif i == 3 then
            return reverse_camera and 5 or 6
        elseif i == 4 then
            return 5
        end
        return 0
    elseif menu == mp.AppearanceMenu then
        local i = menu.CurrentIndex
        if i >= 0 and i <= 27 then
            return 1
        elseif i >= 28 and i <= 32 then
            return 2
        elseif i == 33 then
            return 1
        end
        return 0
    elseif menu == mp.TattoosMenu then
        local i = menu.CurrentIndex
        if i == 0 or i == 1 then
            return 1
        elseif i == 2 or i == 7 then
            return 2
        elseif i == 3 or i == 4 then
            return 6
        elseif i == 5 or i == 6 then
            return 3
        end
        return 0
    elseif menu == mp.FaceShapeMenu then
        local item = menu:GetCurrentMenuItem()
        if item ~= nil and item.Position ~= nil then
            return 1
        end
        return 0
    end
    return 0
end

function CreatorCamera.clear_camera()
    SetCamActive(current_cam, false)
    RenderScriptCams(false, false, 0, false, false)
    DestroyCam(current_cam, false)
    current_cam = -1
end

-- Interpolates to a new camera position.
local function update_camera(old_cam, pos, point_at)
    local new_cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(new_cam, pos.x, pos.y, pos.z)
    SetCamFov(new_cam, CAMERA_FOV)
    PointCamAtCoord(new_cam, point_at.x, point_at.y, point_at.z)
    SetCamActiveWithInterp(new_cam, old_cam, 1000, 1, 1)
    while IsCamInterpolating(old_cam) or not IsCamActive(new_cam) do
        SetEntityCollision(PlayerPedId(), false, false)
        FreezeEntityPosition(PlayerPedId(), true)
        Wait(0)
    end
    Wait(50)
    DestroyCam(old_cam, false)
    current_cam = new_cam
end

local WATCHES_ANIM_DICT = 'anim@random@shop_clothes@watches'
local VEHICLE_LOCK_NOTE = ' ~r~You need to get out of your vehicle before you can use this.'

local function lock_creator_button(btn)
    if btn ~= nil and btn.Enabled then
        btn.Enabled = false
        btn.LeftIcon = Items.Icon.LOCK
        btn.Description = btn.Description .. VEHICLE_LOCK_NOTE
    end
end

local function unlock_creator_button(btn)
    if btn ~= nil and not btn.Enabled then
        btn.Enabled = true
        btn.LeftIcon = Items.Icon.NONE
        local start_pos = btn.Description:find(VEHICLE_LOCK_NOTE, 1, true)
        if start_pos ~= nil then
            btn.Description = btn.Description:sub(1, start_pos - 1)
                .. btn.Description:sub(start_pos + #VEHICLE_LOCK_NOTE)
        end
    end
end

function CreatorCamera.manage_camera()
    local mp = State.menus.mp_ped_customization
    if mp == nil then
        Wait(100)
        return
    end

    -- the creator can't be entered from inside a vehicle
    if IsPedInAnyVehicle(PlayerPedId(), false) then
        lock_creator_button(mp.EditPedBtn)
        lock_creator_button(mp.CreateMaleBtn)
        lock_creator_button(mp.CreateFemaleBtn)
    else
        unlock_creator_button(mp.EditPedBtn)
        unlock_creator_button(mp.CreateMaleBtn)
        unlock_creator_button(mp.CreateFemaleBtn)
    end

    if is_mp_char_editor_open() then
        if not HasAnimDictLoaded(WATCHES_ANIM_DICT) then
            RequestAnimDict(WATCHES_ANIM_DICT)
        end
        while not HasAnimDictLoaded(WATCHES_ANIM_DICT) do
            Wait(0)
        end

        while is_mp_char_editor_open() do
            Wait(0)
            local ped = PlayerPedId()

            local index = get_camera_index(Controller.GetCurrentMenu())
            if
                Controller.GetCurrentMenu() == mp.PropsMenu
                and mp.PropsMenu.CurrentIndex == 3
                and not reverse_camera
            then
                TaskPlayAnim(ped, WATCHES_ANIM_DICT, 'BASE', 8.0, -8.0, -1, 1, 0, false, false, false)
            else
                ClearPedTasks(ped)
            end

            local x_offset = 0.0
            local y_offset = 0.0

            local brake_left = IsControlPressed(0, CONTROLS.ParachuteBrakeLeft)
            local brake_right = IsControlPressed(0, CONTROLS.ParachuteBrakeRight)
            if (brake_left or brake_right) and not (brake_left and brake_right) then
                local offsets = {
                    [0] = { 2.2, -1.0 },
                    [1] = { 0.7, -0.45 },
                    [2] = { 1.35, -0.4 },
                    [3] = { 1.0, -0.4 },
                    [4] = { 0.9, -0.4 },
                    [5] = { 0.8, -0.7 },
                    [6] = { 1.5, -1.0 },
                }
                local pair = offsets[index] or { 0.0, 0.2 }
                x_offset = pair[1]
                y_offset = pair[2]
                if brake_right then
                    x_offset = x_offset * -1.0
                end
            end

            local offset = CAMERA_OFFSETS[index]
            local pos
            if reverse_camera then
                pos = GetOffsetFromEntityInWorldCoords(
                    ped,
                    (offset[1][1] + x_offset) * -1.0,
                    (offset[1][2] + y_offset) * -1.0,
                    offset[1][3]
                )
            else
                pos = GetOffsetFromEntityInWorldCoords(
                    ped,
                    offset[1][1] + x_offset,
                    offset[1][2] + y_offset,
                    offset[1][3]
                )
            end
            local point_at = GetOffsetFromEntityInWorldCoords(ped, offset[2][1], offset[2][2], offset[2][3])

            -- turn head
            if IsControlPressed(0, CONTROLS.MoveLeftOnly) then
                local look = GetOffsetFromEntityInWorldCoords(ped, 1.2, 0.5, 0.7)
                TaskLookAtCoord(ped, look.x, look.y, look.z, 1100, 0, 2)
            elseif IsControlPressed(0, CONTROLS.MoveRightOnly) then
                local look = GetOffsetFromEntityInWorldCoords(ped, -1.2, 0.5, 0.7)
                TaskLookAtCoord(ped, look.x, look.y, look.z, 1100, 0, 2)
            else
                local look = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.5, 0.7)
                TaskLookAtCoord(ped, look.x, look.y, look.z, 1100, 0, 2)
            end

            -- turn the character around
            if IsControlJustReleased(0, CONTROLS.Jump) then
                local position = GetEntityCoords(ped)
                SetEntityCollision(ped, true, true)
                FreezeEntityPosition(ped, false)
                TaskGoStraightToCoord(
                    ped,
                    position.x,
                    position.y,
                    position.z,
                    8.0,
                    1600,
                    GetEntityHeading(ped) + 180.0,
                    0.1
                )
                local timer = GetGameTimer()
                while true do
                    Wait(0)
                    DisableAllControlActions(0)
                    if GetGameTimer() - timer > 1600 then
                        break
                    end
                end
                ClearPedTasks(ped)
                SetEntityCoordsNoOffset(ped, position.x, position.y, position.z, false, false, false)
                FreezeEntityPosition(ped, true)
                SetEntityCollision(ped, false, false)
                reverse_camera = not reverse_camera
            end

            SetEntityCollision(ped, false, false)
            FreezeEntityPosition(ped, true)

            if not DoesCamExist(current_cam) then
                current_cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
                SetCamCoord(current_cam, pos.x, pos.y, pos.z)
                SetCamFov(current_cam, CAMERA_FOV)
                PointCamAtCoord(current_cam, point_at.x, point_at.y, point_at.z)
                RenderScriptCams(true, false, 0, false, false)
                SetCamActive(current_cam, true)
            else
                local cam_pos = GetCamCoord(current_cam)
                if cam_pos.x ~= pos.x or cam_pos.y ~= pos.y or cam_pos.z ~= pos.z then
                    update_camera(current_cam, pos, point_at)
                end
            end
        end

        SetEntityCollision(PlayerPedId(), true, true)
        FreezeEntityPosition(PlayerPedId(), false)

        DisplayHud(true)
        DisplayRadar(true)

        if HasAnimDictLoaded(WATCHES_ANIM_DICT) then
            RemoveAnimDict(WATCHES_ANIM_DICT)
        end

        reverse_camera = false
    else
        if current_cam ~= -1 then
            CreatorCamera.clear_camera()
        end
    end
end

function CreatorCamera.disable_movement()
    if is_mp_char_editor_open() then
        for _, control in ipairs({
            CONTROLS.MoveDown,
            CONTROLS.MoveDownOnly,
            CONTROLS.MoveLeft,
            CONTROLS.MoveLeftOnly,
            CONTROLS.MoveLeftRight,
            CONTROLS.MoveRight,
            CONTROLS.MoveRightOnly,
            CONTROLS.MoveUp,
            CONTROLS.MoveUpDown,
            CONTROLS.MoveUpOnly,
            CONTROLS.NextCamera,
            CONTROLS.LookBehind,
            CONTROLS.LookDown,
            CONTROLS.LookDownOnly,
            CONTROLS.LookLeft,
            CONTROLS.LookLeftOnly,
            CONTROLS.LookLeftRight,
            CONTROLS.LookRight,
            CONTROLS.LookRightOnly,
            CONTROLS.LookUp,
            CONTROLS.LookUpDown,
            CONTROLS.LookUpOnly,
            CONTROLS.Aim,
            CONTROLS.AccurateAim,
            CONTROLS.Cover,
            CONTROLS.Duck,
            CONTROLS.Jump,
            CONTROLS.SelectNextWeapon,
            CONTROLS.PrevWeapon,
            CONTROLS.WeaponSpecial,
            CONTROLS.WeaponSpecial2,
            CONTROLS.WeaponWheelLeftRight,
            CONTROLS.WeaponWheelNext,
            CONTROLS.WeaponWheelPrev,
            CONTROLS.WeaponWheelUpDown,
            CONTROLS.VehicleExit,
            CONTROLS.Enter,
        }) do
            DisableControlAction(0, control, true)
        end
    else
        Wait(0)
    end
end

-- ---------------------------------------------------------------------------
-- Snowballs + helmet visor interactions
-- ---------------------------------------------------------------------------

local SNOWBALL_ANIM_DICT = 'anim@mp_snowball'
local SNOWBALL_ANIM_NAME = 'pickup_snowball'
local SNOWBALL_HASH = GetHashKey('weapon_snowball')
local show_snowball_info = false

local function pickup_snowball_once()
    if not State.config_options_setup_complete then
        return
    end
    local ped = PlayerPedId()
    ClearPedTasks(ped)
    local _, max_ammo = GetMaxAmmo(ped, SNOWBALL_HASH)
    max_ammo = max_ammo or 10
    if GetAmmoInPedWeapon(ped, SNOWBALL_HASH) < max_ammo then
        SetPedCurrentWeaponVisible(ped, false, true, false, false)
        if not HasAnimDictLoaded(SNOWBALL_ANIM_DICT) then
            RequestAnimDict(SNOWBALL_ANIM_DICT)
            while not HasAnimDictLoaded(SNOWBALL_ANIM_DICT) do
                Wait(0)
            end
        end
        TaskPlayAnim(ped, SNOWBALL_ANIM_DICT, SNOWBALL_ANIM_NAME, 8.0, 1.0, -1, 0, 0.0, false, false, false)
        local fired = false
        local duration = GetAnimDuration(SNOWBALL_ANIM_DICT, SNOWBALL_ANIM_NAME)
        local timer = GetGameTimer()
        while GetEntityAnimCurrentTime(ped, SNOWBALL_ANIM_DICT, SNOWBALL_ANIM_NAME) < 0.97 do
            Wait(0)
            if not fired then
                if HasAnimEventFired(ped, GetHashKey('CreateObject')) then
                    AddAmmoToPed(ped, SNOWBALL_HASH, 2)
                    GiveWeaponToPed(ped, SNOWBALL_HASH, 0, true, true)
                    if GetAmmoInPedWeapon(ped, SNOWBALL_HASH) > max_ammo then
                        SetPedAmmo(ped, SNOWBALL_HASH, max_ammo)
                    end
                    fired = true
                elseif HasAnimEventFired(ped, GetHashKey('Interrupt')) then
                    break
                end
            elseif HasAnimEventFired(ped, GetHashKey('Interrupt')) then
                break
            end
            if GetGameTimer() - timer > (duration * 1000.0) then
                break
            end
        end
    else
        ClearAllHelpMessages()
        BeginTextCommandDisplayHelp('string')
        AddTextComponentSubstringPlayerName(('You can not carry more than %d snowballs!'):format(max_ammo))
        EndTextCommandDisplayHelp(0, false, true, 6000)
    end
end

-- Resolves the alternate (visor up/down) prop variation. The C# helper reads
-- an unsafe struct native; here the variant combination hash is matched back
-- to a local prop index instead. Verify in-game (M10 checklist).
local function get_alt_prop_variation(ped)
    local component = GetPedPropIndex(ped, 0)
    local texture = GetPedPropTextureIndex(ped, 0)
    local comp_hash = GetHashNameForProp(ped, 0, component, texture)
    if GetShopPedApparelVariantPropCount(comp_hash) <= 0 then
        return nil
    end
    local variant_hash = Citizen.InvokeNative(
        0xD81B7F27BC773E66,
        comp_hash,
        0,
        Citizen.PointerValueInt(),
        Citizen.PointerValueInt(),
        Citizen.PointerValueInt()
    )
    for drawable = 0, GetNumberOfPedPropDrawableVariations(ped, 0) - 1 do
        for tex = 0, GetNumberOfPedPropTextureVariations(ped, 0, drawable) - 1 do
            if GetHashNameForProp(ped, 0, drawable, tex) == variant_hash then
                return drawable, tex
            end
        end
    end
    return nil
end

local SPORT_BIKES = {
    'AKUMA',
    'BATI',
    'BATI2',
    'CARBONRS',
    'DEFILER',
    'DIABLOUS2',
    'DOUBLE',
    'FCR',
    'FCR2',
    'HAKUCHOU',
    'HAKUCHOU2',
    'LECTRO',
    'NEMESIS',
    'OPPRESSOR',
    'OPPRESSOR2',
    'PCJ',
    'RUFFIAN',
    'SHOTARO',
    'VADER',
    'VORTEX',
}
local CHOPPER_BIKES = { 'SANCTUS', 'ZOMBIEA', 'ZOMBIEB' }
local DIRT_BIKES = { 'BF400', 'ENDURO', 'MANCHEZ', 'SANCHEZ', 'SANCHEZ2', 'ESSKEY' }
local SCOOTERS = { 'FAGGIO', 'FAGGIO2', 'FAGGIO3', 'CLIFFHANGER', 'BAGGER' }
local POLICE_BIKES = {
    'AVARUS',
    'CHIMERA',
    'POLICEB',
    'SOVEREIGN',
    'HEXER',
    'INNOVATION',
    'NIGHTBLADE',
    'RATBIKE',
    'DAEMON',
    'DAEMON2',
    'DIABLOUS',
    'GARGOYLE',
    'THRUST',
    'VINDICATOR',
    'WOLFSBANE',
}

local function model_in(list, model)
    for _, name in ipairs(list) do
        if GetHashKey(name) == model then
            return true
        end
    end
    return false
end

local function switch_helmet_once()
    if not State.config_options_setup_complete then
        return
    end
    local ped = PlayerPedId()
    local component = GetPedPropIndex(ped, 0)
    local new_helmet, new_helmet_texture = get_alt_prop_variation(ped)
    if new_helmet == nil then
        return
    end

    local anim_name = component < new_helmet and 'visor_up' or 'visor_down'
    if GetEntityModel(ped) == GetHashKey('mp_f_freemode_01') then
        if component == 66 or component == 81 then
            anim_name = component > new_helmet and 'visor_up' or 'visor_down'
        end
        if component >= 115 and component <= 118 then
            anim_name = component < new_helmet and 'goggles_up' or 'goggles_down'
        end
    else
        if component == 67 or component == 82 then
            anim_name = component > new_helmet and 'visor_up' or 'visor_down'
        end
        if component >= 116 and component <= 119 then
            anim_name = component < new_helmet and 'goggles_up' or 'goggles_down'
        end
    end

    local anim_dict = 'anim@mp_helmets@on_foot'

    if GetFollowPedCamViewMode() == 4 then
        anim_name = 'pov_' .. anim_name:gsub('goggles', 'visor')
    end

    if IsPedInAnyVehicle(ped, false) then
        if anim_name:find('goggles', 1, true) then
            ClearAllHelpMessages()
            BeginTextCommandDisplayHelp('string')
            AddTextComponentSubstringPlayerName('You can not toggle your goggles while in a vehicle.')
            EndTextCommandDisplayHelp(0, false, true, 6000)
            return
        end
        local veh = Common.get_vehicle()
        if veh ~= 0 and DoesEntityExist(veh) and not IsEntityDead(veh) then
            local model = GetEntityModel(veh)
            if IsThisModelABicycle(model) then
                anim_dict = 'anim@mp_helmets@on_bike@scooter'
            elseif IsThisModelABike(model) then
                if model_in(POLICE_BIKES, model) then
                    anim_dict = 'anim@mp_helmets@on_bike@policeb'
                elseif model_in(SPORT_BIKES, model) then
                    anim_dict = 'anim@mp_helmets@on_bike@sports'
                elseif model_in(CHOPPER_BIKES, model) then
                    anim_dict = 'anim@mp_helmets@on_bike@chopper'
                elseif model_in(DIRT_BIKES, model) then
                    anim_dict = 'anim@mp_helmets@on_bike@dirt'
                elseif model_in(SCOOTERS, model) then
                    anim_dict = 'anim@mp_helmets@on_bike@scooter'
                else
                    anim_dict = 'anim@mp_helmets@on_bike@sports'
                end
            elseif IsThisModelAQuadbike(model) then
                anim_dict = 'anim@mp_helmets@on_bike@quad'
            end
        end
    end

    if not HasAnimDictLoaded(anim_dict) then
        RequestAnimDict(anim_dict)
        while not HasAnimDictLoaded(anim_dict) do
            Wait(0)
        end
    end
    if anim_name:sub(1, 4) == 'pov_' and anim_dict ~= 'anim@mp_helmets@on_foot' then
        anim_name = anim_name:sub(5)
    end
    ClearPedTasks(ped)
    TaskPlayAnim(ped, anim_dict, anim_name, 8.0, 1.0, -1, 48, 0.0, false, false, false)
    local timeout_timer = GetGameTimer()
    while GetEntityAnimCurrentTime(ped, anim_dict, anim_name) <= 0.0 do
        if GetGameTimer() - timeout_timer > 1000 then
            ClearPedTasks(ped)
            return
        end
        Wait(0)
    end
    timeout_timer = GetGameTimer()
    while GetEntityAnimCurrentTime(ped, anim_dict, anim_name) > 0.0 do
        Wait(0)
        if GetGameTimer() - timeout_timer > 3000 then
            ClearPedTasks(ped)
            return
        end
        if GetEntityAnimCurrentTime(ped, anim_dict, anim_name) > 0.39 then
            SetPedPropIndex(ped, 0, new_helmet, new_helmet_texture, true)
        end
    end
    ClearPedTasks(ped)
    RemoveAnimDict(anim_dict)
end

local function busy_or_hidden()
    return Controller.IsAnyMenuOpen()
        or not IsScreenFadedIn()
        or IsPauseMenuActive()
        or IsPlayerSwitchInProgress()
        or IsEntityDead(PlayerPedId())
end

function CreatorCamera.animations_and_interactions()
    if not busy_or_hidden() then
        local ped = PlayerPedId()

        -- snowballs
        if Config.get_bool('vmenu_enable_snow') and Permissions.is_allowed('WPSnowball') then
            if IsControlJustReleased(0, CONTROLS.Detonate) then
                if
                    not (
                        IsPedInAnyVehicle(ped, false)
                        or IsEntityDead(ped)
                        or not IsScreenFadedIn()
                        or IsPlayerSwitchInProgress()
                        or IsPauseMenuActive()
                        or GetInteriorFromEntity(ped) ~= 0
                        or not IsPedOnFoot(ped)
                        or IsPedInParachuteFreeFall(ped)
                        or IsPedFalling(ped)
                        or IsPedBeingStunned(ped, 0)
                        or IsPedWalking(ped)
                        or IsPedRunning(ped)
                        or IsPedSprinting(ped)
                        or IsPedSwimming(ped)
                        or IsPedSwimmingUnderWater(ped)
                        or (IsPedDiving(ped) and GetSelectedPedWeapon(ped) == SNOWBALL_HASH)
                        or GetSelectedPedWeapon(ped) == GetHashKey('unarmed')
                    )
                then
                    pickup_snowball_once()
                end
            end
        end

        -- helmet visor (hold)
        if IsControlPressed(0, CONTROLS.SwitchVisor) then
            local timer = GetGameTimer()
            while not busy_or_hidden() and IsControlPressed(0, CONTROLS.SwitchVisor) do
                Wait(0)
                local veh = Common.get_vehicle()
                local model = veh ~= 0 and GetEntityModel(veh) or 0
                local in_veh = veh ~= 0
                    and (IsThisModelABike(model) or IsThisModelABicycle(model) or IsThisModelAQuadbike(model))
                if GetGameTimer() - timer > 380 and in_veh then
                    DisableControlAction(2, CONTROLS.VehicleHeadlight, true)
                end
                if GetGameTimer() - timer > 400 then
                    switch_helmet_once()
                    break
                end
            end
            while IsControlPressed(0, CONTROLS.SwitchVisor) do
                Wait(0)
            end
        end
    end
end

function CreatorCamera.snowball_pickup_help_message_task()
    if Config.get_bool('vmenu_enable_snow') then
        local ped = PlayerPedId()
        if not IsPedInAnyVehicle(ped, true) then
            if show_snowball_info then
                BeginTextCommandIsThisHelpMessageBeingDisplayed('HELP_SNOWP')
                if EndTextCommandIsThisHelpMessageBeingDisplayed(0) then
                    show_snowball_info = false
                    return
                elseif IsHelpMessageBeingDisplayed() then
                    ClearAllHelpMessages()
                end
                local _, max_ammo = GetMaxAmmo(ped, SNOWBALL_HASH)
                max_ammo = max_ammo or 10
                if max_ammo > GetAmmoInPedWeapon(ped, SNOWBALL_HASH) then
                    BeginTextCommandDisplayHelp('HELP_SNOWP')
                    AddTextComponentInteger(2)
                    AddTextComponentInteger(max_ammo)
                    EndTextCommandDisplayHelp(0, false, true, 6000)
                end
            end
            show_snowball_info = false
        else
            show_snowball_info = true
        end
    end
    Wait(100)
end

return CreatorCamera
