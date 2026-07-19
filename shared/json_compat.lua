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
