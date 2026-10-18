-- Port of vMenu.Enhanced.Menus/WorldMenu.cs. Every change goes through the
-- server, which checks the permission again and tells every client.

local Localization = require('shared.localization')
local Config = require('shared.config')
local Types = require('shared.world.types')
local TimeText = require('shared.world.time_text')
local Clock = require('shared.world.clock')
local Log = require('shared.log')
local Gate = require('client.framework.gate')
local Entries = require('client.framework.entries')
local Registry = require('client.framework.registry')
local Notifications = require('client.framework.notifications')
local Input = require('client.framework.input')
local Actions = require('client.actions')
local Ticks = require('menu.ticks')
local State = require('client.menus.world.state')

local WEATHER_ENABLED = 'vMenu.Enhanced.WeatherOptions.Enabled'
local TIME_ENABLED = 'vMenu.Enhanced.TimeOptions.Enabled'
local PRESETS = 'vMenu.Enhanced.TimeOptions.Presets'
local WEATHER = 'vMenu.Enhanced.Menus.WeatherOptions.'
local TIME = 'vMenu.Enhanced.Menus.TimeOptions.'

local WEATHER_ALLOWED = Gate.all(Gate.setting(WEATHER_ENABLED), WEATHER .. 'SetWeather')
local TIME_ALLOWED = Gate.all(Gate.setting(TIME_ENABLED), TIME .. 'SetTime')

-- Presets ----------------------------------------------------------------------------

-- Refilled in place when the setting changes, so the list entry keeps its table.
local preset_labels, preset_seconds = {}, {}

