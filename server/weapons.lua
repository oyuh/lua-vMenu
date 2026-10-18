-- Ports of vMenu.Enhanced.Permissions.Server/WeaponCatalog.Resource.cs and
-- WeaponComponentCatalog.cs: sends a client the weapon categories (read by
-- server/catalogs.lua) and the components from config/weapon-components.json.
-- Which weapon takes which component is asked of the game on the client.

local Log = require('shared.log')
local Json = require('shared.json_compat')
local Catalogs = require('server.catalogs')

local Weapons = {}

local COMPONENT_FILE = 'config/weapon-components.json'
local EVENT_REQUEST = 'vMenu.Enhanced:Weapons:Request'
local EVENT_SET = 'vMenu.Enhanced:Weapons:Set'

local categories_payload = '[]'
local components_payload = '[]'

local function load_components()
    local contents = LoadResourceFile(GetCurrentResourceName(), COMPONENT_FILE)
    if not contents or contents:match('^%s*$') then
        Log.warning(('[Permissions] No %s found. No weapon offers any components.'):format(COMPONENT_FILE))
        return
    end
    local root, problem = Json.decode_ordered(contents)
    if not root then
        Log.error(
            ('[Permissions] %s could not be parsed, so no weapon offers any components: %s'):format(
                COMPONENT_FILE,
                tostring(problem)
            )
        )
        return
    end
    if not Json.is_object(root) then
        Log.error(
            ('[Permissions] %s has to hold a single object of component names, '):format(COMPONENT_FILE)
                .. 'so no weapon offers any components.'
        )
        return
    end
    local components, claimed = {}, {}
    for name, label in Json.ordered_pairs(root) do
        local spawn_name = name:match('^%s*(.-)%s*$'):upper()
        if spawn_name == '' then
            Log.debug(('[Permissions] Skipping a component without a name in %s.'):format(COMPONENT_FILE))
        elseif type(label) ~= 'string' then
            Log.warning(
                ("[Permissions] Skipping component '%s': the text to show for it has to be written in quotes."):format(
                    spawn_name
                )
            )
        elseif claimed[spawn_name] then
            Log.warning(
                ("[Permissions] '%s' is listed more than once in %s, so only the first one is used."):format(
                    spawn_name,
                    COMPONENT_FILE
                )
            )
        else
            claimed[spawn_name] = true
            label = label:match('^%s*(.-)%s*$')
            components[#components + 1] = { spawnName = spawn_name, label = label ~= '' and label or spawn_name }
        end
    end
    components_payload = Json.encode(components)
    if #components > 0 then
        Log.debug(('[Permissions] Loaded %d weapon component(s) from %s.'):format(#components, COMPONENT_FILE))
    end
end

-- Call once, after server/permissions.lua loaded the catalogs.
function Weapons.init()
    categories_payload = Json.encode(Catalogs.weapon_categories())
    load_components()
    RegisterNetEvent(EVENT_REQUEST, function()
        TriggerClientEvent(EVENT_SET, source, categories_payload, components_payload)
    end)
end

return Weapons
