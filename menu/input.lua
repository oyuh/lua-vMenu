-- Ports of MenuAPI/MenuInput.cs, MenuKeyBinding.cs and
-- ticks/InstructionalButtonIcons.cs. Every menu key is a key mapping the
-- player can rebind in the game settings. Command names match the C# build
-- (menuapi:<resource>:<name>), and FiveM stores rebinds per command name, so
-- a player's binds carry over between the two builds.

local Log = require('shared.log')
local FrameState = require('menu.frame_state')

local Input = {}

local KEYBOARD, CONTROLLER, MOUSE, ALTERNATE_KEYBOARD = 1, 2, 3, 4

local CONTROLLER_TOGGLE_HOLD_MS = 400
local MAX_SCROLL_STEPS = 10

-- Game controls, by index.
local SELECT_WEAPON, SELECT_NEXT_WEAPON, SELECT_PREV_WEAPON = 37, 16, 17

-- The game's icon for a key mapper parameter, for when a binding has no
-- icon of its own yet (a fresh install before any rebind).
local DEFAULT_ICONS = {
    UP = 188,
    DOWN = 187,
    LEFT = 174,
    RIGHT = 175,
    RETURN = 201,
    BACK = 202,
    LUP_INDEX = 188,
    LDOWN_INDEX = 187,
    LLEFT_INDEX = 174,
    LRIGHT_INDEX = 175,
    RDOWN_INDEX = 201,
    RRIGHT_INDEX = 202,
    RUP_INDEX = 192,
    RLEFT_INDEX = 193,
    L1_INDEX = 205,
    R1_INDEX = 206,
    L2_INDEX = 207,
    R2_INDEX = 208,
    L3_INDEX = 209,
    R3_INDEX = 210,
    SELECT_INDEX = 217,
    START_INDEX = 199,
}

local prefix

-- The control id FiveM gives a key mapping: its command hash with the top bit
-- set, as a signed 32-bit number.
local function binding_control(command)
    local value = (GetHashKey(command) | 0x80000000) & 0xFFFFFFFF
    if value >= 0x80000000 then
        value = value - 0x100000000
    end
    return value
end

Input.binding_control = binding_control

local function pad_command(command)
    return command .. ':pad'
end

local function mouse_command(command)
    return command .. ':mouse'
end

-- Bindings ---------------------------------------------------------------------------

local Binding = {}
Binding.__index = Binding

local function new_binding(name, command)
    return setmetatable({
        name = name,
        command = command,
        keyboard_control = binding_control('+' .. command),
        controller_control = binding_control('+' .. pad_command(command)),
        keyboard_default = '',
        controller_default = '',
        held_by = { false, false, false, false },
        armed = { false, false, false, false },
        pressed = false,
        released = false,
    }, Binding)
end

function Binding:held()
    for device = 1, 4 do
        if self.held_by[device] then
            return true
        end
    end
    return false
end

function Binding:press(device)
    self.held_by[device] = true
    self.armed[device] = true
    self.pressed = true
end

-- A release only counts after a press seen on the same device, so a key held
-- while the menu opened does not fire when it is let go.
function Binding:release(device)
    self.held_by[device] = false
    if not self.armed[device] then
        return
    end
    self.armed[device] = false
    self.released = true
end

function Binding:consume_press()
    local pending = self.pressed
    self.pressed = false
    return pending
end

function Binding:consume_release()
    local pending = self.released
    self.released = false
    return pending
end

function Binding:clear_held()
    self.held_by = { false, false, false, false }
end

function Binding:clear_pending()
    self.armed = { false, false, false, false }
    self.pressed = false
    self.released = false
end

function Binding:icon()
    return Input.icon_for(self)
end

local own = {}
local custom = {}
local custom_order = {}
local up, down, left, right, select_, back

local toggle_pressed = false
local controller_toggle_since = -1
local controller_toggle_fired = false
local scroll_up_steps, scroll_down_steps = 0, 0
local registered = false

local function register_hold_commands(binding, command, device)
    RegisterCommand('+' .. command, function()
        binding:press(device)
    end, false)
    RegisterCommand('-' .. command, function()
        binding:release(device)
    end, false)
end

local function register_hold(binding, description, keyboard_key, controller_button)
    binding.keyboard_default = keyboard_key
    binding.controller_default = controller_button
    register_hold_commands(binding, binding.command, KEYBOARD)
    RegisterKeyMapping('+' .. binding.command, description, 'keyboard', keyboard_key)
    local pad = pad_command(binding.command)
    register_hold_commands(binding, pad, CONTROLLER)
    RegisterKeyMapping('+' .. pad, description .. ' (controller)', 'PAD_ANALOGBUTTON', controller_button)
end

local function register_alternate(binding, description, keyboard_key)
    local alternate = binding.command .. ':alt'
    register_hold_commands(binding, alternate, ALTERNATE_KEYBOARD)
    RegisterKeyMapping('+' .. alternate, description .. ' (alternate)', 'keyboard', keyboard_key)
