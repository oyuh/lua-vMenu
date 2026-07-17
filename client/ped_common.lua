-- The ped half of vMenu/CommonFunctions.cs: changing the player skin (with
-- weapon/health/vehicle-seat preservation and the PedInfo restore path),
-- saving/loading peds under the ped_ KVP prefix, and walking styles.
--
-- PedInfo JSON shape (docs/contracts/kvp-saves.md): version, model (uint),
-- isMpPed, plus 21-entry int dicts props/propTextures/drawableVariations/
-- drawableVariationTextures — string-keyed after a JSON round-trip.

local Permissions = require('shared.permissions')
local Common = require('client.common')
local Notification = require('client.notify')
local Storage = require('client.storage')
local Weapons = require('client.weapons')
local State = require('client.state')

local Notify = Notification.Notify

local PedCommon = {}

local TEMP_LOADOUT_NAME = 'vmenu_temp_weapons_loadout_before_respawn'
local TEMP_PED_NAME = 'vMenu_tmp_saved_ped'

-- C# Dictionary<int,int> arrives string-keyed from JSON; tolerate both.
local function dict_get(dict, index)
    if dict == nil then
        return nil
    end
    local value = dict[tostring(index)]
    if value == nil then
        value = dict[index]
    end
    return value
end

-- Ped.SeatIndex: the seat the ped currently occupies, or nil.
local function get_ped_seat_index(ped, vehicle)
    local max_seats = GetVehicleModelNumberOfSeats(GetEntityModel(vehicle))
    for seat = -1, max_seats - 2 do
        if GetPedInVehicleSeat(vehicle, seat) == ped then
            return seat
        end
    end
    return nil
end

-- SetPlayerSkin(modelHash, pedCustomizationOptions, keepWeapons).
function PedCommon.set_player_skin(model, ped_info, keep_weapons)
    if type(model) == 'string' then
        model = GetHashKey(model)
    end
    ped_info = ped_info or { version = -1 }
    if keep_weapons == nil then
        keep_weapons = true
    end

    if not IsModelInCdimage(model) then
        Notify.error(Notification.error_message('InvalidModel'))
        return
    end

    -- Ped whitelist: restricted models need the PW<name> supplementary ace.
    for name, hash in pairs(State.whitelisted_peds) do
        if hash == model then
            if not Permissions.is_supplementary_allowed('PW' .. tostring(name):lower()) then
                Notify.alert('You are not allowed to spawn this ped, because it is restricted by the server owner.')
                return
            end
            break
        end
    end

    if keep_weapons then
        Weapons.save_weapon_loadout(TEMP_LOADOUT_NAME)
    end

    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(0)
    end

    local ped = PlayerPedId()
    if GetEntityModel(ped) ~= model then
        -- check if the ped is in a vehicle
        local was_in_vehicle = IsPedInAnyVehicle(ped, false)
        local vehicle = was_in_vehicle and GetVehiclePedIsIn(ped, false) or 0
        local seat = was_in_vehicle and get_ped_seat_index(ped, vehicle) or nil

        local max_health = GetPedMaxHealth(ped)
        local max_armour = GetPlayerMaxArmour(PlayerId())
        local health = GetEntityHealth(ped)
        local armour = GetPedArmour(ped)

        SetPlayerModel(PlayerId(), model)
        ped = PlayerPedId()

        SetPlayerMaxArmour(PlayerId(), max_armour)
        SetPedMaxHealth(ped, max_health)
        SetEntityHealth(ped, health)
        SetPedArmour(ped, armour)

        -- warp back into the vehicle if the player was in one
        if was_in_vehicle and vehicle ~= 0 and seat ~= nil then
            FreezeEntityPosition(ped, true)
            local tmp_timer = GetGameTimer()
            while GetVehiclePedIsIn(ped, false) ~= vehicle do
                if GetGameTimer() - tmp_timer > 1000 then
                    break
                end
                ClearPedTasks(ped)
                Wait(0)
                TaskWarpPedIntoVehicle(ped, vehicle, seat)
            end
            FreezeEntityPosition(ped, false)
        end
    end

    -- Reset some stuff.
    local player_ped = PlayerPedId()
    SetPedDefaultComponentVariation(player_ped)
    ClearAllPedProps(player_ped)
    ClearPedDecorations(player_ped)
    ClearPedFacialDecorations(player_ped)

    if ped_info.version == 1 then
        for drawable = 0, 20 do
            SetPedComponentVariation(
                player_ped,
                drawable,
                dict_get(ped_info.drawableVariations, drawable) or 0,
                dict_get(ped_info.drawableVariationTextures, drawable) or 0,
                1
            )
        end
        for i = 0, 20 do
            local prop = dict_get(ped_info.props, i) or -1
            local prop_texture = dict_get(ped_info.propTextures, i) or -1
            if prop == -1 or prop_texture == -1 then
                ClearPedProp(player_ped, i)
            else
                SetPedPropIndex(player_ped, i, prop, prop_texture, true)
            end
        end
    elseif ped_info.version == -1 then --luacheck: ignore 542
        -- do nothing
    else
        Notify.error('This is an unsupported saved ped version. Cannot restore appearance. :(')
    end

    if keep_weapons then
        Weapons.spawn_weapon_loadout(TEMP_LOADOUT_NAME, false, true, false)
    end

    if model == GetHashKey('mp_f_freemode_01') or model == GetHashKey('mp_m_freemode_01') then
        if ped_info.version == -1 then
            SetPedHeadBlendData(player_ped, 0, 0, 0, 0, 0, 0, 0.5, 0.5, 0.0, false)
            while not HasPedHeadBlendFinished(player_ped) do
                Wait(0)
            end
        end
    end
    SetModelAsNoLongerNeeded(model)
end

