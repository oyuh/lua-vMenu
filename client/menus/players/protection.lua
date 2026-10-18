-- Port of vMenu.Enhanced.Menus/Players/PedProtection.cs: several features want
-- the same few ped flags (god mode and stay in vehicle both stop the player
-- being dragged out), so each holds a claim and the flags are their union.
-- Turning one feature off then never undoes another's protection.

local PlayerEvents = require('client.events.player_events')

local Protection = {}

Protection.NOT_DRAGGED_OUT = 1
Protection.NOT_SHOT_IN_VEHICLE = 2
Protection.NOT_KNOCKED_OFF_BIKE = 4

local KNOCK_OFF_DEFAULT = 0
local KNOCK_OFF_NEVER = 1

local claims = {}
local applied, applied_to = 0, 0
local unsubscribe

local function apply()
    local wanted = 0
    for _, claim in ipairs(claims) do
        wanted = wanted | claim.wanted
    end
    if wanted ~= 0 and not unsubscribe then
        unsubscribe = PlayerEvents.on('ped_changed', apply)
    elseif wanted == 0 and unsubscribe then
        unsubscribe()
        unsubscribe = nil
    end
    local ped = PlayerPedId()
    if ped == 0 or not DoesEntityExist(ped) or (ped == applied_to and wanted == applied) then
        return
    end
    applied_to, applied = ped, wanted
    SetPedCanBeDraggedOut(ped, (wanted & Protection.NOT_DRAGGED_OUT) == 0)
    SetPedCanBeShotInVehicle(ped, (wanted & Protection.NOT_SHOT_IN_VEHICLE) == 0)
    SetPedCanBeKnockedOffVehicle(
        ped,
        (wanted & Protection.NOT_KNOCKED_OFF_BIKE) == 0 and KNOCK_OFF_DEFAULT or KNOCK_OFF_NEVER
    )
end

-- claim:set(on, flags) asks for flags while on is true.
function Protection.claim()
    local claim = { wanted = 0 }
    function claim:set(on, flags)
        local wanted = on and flags or 0
        if wanted ~= self.wanted then
            self.wanted = wanted
            apply()
        end
    end
    claims[#claims + 1] = claim
    return claim
end

-- Writes the flags again, for when something else reset the ped.
function Protection.reapply()
    applied_to = 0
    apply()
end

return Protection
