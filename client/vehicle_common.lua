-- The vehicle half of vMenu/CommonFunctions.cs: capturing a vehicle's full
-- customization into the VehicleInfo shape (docs/contracts/kvp-saves.md),
-- re-applying it on spawn, saving, and deletion. This is the layer that
-- makes C#-era saved vehicles spawn identically.
--
-- JSON shape notes: colors is a string-keyed object; extras and mods are C#
-- Dictionary<int,...>, string-keyed in JSON and kept string-keyed here so
-- records round-trip byte-compatible (json_compat contract).

local Config = require('shared.config')
local Notification = require('client.notify')
local Storage = require('client.storage')
local Common = require('client.common')
local State = require('client.state')

local Notify = Notification.Notify

local VehicleCommon = {}

-- VehicleData.ModType: contiguous 0..49.
local MOD_TYPE_MAX = 49

-- GetAllVehicleMods: { { mod_type = int, index = int }, ... } for every mod
-- type this vehicle supports.
function VehicleCommon.get_all_vehicle_mods(vehicle)
    local mods = {}
    for mod_type = 0, MOD_TYPE_MAX do
        if GetNumVehicleMods(vehicle, mod_type) > 0 then
            mods[#mods + 1] = { mod_type = mod_type, index = GetVehicleMod(vehicle, mod_type) }
        end
    end
    return mods
end

-- VehicleOptions.SetHeadlightsColorForVehicle.
function VehicleCommon.set_headlights_color_for_vehicle(vehicle, new_index)
    if vehicle ~= 0 and DoesEntityExist(vehicle) and GetPedInVehicleSeat(vehicle, -1) == PlayerPedId() then
        if new_index > -1 and new_index < 13 then
            SetVehicleHeadlightsColour(vehicle, new_index)
        else
            SetVehicleHeadlightsColour(vehicle, -1)
        end
    end
end

-- VehicleOptions.GetHeadlightsColorForVehicle.
function VehicleCommon.get_headlights_color_for_vehicle(vehicle)
    if vehicle ~= 0 and DoesEntityExist(vehicle) then
        if IsToggleModOn(vehicle, 22) then
            local val = GetVehicleHeadlightsColour(vehicle)
            if val > -1 and val < 13 then
                return val
            end
            return -1
        end
    end
    return -1
end

-- ---------------------------------------------------------------------------
-- Capture (SaveVehicle's info-gathering half)
-- ---------------------------------------------------------------------------

-- GetVehicleInfo: reads everything off the vehicle into the exact
-- Newtonsoft-compatible VehicleInfo shape.
function VehicleCommon.get_vehicle_info(vehicle, existing_category)
    local mods = {}
    for _, mod in ipairs(VehicleCommon.get_all_vehicle_mods(vehicle)) do
        mods[tostring(mod.mod_type)] = mod.index
    end

    local colors = {}
    local primary, secondary = GetVehicleColours(vehicle)
    local pearlescent, wheel_color = GetVehicleExtraColours(vehicle)
    local dash_color = GetVehicleDashboardColour(vehicle)
    local trim_color = GetVehicleInteriorColour(vehicle)
    colors.primary = primary
    colors.secondary = secondary
    colors.pearlescent = pearlescent
    colors.wheels = wheel_color
    colors.dash = dash_color
    colors.trim = trim_color

    local neon_r, neon_g, neon_b = GetVehicleNeonLightsColour(vehicle)
    colors.neonR = neon_r or 255
    colors.neonG = neon_g or 255
    colors.neonB = neon_b or 255

    local smoke_r, smoke_g, smoke_b = GetVehicleTyreSmokeColor(vehicle)
    colors.tyresmokeR = smoke_r
    colors.tyresmokeG = smoke_g
    colors.tyresmokeB = smoke_b

    local custom_primary_r, custom_primary_g, custom_primary_b = -1, -1, -1
    if GetIsVehiclePrimaryColourCustom(vehicle) then
        custom_primary_r, custom_primary_g, custom_primary_b = GetVehicleCustomPrimaryColour(vehicle)
    end
    local primary_paint_finish = Entity(vehicle).state['vMenu:PrimaryPaintFinish']
    if type(primary_paint_finish) == 'number' then
        colors.PrimaryPaintFinish = primary_paint_finish
    end
    colors.customPrimaryR = custom_primary_r
    colors.customPrimaryG = custom_primary_g
    colors.customPrimaryB = custom_primary_b

    local custom_secondary_r, custom_secondary_g, custom_secondary_b = -1, -1, -1
    if GetIsVehicleSecondaryColourCustom(vehicle) then
        custom_secondary_r, custom_secondary_g, custom_secondary_b = GetVehicleCustomSecondaryColour(vehicle)
    end
    local secondary_paint_finish = Entity(vehicle).state['vMenu:SecondaryPaintFinish']
    if type(secondary_paint_finish) == 'number' then
        colors.SecondaryPaintFinish = secondary_paint_finish
    end
    colors.customSecondaryR = custom_secondary_r
    colors.customSecondaryG = custom_secondary_g
    colors.customSecondaryB = custom_secondary_b

    local has_custom_headlights, headlight_r, headlight_g, headlight_b = GetVehicleXenonLightsCustomColor(vehicle)
    if has_custom_headlights then
        colors.customheadlightR = headlight_r
        colors.customheadlightG = headlight_g
        colors.customheadlightB = headlight_b
    end

    local extras = {}
    for i = 0, 19 do
        if DoesExtraExist(vehicle, i) then
            extras[tostring(i)] = IsVehicleExtraTurnedOn(vehicle, i)
        end
    end

    local model = GetEntityModel(vehicle)
    return {
        colors = colors,
        customWheels = GetVehicleModVariation(vehicle, 23),
        extras = extras,
        livery = GetVehicleLivery(vehicle),
        model = model,
        mods = mods,
        name = GetLabelText(GetDisplayNameFromVehicleModel(model)),
        neonBack = IsVehicleNeonLightEnabled(vehicle, 3),
        neonFront = IsVehicleNeonLightEnabled(vehicle, 2),
        neonLeft = IsVehicleNeonLightEnabled(vehicle, 0),
        neonRight = IsVehicleNeonLightEnabled(vehicle, 1),
        plateText = GetVehicleNumberPlateText(vehicle),
        plateStyle = GetVehicleNumberPlateTextIndex(vehicle),
        turbo = IsToggleModOn(vehicle, 18),
        tyreSmoke = IsToggleModOn(vehicle, 20),
        version = 1,
        wheelType = GetVehicleWheelType(vehicle),
        windowTint = GetVehicleWindowTint(vehicle),
        xenonHeadlights = IsToggleModOn(vehicle, 22),
        bulletProofTires = not GetVehicleTyresCanBurst(vehicle),
        headlightColor = VehicleCommon.get_headlights_color_for_vehicle(vehicle),
        enveffScale = GetVehicleEnveffScale(vehicle),
        Category = (existing_category == nil or existing_category == '') and 'Uncategorized' or existing_category,
    }
end

-- ---------------------------------------------------------------------------
-- Application (ApplyVehicleModsDelayed)
-- ---------------------------------------------------------------------------

local function color_of(info, key)
    return (info.colors or {})[key]
end

-- Re-applies a saved VehicleInfo onto a live vehicle. Visual mods apply
-- immediately; the mods pass runs again after the delay because performance
-- mods need the mod kit to settle (upstream comment preserved).
function VehicleCommon.apply_vehicle_mods_delayed(vehicle, info, delay)
    if vehicle == 0 or not DoesEntityExist(vehicle) or info == nil then
        return
    end
    SetVehicleModKit(vehicle, 0)

    for extra, enabled in pairs(info.extras or {}) do
        local extra_id = math.tointeger(tonumber(extra))
        if extra_id ~= nil and DoesExtraExist(vehicle, extra_id) then
            SetVehicleExtra(vehicle, extra_id, not enabled)
        end
    end

    SetVehicleWheelType(vehicle, info.wheelType or 0)
    SetVehicleMod(vehicle, 23, 0, info.customWheels == true)
    if IsThisModelABike(GetEntityModel(vehicle)) then
        SetVehicleMod(vehicle, 24, 0, info.customWheels == true)
    end
    ToggleVehicleMod(vehicle, 18, info.turbo == true)
    SetVehicleTyreSmokeColor(
        vehicle,
        color_of(info, 'tyresmokeR'),
        color_of(info, 'tyresmokeG'),
        color_of(info, 'tyresmokeB')
    )
    ToggleVehicleMod(vehicle, 20, info.tyreSmoke == true)
    ToggleVehicleMod(vehicle, 22, info.xenonHeadlights == true)
    SetVehicleLivery(vehicle, info.livery or -1)

    -- Primary color (+ optional custom RGB + paint finish).
    local custom_primary_r = color_of(info, 'customPrimaryR')
    local use_custom_primary = custom_primary_r ~= nil
        and color_of(info, 'customPrimaryG') ~= nil
        and color_of(info, 'customPrimaryB') ~= nil

    local _, current_secondary = GetVehicleColours(vehicle)
    SetVehicleColours(vehicle, color_of(info, 'primary') or 0, current_secondary)

    if
        use_custom_primary
        and custom_primary_r > 0
        and color_of(info, 'customPrimaryG') > 0
        and color_of(info, 'customPrimaryB') > 0
    then
        SetVehicleCustomPrimaryColour(
            vehicle,
            custom_primary_r,
            color_of(info, 'customPrimaryG'),
            color_of(info, 'customPrimaryB')
        )
    end
    if color_of(info, 'PrimaryPaintFinish') ~= nil then
        local pearl_reset, wheel_reset = GetVehicleExtraColours(vehicle)
        SetVehicleModColor_1(vehicle, color_of(info, 'PrimaryPaintFinish'), 0, 0)
        SetVehicleExtraColours(vehicle, pearl_reset, wheel_reset)
    end

    -- Secondary color (+ optional custom RGB + paint finish).
    local custom_secondary_r = color_of(info, 'customSecondaryR')
    local use_custom_secondary = custom_secondary_r ~= nil
        and color_of(info, 'customSecondaryG') ~= nil
        and color_of(info, 'customSecondaryB') ~= nil

    local current_primary = GetVehicleColours(vehicle)
    SetVehicleColours(vehicle, current_primary, color_of(info, 'secondary') or 0)

    if
        use_custom_secondary
        and custom_secondary_r > 0
        and color_of(info, 'customSecondaryG') > 0
        and color_of(info, 'customSecondaryB') > 0
    then
        -- Upstream passes customSecondaryR for the green channel too; quirk
        -- preserved so C# saves render identically here.
        SetVehicleCustomSecondaryColour(
            vehicle,
            custom_secondary_r,
            custom_secondary_r,
            color_of(info, 'customSecondaryB')
        )
    end
    if color_of(info, 'SecondaryPaintFinish') ~= nil then
        local pearl_reset, wheel_reset = GetVehicleExtraColours(vehicle)
        SetVehicleModColor_2(vehicle, color_of(info, 'SecondaryPaintFinish'), 0)
        SetVehicleExtraColours(vehicle, pearl_reset, wheel_reset)
    end

    SetVehicleInteriorColour(vehicle, color_of(info, 'trim') or 0)
    SetVehicleDashboardColour(vehicle, color_of(info, 'dash') or 0)
    SetVehicleExtraColours(vehicle, color_of(info, 'pearlescent') or 0, color_of(info, 'wheels') or 0)

    SetVehicleNumberPlateText(vehicle, info.plateText or '')
    SetVehicleNumberPlateTextIndex(vehicle, info.plateStyle or 0)
    SetVehicleWindowTint(vehicle, info.windowTint or 0)
    SetVehicleTyresCanBurst(vehicle, info.bulletProofTires ~= true)
    SetVehicleEnveffScale(vehicle, info.enveffScale or 0.0)

    VehicleCommon.set_headlights_color_for_vehicle(vehicle, info.headlightColor or -1)
    local headlight_r = color_of(info, 'customheadlightR')
    if
        headlight_r ~= nil
        and color_of(info, 'customheadlightG') ~= nil
        and color_of(info, 'customheadlightB') ~= nil
    then
        SetVehicleXenonLightsCustomColor(
            vehicle,
            headlight_r,
            color_of(info, 'customheadlightG'),
            color_of(info, 'customheadlightB')
        )
    end

    SetVehicleNeonLightsColour(
        vehicle,
        color_of(info, 'neonR') or 255,
        color_of(info, 'neonG') or 255,
        color_of(info, 'neonB') or 255
    )
    SetVehicleNeonLightEnabled(vehicle, 0, info.neonLeft == true)
    SetVehicleNeonLightEnabled(vehicle, 1, info.neonRight == true)
    SetVehicleNeonLightEnabled(vehicle, 2, info.neonFront == true)
    SetVehicleNeonLightEnabled(vehicle, 3, info.neonBack == true)

    local function do_mods()
        for mod_type, mod_index in pairs(info.mods or {}) do
            if DoesEntityExist(vehicle) then
                SetVehicleMod(vehicle, math.tointeger(tonumber(mod_type)), mod_index, info.customWheels == true)
            end
        end
    end

    do_mods()
    -- Performance mods need a delay after the mod kit; run the pass twice.
    Wait(delay or 500)
    do_mods()
end

-- ---------------------------------------------------------------------------
-- Save / list / spawn / delete
-- ---------------------------------------------------------------------------

-- GetSavedVehicles: { [full kvp name incl. veh_] = VehicleInfo }.
function VehicleCommon.get_saved_vehicles()
    local vehicles = {}
    local handle = StartFindKvp('veh_')
    while true do
        local key = FindKvp(handle)
        if key == nil or key == '' or key == 'NULL' then
            break
        end
        vehicles[key] = Storage.get_saved_vehicle_info(key)
    end
    EndFindKvp(handle)
    return vehicles
end

-- SaveVehicle: captures the current vehicle. With no name it asks the user
-- (refusing duplicates); with a name it updates that existing save in place.
function VehicleCommon.save_vehicle(update_existing_saved_vehicle_name, existing_category)
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then
        Notify.error(Notification.error_message('NoVehicle'))
        return
    end
    local vehicle = Common.get_vehicle()
    if
        vehicle == 0
        or not DoesEntityExist(vehicle)
        or IsEntityDead(vehicle)
        or not IsVehicleDriveable(vehicle, false)
    then
        Notify.error(Notification.error_message('NoVehicle', 'to save it'))
        return
    end

    local info = VehicleCommon.get_vehicle_info(vehicle, existing_category)

    if update_existing_saved_vehicle_name == nil then
        local save_name = Common.get_user_input('Enter a save name', nil, 30)
        if save_name ~= nil and save_name ~= '' then
            if Storage.save_vehicle_info('veh_' .. save_name, info, false) then
                Notify.success(('Vehicle %s saved.'):format(save_name))
            else
                Notify.error(Notification.error_message('SaveNameAlreadyExists', '(' .. save_name .. ')'))
            end
        else
            Notify.error(Notification.error_message('InvalidSaveName'))
        end
    else
        Storage.save_vehicle_info('veh_' .. update_existing_saved_vehicle_name, info, true)
    end

    local saved_vehicles_menu = State.menus.saved_vehicles
    if saved_vehicles_menu ~= nil and saved_vehicles_menu.update_menu_available_categories ~= nil then
        saved_vehicles_menu.update_menu_available_categories()
    end
end

-- Spawns a saved vehicle: the shared spawn path plus the mods pass.
function VehicleCommon.spawn_saved_vehicle(info, save_name)
    if info == nil or info.model == nil then
        Notify.error(Notification.error_message('CouldNotLoadSave', save_name))
        return 0
    end
    return Common.spawn_vehicle(info.model, {
        spawn_inside = State.menus.vehicle_spawner ~= nil and State.menus.vehicle_spawner.SpawnInVehicle or false,
        replace_previous = State.menus.vehicle_spawner ~= nil and State.menus.vehicle_spawner.ReplaceVehicle or false,
        vehicle_info = info,
        save_name = save_name,
        apply_mods = function(vehicle, vehicle_info)
            VehicleCommon.apply_vehicle_mods_delayed(vehicle, vehicle_info, 500)
        end,
    })
end

-- PressKeyFob: plays the key-fob prop + click animation when the player is
-- on foot (used by every remote personal-vehicle action).
function VehicleCommon.press_key_fob(vehicle)
    local ped = PlayerPedId()
    if IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) then
        return
    end

    local key_fob_hash = GetHashKey('p_car_keys_01')
    RequestModel(key_fob_hash)
    while not HasModelLoaded(key_fob_hash) do
        Wait(0)
    end

    local key_fob = CreateObject(key_fob_hash, 0.0, 0.0, 0.0, true, true, true)
    AttachEntityToEntity(
        key_fob,
        ped,
        GetPedBoneIndex(ped, 57005),
        0.09,
        0.03,
        -0.02,
        -76.0,
        13.0,
        28.0,
        false,
        true,
        true,
        true,
        0,
        true
    )
    SetModelAsNoLongerNeeded(key_fob_hash)

    ClearPedTasks(ped)
    SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
    ClearPedTasks(ped)
    TaskTurnPedToFaceEntity(ped, vehicle, 500)

    local anim_dict = 'anim@mp_player_intmenu@key_fob@'
    RequestAnimDict(anim_dict)
    while not HasAnimDictLoaded(anim_dict) do
        Wait(0)
    end
    -- AnimationFlags.UpperBodyOnly = 48 (upper body + secondary task)
    TaskPlayAnim(ped, anim_dict, 'fob_click', 3.0, 3.0, 1000, 48, 0.0, false, false, false)
    PlaySoundFromEntity(-1, 'Remote_Control_Fob', ped, 'PI_Menu_Sounds', true, 0)

    Wait(1250)
    DetachEntity(key_fob, false, false)
    DeleteObject(key_fob)
    RemoveAnimDict(anim_dict)
end

-- LockOrUnlockDoors: two short horn bursts, then (un)lock for all players.
function VehicleCommon.lock_or_unlock_doors(vehicle, lock_doors)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return
    end
    for _ = 1, 2 do
        local timer = GetGameTimer()
        while GetGameTimer() - timer < 50 do
            SoundVehicleHornThisFrame(vehicle)
            Wait(0)
        end
        Wait(50)
    end
    if lock_doors then
        Notification.Subtitle.custom('Vehicle doors are now locked.')
        SetVehicleDoorsLockedForAllPlayers(vehicle, true)
    else
        Notification.Subtitle.custom('Vehicle doors are now unlocked.')
        SetVehicleDoorsLockedForAllPlayers(vehicle, false)
    end
end

-- ToggleVehicleAlarm: random 8-45s alarm, or silences a sounding one.
function VehicleCommon.toggle_vehicle_alarm(vehicle)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return
    end
    if IsVehicleAlarmActivated(vehicle) then
        SetVehicleAlarmTimeLeft(vehicle, 0)
        SetVehicleAlarm(vehicle, false)
    else
        SetVehicleAlarm(vehicle, true)
        SetVehicleAlarmTimeLeft(vehicle, math.random(8000, 45000))
        StartVehicleAlarm(vehicle)
    end
end

-- SoundHorn: one second of horn.
function VehicleCommon.sound_horn(vehicle)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return
    end
    local timer = GetGameTimer()
    while GetGameTimer() - timer < 1000 do
        SoundVehicleHornThisFrame(vehicle)
        Wait(0)
    end
end

-- DeleteVehicle: deletes the current vehicle (as driver), or raycasts for
-- one in front of the player.
function VehicleCommon.delete_vehicle()
    local ped = PlayerPedId()
    if IsEntityDead(ped) then
        return
    end

    if IsPedInAnyVehicle(ped, false) then
        local vehicle = Common.get_vehicle()
        if vehicle ~= 0 and DoesEntityExist(vehicle) and GetPedInVehicleSeat(vehicle, -1) == ped then
            SetVehicleHasBeenOwnedByPlayer(vehicle, false)
            SetEntityAsMissionEntity(vehicle, false, false)
            DeleteVehicle(vehicle)
        else
            Notify.error(
                'This vehicle does not exist (somehow) or you need to be the driver of this vehicle to delete it!'
            )
        end
        return
    end

    local distance = Config.get_float('vmenu_delete_vehicle_distance', 5.0)
    local max_delete_tries = 5
    local max_hit_tries = 5

    local pos = GetEntityCoords(ped)
    local forward = GetOffsetFromEntityInWorldCoords(ped, 0.0, distance, 0.0)
    local ray = StartShapeTestCapsule(pos.x, pos.y, pos.z, forward.x, forward.y, forward.z, 5.0, 10, ped, 7)

    local hit, entity = false, 0
    for _ = 1, max_hit_tries do
        local _, ray_hit, _, _, ray_entity = GetShapeTestResult(ray)
        hit = ray_hit
        entity = ray_entity
        if hit then
            break
        end
    end

    if not hit or not DoesEntityExist(entity) or not IsEntityAVehicle(entity) then
        Notify.error('No vehicle found in front of you to delete!')
        return
    end

    local tries = 0
    while tries <= max_delete_tries and DoesEntityExist(entity) do
        NetworkRequestControlOfEntity(entity)
        SetVehicleHasBeenOwnedByPlayer(entity, false)
        SetEntityAsMissionEntity(entity, false, false)
        DeleteVehicle(entity)
        tries = tries + 1
    end

    if DoesEntityExist(entity) then
        Notify.error('Failed to delete the vehicle in front of you. Try again or ask an admin for help.')
    else
        Notify.success('Vehicle deleted successfully.')
    end
end

return VehicleCommon
