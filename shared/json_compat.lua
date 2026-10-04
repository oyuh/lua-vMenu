-- JSON layer with Newtonsoft-compatible behavior guarantees.
-- In-game this wraps CfxLua's built-in `json`; under busted it falls back to
-- dkjson. Contract notes (docs/contracts/kvp-saves.md):
--   * loads never throw; corrupt input returns nil (upstream catches and
--     degrades, so must we)
--   * C# Dictionary<int,...> arrives as string-keyed objects; callers keep
--     them string-keyed rather than converting, so re-encoding round-trips

local Json = {}

local backend = rawget(_G, 'json')
local dkjson
if backend == nil then
    dkjson = require('dkjson')
end

-- Newtonsoft (what upstream vMenu decodes with) silently ignores `//` line
-- and `/* */` block comments, and the shipped config/*.json files use them.
-- CfxLua's built-in json.decode is strict JSON and rejects comments outright,
-- which broke config loads in-game ("model-whitelists.json ... invalid JSON").
-- Strip comments before decoding, string-aware so a `//` or `/*` sitting
-- inside a JSON string value (e.g. a URL) is left untouched.
local function strip_comments(text)
    if not text:find('/', 1, true) then
        return text
    end
    local out = {}
    local i, n = 1, #text
    local in_string = false
    while i <= n do
        local c = text:sub(i, i)
        if in_string then
            if c == '\\' then
                out[#out + 1] = text:sub(i, i + 1)
                i = i + 2
            else
                out[#out + 1] = c
                if c == '"' then
                    in_string = false
                end
                i = i + 1
            end
        elseif c == '/' and text:sub(i + 1, i + 1) == '/' then
            local nl = text:find('\n', i + 2, true)
            if not nl then
                break
            end
            i = nl -- keep the newline so line numbers/whitespace survive
        elseif c == '/' and text:sub(i + 1, i + 1) == '*' then
            local close = text:find('*/', i + 2, true)
            if not close then
                break
            end
            i = close + 2
        else
            out[#out + 1] = c
            if c == '"' then
                in_string = true
            end
            i = i + 1
        end
    end
    return table.concat(out)
end

function Json.encode(value)
    if backend then
        return backend.encode(value)
    end
    return dkjson.encode(value)
end

-- Newtonsoft Formatting.Indented equivalent, for files meant to be
-- hand-edited (locations.json). Both backends are dkjson-derived and accept
-- the same options table.
function Json.encode_indented(value)
    if backend then
        return backend.encode(value, { indent = true })
    end
    return dkjson.encode(value, { indent = true })
end

-- Ordered decoding ------------------------------------------------------------
-- The config files are JSON objects whose key order matters: it is menu order,
-- and when two categories claim the same model the first one keeps it (the
-- System.Text.Json JsonDocument upstream reads them with preserves order).
-- Lua tables do not, so decode_ordered records each object's keys on the side
-- and ordered_pairs walks them. It also skips comments and tolerates trailing
-- commas, matching upstream's JsonCommentHandling.Skip + AllowTrailingCommas.

local key_order = setmetatable({}, { __mode = 'k' })

local ESCAPES = { ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t' }

local function decode_error(position, message)
    error({ json_error = ('%s at character %d'):format(message, position) }, 0)
end

local function skip_space(text, i)
    while true do
        i = text:find('[^ \t\r\n]', i) or #text + 1
        local two = text:sub(i, i + 1)
        if two == '//' then
            i = (text:find('\n', i + 2, true) or #text) + 1
        elseif two == '/*' then
            local close = text:find('*/', i + 2, true)
            if not close then
                decode_error(i, 'unterminated comment')
            end
            i = close + 2
        else
            return i
        end
    end
end

local parse_value

local function parse_string(text, i)
    local out = {}
    i = i + 1
    while true do
        local c = text:sub(i, i)
        if c == '' then
            decode_error(i, 'unterminated string')
        elseif c == '"' then
            return table.concat(out), i + 1
        elseif c == '\\' then
            local e = text:sub(i + 1, i + 1)
            if e == 'u' then
                local code = tonumber(text:sub(i + 2, i + 5), 16)
                if not code then
                    decode_error(i, 'bad unicode escape')
                end
                i = i + 6
                -- Surrogate pair: a high surrogate followed by \uDC00-\uDFFF.
                if code >= 0xD800 and code <= 0xDBFF and text:sub(i, i + 1) == '\\u' then
                    local low = tonumber(text:sub(i + 2, i + 5), 16)
                    if low and low >= 0xDC00 and low <= 0xDFFF then
                        code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
                        i = i + 6
                    end
                end
                out[#out + 1] = utf8.char(code)
            elseif ESCAPES[e] then
                out[#out + 1] = ESCAPES[e]
                i = i + 2
            else
                decode_error(i, 'bad escape')
            end
        else
            local stop = text:find('["\\]', i) or #text + 1
            out[#out + 1] = text:sub(i, stop - 1)
            i = stop
        end
    end
end

local function parse_container(text, i, close, read_entry)
    i = skip_space(text, i + 1)
    if text:sub(i, i) == close then
        return i + 1
    end
    while true do
        i = skip_space(text, read_entry(i))
        local c = text:sub(i, i)
        if c == ',' then
            i = skip_space(text, i + 1)
            if text:sub(i, i) == close then -- trailing comma
                return i + 1
            end
        elseif c == close then
            return i + 1
        else
            decode_error(i, "expected ',' or '" .. close .. "'")
        end
    end
end

parse_value = function(text, i)
    i = skip_space(text, i)
    local c = text:sub(i, i)
    if c == '{' then
        local object, order = {}, {}
        local stop = parse_container(text, i, '}', function(at)
            if text:sub(at, at) ~= '"' then
                decode_error(at, 'expected a property name')
            end
            local key, after = parse_string(text, at)
            after = skip_space(text, after)
            if text:sub(after, after) ~= ':' then
                decode_error(after, "expected ':'")
            end
            local value
            value, after = parse_value(text, after + 1)
            if value ~= nil then
                if object[key] == nil then
                    order[#order + 1] = key
                end
                object[key] = value
            end
            return after
        end)
        key_order[object] = order
        return object, stop
    elseif c == '[' then
        local array = {}
        local stop = parse_container(text, i, ']', function(at)
            local value, after = parse_value(text, at)
            array[#array + 1] = value
            return after
        end)
        return array, stop
    elseif c == '"' then
        return parse_string(text, i)
    elseif text:sub(i, i + 3) == 'true' then
        return true, i + 4
    elseif text:sub(i, i + 4) == 'false' then
        return false, i + 5
    elseif text:sub(i, i + 3) == 'null' then
        return nil, i + 4
    end
    local number = text:match('^-?%d+%.?%d*[eE]?[+-]?%d*', i)
    if number and number ~= '' and number ~= '-' then
        local value = tonumber(number)
        if value == nil then
            decode_error(i, 'bad number')
        end
        return math.tointeger(value) or value, i + #number
    end
    decode_error(i, 'unexpected character')
end

-- Returns the decoded value, or nil and an error message for invalid input.
function Json.decode_ordered(text)
    if type(text) ~= 'string' then
        return nil, 'no input'
    end
    local ok, value, stop = pcall(parse_value, text, 1)
    if not ok then
        return nil, type(value) == 'table' and value.json_error or tostring(value)
    end
    if skip_space(text, stop) <= #text then
        return nil, ('unexpected trailing content at character %d'):format(skip_space(text, stop))
    end
    return value
end

-- Iterates an object from decode_ordered in file order. Falls back to pairs
-- for any other table.
function Json.ordered_pairs(object)
    local order = key_order[object]
    if not order then
        return pairs(object)
    end
    local index = 0
    return function()
        index = index + 1
        local key = order[index]
        if key ~= nil then
            return key, object[key]
        end
    end
end

function Json.is_object(value)
    return type(value) == 'table' and key_order[value] ~= nil
end

-- Returns the decoded value, or nil if the input is nil, empty, or invalid.
function Json.decode(text)
    if type(text) ~= 'string' or text == '' then
        return nil
    end
    text = strip_comments(text)
    if backend then
        local ok, result = pcall(backend.decode, text)
        if ok then
            return result
        end
        return nil
    end
    local result = dkjson.decode(text)
    return result
end

return Json
