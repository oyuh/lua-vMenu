-- Port of vMenu.Enhanced.Menus/World/WorldState.cs: what the server says the
-- world should be, read from its replicated convars, and a clock anchored to
-- the UTC it publishes. Until that arrives, this machine's clock stands in.

local Log = require('shared.log')
local Config = require('shared.config')
local Platform = require('shared.platform')
local Types = require('shared.world.types')
local Clock = require('shared.world.clock')
local WeatherCycle = require('shared.world.weather_cycle')
local Ticks = require('menu.ticks')

local State = {}

local WEATHER_ENABLED = 'vMenu.Enhanced.WeatherOptions.Enabled'
local TIME_ENABLED = 'vMenu.Enhanced.TimeOptions.Enabled'
local CUSTOM_CYCLE_KEY = 'vMenu.Enhanced.CustomCycle'
local FALLBACK_INTERVAL_MS = 500
local HARD_RESYNC_SECONDS = 30.0
local DRIFT_CORRECTION = 0.1

local listeners = {}
local anchor_unix, anchor_timer, anchored = 0, 0, false
local heard_from_server, warned_about_fallback = false, false

-- What the convars say. weather_override is nil while the schedule decides.
State.weather_override = nil
State.time_offset = 0
State.frozen_at = nil
State.blackout = 'dynamic'
State.snow = 'auto'

