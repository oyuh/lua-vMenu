-- JSON layer with Newtonsoft-compatible behavior guarantees.
-- In-game this wraps CfxLua's built-in `json`; under busted it falls back to
-- dkjson. Contract notes (docs/contracts/kvp-saves.md):
--   * loads never throw — corrupt input returns nil (upstream catches and
--     degrades, so must we)
--   * C# Dictionary<int,...> arrives as string-keyed objects; callers keep
--     them string-keyed rather than converting, so re-encoding round-trips

local Json = {}

local backend = rawget(_G, 'json')
local dkjson
if backend == nil then
    dkjson = require('dkjson')
end

function Json.encode(value)
    if backend then
        return backend.encode(value)
    end
    return dkjson.encode(value)
end

-- Returns the decoded value, or nil if the input is nil, empty, or invalid.
function Json.decode(text)
    if type(text) ~= 'string' or text == '' then
        return nil
    end
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
