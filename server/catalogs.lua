-- Ports of vMenu.Enhanced.Permissions.Server/ModelWhitelist.cs,
-- VehicleCategories.cs, PedCategories.cs and WeaponCatalog.cs: the owner-edited
-- config files that add permissions at runtime. Each category becomes a
-- permission under its menu's Categories container; each whitelisted model
-- becomes one under SupplementalPermissions. Files are read in key order
-- (Json.decode_ordered), because that is menu order and the first category to
-- claim a model keeps it.

local Log = require('shared.log')
local Json = require('shared.json_compat')
local PermissionPath = require('shared.permission_path')
local Registry = require('server.permission_registry')

local Catalogs = {}

local WHITELIST_FILE = 'config/model-whitelists.json'
local VEHICLE_FILE = 'config/vehicle-categories.json'
local PED_FILE = 'config/ped-models.json'
local WEAPON_FILE = 'config/weapons.json'

local VEHICLE_CATEGORIES = 'vMenu.Enhanced.Menus.VehicleSpawner.Categories'
local PED_CATEGORIES = 'vMenu.Enhanced.Menus.PedModels.Categories'
local WEAPON_CATEGORIES = 'vMenu.Enhanced.Menus.WeaponOptions.Categories'

local UNARMED = 'weapon_unarmed'

-- kind -> { json property, permission prefix }
local WHITELIST_KINDS = {
    vehicle = { 'vehicles', 'vMenu.Enhanced.SupplementalPermissions.VehicleModels' },
    ped = { 'peds', 'vMenu.Enhanced.SupplementalPermissions.Peds' },
    weapon = { 'weapons', 'vMenu.Enhanced.SupplementalPermissions.Weapons' },
}

local whitelists = {} -- kind -> { set = { [model] = true }, ordered = { ... } }
local vehicle_category_by_model = {}
local categorised_vehicles, vehicle_category_names = {}, {}
local ped_categories = {}
local weapon_categories = {}

local function trim(text)
    return (text:gsub('^%s+', ''):gsub('%s+$', ''))
end

-- Reads a config file into a top-level object, logging why when it can't.
-- missing_note says what happens without it.
local function read_object(path, missing_note, failed_note)
    local contents = LoadResourceFile(GetCurrentResourceName(), path)
    if contents == nil or contents:match('^%s*$') then
        Log.warning(('[Permissions] No %s found. %s'):format(path, missing_note))
        return nil
    end
    local document, err = Json.decode_ordered(contents)
    if document == nil then
        Log.error(('[Permissions] %s could not be parsed, so %s: %s'):format(path, failed_note, err))
        return nil
    end
    if not Json.is_object(document) then
        Log.error(('[Permissions] %s has to hold a single object of categories, so %s.'):format(path, failed_note))
        return nil
    end
    return document
end

-- Shared checks for one category name. Returns its permission, or nil after
-- logging why the category is skipped.
local function category_permission(container, name, raw_name, taken, label)
    local segment = PermissionPath.category_segment(name)
    if segment == '' then
        Log.warning(
            (
                "[Permissions] Skipping %s '%s': its name has no "
                .. 'letters or digits in it, so it could never be granted.'
            ):format(label, raw_name)
        )
        return nil
    end
    local permission = container .. '.' .. segment
    -- A name matching one vMenu declares itself would quietly hijack it.
    if Registry.get(permission) then
        Log.warning(
            (
                "[Permissions] Skipping %s '%s': '%s' is a permission "
                .. 'vMenu already declares, so pick a different name.'
            ):format(label, name, permission)
        )
        return nil
    end
    if taken[segment:lower()] then
        Log.warning(
            ("[Permissions] Skipping %s '%s': another category already claims '%s'."):format(label, name, permission)
        )
        return nil
    end
    taken[segment:lower()] = true
    return permission
end

