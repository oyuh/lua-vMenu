-- Port of vMenu.Enhanced.Actions.Server/Handlers/TeleportAction.cs: the teleport
-- categories in config/teleport-categories.json, sent to every player allowed
-- to see them, and edited by staff through server actions. A change only
-- sticks once the file is written; a failed write puts the list back.

local Log = require('shared.log')
local Json = require('shared.json_compat')
local Permissions = require('server.permissions')
local Actions = require('server.actions')

local Teleport = {}

local CONFIG_FILE = 'config/teleport-categories.json'
local EVENT_REQUEST = 'vMenu.Enhanced:Teleport:Request'
local EVENT_SET = 'vMenu.Enhanced:Teleport:Set'
local MANAGE = 'vMenu.Enhanced.Menus.TeleportMenu.Manage'
local SEE = 'vMenu.Enhanced.Menus.TeleportMenu.Category'

local categories = {}
local payload = '[]'

local function trimmed(value)
    if type(value) ~= 'string' then
        return nil
    end
    value = value:match('^%s*(.-)%s*$')
    return value ~= '' and value or nil
end

local function index_of(list, name)
    name = trimmed(name)
    if not name then
        return nil
    end
    name = name:lower()
    for index, item in ipairs(list) do
        if item.name:lower() == name then
            return index
        end
    end
    return nil
end

