-- Ports of vMenu.Enhanced.Data/World/GameClock.cs, CivilTime.cs and
-- MoonCycle.cs. The in-game clock is derived from real UTC seconds, so every
-- client and the server work out the same time without sending it around.

local Clock = {}

Clock.REAL_SECONDS_PER_GAME_HOUR = 120.0
Clock.SECONDS_PER_GAME_DAY = 86400
Clock.NORMAL_SPEED = 1.0
local SLOWEST_SPEED = 0.01
local FASTEST_SPEED = 1000.0
local REAL_SECONDS_PER_GAME_DAY = 24.0 * Clock.REAL_SECONDS_PER_GAME_HOUR

function Clock.clamp_speed(speed)
    if speed ~= speed or speed == nil then
        return Clock.NORMAL_SPEED
    end
    return math.max(SLOWEST_SPEED, math.min(FASTEST_SPEED, speed))
end

function Clock.real_seconds_per_game_hour(speed)
    return Clock.REAL_SECONDS_PER_GAME_HOUR / Clock.clamp_speed(speed)
end

function Clock.second_of_day(unix_seconds, speed)
    local real_seconds_per_day = REAL_SECONDS_PER_GAME_DAY / Clock.clamp_speed(speed)
    return (unix_seconds % real_seconds_per_day) * (Clock.SECONDS_PER_GAME_DAY / real_seconds_per_day)
end

-- How far into a cycle of cycle_length game hours the clock is.
function Clock.cycle_game_hours(unix_seconds, speed, cycle_length)
    local per_hour = Clock.real_seconds_per_game_hour(speed)
    return (unix_seconds % (cycle_length * per_hour)) / per_hour
end

-- The offset that puts a sped up or slowed down clock on real time.
function Clock.real_time_offset(unix_seconds, speed)
    return (Clock.second_of_day(unix_seconds, Clock.NORMAL_SPEED) - Clock.second_of_day(unix_seconds, speed))
        % Clock.SECONDS_PER_GAME_DAY
end

function Clock.game_day(unix_seconds, offset_seconds, speed)
    return math.floor(
        unix_seconds * Clock.clamp_speed(speed) / REAL_SECONDS_PER_GAME_DAY
            + offset_seconds / Clock.SECONDS_PER_GAME_DAY
    )
end

function Clock.smooth(t)
    return t * t * (3.0 - 2.0 * t)
end

-- Civil calendar (Howard Hinnant's days-from-civil). Lua's // floors, so the era
-- needs none of the negative-year adjustment C#'s truncating division does.

function Clock.to_unix_seconds(year, month, day, hour, minute, second)
    local y = year - (month <= 2 and 1 or 0)
    local era = y // 400
    local year_of_era = y - era * 400
    local day_of_year = (153 * (month + (month > 2 and -3 or 9)) + 2) // 5 + day - 1
    local day_of_era = year_of_era * 365 + year_of_era // 4 - year_of_era // 100 + day_of_year
    local days = era * 146097 + day_of_era - 719468
    return days * 86400 + hour * 3600 + minute * 60 + second
end

-- year, month (1-12), day
function Clock.from_days(days)
    local z = days + 719468
    local era = z // 146097
    local day_of_era = z - era * 146097
    local year_of_era = (day_of_era - day_of_era // 1460 + day_of_era // 36524 - day_of_era // 146096) // 365
    local day_of_year = day_of_era - (365 * year_of_era + year_of_era // 4 - year_of_era // 100)
    local mp = (5 * day_of_year + 2) // 153
    local day = day_of_year - (153 * mp + 2) // 5 + 1
    local month = mp + (mp < 10 and 3 or -9)
    local year = year_of_era + era * 400 + (month <= 2 and 1 or 0)
    return year, month, day
end

-- Moon -------------------------------------------------------------------------------

Clock.MOON_CYCLE_DAYS = 55.0
Clock.FULL_MOON_DAY = 27.0
Clock.DATE_PERIOD_DAYS = 385
Clock.DATE_EPOCH_DAY = 10957

Clock.MOON_PHASES = {
    'new',
    'waxingcrescent',
    'firstquarter',
    'waxinggibbous',
    'full',
    'waninggibbous',
    'lastquarter',
    'waningcrescent',
}

local WEEKDAYS = { 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday' }

function Clock.moon_day(cycle_days)
    return cycle_days % Clock.MOON_CYCLE_DAYS
end

local function moon_radians(cycle_days)
    return math.pi * ((Clock.moon_day(cycle_days) - Clock.FULL_MOON_DAY) / Clock.FULL_MOON_DAY)
end

function Clock.moon_degrees(cycle_days)
    return moon_radians(cycle_days) * 180.0 / math.pi
end

function Clock.moon_illumination(cycle_days)
    return (1.0 + math.cos(moon_radians(cycle_days))) / 2.0
end

-- One of MOON_PHASES, which is also the end of its translation key.
function Clock.moon_phase(cycle_days)
    local waxing = Clock.moon_day(cycle_days) < Clock.FULL_MOON_DAY
    local lit = Clock.moon_illumination(cycle_days)
    if lit < 0.03 then
        return 'new'
    elseif lit < 0.47 then
        return waxing and 'waxingcrescent' or 'waningcrescent'
    elseif lit <= 0.53 then
        return waxing and 'firstquarter' or 'lastquarter'
    elseif lit <= 0.97 then
        return waxing and 'waxinggibbous' or 'waninggibbous'
    end
    return 'full'
end

function Clock.weekday(unix_day)
    return WEEKDAYS[(unix_day + 3) % 7 + 1]
end

return Clock