-- Models held back from the class permissions and given their own instead.
-- A missing or unreadable file just means nothing is held back.
local function load_whitelist()
    whitelists = {}
    for kind in pairs(WHITELIST_KINDS) do
        whitelists[kind] = { set = {}, ordered = {} }
    end

    local document =
        read_object(WHITELIST_FILE, 'Every model is governed by its class permission.', 'no models are whitelisted')
    if not document then
        return
    end

    for kind, descriptor in pairs(WHITELIST_KINDS) do
        local property, prefix = descriptor[1], descriptor[2]
        local accepted = whitelists[kind]
        local models = document[property]
        for _, entry in ipairs(type(models) == 'table' and models or {}) do
            local model = type(entry) == 'string' and trim(entry):lower() or ''
            if model == '' then
                goto continue
            end
            if not PermissionPath.is_valid_segment(model) then
                Log.warning(
                    (
                        "[Permissions] Skipping whitelisted %s entry '%s': only "
                        .. 'letters, digits and underscores are usable in a permission.'
                    ):format(property, model)
                )
            elseif accepted.set[model] then
                Log.warning(("[Permissions] '%s' is listed more than once under '%s'."):format(model, property))
            else
                accepted.set[model] = true
                accepted.ordered[#accepted.ordered + 1] = model
                Registry.register_dynamic(prefix .. '.' .. model, WHITELIST_FILE)
            end
            ::continue::
        end
        table.sort(accepted.ordered)
        if #accepted.ordered > 0 then
            Log.debug(("[Permissions] Loaded %d whitelisted model(s) from '%s'."):format(#accepted.ordered, property))
        end
    end
end

-- Owner-defined vehicle categories, which take their models out of the game
-- class they would otherwise fall in.
local function load_vehicle_categories()
    vehicle_category_by_model, categorised_vehicles, vehicle_category_names = {}, {}, {}

    local document =
        read_object(VEHICLE_FILE, 'Every vehicle stays in its own game class.', 'no custom categories exist')
    if not document then
        return
    end

    local taken = {}
    for raw_name, models in Json.ordered_pairs(document) do
        local name = trim(raw_name)
        local permission = category_permission(VEHICLE_CATEGORIES, name, raw_name, taken, 'category')
        if not permission then
            goto continue
        end
        if type(models) ~= 'table' or Json.is_object(models) then
            Log.warning(
                ("[Permissions] Skipping category '%s': its value has to be a list of vehicle model names."):format(
                    name
                )
            )
            goto continue
        end

        local claimed = 0
        for _, entry in ipairs(models) do
            local model = type(entry) == 'string' and trim(entry):lower() or ''
            if model ~= '' then
                local owner = vehicle_category_by_model[model]
                if owner then
                    Log.warning(
                        ("[Permissions] '%s' is listed under both '%s' and '%s', so it stays in '%s'."):format(
                            model,
                            owner,
                            name,
                            owner
                        )
                    )
                else
                    vehicle_category_by_model[model] = name
                    categorised_vehicles[#categorised_vehicles + 1] = model
                    vehicle_category_names[#vehicle_category_names + 1] = name
                    claimed = claimed + 1
                end
            end
        end

        if claimed == 0 then
            Log.warning(
                ("[Permissions] Skipping category '%s': it has no vehicles in it, so it would show up empty."):format(
                    name
                )
            )
        else
            Registry.register_dynamic(permission, VEHICLE_FILE)
            Log.info(
                ("[Permissions] Category '%s' holds %d vehicle(s) and is granted by '%s'."):format(
                    name,
                    claimed,
                    permission
                )
            )
        end
        ::continue::
    end
end

-- Ped and weapon files share a shape: { "Category": { "model": "label" } }.
-- Returns the kept categories as { name = ..., entries = { { key, label } } }.
local function load_labelled_categories(spec)
    local document = read_object(spec.file, spec.missing_note, spec.failed_note)
    if not document then
        return {}
    end

    local categories, taken, claimed = {}, {}, {}
    for raw_name, entries in Json.ordered_pairs(document) do
        local name = trim(raw_name)
        local permission = category_permission(spec.container, name, raw_name, taken, spec.label)
        if not permission then
            goto continue
        end
        if not Json.is_object(entries) then
            Log.warning(
                (
                    "[Permissions] Skipping %s '%s': its value has to "
                    .. 'be a list of %s and the text to show for them.'
                ):format(spec.label, name, spec.entry_noun)
            )
            goto continue
        end

        local kept = {}
        for raw_key, raw_label in Json.ordered_pairs(entries) do
            local key = trim(raw_key):lower()
            if key == '' or (spec.accept and not spec.accept(key, name)) then
                goto next_entry
            end
            if type(raw_label) ~= 'string' then
                Log.warning(
                    (
                        "[Permissions] Skipping '%s' in %s '%s': the text "
                        .. 'to show for it has to be written in quotes.'
                    ):format(key, spec.label, name)
                )
            elseif claimed[key] then
                Log.warning(
                    ("[Permissions] '%s' is listed in more than one %s, so it stays in the first one."):format(
                        key,
                        spec.label
                    )
                )
            else
                claimed[key] = true
                -- An empty label leaves the row with nothing beside the name.
                local label = trim(raw_label)
                kept[#kept + 1] = { key, label ~= '' and label or key }
            end
            ::next_entry::
        end

        if #kept == 0 then
            Log.warning(
                ("[Permissions] Skipping %s '%s': it has no %s in it, so it would show up empty."):format(
                    spec.label,
                    name,
                    spec.plural
                )
            )
        else
            categories[#categories + 1] = { name = name, entries = kept }
            Registry.register_dynamic(permission, spec.file)
            Log.debug(
                ("[Permissions] %s '%s' holds %d %s and is granted by '%s'."):format(
                    spec.label:gsub('^%l', string.upper),
                    name,
                    #kept,
                    spec.plural,
                    permission
                )
            )
        end
        ::continue::
    end
    return categories
end

local function load_ped_categories()
    ped_categories = {}
    for _, category in
        ipairs(load_labelled_categories({
            file = PED_FILE,
            container = PED_CATEGORIES,
            label = 'ped category',
            entry_noun = 'ped model names',
            plural = 'peds',
            missing_note = 'The ped models menu starts empty.',
            failed_note = 'the ped models menu starts empty',
        }))
    do
        local peds = {}
        for _, entry in ipairs(category.entries) do
            peds[#peds + 1] = { model = entry[1], label = entry[2] }
        end
        ped_categories[#ped_categories + 1] = { name = category.name, peds = peds }
    end
end

local function load_weapon_categories()
    weapon_categories = {}
    for _, category in
        ipairs(load_labelled_categories({
            file = WEAPON_FILE,
            container = WEAPON_CATEGORIES,
            label = 'weapon category',
            entry_noun = 'weapon spawn names',
            plural = 'weapons',
            missing_note = 'The weapon options menu starts empty.',
            failed_note = 'the weapon options menu starts empty',
            accept = function(spawn_name, category_name)
                if spawn_name == UNARMED then
                    Log.warning(
                        (
                            "[Permissions] Skipping '%s' in weapon category '%s': every "
                            .. 'player already has it, so there would be nothing to hand out.'
                        ):format(UNARMED, category_name)
                    )
                    return false
                end
                if not PermissionPath.is_valid_segment(spawn_name) then
                    Log.warning(
                        (
                            "[Permissions] Skipping '%s' in weapon category '%s': only letters, digits and "
                            .. 'underscores are usable in a permission, so this one could never be whitelisted.'
                        ):format(spawn_name, category_name)
                    )
                    return false
                end
                return true
            end,
        }))
    do
        local weapons = {}
        for _, entry in ipairs(category.entries) do
            weapons[#weapons + 1] = { spawnName = entry[1], label = entry[2] }
        end
        weapon_categories[#weapon_categories + 1] = { name = category.name, weapons = weapons }
    end
end

-- Call once, after the permission registry is built. Order matches
-- ServerPermissions.Initialize.
function Catalogs.load()
    load_whitelist()
    load_vehicle_categories()
    load_ped_categories()
    load_weapon_categories()
end

-- kind is 'vehicle', 'ped' or 'weapon'.
function Catalogs.is_whitelisted(kind, model)
    return whitelists[kind] ~= nil and whitelists[kind].set[model:lower()] == true
end

-- Sorted, for sending to clients so they know which models their class
-- permissions do not cover.
function Catalogs.whitelisted_models(kind)
    return whitelists[kind] and whitelists[kind].ordered or {}
end

-- The category a model was moved into, or nil when it is in its game class.
function Catalogs.vehicle_category_of(model)
    return vehicle_category_by_model[model:lower()]
end

-- Two aligned lists, for sending to clients.
function Catalogs.categorised_vehicles()
    return categorised_vehicles, vehicle_category_names
end

function Catalogs.ped_categories()
    return ped_categories
end

function Catalogs.weapon_categories()
    return weapon_categories
end

return Catalogs