end

local function register_mouse_hold(binding, description, mouse_button)
    local mouse = mouse_command(binding.command)
    register_hold_commands(binding, mouse, MOUSE)
    RegisterKeyMapping('+' .. mouse, description .. ' (mouse)', 'MOUSE_BUTTON', mouse_button)
end

-- The wheel is only a menu scroll while the weapon wheel is not using it.
local function using_weapon_wheel()
    if FrameState.is_in_vehicle() or not IsControlPressed(0, SELECT_WEAPON) then
        return false
    end
    return IsControlPressed(0, SELECT_NEXT_WEAPON) or IsControlPressed(0, SELECT_PREV_WEAPON)
end

local function register_scroll(binding, description, wheel_direction, is_up)
    local mouse = mouse_command(binding.command)
    RegisterCommand(mouse, function()
        if using_weapon_wheel() then
            return
        end
        if is_up then
            scroll_up_steps = math.min(scroll_up_steps + 1, MAX_SCROLL_STEPS)
        else
            scroll_down_steps = math.min(scroll_down_steps + 1, MAX_SCROLL_STEPS)
        end
    end, false)
    RegisterKeyMapping(mouse, description .. ' (mouse wheel)', 'MOUSE_WHEEL', wheel_direction)
end

local function register_toggle(Controller, keyboard_key)
    -- Not registered at all when off, so the key binding settings do not list
    -- a key that does nothing.
    if not Controller.EnableMenuToggleKey then
        return
    end
    local command = prefix .. 'toggle'
    RegisterCommand(command, function()
        toggle_pressed = Controller.EnableMenuToggleKey
    end, false)
    RegisterKeyMapping(command, 'Open / close menu', 'keyboard', keyboard_key)
    local pad = pad_command(command)
    RegisterCommand('+' .. pad, function()
        controller_toggle_since = GetGameTimer()
        controller_toggle_fired = false
    end, false)
    RegisterCommand('-' .. pad, function()
        controller_toggle_since = -1
    end, false)
    RegisterKeyMapping('+' .. pad, 'Open / close menu (controller)', 'PAD_ANALOGBUTTON', 'SELECT_INDEX')
end

-- Instructional button icons -----------------------------------------------------------
-- GetControlInstructionalButton is cached until the player switches between
-- keyboard and controller, or leaves the pause menu (where rebinds happen).

local icons = {}
local icons_refreshed = false
local pause_menu_was_active = false
local using_keyboard = true

function Input.refresh_icons()
    -- IsInputDisabled(2) is IS_USING_KEYBOARD_AND_MOUSE under the name every
    -- CfxLua build defines (the original port relies on it the same way).
    local keyboard = IsInputDisabled(2)
    local pause_active = FrameState.is_pause_menu_active()
    local left_pause_menu = pause_menu_was_active and not pause_active
    pause_menu_was_active = pause_active
    if icons_refreshed and keyboard == using_keyboard and not left_pause_menu then
        return
    end
    using_keyboard = keyboard
    icons_refreshed = true
    icons = {}
end

local function icon_for_control(control)
    if not icons_refreshed then
        Input.refresh_icons()
    end
    local icon = icons[control]
    if icon == nil then
        icon = GetControlInstructionalButton(0, control, true)
        icons[control] = icon
    end
    return icon
end

function Input.clear_icons()
    icons = {}
    icons_refreshed = false
    pause_menu_was_active = false
end

local function default_icon(parameter)
    local control = DEFAULT_ICONS[parameter]
    return control and icon_for_control(control) or ''
end

function Input.icon_for(binding)
    if not icons_refreshed then
        Input.refresh_icons()
    end
    local icon = icon_for_control(using_keyboard and binding.keyboard_control or binding.controller_control)
    local unbound = icon_for_control(binding_control('+' .. prefix .. 'unbound'))
    if icon ~= nil and icon ~= '' and icon ~= unbound then
        return icon
    end
    return default_icon(using_keyboard and binding.keyboard_default or binding.controller_default)
end

-- Public input API ---------------------------------------------------------------------

function Input.prefix()
    return prefix
end

-- Waits a frame before registering in the C# build, so a resource can set
-- MenuToggleKeyDefault first. The controller calls this from a thread for the
-- same reason.
function Input.register(Controller)
    if registered then
        return
    end
    registered = true
    local toggle_key = Controller.MenuToggleKeyDefault
    if toggle_key == nil or toggle_key:match('^%s*$') then
        toggle_key = 'M'
    end
    register_toggle(Controller, toggle_key)
    register_hold(up, 'Menu up', 'UP', 'LUP_INDEX')
    register_hold(down, 'Menu down', 'DOWN', 'LDOWN_INDEX')
    register_hold(left, 'Menu left', 'LEFT', 'LLEFT_INDEX')
    register_hold(right, 'Menu right', 'RIGHT', 'LRIGHT_INDEX')
    register_hold(select_, 'Menu select', 'RETURN', 'RDOWN_INDEX')
    register_hold(back, 'Menu back', 'BACK', 'RRIGHT_INDEX')
    register_mouse_hold(select_, 'Menu select', 'MOUSE_LEFT')
    register_mouse_hold(back, 'Menu back', 'MOUSE_RIGHT')
    register_alternate(back, 'Menu back', 'ESCAPE')
    register_scroll(up, 'Menu up', 'IOM_WHEEL_UP', true)
    register_scroll(down, 'Menu down', 'IOM_WHEEL_DOWN', false)
    RegisterCommand(prefix .. 'buttons', Input.dump_buttons, false)
