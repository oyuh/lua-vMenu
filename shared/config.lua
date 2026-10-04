-- Port of vMenu.Enhanced.Data/Configuration/ConfigStore.cs and ConvarValue.cs,
-- plus ClientConfig.cs / ServerConfig.cs, which only differed in whether the
-- server_only settings are readable. Settings are convars named in
-- shared/data/settings.lua; replicated ones (setr) reach clients through the
-- runtime, so there is no handshake.

local Log = require('shared.log')
local Platform = require('shared.platform')
local Catalog = require('shared.data.settings')

local Config = {}

-- Makes an unset convar distinguishable from one set to an empty value.
local UNSET = 'vMenu.Enhanced.Unset'
local ROOT = 'vMenu.Enhanced'

local TRUE = { ['true'] = true, ['1'] = true, yes = true, on = true }
local FALSE = { ['false'] = true, ['0'] = true, no = true, off = true }

local by_name = {}
for _, section in ipairs(Catalog) do
    for _, setting in ipairs(section.settings) do
        by_name[setting.name:lower()] = setting
    end
end

local include_server_only = false
local cache = {} -- lowercased convar -> raw string or false (unset)
local tracked = {} -- ordered convar names
local reported = {}
local watchers = {} -- lowercased convar -> { handler, ... }
local except_watchers = {} -- { { excluded = set, handler = fn } }
local secret = {}

-- ConvarValue.Normalise: trims, unquotes, and maps an empty value to nil.
function Config.normalise(raw)
    if raw == nil then
        return nil
    end
    local value = raw:match('^%s*(.-)%s*$')
    if #value > 1 and value:sub(1, 1) == '"' and value:sub(-1) == '"' then
        value = value:sub(2, -2):match('^%s*(.-)%s*$')
    end
    return value ~= '' and value or nil
end

function Config.parse_bool(raw)
    local value = Config.normalise(raw)
    if value == nil then
        return nil
    end
    value = value:lower()
    if TRUE[value] then
        return true
    end
    if FALSE[value] then
        return false
    end
    return nil
end

-- int.TryParse with NumberStyles.Integer: optional sign, digits, 32-bit range.
function Config.parse_int(raw)
    local value = Config.normalise(raw)
    if value == nil or not value:match('^[+-]?%d+$') then
        return nil
    end
    local parsed = math.tointeger(tonumber(value))
    if parsed == nil or parsed < -2147483648 or parsed > 2147483647 then
        return nil
    end
    return parsed
end

function Config.parse_float(raw)
    local value = Config.normalise(raw)
    if value == nil or not value:match('^[+-]?%d*%.?%d*[eE]?[+-]?%d*$') then
        return nil
    end
    return tonumber(value)
end

-- C#'s float.ToString("0.0###"): one to four decimals, trailing zeros trimmed.
local function format_float(value)
    local text = ('%.4f'):format(value):gsub('0+$', '')
    if text:sub(-1) == '.' then
        text = text .. '0'
    end
    return text
end

-- The default as the example file's "Default value" line spells it.
function Config.default_value(setting)
    if setting.type == 'bool' then
        return setting.default and 'true' or 'false'
    elseif setting.type == 'float' then
        return format_float(setting.default)
    end
    return tostring(setting.default)
end

-- The default as the example file's set/setr line spells it.
function Config.default_text(setting)
    if setting.type == 'string' then
        return '"' .. setting.default .. '"'
    end
    return Config.default_value(setting)
end

local function is_valid_segment(segment)
    return segment ~= '' and segment:match('^[%w_]+$') ~= nil
end