local function sync_presets()
    local seconds, rejected = TimeText.parse_presets(Config.value(PRESETS))
    for index = #preset_labels, 1, -1 do
        preset_labels[index] = nil
    end
    preset_seconds = seconds
    for index, second in ipairs(seconds) do
        preset_labels[index] = TimeText.format(second)
    end
    if #rejected > 0 then
        local message = '[World] Ignoring %d time preset(s) in %s: %s. '
            .. 'Every preset has to be four digits on a 24 hour clock, such as 0930 or 2130.'
        Log.warning(message:format(#rejected, PRESETS, table.concat(rejected, ', ')))
    end
end

-- Talking to the server --------------------------------------------------------------

local function failure_key(status)
    if status == Actions.DENIED then
        return 'world.denied'
    elseif status == Actions.REFUSED then
        return 'world.disabled'
    end
    return 'world.failed'
end

local function transition(setting)
    local seconds = math.max(0, Config.value(setting))
    if seconds == 0 then
        return ''
    end
    return Localization.key('world.transition', { duration = seconds .. 's' })
end

-- For changes that ease in over a transition time.
local function send(action, argument, success_key, transition_setting, value)
    local status = Actions.invoke(action, argument)
    if status == Actions.OK then
        Notifications.success(
            Localization.key(success_key, { value = value or '', transition = transition(transition_setting) })
        )
    else
        Notifications.error(Localization.key(failure_key(status)))
    end
end

-- For switches the menu shows the state of: a refusal puts the row back.
local function send_state(menu, action, argument, success_key, value)
    local status = Actions.invoke(action, argument)
    if status == Actions.OK then
        Notifications.success(Localization.key(success_key, { value = value or '' }))
        return
    end
    menu:refresh()
    Notifications.error(Localization.key(failure_key(status)))
end

local function set_time(second_of_day)
    local speed = State.time_speed()
    local offset = (second_of_day - Clock.second_of_day(State.clock_unix_seconds(), speed)) % Clock.SECONDS_PER_GAME_DAY
    send(
        'TimeOptions.SetTime',
        tostring(math.floor(offset)),
        'world.time.set',
        'vMenu.Enhanced.TimeOptions.TransitionSeconds',
        TimeText.format(second_of_day)
    )
end

local function prompt_for_time()
    local typed = Input.get_text({
        title = Localization.key('world.settime.prompt'),
        max_length = TimeText.MAX_INPUT_LENGTH,
        initial_value = TimeText.EXAMPLE,
    })
    if typed == nil then
        return
    end
    local second_of_day = TimeText.parse(typed)
    if not second_of_day then
        Notifications.error(Localization.key('world.time.notunderstood', { input = typed }))
        return
    end
    set_time(second_of_day)
end

-- Status subtitle --------------------------------------------------------------------

local function status_key()
    local forced = State.weather_override ~= nil
    if State.is_time_frozen() then
        return forced and 'world.status.weatherforcedtimefrozen' or 'world.status.timefrozen'
    end
    local offset = State.time_offset ~= 0
    if forced then
        return offset and 'world.status.bothforced' or 'world.status.weatherforced'
    end
    return offset and 'world.status.timeforced' or 'world.status'
end

local function status()
    return Localization.resolve(Localization.key(status_key(), {
        weather = Localization.key(Types.weather_key(State.weather())),
        time = TimeText.format(math.floor(State.second_of_day())),
    }))
end

-- Options ----------------------------------------------------------------------------

local function index_of(list, value)
    for index, candidate in ipairs(list) do
        if candidate == value then
            return index
        end
    end
    return 1
end

local function mode_options(modes, key_of)
    local options = {}
    for index, mode in ipairs(modes) do
        options[index] = Localization.key(key_of(mode))
    end
    return options
end

local WEATHER_OPTIONS = { Localization.key('world.weather.dynamic') }
for index, weather in ipairs(Types.WEATHERS) do
    WEATHER_OPTIONS[index + 1] = Localization.key(Types.weather_key(weather))
end

local function configured_cycle()
    return Types.cycle(Config.value('vMenu.Enhanced.WeatherOptions.WeatherCycle')) or 'default'
end

local open_menu

local function refresh_open()
    if open_menu then
        open_menu:refresh()
    end
end

return Registry.definition({
    audit_name = 'WorldMenu',
    title_key = 'world.title',
    subtitle = Localization.from(status),
    description_key = 'world.link.desc',
    gate = Gate.any(
        Gate.all(Gate.setting(WEATHER_ENABLED), WEATHER .. 'Menu'),
        Gate.all(Gate.setting(TIME_ENABLED), TIME .. 'Menu')
    ),
    link_behaviour = 'hide',
    default_gate_behaviour = 'hide',
    build = function(menu)
        sync_presets()
        Config.watch({ PRESETS }, function()
            sync_presets()
            menu:refresh()
        end)
        State.on_changed(refresh_open)
        Ticks.register('World.MenuStatus', function()
            menu:refresh_header()
        end, {
            rate = 250,
            condition = function()
                return open_menu ~= nil
            end,
        })
        menu:on_opened(function()
            open_menu = menu
            menu:refresh()
            Ticks.reevaluate()
        end)
        menu:on_closed(function()
            open_menu = nil
            Ticks.reevaluate()
        end)

        menu:add(Entries.list({
            text = Localization.key('world.weather'),
            description = Localization.key('world.weather.desc'),
            gate = WEATHER_ALLOWED,
            options = WEATHER_OPTIONS,
            read_selected_index = function()
                local forced = State.weather_override
                return forced and Types.weather_index(forced) + 1 or 0
            end,
            on_selected_async = function(args)
                local weather = Types.WEATHERS[args.selected_index]
                if not weather then
                    send(
                        'WeatherOptions.SetWeather',
                        Types.DYNAMIC,
                        'world.weather.reset',
                        'vMenu.Enhanced.WeatherOptions.TransitionSeconds'
                    )
                    return
                end
                send(
                    'WeatherOptions.SetWeather',
                    weather,
                    'world.weather.set',
                    'vMenu.Enhanced.WeatherOptions.TransitionSeconds',
                    Localization.key(Types.weather_key(weather))
                )
            end,
        }))
        menu:add(Entries.button({
            text = Localization.key('world.settime'),
            description = Localization.key('world.settime.desc'),
            gate = TIME_ALLOWED,
            on_selected_async = prompt_for_time,
        }))
        menu:add(Entries.list({
            text = Localization.key('world.timepreset'),
            description = Localization.key('world.timepreset.desc'),
            gate = Gate.all(
                TIME_ALLOWED,
                Gate.when(function()
                    return #preset_labels > 0
                end)
            ),
            options = preset_labels,
            on_selected_async = function(args)
                local second = preset_seconds[args.selected_index + 1]
                if second then
                    set_time(second)
                end
            end,
        }))
        menu:add(Entries.checkbox({
            text = Localization.key('world.freezetime'),
            description = Localization.key('world.freezetime.desc'),
            gate = Gate.all(Gate.setting(TIME_ENABLED), TIME .. 'FreezeTime'),
            read_state = State.is_time_frozen,
            on_changed_async = function(args)
                send_state(
                    menu,
                    'TimeOptions.SetFrozen',
                    args.checked and 'true' or 'false',
                    args.checked and 'world.time.frozen' or 'world.time.unfrozen'
                )
            end,
        }))
        menu:add(Entries.list({
            text = Localization.key('world.blackout'),
            description = Localization.key('world.blackout.desc'),
            gate = WEATHER .. 'Blackout',
            options = mode_options(Types.BLACKOUTS, Types.blackout_key),
            read_selected_index = function()
                return index_of(Types.BLACKOUTS, State.blackout) - 1
            end,
            on_selected_async = function(args)
                local mode = Types.BLACKOUTS[args.selected_index + 1]
                send_state(
                    menu,
                    'WeatherOptions.SetBlackout',
                    mode,
                    'world.blackout.set',
                    Localization.key(Types.blackout_key(mode))
                )
            end,
        }))
        menu:add(Entries.list({
            text = Localization.key('world.snow'),
            description = Localization.key('world.snow.desc'),
            gate = Gate.all(Gate.setting(WEATHER_ENABLED), WEATHER .. 'Snow'),
            options = mode_options(Types.SNOWS, Types.snow_key),
            read_selected_index = function()
                return index_of(Types.SNOWS, State.snow) - 1
            end,
            on_selected_async = function(args)
                local mode = Types.SNOWS[args.selected_index + 1]
                send_state(
                    menu,
                    'WeatherOptions.SetSnow',
                    mode,
                    'world.snow.set',
                    Localization.key(Types.snow_key(mode))
                )
            end,
        }))
        menu:add(Entries.list({
            text = Localization.key('world.cycle'),
            description = Localization.key('world.cycle.desc', {
                cycle = Localization.from(function()
                    return Localization.get(Types.cycle_key(configured_cycle()))
                end),
            }),
            gate = Gate.all(Gate.setting(WEATHER_ENABLED), WEATHER .. 'WeatherCycle'),
            options = mode_options(Types.CYCLES, Types.cycle_key),
            read_selected_index = function()
                return index_of(Types.CYCLES, configured_cycle()) - 1
            end,
            on_selected_async = function(args)
                local cycle = Types.CYCLES[args.selected_index + 1]
                send_state(
                    menu,
                    'WeatherOptions.SetCycle',
                    cycle,
                    'world.cycle.set',
                    Localization.key(Types.cycle_key(cycle))
                )
            end,
        }))
        menu:add(Entries.button({
            text = Localization.key('world.resetweather'),
            description = Localization.key('world.resetweather.desc'),
            gate = WEATHER_ALLOWED,
            on_selected_async = function()
                send(
                    'WeatherOptions.SetWeather',
                    Types.DYNAMIC,
                    'world.weather.reset',
                    'vMenu.Enhanced.WeatherOptions.TransitionSeconds'
                )
            end,
        }))
        menu:add(Entries.button({
            text = Localization.key('world.resettime'),
            description = Localization.key('world.resettime.desc'),
            gate = TIME_ALLOWED,
            on_selected_async = function()
                send(
                    'TimeOptions.SetTime',
                    'realtime',
                    'world.time.reset',
                    'vMenu.Enhanced.TimeOptions.TransitionSeconds'
                )
            end,
        }))
    end,
})
