-- Ports of vMenu.Enhanced.Permissions/ClientPermissions.cs, PermissionsSync.cs
-- and the Client{Vehicle,Ped,Weapon}Permissions.cs helpers. The client's view
-- of what the local player may do is advisory only: the server re-checks
-- anything that matters. The server sends the smallest granted set, so a
-- permission ending in .All is stored as a subtree and a question inside it is
-- answered by walking up the asked-for name.

local Log = require('shared.log')
local PermissionPath = require('shared.permission_path')

local Permissions = {}

local EVENT_REQUEST = 'vMenu.Enhanced:Permissions:Request'
local EVENT_SET = 'vMenu.Enhanced:Permissions:Set'
local MAX_REQUEST_ATTEMPTS = 10
local REQUEST_RETRY_DELAY = 1000

-- Same order as VehicleClass ids; FromClassId falls back to Categories.All.
local VEHICLE_CLASS_CATEGORIES = {
    [0] = 'Compacts',
    'Sedans',
    'Suvs',
    'Coupes',
    'Muscle',
    'SportsClassics',
    'Sports',
    'Super',
    'Motorcycles',
    'OffRoad',
    'Industrial',
    'Utility',
    'Vans',
    'Cycles',
    'Boats',
    'Helicopters',
    'Planes',
    'Service',
    'Emergency',
    'Military',
    'Commercial',
    'Trains',
    'OpenWheel',
}

local VEHICLE_CATEGORIES = 'vMenu.Enhanced.Menus.VehicleSpawner.Categories'
local PED_CATEGORIES = 'vMenu.Enhanced.Menus.PedModels.Categories'
local WEAPON_CATEGORIES = 'vMenu.Enhanced.Menus.WeaponOptions.Categories'
local SUPPLEMENTAL = 'vMenu.Enhanced.SupplementalPermissions'

-- All keys lowercased: the C# sets compare OrdinalIgnoreCase.
local granted_exact = {}
local granted_subtrees = {} -- container paths granted in full, without .All
local resolved = {}
local grants_everything = false
-- Until a set arrives every check fails, so menus start locked, not open.
local received = false

local whitelisted = { vehicle = {}, ped = {}, weapon = {} }
local vehicle_category_by_model = {}

local listeners = {}

local function lower_set(list)
    local set = {}
    for _, value in ipairs(list or {}) do
        set[tostring(value):lower()] = true
    end
    return set
end

local function changed()
    for _, listener in ipairs(listeners) do
        local ok, err = pcall(listener)
        if not ok then
            Log.error('[Permissions] A permissions listener threw: ' .. tostring(err))
        end
    end
end

