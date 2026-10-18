-- Port of vMenu.Enhanced.Menus/World/WeatherForecast.cs and
-- WeatherForecastKeyBinding.cs: the forecast panel on ui/forecast.js, with
-- what is coming, the temperature, the moon and an in-game clock. A key
-- cycles it off, compact and full; Display Settings has the switches too.

local Localization = require('shared.localization')
local Json = require('shared.json_compat')
local Config = require('shared.config')
local Types = require('shared.world.types')
local Clock = require('shared.world.clock')
local TimeText = require('shared.world.time_text')
local Temperatures = require('shared.world.temperatures')
local WeatherCycle = require('shared.world.weather_cycle')
local Permissions = require('client.permissions')
local UserDefaults = require('client.user_defaults')
local Hud = require('client.framework.hud')
local Registry = require('client.framework.registry')
local Ticks = require('menu.ticks')
local State = require('client.menus.world.state')
local Time = require('client.menus.world.time')
local Temperature = require('client.menus.world.temperature')

local Forecast = {}

Forecast.FULL = 0
Forecast.COMPACT = 1

local PERMISSION = 'vMenu.Enhanced.Menus.DisplaySettings.Forecast'
local REFRESH_INTERVAL_MS = 1000
local CHANGING_INTERVAL_MS = 250
local UPCOMING_COUNT = 3
local OUTLOOK_STEP_GAME_HOURS = 3
local OUTLOOK_COUNT = 16
local UNKNOWN = -1
local HIDE_MESSAGE = '{"type":"forecast","visible":false}'
local KEY_COMMAND = 'vmenu:forecast'

local ICONS = {
    EXTRASUNNY = 'sunny',
    CLEAR = 'clear',
    NEUTRAL = 'clear',
    CLOUDS = 'clouds',
    OVERCAST = 'overcast',
    CLEARING = 'clearing',
    RAIN = 'rain',
    RAIN_HALLOWEEN = 'rain',
    THUNDER = 'thunder',
    SMOG = 'smog',
    FOGGY = 'fog',
    SNOW = 'snow',
    SNOWLIGHT = 'snow',
    SNOW_HALLOWEEN = 'snow',
    XMAS = 'snow',
    BLIZZARD = 'blizzard',
    HALLOWEEN = 'halloween',
}

local shown, painted = false, ''

local function allowed()
    return Config.value('vMenu.Enhanced.WeatherOptions.Enabled') and Permissions.is_allowed(PERMISSION)
end

function Forecast.enabled()
    return UserDefaults.get('displayWeatherForecast') == true and allowed()
end

function Forecast.clock_enabled()
    return UserDefaults.get('displayShowTime') == true
end

function Forecast.style()
    return UserDefaults.get('displayWeatherForecastStyle') == Forecast.COMPACT and Forecast.COMPACT or Forecast.FULL
end

local function wanted()
    return Forecast.enabled() or Forecast.clock_enabled()
end

local function weather_name(weather)
    return Localization.get(Types.weather_key(weather))
end

local function real_seconds(game_hours)
    return math.floor(game_hours * Clock.real_seconds_per_game_hour(State.time_speed()) + 0.5)
end

local function clock_text()
    return TimeText.format(GetClockHours() * 3600 + GetClockMinutes() * 60)
end

local function outlook(forced)
    local metric = Temperature.use_metric()
    local cells = {}
    local entries = Temperatures.outlook(
        State.cycle_game_hours(),
        Temperature.hour_of_day() * 3600.0,
        State.is_time_frozen(),
        forced,
        OUTLOOK_STEP_GAME_HOURS,
        OUTLOOK_COUNT
    )
    for index, entry in ipairs(entries) do
        cells[index] = {
            time = TimeText.format(math.floor(entry.hour_of_day * 3600.0)),
            icon = ICONS[entry.weather],
            temperature = ('%d°'):format(Temperature.rounded(entry.celsius, metric)),
        }
    end
    return cells
end

local function clock_only()
    return {
        type = 'forecast',
        visible = true,
        showForecast = false,
        showTime = true,
        compact = true,
        time = clock_text(),
        title = '',
        nowLabel = '',
        nextLabel = '',
        moonLabel = '',
        note = '',
        currentName = '',
        currentIcon = '',
        currentForSeconds = UNKNOWN,
        temperature = '',
        outsideLabel = '',
        outlookLabel = '',
        outlook = {},
        upcoming = {},
        moonName = '',
        moonLit = 0,
        moonWaxing = false,
    }
