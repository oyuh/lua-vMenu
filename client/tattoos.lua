-- Port of vMenu/data/TattoosData.cs: sorts the 3400+ overlay records from
-- client/data/overlays.json (shipped verbatim from upstream) into gendered
-- per-zone collections, plus the addon tattoos from config/tattoos.json
-- (parsed into State.tattoos by client/events.lua).

local Json = require('shared.json_compat')
local State = require('client.state')

local Tattoos = {}

-- TattooZone enum values (zoneId in overlays.json is the number).
Tattoos.ZONE_TORSO = 0
Tattoos.ZONE_HEAD = 1
Tattoos.ZONE_LEFT_ARM = 2
Tattoos.ZONE_RIGHT_ARM = 3
Tattoos.ZONE_LEFT_LEG = 4
Tattoos.ZONE_RIGHT_LEG = 5
Tattoos.ZONE_UNKNOWN = 6
Tattoos.ZONE_NONE = 7

local function new_collection()
    return {
        HAIR = {},
        TORSO = {},
        HEAD = {},
        LEFT_ARM = {},
        RIGHT_ARM = {},
        LEFT_LEG = {},
        RIGHT_LEG = {},
        BADGES = {},
        ADDONS = {},
    }
end

Tattoos.male = new_collection()
Tattoos.female = new_collection()

local ZONE_KEYS = {
    [Tattoos.ZONE_TORSO] = 'TORSO',
    [Tattoos.ZONE_HEAD] = 'HEAD',
    [Tattoos.ZONE_LEFT_ARM] = 'LEFT_ARM',
    [Tattoos.ZONE_RIGHT_ARM] = 'RIGHT_ARM',
    [Tattoos.ZONE_LEFT_LEG] = 'LEFT_LEG',
    [Tattoos.ZONE_RIGHT_LEG] = 'RIGHT_LEG',
}

-- gender: 0 = male, 1 = female, 2 = both.
local function add_to(key, tattoo)
    if tattoo.gender == 0 or tattoo.gender == 2 then
        table.insert(Tattoos.male[key], tattoo)
    end
    if tattoo.gender == 1 or tattoo.gender == 2 then
        table.insert(Tattoos.female[key], tattoo)
    end
end

local is_data_setup = false

-- GenerateTattoosData: idempotent, called before the MpPedCustomization
-- tattoo menus are built.
function Tattoos.generate()
    if is_data_setup then
        return
    end
    is_data_setup = true

    local raw = LoadResourceFile(GetCurrentResourceName(), 'client/data/overlays.json') or '[]'
    local overlays = Json.decode(raw) or {}

    for _, tattoo in ipairs(overlays) do
        if tattoo.name ~= nil and tattoo.name ~= '' then
            if tattoo.name:lower():find('hair_', 1, true) then
                add_to('HAIR', tattoo)
            elseif tattoo.type == 'TYPE_TATTOO' then
                local zone_key = ZONE_KEYS[tattoo.zoneId]
                if zone_key then
                    add_to(zone_key, tattoo)
                end
            elseif tattoo.type == 'TYPE_BADGE' then
                add_to('BADGES', tattoo)
            end
        end
    end

    for _, tattoo in ipairs(State.tattoos) do
        add_to('ADDONS', tattoo)
    end
end

-- Test hook.
function Tattoos._reset()
    is_data_setup = false
    Tattoos.male = new_collection()
    Tattoos.female = new_collection()
end

return Tattoos
