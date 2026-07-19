-- Port of vMenu/PlayerLists.cs. Two modes:
--   * native: players in scope, straight from GetActivePlayers()
--   * infinity: OneSync Infinity servers, where the full list comes from the
--     server (vMenu:RequestPlayerList → vMenu:ReceivePlayerList) and is
--     merged with the local (nearby) players
-- Each entry mirrors IPlayer: handle, server_id, ped, is_local, is_active,
-- name. For remote-only players handle is -1 and ped is nil.

local PlayerLists = {}

local infinity_mode = false
local remote_players = {} -- [server_id] = { server_id = int, name = string }
local updating_player_list = 0

function PlayerLists.set_infinity_mode(enabled)
    infinity_mode = enabled == true
end

function PlayerLists.is_infinity_mode()
    return infinity_mode
end

local function native_player(handle)
    local ped = GetPlayerPed(handle)
    return {
        handle = handle,
        server_id = GetPlayerServerId(handle),
        ped = ped ~= 0 and ped or nil,
        is_local = handle == PlayerId(),
        is_active = NetworkIsPlayerActive(handle),
        name = GetPlayerName(handle),
    }
end

local function infinity_player(server_id, name)
    local handle = GetPlayerFromServerId(server_id)
    local ped = handle >= 0 and GetPlayerPed(handle) or 0
    return {
        handle = handle,
        server_id = server_id,
        ped = ped > 0 and ped or nil,
        is_local = server_id == GetPlayerServerId(PlayerId()),
        is_active = handle ~= -1 and NetworkIsPlayerActive(handle),
        name = name,
    }
end

-- The merged list: local players first, then remote players not in scope.
function PlayerLists.players()
    local list = {}
    local near_server_ids = {}
    for _, handle in ipairs(GetActivePlayers()) do
        local player = native_player(handle)
        list[#list + 1] = player
        near_server_ids[player.server_id] = true
    end
    if infinity_mode then
        for server_id, remote in pairs(remote_players) do
            if not near_server_ids[server_id] then
                list[#list + 1] = infinity_player(server_id, remote.name)
            end
        end
    end
    return list
end

-- RequestPlayerList: no-op for the native list (it always has everyone).
function PlayerLists.request_player_list()
    if infinity_mode then
        updating_player_list = updating_player_list + 1
        TriggerServerEvent('vMenu:RequestPlayerList')
    end
end

-- ReceivedPlayerList: payload is the server's [{ n = name, s = serverId }].
function PlayerLists.received_player_list(players)
    if not infinity_mode then
        return
    end
    remote_players = {}
    for _, pair in ipairs(players or {}) do
        if type(pair) == 'table' and type(pair.n) == 'string' and pair.s ~= nil then
            local server_id = math.tointeger(tonumber(pair.s))
            if server_id then
                remote_players[server_id] = { server_id = server_id, name = pair.n }
            end
        end
    end
    updating_player_list = updating_player_list - 1
end

-- WaitRequested: blocks (yielding) until the requested list has arrived.
function PlayerLists.wait_requested()
    while updating_player_list > 0 do
        Wait(0)
    end
end

return PlayerLists
