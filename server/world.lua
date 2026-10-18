-- Ports of vMenu.Enhanced.Configuration.Server/ServerState.cs, ServerClock.cs
-- and ServerWeatherCycle.cs, and vMenu.Enhanced.Actions.Server/Handlers/
-- WorldActions.cs. The server owns the world: it publishes UTC, the weather
-- override, the clock offset, blackout and snow as replicated convars, and
-- every client derives the same time and weather from them.
--
-- Upstream also records the last weather change and a full world snapshot for
-- its HTTP endpoint; those come with the integrations in phase 6.

local Log = require('shared.log')
local Json = require('shared.json_compat')
local Config = require('shared.config')
local Types = require('shared.world.types')
local Clock = require('shared.world.clock')
local WeatherCycle = require('shared.world.weather_cycle')
local Actions = require('server.actions')

local World = {}

local WEATHER_ENABLED = 'vMenu.Enhanced.WeatherOptions.Enabled'
local WEATHER_CYCLE = 'vMenu.Enhanced.WeatherOptions.WeatherCycle'
local TIME_ENABLED = 'vMenu.Enhanced.TimeOptions.Enabled'
local TIME_SPEED = 'vMenu.Enhanced.TimeOptions.SpeedMultiplier'
local CYCLE_FILE = 'config/weather-cycle.json'
local CUSTOM_CYCLE_KEY = 'vMenu.Enhanced.CustomCycle'
local PUBLISH_INTERVAL_MS = 1000

local state = {
    weather = nil, -- a forced weather, or nil for the schedule
    offset = 0,
    frozen_at = nil,
    blackout = 'dynamic',
    snow = 'auto',
}
local published_cycle

local function now()
    return os.time()
end

local function speed()
    return Clock.clamp_speed(Config.value(TIME_SPEED))
end

local function needed()
    return Config.value(WEATHER_ENABLED) or Config.value(TIME_ENABLED)
end

-- Publishing -------------------------------------------------------------------------

local function publish_weather()
    SetConvarReplicated(Types.CONVAR_WEATHER, state.weather or Types.DYNAMIC)
end

local function publish_time()
    SetConvarReplicated(Types.CONVAR_TIME_OFFSET, Types.format_time(state.offset, state.frozen_at))
end

local function publish_blackout()
    SetConvarReplicated(Types.CONVAR_BLACKOUT, state.blackout)
end

local function publish_snow()
    SetConvarReplicated(Types.CONVAR_SNOW, state.snow)
end

local function publish_clock()
    SetConvarReplicated(Types.CONVAR_UTC, tostring(now()))
end

-- State ------------------------------------------------------------------------------

function World.real_time_offset()
    return math.floor(Clock.real_time_offset(now(), speed()))
end

local function set_offset_running(seconds)
    state.offset = Types.normalise_offset(seconds)
    state.frozen_at = nil
    publish_time()
end

function World.reset_to_real_time()
    if not Config.value(TIME_ENABLED) then
        Log.warning(
            '[Clock] Time sync is off, so vMenu is not driving the clock and there is nothing to reset. '
                .. ('Turn on %s first.'):format(TIME_ENABLED)
        )
        return
    end
    set_offset_running(World.real_time_offset())
    Log.debug("[Clock] The clock is back on the server's own time.")
end

-- Weather cycle ----------------------------------------------------------------------

local function read_cycle_file()
    local contents = LoadResourceFile(GetCurrentResourceName(), CYCLE_FILE)
    if not contents or contents:match('^%s*$') then
        Log.warning(
            ('[Weather] The weather cycle is set to custom, but %s is missing or empty. Using default.'):format(
                CYCLE_FILE
            )
        )
        return nil
    end
    local raw = Json.decode(contents)
    if type(raw) ~= 'table' then
        Log.warning(('[Weather] %s could not be read, so the default weather cycle is used.'):format(CYCLE_FILE))
        return nil
    end
    local blocks = {}
    for index, block in ipairs(Json.field(raw, 'cycle') or {}) do
        blocks[index] = {
            hours = Json.field(block, 'hours'),
            weather = Json.field(block, 'weather'),
            blackout = Json.field(block, 'blackout'),
        }
    end
    local custom = WeatherCycle.build_custom(
        { snowPass = Json.field(raw, 'snowPass'), cycle = blocks },
        function(problem)
            Log.warning(('[Weather] %s: %s'):format(CYCLE_FILE, problem))
        end
    )
    if not custom then
        Log.warning(('[Weather] %s has no usable entries, so the default weather cycle is used.'):format(CYCLE_FILE))
    end
    return custom
