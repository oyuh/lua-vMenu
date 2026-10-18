-- Port of vMenu.Enhanced.Menus/World/WeatherTemperature.cs: the temperature
-- where the player stands, from the weather the game shows. Other resources
-- read it through the GetTemperature and GetTemperatureAtHeight exports.

local Clock = require('shared.world.clock')
local Temperatures = require('shared.world.temperatures')
local UserDefaults = require('client.user_defaults')
local Ticks = require('menu.ticks')
local State = require('client.menus.world.state')
local Time = require('client.menus.world.time')
local Weather = require('client.menus.world.weather')

local Temperature = {}

local CACHE_INTERVAL_MS = 500
local CHANGING_INTERVAL_MS = 250

Temperature.UNIT_CELSIUS = 0
Temperature.UNIT_FAHRENHEIT = 1

local sea_level, here

function Temperature.hour_of_day()
    return GetClockHours() + GetClockMinutes() / 60.0 + GetClockSeconds() / 3600.0
end

function Temperature.changing()
    return Weather.is_blending() or Time.is_transitioning() or State.time_speed() > Clock.NORMAL_SPEED
end

local function refresh()
    local previous, next_weather, percent = GetWeatherTypeTransition()
    local from, to = Weather.of_hash(previous), Weather.of_hash(next_weather)
    if not from or not to then
        sea_level, here = nil, nil
        return
    end
    sea_level = Temperatures.blended(from, to, percent, Temperature.hour_of_day())
    here = Temperatures.at_height(sea_level, GetEntityCoords(PlayerPedId(), false).z)
end

-- Degrees Celsius where the player is, or nil while the weather is unknown.
function Temperature.celsius()
    refresh()
    return here
end

function Temperature.use_metric()
    return UserDefaults.get('displayTemperatureUnit') ~= Temperature.UNIT_FAHRENHEIT
end

function Temperature.rounded(celsius, metric)
    return math.floor((metric and celsius or Temperatures.to_fahrenheit(celsius)) + 0.5)
end

function Temperature.format(celsius)
    local metric = Temperature.use_metric()
    return ('%d°%s'):format(Temperature.rounded(celsius, metric), metric and 'C' or 'F')
end

function Temperature.init()
    Ticks.register('World.Temperature', refresh, {
        rate = function()
            return Temperature.changing() and CHANGING_INTERVAL_MS or CACHE_INTERVAL_MS
        end,
    })
    exports('GetTemperature', function()
        return here
    end)
    exports('GetTemperatureAtHeight', function(height)
        height = tonumber(height)
        if not sea_level or not height then
            return nil
        end
        return Temperatures.at_height(sea_level, height)
    end)
end

return Temperature