function State.on_changed(listener)
    listeners[#listeners + 1] = listener
end

local function changed()
    for _, listener in ipairs(listeners) do
        local ok, err = pcall(listener)
        if not ok then
            Log.error('[World] A world state listener threw: ' .. tostring(err))
        end
    end
end

function State.needed()
    return Config.value(WEATHER_ENABLED) or Config.value(TIME_ENABLED)
end

function State.weather_enabled()
    return Config.value(WEATHER_ENABLED)
end

function State.time_enabled()
    return Config.value(TIME_ENABLED)
end

function State.has_clock()
    return anchored
end

function State.unix_seconds()
    return anchored and anchor_unix + (GetGameTimer() - anchor_timer) / 1000.0 or 0.0
end

function State.clock_unix_seconds()
    return State.frozen_at or State.unix_seconds()
end

function State.time_speed()
    return Clock.clamp_speed(Config.value('vMenu.Enhanced.TimeOptions.SpeedMultiplier'))
end

function State.time_transition_seconds()
    return math.max(0, Config.value('vMenu.Enhanced.TimeOptions.TransitionSeconds'))
end

function State.weather_transition_seconds()
    return math.max(0, Config.value('vMenu.Enhanced.WeatherOptions.TransitionSeconds'))
end

function State.sync_clouds()
    return Config.value('vMenu.Enhanced.WeatherOptions.SyncClouds')
end

function State.is_time_frozen()
    return State.frozen_at ~= nil
end

function State.second_of_day()
    return (Clock.second_of_day(State.clock_unix_seconds(), State.time_speed()) + State.time_offset)
        % Clock.SECONDS_PER_GAME_DAY
end

function State.cycle_game_hours()
    return Clock.cycle_game_hours(State.unix_seconds(), State.time_speed(), WeatherCycle.length())
end

function State.schedule()
    return WeatherCycle.resolve(State.cycle_game_hours())
end

function State.weather()
    return State.weather_override or State.schedule().current
end

function State.effective_blackout()
    return WeatherCycle.effective_blackout(
        State.blackout,
        State.weather_override ~= nil,
        State.weather_enabled(),
        State.cycle_game_hours()
    )
end

function State.snow_wanted()
    return WeatherCycle.snow_wanted(State.snow, State.weather())
end

-- Reading ----------------------------------------------------------------------------

local function read_custom_cycle()
    local payload = GlobalState[CUSTOM_CYCLE_KEY]
    if type(payload) ~= 'string' or payload == '' then
        return nil
    end
    local file = WeatherCycle.unpack(payload)
    if not file then
        Log.error('[World] The custom weather cycle the server sent could not be read: ' .. payload)
        return nil
    end
    return WeatherCycle.build_custom(file, function(problem)
        Log.warning('[World] The custom weather cycle the server sent: ' .. problem)
    end)
end

local function read_cycle()
    local wanted = Types.cycle(Config.value('vMenu.Enhanced.WeatherOptions.WeatherCycle')) or 'default'
    WeatherCycle.use(wanted, wanted == 'custom' and read_custom_cycle() or nil)
    changed()
end

local function anchor(published)
    local timer = GetGameTimer()
    if not anchored then
        anchor_unix, anchor_timer, anchored = published, timer, true
        return
    end
    local drift = published - State.unix_seconds()
    if math.abs(drift) > HARD_RESYNC_SECONDS then
        anchor_unix, anchor_timer = published, timer
        return
    end
    -- Nudged, not snapped, so the clock never jumps for a small drift.
    anchor_unix = anchor_unix + drift * DRIFT_CORRECTION
end

local function read_clock()
    local published = Types.parse_unix(GetConvar(Types.CONVAR_UTC, ''))
    if not published then
        return
    end
    heard_from_server = true
    anchor(published)
    Ticks.reevaluate()
end

local function read_overrides()
    State.weather_override = Types.weather(GetConvar(Types.CONVAR_WEATHER, Types.DYNAMIC))
    local offset, frozen = Types.parse_time(GetConvar(Types.CONVAR_TIME_OFFSET, '0'))
    State.time_offset, State.frozen_at = offset or 0, offset and frozen or nil
    State.blackout = Types.blackout(GetConvar(Types.CONVAR_BLACKOUT, '')) or 'dynamic'
    State.snow = Types.snow(GetConvar(Types.CONVAR_SNOW, '')) or 'auto'
    changed()
end

local function anchor_from_local_clock()
    local year, month, day, hour, minute, second = GetUtcTime()
    if year < 2000 then
        return
    end
    if not warned_about_fallback then
        warned_about_fallback = true
        Log.warning("[World] No server time yet, falling back to this machine's clock.")
    end
    anchor_unix = Clock.to_unix_seconds(year, month, day, hour, minute, second)
    anchor_timer, anchored = GetGameTimer(), true
    Ticks.reevaluate()
end

local function dump()
    if not State.needed() then
        Log.info('[World] Both weather and time sync are off on this server, so nothing is being synced.')
        return
    end
    for _, convar in ipairs({ Types.CONVAR_UTC, Types.CONVAR_WEATHER, Types.CONVAR_TIME_OFFSET }) do
        Log.info(("[World] %s = '%s'"):format(convar, GetConvar(convar, '')))
    end
    local clock = not anchored and 'not anchored'
        or heard_from_server and 'anchored to the server'
        or 'anchored to THIS MACHINE, no server time has arrived'
    Log.info(('[World] clock: %s, running at %.3fx speed'):format(clock, State.time_speed()))
    Log.info(
        ('[World] override: %s, schedule: %s, in force: %s, time offset: %ds, clock: %s'):format(
            State.weather_override or 'none',
            State.schedule().current,
            State.weather(),
            State.time_offset,
            State.frozen_at and ('frozen at unix %.3f'):format(State.frozen_at) or 'running'
        )
    )
    Log.info(
        ('[World] cycle: %s, %d entries over %.2f hours, snow pass: %s'):format(
            WeatherCycle.name(),
            #WeatherCycle.entries(),
            WeatherCycle.length(),
            tostring(WeatherCycle.snow_pass())
        )
    )
    Log.info(
        ('[World] blackout: %s (in force: %s), snow: %s (wanted right now: %s)'):format(
            State.blackout,
            State.effective_blackout(),
            State.snow,
            tostring(State.snow_wanted())
        )
    )
end

local function listen(convars, handler)
    if not Platform.has('AddConvarChangeListener') then
        return
    end
    for _, convar in ipairs(convars) do
        AddConvarChangeListener(convar, function()
            handler()
        end)
    end
end

function State.init()
    read_clock()
    read_cycle()
    read_overrides()
    Config.watch({ 'vMenu.Enhanced.WeatherOptions.WeatherCycle' }, read_cycle)
    Config.watch({
        'vMenu.Enhanced.TimeOptions.SpeedMultiplier',
        'vMenu.Enhanced.TimeOptions.TransitionSeconds',
        'vMenu.Enhanced.WeatherOptions.TransitionSeconds',
        'vMenu.Enhanced.WeatherOptions.SyncClouds',
        WEATHER_ENABLED,
        TIME_ENABLED,
    }, function()
        changed()
        Ticks.reevaluate()
    end)
    listen({ Types.CONVAR_UTC }, read_clock)
    listen({ Types.CONVAR_WEATHER, Types.CONVAR_TIME_OFFSET, Types.CONVAR_BLACKOUT, Types.CONVAR_SNOW }, read_overrides)
    -- The bag arrives before its value can be read, so this waits a frame.
    AddStateBagChangeHandler(CUSTOM_CYCLE_KEY, 'global', function()
        SetTimeout(0, read_cycle)
    end)
    Ticks.register('World.Clock.Fallback', anchor_from_local_clock, {
        rate = FALLBACK_INTERVAL_MS,
        condition = function()
            return State.needed() and not anchored
        end,
    })
    RegisterCommand('vmenu_world', function()
        if Config.value('vMenu.Enhanced.Debugging.Client') then
            dump()
        end
    end, false)
end

return State
