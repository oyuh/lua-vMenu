-- Port of vMenu.Enhanced.Menus/VehicleSpawnerMenu.cs and
-- Vehicles/VehicleSpawnShortcuts.cs. Every vehicle model the game knows, grouped
-- by its game class or by the server's custom categories.

local Localization = require('shared.localization')
local Permissions = require('client.permissions')
local Gate = require('client.framework.gate')
local Entries = require('client.framework.entries')
local Registry = require('client.framework.registry')
local Notifications = require('client.framework.notifications')
local Input = require('client.framework.input')
local Spawning = require('client.menus.vehicles.spawning')

local PERMISSION = 'vMenu.Enhanced.Menus.VehicleSpawner.'
local MAX_NAME_INPUT = 30

local categories = {}
local described = {}

local function class_name(vehicle_class)
    return GetLabelText(('VEH_CLASS_%d'):format(vehicle_class))
end

local CLASS_ICONS = {
    [8] = 'motorcycle',
    [10] = 'truck',
    [11] = 'truck',
    [12] = 'van',
    [13] = 'bicycle',
    [14] = 'boat',
    [15] = 'heli',
    [16] = 'plane',
    [20] = 'truck',
    [21] = 'train',
}

-- The icon the input box shows next to a suggestion.
local function vehicle_icon(hash, vehicle_class)
    if IsThisModelATrain(hash) then
        return 'train'
    elseif IsThisModelAPlane(hash) then
        return 'plane'
    elseif IsThisModelAHeli(hash) then
        return 'heli'
    elseif IsThisModelABicycle(hash) then
        return 'bicycle'
    elseif IsThisModelABike(hash) then
        return 'motorcycle'
    elseif IsThisModelAQuadbike(hash) or IsThisModelAnAmphibiousQuadbike(hash) then
        return 'quad'
    elseif IsThisModelASubmersible(hash) then
        return 'submarine'
    elseif IsThisModelABoat(hash) or IsThisModelAnEmergencyBoat(hash) or IsThisModelAJetski(hash) then
        return 'boat'
    end
    return CLASS_ICONS[vehicle_class] or 'car'
end