end

local function build()
    if Forecast.clock_enabled() and not Forecast.enabled() then
        return clock_only()
    end
    local forced = State.weather_override
    local scheduled = State.has_clock() and forced == nil
    local compact = Forecast.style() == Forecast.COMPACT
    local upcoming = {}
    if scheduled then
        for index, entry in ipairs(WeatherCycle.forecast(State.cycle_game_hours(), compact and 1 or UPCOMING_COUNT)) do
            upcoming[index] = {
                name = weather_name(entry.weather),
                icon = ICONS[entry.weather],
                inSeconds = real_seconds(entry.hours_until_start),
                forSeconds = real_seconds(entry.hours_long),
            }
        end
    end
    local note = ''
    if not State.has_clock() then
        note = Localization.get('displaysettings.forecast.noclock')
    elseif forced then
        note = Localization.get('displaysettings.forecast.forced')
    end
    local moon_days = Time.moon_cycle_days()
    local moon_key = 'world.moonphase.' .. Clock.moon_phase(moon_days)
    local celsius = Temperature.celsius()
    local current = State.weather()
    return {
        type = 'forecast',
        visible = true,
        showForecast = true,
        showTime = Forecast.clock_enabled(),
        compact = compact,
        time = clock_text(),
        title = Localization.get('displaysettings.forecast.title'),
        nowLabel = Localization.get('displaysettings.forecast.now'),
        nextLabel = Localization.get('displaysettings.forecast.next'),
        moonLabel = Localization.get('displaysettings.forecast.moon'),
        note = note,
        currentName = weather_name(current),
        currentIcon = ICONS[current],
        currentForSeconds = scheduled and real_seconds(State.schedule().hours_until_next) or UNKNOWN,
        temperature = celsius and Temperature.format(celsius) or '',
        outsideLabel = Localization.get('displaysettings.forecast.outside'),
        outlookLabel = Localization.get('displaysettings.forecast.outlook'),
        outlook = (compact or not State.has_clock()) and {} or outlook(forced),
        upcoming = upcoming,
        moonName = Localization.get(moon_key),
        moonLit = math.floor(Clock.moon_illumination(moon_days) * 100.0 + 0.5),
        moonWaxing = Clock.moon_day(moon_days) < Clock.FULL_MOON_DAY,
    }
end

local function hide()
    painted = ''
    if shown then
        shown = false
        SendNuiMessage(HIDE_MESSAGE)
    end
end

local function flush()
    if not Hud.can_draw() then
        hide()
        return
    end
    local message = Json.encode(build())
    if message == painted then
        return
    end
    painted, shown = message, true
    SendNuiMessage(message)
end

local function reevaluate()
    Ticks.reevaluate()
    if wanted() then
        flush()
    else
        hide()
    end
end

function Forecast.set_enabled(on)
    UserDefaults.set('displayWeatherForecast', on)
    reevaluate()
end

function Forecast.set_style(style)
    UserDefaults.set('displayWeatherForecastStyle', style)
    reevaluate()
end

function Forecast.set_clock_enabled(on)
    UserDefaults.set('displayShowTime', on)
    reevaluate()
end

-- Off, compact, full, off.
function Forecast.cycle()
    if not allowed() or not Hud.can_draw() then
        return
    end
    if UserDefaults.get('displayWeatherForecast') ~= true then
        UserDefaults.set('displayWeatherForecastStyle', Forecast.COMPACT)
        Forecast.set_enabled(true)
    elseif Forecast.style() == Forecast.COMPACT then
        Forecast.set_style(Forecast.FULL)
    else
        Forecast.set_enabled(false)
    end
    Registry.refresh_all()
end

function Forecast.init()
    Ticks.register('World.Forecast', flush, {
        rate = function()
            return Temperature.changing() and CHANGING_INTERVAL_MS or REFRESH_INTERVAL_MS
        end,
        condition = wanted,
    })
    RegisterCommand(KEY_COMMAND, Forecast.cycle, false)
    RegisterKeyMapping(KEY_COMMAND, 'vMenu: Cycle the weather forecast off, compact or full', 'keyboard', 'EQUALS')
    Permissions.on_changed(reevaluate)
    Config.watch({ 'vMenu.Enhanced.WeatherOptions.Enabled' }, reevaluate)
end

return Forecast
