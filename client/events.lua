-- Client event handlers (EventManager.cs port begins here; grows in M5).
-- Contract: docs/contracts/events.md — names and payloads are fixed.

local Permissions = require('shared.permissions')

local Events = {}

function Events.register()
    RegisterNetEvent('vMenu:SetPermissions', function(payload)
        Permissions.set_from_json(payload)
    end)

    RegisterNetEvent('vMenu:SetSupplementaryPermissions', function(payload)
        Permissions.set_supplementary_from_json(payload)
    end)
end

return Events
