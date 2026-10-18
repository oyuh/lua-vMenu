-- Port of vMenu.Enhanced.MenuFramework/MenuArbiter.cs: decides whether a menu
-- opened from outside vMenu's own navigation (a plugin's openMenu) may replace
-- what is open, and keeps a menu that asked not to be closed open, with a
-- hold-to-close escape so a broken plugin cannot trap the player.
--
-- Priorities are 'none', 'low', 'medium' and 'high'. try_open answers with
-- the plugin protocol's own reason strings.

local Log = require('shared.log')
local Json = require('shared.json_compat')
local Localization = require('shared.localization')
local Controller = require('menu.controller')
local Input = require('menu.input')
local Ticks = require('menu.ticks')
local Locks = require('client.framework.locks')
local Registry = require('client.framework.registry')

local Arbiter = {}

local PRIORITIES = { none = 0, low = 1, medium = 2, high = 3 }
local HIGH = PRIORITIES.high
local HOLD_MS = 5000
local CONFIRM_TIMEOUT_MS = 10000
local MAX_PARENT_DEPTH = 32
local ACCEPT_CONTROL = 201
local CANCEL_CONTROL = 202
local HIDE_CARD = '{"type":"menuLock","state":"hidden"}'

-- Set by the plugin host: the resource that owns a menu, or nil.
Arbiter.owner_of = nil

local replacing_handlers = {}
local force_closed_handlers = {}

local session -- { owner, priority }
local lock -- { root, owner, force_closable, button }
local last_seen
local tick
local hold_binding
local hold_started = -1
local confirm_started = -1
local card_shown = false
local toggle_before

-- Unknown names count as low, like upstream.
function Arbiter.priority(name)
    return PRIORITIES[name] or PRIORITIES.low
end

Arbiter.HIGH = HIGH

