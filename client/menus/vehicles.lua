-- Port of vMenu.Enhanced.Menus/VehiclesMenu.cs. Its gate already names every
-- submenu upstream links here; the links themselves join as they are ported.

local Gate = require('client.framework.gate')
local Entries = require('client.framework.entries')
local Registry = require('client.framework.registry')

return Registry.definition({
    audit_name = 'VehiclesMenu',
    title_key = 'vehiclesmenu.title',
    subtitle_key = 'vehiclesmenu.subtitle',
    description_key = 'vehiclesmenu.link.desc',
    gate = Gate.any(
        'vMenu.Enhanced.Menus.VehicleOptions.Menu',
        'vMenu.Enhanced.Menus.PersonalVehicle.Menu',
        'vMenu.Enhanced.Menus.VehicleSpawner.Menu',
        'vMenu.Enhanced.Menus.SavedVehicles.Menu'
    ),
    build = function(menu)
        menu:add(Entries.submenu_for(require('client.menus.vehicle_spawner')))
    end,
})
