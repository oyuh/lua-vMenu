-- Port of vMenu/menus/WeatherOptions.cs: weather types, dynamic weather,
-- blackout, snow effects, and clouds.

local Config = require('shared.config')
local Permissions = require('shared.permissions')
local Common = require('client.common')
local Notification = require('client.notify')
local Items = require('menu.items')
local Menu = require('menu.menu')

local Notify = Notification.Notify

local WeatherOptions = {}

local WEATHER_ITEMS = {
    { 'Extra Sunny', 'extra sunny', 'EXTRASUNNY' },
    { 'Clear', 'clear', 'CLEAR' },
    { 'Neutral', 'neutral', 'NEUTRAL' },
    { 'Smog', 'smog', 'SMOG' },
    { 'Foggy', 'foggy', 'FOGGY' },
    { 'Cloudy', 'clouds', 'CLOUDS' },
    { 'Overcast', 'overcast', 'OVERCAST' },
    { 'Clearing', 'clearing', 'CLEARING' },
    { 'Rainy', 'rain', 'RAIN' },
    { 'Thunder', 'thunder', 'THUNDER' },
    { 'Blizzard', 'blizzard', 'BLIZZARD' },
    { 'Snow', 'snow', 'SNOW' },
    { 'Light Snow', 'light snow', 'SNOWLIGHT' },
    { 'X-MAS Snow', 'x-mas', 'XMAS' },
    { 'Halloween', 'halloween', 'HALLOWEEN' },
}

local function server_weather()
    return Config.get_string('vmenu_current_weather', 'CLEAR') or 'CLEAR'
end

local function dynamic_weather_enabled()
    return Config.get_bool('vmenu_enable_dynamic_weather')
end

local function is_snow_enabled()
    return Config.get_bool('vmenu_enable_snow')
end

function WeatherOptions.create()
    local self = {}
    local menu = Menu.new(GetPlayerName(PlayerId()), 'Weather Options')

    local dynamic_weather = Items.MenuCheckboxItem.new(
        'Toggle Dynamic Weather',
        'Enable or disable dynamic weather changes.',
        dynamic_weather_enabled()
    )
    local blackout = Items.MenuCheckboxItem.new(
        'Toggle Blackout',
        'This disables or enables all lights across the map.',
        Config.get_bool('vmenu_blackout_enabled')
    )
    local vehicle_blackout = Items.MenuCheckboxItem.new(
        'Toggle Vehicle Lights Blackout',
        'This disables or enables all vehicle lights across the map.',
        not Config.get_bool('vmenu_vehicle_blackout_enabled')
    )
    local snow_enabled = Items.MenuCheckboxItem.new(
        'Enable Snow Effects',
        'This will force snow to appear on the ground and enable snow particle effects for peds and vehicles. '
            .. 'Combine with X-MAS or Light Snow weather for best results.',
        is_snow_enabled()
    )
    self.dynamic_weather_enabled = dynamic_weather
    self.blackout = blackout
    self.vehicle_blackout = vehicle_blackout
    self.snow_enabled = snow_enabled

    local weather_items = {}
    for i, entry in ipairs(WEATHER_ITEMS) do
        local item = Items.MenuItem.new(entry[1], ('Set the weather to ~y~%s~s~!'):format(entry[2]))
        item.ItemData = entry[3]
        weather_items[i] = item
    end
    local removeclouds = Items.MenuItem.new('Remove All Clouds', 'Remove all clouds from the sky!')
    local randomizeclouds = Items.MenuItem.new('Randomize Clouds', 'Add random clouds to the sky!')

    if Permissions.is_allowed('WODynamic') then
        menu:AddMenuItem(dynamic_weather)
    end
    if Permissions.is_allowed('WOBlackout') then
        menu:AddMenuItem(blackout)
    end
    if Permissions.is_allowed('WOVehBlackout') then
        menu:AddMenuItem(vehicle_blackout)
    end
    if Permissions.is_allowed('WOSetWeather') then
        menu:AddMenuItem(snow_enabled)
        for _, item in ipairs(weather_items) do
            menu:AddMenuItem(item)
        end
    end
    if Permissions.is_allowed('WORandomizeClouds') then
        menu:AddMenuItem(randomizeclouds)
    end
    if Permissions.is_allowed('WORemoveClouds') then
        menu:AddMenuItem(removeclouds)
    end

    menu.OnItemSelect = function(_, item, _index)
        if item == removeclouds then
            Common.modify_clouds(true)
        elseif item == randomizeclouds then
            Common.modify_clouds(false)
        elseif type(item.ItemData) == 'string' then
            local change_time = math.min(math.max(Config.get_int('vmenu_weather_change_duration'), 0), 45)
            Notify.custom(
                ('The weather will be changed to ~y~%s~s~. This will take %d seconds.'):format(item.Text, change_time)
            )
            Common.update_server_weather(item.ItemData, dynamic_weather_enabled(), is_snow_enabled())
        end
    end

    menu.OnCheckboxChange = function(_, item, _index, checked)
        if item == dynamic_weather then
            Notify.custom(('Dynamic weather changes are now %s~s~.'):format(checked and '~g~enabled' or '~r~disabled'))
            Common.update_server_weather(server_weather(), checked, is_snow_enabled())
        elseif item == blackout then
            Notify.custom(('Blackout mode is now %s~s~.'):format(checked and '~g~enabled' or '~r~disabled'))
            Common.update_server_blackout(checked)
        elseif item == vehicle_blackout then
            Notify.custom(
                ('Vehicle light blackout mode is now %s~s~.'):format(checked and '~g~enabled' or '~r~disabled')
            )
            Common.update_server_vehicle_blackout(not checked)
        elseif item == snow_enabled then
            local weather = server_weather()
            if weather == 'XMAS' or weather == 'SNOWLIGHT' or weather == 'SNOW' or weather == 'BLIZZARD' then
                Notify.custom(('Snow effects cannot be disabled when weather is ~y~%s~s~.'):format(weather))
                return
            end
            Notify.custom(('Snow effects will now be forced %s~s~.'):format(checked and '~g~enabled' or '~r~disabled'))
            Common.update_server_weather(weather, dynamic_weather_enabled(), checked)
        end
    end

    self.menu = menu
    return self
end

return WeatherOptions
