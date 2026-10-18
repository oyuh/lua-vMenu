-- Port of vMenu.Enhanced.Localization (Localizer, CompiledLocalizer,
-- LanguageCatalog, LanguageTable, MenuText, Placeholders, LocalizationLog)
-- and MenuFramework/LanguageLoader.cs.
--
-- English is built in (shared/data/english.lua) and is the fallback for every
-- key another language leaves out. Other languages are language/<code>.json
-- files named in the vMenu.Enhanced.Languages setting.
--
-- Menu text is resolved late, so a language switch relabels menus in place:
--   'Plain text'                      a literal, never translated
--   Localization.key('a.b', { n = x }) a translation key with named arguments,
--                                     each itself menu text
--   Localization.from(fn)             text produced on demand, for GTA labels

local Log = require('shared.log')
local Json = require('shared.json_compat')
local English = require('shared.data.english')

local Localization = {}

local ENGLISH = 'en'
local FOLDER = 'language'
-- The generated template, which is a file to copy, not a language to load.
local TEMPLATE = 'example'

local tables = { [ENGLISH] = { code = ENGLISH, native_name = 'English', strings = English } }
local order = { ENGLISH }
local current = ENGLISH
local listeners = {}
local reported = {}

local function report_once(key, message)
    if not reported[key] then
        reported[key] = true
        Log.error(message)
    end
end

-- Never errors and never returns nil. A key missing even from English renders
-- as a visible marker instead of taking a menu down over a typo.
function Localization.get(key)
    local value = tables[current].strings[key]
    if value ~= nil then
        return value
    end
    -- A partial translation is expected; a gap in English is a bug in vMenu.
    value = English[key]
    if value ~= nil then
        return value
    end
    report_once('key:' .. key, ("[i18n] No 'en' text for key '%s'. Add it to the English table."):format(key))
    return '!!' .. key .. '!!'
end

-- Menu text --------------------------------------------------------------------------

function Localization.key(key, args)
    return { key = key, args = args }
end

function Localization.from(factory)
    return { factory = factory }
end

local resolve

-- Named {placeholder} substitution; "{{" and "}}" are escaped braces.
local function substitute(template, args)
    if not template:find('{', 1, true) and not template:find('}', 1, true) then
        return template
    end
    local out = {}
    local index, length = 1, #template
    while index <= length do
        local char = template:sub(index, index)
        if char == '}' then
            -- A lone '}' passes through, so an unbalanced string still renders.
            if template:sub(index + 1, index + 1) == '}' then
                index = index + 1
            end
            out[#out + 1] = '}'
        elseif char ~= '{' then
            out[#out + 1] = char
        elseif template:sub(index + 1, index + 1) == '{' then
            out[#out + 1] = '{'
            index = index + 1
        else
            local close = template:find('}', index + 1, true)
            if not close then
                -- Unterminated: emit the rest verbatim so the row still renders.
                out[#out + 1] = template:sub(index)
                break
            end
            local name = template:sub(index + 1, close - 1)
            local value
            for arg_name, arg_value in pairs(args or {}) do
                if arg_name:lower() == name:lower() then
                    value = resolve(arg_value)
                    break
                end
            end
            if value == nil then
                report_once(
                    'arg:' .. name .. ':' .. template,
                    ('[i18n] No argument named \'%s\' was supplied for "%s".'):format(name, template)
                )
                value = '!{' .. name .. '}!'
            end
            out[#out + 1] = value
            index = close
        end
        index = index + 1
    end
    return table.concat(out)
end

resolve = function(text)
    local kind = type(text)
    if kind == 'nil' then
        return ''
    elseif kind == 'string' then
        return text
    elseif kind == 'number' then
        return tostring(text)
    elseif text.factory then
        return text.factory() or ''
    end
    return substitute(Localization.get(text.key), text.args)
end

Localization.resolve = resolve

-- Languages ----------------------------------------------------------------------------

function Localization.current_language()
    return current
end

-- In registration order, English first, which is the language picker's order.
function Localization.available_languages()
    return order
end

function Localization.native_name(code)
    local entry = tables[code]
    return entry and entry.native_name or code
end

-- Raised after the language changes; menus relabel in place.
function Localization.on_changed(listener)
    listeners[#listeners + 1] = listener
end

-- False when the language is not registered; the current one is kept.
function Localization.set_language(code)
    code = (code or ''):lower()
    if not tables[code] then
        return false
    end
    if code == current then
        return true
    end
    current = code
    for _, listener in ipairs(listeners) do
        local ok, err = pcall(listener)
        if not ok then
            Log.error('[i18n] A language listener threw: ' .. tostring(err))
        end
    end
    return true
end

function Localization.register(code, native_name, strings)
    if not tables[code] then
        order[#order + 1] = code
    end
    -- Replacing in place keeps the picker order stable.
    tables[code] = { code = code, native_name = native_name, strings = strings }
end

local function read_language(code)
    local path = ('%s/%s.json'):format(FOLDER, code)
    local raw = LoadResourceFile(GetCurrentResourceName(), path)
    if raw == nil or raw:match('^%s*$') then
        Log.error(("[i18n] '%s' is listed but %s is missing or empty, so it is not available."):format(code, path))
        return
    end
    local file = Json.decode(raw)
    if type(file) ~= 'table' then
        Log.error(("[i18n] %s is not readable as JSON, so '%s' is not available."):format(path, code))
        return
    end
    local strings = {}
    local count = 0
    for key, value in pairs(type(file.strings) == 'table' and file.strings or {}) do
        if type(key) == 'string' and type(value) == 'string' then
            strings[key] = value
            count = count + 1
        end
    end
    if count == 0 then
        Log.error(("[i18n] %s has no strings, so '%s' is not available."):format(path, code))
        return
    end
    -- Falling back to the code keeps the picker from showing a blank row.
    local native_name = type(file.nativeName) == 'string' and not file.nativeName:match('^%s*$') and file.nativeName
        or code
    Localization.register(code, native_name, strings)
end

-- Registers every language the setting names. Call after Config.init and
-- before menus are built, since the picker's options are fixed once it exists.
function Localization.load(setting_name, configured)
    local seen = {}
    for part in (configured or ''):gmatch('[^,]+') do
        local code = part:match('^%s*(.-)%s*$'):lower()
        if code == ENGLISH then
            Log.warning(
                ("[i18n] '%s' lists 'en', which is being skipped. English is built into vMenu and is always "):format(
                    setting_name
                ) .. 'available, so it does not come from a file and cannot be overridden by one.'
            )
        elseif code == TEMPLATE then
            Log.warning(
                ("[i18n] '%s' lists '%s', which is being skipped. %s/%s.json is a generated template to copy."):format(
                    setting_name,
                    TEMPLATE,
                    FOLDER,
                    TEMPLATE
                )
            )
        elseif code ~= '' then
            if seen[code] then
                Log.warning(("[i18n] '%s' lists '%s' more than once."):format(setting_name, code))
            else
                seen[code] = true
                read_language(code)
            end
        end
    end
end

return Localization
