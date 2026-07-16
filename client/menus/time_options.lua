-- Port of vMenu/menus/TimeOptions.cs: freeze time + preset and custom times.

local Config = require('shared.config')
local Permissions = require('shared.permissions')
local Common = require('client.common')
local Notification = require('client.notify')
local Items = require('menu.items')
local Menu = require('menu.menu')

local Subtitle = Notification.Subtitle

local TimeOptions = {}

local function clamp(value, min, max)
    if value < min then
        return min
    elseif value > max then
        return max
    end
    return value
end

function TimeOptions.create()
    local self = {}
    local menu = Menu.new(GetPlayerName(PlayerId()), 'Time Options')

    local freeze_time_toggle = Items.MenuItem.new('Freeze/Unfreeze Time', 'Enable or disable time freezing.')
    self.freeze_time_toggle = freeze_time_toggle

    local presets = {
        { 'Early Morning', '06:00' },
        { 'Morning', '09:00' },
        { 'Noon', '12:00' },
        { 'Early Afternoon', '15:00' },
        { 'Afternoon', '18:00' },
        { 'Evening', '21:00' },
        { 'Midnight', '00:00' },
        { 'Night', '03:00' },
    }
    local preset_items = {}
    for i, preset in ipairs(presets) do
        local item = Items.MenuItem.new(preset[1], ('Set the time to %s.'):format(preset[2]))
        item.Label = preset[2]
        preset_items[i] = item
    end

    local hours = {}
    for i = 0, 23 do
        hours[#hours + 1] = ('%02d'):format(i)
    end
    local minutes = {}
    for i = 0, 59 do
        minutes[#minutes + 1] = ('%02d'):format(i)
    end
    local manual_hour = Items.MenuListItem.new('Set Custom Hour', hours, 0)
    local manual_minute = Items.MenuListItem.new('Set Custom Minute', minutes, 0)

    if Permissions.is_allowed('TOFreezeTime') then
        menu:AddMenuItem(freeze_time_toggle)
    end
    if Permissions.is_allowed('TOSetTime') then
        for _, item in ipairs(preset_items) do
            menu:AddMenuItem(item)
        end
        menu:AddMenuItem(manual_hour)
        menu:AddMenuItem(manual_minute)
    end

    menu.OnItemSelect = function(_, item, index)
        if item == freeze_time_toggle then
            Subtitle.info(
                ('Time will now %s~s~.'):format(Common.is_server_time_frozen() and '~y~continue' or '~o~freeze'),
                nil,
                nil,
                'Info:'
            )
            Common.freeze_server_time(not Common.is_server_time_frozen())
        else
            -- Preset time from the item index (upstream's *3+3 wrap math,
            -- shifted by one when the freeze toggle is absent).
            local new_hour
            if Permissions.is_allowed('TOFreezeTime') then
                new_hour = (index * 3) + 3 < 23 and (index * 3) + 3 or (index * 3) + 3 - 24
            else
                new_hour = ((index + 1) * 3) + 3 < 23 and ((index + 1) * 3) + 3 or ((index + 1) * 3) + 3 - 24
            end
            local new_minute = 0
            Subtitle.info(('Time set to ~y~%02d~s~:~y~%02d~s~.'):format(new_hour, new_minute), nil, nil, 'Info:')
            Common.update_server_time(new_hour, new_minute)
        end
    end

    menu.OnListItemSelect = function(_, item, _list_index, _item_index)
        local new_hour = clamp(Config.get_int('vmenu_current_hour'), 0, 23)
        local new_minute = clamp(Config.get_int('vmenu_current_minute'), 0, 59)
        if item == manual_hour then
            new_hour = item.ListIndex
        elseif item == manual_minute then
            new_minute = item.ListIndex
        end
        Subtitle.info(('Time set to ~y~%02d~s~:~y~%02d~s~.'):format(new_hour, new_minute), nil, nil, 'Info:')
        Common.update_server_time(new_hour, new_minute)
    end

    self.menu = menu
    return self
end

return TimeOptions