end

local function wanted_cycle()
    local raw = Config.value(WEATHER_CYCLE)
    local cycle = Types.cycle(raw)
    if cycle then
        return cycle
    end
    if raw and not tostring(raw):match('^%s*$') then
        Log.warning(
            ("[Weather] %s is set to '%s', which is not default, snowy or custom. Using default."):format(
                WEATHER_CYCLE,
                tostring(raw)
            )
        )
    end
    return 'default'
end

local function load_cycle()
    local wanted = wanted_cycle()
    local custom = wanted == 'custom' and Config.value(WEATHER_ENABLED) and read_cycle_file() or nil
    WeatherCycle.use(wanted, custom)
    local payload = custom and WeatherCycle.pack(custom) or ''
    if payload == published_cycle then
        return
    end
    published_cycle = payload
    GlobalState:set(CUSTOM_CYCLE_KEY, payload, true)
    if custom then
        Log.info(
            ('[Weather] Using the custom weather cycle from %s: %d entries over %.2f in-game hours.'):format(
                CYCLE_FILE,
                #custom.entries,
                custom.length
            )
        )
    end
end

-- Actions ----------------------------------------------------------------------------

local function refused_unless(setting)
    return not Config.value(setting) and Actions.REFUSED or nil
end

local function set_weather(source, args)
    local refusal = refused_unless(WEATHER_ENABLED)
    if refusal then
        return refusal
    end
    if type(args[1]) ~= 'string' then
        return Actions.INVALID_REQUEST
    end
    if args[1]:lower() == Types.DYNAMIC then
        state.weather = nil
        Log.debug(('[State] Player %d handed the weather back to the schedule.'):format(source))
    else
        local weather = Types.weather(args[1])
        if not weather then
            return Actions.INVALID_REQUEST
        end
        state.weather = weather
        Log.debug(('[State] Player %d forced the weather to %s.'):format(source, weather))
    end
    publish_weather()
    return Actions.OK
end

local function set_time(source, args)
    local refusal = refused_unless(TIME_ENABLED)
    if refusal then
        return refusal
    end
    if type(args[1]) ~= 'string' then
        return Actions.INVALID_REQUEST
    end
    if args[1]:lower() == 'realtime' then
        set_offset_running(World.real_time_offset())
        Log.debug(("[State] Player %d put the clock back on the server's own time."):format(source))
        return Actions.OK
    end
    local seconds = math.tointeger(tonumber(args[1]))
    if not seconds then
        return Actions.INVALID_REQUEST
    end
    state.offset = Types.normalise_offset(seconds)
    publish_time()
    Log.debug(('[State] Player %d set the clock offset to %ds.'):format(source, state.offset))
    return Actions.OK
end

local function set_frozen(source, args)
    local refusal = refused_unless(TIME_ENABLED)
    if refusal then
        return refusal
    end
    local text = type(args[1]) == 'string' and args[1]:lower()
    if text ~= 'true' and text ~= 'false' then
        return Actions.INVALID_REQUEST
    end
    local frozen = text == 'true'
    if frozen ~= (state.frozen_at ~= nil) then
        state.frozen_at = frozen and now() or nil
        publish_time()
    end
    Log.debug(('[State] Player %d %s the clock.'):format(source, frozen and 'froze' or 'unfroze'))
    return Actions.OK
end

local function set_blackout(source, args)
    local mode = Types.blackout(args[1])
    if not mode then
        return Actions.INVALID_REQUEST
    end
    state.blackout = mode
    publish_blackout()
    Log.debug(('[State] Player %d set the blackout to %s.'):format(source, mode))
    return Actions.OK
