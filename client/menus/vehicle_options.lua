-- Port of vMenu.Enhanced.Menus/VehicleOptionsMenu.cs, with the god mode
-- section (Sections/GodModeSection.cs) and the dirt row (Sections/DirtSection.cs).
-- Each larger section lives in client/menus/vehicles/sections/.

local Localization = require('shared.localization')
local Entries = require('client.framework.entries')
local Registry = require('client.framework.registry')
local GodMode = require('client.menus.vehicles.god_mode')
local Toggles = require('client.menus.vehicles.toggles')
local VehicleActions = require('client.menus.vehicles.actions')
local Rows = require('client.menus.vehicles.sections.rows')

local PERMISSION = 'vMenu.Enhanced.Menus.VehicleOptions.'
local MAX_DIRT = 15

local function build_god_mode(menu)
    for _, part in ipairs(GodMode.PARTS) do
        local preference = part[1]
        local text_key = 'vehicleoptions.god.' .. part[2]
        local description_key = text_key .. '.desc'
        menu:add(Entries.checkbox({
            text = Localization.key(text_key),
            description = Localization.key(description_key),
            read_state = function()
                return GodMode.part(preference)
            end,
            on_changed = function(args)
                GodMode.set_part(preference, args.checked)
            end,
        }))
    end
end

local function dirt_row()
    local options = { Localization.key('vehicleoptions.dirt.clean') }
    for level = 1, MAX_DIRT do
        options[level + 1] = Localization.key('vehicleoptions.dirt.value', { number = tostring(level) })
    end
    return Entries.list({
        text = Localization.key('vehicleoptions.dirt.level'),
        description = Localization.key('vehicleoptions.dirt.level.desc'),
        options = options,
        gate = PERMISSION .. 'Dirt',
        read_selected_index = function()
            local vehicle = Rows.driven()
            return vehicle and math.max(0, math.min(MAX_DIRT, math.floor(GetVehicleDirtLevel(vehicle)))) or 0
        end,
        on_index_changed = function(args)
            local vehicle = Rows.driven()
            if vehicle then
                SetVehicleDirtLevel(vehicle, args.new_index + 0.0)
            end
        end,
    })
end

return Registry.definition({
    audit_name = 'VehicleOptionsMenu',
    title_key = 'vehicleoptions.title',
    subtitle_key = 'vehicleoptions.subtitle',
    description_key = 'vehicleoptions.link.desc',
    permission = PERMISSION .. 'Menu',
    build = function(menu)
        menu:add(Entries.checkbox({
            text = Localization.key('vehicleoptions.god'),
            description = Localization.key('vehicleoptions.god.desc'),
            gate = PERMISSION .. 'God',
            read_state = GodMode.enabled,
            on_changed = function(args)
                GodMode.set_enabled(args.checked)
            end,
        }))
        menu:add(Entries.submenu({
            text = Localization.key('vehicleoptions.god.options'),
            description = Localization.key('vehicleoptions.god.options.desc'),
            menu_title = Localization.key('vehicleoptions.title'),
            menu_subtitle = Localization.key('vehicleoptions.god.subtitle'),
            gate = PERMISSION .. 'God',
            build = build_god_mode,
        }))
        menu:add(Entries.button({
            text = Localization.key('vehicleoptions.repair'),
            description = Localization.key('vehicleoptions.repair.desc'),
            gate = PERMISSION .. 'RepairVehicle',
            on_selected_async = VehicleActions.repair_current,
        }))
        menu:add(Entries.button({
            text = Localization.key('vehicleoptions.wash'),
            description = Localization.key('vehicleoptions.wash.desc'),
            gate = PERMISSION .. 'WashVehicle',
            on_selected = VehicleActions.wash_current,
        }))
        menu:add(Entries.button({
            text = Localization.key('vehicleoptions.cycleseat'),
            description = Localization.key('vehicleoptions.cycleseat.desc'),
            gate = PERMISSION .. 'CycleSeat',
            read_enabled = VehicleActions.can_cycle_seat,
            on_selected = VehicleActions.cycle_seat,
        }))
        menu:add(Entries.checkbox({
            text = Localization.key('vehicleoptions.keepclean'),
            description = Localization.key('vehicleoptions.keepclean.desc'),
            gate = PERMISSION .. 'KeepClean',
            read_state = Toggles.keep_clean,
            on_changed = function(args)
                Toggles.set_keep_clean(args.checked)
            end,
        }))
        menu:add(dirt_row())
        menu:add(Entries.confirm_button({
            text = Localization.key('vehicleoptions.delete'),
            description = Localization.key('vehicleoptions.delete.desc'),
            confirmation_description = Localization.key('vehicleoptions.delete.confirm'),
            gate = PERMISSION .. 'DeleteVehicle',
            on_confirmed_async = VehicleActions.delete_driven,
        }))
        Rows.auto_refresh(menu, Registry.refresh_all)
    end,
})
