-- Port of MenuAPI/MenuController.cs (v4): the menu registry, the ticks that
-- run while a menu is open, button handling, disabled game controls and the
-- instructional buttons. Call Controller.init() once, after setting
-- MenuToggleKeyDefault.

local Log = require('shared.log')
local FrameState = require('menu.frame_state')
local Input = require('menu.input')
local Items = require('menu.items')
local Nui = require('menu.nui')
local Sprites = require('menu.sprites')
local Ticks = require('menu.ticks')

local Controller = {}

local LAYOUT_REFRESH_MS = 500
local TEXTURE_REFRESH_MS = 250
local INSTRUCTIONAL_BUTTONS_CONFIGURE_MS = 300
local PAGE_REPEAT_FIRST_DELAY = 400
local PAGE_REPEAT_DELAY = 250
local ICON_SEPARATOR = '%b_998%'

-- Game controls, by index.
local C = {
    MULTIPLAYER_INFO = 20,
    FRONTEND_PAUSE = 199,
    FRONTEND_PAUSE_ALTERNATE = 200,
    INTERACTION_MENU = 244,
    VEHICLE_SELECT_NEXT_WEAPON = 99,
    VEHICLE_SELECT_PREV_WEAPON = 100,
    VEHICLE_CIN_CAM = 80,
    VEHICLE_HEADLIGHT = 74,
    VEHICLE_DUCK = 73,
    VEHICLE_FLY_TRANSFORM = 357,
    SELECT_WEAPON = 37,
    SELECT_NEXT_WEAPON = 16,
    SELECT_PREV_WEAPON = 17,
    ATTACK = 24,
    ATTACK2 = 257,
    MELEE_ATTACK1 = 263,
    MELEE_ATTACK2 = 264,
    MELEE_ATTACK_ALTERNATE = 142,
    MELEE_ATTACK_HEAVY = 141,
    MELEE_ATTACK_LIGHT = 140,
    VEHICLE_ATTACK = 69,
    VEHICLE_ATTACK2 = 70,
    VEHICLE_FLY_ATTACK = 114,
    VEHICLE_PASSENGER_ATTACK = 92,
    AIM = 25,
    VEHICLE_AIM = 68,
    PHONE = 27,
    PHONE_CANCEL = 177,
    PHONE_DOWN = 173,
    PHONE_LEFT = 174,
    PHONE_RIGHT = 175,
    RADIO_WHEEL_LEFT_RIGHT = 333,
    RADIO_WHEEL_UP_DOWN = 332,
    VEHICLE_NEXT_RADIO = 81,
    VEHICLE_RADIO_WHEEL = 85,
    VEHICLE_PREV_RADIO = 82,
    -- Rarely used, and disabled while the F8 console is open, which is the
    -- only way to tell that the console is open.
    CONSOLE_PROBE = 360,
}

Controller.Menus = {}
Controller.MainMenu = nil
Controller.DisableMenuButtons = false
Controller.NavigateMenuUsingArrows = true
Controller.PreventExitingMenu = false
Controller.DisableBackButton = false
Controller.DontOpenAnyMenu = false
Controller.EnableMenuToggleKeyOnController = true
Controller.EnableMenuToggleKey = true
-- The menu toggle key for players who never rebound it. Set before init().
Controller.MenuToggleKeyDefault = 'M'

-- Drawn defaults: assigning one redraws the open menu.
local drawn = {
    DefaultTitleFont = 1, -- MenuFont.HouseScript
    DefaultTitleAlignment = 'Center', -- 'Left', 'Center' or 'Right'
    DefaultShowHeaderGlare = false,
    MenuAlignment = 'Left', -- 'Left' or 'Right'
}

setmetatable(Controller, {
    __index = drawn,
    __newindex = function(_, key, value)
        if drawn[key] == nil then
            rawset(Controller, key, value)
            return
        end
        if key == 'MenuAlignment' and value == 'Right' and GetScreenAspectRatio(false) >= 1.888888888888889 then
            -- Right aligned menus are not supported on 17:9 or wider screens.
            Log.error(
                (
                    '[MenuAPI (%s)] Right aligned menus are not supported for aspect ratios '
                    .. '17:9 or 21:9, left aligned will be used instead.'
                ):format(GetCurrentResourceName())
            )
            value = 'Left'
        end
        if drawn[key] ~= value then
            drawn[key] = value
            Nui.invalidate()
        end
    end,
})

