-- Ports of vMenu.Enhanced.Data/World: WeatherType.cs, WeatherTypes.cs,
-- BlackoutMode.cs, SnowMode.cs, WeatherCycleType.cs and WorldStateConvars.cs.
-- Each value is the name upstream writes into the replicated convars, so the
-- two builds agree on the wire.

local Types = {}

-- In upstream's enum order: the custom cycle packs a weather as 'A' + index.
Types.WEATHERS = {
    'CLEAR',
    'EXTRASUNNY',
    'CLOUDS',
    'OVERCAST',
    'RAIN',
    'CLEARING',
    'THUNDER',
    'SMOG',
    'FOGGY',
    'XMAS',
    'SNOW',
    'SNOWLIGHT',
    'BLIZZARD',
    'HALLOWEEN',
    'NEUTRAL',
    'RAIN_HALLOWEEN',
    'SNOW_HALLOWEEN',
}

Types.BLACKOUTS = { 'dynamic', 'off', 'city', 'all' }
Types.SNOWS = { 'auto', 'on', 'off' }
Types.CYCLES = { 'default', 'snowy', 'custom' }

local SNOWY = { XMAS = true, SNOW = true, SNOWLIGHT = true, BLIZZARD = true, SNOW_HALLOWEEN = true }

-- The canonical spelling of name from list, matched ignoring case, or nil.
local function find(list, name)
    if type(name) ~= 'string' then
        return nil
    end
    local wanted = name:match('^%s*(.-)%s*$'):lower()
    for _, candidate in ipairs(list) do
        if candidate:lower() == wanted then
            return candidate
        end
    end
    return nil
end

function Types.weather(name)
    return find(Types.WEATHERS, name)
end

function Types.blackout(name)
    return find(Types.BLACKOUTS, name)
end

function Types.snow(name)
    return find(Types.SNOWS, name)
end

function Types.cycle(name)
    return find(Types.CYCLES, name)
end

function Types.is_snowy(weather)
    return SNOWY[weather] == true
end

-- 0-based, upstream's enum value.
function Types.weather_index(weather)
    for index, candidate in ipairs(Types.WEATHERS) do
        if candidate == weather then
            return index - 1
        end
    end
    return nil
end

-- Translation keys -------------------------------------------------------------------

function Types.weather_key(weather)
    return 'world.weathername.' .. weather:lower():gsub('_', '')
end

function Types.blackout_key(mode)
    return 'world.blackout.' .. mode
end

function Types.snow_key(mode)
    return 'world.snow.' .. (mode == 'auto' and 'automatic' or mode)
end

function Types.cycle_key(cycle)
    return 'world.cycle.' .. cycle
end

-- Replicated convars -----------------------------------------------------------------

Types.CONVAR_UTC = 'vMenu.Enhanced.State.Utc'
Types.CONVAR_WEATHER = 'vMenu.Enhanced.State.Weather'
Types.CONVAR_TIME_OFFSET = 'vMenu.Enhanced.State.TimeOffset'
Types.CONVAR_BLACKOUT = 'vMenu.Enhanced.State.Blackout'
Types.CONVAR_SNOW = 'vMenu.Enhanced.State.Snow'
Types.DYNAMIC = 'dynamic'

Types.SECONDS_PER_GAME_DAY = 86400

local FROZEN_SEPARATOR = '@'

function Types.normalise_offset(seconds)
    return math.floor(seconds) % Types.SECONDS_PER_GAME_DAY
end

local function parse_offset(text)
    local parsed = math.tointeger(tonumber(text))
    return parsed and Types.normalise_offset(parsed) or nil
end

-- The offset, plus "@<unix seconds>" while the clock is frozen.
function Types.format_time(offset_seconds, frozen_at_unix)
    local offset = tostring(Types.normalise_offset(offset_seconds))
    if frozen_at_unix then
        return offset .. FROZEN_SEPARATOR .. ('%.3f'):format(frozen_at_unix)
    end
    return offset
end

-- offset, frozen_at_unix (or nil); nil when the text is unusable.
function Types.parse_time(text)
    if type(text) ~= 'string' or text:match('^%s*$') then
        return nil
    end
    local separator = text:find(FROZEN_SEPARATOR, 1, true)
    if not separator then
        return parse_offset(text), nil
    end
    local offset = parse_offset(text:sub(1, separator - 1))
    if not offset then
        return nil
    end
    local pinned = tonumber(text:sub(separator + 1))
    return offset, (pinned and pinned > 0) and pinned or nil
end

function Types.parse_unix(text)
    local value = math.tointeger(tonumber(text))
    return (value and value > 0) and value or nil
end

return Types
