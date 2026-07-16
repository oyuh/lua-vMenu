-- Port of MenuAPI/MenuController.cs tick functions: per-frame menu drawing,
-- select/back buttons, directional navigation with hold-to-scroll
-- acceleration, the menu toggle key, and control disabling while a menu is
-- open. Process.start() spins up the threads (called from client/main.lua).

local Controller = require('menu.controller')
require('menu.render')

local Process = {}

-- FiveM control ids (CitizenFX.Core Control enum values used by MenuAPI).
-- Ids marked "verify" get double-checked during the in-game M3 checklist.
local Controls = {
    FrontendAccept = 201,
    PhoneCancel = 177,
    FrontendPause = 199,
    FrontendPauseAlternate = 200,
    FrontendUp = 188,
    FrontendDown = 187,
    PhoneLeft = 174,
    PhoneRight = 175,
    PhoneScrollBackward = 241,
    PhoneScrollForward = 242,
    SelectWeapon = 37,
    SelectNextWeapon = 14,
    SelectPrevWeapon = 15,
    InteractionMenu = 244,
    MultiplayerInfo = 337, -- verify
    VehicleMouseControlOverride = 338, -- verify
    Phone = 27,
    PhoneDown = 173,
    Attack = 24,
    Attack2 = 257,
    Aim = 25,
    MeleeAttackLight = 140,
    MeleeAttackHeavy = 141,
    MeleeAttackAlternate = 142,
    MeleeAttack1 = 263,
    MeleeAttack2 = 264,
    VehicleAim = 68,
    VehicleAttack = 69,
    VehicleAttack2 = 70,
    VehicleFlyAttack = 114,
    VehiclePassengerAttack = 91,
    VehicleSelectNextWeapon = 99,
    VehicleSelectPrevWeapon = 100,
    VehicleCinCam = 80,
    VehicleHeadlight = 74,
    VehicleDuck = 73,
    VehicleFlyTransform = 352, -- verify
    VehicleNextRadio = 81,
    VehiclePrevRadio = 82,
    RadioWheelLeftRight = 85,
    RadioWheelUpDown = 86,
    VehicleRadioWheel = 85,
}
Process.Controls = Controls

local MENU_TEXTURE_ASSETS = { 'commonmenu', 'mpleaderboard' }

local function pressed(control)
    return IsControlPressed(0, control) or IsDisabledControlPressed(0, control)
end

local function just_pressed(control)
    return IsControlJustPressed(0, control) or IsDisabledControlJustPressed(0, control)
end

local function just_released(control)
    return IsControlJustReleased(0, control) or IsDisabledControlJustReleased(0, control)
end

local function using_keyboard()
    -- IsInputDisabled(2): true while the last input came from keyboard/mouse.
    return IsInputDisabled(2)
end

-- ---------------------------------------------------------------------------
-- Asset streaming
-- ---------------------------------------------------------------------------

local function load_assets()
    for _, dict in ipairs(MENU_TEXTURE_ASSETS) do
        if not HasStreamedTextureDictLoaded(dict) then
            RequestStreamedTextureDict(dict, false)
        end
    end
    local all_loaded = false
    while not all_loaded do
        all_loaded = true
        for _, dict in ipairs(MENU_TEXTURE_ASSETS) do
            if not HasStreamedTextureDictLoaded(dict) then
                all_loaded = false
            end
        end
        if not all_loaded then
            Wait(0)
        end
    end
end

local function unload_assets()
    for _, dict in ipairs(MENU_TEXTURE_ASSETS) do
        if HasStreamedTextureDictLoaded(dict) then
            SetStreamedTextureDictAsNoLongerNeeded(dict)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Control disabling while a menu is open (MenuController.DisableControls)
-- ---------------------------------------------------------------------------

local ATTACK_CONTROLS = {
    Controls.Attack,
    Controls.Attack2,
    Controls.MeleeAttackLight,
    Controls.MeleeAttackHeavy,
    Controls.MeleeAttackAlternate,
    Controls.MeleeAttack1,
    Controls.MeleeAttack2,
    Controls.VehicleAttack,
    Controls.VehicleAttack2,
    Controls.VehicleFlyAttack,
    Controls.VehiclePassengerAttack,
    Controls.Aim,
    Controls.VehicleAim,
}

local RADIO_CONTROLS = {
    Controls.RadioWheelLeftRight,
    Controls.RadioWheelUpDown,
    Controls.VehicleNextRadio,
    Controls.VehicleRadioWheel,
    Controls.VehiclePrevRadio,
}

local PHONE_CONTROLS = {
    Controls.Phone,
    Controls.PhoneCancel,
    Controls.PhoneDown,
    Controls.PhoneLeft,
    Controls.PhoneRight,
}

