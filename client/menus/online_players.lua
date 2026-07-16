-- Port of vMenu/menus/OnlinePlayers.cs: the player list and all per-player
-- staff actions (PM, teleport, summon, spectate, GPS route, identifiers,
-- kill, kick, temp/perm ban).

local Json = require('shared.json_compat')
local Permissions = require('shared.permissions')
local State = require('client.state')
local Common = require('client.common')
local Notification = require('client.notify')
local PlayerLists = require('client.player_lists')
local Controller = require('menu.controller')
local Items = require('menu.items')
local Menu = require('menu.menu')

local Notify = Notification.Notify

local OnlinePlayers = {}

function OnlinePlayers.create()
    local self = {}
    self.players_waypoint_list = {} -- server ids with an active GPS route
    self.player_coord_waypoints = {} -- [server id] = coord blip handle

    local menu = Menu.new(GetPlayerName(PlayerId()), 'Online Players')
    menu.CounterPreText = 'Players: '

    local player_menu = Menu.new('Online Players', 'Player:')
    Controller.AddSubmenu(menu, player_menu)

    local current_player = nil -- selected PlayerLists entry

    local send_message = Items.MenuItem.new(
        'Send Private Message',
        "Sends a private message to this player. ~r~Note: staff may be able to see all PM's."
    )
    local teleport = Items.MenuItem.new('Teleport To Player', 'Teleport to this player.')
    local teleport_veh = Items.MenuItem.new('Teleport Into Player Vehicle', 'Teleport into the vehicle of the player.')
    local summon = Items.MenuItem.new('Summon Player', 'Teleport the player to you.')
    local toggle_gps =
        Items.MenuItem.new('Toggle GPS', 'Enables or disables the GPS route on your radar to this player.')
    local spectate =
        Items.MenuItem.new('Spectate Player', 'Spectate this player. Click this button again to stop spectating.')
    local print_identifiers = Items.MenuItem.new(
        'Print Identifiers',
        "This will print the player's identifiers to the client console (F8). And also save it to the "
            .. 'CitizenFX.log file.'
    )
    local kill = Items.MenuItem.new(
        '~r~Kill Player',
        'Kill this player, note they will receive a notification saying that you killed them. It will also be '
            .. 'logged in the Staff Actions log.'
    )
    local kick = Items.MenuItem.new('~r~Kick Player', 'Kick the player from the server.')
    local ban = Items.MenuItem.new(
        '~r~Ban Player Permanently',
        'Ban this player permanently from the server. Are you sure you want to do this? You can specify the ban '
            .. 'reason after clicking this button.'
    )
    local tempban = Items.MenuItem.new(
        '~r~Ban Player Temporarily',
        'Give this player a tempban of up to 30 days (max). You can specify duration and ban reason after '
            .. 'clicking this button.'
    )

    if Permissions.is_allowed('OPSendMessage') then
        player_menu:AddMenuItem(send_message)
    end
    if Permissions.is_allowed('OPTeleport') then
        player_menu:AddMenuItem(teleport)
        player_menu:AddMenuItem(teleport_veh)
    end
    if Permissions.is_allowed('OPSummon') then
        player_menu:AddMenuItem(summon)
    end
    if Permissions.is_allowed('OPSpectate') then
        player_menu:AddMenuItem(spectate)
    end
    if Permissions.is_allowed('OPWaypoint') then
        player_menu:AddMenuItem(toggle_gps)
    end
    if Permissions.is_allowed('OPIdentifiers') then
        player_menu:AddMenuItem(print_identifiers)
    end
    if Permissions.is_allowed('OPKill') then
        player_menu:AddMenuItem(kill)
    end
    if Permissions.is_allowed('OPKick') then
        player_menu:AddMenuItem(kick)
    end
    if Permissions.is_allowed('OPTempBan') then
        player_menu:AddMenuItem(tempban)
    end
    if Permissions.is_allowed('OPPermBan') then
        player_menu:AddMenuItem(ban)
        ban.LeftIcon = Items.Icon.WARNING
    end

    player_menu.OnMenuClose = function(_)
        player_menu:RefreshIndex()
        ban.Label = ''
    end

    player_menu.OnIndexChange = function(_, _old_item, _new_item, _old_index, _new_index)
        ban.Label = ''
    end

    player_menu.OnItemSelect = function(_, item, _index)
        if current_player == nil then
            return
        end
        if item == send_message then
            if current_player.is_local then
                Notify.error('You cannot message yourself!')
                return
            end
            local misc = State.menus.misc_settings
            if misc ~= nil and not misc.MiscDisablePrivateMessages then
                local message = Common.get_user_input(('Private Message To %s'):format(current_player.name), nil, 200)
                if message == nil or message == '' then
                    Notify.error(Notification.error_message('InvalidInput'))
                else
                    TriggerServerEvent('vMenu:SendMessageToPlayer', current_player.server_id, message)
                    Common.private_message(tostring(current_player.server_id), message, true)
                end
            else
                Notify.error(
                    "You can't send a private message if you have private messages disabled yourself. "
                        .. 'Enable them in the Misc Settings menu and try again.'
                )
            end
        elseif item == teleport or item == teleport_veh then
            if not current_player.is_local then
                Common.teleport_to_player(current_player, item == teleport_veh)
            else
                Notify.error('You can not teleport to yourself!')
            end
        elseif item == summon then
            if not current_player.is_local then
                Common.summon_player(current_player)
            else
                Notify.error("You can't summon yourself.")
            end
        elseif item == spectate then
            Common.spectate_player(current_player)
        elseif item == kill then
            Common.kill_player(current_player)
        elseif item == toggle_gps then
            -- Clear every active route first; re-selecting the same player
            -- just leaves it off.
            local selected_route_already_active = false
            if #self.players_waypoint_list > 0 then
                for _, server_id in ipairs(self.players_waypoint_list) do
                    if server_id == current_player.server_id then
                        selected_route_already_active = true
                    end
                    local coord_blip = self.player_coord_waypoints[server_id]
                    if coord_blip ~= nil then
                        SetBlipRoute(coord_blip, false)
                        RemoveBlip(coord_blip)
                        self.player_coord_waypoints[server_id] = nil
                    end
                    local player_id = GetPlayerFromServerId(server_id)
                    if player_id >= 0 then
                        local player_ped = GetPlayerPed(player_id)
                        if DoesEntityExist(player_ped) and DoesBlipExist(GetBlipFromEntity(player_ped)) then
                            local old_blip = GetBlipFromEntity(player_ped)
                            SetBlipRoute(old_blip, false)
                            RemoveBlip(old_blip)
                            Notify.custom(
                                ('~g~GPS route to ~s~<C>%s</C>~g~ is now disabled.'):format(
                                    Common.get_safe_player_name(current_player.name)
                                )
                            )
                        end
                    end
                end
                self.players_waypoint_list = {}
            end

            if not selected_route_already_active then
                if current_player.server_id ~= GetPlayerServerId(PlayerId()) then
                    local blip
                    if current_player.is_active and current_player.ped ~= nil then
                        local ped = GetPlayerPed(current_player.handle)
                        blip = GetBlipFromEntity(ped)
                        if not DoesBlipExist(blip) then
                            blip = AddBlipForEntity(ped)
                        end
                    else
                        blip = self.player_coord_waypoints[current_player.server_id]
                        if blip == nil then
                            local request = State.request_player_coordinates
                            local coords = request ~= nil and request(current_player.server_id)
                                or { x = 0.0, y = 0.0, z = 0.0 }
                            blip = AddBlipForCoord(coords.x, coords.y, coords.z)
                            self.player_coord_waypoints[current_player.server_id] = blip
                        end
                    end

                    SetBlipColour(blip, 58)
                    SetBlipRouteColour(blip, 58)
                    SetBlipRoute(blip, true)

                    table.insert(self.players_waypoint_list, current_player.server_id)
                    Notify.custom(
                        (
                            '~g~GPS route to ~s~<C>%s</C>~g~ is now active, press the ~s~Toggle GPS Route~g~ button '
                            .. 'again to disable the route.'
                        ):format(Common.get_safe_player_name(current_player.name))
                    )
                else
                    Notify.error('You can not set a waypoint to yourself.')
                end
            end
        elseif item == print_identifiers then
            TriggerServerEvent('vMenu:GetPlayerIdentifiers', current_player.server_id, function(data)
                print(data)
                local ids = '~s~'
                for _, id in ipairs(Json.decode(data) or {}) do
                    ids = ids .. '~n~' .. id
                end
                Notify.custom(
                    ("~y~<C>%s</C>~g~'s Identifiers: %s"):format(Common.get_safe_player_name(current_player.name), ids),
                    false
                )
                return data
            end)
        elseif item == kick then
            if not current_player.is_local then
                Common.kick_player(current_player, true)
            else
                Notify.error('You cannot kick yourself!')
            end
        elseif item == tempban then
            Common.ban_player(current_player, false)
        elseif item == ban then
            if ban.Label == 'Are you sure?' then
                ban.Label = ''
                self.update_player_list()
                player_menu:GoBack()
                Common.ban_player(current_player, true)
            else
                ban.Label = 'Are you sure?'
            end
        end
    end

    -- Selecting a player in the list opens their action menu.
    menu.OnItemSelect = function(_, item, _index)
        local base_id = tonumber((item.Label or ''):gsub(' →→→', ''):gsub('Server #', ''))
        local found = nil
        for _, player in ipairs(PlayerLists.players()) do
            if player.server_id == base_id then
                found = player
                break
            end
        end
        if found ~= nil then
            current_player = found
            player_menu.MenuSubtitle = ('~s~Player: ~y~%s'):format(Common.get_safe_player_name(current_player.name))
            player_menu.CounterPreText = ('[Server ID: ~y~%d~s~] '):format(current_player.server_id)
        else
            player_menu:GoBack()
        end
    end

    -- UpdatePlayerlist: rebuild before and after the (infinity) request so
    -- both local and remote players appear.
    function self.update_player_list()
        local function update_stuff()
            menu:ClearMenuItems()
            local players = PlayerLists.players()
            table.sort(players, function(a, b)
                return tostring(a.name) < tostring(b.name)
            end)
            for _, p in ipairs(players) do
                local item = Items.MenuItem.new(
                    Common.get_safe_player_name(p.name),
                    ('Click to view the options for this player. Server ID: %d. Local ID: %d.'):format(
                        p.server_id,
                        p.handle
                    )
                )
                item.Label = ('Server #%d →→→'):format(p.server_id)
                menu:AddMenuItem(item)
                Controller.BindMenuItem(menu, player_menu, item)
            end
            menu:RefreshIndex()
            player_menu:RefreshIndex()
        end

        update_stuff()
        PlayerLists.wait_requested()
        update_stuff()
    end

    self.menu = menu
    return self
end

return OnlinePlayers
