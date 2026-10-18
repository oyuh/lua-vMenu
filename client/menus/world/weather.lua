-- Ports of vMenu.Enhanced.Menus/World/WorldWeather.cs and WorldClouds.cs:
-- blends the game weather to what the world state says, eases into a forced
-- weather over the transition time, and starts blending into the next
-- scheduled weather half an hour before it begins. Clouds follow when the
-- server syncs them.

local Types = require('shared.world.types')
local Clock = require('shared.world.clock')
local WeatherCycle = require('shared.world.weather_cycle')
local Ticks = require('menu.ticks')
local State = require('client.menus.world.state')

local Weather = {}

local INTERVAL_MS = 250

local HASHES = {}
for _, weather in ipairs(Types.WEATHERS) do
    HASHES[weather] = GetHashKey(weather)
end

local CLOUD_HATS = {
    EXTRASUNNY = 'Clear 01',
    CLEAR = 'Puffs',
    NEUTRAL = 'Horizon',
    SMOG = 'horizonband1',
    FOGGY = 'horizonband2',
    CLOUDS = 'Cloudy 01',
    OVERCAST = 'altostratus',
    CLEARING = 'Wispy',
    RAIN = 'RAIN',
    RAIN_HALLOWEEN = 'RAIN',
    THUNDER = 'Stormy 01',
    BLIZZARD = 'Stormy 01',
    SNOW = 'Snowy 01',
    SNOWLIGHT = 'Snowy 01',
    SNOW_HALLOWEEN = 'Snowy 01',
    XMAS = 'Snowy 01',
    HALLOWEEN = 'Nimbus',
}

local w = { from = nil, to = nil, changed_at = 0, started = false, settled = false, was_forced = false }
local blending = false
local cloud_hat = ''

function Weather.is_blending()
    return blending
end

-- The weather the game reports for a hash, or nil.
function Weather.of_hash(hash)
    for weather, candidate in pairs(HASHES) do
        if candidate == hash then
            return weather
        end
    end
    return nil
end

local function apply_clouds(weather, seconds)
    local hat = CLOUD_HATS[weather] or 'Clear 01'
    if hat ~= cloud_hat then
        cloud_hat = hat
        SetCloudHatTransition(hat, seconds)
    end
end

local function release_clouds(seconds)
    if cloud_hat ~= '' then
        UnloadCloudHat(cloud_hat, seconds)
        cloud_hat = ''
    end
end

local function set(from, to, percent)
    blending = from ~= to and percent > 0 and percent < 1
    SetWeatherTypeTransition(HASHES[from], HASHES[to], percent)
end

local function apply()
    if not State.has_clock() then
        return
    end
    local forced = State.weather_override
    local schedule = State.schedule()
    local desired = forced or schedule.current
    local first = not w.started
    if first then
        w.started, w.from, w.to, w.settled = true, desired, desired, true
    elseif desired ~= w.to then
        -- The schedule moving on is already blended at the boundary below.
        w.settled = forced == nil and not w.was_forced
        w.from, w.to, w.changed_at = w.to, desired, GetGameTimer()
    end
    w.was_forced = forced ~= nil

    local seconds = State.weather_transition_seconds()
    if State.sync_clouds() then
        local near_boundary = schedule.hours_until_next < WeatherCycle.BOUNDARY_WINDOW_GAME_HOURS
        apply_clouds(forced or (near_boundary and schedule.next or schedule.current), first and 0.0 or seconds)
    else
        release_clouds(seconds)
    end

    if not w.settled then
        local progress = seconds <= 0 and 1.0 or math.min(1.0, (GetGameTimer() - w.changed_at) / 1000.0 / seconds)
        if progress < 1.0 then
            set(w.from, w.to, Clock.smooth(math.max(0.0, progress)))
            return
        end
        w.settled = true
    end

    if not forced and schedule.hours_until_next < WeatherCycle.BOUNDARY_WINDOW_GAME_HOURS then
        local into = 1.0 - schedule.hours_until_next / WeatherCycle.BOUNDARY_WINDOW_GAME_HOURS
        set(schedule.current, schedule.next, Clock.smooth(into))
        return
    end
    set(w.to, w.to, 0.0)
end

function Weather.init()
    Ticks.register('World.Weather', apply, {
        rate = INTERVAL_MS,
        condition = State.weather_enabled,
        on_started = function()
            w.started = false
            SetWeatherOwnedByNetwork(false)
            ClearOverrideWeather()
            ClearWeatherTypePersist()
        end,
        on_stopped = function()
            blending = false
            ClearWeatherTypePersist()
            release_clouds(State.weather_transition_seconds())
            SetWeatherOwnedByNetwork(true)
        end,
    })
    State.on_changed(Ticks.reevaluate)
end

return Weather
