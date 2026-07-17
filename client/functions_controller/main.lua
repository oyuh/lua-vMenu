-- Port of vMenu/FunctionsController.cs (part 1 of 3): the tick registration
-- (vMenu:SetupTickFunctions) and the player/vehicle/weapon feature ticks.
-- Each C# Tick handler becomes a CreateThread loop; the permission and
-- convar gates match SetupTickFunctions exactly. HUD/world ticks live in
-- hud.lua, the MP-creator camera in creator_camera.lua.

local Config = require('shared.config')
local Permissions = require('shared.permissions')
local Common = require('client.common')
local PedCommon = require('client.ped_common')
local VehicleCommon = require('client.vehicle_common')
local Weapons = require('client.weapons')
local Notification = require('client.notify')
local State = require('client.state')
local PedModels = require('client.data.ped_models')
local Hud = require('client.functions_controller.hud')
local CreatorCamera = require('client.functions_controller.creator_camera')
local Controller = require('menu.controller')

local Notify = Notification.Notify

local FunctionsController = {}

-- Shared tick state.
local last_vehicle = 0
local switched_vehicle = false

local CLOTHING_ANIMATION_DECOR = 'clothing_animation_type'
local clothing_animation_reverse = false
local clothing_opacity = 1.0

-- Registers fn as a per-frame tick (C# Tick +=). fn may Wait() internally;
-- the loop always yields at least once per iteration.
local function add_tick(fn)
    CreateThread(function()
        while true do
            fn()
            Wait(0)
        end
    end)
end
FunctionsController.add_tick = add_tick

local function player_options_menu()
    return State.menus.player_options
end
local function vehicle_options_menu()
    return State.menus.vehicle_options
end
local function misc_menu()
    return State.menus.misc_settings
end

-- ---------------------------------------------------------------------------
-- General tasks
-- ---------------------------------------------------------------------------

local function general_tasks()
    if IsPedInAnyVehicle(PlayerPedId(), false) then
        local tmp_vehicle = Common.get_vehicle()
        if tmp_vehicle ~= 0 and DoesEntityExist(tmp_vehicle) and tmp_vehicle ~= last_vehicle then
            last_vehicle = tmp_vehicle
            switched_vehicle = true
        end
    end
    Wait(1)
end

local function player_head_props_tick()
    local ped = PlayerPedId()
    if DoesEntityExist(ped) then
        Wait(100)
        if PlayerPedId() ~= ped then
            SetPedCanLosePropsOnDamage(PlayerPedId(), false, 0)
        end
    else
        Wait(1000)
    end
end

-- Controller menu-toggle (hold the interaction menu button on gamepad).
local INTERACTION_MENU = 244 -- Control.InteractionMenu
local function controller_tick()
    if
        not IsPauseMenuActive()
        and not IsPauseMenuRestarting()
        and IsScreenFadedIn()
        and not IsPlayerSwitchInProgress()
        and not IsEntityDead(PlayerPedId())
        and Controller.AreMenuButtonsEnabled ~= nil -- registration sanity
    then
        if not IsInputDisabled(2) then -- gamepad
            local tmp_timer = GetGameTimer()
            while
                (IsControlPressed(0, INTERACTION_MENU) or IsDisabledControlPressed(0, INTERACTION_MENU))
                and not IsPauseMenuActive()
                and IsScreenFadedIn()
                and not IsEntityDead(PlayerPedId())
                and not IsPlayerSwitchInProgress()
                and not Controller.DontOpenAnyMenu
            do
                if GetGameTimer() - tmp_timer > 400 then
                    if State.menus.main ~= nil then
                        State.menus.main:OpenMenu()
                    end
                    break
                end
                Wait(0)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Player options
-- ---------------------------------------------------------------------------

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
FunctionsController.is_mp_char_editor_open = is_mp_char_editor_open

local function player_options_tick()
    local player_options = player_options_menu()
    if player_options == nil then
        Wait(100)
        return
    end
    local ped = PlayerPedId()
    local godmode_allowed = Permissions.is_allowed('POGod')
    local no_ragdoll_allowed = Permissions.is_allowed('PONoRagdoll')

    -- god mode is suspended while the MP character creator is open
    if State.menus.mp_ped_customization ~= nil then
        if not is_mp_char_editor_open() then
            SetEntityInvincible(ped, player_options.PlayerGodMode and godmode_allowed)
        end
    end

    if
        Config.get_bool('vmenu_handle_invisibility')
        and player_options.PlayerInvisible
        and Permissions.is_allowed('POInvisible')
    then
        SetEntityVisible(ped, false, false)
    end

    if player_options.PlayerSuperJump and Permissions.is_allowed('POSuperjump') then
        SetSuperJumpThisFrame(PlayerId())
    end

    SetPedCanRagdoll(ped, (not player_options.PlayerNoRagdoll and no_ragdoll_allowed) or not no_ragdoll_allowed)

    if
        player_options.PlayerNeverWanted
        and GetPlayerWantedLevel(PlayerId()) > 0
        and Permissions.is_allowed('PONeverWanted')
    then
        ClearPlayerWantedLevel(PlayerId())
        if GetMaxWantedLevel() > 0 then
            SetMaxWantedLevel(0)
        end
    end

    if Common.drive_to_wp_task_active and not IsWaypointActive() then
        ClearPedTasks(ped)
        Notify.custom('Destination reached, the car will now stop driving!')
        Common.drive_to_wp_task_active = false
    end
end

-- Shared slow checks: knock-off/drag-out/shot-in-vehicle protection.
local function player_and_vehicle_checks()
    local player_options = player_options_menu()
    local vehicle_options = vehicle_options_menu()

    local god = Permissions.is_allowed('POGod') and player_options ~= nil and player_options.PlayerGodMode
    Wait(100)
    local veh_god = Permissions.is_allowed('VOGod') and vehicle_options ~= nil and vehicle_options.VehicleGodMode
    Wait(100)
    local ignored = Permissions.is_allowed('POIgnored') and player_options ~= nil and player_options.PlayerIsIgnored
    Wait(100)
    local stay_in_veh = Permissions.is_allowed('POStayInVehicle')
        and player_options ~= nil
        and player_options.PlayerStayInVehicle
    Wait(100)
    local bike_seatbelt = Permissions.is_allowed('VOBikeSeatbelt')
        and vehicle_options ~= nil
        and vehicle_options.VehicleBikeSeatbelt
    Wait(100)
    local no_ragdoll = Permissions.is_allowed('PONoRagdoll')
        and player_options ~= nil
        and player_options.PlayerNoRagdoll
    Wait(100)

    local cant_be_knocked_off = god or veh_god or bike_seatbelt or no_ragdoll
    local cant_be_dragged_out = god or veh_god or ignored or stay_in_veh
    local cant_be_shot_in_vehicle = god or veh_god

    local ped = PlayerPedId()
    SetPedCanBeDraggedOut(ped, not cant_be_dragged_out)
    SetPedCanBeShotInVehicle(ped, not cant_be_shot_in_vehicle)
    SetPedCanBeKnockedOffVehicle(ped, cant_be_knocked_off and 1 or 0)
    Wait(1000)
end

-- ---------------------------------------------------------------------------
-- Vehicle options
-- ---------------------------------------------------------------------------

local function vehicle_options_tick()
    local vo = vehicle_options_menu()
    if vo == nil then
        Wait(100)
        return
    end
    local ped = PlayerPedId()

    if IsPedInAnyVehicle(ped, true) then
        local veh = Common.get_vehicle()
        if veh ~= 0 and DoesEntityExist(veh) then
            -- god mode
            local god = vo.VehicleGodMode and Permissions.is_allowed('VOGod')
            local invincible_god = vo.VehicleGodInvincible and god
            local visual_god = vo.VehicleGodVisual and god
            local engine_god = vo.VehicleGodEngine and god
            local strong_wheels_god = vo.VehicleGodStrongWheels and god
            local auto_repair_god = vo.VehicleGodAutoRepair and god
            local ramp_god = vo.VehicleGodRamp and god

            SetRampVehicleReceivesRampDamage(veh, not ramp_god)

            if visual_god and IsVehicleDamaged(veh) then
                RemoveDecalsFromVehicle(veh)
            end
            if auto_repair_god and IsVehicleDamaged(veh) then
                SetVehicleFixed(veh)
            end

            SetVehicleCanBeVisiblyDamaged(veh, not visual_god)

            SetVehicleEngineCanDegrade(veh, not engine_god)
            if engine_god and GetVehicleEngineHealth(veh) < 1000.0 then
                SetVehicleEngineHealth(veh, 1000.0)
            end

            SetVehicleWheelsCanBreak(veh, not strong_wheels_god)
            SetVehicleHasStrongAxles(veh, strong_wheels_god)

            -- Entity.Is*Proof flags + invincibility
            SetEntityProofs(
                veh,
                invincible_god,
                invincible_god,
                invincible_god,
                invincible_god,
                invincible_god,
                false,
                false,
                false
            )
            SetEntityInvincible(veh, invincible_god)
            for door = 0, 7 do
                if GetIsDoorValid(veh, door) then
                    SetVehicleDoorBreakable(veh, door, not invincible_god)
                end
            end

            if vo.VehicleFrozen and Permissions.is_allowed('VOFreeze') then
                FreezeEntityPosition(veh, true)
            end

            if vo.VehicleNeverDirty and GetVehicleDirtLevel(veh) > 0.0 and Permissions.is_allowed('VOKeepClean') then
                SetVehicleDirtLevel(veh, 0.0)
            end

            if vo.VehicleTorqueMultiplier and Permissions.is_allowed('VOTorqueMultiplier') then
                SetVehicleEngineTorqueMultiplier(veh, vo.VehicleTorqueMultiplierAmount)
            end

            if switched_vehicle then
                switched_vehicle = false

                -- sync the license plate type list to the new vehicle
                if Permissions.is_allowed('VOChangePlate') then
                    local plate_label = GetLabelText('CMOD_PLA_0')
                    for _, item in ipairs(vo.menu:GetMenuItems()) do
                        if item.ListItems ~= nil then
                            local matches = false
                            for _, text in ipairs(item.ListItems) do
                                if text == plate_label then
                                    matches = true
                                    break
                                end
                            end
                            if matches then
                                local style_to_index = {
                                    [0] = 0,
                                    [1] = 4,
                                    [2] = 3,
                                    [3] = 1,
                                    [4] = 2,
                                    [5] = 5,
                                    [6] = 6,
                                    [7] = 7,
                                    [8] = 8,
                                    [9] = 9,
                                    [10] = 10,
                                    [11] = 11,
                                    [12] = 12,
                                }
                                local list_index = style_to_index[GetVehicleNumberPlateTextIndex(veh)]
                                if list_index ~= nil then
                                    item.ListIndex = list_index
                                end
                                break
                            end
                        end
                    end
                end

                if vo.VehiclePowerMultiplier and Permissions.is_allowed('VOPowerMultiplier') then
                    SetVehicleEnginePowerMultiplier(veh, vo.VehiclePowerMultiplierAmount)
                else
                    SetVehicleEnginePowerMultiplier(veh, 1.0)
                end

                if not Config.get_bool('vmenu_use_els_compatibility_mode') then
                    DisableVehicleImpactExplosionActivation(
                        veh,
                        vo.VehicleNoSiren and Permissions.is_allowed('VONoSiren')
                    )
                end

                local model = GetEntityModel(veh)
                if IsThisModelAPlane(model) then
                    if vo.DisablePlaneTurbulence and Permissions.is_allowed('VODisableTurbulence') then
                        SetPlaneTurbulenceMultiplier(veh, 0.0)
                    else
                        SetPlaneTurbulenceMultiplier(veh, 1.0)
                    end
                end
                if IsThisModelAHeli(model) then
                    if vo.DisableHelicopterTurbulence and Permissions.is_allowed('VODisableTurbulence') then
                        SetHeliTurbulenceScalar(veh, 0.0)
                    else
                        SetHeliTurbulenceScalar(veh, 1.0)
                    end
                end
                if IsThisModelABoat(model) then
                    if vo.AnchorBoat and Permissions.is_allowed('VOAnchorBoat') and CanAnchorBoatHere(veh) then
                        SetBoatAnchor(veh, true)
                        SetBoatFrozenWhenAnchored(veh, true)
                        SetForcedBoatLocationWhenAnchored(veh, true)
                    else
                        SetBoatAnchor(veh, false)
                        SetBoatFrozenWhenAnchored(veh, false)
                        SetForcedBoatLocationWhenAnchored(veh, false)
                    end
                end
            end

            -- no bike helmet
            if vo.VehicleNoBikeHelemet and Permissions.is_allowed('VONoHelmet') then
                SetPedHelmet(ped, false)
            else
                SetPedHelmet(ped, true)
            end
            if IsPedWearingHelmet(ped) and vo.VehicleNoBikeHelemet and Permissions.is_allowed('VONoHelmet') then
                RemovePedHelmet(ped, true)
            end

            -- infinite fuel (FRFuel decorator)
            if
                vo.VehicleInfiniteFuel
                and DecorIsRegisteredAsType('_Fuel_Level', 1)
                and Permissions.is_allowed('VOInfiniteFuel')
            then
                local max_fuel_level = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fPetrolTankVolume')
                local current_fuel_level = GetVehicleFuelLevel(veh)
                if max_fuel_level > 5.0 and current_fuel_level < (max_fuel_level * 0.95) then
                    DecorSetFloat(veh, '_Fuel_Level', max_fuel_level)
                end
            end
            Wait(0)
        end
    else
        -- restore visibility of the last vehicle when we're not in it
        local last = Common.get_vehicle(true)
        if last ~= 0 and DoesEntityExist(last) then
            if not IsEntityVisible(last) then
                SetEntityVisible(last, true, false)
            end
        end

        -- close vehicle-only submenus when leaving the vehicle
        for _, m in ipairs({
            vo.VehicleColorsMenu,
            vo.VehicleComponentsMenu,
            vo.VehicleDoorsMenu,
            vo.VehicleLiveriesMenu,
            vo.VehicleModMenu,
            vo.VehicleUnderglowMenu,
            vo.VehicleWindowsMenu,
        }) do
            if m ~= nil and m.Visible then
                m:GoBack()
                Notify.error(Notification.error_message('NoVehicle', 'to access this menu'))
            end
        end
    end

    Wait(1)

    -- engine always on
    if
        vo.VehicleEngineAlwaysOn
        and not IsPedInAnyVehicle(PlayerPedId(), false)
        and Permissions.is_allowed('VOEngineAlwaysOn')
    then
        local last = Common.get_vehicle(true)
        if last ~= 0 and DoesEntityExist(last) then
            Wait(100)
            last = Common.get_vehicle(true)
            if last ~= 0 then
                SetVehicleEngineOn(last, true, true, true)
            end
        end
    end
end

local VEHICLE_HORN = 86 -- Control.VehicleHorn

local function vehicle_highbeam_flash_tick()
    local vo = vehicle_options_menu()
    if vo ~= nil and vo.FlashHighbeamsOnHonk and IsPedInAnyVehicle(PlayerPedId(), true) then
        local veh = Common.get_vehicle()
        if veh ~= 0 and DoesEntityExist(veh) and not IsEntityDead(veh) then
            if
                GetPedInVehicleSeat(veh, -1) == PlayerPedId()
                and GetIsVehicleEngineRunning(veh)
                and not IsPauseMenuActive()
            then
                if IsControlPressed(0, VEHICLE_HORN) then
                    SetVehicleFullbeam(veh, true)
                end
                if IsControlJustReleased(0, VEHICLE_HORN) then
                    SetVehicleFullbeam(veh, false)
                end
            end
        end
    end
end

local function health_string(health)
    local color
    if health <= 0 then
        color = '~r~'
    else
        local band = math.floor(Common.map(health, 0, 1000, 0, 4))
        if band == 0 then
            color = '~r~'
        elseif band == 1 then
            color = '~o~'
        elseif band == 2 then
            color = '~y~'
        else
            color = '~g~'
        end
    end
    return color .. tostring(health)
end

local function round2(value)
    return math.floor(value * 100 + 0.5) / 100
end

local function vehicle_show_health_tick()
    local vo = vehicle_options_menu()
    if vo ~= nil and vo.VehicleShowHealth then
        local veh = Common.get_vehicle()
        if veh ~= 0 and DoesEntityExist(veh) then
            Common.draw_text_on_screen(
                ('~n~Engine health: %s'):format(health_string(round2(GetVehicleEngineHealth(veh)))),
                0.5,
                0.0
            )
            Common.draw_text_on_screen(
                ('~n~~n~Body health: %s'):format(health_string(round2(GetVehicleBodyHealth(veh)))),
                0.5,
                0.0
            )
            Common.draw_text_on_screen(
                ('~n~~n~~n~Tank health: %s'):format(health_string(round2(GetVehiclePetrolTankHealth(veh)))),
                0.5,
                0.0
            )
        end
    end
end

-- ---------------------------------------------------------------------------
-- Weapon options
-- ---------------------------------------------------------------------------

local MINIGUN_HASH = GetHashKey('weapon_minigun')
local UNARMED_HASH = GetHashKey('weapon_unarmed')
local PARACHUTE_HASH = GetHashKey('gadget_parachute')

local function weapon_options_tick()
    local wo = State.menus.weapon_options
    if wo == nil then
        Wait(100)
        return
    end
    local ped = PlayerPedId()
    local current_weapon = GetSelectedPedWeapon(ped)

    if wo.NoReload and current_weapon ~= MINIGUN_HASH and Permissions.is_allowed('WPNoReload') then
        SetAmmoInClip(ped, current_weapon, 5)
    end

    if Permissions.is_allowed('WPUnlimitedAmmo') and current_weapon ~= UNARMED_HASH then
        SetPedInfiniteAmmo(ped, wo.UnlimitedAmmo == true, current_weapon)
    end

    if wo.AutoEquipChute then
        if
            (IsPedInAnyHeli(ped) or IsPedInAnyPlane(ped))
            and not HasPedGotWeapon(ped, GetHashKey('gadget_parachute'), false)
        then
            GiveWeaponToPed(ped, GetHashKey('gadget_parachute'), 1, false, true)
            SetPlayerHasReserveParachute(PlayerId())
            SetPlayerCanLeaveParachuteSmokeTrail(ped, true)
        end
    end

    if wo.UnlimitedParachutes then
        if not HasPedGotWeapon(ped, PARACHUTE_HASH, false) then
            GiveWeaponToPed(ped, PARACHUTE_HASH, 0, false, false)
        end
        if not GetPlayerHasReserveParachute(PlayerId()) then
            SetPlayerHasReserveParachute(PlayerId())
        end
    end
end

-- ---------------------------------------------------------------------------
-- Spectate + respawn restore + clothing glow + animal camera + personal veh
-- ---------------------------------------------------------------------------

local function spectate_handling_tick()
    if
        State.menus.online_players ~= nil
        and Permissions.is_allowed('OPMenu')
        and Permissions.is_allowed('OPSpectate')
    then
        local ped = PlayerPedId()
        if GetEntityHealth(ped) < 1 and NetworkIsInSpectatorMode() then
            DoScreenFadeOut(50)
            Wait(50)
            NetworkSetInSpectatorMode(true, ped)
            NetworkSetInSpectatorMode(false, ped)
            Wait(50)
            DoScreenFadeIn(50)
            while GetEntityHealth(PlayerPedId()) < 1 do
                Wait(0)
            end
        end
    else
        Wait(0)
    end
end

local function restore_player_after_being_dead()
    local misc = misc_menu()
    if misc ~= nil and IsEntityDead(PlayerPedId()) then
        local restore_default = false
        if misc.MiscRespawnDefaultCharacter then
            local default_character = GetResourceKvpString('vmenu_default_character')
            if default_character ~= nil and default_character ~= '' then
                restore_default = true
            else
                Notify.error(
                    'You did not set a saved character to restore to. Do so in the ~g~MP Ped Customization~s~ > '
                        .. '~g~Saved Characters~s~ menu.'
                )
            end
        end
        if not restore_default then
            if misc.RestorePlayerAppearance and Permissions.is_allowed('MSRestoreAppearance') then
                PedCommon.save_ped('vMenu_tmp_saved_ped', true)
            end
        end

        local loadouts = State.menus.weapon_loadouts
        local restore_weapons = (misc.RestorePlayerWeapons and Permissions.is_allowed('MSRestoreWeapons'))
            or (
                loadouts ~= nil
                and loadouts.WeaponLoadoutsSetLoadoutOnRespawn
                and Permissions.is_allowed('WLEquipOnRespawn')
            )
        if restore_weapons then
            Weapons.save_weapon_loadout('vmenu_temp_weapons_loadout_before_respawn')
        end

        while IsEntityDead(PlayerPedId()) or IsScreenFadedOut() or IsScreenFadingOut() do
            Wait(0)
        end

        if restore_default then
            local mp = State.menus.mp_ped_customization
            if mp ~= nil then
                mp.spawn_this_character(GetResourceKvpString('vmenu_default_character'), false)
            end
        else
            if
                PedCommon.is_temp_ped_saved()
                and misc.RestorePlayerAppearance
                and Permissions.is_allowed('MSRestoreAppearance')
            then
                PedCommon.load_saved_ped('vMenu_tmp_saved_ped', false)
            end
        end

        if restore_weapons then
            Weapons.spawn_weapon_loadout('vmenu_temp_weapons_loadout_before_respawn', true, false, false)
            DeleteResourceKvp('vmenu_temp_weapons_loadout_before_respawn')
        end
    end
end

local function player_clothing_animations_controller()
    if not DecorIsRegisteredAsType(CLOTHING_ANIMATION_DECOR, 3) then
        DecorRegister(CLOTHING_ANIMATION_DECOR, 3)
        while not DecorIsRegisteredAsType(CLOTHING_ANIMATION_DECOR, 3) do
            Wait(0)
        end
    else
        local appearance = State.menus.player_appearance
        local animation_type = appearance ~= nil and appearance.ClothingAnimationType or 0
        DecorSetInt(PlayerPedId(), CLOTHING_ANIMATION_DECOR, animation_type)

        local PlayerLists = require('client.player_lists')
        for _, player in ipairs(PlayerLists.players()) do
            local p = player.ped
            if p ~= nil and p ~= 0 and DoesEntityExist(p) and not IsEntityDead(p) then
                if DecorExistOn(p, CLOTHING_ANIMATION_DECOR) then
                    local decor_val = DecorGetInt(p, CLOTHING_ANIMATION_DECOR)
                    if decor_val == 0 then -- on solid / no animation
                        SetPedIlluminatedClothingGlowIntensity(p, 1.0)
                    elseif decor_val == 1 then -- off
                        SetPedIlluminatedClothingGlowIntensity(p, 0.0)
                    elseif decor_val == 2 then -- fade
                        SetPedIlluminatedClothingGlowIntensity(p, clothing_opacity)
                    elseif decor_val == 3 then -- flash
                        local result = 0.0
                        if clothing_animation_reverse then
                            if clothing_opacity >= 0.0 and clothing_opacity <= 0.5 then
                                result = 1.0
                            end
                        else
                            if clothing_opacity >= 0.5 and clothing_opacity <= 1.0 then
                                result = 1.0
                            end
                        end
                        SetPedIlluminatedClothingGlowIntensity(p, result)
                    end
                end
            end
        end

        if clothing_animation_reverse then
            clothing_opacity = clothing_opacity - 0.05
            if clothing_opacity < 0.0 then
                clothing_opacity = 0.0
                clothing_animation_reverse = false
            end
        else
            clothing_opacity = clothing_opacity + 0.05
            if clothing_opacity > 1.0 then
                clothing_opacity = 1.0
                clothing_animation_reverse = true
            end
        end
        local timer = GetGameTimer()
        while GetGameTimer() - timer < 25 do
            Wait(0)
        end
    end
    local appearance = State.menus.player_appearance
    DecorSetInt(PlayerPedId(), CLOTHING_ANIMATION_DECOR, appearance ~= nil and appearance.ClothingAnimationType or 0)
end

local function animal_ped_camera_change_blocker()
    local model = GetEntityModel(PlayerPedId())
    local is_animal = false
    for _, hash in ipairs(PedModels.animal_hashes) do
        if hash == model then
            is_animal = true
            break
        end
    end
    if is_animal then
        while model == GetEntityModel(PlayerPedId()) do
            DisableFirstPersonCamThisFrame()
            Wait(0)
        end
    end
end

local did_show_pv_help_message = false
local pv_horn_time = 0

local function personal_vehicle_options_tick()
    local pv = State.menus.personal_vehicle
    if pv ~= nil and pv.CurrentPersonalVehicle ~= nil and DoesEntityExist(pv.CurrentPersonalVehicle) then
        local ped = PlayerPedId()
        local vehicle = pv.CurrentPersonalVehicle
        if GetVehiclePedIsIn(ped, false) ~= vehicle and not IsPedGettingIntoAVehicle(ped) then
            local pos = GetEntityCoords(ped)
            local veh_pos = GetEntityCoords(vehicle)
            local dx, dy, dz = pos.x - veh_pos.x, pos.y - veh_pos.y, pos.z - veh_pos.z
            if (dx * dx + dy * dy + dz * dz) < 650.0 then
                if IsControlJustReleased(0, VEHICLE_HORN) then
                    -- double-tap within 500ms locks/unlocks
                    if GetGameTimer() - pv_horn_time < 500 then
                        VehicleCommon.press_key_fob(vehicle)
                        Wait(100)
                        local lock_doors = not GetVehicleDoorsLockedForPlayer(vehicle, ped)
                        VehicleCommon.lock_or_unlock_doors(vehicle, lock_doors)
                        pv_horn_time = 0
                    else
                        pv_horn_time = GetGameTimer()
                    end
                end
                if not did_show_pv_help_message then
                    did_show_pv_help_message = true
                    Notification.HelpMessage.custom(
                        'When you are close to your personal vehicle, you can double tap ~INPUT_VEH_HORN~ to lock '
                            .. 'or unlock it.',
                        10000,
                        true
                    )
                end
            else
                Wait(100)
            end
        else
            Wait(100)
        end
    else
        Wait(100)
    end
end

-- ---------------------------------------------------------------------------
-- Setup (vMenu:SetupTickFunctions)
-- ---------------------------------------------------------------------------

function FunctionsController.setup_tick_functions()
    -- always needed
    add_tick(CreatorCamera.animations_and_interactions)
    add_tick(player_clothing_animations_controller)
    add_tick(Hud.misc_recording_keybinds)
    add_tick(Hud.misc_settings_tick)
    add_tick(general_tasks)
    -- (C#'s GcTick is .NET garbage collection; nothing to do in Lua)
    add_tick(controller_tick)

    if Config.get_bool('keep_player_head_props') then
        if DoesEntityExist(PlayerPedId()) then
            SetPedCanLosePropsOnDamage(PlayerPedId(), false, 0)
        end
        add_tick(player_head_props_tick)
    end

    -- configuration and permissions based
    if Permissions.is_allowed('WOMenu') and Config.get_bool('vmenu_enable_weather_sync') then
        add_tick(Hud.weather_options_tick)
    end
    if Permissions.is_allowed('TOMenu') and Config.get_bool('vmenu_enable_time_sync') then
        add_tick(Hud.time_options_tick)
    end

    -- configuration based
    if not Config.get_bool('vmenu_disable_spawning_as_default_character') then
        add_tick(restore_player_after_being_dead)
    end
    if not Config.get_bool('vmenu_disable_entity_outlines_tool') then
        add_tick(Hud.slow_misc_tick)
        add_tick(Hud.model_draw_dimensions)
    end

    -- permissions based
    if Permissions.is_allowed('POMenu') or Permissions.is_allowed('VOMenu') then
        add_tick(player_and_vehicle_checks)
    end
    if Permissions.is_allowed('VOMenu') then
        add_tick(vehicle_options_tick)
        add_tick(vehicle_show_health_tick)
        if Permissions.is_allowed('VOFlashHighbeamsOnHonk') then
            add_tick(vehicle_highbeam_flash_tick)
        end
    end
    if Permissions.is_allowed('VCMenu') then
        add_tick(Hud.voice_chat_tick)
    end
    if Permissions.is_allowed('WPMenu') then
        add_tick(weapon_options_tick)
    end
    if Permissions.is_allowed('OPMenu') then
        add_tick(Hud.online_players_tasks)
    end
    if Permissions.is_allowed('MSDeathNotifs') then
        add_tick(Hud.death_notifications)
    end
    if Permissions.is_allowed('MSShowLocation') then
        add_tick(Hud.update_location)
    end
    if Permissions.is_allowed('PAMenu') then
        add_tick(CreatorCamera.manage_camera)
        add_tick(CreatorCamera.disable_movement)
    end
    if Permissions.is_allowed('MSPlayerBlips') then
        add_tick(Hud.player_blips_control)
    end
    if Permissions.is_allowed('MSOverheadNames') then
        add_tick(Hud.player_overhead_names_control)
    end
    if Permissions.is_allowed('POMenu') then
        add_tick(player_options_tick)
    end
    if Permissions.is_allowed('WPSnowball') then
        add_tick(CreatorCamera.snowball_pickup_help_message_task)
    end
    if Permissions.is_allowed('PVLockDoors') then
        add_tick(personal_vehicle_options_tick)
    end
    if Config.get_bool('vmenu_enable_animals_spawn_menu') then
        add_tick(animal_ped_camera_change_blocker)
    end
    if Permissions.is_allowed('OPSpectate') then
        add_tick(spectate_handling_tick)
    end
end

AddEventHandler('vMenu:SetupTickFunctions', function()
    FunctionsController.setup_tick_functions()
end)

-- Join/quit notifications arrive as an event, not a tick.
AddEventHandler('vMenu:PlayerJoinQuit', function(player_name, drop_reason)
    local misc = misc_menu()
    if State.config_options_setup_complete and misc ~= nil then
        if misc.JoinQuitNotifications and Permissions.is_allowed('MSJoinQuitNotifs') then
            if drop_reason == nil then
                Notify.custom(('~g~<C>%s</C>~s~ joined the server.'):format(Common.get_safe_player_name(player_name)))
            else
                Notify.custom(
                    ('~r~<C>%s</C>~s~ left the server. ~c~(%s)'):format(
                        Common.get_safe_player_name(player_name),
                        Common.get_safe_player_name(drop_reason)
                    )
                )
            end
        end
    end
end)

return FunctionsController