-- handler(menu) for each menu in the chain a different owner is replacing.
function Arbiter.on_replacing(handler)
    replacing_handlers[#replacing_handlers + 1] = handler
end

-- handler(root) when a menu that asked not to be closed was closed anyway.
function Arbiter.on_force_closed(handler)
    force_closed_handlers[#force_closed_handlers + 1] = handler
end

local function same(left, right)
    if left == nil or right == nil then
        return left == right
    end
    return left:lower() == right:lower()
end

local function owner_of(menu)
    return Arbiter.owner_of and Arbiter.owner_of(menu) or nil
end

local function raise(handlers, menu)
    for _, handler in ipairs(handlers) do
        local ok, err = pcall(handler, menu)
        if not ok then
            Log.error('[Menu] A menu arbiter handler threw: ' .. tostring(err))
        end
    end
end

local function priority_of(owner)
    return session and same(session.owner, owner) and session.priority or PRIORITIES.none
end

local function is_within(menu, root)
    local current = menu
    for _ = 1, MAX_PARENT_DEPTH do
        if current == nil then
            return false
        end
        if current == root then
            return true
        end
        current = current.ParentMenu
    end
    return false
end

-- The toggle key would close a locked or high priority menu behind the
-- arbiter's back, so it is off meanwhile and restored after.
local function apply_flags()
    if lock or (session and session.priority == HIGH) then
        if toggle_before == nil or Controller.EnableMenuToggleKey then
            toggle_before = Controller.EnableMenuToggleKey
        end
        Controller.EnableMenuToggleKey = false
    elseif toggle_before ~= nil then
        Controller.EnableMenuToggleKey = toggle_before
        toggle_before = nil
    end
end

local function hide_card()
    if not card_shown then
        return
    end
    card_shown = false
    SendNuiMessage(HIDE_CARD)
end

local function show_card(state, duration_ms, title_key, text_key)
    SendNuiMessage(Json.encode({
        type = 'menuLock',
        state = state,
        durationMs = duration_ms,
        title = Localization.get(title_key),
        text = Localization.get(text_key),
        accept = Localization.get('framework.forceclose.accept'),
        acceptKey = Localization.get('framework.forceclose.key.select'),
        cancel = Localization.get('framework.forceclose.cancel'),
        cancelKey = Localization.get('framework.forceclose.key.back'),
    }))
    card_shown = true
end

local function reset_hold()
    hold_started = -1
    hide_card()
    if confirm_started < 0 then
        return
    end
    confirm_started = -1
    Locks.release_buttons()
end

local function release_lock()
    if not lock then
        return
    end
    local held = lock
    lock = nil
    if held.button then
        local handlers = held.root.KeyBindingHandlers
        for index = #handlers, 1, -1 do
            if handlers[index] == held.button then
                table.remove(handlers, index)
            end
        end
    end
    Controller.DisableBackButton = false
    apply_flags()
    reset_hold()
end

local function break_lock(held)
    release_lock()
    if held.owner == nil then
        return
    end
    Log.warning(
        ("[Menu] '%s' from '%s' asked not to be closed, but something else closed it."):format(
            tostring(held.root.MenuTitle),
            held.owner
        )
    )
    raise(force_closed_handlers, held.root)
end

local function force_close(held)
    Log.warning(
        ("[Menu] The player forced '%s' from '%s' shut, which asked not to be closed."):format(
            tostring(held.root.MenuTitle),
            tostring(held.owner)
        )
    )
    release_lock()
    session = nil
    apply_flags()
    Controller.CloseAllMenus()
    raise(force_closed_handlers, held.root)
end

local function pressed(control)
    return IsControlJustPressed(0, control) or IsDisabledControlJustPressed(0, control)
end

local function process_hold(held)
    local now = GetGameTimer()
    if confirm_started >= 0 then
        if pressed(ACCEPT_CONTROL) then
            reset_hold()
            force_close(held)
        elseif pressed(CANCEL_CONTROL) or now - confirm_started > CONFIRM_TIMEOUT_MS then
            reset_hold()
        end
        return
    end
    if not (hold_binding and hold_binding:held()) then
        if hold_started >= 0 then
            hold_started = -1
            hide_card()
        end
        return
    end
    if hold_started < 0 then
        hold_started = now
        show_card('holding', HOLD_MS, 'framework.forceclose.title', 'framework.forceclose.holding')
        return
    end
    if now - hold_started < HOLD_MS then
        return
    end
    hold_started = -1
    confirm_started = now
    -- So the accept press does not also select the highlighted row.
    Locks.take_buttons()
    show_card('confirm', CONFIRM_TIMEOUT_MS, 'framework.forceclose.confirm.title', 'framework.forceclose.confirm')
end

local function watch()
    local current = Controller.GetCurrentMenu()
    if current == nil then
        if lock then
            break_lock(lock)
        end
        session = nil
        last_seen = nil
    elseif current ~= last_seen then
        last_seen = current
        if lock and not is_within(current, lock.root) then
            break_lock(lock)
        end
        if session and not same(owner_of(current), session.owner) then
            session = nil
        end
    end
    apply_flags()
    if current == nil or lock == nil then
        return
    end
    local on_root = current == lock.root
    Controller.DisableBackButton = on_root
    if lock.force_closable and on_root then
        process_hold(lock)
    else
        reset_hold()
    end
end

local function ensure_tick()
    if not tick then
        tick = Ticks.register('Menu.Arbiter', watch, {
            condition = function()
                return session ~= nil or lock ~= nil
            end,
        })
    end
    Ticks.reevaluate()
end

local function take_lock(root, owner, force_closable)
    if lock and lock.root == root and same(lock.owner, owner) then
        return
    end
    release_lock()
    local button
    if force_closable then
        hold_binding = hold_binding
            or Input.register_custom(
                'forceclose',
                Localization.get('framework.forceclose.binding'),
                'BACK',
                'RRIGHT_INDEX'
            )
        -- No handler: the tick reads the hold itself, this only shows the hint.
        button = {
            Binding = hold_binding,
            PressType = 'PRESSED',
            ButtonText = Localization.get('framework.forceclose.button'),
        }
        root.KeyBindingHandlers[#root.KeyBindingHandlers + 1] = button
    end
    lock = { root = root, owner = owner, force_closable = force_closable, button = button }
    apply_flags()
    Controller.DisableBackButton = Controller.GetCurrentMenu() == root
    ensure_tick()
end

-- Returns 'opened', 'blockedByLock', 'blockedByPriority' or 'notAllowed'.
function Arbiter.try_open(menu, owner, priority, do_not_close)
    local current = Controller.GetCurrentMenu()
    local same_owner = false
    if current then
        local current_owner = owner_of(current)
        same_owner = same(current_owner, owner)
        if lock and not same(lock.owner, owner) then
            return 'blockedByLock'
        end
        if not same_owner and (priority == PRIORITIES.none or priority < priority_of(current_owner)) then
            return 'blockedByPriority'
        end
    end
    if not Registry.can_open(menu) then
        return 'notAllowed'
    end
    local kept = same_owner and priority_of(owner) or PRIORITIES.none
    if current == nil then
        if lock then
            break_lock(lock)
        end
    else
        if not same_owner then
            raise(replacing_handlers, current)
        end
        if lock and not is_within(menu, lock.root) then
            release_lock()
        end
        Controller.CloseAllMenus()
    end
    session = { owner = owner, priority = math.max(priority, kept) }
    last_seen = menu
    menu:OpenMenu()
    if not menu.Visible then
        release_lock()
        apply_flags()
        return 'notAllowed'
    end
    if do_not_close then
        take_lock(menu, owner, true)
    end
    apply_flags()
    ensure_tick()
    return 'opened'
end

function Arbiter.release_for(owner)
    if lock and same(lock.owner, owner) then
        release_lock()
    end
end

return Arbiter