local function is_list_like(item)
    local Items = require('menu.items')
    local mt = getmetatable(item)
    return mt == Items.MenuListItem or mt == Items.MenuSliderItem or mt == Items.MenuDynamicListItem
end

local function disable_controls()
    if not Controller.IsAnyMenuOpen() then
        return
    end
    local menu = Controller.GetCurrentMenu()
    if menu == nil then
        return
    end
    if IsEntityDead(PlayerPedId()) then
        Controller.CloseAllMenus()
    end

    local in_vehicle = IsPedInAnyVehicle(PlayerPedId(), false)

    if not using_keyboard() then
        DisableControlAction(0, Controls.MultiplayerInfo, true)
        if in_vehicle then
            DisableControlAction(0, Controls.VehicleHeadlight, true)
            DisableControlAction(0, Controls.VehicleDuck, true)
            DisableControlAction(0, Controls.VehicleFlyTransform, true)
        end
    else
        DisableControlAction(0, Controls.FrontendPauseAlternate, true)
        if not IsControlPressed(0, Controls.SelectWeapon) then
            DisableControlAction(24, Controls.SelectNextWeapon, true)
            DisableControlAction(24, Controls.SelectPrevWeapon, true)
        end
    end

    local current = menu:GetCurrentMenuItem()
    if current and is_list_like(current) and not using_keyboard() then
        DisableControlAction(0, Controls.SelectWeapon, true)
    end

    for _, control in ipairs(RADIO_CONTROLS) do
        DisableControlAction(0, control, true)
    end
    for _, control in ipairs(PHONE_CONTROLS) do
        DisableControlAction(0, control, true)
    end
    for _, control in ipairs(ATTACK_CONTROLS) do
        DisableControlAction(0, control, true)
    end

    if in_vehicle then
        DisableControlAction(0, Controls.VehicleSelectNextWeapon, true)
        DisableControlAction(0, Controls.VehicleSelectPrevWeapon, true)
        DisableControlAction(0, Controls.VehicleCinCam, true)
    end
end

-- ---------------------------------------------------------------------------
-- Drawing tick (MenuController.ProcessMenus)
-- ---------------------------------------------------------------------------

local function can_draw()
    return #Controller.Menus > 0
        and Controller.IsAnyMenuOpen()
        and IsScreenFadedIn()
        and not IsPauseMenuActive()
        and not IsEntityDead(PlayerPedId())
        and not IsPlayerSwitchInProgress()
end

local function process_menus()
    if not can_draw() then
        unload_assets()
        return
    end
    load_assets()
    disable_controls()

    local menu = Controller.GetCurrentMenu()
    if menu == nil then
        return
    end
    if Controller.DontOpenAnyMenu then
        if menu.Visible and not menu.IgnoreDontOpenMenus then
            menu:CloseMenu()
        end
    elseif menu.Visible then
        menu:Draw()
    end
end

-- ---------------------------------------------------------------------------
-- Select / back buttons (MenuController.ProcessMainButtons)
-- ---------------------------------------------------------------------------

local function process_main_buttons()
    if not Controller.IsAnyMenuOpen() or IsPauseMenuActive() then
        return
    end
    local menu = Controller.GetCurrentMenu()
    if menu == nil or Controller.DontOpenAnyMenu then
        return
    end
    DisableControlAction(0, Controls.MultiplayerInfo, true)
    if Controller.PreventExitingMenu then
        DisableControlAction(0, Controls.FrontendPause, true)
        DisableControlAction(0, Controls.FrontendPauseAlternate, true)
    end
    if not menu.Visible or not Controller.AreMenuButtonsEnabled() then
        return
    end

    -- Custom per-menu button handlers (Menu.ButtonPressHandlers).
    if menu.ButtonPressHandlers ~= nil then
        for _, entry in ipairs(menu.ButtonPressHandlers) do
            if entry.disable_control then
                DisableControlAction(0, entry.control, true)
            end
            local fired = false
            if entry.check_type == 'JUST_RELEASED' then
                fired = IsControlJustReleased(0, entry.control) or IsDisabledControlJustReleased(0, entry.control)
            elseif entry.check_type == 'JUST_PRESSED' then
                fired = IsControlJustPressed(0, entry.control) or IsDisabledControlJustPressed(0, entry.control)
            elseif entry.check_type == 'RELEASED' then
                fired = not IsControlPressed(0, entry.control) and not IsDisabledControlPressed(0, entry.control)
            elseif entry.check_type == 'PRESSED' then
                fired = IsControlPressed(0, entry.control) or IsDisabledControlPressed(0, entry.control)
            end
            if fired then
                entry.handler(menu, entry.control)
            end
        end
    end

    if just_released(Controls.FrontendAccept) or just_released(Controls.VehicleMouseControlOverride) then
        if menu:Size() > 0 then
            menu:SelectItem(menu.CurrentIndex)
        end
    elseif not Controller.DisableBackButton and IsDisabledControlJustReleased(0, Controls.PhoneCancel) then
        -- wait a frame so the cinematic-camera control isn't re-enabled early
        Wait(0)
        menu:GoBack()
    elseif
        Controller.PreventExitingMenu
        and not Controller.DisableBackButton
        and IsDisabledControlJustReleased(0, Controls.PhoneCancel)
    then
        if menu.ParentMenu ~= nil then
            menu:GoBack()
        end
        Wait(0)
    end