-- Sorts every model into its category once, before the menu is built.
local function prepare()
    local vehicles = {}
    for _, raw in ipairs(GetAllVehicleModels() or {}) do
        local model = raw:match('^%s*(.-)%s*$')
        if model ~= '' then
            local hash = GetHashKey(model)
            vehicles[#vehicles + 1] = {
                model = model,
                class = GetVehicleClassFromName(hash),
                custom = Permissions.vehicle_category_of(model),
                label = Spawning.display_name(hash),
            }
        end
    end
    table.sort(vehicles, function(left, right)
        if left.label ~= right.label then
            return left.label < right.label
        end
        return left.model < right.model
    end)

    local by_name = {}
    for _, vehicle in ipairs(vehicles) do
        local key = vehicle.custom and ('custom:' .. vehicle.custom:lower()) or ('class:' .. vehicle.class)
        local category = by_name[key]
        if not category then
            if vehicle.custom then
                local name = vehicle.custom
                category = {
                    name = name,
                    title = name,
                    allowed = function()
                        return Permissions.can_spawn_custom_category(name)
                    end,
                    vehicles = {},
                }
            else
                local vehicle_class = vehicle.class
                category = {
                    name = class_name(vehicle_class),
                    title = Localization.from(function()
                        return class_name(vehicle_class)
                    end),
                    allowed = function()
                        return Permissions.can_spawn_vehicle_class(vehicle_class)
                    end,
                    vehicles = {},
                }
            end
            by_name[key] = category
            categories[#categories + 1] = category
        end
        category.vehicles[#category.vehicles + 1] = vehicle
    end
    table.sort(categories, function(left, right)
        return left.name < right.name
    end)
    for _, category in ipairs(categories) do
        for _, vehicle in ipairs(category.vehicles) do
            vehicle.category = category.name
            vehicle.icon = vehicle_icon(GetHashKey(vehicle.model), vehicle.class)
            described[#described + 1] = vehicle
        end
    end
end

-- The two keys every spawner menu offers.
local function attach_shortcuts(menu)
    menu:add_key({
        name = 'spawninside',
        description = Localization.key('vehiclespawner.spawninside.binding'),
        default_key = 'DELETE',
        text = Localization.from(function()
            return Localization.get(
                Spawning.spawn_inside() and 'vehiclespawner.spawninside.button.on'
                    or 'vehiclespawner.spawninside.button.off'
            )
        end),
        handler = function()
            Spawning.set_spawn_inside(not Spawning.spawn_inside())
            Registry.refresh_all()
        end,
    })
    menu:add_key({
        name = 'replaceprevious',
        description = Localization.key('vehiclespawner.replaceprevious.binding'),
        default_key = 'END',
        gate = PERMISSION .. 'AllowKeepPreviousVehicle',
        text = Localization.from(function()
            return Localization.get(
                Spawning.replace_previous() and 'vehiclespawner.replaceprevious.button.on'
                    or 'vehiclespawner.replaceprevious.button.off'
            )
        end),
        handler = function()
            if Spawning.can_keep_previous() then
                Spawning.set_replace_previous(not Spawning.replace_previous())
                Registry.refresh_all()
            end
        end,
    })
end

local function spawn_by_name()
    local suggestions = {}
    for _, vehicle in ipairs(described) do
        if Permissions.can_spawn_vehicle(vehicle.model, vehicle.class) then
            suggestions[#suggestions + 1] = {
                value = vehicle.model,
                label = vehicle.label,
                icon = vehicle.icon,
                detail = vehicle.category,
            }
        end
    end
    local typed = Input.get_text({
        title = Localization.key('vehiclespawner.byname.prompt'),
        max_length = MAX_NAME_INPUT,
        suggestions = suggestions,
    })
    if typed == nil or typed:match('^%s*$') then
        return
    end
    local model = typed:match('^%s*(.-)%s*$')
    local hash = GetHashKey(model)
    if not IsModelValid(hash) or not IsModelAVehicle(hash) then
        Notifications.error(Localization.key('vehiclespawner.byname.invalid', { model = model }))
        return
    end
    local vehicle_class = GetVehicleClassFromName(hash)
    if not Permissions.can_spawn_vehicle(model, vehicle_class) then
        Notifications.warning(Localization.key('vehiclespawner.byname.denied', { model = model }))
        return
    end
    Spawning.spawn_checked(model, vehicle_class)
end

local function build_category(menu, vehicles)
    attach_shortcuts(menu)
    for _, vehicle in ipairs(vehicles) do
        local stats = Spawning.class_stats(GetHashKey(vehicle.model), vehicle.class)
        menu:add(Entries.button({
            text = vehicle.label,
            label = vehicle.model,
            gate = Gate.when(function()
                return Permissions.can_spawn_vehicle(vehicle.model, vehicle.class)
            end),
            vehicle_stats = function()
                return stats
            end,
            on_selected_async = function()
                Spawning.spawn_checked(vehicle.model, vehicle.class)
            end,
        }))
    end
end

return Registry.definition({
    audit_name = 'VehicleSpawnerMenu',
    title_key = 'vehiclespawner.title',
    subtitle_key = 'vehiclespawner.subtitle',
    description_key = 'vehiclespawner.link.desc',
    permission = PERMISSION .. 'Menu',
    prepare = prepare,
    build = function(menu)
        menu:add(Entries.button({
            text = Localization.key('vehiclespawner.byname'),
            description = Localization.key('vehiclespawner.byname.desc'),
            gate = PERMISSION .. 'SpawnByName',
            on_selected_async = spawn_by_name,
        }))
        menu:add(Entries.submenu({
            text = Localization.key('vehiclespawner.bycategory'),
            description = Localization.key('vehiclespawner.bycategory.desc'),
            menu_title = Localization.key('vehiclespawner.title'),
            menu_subtitle = Localization.key('vehiclespawner.bycategory.subtitle'),
            build = function(by_category)
                attach_shortcuts(by_category)
                for _, category in ipairs(categories) do
                    by_category:add(Entries.submenu({
                        text = category.title,
                        description = Localization.key('vehiclespawner.category.desc', { category = category.title }),
                        label = '→',
                        menu_title = category.title,
                        menu_subtitle = Localization.key('vehiclespawner.category.subtitle'),
                        gate = Gate.when(category.allowed),
                        build = function(category_menu)
                            build_category(category_menu, category.vehicles)
                        end,
                    }))
                end
            end,
        }))
        menu:add(Entries.checkbox({
            text = Localization.key('vehiclespawner.spawninside'),
            description = Localization.key('vehiclespawner.spawninside.desc'),
            read_state = Spawning.spawn_inside,
            on_changed = function(args)
                Spawning.set_spawn_inside(args.checked)
            end,
        }))
        menu:add(Entries.checkbox({
            text = Localization.key('vehiclespawner.replaceprevious'),
            description = Localization.key('vehiclespawner.replaceprevious.desc'),
            locked_description = Localization.key('vehiclespawner.replaceprevious.locked'),
            gate = PERMISSION .. 'AllowKeepPreviousVehicle',
            read_state = Spawning.replace_previous,
            on_changed = function(args)
                Spawning.set_replace_previous(args.checked)
            end,
        }))
        attach_shortcuts(menu)
    end,
})
