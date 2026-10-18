-- Port of vMenu.Enhanced.Menus/World/WorldTime.cs: puts the game clock and
-- date where the world state says. A new offset, or the clock unfreezing,
-- eases over the server's transition time instead of jumping.

local Clock = require('shared.world.clock')
local Ticks = require('menu.ticks')
local State = require('client.menus.world.state')

local Time = {}

local STEADY_INTERVAL_MS = 100
local NORMAL_MS_PER_GAME_MINUTE = 2000
local DAY = Clock.SECONDS_PER_GAME_DAY

local t = {
    shown_day = nil,
    shown_offset = 0.0,
    ramp_from = 0.0,
    ramp_to = 0.0,
    ramp_started = 0,
    started = false,
    ramping = false,
    was_frozen = false,
    catching_up = false,
    catch_up_from = 0.0,
    catch_up_started = 0,
    frozen_anchor = 0.0,
}

function Time.is_transitioning()
    return t.ramping or t.catching_up
end

-- The shorter way round the clock, so 23:00 to 01:00 goes forward two hours.
local function shortest(delta)
    local wrapped = delta % DAY
    return wrapped > DAY / 2 and wrapped - DAY or wrapped
end

local function progress(started)
    local seconds = State.time_transition_seconds()
    if seconds <= 0 then
        return 1.0
    end
    return (GetGameTimer() - started) / 1000.0 / seconds
end

local function ramp()
    local target = State.time_offset
    if not t.started then
        t.started, t.ramping = true, false
        t.shown_offset, t.ramp_from, t.ramp_to = target, target, target
        return target
    end
    if math.abs(target - t.ramp_to) > 0.5 then
        t.ramp_from, t.ramp_to = t.shown_offset, target
        t.ramp_started, t.ramping = GetGameTimer(), true
    end
    local done = progress(t.ramp_started)
    if done >= 1.0 then
        t.ramping, t.shown_offset = false, t.ramp_to
        return t.shown_offset
    end
    t.shown_offset = t.ramp_from + shortest(t.ramp_to - t.ramp_from) * Clock.smooth(done)
    return t.shown_offset
end

-- While frozen the clock stands still; unfreezing eases it forward to now.
local function catch_up()
    local frozen = State.is_time_frozen()
    if frozen ~= t.was_frozen then
        t.was_frozen, t.catching_up = frozen, false
        if not frozen then
            local speed = State.time_speed()
            t.catch_up_from = -(
                (Clock.second_of_day(State.unix_seconds(), speed) - Clock.second_of_day(t.frozen_anchor, speed)) % DAY
            )
            t.catch_up_started = GetGameTimer()
            t.catching_up = t.catch_up_from < -0.5
        end
    end
    if frozen then
        t.frozen_anchor = State.frozen_at
        return 0.0
    end
    if not t.catching_up then
        return 0.0
    end
    local done = progress(t.catch_up_started)
    if done >= 1.0 then
        t.catching_up = false
        return 0.0
    end
    return t.catch_up_from * (1.0 - Clock.smooth(done))
end

local function apply_date(offset)
    local day = Clock.game_day(State.clock_unix_seconds(), offset, State.time_speed()) % Clock.DATE_PERIOD_DAYS
    if day == t.shown_day then
        return
    end
    t.shown_day = day
    local year, month, day_of_month = Clock.from_days(Clock.DATE_EPOCH_DAY + day)
    SetClockDate(day_of_month, month - 1, year)
end

local function apply()
    if not State.has_clock() then
        return
    end
    local offset = ramp() + catch_up()
    local speed = State.time_speed()
    local total = (Clock.second_of_day(State.clock_unix_seconds(), speed) + offset) % DAY
    SetMillisecondsPerGameMinute(math.floor(NORMAL_MS_PER_GAME_MINUTE / speed))
    PauseClock(State.is_time_frozen())
    NetworkOverrideClockTime(math.floor(total / 3600), math.floor(total % 3600 / 60), math.floor(total % 60))
    apply_date(offset)
end

-- Days into the moon's cycle, from the date and time the game shows.
function Time.moon_cycle_days()
    local midnight = Clock.to_unix_seconds(GetClockYear(), GetClockMonth() + 1, GetClockDayOfMonth(), 0, 0, 0)
    local fraction = (GetClockHours() * 3600 + GetClockMinutes() * 60 + GetClockSeconds()) / DAY
    return midnight // DAY - Clock.DATE_EPOCH_DAY + fraction
end

function Time.init()
    Ticks.register('World.Time', apply, {
        rate = function()
            return Time.is_transitioning() and 0 or STEADY_INTERVAL_MS
        end,
        condition = State.time_enabled,
        on_started = function()
            t.started, t.ramping, t.catching_up, t.was_frozen, t.shown_day = false, false, false, false, nil
        end,
        on_stopped = function()
            t.ramping, t.catching_up = false, false
            NetworkClearClockTimeOverride()
            PauseClock(false)
            SetMillisecondsPerGameMinute(NORMAL_MS_PER_GAME_MINUTE)
        end,
    })
    State.on_changed(Ticks.reevaluate)
end

return Time