end

-- ---------------------------------------------------------------------------
-- Directional navigation with hold acceleration
-- ---------------------------------------------------------------------------

local function weapon_wheel_conflict()
    if not IsPedInAnyVehicle(PlayerPedId(), false) then
        if IsControlPressed(0, Controls.SelectWeapon) then
            if IsControlPressed(0, Controls.SelectNextWeapon) or IsControlPressed(0, Controls.SelectPrevWeapon) then
                return true
            end
        end
    end
    return false
end

local function is_up_pressed()
    if not Controller.AreMenuButtonsEnabled() or weapon_wheel_conflict() then
        return false
    end
    return pressed(Controls.FrontendUp) or pressed(Controls.PhoneScrollBackward)
end

local function is_down_pressed()
    if not Controller.AreMenuButtonsEnabled() or weapon_wheel_conflict() then
        return false
    end
    return pressed(Controls.FrontendDown) or pressed(Controls.PhoneScrollForward)
end

-- Hold-to-scroll: 200ms between steps, accelerating to 150/100/50/25ms after
-- 3/6/26/61 steps — exactly MenuAPI's ramp.
local function hold_repeat(step, keep_holding)
    step()
    local time = GetGameTimer()
    local times = 0
    local delay = 200
    while keep_holding() and Controller.GetCurrentMenu() ~= nil do
        if GetGameTimer() - time > delay then
            times = times + 1
            if times > 60 then
                delay = 25
            elseif times > 25 then
                delay = 50
            elseif times > 5 then
                delay = 100
            elseif times > 2 then
                delay = 150
            end
            step()
            time = GetGameTimer()
        end
        Wait(0)
    end
end

local function process_directional_buttons()
    if not Controller.AreMenuButtonsEnabled() then
        return
    end
    local menu = Controller.GetCurrentMenu()
    if menu == nil or Controller.DontOpenAnyMenu or menu:Size() < 1 or not menu.Visible then
        return
    end

    if is_up_pressed() then
        hold_repeat(function()
            local current = Controller.GetCurrentMenu()
            if current then
                current:GoUp()
            end
        end, is_up_pressed)
    elseif is_down_pressed() then
        hold_repeat(function()
            local current = Controller.GetCurrentMenu()
            if current then
                current:GoDown()
            end
        end, is_down_pressed)
    elseif just_pressed(Controls.PhoneLeft) then
        local item = menu:GetCurrentMenuItem()
        if item ~= nil and item.Enabled then
            hold_repeat(function()
                local current = Controller.GetCurrentMenu()
                if current then
                    current:GoLeft()
                end
            end, function()
                return Controller.AreMenuButtonsEnabled() and pressed(Controls.PhoneLeft)
            end)
        end
    elseif just_pressed(Controls.PhoneRight) then
        local item = menu:GetCurrentMenuItem()
        if item ~= nil and item.Enabled then
            hold_repeat(function()
                local current = Controller.GetCurrentMenu()
                if current then
                    current:GoRight()
                end
            end, function()
                return Controller.AreMenuButtonsEnabled() and pressed(Controls.PhoneRight)
            end)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Menu toggle key (MenuController.ProcessToggleMenuButton)
-- vMenu itself sets MenuToggleKey = -1 and toggles via RegisterKeyMapping;
-- this exists for MenuAPI parity when a toggle key is configured.
-- ---------------------------------------------------------------------------

local function open_main_menu()
    if Controller.MainMenu ~= nil then
        Controller.MainMenu:OpenMenu()
    elseif #Controller.Menus > 0 then
        Controller.Menus[1]:OpenMenu()
    end
end

local function toggle_key_guards_ok()
    return not IsPauseMenuActive()
        and not IsPauseMenuRestarting()
        and IsScreenFadedIn()
        and not IsPlayerSwitchInProgress()
        and not IsEntityDead(PlayerPedId())
        and not Controller.DisableMenuButtons
end

