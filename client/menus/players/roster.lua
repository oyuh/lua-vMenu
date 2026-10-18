-- Port of vMenu.Enhanced.Menus/Players/PlayerRoster.cs: the players this
-- client streams, as { slot, server_id, ped, position }. Rebuilt at most every
-- 200 ms however many features ask.

local Roster = {}

local PLAYER_SLOTS = 256
local MINIMUM_AGE_MS = 200
-- What GetPlayerServerId answers for a slot that has no server id yet.
local NO_SERVER_ID = 65535

local entries = {}
local by_id = {}
local stale_at = 0

function Roster.refresh()
    local now = GetGameTimer()
    if now < stale_at then
        return
    end
    stale_at = now + MINIMUM_AGE_MS
    entries, by_id = {}, {}
    for slot = 0, PLAYER_SLOTS - 1 do
        if NetworkIsPlayerActive(slot) then
            local ped = GetPlayerPed(slot)
            local server_id = GetPlayerServerId(slot)
            if ped ~= 0 and DoesEntityExist(ped) and server_id > 0 and server_id ~= NO_SERVER_ID then
                local entry = { slot = slot, server_id = server_id, ped = ped, position = GetEntityCoords(ped, true) }
                entries[#entries + 1] = entry
                by_id[server_id] = entry
            end
        end
    end
end

function Roster.all()
    return entries
end

function Roster.get(server_id)
    return by_id[server_id]
end

return Roster
