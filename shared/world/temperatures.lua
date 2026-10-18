-- Port of vMenu.Enhanced.Data/World/WeatherTemperatures.cs: a temperature
-- for each weather through the day, sampled from GTA Online, colder up high,
-- with wintery rows while the cycle keeps snow on the ground.

local WeatherCycle = require('shared.world.weather_cycle')

local Temperatures = {}

local SAMPLE_HOURS = { 0, 5, 6, 7, 10, 12, 16, 17, 18, 19, 20, 21, 22 }
local SAMPLE_HOLDS = { 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
local FADE_START_HEIGHT = 200.0
local FADE_END_HEIGHT = 1000.0
local DROP_AT_FADE_END = 15.0
local LATEST_HOUR = 23.999

-- stylua: ignore start
local S = {
    smog = { 11.5, 11, 12.5, 13.5, 20, 26.5, 28.5, 27, 22.5, 20, 13.5, 12, 12 },
    clouds = { 13, 11.5, 11, 14, 16.5, 20, 24.5, 24.5, 18.5, 16, 12.5, 12.5, 11 },
    rain = { 12, 13, 11.5, 13, 15.5, 19.5, 24, 21.5, 19, 14, 14, 13, 11.5 },
    thunder = { 12.5, 12, 12, 14.5, 16, 19, 23, 17, 16, 14.5, 13, 14.5, 12.5 },
    neutral = { 13.5, 10.5, 9.5, 10, 9.5, 10, 10.5, 10, 10.5, 10, 10, 11, 13 },
    clearing = { 12.1, 12.1, 12.1, 12.7, 13.7, 16.2, 21.1, 26, 24.6, 20.4, 16.2, 13.7, 12.7 },
    foggy = { 12.2, 12.2, 12.2, 12.4, 13.2, 14.4, 15.6, 16, 15.2, 14.1, 13.1, 12.4, 12.1 },
    halloween = { 14, 13.5, 13.5, 15, 17, 28.5, 30.5, 30.5, 16.5, 16.5, 11.5, 11.5, 13.5 },
    extra_sunny = { 15, 14.5, 14.5, 17, 21.5, 30, 34.5, 34, 27, 22, 17, 15, 15.5 },
    clear = { 14.5, 14, 14, 16, 19.5, 27, 31, 31.5, 23, 19, 15, 14, 14.5 },
    blizzard = { -35, -18.8, -15.6, -13.4, -10.2, -7.9, -7.9, -10.2, -14.5, -17.7, -25.3, -31.8, -35 },
    snow = { -23, -12.2, -11.1, -6.8, -5.7, -4.6, -3.5, -4.6, -6.8, -10, -14.3, -17.6, -23 },
    snow_light = { -5, -6, -3, -2, -1.5, -1.5, -1.5, -1.5, -1, -1.5, -2.5, -3.5, -4.5 },
    snowy_clearing = { -13, -13, -13, -12.4, -11.7, -9.7, -5.8, -1.9, -3.1, -6.4, -9.7, -11.7, -12.4 },
    snowy_foggy = { -9.9, -9.9, -10, -9.6, -8.8, -7.6, -6.4, -6, -6.6, -7.6, -9, -9.6, -10 },
    snowy_extra_sunny = { -12, -11.9, -11.9, -10.6, -8.2, -3.4, -0.9, -3.4, -6.3, -8.2, -10.6, -11.5, -12 },
    snowy_clear = { -14, -14, -14, -12.2, -9.1, -4.8, -3, -2.9, -6.7, -9.1, -12.2, -13.4, -14 },
    snowy_smog = { -11, -11, -11, -9.8, -7.9, -5.2, -4, -5.2, -6.2, -7.9, -9.8, -10.6, -11 },
    snowy_clouds = { -9, -9, -8.9, -8.6, -7.8, -5.9, -3.9, -4.8, -5.9, -7.8, -8.6, -8.6, -8.9 },
    snowy_rain = { -4, -4, -4, -3.7, -2.9, -1.3, 0, -0.3, -1.3, -2.9, -3.7, -3.7, -4 },
    snowy_thunder = { -8, -8, -8, -7.6, -6.9, -5.1, -3.8, -6.2, -6.9, -7.3, -7.6, -7.6, -8 },
    snowy_neutral = { -6, -7.9, -7.9, -8, -8, -8, -8, -8, -8, -7.7, -8, -6.9, -6 },
    snowy_halloween = { -16, -16, -16, -13.7, -13.7, -2, -1.9, -2, -13.7, -13.7, -16, -16, -16 },
}
-- stylua: ignore end

local NORMAL = {
    EXTRASUNNY = S.extra_sunny,
    CLEAR = S.clear,
    SMOG = S.smog,
    CLOUDS = S.clouds,
    OVERCAST = S.clouds,
    FOGGY = S.foggy,
    CLEARING = S.clearing,
    RAIN = S.rain,
    THUNDER = S.thunder,
    NEUTRAL = S.neutral,
    SNOW = S.snow,
    BLIZZARD = S.blizzard,
    SNOW_HALLOWEEN = S.snow_light,
    SNOWLIGHT = S.snow_light,
    XMAS = S.snow,
    HALLOWEEN = S.halloween,
    RAIN_HALLOWEEN = S.halloween,
}

local SNOWY = {
    EXTRASUNNY = S.snowy_extra_sunny,
    CLEAR = S.snowy_clear,
    SMOG = S.snowy_smog,
    CLOUDS = S.snowy_clouds,
    OVERCAST = S.snowy_clouds,
    FOGGY = S.snowy_foggy,
    CLEARING = S.snowy_clearing,
    RAIN = S.snowy_rain,
    THUNDER = S.snowy_thunder,
    NEUTRAL = S.snowy_neutral,
    SNOW = S.snow,
    BLIZZARD = S.blizzard,
    SNOW_HALLOWEEN = S.snow_light,
    SNOWLIGHT = S.snow_light,
    XMAS = S.snow,
    HALLOWEEN = S.snowy_halloween,
    RAIN_HALLOWEEN = S.snowy_halloween,
}

local function samples(weather)
    if WeatherCycle.snow_pass() then
        return SNOWY[weather] or S.snowy_clear
    end
    return NORMAL[weather] or S.clear
end

function Temperatures.at_sea_level(weather, hour_of_day)
    local row = samples(weather)
    local hour = math.max(0.0, math.min(LATEST_HOUR, hour_of_day))
    local index = #SAMPLE_HOURS
    while SAMPLE_HOURS[index] > hour do
        index = index - 1
    end
    local next_index = index % #SAMPLE_HOURS + 1
    local next_hour = next_index == 1 and SAMPLE_HOURS[1] + 24.0 or SAMPLE_HOURS[next_index]
    local start = SAMPLE_HOURS[index] + SAMPLE_HOLDS[index]
    local t = math.max(0.0, math.min(1.0, (hour - start) / (next_hour - start)))
    return row[index] + (row[next_index] - row[index]) * t
end

function Temperatures.blended(from, to, percent, hour_of_day)
    local start = Temperatures.at_sea_level(from, hour_of_day)
    return start + (Temperatures.at_sea_level(to, hour_of_day) - start) * math.max(0.0, math.min(1.0, percent))
end

function Temperatures.at_height(sea_level, height)
    local fade = (height - FADE_START_HEIGHT) / (FADE_END_HEIGHT - FADE_START_HEIGHT)
    return sea_level - math.max(0.0, math.min(1.0, fade)) * DROP_AT_FADE_END
end

function Temperatures.to_fahrenheit(celsius)
    return celsius * 9.0 / 5.0 + 32.0
end

-- count steps of step_hours ahead, as { hours_ahead, hour_of_day, weather, celsius }.
function Temperatures.outlook(cycle_game_hours, second_of_day, clock_frozen, forced, step_hours, count)
    local entries = {}
    local hour_now = second_of_day / 3600.0
    local first = clock_frozen and step_hours or step_hours - hour_now % step_hours
    for i = 0, count - 1 do
        local ahead = first + i * step_hours
        local weather = forced or WeatherCycle.resolve(cycle_game_hours + ahead).current
        local hour_of_day = hour_now
        if not clock_frozen then
            hour_of_day = math.floor((hour_now + ahead) % 24.0 + 0.5) % 24.0
        end
        entries[#entries + 1] = {
            hours_ahead = ahead,
            hour_of_day = hour_of_day,
            weather = weather,
            celsius = Temperatures.at_sea_level(weather, hour_of_day),
        }
    end
    return entries
end

return Temperatures
