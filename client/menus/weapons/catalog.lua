-- Ports of vMenu.Enhanced.Menus/Weapons/WeaponSync.cs, WeaponNames.cs,
-- WeaponComponentProbe.cs and the weapon half of CatalogValidity.cs: the
-- weapon list the server sends, what each weapon is called, which components
-- it takes, and which listed weapons this game does not have.

local Log = require('shared.log')
local Json = require('shared.json_compat')

local Catalog = {}

local EVENT_REQUEST = 'vMenu.Enhanced:Weapons:Request'
local EVENT_SET = 'vMenu.Enhanced:Weapons:Set'
local WAIT_TIMEOUT_MS = 10000
local RETRY_MS = 1000
local CHECKS_PER_FRAME = 50

-- { name, weapons = { { spawn_name, label } } } and { spawn_name, label }.
local categories, components = {}, {}
local received = false
local accepted_components = {}
local invalid = {}
local listeners = {}

function Catalog.categories()
    return categories
end

function Catalog.has_received()
    return received
end

function Catalog.on_changed(listener)
    listeners[#listeners + 1] = listener
end

-- The listed weapon with this spawn name, and its category, or nil.
function Catalog.find(spawn_name)
    local wanted = spawn_name:lower()
    for _, category in ipairs(categories) do
        for _, weapon in ipairs(category.weapons) do
            if weapon.spawn_name:lower() == wanted then
                return weapon, category.name
            end
        end
    end
    return nil
end

-- Every listed weapon as { spawn_name, category }, in list order.
function Catalog.listed()
    local listed = {}
    for _, category in ipairs(categories) do
        for _, weapon in ipairs(category.weapons) do
            listed[#listed + 1] = { spawn_name = weapon.spawn_name, category = category.name }
        end
    end
    return listed
end

-- The game's own text for a label, else the label, else the fallback.
function Catalog.resolve_name(label, fallback)
    if label ~= '' and DoesTextLabelExist(label) then
        local text = GetLabelText(label)
        if text and not text:match('^%s*$') and text ~= 'NULL' then
            return text
        end
    end
    return label ~= '' and label or fallback
end

function Catalog.weapon_name(weapon)
    return Catalog.resolve_name(weapon.label, weapon.spawn_name)
end

-- The components this weapon takes, asked of the game once per weapon.
function Catalog.components_for(weapon_hash)
    local cached = accepted_components[weapon_hash]
    if cached then
        return cached
    end
    local accepted = {}
    for _, component in ipairs(components) do
        if DoesWeaponTakeWeaponComponent(weapon_hash, GetHashKey(component.spawn_name)) then
            accepted[#accepted + 1] = component
        end
    end
    accepted_components[weapon_hash] = accepted
    return accepted
end

function Catalog.is_valid(spawn_name)
    return not invalid[spawn_name:lower()]
end

-- Spread over frames: the list can hold hundreds of weapons.
local function check_validity()
    local found = {}
    for index, weapon in ipairs(Catalog.listed()) do
        if index % CHECKS_PER_FRAME == 0 then
            Wait(0)
        end
        if not IsWeaponValid(GetHashKey(weapon.spawn_name)) then
            found[weapon.spawn_name:lower()] = true
        end
    end
    invalid = found
end

local function text(value)
    return value ~= nil and tostring(value) or ''
end

local function read(payload)
    local raw = Json.decode(payload)
    if type(raw) ~= 'table' then
        return nil
    end
    local read_list = {}
    for _, category in ipairs(raw) do
        local weapons = {}
        for _, weapon in ipairs(Json.field(category, 'weapons') or {}) do
            weapons[#weapons + 1] = {
                spawn_name = text(Json.field(weapon, 'spawnName')),
                label = text(Json.field(weapon, 'label')),
            }
        end
        read_list[#read_list + 1] = { name = text(Json.field(category, 'name')), weapons = weapons }
    end
    return read_list
end

local function read_components(payload)
    local raw = Json.decode(payload)
    if type(raw) ~= 'table' then
        return nil
    end
    local read_list = {}
    for _, component in ipairs(raw) do
        read_list[#read_list + 1] = {
            spawn_name = text(Json.field(component, 'spawnName')),
            label = text(Json.field(component, 'label')),
        }
    end
    return read_list
end

function Catalog.register_events()
    RegisterNetEvent(EVENT_SET, function(categories_payload, components_payload)
        local read_categories = read(categories_payload)
        if not read_categories then
            Log.error('[Weapons] The weapons the server sent could not be read.')
            return
        end
        local read_list = read_components(components_payload)
        if not read_list then
            Log.error('[Weapons] The weapon components the server sent could not be read, so no weapon offers any.')
        end
        categories, components = read_categories, read_list or {}
        accepted_components = {}
        received = true
        Log.debug(('[Weapons] Received %d category/categories and %d component(s).'):format(#categories, #components))
        CreateThread(function()
            check_validity()
            for _, listener in ipairs(listeners) do
                listener()
            end
        end)
    end)
end

function Catalog.request()
    TriggerServerEvent(EVENT_REQUEST)
end

-- Waits for the first list, asking again every second. Call from a thread.
function Catalog.wait_for_first()
    local waited = 0
    while not received and waited < WAIT_TIMEOUT_MS do
        Wait(RETRY_MS)
        waited = waited + RETRY_MS
        if not received then
            Catalog.request()
        end
    end
    if not received then
        Log.error(
            ('[Weapons] No weapons received after %dms, so the menu is being built empty.'):format(WAIT_TIMEOUT_MS)
        )
    end
end

return Catalog
