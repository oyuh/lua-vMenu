-- Ports of vMenu.Enhanced.MenuFramework/Notifications.cs and
-- NotificationEvents.cs: toasts drawn by ui/notifications.js above the
-- minimap. Any resource can raise one with the vmenu:notify event.

local Json = require('shared.json_compat')
local Localization = require('shared.localization')
local Hud = require('client.framework.hud')
local Ticks = require('menu.ticks')

local Notifications = {}

Notifications.DEFAULT_DURATION_MS = 8500
Notifications.SPAWN_DURATION_MS = 4000

local VISIBILITY_CHECK_MS = 500
-- Thirty seconds of waiting for a spawn, then it shows regardless.
local MAX_VISIBILITY_CHECKS = 60
-- The grace the page hands a frozen message when the pause menu closes.
local PAUSE_GRACE_MS = 2000
-- Covers the fade the page plays after a message's time is up.
local EXIT_GRACE_MS = 500
local PAUSE_CHECK_INTERVAL_MS = 100
local PAUSED_MESSAGE = '{"type":"notify_pause","paused":true}'
local RESUMED_MESSAGE = '{"type":"notify_pause","paused":false}'

local NOTIFY_EVENT = 'vmenu:notify'
local MIN_EVENT_DURATION_MS = 5000
local MAX_EVENT_DURATION_MS = 30000

local STYLES = { info = true, success = true, warning = true, error = true }

local pause_tick
local paused = false
-- Game time by which every message sent so far has had its say.
local live_until = 0
local polled_at = 0

-- The page holds its messages while the pause menu is up, so the watch window
-- holds with them, and the page is told when the pause menu opens or closes.
local function poll_pause()
    local now = GetGameTimer()
    local is_paused = IsPauseMenuActive()
    if is_paused then
        live_until = live_until + (now - polled_at)
    end
    polled_at = now
    if is_paused ~= paused then
        paused = is_paused
        if not is_paused then
            live_until = live_until + PAUSE_GRACE_MS
        end
        SendNuiMessage(is_paused and PAUSED_MESSAGE or RESUMED_MESSAGE)
    end
    -- Conditions only re-run on demand, so the loop notices it is done.
    if now >= live_until then
        Ticks.reevaluate()
    end
end

-- An estimate: the page owns the timers, this side only needs to know when
-- watching for the pause menu is pointless.
local function watch(duration_ms, is_paused)
    local until_time = GetGameTimer() + duration_ms + EXIT_GRACE_MS
    if until_time > live_until then
        live_until = until_time
    end
    -- Registered on the first message, so a client that never notifies never
    -- runs the loop.
    if not pause_tick then
        pause_tick = Ticks.register('Notifications.Pause', poll_pause, {
            rate = PAUSE_CHECK_INTERVAL_MS,
            condition = function()
                return live_until > GetGameTimer()
            end,
            on_started = function()
                polled_at = GetGameTimer()
            end,
        })
    end
    paused = is_paused
    Ticks.reevaluate()
end

-- style: 'info', 'success', 'warning' or 'error'. source names another
-- resource that raised it, shown as "From: <source>".
function Notifications.show(style, text, duration_ms, source)
    local message = Localization.resolve(text)
    if message:match('^%s*$') then
        return
    end
    duration_ms = duration_ms or Notifications.DEFAULT_DURATION_MS
    local is_paused = IsPauseMenuActive()
    local left, bottom, width = Hud.above_minimap()
    SendNuiMessage(Json.encode({
        type = 'notify',
        style = STYLES[style] and style or 'info',
        text = message,
        duration = duration_ms,
        footer = source,
        paused = is_paused,
        anchor = { left = Hud.fraction(left), bottom = Hud.fraction(bottom), width = Hud.fraction(width) },
    }))
    watch(duration_ms, is_paused)
end

function Notifications.info(text, duration_ms)
    Notifications.show('info', text, duration_ms)
end

function Notifications.success(text, duration_ms)
    Notifications.show('success', text, duration_ms)
end

function Notifications.warning(text, duration_ms)
    Notifications.show('warning', text, duration_ms)
end

function Notifications.error(text, duration_ms)
    Notifications.show('error', text, duration_ms)
end

-- For messages raised before the player can see them, such as at startup.
-- Shown after thirty seconds regardless: a message the player might miss beats
-- one that is never sent.
function Notifications.show_when_visible(style, text, duration_ms)
    CreateThread(function()
        for _ = 1, MAX_VISIBILITY_CHECKS do
            if NetworkIsSessionStarted() and not IsScreenFadedOut() then
                break
            end
            Wait(VISIBILITY_CHECK_MS)
        end
        Notifications.show(style, text, duration_ms)
    end)
end

-- vmenu:notify(message, duration_ms, style) from any client resource.
function Notifications.register_events()
    AddEventHandler(NOTIFY_EVENT, function(message, duration_ms, style)
        local resource = GetInvokingResource()
        if resource == nil or resource == '' or resource == GetCurrentResourceName() then
            resource = nil
        end
        duration_ms = tonumber(duration_ms) or 0
        if duration_ms <= 0 then
            duration_ms = Notifications.DEFAULT_DURATION_MS
        end
        duration_ms = math.max(MIN_EVENT_DURATION_MS, math.min(MAX_EVENT_DURATION_MS, duration_ms))
        local wanted = type(style) == 'string' and style:lower() or 'info'
        -- A literal: a resource's message is never looked up as a translation key.
        Notifications.show(wanted, tostring(message or ''), duration_ms, resource)
    end)
end

return Notifications
