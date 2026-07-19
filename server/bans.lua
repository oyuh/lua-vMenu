-- Port of vMenuServer/BanManager.cs (upstream @ 49e53065).
-- Ban records live in server KVP under vmenu_ban_<uuid> with the exact
-- Newtonsoft JSON shape from docs/contracts/kvp-saves.md, so bans created by
-- the C# vMenu keep working here and vice versa.

local Config = require('shared.config')
local Json = require('shared.json_compat')
local Util = require('shared.util')
local Log = require('server.log')
local DateTime = require('server.datetime')

local Bans = {}

local BAN_KVP_PREFIX = 'vmenu_ban_'

-- The console ban path in MainServer passes new Guid() (all zeros); the
-- record constructor skips the ban-id suffix for it.
Bans.GUID_EMPTY = '00000000-0000-0000-0000-000000000000'

-- Guid.NewGuid().ToString(): random version-4 uuid, lowercase, hyphenated.
function Bans.new_uuid()
    return (
        ('xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'):gsub('[xy]', function(c)
            return ('%x'):format(c == 'x' and math.random(0, 15) or math.random(8, 11))
        end)
    )
end

-- GetSettingsString(vmenu_default_ban_message_information): C# interpolates
-- null as an empty string in every ban message.
local function ban_message_information()
    return Config.get_string('vmenu_default_ban_message_information') or ''
end

-- BanRecord constructor: appends "\nYour ban id: <uuid>" to the reason unless
-- it is already there or the uuid is Guid.Empty.
function Bans.new_record(player_name, identifiers, banned_until, ban_reason, banned_by, uuid)
    local reason = ban_reason
    local suffix = '\nYour ban id: ' .. tostring(uuid)
    if uuid ~= Bans.GUID_EMPTY and not reason:find(suffix, 1, true) then
        reason = reason .. suffix
    end
    return {
        playerName = player_name,
        identifiers = identifiers,
        bannedUntil = banned_until,
        banReason = reason,
        bannedBy = banned_by,
        uuid = uuid,
    }
end

-- Cached list, refreshed from KVP only after a change (upstream statics).
local cached_bans = {}
local bans_have_changed = true

