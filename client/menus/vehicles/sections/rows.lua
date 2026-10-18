-- Port of vMenu.Enhanced.Menus/Vehicles/Sections/SectionRows.cs: what every
-- Vehicle Options section shares. A section's rows depend on the vehicle the
-- player drives, so most rebuild when it opens and when that vehicle changes.

local Localization = require('shared.localization')
local Entries = require('client.framework.entries')
local VehicleEvents = require('client.events.vehicle_events')
local Targeting = require('client.menus.vehicles.targeting')

local Rows = {}

-- The driven vehicle, or nil.
function Rows.driven()
    local vehicle = Targeting.driven()
    return vehicle ~= 0 and vehicle or nil
end

-- The driven vehicle with its mod kit set, which the mod natives need.
function Rows.driven_with_mod_kit()
    local vehicle = Rows.driven()
    if vehicle then
        SetVehicleModKit(vehicle, 0)
    end
    return vehicle
end

-- Swaps a menu's rows, keeping the cursor where it was if it still fits.
function Rows.fill(builder, rows)
    local menu = builder.menu
    local was, offset = menu.CurrentIndex, menu.ViewIndexOffset
    builder:clear_entries()
    builder:add_range(rows)
    local keep = was < #menu:GetMenuItems()
    menu:RefreshIndex(keep and was or 0, keep and offset or 0)
end

-- Calls refresh when the menu opens, and while it is open, whenever the
-- player gets into another vehicle.
function Rows.auto_refresh(builder, refresh)
    local unsubscribe
    builder:on_opened(function()
        refresh()
        if not unsubscribe then
            unsubscribe = VehicleEvents.on('changed', refresh)
        end
    end)
    builder:on_closed(function()
        if unsubscribe then
            unsubscribe()
            unsubscribe = nil
        end
    end)
end

-- auto_refresh that rebuilds the rows from rows().
function Rows.auto_fill(builder, rows)
    Rows.auto_refresh(builder, function()
        Rows.fill(builder, rows())
    end)
end

function Rows.placeholder(text, description)
    return Entries.button({ text = text, description = description })
end

-- The row a section shows when there is no vehicle to work on, saying why.
function Rows.blocked()
    local vehicle, kind = Targeting.current()
    if vehicle and kind == Targeting.PASSENGER then
        return Rows.placeholder(
            Localization.key('vehicleoptions.notdriver.title'),
            Localization.key('vehicleoptions.notdriver')
        )
    end
    return Rows.placeholder(
        Localization.key('vehicleoptions.novehicle'),
        Localization.key('vehicleoptions.novehicle.desc')
    )
end

function Rows.blocked_only()
    return { Rows.blocked() }
end

function Rows.nothing()
    return Rows.placeholder(Localization.key('vehicleoptions.nothing'), Localization.key('vehicleoptions.nothing.desc'))
end

return Rows
