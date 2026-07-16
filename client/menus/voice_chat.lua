-- Port of vMenu/menus/VoiceChat.cs: voice chat toggles, proximity, and
-- channels. The FunctionsController tick that applies these (M9) reads the
-- public fields on the instance.

local Config = require('shared.config')
local Permissions = require('shared.permissions')
local Common = require('client.common')
local Notification = require('client.notify')
local UserDefaults = require('client.user_defaults')
local Items = require('menu.items')
local Menu = require('menu.menu')

local Subtitle = Notification.Subtitle

local VoiceChat = {}

-- ConvertToMetric: proximity display helper (quirks preserved: 0 → global).
local function convert_to_metric(input)
    local val = '0m'
    if input < 1.0 then
        val = tostring(input * 100) .. 'cm'
    elseif input >= 1.0 then
        if input < 1000 then
            val = tostring(input) .. 'm'
        else
            val = tostring(input / 1000) .. 'km'
        end
    end
    if input == 0 then
        val = 'global'
    end
    return val
end

-- The 9 selectable proximity ranges (meters; 0 = global).
VoiceChat.proximity_range = { 5.0, 10.0, 15.0, 20.0, 100.0, 300.0, 1000.0, 2000.0, 0.0 }

function VoiceChat.create()
    local self = {}
    self.EnableVoicechat = UserDefaults.get_bool('voiceChatEnabled')
    self.ShowCurrentSpeaker = UserDefaults.get_bool('voiceChatShowSpeaker')
    self.ShowVoiceStatus = UserDefaults.get_bool('voiceChatShowVoiceStatus')
    local override_range = Config.get_float('vmenu_override_voicechat_default_range', 0.0)
    self.currentProximity = override_range ~= 0.0 and override_range or UserDefaults.get_float('voiceChatProximity')

    self.channels = {
        'Channel 1 (Default)',
        'Channel 2',
        'Channel 3',
        'Channel 4',
    }
    if Permissions.is_allowed('VCStaffChannel') then
        self.channels[#self.channels + 1] = 'Staff Channel'
    end
    self.currentChannel = self.channels[1]

    local menu = Menu.new(GetPlayerName(PlayerId()), 'Voice Chat Settings')

    local voice_chat_enabled =
        Items.MenuCheckboxItem.new('Enable Voice Chat', 'Enable or disable voice chat.', self.EnableVoicechat)
    local show_current_speaker =
        Items.MenuCheckboxItem.new('Show Current Speaker', 'Shows who is currently talking.', self.ShowCurrentSpeaker)
    local show_voice_status = Items.MenuCheckboxItem.new(
        'Show Microphone Status',
        'Shows whether your microphone is open or muted.',
        self.ShowVoiceStatus
    )

    local voice_chat_proximity = Items.MenuItem.new(
        ('Voice Chat Proximity (%s)'):format(convert_to_metric(self.currentProximity)),
        'Set the voice chat receiving proximity in meters. Set to 0 for global.'
    )
    local channel_index = 0
    for i, channel in ipairs(self.channels) do
        if channel == self.currentChannel then
            channel_index = i - 1
        end
    end
    local voice_chat_channel =
        Items.MenuListItem.new('Voice Chat Channel', self.channels, channel_index, 'Set the voice chat channel.')

    if Permissions.is_allowed('VCEnable') then
        menu:AddMenuItem(voice_chat_enabled)
        -- Nested: without voice chat enabled these are useless anyway.
        if Permissions.is_allowed('VCShowSpeaker') then
            menu:AddMenuItem(show_current_speaker)
        end
        menu:AddMenuItem(voice_chat_proximity)
        menu:AddMenuItem(voice_chat_channel)
        menu:AddMenuItem(show_voice_status)
    end

    menu.OnCheckboxChange = function(_, item, _index, checked)
        if item == voice_chat_enabled then
            self.EnableVoicechat = checked
        elseif item == show_current_speaker then
            self.ShowCurrentSpeaker = checked
        elseif item == show_voice_status then
            self.ShowVoiceStatus = checked
        end
    end

    menu.OnListIndexChange = function(_, item, _old_index, new_index, _item_index)
        if item == voice_chat_channel then
            self.currentChannel = self.channels[new_index + 1]
            Subtitle.custom(('New voice chat channel set to: ~b~%s~s~.'):format(self.currentChannel))
        end
    end

    menu.OnItemSelect = function(_, item, _index)
        if item == voice_chat_proximity then
            local result = Common.get_user_input(
                ('Enter Proximity In Meters. Current: (%s)'):format(convert_to_metric(self.currentProximity)),
                nil,
                6
            )
            local parsed = tonumber(result)
            if parsed ~= nil then
                self.currentProximity = parsed + 0.0
                Subtitle.custom(
                    ('New voice chat proximity set to: ~b~%s~s~.'):format(convert_to_metric(self.currentProximity))
                )
                voice_chat_proximity.Text = ('Voice Chat Proximity (%s)'):format(
                    convert_to_metric(self.currentProximity)
                )
            end
        end
    end

    self.menu = menu
    return self
end

return VoiceChat
