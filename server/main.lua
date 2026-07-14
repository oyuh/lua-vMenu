-- Server entrypoint (MainServer.cs port begins here; sync loops, admin
-- actions, and bans land in M4). For now: the permission push flow, which is
-- the part clients need to boot (contract: docs/contracts/events.md).

local Util = require('shared.util')
local Json = require('shared.json_compat')
local Permissions = require('shared.permissions')

local function push_permissions(player_handle)
    TriggerClientEvent(
        'vMenu:SetPermissions',
        player_handle,
        Json.encode(Permissions.collect_for_player(player_handle))
    )
    TriggerClientEvent(
        'vMenu:SetSupplementaryPermissions',
        player_handle,
        Json.encode(Permissions.collect_supplementary_for_player(player_handle))
    )
    -- vMenu:SetConfigOptions / vMenu:UpdateTeleportLocations follow in M4
    -- together with the rest of OnPlayerJoining.
end

AddEventHandler('playerJoining', function()
    push_permissions(source)
end)

-- Resource restart: connected players need their permissions re-pushed
-- (MainServer.PlayersFirstTick waits 3s for client scripts to restart).
CreateThread(function()
    Wait(3000)
    for _, player_handle in ipairs(GetPlayers()) do
        push_permissions(player_handle)
    end
end)

Util.log('server started (Lua rewrite — milestone 3)')
