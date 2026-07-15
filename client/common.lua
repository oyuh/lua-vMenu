-- Port of vMenu/CommonFunctions.cs — split by topic as menus land in M7+.
-- M5 brings the pieces the client foundation needs: the name sanitizer and
-- the private-message display flow.

local Notification = require('client.notify')
local PlayerLists = require('client.player_lists')
local State = require('client.state')

local Common = {}

-- Client-side GetSafePlayerName: escapes GTA markup instead of stripping it
-- (different from the server-side ban sanitizer!).
function Common.get_safe_player_name(name)
    if name == nil or name == '' then
        return ''
    end
    return (name:gsub('%^', '\\^'):gsub('~', '\\~'):gsub('<', '«'):gsub('>', '»'))
end

-- PrivateMessage(source, message, sent): shows the PM as a notification with
-- the sender's headshot; falls back to plain text when the headshot takes
-- longer than 2 seconds. The "PM From:"/"PM To:" fallback labels are swapped
-- for sent messages upstream — quirk preserved.
function Common.private_message(source, message, sent)
    sent = sent == true
    PlayerLists.request_player_list()
    PlayerLists.wait_requested()

    local name = '**Invalid**'
    for _, player in ipairs(PlayerLists.players()) do
        if tostring(player.server_id) == tostring(source) then
            name = player.name
            break
        end
    end

    local misc = State.menus.misc_settings
    if misc == nil or misc.MiscDisablePrivateMessages then
        return
    end

    local source_handle = GetPlayerFromServerId(math.tointeger(tonumber(source)) or -1)
    if source_handle == -1 then
        return
    end

    local headshot = RegisterPedheadshot(GetPlayerPed(source_handle))
    local timer = GetGameTimer()
    local took_too_long = false
    while not IsPedheadshotReady(headshot) or not IsPedheadshotValid(headshot) do
        Wait(0)
        if GetGameTimer() - timer > 2000 then
            took_too_long = true
            break
        end
    end

    local safe_name = ('<C>%s</C>'):format(Common.get_safe_player_name(name))
    if not took_too_long then
        local txd = GetPedheadshotTxdString(headshot)
        local subtitle = sent and 'Message Sent' or 'Message Received'
        Notification.Notify.custom_image(txd, txd, message, safe_name, subtitle, true, 1)
    else
        if sent then
            Notification.Notify.custom(('PM From: %s. Message: %s'):format(safe_name, message))
        else
            Notification.Notify.custom(('PM To: %s. Message: %s'):format(safe_name, message))
        end
    end
    UnregisterPedheadshot(headshot)
end

return Common
