-- Ports of vMenu.Enhanced.Data/World/WeatherCycle.cs and CustomCycle.cs, plus
-- the Resolve helpers of BlackoutMode.cs and SnowMode.cs. The schedule is a
-- fixed list of weathers over a loop of game hours, so the server and every
-- client read the same weather off the same clock. A custom cycle comes from
-- config/weather-cycle.json on the server and reaches clients packed into a
-- global state bag.

local Types = require('shared.world.types')
local Tables = require('shared.data.weather_cycles')

local WeatherCycle = {}

WeatherCycle.BOUNDARY_WINDOW_GAME_HOURS = 0.5

local function rows(source, length, snow_pass)
    local entries = {}
    for index, row in ipairs(source) do
        entries[index] = { hour = row[1], weather = row[2], blackout = 'off' }
    end
    return { entries = entries, length = length, snow_pass = snow_pass, has_blackouts = false }
end

local BUILT_IN = {
    default = rows(Tables.normal, 384.0, false),
    snowy = rows(Tables.snowy, 180.0, true),
}

local current_name = 'default'
local current = BUILT_IN.default

function WeatherCycle.name()
    return current_name
end

function WeatherCycle.entries()
    return current.entries
end

function WeatherCycle.length()
    return current.length
end

function WeatherCycle.snow_pass()
    return current.snow_pass
end

function WeatherCycle.has_scheduled_blackouts()
    return current.has_blackouts
end

-- A custom cycle without its table falls back to default.
function WeatherCycle.use(wanted, custom)
    if wanted == 'custom' and not custom then
        wanted = 'default'
    end
    current_name = wanted
    current = wanted == 'custom' and custom or BUILT_IN[wanted] or BUILT_IN.default
end

local function index_at(position)
    local entries = current.entries
    for index, entry in ipairs(entries) do
        if entry.hour > position then
            return index - 1
        end
    end
    return #entries
end

function WeatherCycle.blackout_at(cycle_game_hours)
    return current.entries[index_at(cycle_game_hours % current.length)].blackout
end