local visible_menus = {}
local menu_buttons = {} -- item -> menu it opens
local scaleform = 0
local instructional_menu, instructional_item

-- Registry ---------------------------------------------------------------------------

local function contains(list, value)
    for _, entry in ipairs(list) do
        if entry == value then
            return true
        end
    end
    return false
end

local function remove_value(list, value)
    for index = #list, 1, -1 do
        if list[index] == value then
            table.remove(list, index)
        end
    end
end

function Controller.AddMenu(menu)
    if not contains(Controller.Menus, menu) then
        Controller.Menus[#Controller.Menus + 1] = menu
        -- The first menu becomes the main menu unless one is set.
        if Controller.MainMenu == nil then
            Controller.MainMenu = menu
        end
    end
end

function Controller.AddSubmenu(parent, child)
    Controller.AddMenu(child)
    child.ParentMenu = parent
end

-- Binds child to item and makes parent its parent menu.
function Controller.BindMenuItem(parent, child, item)
    Controller.AddSubmenu(parent, child)
    menu_buttons[item] = child
end

function Controller.bound_menu(item)
    return menu_buttons[item]
end

function Controller.has_bound_menus()
    return next(menu_buttons) ~= nil
end

local function still_bound(menu)
    for _, bound in pairs(menu_buttons) do
        if bound == menu then
            return true
        end
    end
    return false
end

local remove_menu

-- Forgets the menu item opened. Inside a RemoveMenu cascade (removed is
-- set) the menu goes too, unless another row still opens it.
function Controller.unbind(item, removed)
    local child = menu_buttons[item]
    if not child then
        return
    end
    menu_buttons[item] = nil
    if removed == nil or still_bound(child) or Controller.MainMenu == child then
        return
    end
    remove_menu(child, removed)
end

remove_menu = function(menu, removed)
    -- Added first, so a menu bound in a loop back to this one stops here.
    if removed[menu] then
        return
    end
    removed[menu] = true
    local parent = menu.ParentMenu
    local was_open = menu.Visible
    if was_open then
        -- Through CloseMenu, so subscribers hear about it while attached.
        menu:CloseMenu()
    end
    remove_value(Controller.Menus, menu)
    menu:Detach(removed)
    for _, other in ipairs(Controller.Menus) do
        if other.ParentMenu == menu then
            other.ParentMenu = nil
        end
    end
    if Controller.MainMenu == menu then
        Controller.MainMenu = Controller.Menus[1]
    end
    -- The player was looking at it, so put them somewhere.
    if was_open and parent and not removed[parent] and contains(Controller.Menus, parent) then
        parent:OpenMenu()
    end
end

-- Removes the menu and every menu only reachable through its rows.
function Controller.RemoveMenu(menu)
    if menu then
        remove_menu(menu, {})
    end
end

function Controller.RemoveAllMenus()
    for _, menu in ipairs(table.move(Controller.Menus, 1, #Controller.Menus, 1, {})) do
        Controller.RemoveMenu(menu)
    end
    Controller.Menus = {}
    visible_menus = {}
    menu_buttons = {}
    Controller.MainMenu = nil
    Ticks.reevaluate()
end

-- Called by Menu:SetVisible only.
function Controller.set_visible(menu, visible)
    remove_value(visible_menus, menu)
    if visible then
        visible_menus[#visible_menus + 1] = menu
    end
end

function Controller.GetCurrentMenu()
    return visible_menus[1]
end

function Controller.IsAnyMenuOpen()
    return #visible_menus ~= 0
end

function Controller.CloseAllMenus()
    for _, menu in ipairs(table.move(Controller.Menus, 1, #Controller.Menus, 1, {})) do
        if menu.Visible then
            menu:CloseMenu()
        end
    end
end

local function console_likely_open()
    return not IsControlEnabled(0, C.CONSOLE_PROBE)
end

function Controller.AreMenuButtonsEnabled()
    return Controller.IsAnyMenuOpen()
        and not FrameState.is_pause_menu_active()
        and FrameState.is_screen_faded_in()
        and not FrameState.is_player_switch_in_progress()
        and not Controller.DisableMenuButtons
        and not FrameState.is_dead()
        and not console_likely_open()
end

-- Something a description is built from that MenuAPI does not own changed.
function Controller.RefreshNui()
    Nui.invalidate()
end

-- Drawing ----------------------------------------------------------------------------

local function can_draw()
    return FrameState.is_screen_faded_in()
        and not FrameState.is_pause_menu_active()
        and not FrameState.is_dead()
        and not FrameState.is_player_switch_in_progress()
end

local function disable(control)
    DisableControlAction(0, control, false)
end

local function disable_controls()
    local menu = Controller.GetCurrentMenu()
    if not menu then
        return
    end
    if FrameState.is_dead() then
        Controller.CloseAllMenus()
        return
    end

    local in_vehicle = FrameState.is_in_vehicle()
    if not IsInputDisabled(2) then
        disable(C.MULTIPLAYER_INFO)
        if in_vehicle then
            disable(C.VEHICLE_HEADLIGHT)
            disable(C.VEHICLE_DUCK)
            -- Toggles boost in some DLC vehicles, and select is on the same button.
            disable(C.VEHICLE_FLY_TRANSFORM)
        end
    else
        -- Escape would open the pause menu; P still does.
        disable(C.FRONTEND_PAUSE_ALTERNATE)
        -- The scroll wheel changes weapons only while TAB shows the wheel.
        if not IsControlPressed(0, C.SELECT_WEAPON) then
            DisableControlAction(24, C.SELECT_NEXT_WEAPON, false)
            DisableControlAction(24, C.SELECT_PREV_WEAPON, false)
        end
    end
    -- Controller only: on keyboard a disabled control never reads as pressed,
    -- which would break the TAB + wheel check above.
    if Items.holds_value(menu:GetCurrentMenuItem()) and not IsInputDisabled(2) then
        disable(C.SELECT_WEAPON)
    end

    for _, control in ipairs({
        C.RADIO_WHEEL_LEFT_RIGHT,
        C.RADIO_WHEEL_UP_DOWN,
        C.VEHICLE_NEXT_RADIO,
        C.VEHICLE_RADIO_WHEEL,
        C.VEHICLE_PREV_RADIO,
        C.PHONE,
        C.PHONE_CANCEL,
        C.PHONE_DOWN,
        C.PHONE_LEFT,
        C.PHONE_RIGHT,
        C.ATTACK,
        C.ATTACK2,
        C.MELEE_ATTACK1,
        C.MELEE_ATTACK2,
        C.MELEE_ATTACK_ALTERNATE,
        C.MELEE_ATTACK_HEAVY,
        C.MELEE_ATTACK_LIGHT,
        C.VEHICLE_ATTACK,
        C.VEHICLE_ATTACK2,
        C.VEHICLE_FLY_ATTACK,
        C.VEHICLE_PASSENGER_ATTACK,
        C.AIM,
        C.VEHICLE_AIM,
        C.SELECT_NEXT_WEAPON,
        C.SELECT_PREV_WEAPON,
        -- The default M toggle and the controller toggle both sit on this.
        C.INTERACTION_MENU,
    }) do
        disable(control)
    end
    if in_vehicle then
        disable(C.VEHICLE_SELECT_NEXT_WEAPON)
        disable(C.VEHICLE_SELECT_PREV_WEAPON)
        disable(C.VEHICLE_CIN_CAM)
    end
end

local function process_menus()
    Nui.ensure_layout()
    if not can_draw() then
        Nui.hide()
        return
    end
    disable_controls()
    local menu = Controller.GetCurrentMenu()
    if not menu then
        Nui.hide()
        return
    end
    if Controller.DontOpenAnyMenu then
        if menu.Visible and not menu.IgnoreDontOpenMenus then
            menu:CloseMenu()
        end
        Nui.hide()
        return
    end
    if not menu.Visible then
        Nui.hide()
        return
    end
    menu:ProcessKeyBindings()
    Nui.send_changes(menu)
end

local function refresh_textures()
    if not Sprites.cached() then
        Sprites.request_all(Sprites.dictionaries())
    end
    Nui.request_pending_textures()
end

local function unload_assets()
    Sprites.release_all(Sprites.dictionaries())
end

-- The menu whose key bindings the draw tick processes this frame.
local function menu_reading_key_bindings()
    if not can_draw() or Controller.DontOpenAnyMenu then
        return nil
    end
    local menu = Controller.GetCurrentMenu()
    return menu and menu.Visible and menu or nil
end

-- Buttons ----------------------------------------------------------------------------

local function process_main_buttons()
    -- Always drained, so a press the menu could not act on is dropped.
    local select_pressed = Input.consume_select()
    local back_pressed = Input.consume_back()
    Input.drain_unhandled(menu_reading_key_bindings())

    if FrameState.is_pause_menu_active() then
        return
    end
    local menu = Controller.GetCurrentMenu()
    if not menu or Controller.DontOpenAnyMenu then
        return
    end
    DisableControlAction(0, C.MULTIPLAYER_INFO, false)
    if Controller.PreventExitingMenu then
        disable(C.FRONTEND_PAUSE)
        disable(C.FRONTEND_PAUSE_ALTERNATE)
    end
    if not menu.Visible or not Controller.AreMenuButtonsEnabled() then
        return
    end
    if select_pressed then
        if menu:Size() > 0 then
            menu:SelectItem(menu.CurrentIndex)
        end
    elseif back_pressed and not Controller.DisableBackButton then
        -- A frame later, so the cinematic camera button is not re-enabled
        -- before the menu closes.
        Wait(0)
        -- A submenu can always go back; a top level menu only closes when
        -- the resource allows it.
        if menu.ParentMenu ~= nil or not Controller.PreventExitingMenu then
            menu:GoBack()
        end
    end
end

-- Holding a direction repeats it, faster the longer it is held. Paging is
-- slower and never speeds up, or a held key would run through hundreds of
-- pages.
local function hold_repeat(menu, step, held, paging)
    step(menu)
    local time = GetGameTimer()
    local times = 0
    local delay = paging and PAGE_REPEAT_FIRST_DELAY or 200
    while held() and Controller.AreMenuButtonsEnabled() do
        -- Re-read every frame: the menu can close from anywhere meanwhile.
        local open = Controller.GetCurrentMenu()
        if not open then
            break
        end
        menu = open
        if GetGameTimer() - time > delay then
            times = times + 1
            if paging then
                delay = PAGE_REPEAT_DELAY
            elseif times > 60 then
                delay = 25
            elseif times > 25 then
                delay = 50
            elseif times > 5 then
                delay = 100
            elseif times > 2 then
                delay = 150
            end
            step(menu)
            time = GetGameTimer()
        end
        Wait(0)
    end
end

local function go_up(menu)
    menu:GoUp()
end

local function go_down(menu)
    menu:GoDown()
end

local function go_left(menu)
    menu:GoLeft()
end

local function go_right(menu)
    menu:GoRight()
end

local function process_directional_buttons()
    local enabled = Controller.AreMenuButtonsEnabled()
    local scroll_up = Input.consume_scroll_up()
    local scroll_down = Input.consume_scroll_down()
    if not enabled then
        return
    end
    local menu = Controller.GetCurrentMenu()
    if not menu or Controller.DontOpenAnyMenu or menu:Size() < 1 or not menu.Visible then
        return
    end
    for _ = 1, scroll_up do
        menu:GoUp()
    end
    for _ = 1, scroll_down do
        menu:GoDown()
    end

    if Input.up_held() then
        hold_repeat(menu, go_up, Input.up_held, false)
    elseif Input.down_held() then
        hold_repeat(menu, go_down, Input.down_held, false)
    elseif Input.left_held() or Input.right_held() then
        local item = menu:GetCurrentMenuItem()
        -- A page move belongs to the menu, so a locked row does not stop it.
        local paging = menu:IsPageNavigation(item)
        if item == nil or (not item.Enabled and not paging) then
            return
        end
        if Input.left_held() then
            hold_repeat(menu, go_left, Input.left_held, paging)
        else
            hold_repeat(menu, go_right, Input.right_held, paging)
        end
    end
end

local function open_main_menu()
    local main = Controller.MainMenu or Controller.Menus[1]
    if main then
        main:OpenMenu()
    end
end

local function process_toggle()
    Input.poll_controller_toggle_hold(Controller.EnableMenuToggleKeyOnController)
    -- Drained every frame, so a press from while the menu could not open does
    -- not open it later. Checked first, so an idle frame costs nothing.
    if not Input.consume_toggle() then
        return
    end
    if
        FrameState.is_pause_menu_active()
        or IsPauseMenuRestarting()
        or not FrameState.is_screen_faded_in()
        or FrameState.is_player_switch_in_progress()
        or FrameState.is_dead()
        or Controller.DisableMenuButtons
    then
        return
    end
    if Controller.IsAnyMenuOpen() then
        if not Controller.PreventExitingMenu then
            Controller.GetCurrentMenu():CloseMenu()
        end
        return
    end
    if not Controller.DontOpenAnyMenu then
        open_main_menu()
    end
end

-- Keeps the menu from reacting while the onscreen keyboard is open, and for
-- 300 ms after, so the key that closed it does not also act on the menu.
local function disable_buttons_while_typing()
    if FrameState.onscreen_keyboard() ~= 0 then
        return
    end
    local previous = Controller.DisableMenuButtons
    while UpdateOnscreenKeyboard() == 0 do
        Wait(0)
        Controller.DisableMenuButtons = true
    end
    local timer = GetGameTimer()
    while GetGameTimer() - timer < 300 do
        Wait(0)
        Controller.DisableMenuButtons = true
    end
    Controller.DisableMenuButtons = previous
end

-- Instructional buttons ----------------------------------------------------------------

local function can_show_instructional_buttons(menu)
    return menu.Visible
        and menu.EnableInstructionalButtons
        and not FrameState.is_player_switch_in_progress()
        and not FrameState.is_dead()
        and FrameState.is_screen_faded_in()
        and not IsWarningMessageActive()
        and FrameState.onscreen_keyboard() ~= 0
end

local function set_slot(slot, button, text)
    BeginScaleformMovieMethod(scaleform, 'SET_DATA_SLOT')
    ScaleformMovieMethodAddParamInt(slot)
    PushScaleformMovieMethodParameterString(button)
    PushScaleformMovieMethodParameterString(text)
    EndScaleformMovieMethod()
end

local function fill_slots(menu)
    BeginScaleformMovieMethod(scaleform, 'CLEAR_ALL')
    EndScaleformMovieMethod()
    Input.refresh_icons()

    local slot = 0
    local function add(button, text)
        set_slot(slot, button, text)
        slot = slot + 1
    end

    if menu.ShowSelectInstructionalButton then
        add(Input.select_button(), menu.SelectButtonText)
    end
    if menu.ShowBackInstructionalButton then
        add(Input.back_button(), menu.BackButtonText)
    end
    local item = menu:GetCurrentMenuItem()
    if menu.ShowChangeValueInstructionalButton and Items.holds_value(item) and item.Enabled then
        add(Input.left_button() .. ICON_SEPARATOR .. Input.right_button(), menu.ChangeValueButtonText)
    elseif menu:Paginated() and menu.ShowPageInstructionalButtons and menu:PageCount() > 1 then
        -- Only worth a hint when there is more than one page.
        add(Input.left_button(), menu.PreviousPageButtonText)
        add(Input.right_button(), menu.NextPageButtonText)
    end
    for _, entry in ipairs(menu.KeyBindingHandlers) do
        local icon = entry.ButtonText and entry.ButtonText ~= '' and entry.Binding:icon() or ''
        -- A binding with no icon on this device is a label nobody can find.
        if icon ~= '' then
            add(icon, entry.ButtonText)
        end
    end
    for _, button in ipairs(menu.CustomInstructionalButtons) do
        add(button.controlString, button.instructionText)
    end

    BeginScaleformMovieMethod(scaleform, 'DRAW_INSTRUCTIONAL_BUTTONS')
    ScaleformMovieMethodAddParamInt(0)
    EndScaleformMovieMethod()
    instructional_menu, instructional_item = menu, item
end

local function draw_instructional_buttons()
    local menu = Controller.GetCurrentMenu()
    if not menu or not can_show_instructional_buttons(menu) or not HasScaleformMovieLoaded(scaleform) then
        return
    end
    if menu ~= instructional_menu or menu:GetCurrentMenuItem() ~= instructional_item then
        fill_slots(menu)
    end
    DrawScaleformMovieFullscreen(scaleform, 255, 255, 255, 255, 0)
end

local function dispose_instructional_buttons()
    if HasScaleformMovieLoaded(scaleform) then
        SetScaleformMovieAsNoLongerNeeded(scaleform)
    end
    scaleform = 0
    instructional_menu = nil
end

-- On a slow loop: icons only change when the player switches device or
-- rebinds a key. Drawing still happens every frame.
local function configure_instructional_buttons()
    local menu = Controller.GetCurrentMenu()
    if not menu or not can_show_instructional_buttons(menu) then
        dispose_instructional_buttons()
        return
    end
    if not HasScaleformMovieLoaded(scaleform) then
        scaleform = RequestScaleformMovie('INSTRUCTIONAL_BUTTONS')
        while not HasScaleformMovieLoaded(scaleform) do
            Wait(0)
        end
    end
    fill_slots(menu)
end

-- Startup ----------------------------------------------------------------------------

local initialized = false

function Controller.init()
    if initialized then
        return
    end
    initialized = true

    Ticks.init(Input.prefix())
    Sprites.init()
    -- A frame later, so every script has had the chance to set
    -- MenuToggleKeyDefault before the key mappings are registered.
    CreateThread(function()
        Wait(0)
        Input.register(Controller)
    end)

    local open = Controller.IsAnyMenuOpen
    -- Every tick but the toggle only runs while a menu is open, so a closed
    -- menu costs no natives at all.
    Ticks.register('Menu.Layout', Nui.refresh_layout, {
        rate = LAYOUT_REFRESH_MS,
        condition = open,
        on_started = Nui.refresh_layout,
    })
    Ticks.register('Menu.Textures', refresh_textures, {
        rate = TEXTURE_REFRESH_MS,
        condition = open,
        on_stopped = unload_assets,
    })
    Ticks.register('Menu.Draw', process_menus, { condition = open, on_stopped = Nui.hide })
    Ticks.register('Menu.InstructionalButtons', draw_instructional_buttons, {
        condition = open,
        on_stopped = function()
            dispose_instructional_buttons()
            Input.clear_icons()
        end,
    })
    Ticks.register('Menu.InstructionalButtonsData', configure_instructional_buttons, {
        rate = INSTRUCTIONAL_BUTTONS_CONFIGURE_MS,
        condition = open,
    })
    -- A menu opens from a clean slate, not acting on presses from before.
    Ticks.register('Menu.Select', process_main_buttons, {
        condition = open,
        on_started = function()
            Input.clear_pending()
            Input.clear_held()
        end,
        on_stopped = function()
            Input.clear_held()
            Input.clear_pending()
        end,
    })
    -- Separate from Menu.Select: this one waits inside its hold-to-repeat
    -- loop, and select has to stay responsive meanwhile.
    Ticks.register('Menu.Navigate', process_directional_buttons, { condition = open })
    Ticks.register('Menu.OnscreenKeyboard', disable_buttons_while_typing, { condition = open })
    -- The only tick that always runs. It reads a flag the key mapping sets,
    -- so an idle frame costs no natives.
    Ticks.register('Menu.Toggle', process_toggle)
end

return Controller