-- SpawnPedByName: user-input model name.
function PedCommon.spawn_ped_by_name()
    local input = Common.get_user_input('Enter Ped Model Name', nil, 30)
    if input ~= nil and input ~= '' then
        PedCommon.set_player_skin(input, { version = -1 })
    else
        Notify.error(Notification.error_message('InvalidModel'))
    end
end

-- SavePed(forceName, overrideExistingPed) → bool.
function PedCommon.save_ped(force_name, override_existing_ped)
    local name = force_name
    if name == nil or name == '' then
        name = Common.get_user_input('Enter a ped save name', nil, 30)
    end

    if name == nil or name == '' then
        Notify.error(Notification.error_message('InvalidSaveName'))
        return false
    end

    local ped = PlayerPedId()
    local model = GetEntityModel(ped)

    local drawables = {}
    local drawable_textures = {}
    for i = 0, 20 do
        drawables[tostring(i)] = GetPedDrawableVariation(ped, i)
        drawable_textures[tostring(i)] = GetPedTextureVariation(ped, i)
    end

    local props = {}
    local prop_textures = {}
    for i = 0, 20 do
        props[tostring(i)] = GetPedPropIndex(ped, i)
        prop_textures[tostring(i)] = GetPedPropTextureIndex(ped, i)
    end

    local is_mp_ped = model == GetHashKey('mp_f_freemode_01') or model == GetHashKey('mp_m_freemode_01')
    if is_mp_ped then
        Notify.alert(
            'Note, you should probably use the MP Character creator if you want more advanced features. Saving '
                .. 'Multiplayer characters with this function does NOT save a lot of the online peds customization.'
        )
    end

    local data = {
        version = 1,
        model = model,
        isMpPed = is_mp_ped,
        drawableVariations = drawables,
        drawableVariationTextures = drawable_textures,
        props = props,
        propTextures = prop_textures,
    }

    if name == TEMP_PED_NAME then
        return Storage.save_ped_info(name, data, true)
    end
    return Storage.save_ped_info('ped_' .. name, data, override_existing_ped == true)
end

-- LoadSavedPed(savedName, restoreWeapons): saved_name has no ped_ prefix
-- except for the special temp save.
function PedCommon.load_saved_ped(saved_name, restore_weapons)
    if saved_name ~= TEMP_PED_NAME then
        local ped_info = Storage.get_saved_ped_info('ped_' .. saved_name)
        PedCommon.set_player_skin(ped_info.model, ped_info, restore_weapons)
    else
        local ped_info = Storage.get_saved_ped_info(saved_name)
        PedCommon.set_player_skin(ped_info.model, ped_info, restore_weapons)
        DeleteResourceKvp(TEMP_PED_NAME)
    end
end

-- IsTempPedSaved: was a ped saved before the player died?
function PedCommon.is_temp_ped_saved()
    local saved = GetResourceKvpString(TEMP_PED_NAME)
    return saved ~= nil and saved ~= ''
end

-- SetWalkingStyle: only works on the freemode models.
function PedCommon.set_walking_style(walking_style)
    local ped = PlayerPedId()
    if IsPedModel(ped, GetHashKey('mp_f_freemode_01')) or IsPedModel(ped, GetHashKey('mp_m_freemode_01')) then
        local is_ped_male = IsPedModel(ped, GetHashKey('mp_m_freemode_01'))
        ClearPedAlternateMovementAnim(ped, 0, 1.0)
        ClearPedAlternateMovementAnim(ped, 1, 1.0)
        ClearPedAlternateMovementAnim(ped, 2, 1.0)
        ClearPedAlternateWalkAnim(ped, 1.0)

        local anim_dict = nil
        if walking_style == 'Injured' then
            anim_dict = is_ped_male and 'move_m@injured' or 'move_f@injured'
        elseif walking_style == 'Tough Guy' then
            anim_dict = is_ped_male and 'move_m@tough_guy@' or 'move_f@tough_guy@'
        elseif walking_style == 'Femme' then
            anim_dict = is_ped_male and 'move_m@femme@' or 'move_f@femme@'
        elseif walking_style == 'Gangster' then
            anim_dict = is_ped_male and 'move_m@gangster@a' or 'move_f@gangster@ng'
        elseif walking_style == 'Posh' then
            anim_dict = is_ped_male and 'move_m@posh@' or 'move_f@posh@'
        elseif walking_style == 'Sexy' then
            anim_dict = not is_ped_male and 'move_f@sexy@a' or nil
        elseif walking_style == 'Business' then
            anim_dict = not is_ped_male and 'move_f@business@a' or nil
        elseif walking_style == 'Drunk' then
            anim_dict = is_ped_male and 'move_m@drunk@a' or 'move_f@drunk@a'
        elseif walking_style == 'Hipster' then
            anim_dict = is_ped_male and 'move_m@hipster@a' or nil
        end

        if anim_dict ~= nil then
            if not HasAnimDictLoaded(anim_dict) then
                RequestAnimDict(anim_dict)
                while not HasAnimDictLoaded(anim_dict) do
                    Wait(0)
                end
            end
            SetPedAlternateMovementAnim(ped, 0, anim_dict, 'idle', 1.0, true)
            SetPedAlternateMovementAnim(ped, 1, anim_dict, 'walk', 1.0, true)
            SetPedAlternateMovementAnim(ped, 2, anim_dict, 'run', 1.0, true)
        elseif walking_style ~= 'Normal' then
            if is_ped_male then
                Notify.error(Notification.error_message('WalkingStyleNotForMale'))
            else
                Notify.error(Notification.error_message('WalkingStyleNotForFemale'))
            end
        end
    else
        Notify.error('This feature only supports the multiplayer freemode male/female ped models.')
    end
end

return PedCommon