function Config.is_valid_name(name)
    if type(name) ~= 'string' or name:sub(1, #ROOT + 1) ~= ROOT .. '.' then
        return false
    end
    for segment in (name:sub(#ROOT + 2) .. '.'):gmatch('([^.]*)%.') do
        if not is_valid_segment(segment) then
            return false
        end
    end
    return true
end

Config.is_valid_segment = is_valid_segment

local function raw(convar)
    local value = GetConvar(convar, UNSET)
    if value == UNSET then
        return nil
    end
    return value
end

local function redact(convar, value)
    if secret[convar:lower()] then
        return value == nil and 'unset' or 'set (hidden)'
    end
    return value == nil and 'unset' or ("'" .. value .. "'")
end

local function invoke(convar, handler)
    local ok, err = pcall(handler)
    if not ok then
        Log.error(('[Config] A listener for %s threw: %s'):format(convar, tostring(err)))
    end
end

-- Reads every catalogued setting once, so later changes can be detected.
function Config.prime()
    cache, tracked, reported, secret = {}, {}, {}, {}
    for _, section in ipairs(Catalog) do
        for _, setting in ipairs(section.settings) do
            if include_server_only or not setting.server_only then
                if not Config.is_valid_name(setting.name) then
                    Log.error(
                        ("[Config] '%s' is not a usable convar name, so it can never be set."):format(setting.name)
                    )
                else
                    local key = setting.name:lower()
                    cache[key] = raw(setting.name) or false
                    tracked[#tracked + 1] = setting.name
                    if setting.server_only then
                        secret[key] = true
                    end
                end
            end
        end
    end
    Log.debug(('[Config] Tracking %d setting(s).'):format(#tracked))
end

function Config.tracked()
    return tracked
end

-- Calls handler whenever any of the named settings changes.
function Config.watch(names, handler)
    for _, name in ipairs(names) do
        local key = name:lower()
        if cache[key] == nil then
            Log.error(("[Config] '%s' is not being watched, so a listener on it can never fire."):format(name))
        else
            watchers[key] = watchers[key] or {}
            table.insert(watchers[key], handler)
        end
    end
end

-- Calls handler whenever any setting outside names changes.
function Config.watch_except(names, handler)
    local excluded = {}
    for _, name in ipairs(names) do
        excluded[name:lower()] = true
    end
    except_watchers[#except_watchers + 1] = { excluded = excluded, handler = handler }
end

function Config.unwatch(names, handler)
    for _, name in ipairs(names) do
        local handlers = watchers[name:lower()]
        for index = #(handlers or {}), 1, -1 do
            if handlers[index] == handler then
                table.remove(handlers, index)
            end
        end
    end
end

function Config.unwatch_except(handler)
    for index = #except_watchers, 1, -1 do
        if except_watchers[index].handler == handler then
            table.remove(except_watchers, index)
        end
    end
end

function Config.notify_changed(convar)
    local key = convar:lower()
    local previous = cache[key]
    if previous == nil then
        return
    end
    local current = raw(convar)
    if (previous or nil) == current then
        return
    end
    cache[key] = current or false
    reported[key] = nil

    Log.info(('[Config] %s changed to %s.'):format(convar, redact(convar, current)))

    -- Named listeners first, so one that caches the value has refreshed it
    -- before a broad subscriber reads it back.
    for _, handler in ipairs(watchers[key] or {}) do
        invoke(convar, handler)
    end
    for _, watcher in ipairs(except_watchers) do
        if not watcher.excluded[key] then
            invoke(convar, watcher.handler)
        end
    end
end

-- One line per setting, for the vmenu_config command.
function Config.describe()
    local lines = {}
    for _, section in ipairs(Catalog) do
        for _, setting in ipairs(section.settings) do
            if include_server_only or not setting.server_only then
                local untracked = cache[setting.name:lower()] == nil and '  [not tracked]' or ''
                lines[#lines + 1] = ('%s = %s (default %s)%s'):format(
                    setting.name,
                    redact(setting.name, raw(setting.name)),
                    Config.default_text(setting),
                    untracked
                )
            end
        end
    end
    return lines
end

local EXPECTED = { bool = 'true or false', int = 'a whole number', float = 'a number' }
local PARSERS = { bool = Config.parse_bool, int = Config.parse_int, float = Config.parse_float }

local function typed(convar, kind)
    local text = raw(convar)
    local parsed = PARSERS[kind](text)
    local normalised = Config.normalise(text)
    if parsed == nil and normalised ~= nil and not reported[convar:lower()] then
        reported[convar:lower()] = true
        Log.warning(
            ("[Config] %s is set to '%s', which is not %s. Treating it as unset."):format(
                convar,
                normalised,
                EXPECTED[kind]
            )
        )
    end
    return parsed
end

-- The parsed value, or nil when the convar is unset or unparseable.
function Config.get(convar)
    local setting = by_name[convar:lower()]
    local kind = setting and setting.type or 'string'
    if kind == 'string' then
        return Config.normalise(raw(convar))
    end
    return typed(convar, kind)
end

-- The parsed value, falling back to the catalogued default.
function Config.value(convar)
    local setting = by_name[convar:lower()]
    assert(setting, ("'%s' is not a catalogued setting"):format(convar))
    local value = Config.get(convar)
    if value == nil then
        return setting.default
    end
    return value
end

function Config.setting(convar)
    return by_name[convar:lower()]
end

local function apply_debug_mode()
    local side = IsDuplicityVersion() and 'Server' or 'Client'
    Log.set_debug(Config.value('vMenu.Enhanced.Debugging.' .. side))
end

-- Call once, first, from each entrypoint.
function Config.init()
    include_server_only = IsDuplicityVersion()
    Config.prime()
    apply_debug_mode()

    local side = include_server_only and 'Server' or 'Client'
    local debug_setting = 'vMenu.Enhanced.Debugging.' .. side
    Config.watch({ debug_setting }, apply_debug_mode)

    -- One listener per convar rather than a wildcard filter, which would look
    -- like this module quietly not working if it matched nothing.
    if Platform.has('AddConvarChangeListener') then
        for _, convar in ipairs(tracked) do
            AddConvarChangeListener(convar, function(name)
                Config.notify_changed(name)
            end)
        end
    else
        Log.warning('[Config] This server build has no AddConvarChangeListener, so setting changes need a restart.')
    end

    RegisterCommand('vmenu_config', function()
        if not Config.value(debug_setting) then
            Log.info(('[vMenu] This command only reports while %s is set to true.'):format(debug_setting))
            return
        end
        Log.info('[Config] Current values:')
        for _, line in ipairs(Config.describe()) do
            Log.info('[Config]   ' .. line)
        end
    end, include_server_only)
end

return Config