local function process_toggle_menu_button()
    local key = Controller.MenuToggleKey
    if key == nil or key == -1 then
        Wait(1500)
        return
    end
    if not toggle_key_guards_ok() then
        return
    end

    if Controller.IsAnyMenuOpen() then
        -- disable the key and let it close the menu (keyboard only)
        DisableControlAction(0, key, true)
        if using_keyboard() and just_pressed(key) and not Controller.PreventExitingMenu then
            local menu = Controller.GetCurrentMenu()
            if menu then
                menu:CloseMenu()
            end
        end
    elseif not using_keyboard() then
        if not Controller.EnableMenuToggleKeyOnController then
            return
        end
        local timer = GetGameTimer()
        while pressed(Controls.InteractionMenu) and toggle_key_guards_ok() and not Controller.DontOpenAnyMenu do
            if GetGameTimer() - timer > 400 then
                open_main_menu()
                break
            end
            Wait(0)
        end
    else
        if just_pressed(key) and not Controller.DontOpenAnyMenu and #Controller.Menus > 0 then
            open_main_menu()
        end
    end
end

-- ---------------------------------------------------------------------------
-- Onscreen keyboard guard (MenuController.MenuButtonsDisableChecks)
-- ---------------------------------------------------------------------------

local function menu_buttons_disable_checks()
    if UpdateOnscreenKeyboard() == 0 then
        local previous_state = Controller.DisableMenuButtons
        while UpdateOnscreenKeyboard() == 0 do
            Wait(0)
            Controller.DisableMenuButtons = true
        end
        local timer = GetGameTimer()
        while GetGameTimer() - timer < 300 do
            Wait(0)
            Controller.DisableMenuButtons = true
        end
        Controller.DisableMenuButtons = previous_state
    end
end

-- ---------------------------------------------------------------------------
-- Instructional buttons scaleform (MenuController.DrawInstructionalButtons)
-- ---------------------------------------------------------------------------

local instructional_handle = nil

local function dispose_instructional_buttons()
    if instructional_handle ~= nil then
        SetScaleformMovieAsNoLongerNeeded(instructional_handle)
        instructional_handle = nil
    end
end

local function draw_instructional_buttons()
    if
        IsPauseMenuActive()
        or IsEntityDead(PlayerPedId())
        or not IsScreenFadedIn()
        or IsPlayerSwitchInProgress()
        or IsWarningMessageActive()
        or UpdateOnscreenKeyboard() == 0
    then
        dispose_instructional_buttons()
        return
    end
    local menu = Controller.GetCurrentMenu()
    if menu == nil or not menu.Visible or not menu.EnableInstructionalButtons then
        dispose_instructional_buttons()
        return
    end

    if instructional_handle == nil then
        instructional_handle = RequestScaleformMovie('INSTRUCTIONAL_BUTTONS')
    end
    if not HasScaleformMovieLoaded(instructional_handle) then
        return
    end

    local buttons = menu.InstructionalButtons
        or {
            { control = Controls.FrontendAccept, label = GetLabelText('HUD_INPUT28') }, -- Select
            { control = 202, label = GetLabelText('HUD_INPUT53') }, -- Back (FrontendCancel)
        }

    BeginScaleformMovieMethod(instructional_handle, 'CLEAR_ALL')
    EndScaleformMovieMethod()

    BeginScaleformMovieMethod(instructional_handle, 'TOGGLE_MOUSE_BUTTONS')
    ScaleformMovieMethodAddParamBool(false)
    EndScaleformMovieMethod()

    for i, button in ipairs(buttons) do
        BeginScaleformMovieMethod(instructional_handle, 'SET_DATA_SLOT')
        ScaleformMovieMethodAddParamInt(i - 1)
        PushScaleformMovieMethodParameterString(GetControlInstructionalButton(2, button.control, true))
        PushScaleformMovieMethodParameterString(button.label or '')
        EndScaleformMovieMethod()
    end

    BeginScaleformMovieMethod(instructional_handle, 'DRAW_INSTRUCTIONAL_BUTTONS')
    ScaleformMovieMethodAddParamInt(0)
    EndScaleformMovieMethod()

    DrawScaleformMovieFullscreen(instructional_handle, 255, 255, 255, 255, 0)
end

-- ---------------------------------------------------------------------------
-- Thread startup
-- ---------------------------------------------------------------------------

local started = false

function Process.start()
    if started then
        return
    end
    started = true

    local ticks = {
        process_menus,
        draw_instructional_buttons,
        process_main_buttons,
        process_directional_buttons,
        process_toggle_menu_button,
        menu_buttons_disable_checks,
    }
    for _, tick in ipairs(ticks) do
        CreateThread(function()
            while true do
                tick()
                Wait(0)
            end
        end)
    end
end

return Process
