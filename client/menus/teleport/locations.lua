-- Port of vMenu.Enhanced.Menus/Teleport/TeleportSync.cs and TeleportCategory.cs:
-- the teleport categories the server keeps in config/teleport-categories.json,
-- as { name, description, locations = { { name, description, position, heading } } }.

local Log = require('shared.log')
local Json = require('shared.json_compat')

local Locations = {}

local EVENT_REQUEST = 'vMenu.Enhanced:Teleport:Request'
local EVENT_SET = 'vMenu.Enhanced:Teleport:Set'

local categories = {}
local listeners = {}

function Locations.categories()
    return categories
end

function Locations.on_changed(listener)
    listeners[#listeners + 1] = listener
end

local function text(value)
    return value ~= nil and tostring(value) or ''
end

-- Read case-insensitively, like upstream's deserializer.
local function read(payload)
    local raw = Json.decode(payload)
    if type(raw) ~= 'table' then
        return nil
    end
    local read_categories = {}
    for _, category in ipairs(raw) do
        local locations = {}
        for _, location in ipairs(Json.field(category, 'locations') or {}) do
            local position = Json.field(location, 'position') or {}
            locations[#locations + 1] = {
                name = text(Json.field(location, 'name')),
                description = text(Json.field(location, 'description')),
                x = tonumber(Json.field(position, 'x')) or 0.0,
                y = tonumber(Json.field(position, 'y')) or 0.0,
                z = tonumber(Json.field(position, 'z')) or 0.0,
                heading = tonumber(Json.field(location, 'heading')),
            }
        end
        read_categories[#read_categories + 1] = {
            name = text(Json.field(category, 'name')),
            description = text(Json.field(category, 'description')),
            locations = locations,
        }
    end
    return read_categories
end

function Locations.register_events()
    RegisterNetEvent(EVENT_SET, function(payload)
        local read_categories = read(payload)
        if not read_categories then
            Log.error('[Teleport] The locations the server sent could not be read: ' .. tostring(payload))
            return
        end
        categories = read_categories
        Log.debug(('[Teleport] Received %d category/categories.'):format(#categories))
        for _, listener in ipairs(listeners) do
            listener()
        end
    end)
end

function Locations.request()
    TriggerServerEvent(EVENT_REQUEST)
end

return Locations
