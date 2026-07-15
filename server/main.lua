-- Port of vMenuServer/MainServer.cs (upstream @ 49e53065): startup checks,
-- weather/time sync, the vmenuserver console command, and every server-side
-- vMenu:* event handler. Every client-triggered handler re-checks ACE
-- permissions and treats an unauthorized call as cheating (see
-- docs/contracts/events.md, "Security model").

local Util = require('shared.util')
local Json = require('shared.json_compat')
local Config = require('shared.config')
local Permissions = require('shared.permissions')
local Log = require('server.log')
local DateTime = require('server.datetime')
local Bans = require('server.bans')

local M = {}

local RESOURCE = GetCurrentResourceName()

local function version()
    return GetResourceMetadata(RESOURCE, 'version', 0)
end

-- ---------------------------------------------------------------------------
-- Weather & time state (replicated convars, mirroring the C# properties)
-- ---------------------------------------------------------------------------

local WEATHER_TYPES = {
    'EXTRASUNNY',
    'CLEAR',
    'NEUTRAL',
    'SMOG',
    'FOGGY',
    'CLOUDS',
    'OVERCAST',
    'CLEARING',
    'RAIN',
    'THUNDER',
    'BLIZZARD',
    'SNOW',
    'SNOWLIGHT',
    'XMAS',
    'HALLOWEEN',
}
local WEATHER_TYPE_SET = {}
for _, weather_type in ipairs(WEATHER_TYPES) do
    WEATHER_TYPE_SET[weather_type] = true
end

local CLOUD_TYPES = {
    'Cloudy 01',
    'RAIN',
    'horizonband1',
    'horizonband2',
    'Puffs',
    'Wispy',
    'Horizon',
    'Stormy 01',
    'Clear 01',
    'Snowy 01',
    'Contrails',
    'altostratus',
    'Nimbus',
    'Cirrus',
    'cirrocumulus',
    'stratoscumulus',
    'horizonband3',
    'Stripey',
    'horsey',
    'shower',
}

local function clamp(value, min, max)
    if value < min then
        return min
    elseif value > max then
        return max
    end
    return value
end

local function get_current_hours()
    return clamp(Config.get_int('vmenu_current_hour'), 0, 23)
end

local function set_current_hours(value)
    SetConvarReplicated('vmenu_current_hour', tostring(clamp(value, 0, 23)))
end

local function get_current_minutes()
    return clamp(Config.get_int('vmenu_current_minute'), 0, 59)
end

local function set_current_minutes(value)
    SetConvarReplicated('vmenu_current_minute', tostring(clamp(value, 0, 59)))
end

local function minute_clock_speed()
    local value = Config.get_int('vmenu_ingame_minute_duration')
    if value < 100 then
        value = 2000
    end
    return value
end

local function get_freeze_time()
    return Config.get_bool('vmenu_freeze_time')
end

local function set_freeze_time(value)
    SetConvarReplicated('vmenu_freeze_time', tostring(value))
end

local function get_current_weather()
    local value = Config.get_string('vmenu_current_weather', 'CLEAR') or 'CLEAR'
    if not WEATHER_TYPE_SET[value:upper()] then
        return 'CLEAR'
    end
    return value
end

-- C# quirk preserved: an invalid value first writes CLEAR, then immediately
-- overwrites it with the uppercased invalid value anyway (the getter's
-- validation is what actually saves the day).
local function set_current_weather(value)
    if value == nil then
        SetConvarReplicated('vmenu_current_weather', 'CLEAR')
        return
    end
    if value == '' or not WEATHER_TYPE_SET[value:upper()] then
        SetConvarReplicated('vmenu_current_weather', 'CLEAR')
    end
    SetConvarReplicated('vmenu_current_weather', value:upper())
end

local function get_dynamic_weather_enabled()
    return Config.get_bool('vmenu_enable_dynamic_weather')
end

local function set_dynamic_weather_enabled(value)
    SetConvarReplicated('vmenu_enable_dynamic_weather', tostring(value))
end

local function get_manual_snow_enabled()
    return Config.get_bool('vmenu_enable_snow')
end

local function set_manual_snow_enabled(value)
    SetConvarReplicated('vmenu_enable_snow', tostring(value))
end

local function set_blackout_enabled(value)
    SetConvarReplicated('vmenu_blackout_enabled', tostring(value))
end

local function set_vehicle_blackout_enabled(value)
    SetConvarReplicated('vmenu_vehicle_blackout_enabled', tostring(value))
end

local function dynamic_weather_minutes()
    return math.max(Config.get_int('vmenu_dynamic_weather_timer'), 1)
end

local last_weather_change = 0

-- RefreshWeather: semi-random next weather based on the current one.
-- roll is new Random().Next(20); injectable for tests.
local function refresh_weather(roll)
    roll = roll or math.random(0, 19)
    local weather = get_current_weather()
    if weather == 'RAIN' or weather == 'THUNDER' then
        set_current_weather('CLEARING')
    elseif weather == 'CLEARING' then
        set_current_weather('CLOUDS')
    elseif roll <= 5 then
        set_current_weather(weather == 'EXTRASUNNY' and 'CLEAR' or 'EXTRASUNNY')
    elseif roll <= 8 then
        set_current_weather(weather == 'SMOG' and 'FOGGY' or 'SMOG')
    elseif roll <= 14 then
        set_current_weather(weather == 'CLOUDS' and 'OVERCAST' or 'CLOUDS')
    elseif roll == 15 then
        set_current_weather(weather == 'OVERCAST' and 'THUNDER' or 'OVERCAST')
    elseif roll == 16 then
        set_current_weather(weather == 'CLOUDS' and 'EXTRASUNNY' or 'RAIN')
    else
        set_current_weather(weather == 'FOGGY' and 'SMOG' or 'FOGGY')
    end
end

-- TimeLoop body; returns the delay until the next tick.
local function time_tick()
    if Config.get_bool('vmenu_sync_to_machine_time') then
        local machine_time = os.date('*t')
        set_current_minutes(machine_time.min)
        set_current_hours(machine_time.hour)
        return 60000
    end
    if not get_freeze_time() then
        if get_current_minutes() + 1 > 59 then
            set_current_minutes(0)
            if get_current_hours() + 1 > 23 then
                set_current_hours(0)
            else
                set_current_hours(get_current_hours() + 1)
            end
        else
            set_current_minutes(get_current_minutes() + 1)
        end
    end
    return minute_clock_speed()
end

-- WeatherLoop body, run after the dynamic-weather delay has elapsed.
local function weather_body()
    if Config.get_bool('vmenu_enable_weather_sync') then
        local weather = get_current_weather()
        if weather == 'XMAS' or weather == 'HALLOWEEN' or weather == 'NEUTRAL' then
            -- These weather types shouldn't randomly change.
            set_dynamic_weather_enabled(false)
            return
        end
        if GetGameTimer() - last_weather_change > dynamic_weather_minutes() * 60000 then
            refresh_weather()
            if Log.debug_mode then
                Log.log(('Changing weather, new weather: %s'):format(get_current_weather()))
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- GetPlayerFromServerId: nil unless the id parses, is positive, and is online.
local function get_player_from_server_id(server_id)
    local id = math.tointeger(tonumber(server_id))
    if id == nil or id <= 0 or not DoesPlayerExist(tostring(id)) then
        return nil
    end
    return id
end

local function notify(player_handle, message)
    TriggerClientEvent('vMenu:Notify', player_handle, message)
end

-- KickLog: appends to vmenu.log when vmenu_log_kick_actions is set.
local function kick_log(message)
    if Config.get_bool('vmenu_log_kick_actions') then
        local file = LoadResourceFile(RESOURCE, 'vmenu.log') or ''
        local line = ('[\t%s\t] [KICK ACTION] %s\n'):format(DateTime.log_stamp(), message)
        SaveResourceFile(RESOURCE, 'vmenu.log', file .. line, -1)
        print('^3[vMenu] [KICK]^7 ' .. message .. '\n')
    end
end

local function encode_array(list)
    return #list == 0 and '[]' or Json.encode(list)
end

-- Players that completed the join flow, keyed by handle string.
local joined_players = {}

local function join_quit_notif_players()
    local players = {}
    for handle in pairs(joined_players) do
        if Permissions.is_allowed_server('MSJoinQuitNotifs', handle) and get_player_from_server_id(handle) then
            players[#players + 1] = handle
        end
    end
    return players
end

-- The full join push: main permissions, config-options nudge, teleport
-- locations, then supplementary permissions (PermissionsManager +
-- SupplementaryPermissionManager SetPermissionsForPlayer). The upstream dev
-- backdoor is intentionally not ported (docs/contracts/permissions.md).
local function push_permissions(player_handle)
    TriggerClientEvent(
        'vMenu:SetPermissions',
        player_handle,
        Json.encode(Permissions.collect_for_player(player_handle))
    )
    TriggerClientEvent('vMenu:SetConfigOptions', player_handle)
    TriggerClientEvent('vMenu:UpdateTeleportLocations', player_handle, encode_array(Config.get_teleport_locations()))
    TriggerClientEvent(
        'vMenu:SetSupplementaryPermissions',
        player_handle,
        Json.encode(Permissions.collect_supplementary_for_player(player_handle))
    )
end

-- SetupAddonPerms: one supplementary permission per whitelisted model, plus
-- the template cfg dropped into config/templates/.
local function setup_addon_perms(whitelists)
    whitelists = whitelists or {}
    for _, entry in ipairs(whitelists.whitelistedweapons or {}) do
        Permissions.register_supplementary('WW' .. entry:lower():gsub('weapon_', ''))
    end
    for _, entry in ipairs(whitelists.whitelistedvehicle or {}) do
        Permissions.register_supplementary('VW' .. entry:lower())
    end
    for _, entry in ipairs(whitelists.whitelistedpeds or {}) do
        Permissions.register_supplementary('PW' .. entry:lower())
    end

    local lines = {
        '#################################################################',
        '#                   THIS IS A TEMPLATE FILE.                    #',
        '#          DO NOT EDIT, MAKE A COPY AND EDIT THE COPY.          #',
        '#################################################################',
    }
    for _, permission in ipairs(Permissions.supplementary_list) do
        lines[#lines + 1] = ('add_ace builtin.everyone "%s" allow'):format(
            Permissions.supplementary_ace_name(permission)
        )
    end
    local contents = table.concat(lines, '\n') .. '\n'
    if not SaveResourceFile(RESOURCE, 'config/templates/SupplementaryPermissionTemplate.cfg', contents, -1) then
        Log.log('Could not write config/templates/SupplementaryPermissionTemplate.cfg.', Log.levels.warning)
    end
end

local function squared_distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return dx * dx + dy * dy + dz * dz
end

-- ---------------------------------------------------------------------------
-- vmenuserver console command
-- ---------------------------------------------------------------------------

local function version_fallback()
    print(('vMenu is currently running version: %s. Try ^5vmenuserver help^7 for info.'):format(version()))
end

local function server_command(src, args)
    if args == nil or #args == 0 then
        version_fallback()
        return
    end
    local sub = tostring(args[1]):lower()

    if sub == 'debug' then
        Log.debug_mode = not Log.debug_mode
        local state = Log.debug_mode and 'True' or 'False'
        if src < 1 then
            print(('Debug mode is now set to: %s.'):format(state))
        else
            TriggerClientEvent('chatMessage', src, ('vMenu Debug mode is now set to: %s.'):format(state))
        end
    elseif sub == 'unban' and src < 1 then
        if args[2] ~= nil and tostring(args[2]) ~= '' then
            local uuid = tostring(args[2]):gsub('^%s+', ''):gsub('%s+$', '')
            local record = nil
            for _, ban in ipairs(Bans.get_ban_list()) do
                if tostring(ban.uuid) == uuid then
                    record = ban
                    break
                end
            end
            if record then
                Bans.remove_ban(record)
                print('Player has been successfully unbanned.')
            else
                print(("Could not find a banned player with the provided uuid '%s'."):format(uuid))
            end
        else
            print(
                'You did not specify a player to unban, you must enter the FULL playername. '
                    .. 'Usage: vmenuserver unban "playername"'
            )
        end
    elseif sub == 'weather' then
        if args[2] == nil or tostring(args[2]) == '' then
            print("[vMenu] Invalid command syntax. Use 'vmenuserver weather <weatherType>' instead.")
        else
            local wtype = tostring(args[2]):upper()
            if WEATHER_TYPE_SET[wtype] then
                TriggerEvent(
                    'vMenu:UpdateServerWeather',
                    wtype,
                    get_dynamic_weather_enabled(),
                    get_manual_snow_enabled()
                )
                print(('[vMenu] Weather is now set to: %s'):format(wtype))
            elseif wtype:lower() == 'dynamic' then
                -- C# only accepts exactly `weather dynamic <true|false>`.
                local flag = (#args == 3 and args[3] ~= nil) and tostring(args[3]):lower() or nil
                if flag == 'true' then
                    TriggerEvent('vMenu:UpdateServerWeather', get_current_weather(), true, get_manual_snow_enabled())
                    print('[vMenu] Dynamic weather is now turned on.')
                elseif flag == 'false' then
                    TriggerEvent('vMenu:UpdateServerWeather', get_current_weather(), false, get_manual_snow_enabled())
                    print('[vMenu] Dynamic weather is now turned off.')
                else
                    print('[vMenu] Invalid command usage. Correct syntax: vmenuserver weather dynamic <true|false>')
                end
            else
                print('[vMenu] This weather type is not valid!')
            end
        end
    elseif sub == 'time' then
        if #args == 2 then
            if tostring(args[2]):lower() == 'freeze' then
                TriggerEvent(
                    'vMenu:UpdateServerTime',
                    get_current_hours(),
                    get_current_minutes(),
                    not get_freeze_time()
                )
                print(('Time is now %s.'):format(get_freeze_time() and 'frozen' or 'not frozen'))
            else
                print('Invalid syntax. Use: ^5vmenuserver time <freeze|<hour> <minute>>^7 instead.')
            end
        elseif #args > 2 then
            local hour = math.tointeger(tonumber(args[2]))
            local minute = math.tointeger(tonumber(args[3]))
            if hour == nil or minute == nil then
                print('Invalid syntax. Use: ^5vmenuserver time <freeze|<hour> <minute>>^7 instead.')
            elseif hour < 0 or hour > 23 then
                print('Invalid hour provided. Value must be between 0 and 23.')
            elseif minute < 0 or minute > 59 then
                print('Invalid minute provided. Value must be between 0 and 59.')
            else
                TriggerEvent('vMenu:UpdateServerTime', hour, minute, get_freeze_time())
                print(('Time is now %02d:%02d.'):format(hour, minute))
            end
        else
            print('Invalid syntax. Use: ^5vmenuserver time <freeze|<hour> <minute>>^7 instead.')
        end
    elseif sub == 'ban' and src < 1 then
        if #args > 3 then
            local target = nil
            local find_by_server_id = tostring(args[2]):lower() == 'id'
            local identifier = tostring(args[3]):lower()

            if find_by_server_id then
                for _, handle in ipairs(GetPlayers()) do
                    if tostring(handle) == identifier then
                        target = handle
                        break
                    end
                end
            else
                for _, handle in ipairs(GetPlayers()) do
                    local name = GetPlayerName(tostring(handle))
                    if name ~= nil and name:lower() == identifier then
                        target = handle
                        break
                    end
                end
            end
            if target == nil then
                print('[vMenu] Could not find this player, make sure they are online.')
                return
            end

            local reason = 'Banned by staff for:'
            for i = 4, #args do
                reason = reason .. ' ' .. tostring(args[i])
            end

            -- Console bans use Guid.Empty upstream (new Guid()), so no ban-id
            -- suffix gets appended and repeat console bans collide in KVP.
            local record = Bans.new_record(
                Bans.get_safe_player_name(GetPlayerName(tostring(target))),
                Util.player_identifiers(target),
                DateTime.PERM_BAN_ISO,
                reason,
                'Server Console',
                Bans.GUID_EMPTY
            )
            Bans.add_ban(record)
            Bans.ban_log(
                ('[vMenu] Player %s^7 has been banned by Server Console for [%s].'):format(
                    GetPlayerName(tostring(target)),
                    reason
                )
            )
            TriggerEvent('vMenu:BanSuccessful', Json.encode(record))
            local time_remaining = Bans.get_remaining_time_message(DateTime.seconds_until(record.bannedUntil))
            DropPlayer(
                tostring(target),
                (
                    'You are banned from this server. Ban time remaining: %s. Banned by: %s. '
                    .. 'Ban reason: %s. Additional information: %s.'
                ):format(
                    time_remaining,
                    record.bannedBy,
                    record.banReason,
                    Config.get_string('vmenu_default_ban_message_information') or ''
                )
            )
        else
            print('[vMenu] Not enough arguments, syntax: ^5vmenuserver ban <id|name> <server id|username> <reason>^7.')
        end
    elseif sub == 'help' then
        print('Available commands:')
        print('(server console only): vmenuserver ban <id|name> <server id|username> <reason> (player must be online!)')
        print('(server console only): vmenuserver unban <uuid>')
        print('vmenuserver weather <new weather type | dynamic <true | false>>')
        print('vmenuserver time <freeze|<hour> <minute>>')
        print(
            'vmenuserver migrate (This copies all banned players in the bans.json file to the new ban system '
                .. 'in vMenu v3.3.0, you only need to do this once)'
        )
    elseif sub == 'migrate' and src < 1 then
        local file = LoadResourceFile(RESOURCE, 'bans.json')
        if file == nil or file == '' or file == '[]' then
            -- "&1" typo preserved from upstream.
            print("&1[vMenu] [ERROR]^7 No bans.json file found or it's empty.")
            return
        end
        print(
            '^5[vMenu] [INFO]^7 Importing all ban records from the bans.json file into the new storage system. '
                .. '^3This may take some time...^7'
        )
        local bans = Json.decode(file) or {}
        for _, br in ipairs(bans) do
            local record = Bans.new_record(
                br.playerName,
                br.identifiers,
                br.bannedUntil,
                br.banReason,
                br.bannedBy,
                Bans.new_uuid()
            )
            Bans.add_ban(record)
        end
        print('^2[vMenu] [SUCCESS]^7 All ban records have been imported. You now no longer need the bans.json file.')
    else
        version_fallback()
    end
end

-- ---------------------------------------------------------------------------
-- Event handlers
-- ---------------------------------------------------------------------------

local function register_event_handlers()
    -- Identifier lookup RPC (ip identifiers are never exposed).
    RegisterNetEvent('vMenu:GetPlayerIdentifiers', function(target_player, callback)
        local data = {}
        for _, id in ipairs(Util.player_identifiers(target_player)) do
            if not id:find('ip:', 1, true) then
                data[#data + 1] = id
            end
        end
        callback(encode_array(data))
    end)

    -- Kick passengers out of a personal vehicle.
    RegisterNetEvent('vMenu:GetOutOfCar', function(vehicle_net_id)
        local src = source
        if not Permissions.is_allowed_server('PVKickPassengers', src) then
            Bans.ban_cheater(src)
            return
        end
        local vehicle = NetworkGetEntityFromNetworkId(vehicle_net_id)
        if vehicle == nil or vehicle == 0 then
            return
        end
        for seat = -1, 14 do
            local ped = GetPedInVehicleSeat(vehicle, seat)
            if ped ~= 0 and IsPedAPlayer(ped) then
                local occupant = get_player_from_server_id(NetworkGetEntityOwner(ped))
                if occupant ~= nil and tostring(occupant) ~= tostring(src) then
                    TaskLeaveVehicle(ped, vehicle, 16) -- warp-out flag
                    notify(occupant, 'The owner of the vehicle has kicked you out.')
                end
            end
        end
    end)

    -- Clear the area around the source player, for all clients.
    RegisterNetEvent('vMenu:ClearArea', function()
        local src = source
        local position = GetEntityCoords(GetPlayerPed(tostring(src)))
        TriggerClientEvent('vMenu:ClearArea', -1, position)
    end)

    -- Weather & time sync.
    RegisterNetEvent('vMenu:UpdateServerWeather', function(new_weather, dynamic_weather, enable_snow)
        local src = source
        if not Permissions.is_allowed_server('WOSetWeather', src) then
            Bans.ban_cheater(src)
            return
        end
        -- Snow effects always come on for snowy weather types.
        if
            new_weather == 'XMAS'
            or new_weather == 'SNOWLIGHT'
            or new_weather == 'SNOW'
            or new_weather == 'BLIZZARD'
        then
            enable_snow = true
        end
        set_current_weather(new_weather)
        set_dynamic_weather_enabled(dynamic_weather)
        set_manual_snow_enabled(enable_snow)
        last_weather_change = GetGameTimer()
    end)

    RegisterNetEvent('vMenu:UpdateServerBlackout', function(value)
        local src = source
        if not Permissions.is_allowed_server('WOBlackout', src) then
            Bans.ban_cheater(src)
            return
        end
        set_blackout_enabled(value)
    end)

    RegisterNetEvent('vMenu:UpdateServerVehicleBlackout', function(value)
        local src = source
        if not Permissions.is_allowed_server('WOVehBlackout', src) then
            Bans.ban_cheater(src)
            return
        end
        set_vehicle_blackout_enabled(value)
    end)

    RegisterNetEvent('vMenu:UpdateServerWeatherCloudsType', function(remove_clouds)
        local src = source
        if remove_clouds then
            if not Permissions.is_allowed_server('WORemoveClouds', src) then
                Bans.ban_cheater(src)
                return
            end
            TriggerClientEvent('vMenu:SetClouds', -1, 0.0, 'removed')
        else
            if not Permissions.is_allowed_server('WORandomizeClouds', src) then
                Bans.ban_cheater(src)
                return
            end
            local opacity = math.random() + 0.0
            local cloud_type = CLOUD_TYPES[math.random(#CLOUD_TYPES)]
            TriggerClientEvent('vMenu:SetClouds', -1, opacity, cloud_type)
        end
    end)

    RegisterNetEvent('vMenu:UpdateServerTime', function(new_hours, new_minutes, new_freeze_time)
        local src = source
        if not Permissions.is_allowed_server('TOSetTime', src) then
            Bans.ban_cheater(src)
            return
        end
        if Config.get_bool('vmenu_smooth_time_transitions') then
            set_current_hours(get_current_hours())
            set_current_minutes(get_current_minutes())
            set_freeze_time(true)
            while new_hours ~= get_current_hours() do
                if get_current_minutes() + 1 > 59 then
                    set_current_minutes(0)
                    if get_current_hours() + 1 > 23 then
                        set_current_hours(0)
                    else
                        set_current_hours(get_current_hours() + 1)
                    end
                else
                    -- Upstream steps minutes by 5 here (the wrap check above
                    -- still uses +1); the setter clamp keeps it in range.
                    set_current_minutes(get_current_minutes() + 5)
                end
                Wait(0)
            end
            set_freeze_time(new_freeze_time)
        end
        set_current_hours(new_hours)
        set_current_minutes(new_minutes)
    end)

    RegisterNetEvent('vMenu:FreezeServerTime', function(freeze_time)
        local src = source
        if not Permissions.is_allowed_server('TOFreezeTime', src) then
            Bans.ban_cheater(src)
            return
        end
        set_freeze_time(freeze_time)
    end)

    -- Online Players menu actions.
    RegisterNetEvent('vMenu:KickPlayer', function(target, kick_reason)
        local src = source
        kick_reason = kick_reason or 'You have been kicked from the server.'
        if not Permissions.is_allowed_server('OPKick', src) then
            Bans.ban_cheater(src)
            return
        end
        local target_player = get_player_from_server_id(target)
        if target_player == nil then
            notify(src, 'Failed to kick target, because the target could not be found. Did they already leave?')
            return
        end
        if Permissions.is_allowed_server('DontKickMe', target_player) then
            notify(src, 'Sorry, this player can ~r~not ~w~be kicked.')
            return
        end
        kick_log(
            ('Player: %s has kicked: %s for: %s.'):format(
                GetPlayerName(tostring(src)),
                GetPlayerName(tostring(target_player)),
                kick_reason
            )
        )
        notify(src, ('The target player (<C>%s</C>) has been kicked.'):format(GetPlayerName(tostring(target_player))))
        DropPlayer(tostring(target_player), kick_reason)
    end)

    RegisterNetEvent('vMenu:KillPlayer', function(target)
        local src = source
        if not Permissions.is_allowed_server('OPKill', src) then
            Bans.ban_cheater(src)
            return
        end
        local target_player = get_player_from_server_id(target)
        if target_player == nil then
            return
        end
        TriggerClientEvent('vMenu:KillMe', target_player, GetPlayerName(tostring(src)))
    end)

    RegisterNetEvent('vMenu:SummonPlayer', function(target, number_of_seats)
        local src = source
        if not Permissions.is_allowed_server('OPSummon', src) then
            Bans.ban_cheater(src)
            return
        end
        local target_player = get_player_from_server_id(target)
        if target_player == nil then
            return
        end
        local target_ped = GetPlayerPed(tostring(target_player))
        if target_ped == 0 or not DoesEntityExist(target_ped) then
            return
        end

        local source_ped = GetPlayerPed(tostring(src))
        local source_vehicle = GetVehiclePedIsIn(source_ped, false)

        if source_vehicle == 0 then
            local position = GetEntityCoords(source_ped)
            SetEntityCoords(target_ped, position.x, position.y, position.z, false, false, false, true)
            return
        end

        local seat_found = false
        -- Seat indices start at -1.
        number_of_seats = number_of_seats - 1

        for seat = -1, number_of_seats - 1 do
            if GetPedInVehicleSeat(source_vehicle, seat) == 0 then
                local timeout = GetGameTimer() + 1500
                local prior_position = GetEntityCoords(target_ped)
                local source_position = GetEntityCoords(source_ped)
                local new_position = { x = source_position.x, y = source_position.y, z = source_position.z + 5.0 }

                seat_found = true
                SetEntityCoords(target_ped, new_position.x, new_position.y, new_position.z, false, false, false, true)

                while timeout > GetGameTimer() do
                    local check_position = GetEntityCoords(target_ped)
                    if
                        squared_distance(prior_position, check_position)
                        >= squared_distance(new_position, check_position)
                    then
                        break
                    end
                    Wait(100)
                end

                if timeout < GetGameTimer() then
                    notify(src, 'Failed to teleport player.')
                    break
                end

                SetPedIntoVehicle(target_ped, source_vehicle, seat)
                break
            end
        end

        if not seat_found then
            notify(src, 'No free seats in your vehicle for summoned player.')
        end
    end)

    RegisterNetEvent('vMenu:SendMessageToPlayer', function(target, message)
        local src = source
        if not Permissions.is_allowed_server('OPSendMessage', src) then
            Bans.ban_cheater(src)
            return
        end

        local source_pms_disabled = Player(src).state.vmenu_pms_disabled or false
        if source_pms_disabled then
            notify(
                src,
                "You can't send a private message if you have private messages disabled yourself. "
                    .. 'Enable them in the Misc Settings menu and try again.'
            )
            return
        end

        local target_player = get_player_from_server_id(target)
        if target_player == nil then
            notify(src, 'Failed to send message because the target could not be found. Did they disconnect?')
            return
        end

        local target_pms_disabled = Player(target_player).state.vmenu_pms_disabled or false
        if target_pms_disabled then
            -- Upstream interpolates source.Name here (not the target's name);
            -- quirk preserved.
            notify(
                src,
                (
                    'Sorry, your private message to <C>%s</C>~s~ could not be delivered because they have '
                    .. 'private messages disabled.'
                ):format(GetPlayerName(tostring(src)))
            )
            return
        end

        TriggerClientEvent('vMenu:PrivateMessage', target_player, tostring(src), message)

        for handle in pairs(joined_players) do
            if Permissions.is_allowed_server('OPSeePrivateMessages', handle) and get_player_from_server_id(handle) then
                notify(
                    handle,
                    ('[vMenu Staff Log] <C>%s</C>~s~ sent a PM to <C>%s</C>~s~: %s'):format(
                        GetPlayerName(tostring(src)),
                        GetPlayerName(tostring(target_player)),
                        message
                    )
                )
            end
        end
    end)

    -- Add teleport location.
    RegisterNetEvent('vMenu:SaveTeleportLocation', function(location_json)
        local src = source
        if not Permissions.is_allowed_server('MSTeleportSaveLocation', src) then
            Bans.ban_cheater(src)
            return
        end
        local teleport_location = Json.decode(location_json)
        if teleport_location == nil then
            Log.log('Teleport location could not be deserialized, location was not saved.', Log.levels.error_)
            return
        end
        local locations = Config.get_locations()
        for _, existing in ipairs(locations.teleports) do
            if existing.name == teleport_location.name then
                Log.log('A teleport location with this name already exists, location was not saved.', Log.levels.error_)
                return
            end
        end
        locations.teleports[#locations.teleports + 1] = teleport_location
        if not SaveResourceFile(RESOURCE, 'config/locations.json', Json.encode_indented(locations), -1) then
            Log.log('Could not save locations.json file, reason unknown.', Log.levels.error_)
        end
        TriggerClientEvent('vMenu:UpdateTeleportLocations', -1, encode_array(locations.teleports))
    end)

    -- Infinity bits.
    RegisterNetEvent('vMenu:RequestPlayerList', function()
        local src = source
        local list = {}
        for _, handle in ipairs(GetPlayers()) do
            list[#list + 1] = { n = GetPlayerName(tostring(handle)), s = math.tointeger(tonumber(handle)) }
        end
        TriggerClientEvent('vMenu:ReceivePlayerList', src, list)
    end)

    RegisterNetEvent('vMenu:GetPlayerCoords', function(rpc_id, player_id, _callback)
        local src = source
        local coords = vector3(0.0, 0.0, 0.0)
        if Permissions.is_allowed_server('OPTeleport', src) then
            local target_player = get_player_from_server_id(player_id)
            if target_player ~= nil then
                local target_ped = GetPlayerPed(tostring(target_player))
                if target_ped ~= 0 and DoesEntityExist(target_ped) then
                    coords = GetEntityCoords(target_ped)
                end
            end
        end
        TriggerClientEvent('vMenu:GetPlayerCoords:reply', src, rpc_id, coords)
    end)

    -- Player join/quit.
    AddEventHandler('playerJoining', function()
        local src = source
        joined_players[tostring(src)] = true
        push_permissions(src)
        local name = GetPlayerName(tostring(src))
        for _, notif_player in ipairs(join_quit_notif_players()) do
            TriggerClientEvent('vMenu:PlayerJoinQuit', notif_player, name, nil)
        end
    end)

    AddEventHandler('playerDropped', function(reason)
        local src = source
        if not joined_players[tostring(src)] then
            return
        end
        joined_players[tostring(src)] = nil
        local name = GetPlayerName(tostring(src))
        for _, notif_player in ipairs(join_quit_notif_players()) do
            TriggerClientEvent('vMenu:PlayerJoinQuit', notif_player, name, reason)
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Startup (the MainServer constructor)
-- ---------------------------------------------------------------------------

local function boot()
    if RESOURCE ~= 'vMenu' then
        print(
            (
                '\r\n\r\n^1[vMenu] INSTALLATION ERROR!\r\nThe name of the resource is not valid. '
                .. "Please change the folder name from '^3%s^1' to '^2vMenu^1' (case sensitive) instead!\r\n\r\n\r\n^7"
            ):format(RESOURCE)
        )
        return
    end

    register_event_handlers()
    Bans.register()

    -- Config file sanity checks (invalid JSON gets a console warning, exactly
    -- like the upstream constructor).
    local addons = LoadResourceFile(RESOURCE, 'config/addons.json') or '{}'
    if Json.decode(addons) == nil then
        print('\n\n^1[vMenu] [ERROR] ^7Your addons.json file contains a problem! Error details: invalid JSON\n\n')
    end
    local whitelist = LoadResourceFile(RESOURCE, 'config/model-whitelists.json') or '{}'
    local whitelist_data = Json.decode(whitelist)
    if whitelist_data == nil then
        print(
            '\n\n^1[vMenu] [ERROR] ^7Your model-whitelists.json file contains a problem! '
                .. 'Error details: invalid JSON\n\n'
        )
    end
    local extras = LoadResourceFile(RESOURCE, 'config/extras.json') or '{}'
    if Json.decode(extras) == nil then
        print('\n\n^1[vMenu] [ERROR] ^7Your extras.json file contains a problem! Error details: invalid JSON\n\n')
    end

    setup_addon_perms(whitelist_data)

    if not Config.get_bool('vmenu_use_permissions') then
        print(
            '^3[vMenu] [WARNING] vMenu is set up to ignore permissions!\n'
                .. 'If you did this on purpose then you can ignore this warning.\n'
                .. 'If you did not set this on purpose, then you must have made a mistake while setting up vMenu.\n'
                .. 'Please read the vMenu documentation (^5https://docs.vespura.com/vmenu^3).\n'
                .. 'Most likely you are not executing the permissions.cfg (correctly).^7'
        )
    end

    -- PlayersFirstTick: connected players need their permissions re-pushed
    -- after a resource restart (give client scripts 3s to boot).
    CreateThread(function()
        Wait(3000)
        for _, handle in ipairs(GetPlayers()) do
            joined_players[tostring(handle)] = true
            push_permissions(handle)
        end
    end)

    if Config.get_bool('vmenu_enable_weather_sync') then
        CreateThread(function()
            while true do
                if get_dynamic_weather_enabled() then
                    Wait(dynamic_weather_minutes() * 60000)
                    weather_body()
                else
                    Wait(5000)
                end
            end
        end)
    end

    if Config.get_bool('vmenu_enable_time_sync') then
        CreateThread(function()
            while true do
                Wait(time_tick())
            end
        end)
    end

    GlobalState:set('vmenu_onesync', GetConvar('onesync', 'off') == 'on', true)

    RegisterCommand('vmenuserver', function(src, args, _raw)
        server_command(src, args)
    end, true)

    Util.log(('server started (Lua rewrite %s)'):format(version() or 'dev'))
end

boot()

-- Internals exposed for the busted specs; not part of any public API.
M._refresh_weather = refresh_weather
M._time_tick = time_tick
M._weather_body = weather_body
M._server_command = server_command
M._joined_players = joined_players

return M
