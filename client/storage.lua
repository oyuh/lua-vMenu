-- Port of vMenu.Enhanced.Storage/KvpStore.cs, KvpEnvelope.cs and
-- vMenu.Enhanced.Serialization/JsonMerge.cs. Every KVP this resource writes is
-- a JSON envelope, never the typed natives (whose unset value reads as zero):
--   {"key":"vmenu_...","value":...,"type":"bool|int|float|string|json","version":1}
-- Same shape and key names as upstream, so saves move between the two builds.

local Log = require('shared.log')
local Json = require('shared.json_compat')

local Storage = {}

Storage.INITIAL_VERSION = 1
Storage.PREFIX = 'vmenu_'

local cache = {} -- key -> { value = ..., version = n, type = ... }
local reported = {}

local function complain(key, problem)
    if not reported[key] then
        reported[key] = true
        Log.warning(("[Storage] '%s' %s."):format(key, problem))
    end
end

-- Field order matches the C# envelope class, so a fresh save is byte for byte
-- what upstream would write for the same primitive value.
local function encode_envelope(key, value_json, kind, version, merged_by)
    local parts = {
        '{"key":',
        Json.encode(key),
        ',"value":',
        value_json,
        ',"type":',
        Json.encode(kind),
        ',"version":',
        tostring(version),
    }
    if merged_by then
        parts[#parts + 1] = ',"mergedBy":' .. tostring(merged_by)
    end
    parts[#parts + 1] = '}'
    return table.concat(parts)
end

-- Case-insensitive property lookup, like PropertyNameCaseInsensitive.
local function field(object, name)
    if object[name] ~= nil then
        return object[name]
    end
    local wanted = name:lower()
    for key, value in pairs(object) do
        if type(key) == 'string' and key:lower() == wanted then
            return value
        end
    end
    return nil
end

local function read_envelope(raw)
    if raw == nil or raw == '' then
        return nil
    end
    local envelope = Json.decode_ordered(raw)
    if not Json.is_object(envelope) then
        return nil
    end
    return envelope
end

function Storage.read_raw(key)
    return GetResourceKvpString(key)
end

-- The stored value for key, or nil when it is absent, unreadable, or of a
-- different type. Also returns the stored version, which may exceed
-- known_version when a newer vMenu wrote it (write then has to merge).
function Storage.read(key, expected_type, known_version)
    local cached = cache[key]
    if cached and cached.type == expected_type then
        return cached.value, cached.version
    end

    local raw = Storage.read_raw(key)
    if raw == nil or raw == '' then
        return nil, known_version
    end
    local envelope = read_envelope(raw)
    if not envelope then
        complain(key, 'is not readable as a vMenu envelope, so it is being ignored')
        return nil, known_version
    end

    local stored_type = field(envelope, 'type')
    if stored_type ~= expected_type then
        complain(
            key,
            ("holds a '%s' but was read as a '%s', so it is being ignored"):format(tostring(stored_type), expected_type)
        )
        return nil, known_version
    end
    if field(envelope, 'key') ~= key then
        complain(
            key,
            ("names itself '%s', which is not the key it is stored under"):format(tostring(field(envelope, 'key')))
        )
    end
    local merged_by = field(envelope, 'mergedBy')
    if type(merged_by) == 'number' and merged_by < known_version then
        complain(
            key,
            (
                'was last saved by an older vMenu (version %d, this build understands %d). Anything added after '
                .. 'version %d was kept through that save but not written by it, so it may not agree with the rest'
            ):format(merged_by, known_version, merged_by)
        )
    end

    local version = math.tointeger(field(envelope, 'version')) or 0
    local value = field(envelope, 'value')
    cache[key] = { value = value, version = version, type = expected_type }
    return value, version
end

-- The stored version from the envelope header, or nil when there is none.
function Storage.version_of(key)
    if cache[key] then
        return cache[key].version
    end
    local envelope = read_envelope(Storage.read_raw(key))
    return envelope and math.tointeger(field(envelope, 'version')) or nil
end

local function is_array(value)
    return type(value) == 'table' and not Json.is_object(value) and (next(value) == nil or value[1] ~= nil)
end

local function is_object(value)
    return type(value) == 'table' and not is_array(value)
end

-- JsonMerge.Merge: preferred wins where both have a value; object keys only
-- fallback has are kept, at every level. Arrays and scalars come whole from
-- preferred.
function Storage.merge(preferred, fallback)
    if not is_object(preferred) or not is_object(fallback) then
        return preferred
    end
    local merged = {}
    for key, value in pairs(preferred) do
        local other = fallback[key]
        merged[key] = other ~= nil and Storage.merge(value, other) or value
    end
    for key, value in pairs(fallback) do
        if preferred[key] == nil then
            merged[key] = value
        end
    end
    return merged
end

-- JsonMerge.IsSupersetOf: whether candidate holds every key and array element
-- required does. Scalar values may differ; only missing structure is loss.
function Storage.covers(candidate, required)
    if is_object(required) then
        if not is_object(candidate) then
            return false
        end
        for key, value in pairs(required) do
            if candidate[key] == nil or not Storage.covers(candidate[key], value) then
                return false
            end
        end
        return true
    elseif is_array(required) and type(required) == 'table' then
        if not is_array(candidate) or #candidate ~= #required then
            return false
        end
        for index = 1, #required do
            if not Storage.covers(candidate[index], required[index]) then
                return false
            end
        end
        return true
    end
    return true
end

-- Writes value. Refuses (returns false, changes nothing) when a newer vMenu
-- wrote fields this build cannot carry through the save.
function Storage.write(key, kind, version, value)
    local stored = Storage.version_of(key)
    if stored and stored > version then
        -- A newer build wrote this. Carry its unknown fields forward, and only
        -- overwrite when every one of them survives the merge.
        local envelope = read_envelope(Storage.read_raw(key))
        local stored_value = envelope and field(envelope, 'value')
        if stored_value ~= nil then
            local merged = Storage.merge(value, stored_value)
            if Storage.covers(merged, stored_value) then
                SetResourceKvp(key, encode_envelope(key, Json.encode(merged), kind, stored, version))
                cache[key] = { value = value, version = stored, type = kind }
                reported[key] = nil
                return true
            end
        end
        Log.warning(
            (
                "[Storage] '%s' was saved by a newer version of vMenu "
                .. '(version %d, this build understands %d), and it holds data '
                .. 'this build could not carry through the save. Refusing to '
                .. 'overwrite it, because doing so would discard that data.'
            ):format(key, stored, version)
        )
        return false
    end

    SetResourceKvp(key, encode_envelope(key, Json.encode(value), kind, version))
    cache[key] = { value = value, version = version, type = kind }
    reported[key] = nil
    return true
end

function Storage.delete(key)
    DeleteResourceKvp(key)
    cache[key] = nil
    reported[key] = nil
end

function Storage.write_raw(key, envelope)
    SetResourceKvp(key, envelope)
    cache[key] = nil
    reported[key] = nil
end

-- Every key under prefix, collected first so callers can delete while looping.
function Storage.keys(prefix)
    local keys = {}
    local handle = StartFindKvp(prefix)
    if handle == -1 then
        return keys
    end
    while true do
        local key = FindKvp(handle)
        if not key or key == '' then
            break
        end
        if key:sub(1, #prefix) == prefix then
            keys[#keys + 1] = key
        end
    end
    EndFindKvp(handle)
    return keys
end

function Storage.describe(prefix)
    local lines = {}
    for _, key in ipairs(Storage.keys(prefix)) do
        local raw = Storage.read_raw(key)
        lines[#lines + 1] = (raw == nil or raw == '') and (key .. ' = <empty>') or (key .. ' = ' .. raw)
    end
    return lines
end

function Storage.invalidate_cache()
    cache, reported = {}, {}
end

return Storage
