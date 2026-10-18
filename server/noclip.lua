-- Port of vMenu.Enhanced.Actions.Server/Events/PlayerNoClipState.cs: which
-- players are noclipping. A client says so; the server checks the permission
-- and puts the answer in the player's state bag, where other clients read it
-- (for the noclip smoke, and later for staff).
--
-- Upstream also tracks noclip that staff lent or forced on a player; that comes
-- with the Online Players menu.

local Log = require('shared.log')
local Permissions = require('server.permissions')

local NoClip = {}

local EVENT_REPORT = 'vMenu.Enhanced:PlayerState:ReportNoClip'
local PERMISSION = 'vMenu.Enhanced.NoClip'
local STATE_KEY = 'vMenu:noclip'

local active = {}

function NoClip.is_active(server_id)
    return active[server_id] == true
end

function NoClip.register_events()
    RegisterNetEvent(EVENT_REPORT, function(on)
        local player = source
        on = on == true and Permissions.is_allowed(player, PERMISSION)
        if (active[player] == true) == on then
            return
        end
        active[player] = on or nil
        Player(player).state:set(STATE_KEY, on, true)
        Log.debug(
            ('[NoClip] %s (%d) is %s noclipping.'):format(GetPlayerName(player), player, on and 'now' or 'no longer')
        )
    end)
    AddEventHandler('playerDropped', function()
        active[source] = nil
    end)
end

return NoClip
