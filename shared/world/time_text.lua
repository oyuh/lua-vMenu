-- Ports of vMenu.Enhanced.Data/World/TimeText.cs and TimePresets.cs: reading
-- the time a player types, and the server's preset list.

local Types = require('shared.world.types')

local TimeText = {}

TimeText.EXAMPLE = '15:25'
TimeText.MAX_INPUT_LENGTH = 12

local SUFFIXES = { { 'AM', 'am' }, { 'PM', 'pm' }, { 'A', 'am' }, { 'P', 'pm' } }

local function digits(text, min_length, max_length)
    if #text < min_length or #text > max_length or not text:match('^%d+$') then
        return nil
    end
    return tonumber(text)
end

local function split(text)
    local separator = text:find('[:.,]')
    if separator then
        local hour = digits(text:sub(1, separator - 1), 1, 2)
        local minute = digits(text:sub(separator + 1), 1, 2)
        if hour and minute then
            return hour, minute
        end
        return nil
    end
    local value = digits(text, 1, 4)
    if not value then
        return nil
    end
    if #text <= 2 then
        return value, 0
    end
    return value // 100, value % 100
end

-- Accepts 15:25, 1525, 3pm, 3:25 p and the like. The second of the day, or nil.
function TimeText.parse(input)
    if type(input) ~= 'string' then
        return nil
    end
    local text = input:gsub('%s', ''):upper()
    local meridiem
    for _, suffix in ipairs(SUFFIXES) do
        if text:sub(-#suffix[1]) == suffix[1] then
            text = text:sub(1, -#suffix[1] - 1)
            meridiem = suffix[2]
            break
        end
    end
    if text == '' then
        return nil
    end
    local hour, minute = split(text)
    if not hour then
        return nil
    end
    if meridiem then
        if hour < 1 or hour > 12 then
            return nil
        end
        if meridiem == 'am' then
            hour = hour == 12 and 0 or hour
        else
            hour = hour == 12 and 12 or hour + 12
        end
    end
    if hour > 23 or minute > 59 then
        return nil
    end
    return hour * 3600 + minute * 60
end

function TimeText.format(second_of_day)
    local wrapped = Types.normalise_offset(second_of_day)
    return ('%02d:%02d'):format(wrapped // 3600, wrapped % 3600 // 60)
end

-- Presets ----------------------------------------------------------------------------

-- "0930,2130": seconds of the day, plus the entries that were not four digits
-- on a 24 hour clock.
function TimeText.parse_presets(text)
    local presets, rejected = {}, {}
    for entry in (text or ''):gmatch('[^,]+') do
        local hour, minute = entry:match('^(%d%d)(%d%d)$')
        hour, minute = tonumber(hour), tonumber(minute)
        if hour and hour <= 23 and minute <= 59 then
            presets[#presets + 1] = hour * 3600 + minute * 60
        else
            rejected[#rejected + 1] = entry
        end
    end
    return presets, rejected
end

return TimeText