end

local function set_snow(source, args)
    local refusal = refused_unless(WEATHER_ENABLED)
    if refusal then
        return refusal
    end
    local mode = Types.snow(args[1])
    if not mode then
        return Actions.INVALID_REQUEST
    end
    state.snow = mode
    publish_snow()
    Log.debug(('[State] Player %d set the snow effects to %s.'):format(source, mode))
    return Actions.OK
end

local function set_cycle(source, args)
    local refusal = refused_unless(WEATHER_ENABLED)
    if refusal then
        return refusal
    end
    local cycle = Types.cycle(args[1])
    if not cycle then
        return Actions.INVALID_REQUEST
    end
    SetConvarReplicated(WEATHER_CYCLE, cycle)
    load_cycle()
    Log.debug(('[State] Player %d set the weather cycle to %s.'):format(source, cycle))
    return Actions.OK
end

-- Commands ---------------------------------------------------------------------------

local function dump_state()
    Log.info(
        ('[State] weather: %s, time offset: %ds, clock: %s'):format(
            state.weather or 'dynamic',
            state.offset,
            state.frozen_at and ('frozen at unix %d'):format(state.frozen_at) or 'running'
        )
    )
    Log.info(('[State] blackout: %s, snow: %s'):format(state.blackout, state.snow))
end

local function dump_clock()
    if not needed() then
        Log.info('[Clock] Both weather and time sync are off, so no world time is published.')
        return
    end
    local clock = state.frozen_at or now()
    local second = (Clock.second_of_day(clock, speed()) + state.offset) % Clock.SECONDS_PER_GAME_DAY
    local schedule = WeatherCycle.resolve(Clock.cycle_game_hours(now(), speed(), WeatherCycle.length()))
    Log.info(
        ('[Clock] in-game %02d:%02d (offset %ds), %s cycle, at %.3fx speed'):format(
            second // 3600,
            second % 3600 // 60,
            state.offset,
            WeatherCycle.name(),
            speed()
        )
    )
    Log.info(
        ('[Clock] weather %s, then %s in %.1f real minutes'):format(
            state.weather or schedule.current,
            schedule.next,
            schedule.hours_until_next * Clock.real_seconds_per_game_hour(speed()) / 60
        )
    )
end

local function debug_only(handler)
    return function()
        if not Config.value('vMenu.Enhanced.Debugging.Server') then
            Log.info('[vMenu] This command only reports while vMenu.Enhanced.Debugging.Server is set to true.')
            return
        end
        handler()
    end
end

-- Call once, after Config.init.
function World.init()
    publish_weather()
    publish_time()
    publish_blackout()
    publish_snow()
    load_cycle()
    Config.watch({ WEATHER_ENABLED, WEATHER_CYCLE }, load_cycle)

    CreateThread(function()
        while true do
            if needed() then
                publish_clock()
            end
            Wait(PUBLISH_INTERVAL_MS)
        end
    end)

    Actions.register('WeatherOptions.SetWeather', 'vMenu.Enhanced.Menus.WeatherOptions.SetWeather', set_weather)
    Actions.register('TimeOptions.SetTime', 'vMenu.Enhanced.Menus.TimeOptions.SetTime', set_time)
    Actions.register('WeatherOptions.SetBlackout', 'vMenu.Enhanced.Menus.WeatherOptions.Blackout', set_blackout)
    Actions.register('WeatherOptions.SetSnow', 'vMenu.Enhanced.Menus.WeatherOptions.Snow', set_snow)
    Actions.register('WeatherOptions.SetCycle', 'vMenu.Enhanced.Menus.WeatherOptions.WeatherCycle', set_cycle)
    Actions.register('TimeOptions.SetFrozen', 'vMenu.Enhanced.Menus.TimeOptions.FreezeTime', set_frozen)

    RegisterCommand('vmenu_state', debug_only(dump_state), true)
    RegisterCommand('vmenu_clock', debug_only(dump_clock), true)
    RegisterCommand('vmenu_resettime', World.reset_to_real_time, true)
end

return World