end

function Input.register_custom(name, description, keyboard_key, controller_button)
    local existing = custom[name]
    if existing then
        return existing
    end
    local binding = new_binding(name, prefix .. name)
    custom[name] = binding
    custom_order[#custom_order + 1] = binding
    binding.keyboard_default = keyboard_key
    register_hold_commands(binding, binding.command, KEYBOARD)
    RegisterKeyMapping('+' .. binding.command, description, 'keyboard', keyboard_key)
    if controller_button == nil or controller_button:match('^%s*$') then
        return binding
    end
    binding.controller_default = controller_button
    local pad = pad_command(binding.command)
    register_hold_commands(binding, pad, CONTROLLER)
    RegisterKeyMapping('+' .. pad, description .. ' (controller)', 'PAD_ANALOGBUTTON', controller_button)
    return binding
end

function Input.up_held()
    return up:held()
end

function Input.down_held()
    return down:held()
end

function Input.left_held()
    return left:held()
end

function Input.right_held()
    return right:held()
end

function Input.clear_held()
    for _, binding in ipairs(own) do
        binding:clear_held()
    end
    for _, binding in ipairs(custom_order) do
        binding:clear_held()
    end
end

function Input.clear_pending()
    for _, binding in ipairs(own) do
        binding:clear_pending()
    end
    for _, binding in ipairs(custom_order) do
        binding:clear_pending()
    end
    scroll_up_steps, scroll_down_steps = 0, 0
end

-- Throws away custom presses no open menu is going to handle, so they do not
-- fire later.
function Input.drain_unhandled(menu)
    for _, binding in ipairs(custom_order) do
        if not (menu and menu:Handles(binding)) then
            binding:clear_pending()
        end
    end
end

function Input.poll_controller_toggle_hold(enabled)
    if controller_toggle_since < 0 or controller_toggle_fired or not enabled then
        return
    end
    if GetGameTimer() - controller_toggle_since < CONTROLLER_TOGGLE_HOLD_MS then
        return
    end
    controller_toggle_fired = true
    toggle_pressed = true
end

function Input.consume_toggle()
    local pressed = toggle_pressed
    toggle_pressed = false
    return pressed
end

function Input.consume_select()
    return select_:consume_release()
end

function Input.consume_back()
    return back:consume_release()
end

function Input.consume_scroll_up()
    local steps = scroll_up_steps
    scroll_up_steps = 0
    return steps
end

function Input.consume_scroll_down()
    local steps = scroll_down_steps
    scroll_down_steps = 0
    return steps
end

function Input.select_button()
    return Input.icon_for(select_)
end

function Input.back_button()
    return Input.icon_for(back)
end

function Input.left_button()
    return Input.icon_for(left)
end

function Input.right_button()
    return Input.icon_for(right)
end

function Input.dump_buttons()
    Input.clear_icons()
    local device = IsInputDisabled(2) and 'keyboard' or 'a controller'
    local unbound = icon_for_control(binding_control('+' .. prefix .. 'unbound'))
    Log.info(('[MenuAPI] instructional button icons, on %s:'):format(device))
    Log.info(('[MenuAPI]   a binding with no icon looks like "%s"'):format(unbound))
    local all = table.move(own, 1, #own, 1, {})
    table.move(custom_order, 1, #custom_order, #all + 1, all)
    for _, binding in ipairs(all) do
        Log.info(
            ('[MenuAPI]   %s: keyboard "%s", controller "%s", defaults %s "%s" and %s "%s"'):format(
                binding.command,
                icon_for_control(binding.keyboard_control),
                icon_for_control(binding.controller_control),
                binding.keyboard_default,
                default_icon(binding.keyboard_default),
                binding.controller_default,
                default_icon(binding.controller_default)
            )
        )
    end
end

-- Builds the built-in bindings. Called once at load with the resource name.
function Input.setup(resource)
    prefix = ('menuapi:%s:'):format(resource:lower())
    up = new_binding('up', prefix .. 'up')
    down = new_binding('down', prefix .. 'down')
    left = new_binding('left', prefix .. 'left')
    right = new_binding('right', prefix .. 'right')
    select_ = new_binding('select', prefix .. 'select')
    back = new_binding('back', prefix .. 'back')
    own = { up, down, left, right, select_, back }
end

Input.setup(GetCurrentResourceName())

return Input