-- Menus build once and re-evaluate their gates from here.
function Permissions.on_changed(listener)
    listeners[#listeners + 1] = listener
end

function Permissions.has_received()
    return received
end

function Permissions.has_any()
    return received and (grants_everything or next(granted_exact) ~= nil or next(granted_subtrees) ~= nil)
end

function Permissions.apply(permissions)
    granted_exact, granted_subtrees, resolved = {}, {}, {}
    grants_everything = false
    for _, permission in ipairs(permissions or {}) do
        local lower = permission:lower()
        if lower == PermissionPath.EVERYTHING:lower() then
            grants_everything = true
        elseif PermissionPath.is_container_grant(permission) then
            granted_subtrees[lower:sub(1, -#PermissionPath.ALL_SUFFIX - 1)] = true
        else
            granted_exact[lower] = true
        end
    end
    received = true
    changed()
end

-- Back to the pre-sync state.
function Permissions.clear()
    granted_exact, granted_subtrees, resolved = {}, {}, {}
    grants_everything = false
    received = false
    changed()
end

-- After a KVP import restores settings, so gates read them again.
function Permissions.reevaluate()
    changed()
end

local function evaluate(lower)
    if granted_exact[lower] then
        return true
    end
    local container = PermissionPath.get_container(lower)
    while container do
        if granted_subtrees[container] then
            return true
        end
        container = PermissionPath.get_container(container)
    end
    return false
end

-- Inheritance is applied here, so callers never name a parent themselves.
function Permissions.is_allowed(permission)
    if grants_everything then
        return true
    end
    if not received then
        return false
    end
    local lower = permission:lower()
    local cached = resolved[lower]
    if cached == nil then
        cached = evaluate(lower)
        resolved[lower] = cached
    end
    return cached
end

-- Vehicles -------------------------------------------------------------------

function Permissions.is_whitelisted_vehicle(model)
    return whitelisted.vehicle[model:lower()] == true
end

-- The category a model was moved into, or nil when it is in its game class.
function Permissions.vehicle_category_of(model)
    return vehicle_category_by_model[model:lower()]
end

function Permissions.vehicle_class_permission(vehicle_class)
    local category = VEHICLE_CLASS_CATEGORIES[vehicle_class]
    return VEHICLE_CATEGORIES .. '.' .. (category or 'All')
end

function Permissions.can_spawn_vehicle_class(vehicle_class)
    return Permissions.is_allowed(Permissions.vehicle_class_permission(vehicle_class))
end

function Permissions.can_spawn_custom_category(category_name)
    return Permissions.is_allowed(VEHICLE_CATEGORIES .. '.' .. PermissionPath.category_segment(category_name))
end

function Permissions.can_spawn_vehicle(model, vehicle_class)
    if Permissions.is_whitelisted_vehicle(model) then
        return Permissions.is_allowed(SUPPLEMENTAL .. '.VehicleModels.' .. model:lower())
    end
    local category = Permissions.vehicle_category_of(model)
    if category then
        return Permissions.can_spawn_custom_category(category)
    end
    return Permissions.can_spawn_vehicle_class(vehicle_class)
end

-- Peds -----------------------------------------------------------------------

function Permissions.is_whitelisted_ped(model)
    return whitelisted.ped[model:lower()] == true
end

function Permissions.can_spawn_ped_category(category_name)
    return Permissions.is_allowed(PED_CATEGORIES .. '.' .. PermissionPath.category_segment(category_name))
end

function Permissions.can_spawn_ped(model, category_name)
    if Permissions.is_whitelisted_ped(model) then
        return Permissions.is_allowed(SUPPLEMENTAL .. '.Peds.' .. model:lower())
    end
    return Permissions.can_spawn_ped_category(category_name)
end

-- Weapons --------------------------------------------------------------------

function Permissions.is_whitelisted_weapon(spawn_name)
    return whitelisted.weapon[spawn_name:lower()] == true
end

function Permissions.can_use_weapon_category(category_name)
    return Permissions.is_allowed(WEAPON_CATEGORIES .. '.' .. PermissionPath.category_segment(category_name))
end

function Permissions.can_use_weapon(spawn_name, category_name)
    if Permissions.is_whitelisted_weapon(spawn_name) then
        return Permissions.is_allowed(SUPPLEMENTAL .. '.Weapons.' .. spawn_name:lower())
    end
    return Permissions.can_use_weapon_category(category_name)
end

-- Sync -------------------------------------------------------------------------

local function on_received(
    granted,
    whitelisted_vehicles,
    categorised,
    categories,
    whitelisted_peds,
    whitelisted_weapons
)
    -- Model data first, so the single change notification sees consistent state.
    whitelisted.vehicle = lower_set(whitelisted_vehicles)
    vehicle_category_by_model = {}
    categorised, categories = categorised or {}, categories or {}
    for index = 1, math.min(#categorised, #categories) do
        vehicle_category_by_model[categorised[index]:lower()] = categories[index]
    end
    whitelisted.ped = lower_set(whitelisted_peds)
    whitelisted.weapon = lower_set(whitelisted_weapons)
    Permissions.apply(granted)

    Log.debug(
        (
            '[Permissions] Received %d permission(s), %d whitelisted vehicle(s), %d '
            .. 'categorised vehicle(s), %d whitelisted ped(s) and %d whitelisted weapon(s).'
        ):format(
            #(granted or {}),
            #(whitelisted_vehicles or {}),
            #categorised,
            #(whitelisted_peds or {}),
            #(whitelisted_weapons or {})
        )
    )
end

-- The client asks instead of waiting to be told, because the server's join
-- event fires before this script runs. Retries cover the server handler not
-- being registered yet, which happens on a restart with players connected.
function Permissions.register_events()
    RegisterNetEvent(EVENT_SET, on_received)
    CreateThread(function()
        for _ = 1, MAX_REQUEST_ATTEMPTS do
            TriggerServerEvent(EVENT_REQUEST)
            Wait(REQUEST_RETRY_DELAY)
            if received then
                return
            end
        end
        Log.error(
            ('[Permissions] No permissions received after %d attempts. Everything stays locked.'):format(
                MAX_REQUEST_ATTEMPTS
            )
        )
    end)
end

return Permissions