-- Writes value as JSON. A table with a `keys` list is an object written in that
-- order, so a hand-edited file keeps upstream's shape across saves; any other
-- table is an array.
local function write(value, depth, pretty)
    if type(value) ~= 'table' then
        return Json.encode(value)
    end
    local newline = pretty and '\n' or ''
    local inner = pretty and ('  '):rep(depth + 1) or ''
    local outer = pretty and ('  '):rep(depth) or ''
    local parts = {}
    if value.keys then
        for _, key in ipairs(value.keys) do
            if value[key] ~= nil then
                parts[#parts + 1] = inner
                    .. Json.encode(key)
                    .. (pretty and ': ' or ':')
                    .. write(value[key], depth + 1, pretty)
            end
        end
        return #parts == 0 and '{}' or '{' .. newline .. table.concat(parts, ',' .. newline) .. newline .. outer .. '}'
    end
    for _, item in ipairs(value) do
        parts[#parts + 1] = inner .. write(item, depth + 1, pretty)
    end
    return #parts == 0 and '[]' or '[' .. newline .. table.concat(parts, ',' .. newline) .. newline .. outer .. ']'
end

local function encode(list, pretty)
    local shaped = {}
    for index, category in ipairs(list) do
        local locations = {}
        for at, location in ipairs(category.locations) do
            locations[at] = {
                keys = { 'name', 'description', 'position', 'heading' },
                name = location.name,
                description = location.description,
                position = { keys = { 'x', 'y', 'z' }, x = location.x, y = location.y, z = location.z },
                heading = location.heading,
            }
        end
        shaped[index] = {
            keys = { 'name', 'description', 'locations' },
            name = category.name,
            description = category.description,
            locations = locations,
        }
    end
    return write(shaped, 0, pretty)
end

local function send_to(player)
    if Permissions.is_allowed(player, SEE) then
        TriggerClientEvent(EVENT_SET, player, payload)
    end
end

local function commit(source, what, undo)
    if not SaveResourceFile(GetCurrentResourceName(), CONFIG_FILE, encode(categories, true), -1) then
        Log.error(('[Teleport] %s could not be written, so nothing was changed.'):format(CONFIG_FILE))
        undo()
        return Actions.FAILED
    end
    payload = encode(categories, false)
    for _, player in ipairs(GetPlayers()) do
        send_to(tonumber(player))
    end
    Log.debug(('[Teleport] Player %d %s.'):format(source, what))
    return Actions.OK
end

-- Actions ----------------------------------------------------------------------------

local function add_category(source, args)
    local name = trimmed(args[1])
    if not name or type(args[2]) ~= 'string' then
        return Actions.INVALID_REQUEST
    end
    if index_of(categories, name) then
        return Actions.REFUSED
    end
    local added = { name = name, description = trimmed(args[2]) or '', locations = {} }
    categories[#categories + 1] = added
    return commit(source, ("added category '%s'"):format(name), function()
        table.remove(categories)
    end)
end

local function add_location(source, args)
    local name = trimmed(args[2])
    if not name or type(args[3]) ~= 'string' then
        return Actions.INVALID_REQUEST
    end
    local at = index_of(categories, args[1])
    if not at then
        return Actions.NOT_FOUND
    end
    local x, y, z = tonumber(args[4]), tonumber(args[5]), tonumber(args[6])
    if not (x and y and z) then
        return Actions.INVALID_REQUEST
    end
    local category = categories[at]
    if index_of(category.locations, name) then
        return Actions.REFUSED
    end
    category.locations[#category.locations + 1] = {
        name = name,
        description = trimmed(args[3]) or '',
        x = x,
        y = y,
        z = z,
        heading = tonumber(args[7]),
    }
    return commit(source, ("added '%s' to '%s'"):format(name, category.name), function()
        table.remove(category.locations)
    end)
end

local function remove_category(source, args)
    if not trimmed(args[1]) then
        return Actions.INVALID_REQUEST
    end
    local at = index_of(categories, args[1])
    if not at then
        return Actions.NOT_FOUND
    end
    local removed = table.remove(categories, at)
    return commit(source, ("removed category '%s'"):format(removed.name), function()
        table.insert(categories, at, removed)
    end)
end

local function remove_location(source, args)
    if not trimmed(args[2]) then
        return Actions.INVALID_REQUEST
    end
    local category_at = index_of(categories, args[1])
    local category = category_at and categories[category_at]
    local at = category and index_of(category.locations, args[2])
    if not at then
        return Actions.NOT_FOUND
    end
    local removed = table.remove(category.locations, at)
    return commit(source, ("removed '%s' from '%s'"):format(removed.name, category.name), function()
        table.insert(category.locations, at, removed)
    end)
end

-- Loading ----------------------------------------------------------------------------

local function load()
    local contents = LoadResourceFile(GetCurrentResourceName(), CONFIG_FILE)
    if not contents or contents:match('^%s*$') then
        Log.info(('[Teleport] No %s found, so the category menu starts empty.'):format(CONFIG_FILE))
        return
    end
    local raw = Json.decode(contents)
    if type(raw) ~= 'table' then
        Log.error(('[Teleport] %s could not be parsed, so the category menu starts empty.'):format(CONFIG_FILE))
        return
    end
    for _, read in ipairs(raw) do
        local name = trimmed(Json.field(read, 'name'))
        if not name then
            Log.warning(('[Teleport] Skipping a category in %s: it has no name.'):format(CONFIG_FILE))
        else
            local locations = {}
            for _, location in ipairs(Json.field(read, 'locations') or {}) do
                local location_name = trimmed(Json.field(location, 'name'))
                local position = Json.field(location, 'position')
                if not location_name then
                    Log.warning(("[Teleport] Skipping a location in '%s': it has no name."):format(name))
                elseif type(position) ~= 'table' then
                    Log.warning(("[Teleport] Skipping '%s' in '%s': it has no position."):format(location_name, name))
                else
                    locations[#locations + 1] = {
                        name = location_name,
                        description = tostring(Json.field(location, 'description') or ''),
                        x = tonumber(Json.field(position, 'x')) or 0.0,
                        y = tonumber(Json.field(position, 'y')) or 0.0,
                        z = tonumber(Json.field(position, 'z')) or 0.0,
                        heading = tonumber(Json.field(location, 'heading')),
                    }
                end
            end
            categories[#categories + 1] = {
                name = name,
                description = tostring(Json.field(read, 'description') or ''),
                locations = locations,
            }
            Log.debug(("[Teleport] Category '%s' holds %d location(s)."):format(name, #locations))
        end
    end
    payload = encode(categories, false)
end

function Teleport.init()
    load()
    Actions.register('TeleportMenu.AddCategory', MANAGE, add_category)
    Actions.register('TeleportMenu.AddLocation', MANAGE, add_location)
    Actions.register('TeleportMenu.RemoveCategory', MANAGE, remove_category)
    Actions.register('TeleportMenu.RemoveLocation', MANAGE, remove_location)
    RegisterNetEvent(EVENT_REQUEST, function()
        send_to(source)
    end)
end

return Teleport
