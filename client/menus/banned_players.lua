-- Port of vMenu/menus/BannedPlayers.cs: the ban list (server-pushed via
-- vMenu:SetBanList), record details, filtering, and unbanning.

local Json = require('shared.json_compat')
local Permissions = require('shared.permissions')
local Common = require('client.common')
local Notification = require('client.notify')
local Controller = require('menu.controller')
local Items = require('menu.items')
local Menu = require('menu.menu')

local Notify = Notification.Notify
local Subtitle = Notification.Subtitle

local BannedPlayers = {}

local JUMP = 22 -- Control.Jump

-- Identifier display colors (enough to cover all identifier types).
local ID_COLORS = { '~r~', '~g~', '~b~', '~o~', '~y~', '~p~', '~s~', '~t~' }

local function banned_until_year(banned_until)
    return tonumber(tostring(banned_until or ''):sub(1, 4)) or 0
end

local function banned_until_date(banned_until)
    -- The date part of the Newtonsoft ISO string (display only).
    return tostring(banned_until or ''):sub(1, 10)
end

function BannedPlayers.create()
    local self = {}
    self.banlist = {}

    local menu = Menu.new(GetPlayerName(PlayerId()), 'Banned Players Management')
    local banned_player = Menu.new('Banned Player', 'Ban Record: ')

    local current_record = nil

    -- update_bans rebuilds the list menu from self.banlist.
    local function update_bans()
        menu:ResetFilter()
        menu:ClearMenuItems()
        for _, ban in ipairs(self.banlist) do
            local record_btn = Items.MenuItem.new(
                ban.playerName,
                ('~y~%s~s~ was banned by ~y~%s~s~ until ~y~%s~s~ for ~y~%s~s~.'):format(
                    tostring(ban.playerName),
                    tostring(ban.bannedBy),
                    tostring(ban.bannedUntil),
                    tostring(ban.banReason)
                )
            )
            record_btn.Label = '→→→'
            record_btn.ItemData = ban
            menu:AddMenuItem(record_btn)
            Controller.BindMenuItem(menu, banned_player, record_btn)
        end
        menu:RefreshIndex()
    end
    self.update_bans = update_bans

    -- vMenu:SetBanList handler target (wired in client/events.lua).
    function self.update_ban_list(ban_json_string)
        self.banlist = Json.decode(ban_json_string) or {}
        update_bans()
    end

    -- Filter with the jump key.
    menu:AddInstructionalButton(JUMP, 'Filter Options')
    menu:AddButtonPressHandler(JUMP, 'JUST_RELEASED', function(_, _control)
        if #self.banlist > 1 then
            local filter_text =
                Common.get_user_input('Filter username or ban id (leave this empty to reset the filter)')
            if filter_text == nil or filter_text == '' then
                Subtitle.custom('Filters have been cleared.')
                menu:ResetFilter()
                update_bans()
            else
                local needle = filter_text:lower()
                menu:FilterMenuItems(function(item)
                    local ban = item.ItemData
                    return type(ban) == 'table'
                        and (
                            tostring(ban.playerName):lower():find(needle, 1, true) ~= nil
                            or tostring(ban.uuid):lower():find(needle, 1, true) ~= nil
                        )
                end)
                Subtitle.custom('Filter has been applied.')
            end
        else
            Notify.error('At least 2 players need to be banned in order to use the filter function.')
        end
    end, true)

    banned_player:AddMenuItem(Items.MenuItem.new('Player Name'))
    banned_player:AddMenuItem(Items.MenuItem.new('Banned By'))
    banned_player:AddMenuItem(Items.MenuItem.new('Banned Until'))
    banned_player:AddMenuItem(Items.MenuItem.new('Player Identifiers'))
    banned_player:AddMenuItem(Items.MenuItem.new('Banned For'))
    banned_player:AddMenuItem(
        Items.MenuItem.new(
            '~r~Unban',
            '~r~Warning, unbanning the player can NOT be undone. You will NOT be able to ban them again until they '
                .. 're-join the server. Are you absolutely sure you want to unban this player? ~s~Tip: Tempbanned '
                .. 'players will automatically get unbanned if they log on to the server after their ban date '
                .. 'has expired.'
        )
    )

    banned_player.OnMenuClose = function(_)
        TriggerServerEvent('vMenu:RequestBanList', PlayerId())
        banned_player:GetMenuItems()[6].Label = ''
        update_bans()
    end

    banned_player.OnIndexChange = function(_, _old_item, _new_item, _old_index, _new_index)
        banned_player:GetMenuItems()[6].Label = ''
    end

    banned_player.OnItemSelect = function(_, item, index)
        if index == 5 and Permissions.is_allowed('OPUnban') then
            if item.Label == 'Are you sure?' then
                local found_index = nil
                for i, record in ipairs(self.banlist) do
                    if record == current_record then
                        found_index = i
                        break
                    end
                end
                if found_index ~= nil then
                    -- Assume the unban worked; re-sync happens on menu close.
                    local record = table.remove(self.banlist, found_index)
                    TriggerServerEvent('vMenu:RequestPlayerUnban', record.uuid)
                    banned_player:GetMenuItems()[6].Label = ''
                    banned_player:GoBack()
                else
                    Notify.error(
                        "Somehow you managed to click the unban button but this ban record you're apparently "
                            .. 'viewing does not even exist. Weird...'
                    )
                end
            else
                item.Label = 'Are you sure?'
            end
        else
            banned_player:GetMenuItems()[6].Label = ''
        end
    end

    menu.OnItemSelect = function(_, item, _index)
        local ban_record = item.ItemData
        if type(ban_record) ~= 'table' then
            return
        end
        current_record = ban_record

        banned_player.MenuSubtitle = 'Ban Record: ~y~' .. tostring(current_record.playerName)
        local menu_items = banned_player:GetMenuItems()
        local name_item = menu_items[1]
        local banned_by_item = menu_items[2]
        local banned_until_item = menu_items[3]
        local identifiers_item = menu_items[4]
        local ban_reason_item = menu_items[5]

        name_item.Label = current_record.playerName
        name_item.Description = 'Player name: ~y~' .. tostring(current_record.playerName)
        banned_by_item.Label = current_record.bannedBy
        banned_by_item.Description = 'Player banned by: ~y~' .. tostring(current_record.bannedBy)
        if banned_until_year(current_record.bannedUntil) == 3000 then
            banned_until_item.Label = 'Forever'
        else
            banned_until_item.Label = banned_until_date(current_record.bannedUntil)
        end
        banned_until_item.Description = 'This player is banned until: ' .. banned_until_date(current_record.bannedUntil)

        identifiers_item.Description = ''
        for i, id in ipairs(current_record.identifiers or {}) do
            local color = ID_COLORS[i] or '~s~'
            -- Only people who can unban (admins) may see IPs.
            if id:sub(1, 3) == 'ip:' and not Permissions.is_allowed('OPUnban') then
                identifiers_item.Description = identifiers_item.Description .. ('%sip: (hidden) '):format(color)
            else
                identifiers_item.Description = identifiers_item.Description
                    .. ('%s%s '):format(color, id:gsub(':', ': ', 1))
            end
        end
        ban_reason_item.Description = 'Banned for: ' .. tostring(current_record.banReason)

        local unban_btn = menu_items[6]
        unban_btn.Label = ''
        if not Permissions.is_allowed('OPUnban') then
            unban_btn.Enabled = false
            unban_btn.Description =
                'You are not allowed to unban players. You are only allowed to view their ban record.'
            unban_btn.LeftIcon = Items.Icon.LOCK
        end

        banned_player:RefreshIndex()
    end
    Controller.AddMenu(banned_player)

    self.menu = menu
    return self
end

return BannedPlayers