function Bans.get_ban_list()
    if not bans_have_changed then
        return cached_bans
    end
    bans_have_changed = false

    local handle = StartFindKvp(BAN_KVP_PREFIX)
    local keys = {}
    while true do
        local key = FindKvp(handle)
        if key == nil or key == '' then
            break
        end
        keys[#keys + 1] = key
    end
    EndFindKvp(handle)

    local records = {}
    for _, key in ipairs(keys) do
        local record = Json.decode(GetResourceKvpString(key))
        if record then
            records[#records + 1] = record
        end
    end
    cached_bans = records
    return records
end

function Bans.add_ban(record)
    local key = BAN_KVP_PREFIX .. tostring(record.uuid)
    local existing = GetResourceKvpString(key)
    if existing == nil or existing == '' then
        SetResourceKvp(key, Json.encode(record))
        bans_have_changed = true
    else
        Log.log('Ban record already exists, this is very odd.', Log.levels.error_)
    end
end

function Bans.remove_ban(record)
    DeleteResourceKvp(BAN_KVP_PREFIX .. tostring(record.uuid))
    bans_have_changed = true
end

-- GetRemainingTimeMessage(TimeSpan): "N days N hours N minutes" with each
-- part omitted when zero, or "Less than 1 minute".
function Bans.get_remaining_time_message(remaining_seconds)
    local days = math.floor(remaining_seconds / 86400)
    local hours = math.floor(remaining_seconds / 3600) % 24
    local minutes = math.floor(remaining_seconds / 60) % 60
    local message = ''
    if days > 0 then
        message = message .. ('%d day%s '):format(days, days > 1 and 's' or '')
    end
    if hours > 0 then
        message = message .. ('%d hour%s '):format(hours, hours > 1 and 's' or '')
    end
    if minutes > 0 then
        message = message .. ('%d minute%s'):format(minutes, minutes > 1 and 's' or '')
    end
    if days < 1 and hours < 1 and minutes < 1 then
        message = 'Less than 1 minute'
    end
    return message
end

-- GetSafePlayerName: strip ^ < > ~ and non-ASCII, trim . , space ! ? from
-- both ends, fall back to "InvalidPlayerName".
function Bans.get_safe_player_name(player_name)
    if player_name == nil or player_name == '' then
        return 'InvalidPlayerName'
    end
    local safe = player_name:gsub('[%^<>~]', '')
    safe = safe:gsub('[\128-\255]+', '')
    safe = safe:gsub('^[.,!? ]+', ''):gsub('[.,!? ]+$', '')
    if safe == '' then
        return 'InvalidPlayerName'
    end
    return safe
end

-- BanLog: appends to vmenu.log when vmenu_log_ban_actions is set.
function Bans.ban_log(message)
    if Config.get_bool('vmenu_log_ban_actions') then
        local file = LoadResourceFile(GetCurrentResourceName(), 'vmenu.log') or ''
        local line = ('[\t%s\t] [BAN ACTION] %s\n'):format(DateTime.log_stamp(), message)
        SaveResourceFile(GetCurrentResourceName(), 'vmenu.log', file .. line, -1)
        print('^2[vMenu] [SUCCESS] [BAN]^7 ' .. message)
    end
end

-- BanCheater: permanently bans a player who triggered a server event without
-- the required permission, when vmenu_auto_ban_cheaters is enabled.
-- ("Aditional" typo preserved from upstream.)
function Bans.ban_cheater(player_handle)
    if not Config.get_bool('vmenu_auto_ban_cheaters') then
        return
    end
    local reason = Config.get_string('vmenu_auto_ban_cheaters_ban_message')
    if reason == nil or reason == '' then
        reason = (
            'You have been automatically banned. If you believe this was done by error, '
            .. 'please contact the server owner for support. Aditional information: %s.'
        ):format(ban_message_information())
    end
    local record = Bans.new_record(
        Bans.get_safe_player_name(GetPlayerName(tostring(player_handle))),
        Util.player_identifiers(player_handle),
        DateTime.PERM_BAN_ISO,
        reason,
        'vMenu Auto Ban',
        Bans.new_uuid()
    )

    Bans.add_ban(record)
    TriggerEvent('vMenu:BanCheaterSuccessful', Json.encode(record))
    Bans.ban_log('A cheater has been banned. ' .. Json.encode(record))
    TriggerClientEvent('vMenu:GoodBye', player_handle) -- much more fun than just kicking them
    Log.log('A cheater has been banned because they attempted to trigger a fake event.', Log.levels.warning)
end

-- BanPlayer: shared by vMenu:TempBanPlayer (hours > 0, capped at 720) and
-- vMenu:PermBanPlayer (hours <= 0 → year 3000). Permission checks are the
-- literal ace names upstream hardcodes here, not the shared helper.
local function ban_player(source_handle, target, ban_duration_hours, ban_reason)
    local src = tostring(source_handle)
    if
        IsPlayerAceAllowed(src, 'vMenu.OnlinePlayers.TempBan')
        or IsPlayerAceAllowed(src, 'vMenu.Everything')
        or IsPlayerAceAllowed(src, 'vMenu.OnlinePlayers.All')
    then
        Log.log('Source player is allowed to ban others.', Log.levels.info)
        local tgt = tostring(target)
        if DoesPlayerExist(tgt) then
            Log.log('Target player is not null so moving on.', Log.levels.info)
            if not IsPlayerAceAllowed(tgt, 'vMenu.DontBanMe') then
                Log.log(
                    "Target player (Player) does not have the 'dont ban me' permission, "
                        .. 'so we can continue to ban them.',
                    Log.levels.info
                )
                local banned_until
                if ban_duration_hours > 0 then
                    banned_until = DateTime.add_hours_iso(DateTime.now(), math.min(ban_duration_hours, 720.0))
                else
                    banned_until = DateTime.PERM_BAN_ISO
                end

                local record = Bans.new_record(
                    Bans.get_safe_player_name(GetPlayerName(tgt)),
                    Util.player_identifiers(target),
                    banned_until,
                    ban_reason,
                    Bans.get_safe_player_name(GetPlayerName(src)),
                    Bans.new_uuid()
                )

                Bans.add_ban(record)
                Log.log('Ban record created.', Log.levels.info)
                Bans.ban_log(
                    ("A new ban record has been added. Player: '%s' was banned by '%s' for '%s' until '%s'."):format(
                        record.playerName,
                        record.bannedBy,
                        record.banReason,
                        record.bannedUntil
                    )
                )
                TriggerEvent('vMenu:BanSuccessful', Json.encode(record))

                local time_remaining = Bans.get_remaining_time_message(DateTime.seconds_until(record.bannedUntil))
                DropPlayer(
                    tgt,
                    (
                        'You are banned from this server. Ban time remaining: %s. Banned by: %s. '
                        .. 'Ban reason: %s. Aditional information: %s.'
                    ):format(
                        time_remaining,
                        record.bannedBy,
                        record.banReason,
                        ban_message_information()
                    )
                )
                TriggerClientEvent('vMenu:Notify', source_handle, '~g~Target player successfully banned.')
            else
                Log.log('Player could not be banned because he is exempt from being banned.', Log.levels.error_)
                TriggerClientEvent(
                    'vMenu:Notify',
                    source_handle,
                    '~r~Could not ban this player, they are exempt from being banned.'
                )
            end
        else
            Log.log('Player is invalid (no longer online) and therefor the banning has failed.', Log.levels.error_)
            TriggerClientEvent(
                'vMenu:Notify',
                source_handle,
                'Could not ban this player because they already left the server.'
            )
        end
    else
        Log.log('If enabled, the source player will be banned now because they are cheating!', Log.levels.warning)
        Bans.ban_cheater(source_handle)
    end
end

-- CheckForBans (playerConnecting): expired bans are cleaned up, then the
-- connecting player's identifiers are matched against active records.
local function check_for_bans(source_handle, _player_name, set_kick_reason)
    local now = DateTime.now()

    for _, record in ipairs(Bans.get_ban_list()) do
        if DateTime.seconds_until(record.bannedUntil, now) <= 0 then
            Bans.remove_ban(record)
        end
    end

    local id_set = {}
    for _, id in ipairs(Util.player_identifiers(source_handle)) do
        id_set[id] = true
    end

    local match = nil
    for _, record in ipairs(Bans.get_ban_list()) do
        if DateTime.seconds_until(record.bannedUntil, now) > 0 then
            for _, id in ipairs(record.identifiers or {}) do
                if id_set[id] then
                    match = record
                    break
                end
            end
        end
        if match then
            break
        end
    end

    if match == nil then
        return
    end

    if DateTime.is_permanent(match.bannedUntil) then
        set_kick_reason(
            (
                'You have been permanently banned from this server. Banned by: %s. Ban reason: %s. '
                .. 'Additional information: %s.'
            ):format(match.bannedBy, match.banReason, ban_message_information())
        )
    else
        set_kick_reason(
            ('You are banned from this server. Ban time remaining: %s. Additional information: %s.'):format(
                Bans.get_remaining_time_message(DateTime.seconds_until(match.bannedUntil, now)),
                ban_message_information()
            )
        )
    end
    CancelEvent()
end

-- RemoveBanRecord (vMenu:RequestPlayerUnban).
local function remove_ban_record(source_handle, uuid)
    local name = source_handle ~= nil and GetPlayerName(tostring(source_handle)) or nil
    if name ~= nil and name ~= '' and name:lower() ~= '**invalid**' and name:lower() ~= '** invalid **' then
        local src = tostring(source_handle)
        if
            IsPlayerAceAllowed(src, 'vMenu.OnlinePlayers.Unban')
            or IsPlayerAceAllowed(src, 'vMenu.OnlinePlayers.All')
            or IsPlayerAceAllowed(src, 'vMenu.Everything')
        then
            for _, record in ipairs(Bans.get_ban_list()) do
                if tostring(record.uuid) == uuid then
                    Bans.remove_ban(record)
                    Bans.ban_log(
                        (
                            'The following ban record has been removed (player unbanned). '
                            .. '[Player: %s was banned by %s for %s until %s.]'
                        ):format(
                            record.playerName,
                            record.bannedBy,
                            record.banReason,
                            record.bannedUntil
                        )
                    )
                    TriggerEvent('vMenu:UnbanSuccessful', Json.encode(record))
                    break
                end
            end
        else
            Bans.ban_cheater(source_handle)
            print(
                (
                    '^3[vMenu] [WARNING] [BAN] ^7Player %s (%s) did not have the required permissions, '
                    .. 'but somehow triggered the unban event. Missing permissions: vMenu.OnlinePlayers.Unban '
                    .. '(is ace allowed: %s)\n'
                ):format(
                    name,
                    tostring(source_handle),
                    tostring(IsPlayerAceAllowed(src, 'vMenu.OnlinePlayers.Unban'))
                )
            )
        end
    else
        print(
            '^3[vMenu] [WARNING] ^7The unban event was triggered, but no valid source was provided. '
                .. 'Nobody has been unbanned.'
        )
    end
end

-- SendBanList (vMenu:RequestBanList).
-- Hardening (deviation from upstream): upstream replies to any client that
-- fires this event, exposing every banned player's full identifier set
-- (including ip), ban reasons, and staff names. Gate it on the same aces the
-- client checks before opening the Banned Players menu, and treat an
-- unauthorized trigger as cheating like the sibling unban handler does.
local function send_ban_list(source_handle)
    local src = tostring(source_handle)
    if
        not IsPlayerAceAllowed(src, 'vMenu.OnlinePlayers.ViewBannedPlayers')
        and not IsPlayerAceAllowed(src, 'vMenu.OnlinePlayers.Unban')
        and not IsPlayerAceAllowed(src, 'vMenu.OnlinePlayers.All')
        and not IsPlayerAceAllowed(src, 'vMenu.Everything')
    then
        Bans.ban_cheater(source_handle)
        return
    end
    Log.log('Updating player with new banlist.\n')
    local records = Bans.get_ban_list()
    local payload = #records == 0 and '[]' or Json.encode(records)
    TriggerClientEvent('vMenu:SetBanList', source_handle, payload)
end

-- Event wiring (the BanManager constructor). Called once from server/main.lua.
function Bans.register()
    RegisterNetEvent('vMenu:TempBanPlayer', function(target, ban_duration_hours, ban_reason)
        ban_player(source, target, ban_duration_hours, ban_reason)
    end)
    RegisterNetEvent('vMenu:PermBanPlayer', function(target, ban_reason)
        ban_player(source, target, -1.0, ban_reason)
    end)
    RegisterNetEvent('vMenu:RequestPlayerUnban', function(uuid)
        remove_ban_record(source, uuid)
    end)
    RegisterNetEvent('vMenu:RequestBanList', function()
        send_ban_list(source)
    end)
    AddEventHandler('playerConnecting', function(player_name, set_kick_reason)
        check_for_bans(source, player_name, set_kick_reason)
    end)
end

return Bans