-- { current, next, hours_until_next } at a point in the loop.
function WeatherCycle.resolve(cycle_game_hours)
    local entries, length = current.entries, current.length
    local position = cycle_game_hours % length
    local index = index_at(position)
    local weather = entries[index].weather
    for step = 1, #entries do
        local next_entry = entries[(index - 1 + step) % #entries + 1]
        if next_entry.weather ~= weather then
            local until_next = next_entry.hour - position
            if until_next <= 0 then
                until_next = until_next + length
            end
            return { current = weather, next = next_entry.weather, hours_until_next = until_next }
        end
    end
    return { current = weather, next = weather, hours_until_next = length }
end

-- The next count weathers as { weather, hours_until_start, hours_long }.
function WeatherCycle.forecast(cycle_game_hours, count)
    local entries, length = current.entries, current.length
    if count <= 0 then
        return {}
    end
    local position = cycle_game_hours % length
    local index = index_at(position)
    local previous = entries[index].weather
    local boundaries = {}
    local step = 1
    while step <= #entries * (count + 1) and #boundaries <= count do
        local at = index - 1 + step
        local entry = entries[at % #entries + 1]
        if entry.weather ~= previous then
            previous = entry.weather
            boundaries[#boundaries + 1] = {
                weather = entry.weather,
                hours_until_start = entry.hour + (at // #entries) * length - position,
            }
        end
        step = step + 1
    end
    local forecast = {}
    for i = 1, #boundaries - 1 do
        if #forecast >= count then
            break
        end
        forecast[#forecast + 1] = {
            weather = boundaries[i].weather,
            hours_until_start = boundaries[i].hours_until_start,
            hours_long = boundaries[i + 1].hours_until_start - boundaries[i].hours_until_start,
        }
    end
    return forecast
end

-- The blackout in force: a set mode wins, 'dynamic' follows the custom cycle.
function WeatherCycle.effective_blackout(mode, weather_forced, weather_enabled, cycle_game_hours)
    if mode ~= 'dynamic' then
        return mode
    end
    if not weather_enabled or weather_forced or not current.has_blackouts then
        return 'off'
    end
    return WeatherCycle.blackout_at(cycle_game_hours)
end

function WeatherCycle.snow_wanted(mode, weather)
    if mode == 'on' then
        return true
    elseif mode == 'off' then
        return false
    end
    return current.snow_pass or Types.is_snowy(weather)
end

-- Custom cycles -----------------------------------------------------------------------

local BLACKOUT_LETTERS = { city = 'c', all = 'a' }
local LETTER_BLACKOUTS = { c = 'city', a = 'all' }

-- The file's { snowPass, cycle = { { hours, weather, blackout } } }, checked;
-- nil when nothing is usable. warn(problem) hears about every skipped entry.
function WeatherCycle.build_custom(file, warn)
    local blocks = type(file) == 'table' and file.cycle
    if type(blocks) ~= 'table' or #blocks == 0 then
        warn('it has no cycle entries.')
        return nil
    end
    local entries, start, has_blackouts = {}, 0.0, false
    for index, block in ipairs(blocks) do
        local hours = type(block) == 'table' and tonumber(block.hours)
        local weather = hours and Types.weather(block.weather)
        if not hours or hours <= 0 or hours == math.huge then
            warn(('entry %d is skipped, its hours must be a number above 0.'):format(index))
        elseif not weather then
            warn(("entry %d is skipped, '%s' is not a known weather type."):format(index, tostring(block.weather)))
        else
            local blackout = 'off'
            if type(block.blackout) == 'string' and not block.blackout:match('^%s*$') then
                local parsed = Types.blackout(block.blackout)
                if parsed and parsed ~= 'dynamic' then
                    blackout = parsed
                else
                    warn(
                        ("entry %d has blackout '%s', which is not off, city or all, so it gets no blackout."):format(
                            index,
                            block.blackout
                        )
                    )
                end
            end
            entries[#entries + 1] = { hour = start, weather = weather, blackout = blackout }
            has_blackouts = has_blackouts or blackout ~= 'off'
            start = start + hours
        end
    end
    if #entries == 0 then
        warn('none of its cycle entries are usable.')
        return nil
    end
    return { entries = entries, length = start, snow_pass = file.snowPass == true, has_blackouts = has_blackouts }
end

local function format_hours(hours)
    local text = ('%.6f'):format(hours):gsub('0+$', ''):gsub('%.$', '')
    return text
end

-- Upstream's compact form: "<snow pass 0|1>|" then per entry its length in
-- hours, 'A' + weather index, and 'c' or 'a' for a blackout.
function WeatherCycle.pack(cycle)
    local parts = { cycle.snow_pass and '1|' or '0|' }
    for index, entry in ipairs(cycle.entries) do
        local next_entry = cycle.entries[index + 1]
        local finish = next_entry and next_entry.hour or cycle.length
        parts[#parts + 1] = format_hours(finish - entry.hour)
        parts[#parts + 1] = string.char(65 + Types.weather_index(entry.weather))
        parts[#parts + 1] = BLACKOUT_LETTERS[entry.blackout] or ''
    end
    return table.concat(parts)
end

-- The file form of a packed cycle, or nil when it does not parse.
function WeatherCycle.unpack(packed)
    if type(packed) ~= 'string' or not packed:match('^[01]|') then
        return nil
    end
    local blocks = {}
    local position = 3
    while position <= #packed do
        local number, letter, after = packed:match('^([%d%.]+)([A-Z])()', position)
        if not number then
            return nil
        end
        local hours = tonumber(number)
        if not hours then
            return nil
        end
        local blackout = LETTER_BLACKOUTS[packed:sub(after, after)]
        if blackout then
            after = after + 1
        end
        blocks[#blocks + 1] = { hours = hours, weather = Types.WEATHERS[letter:byte() - 64], blackout = blackout }
        position = after
    end
    return { snowPass = packed:sub(1, 1) == '1', cycle = blocks }
end

return WeatherCycle
