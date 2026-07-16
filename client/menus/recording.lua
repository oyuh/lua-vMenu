-- Port of vMenu/menus/Recording.cs: in-game recording, photos, and the
-- Rockstar Editor.

local Config = require('shared.config')
local Common = require('client.common')
local Notification = require('client.notify')
local Items = require('menu.items')
local Menu = require('menu.menu')

local Notify = Notification.Notify

local Recording = {}

function Recording.create()
    local self = {}

    -- Replace the "Upload To Social Club" button in the gallery + warning.
    AddTextEntryByHash(0x86F10CE6, 'Upload To Cfx.re Forum')
    AddTextEntry('ERROR_UPLOAD', 'Are you sure you want to upload this photo to Cfx.re forum?')

    local menu = Menu.new('Recording', 'Recording Options')

    local take_pic = Items.MenuItem.new('Take Photo', 'Takes a photo and saves it to the Pause Menu gallery.')
    local open_pm_gallery = Items.MenuItem.new('Open Gallery', 'Opens the Pause Menu gallery.')
    local start_rec =
        Items.MenuItem.new('Start Recording', "Start a new game recording using GTA V's built in recording.")
    local stop_rec = Items.MenuItem.new('Stop Recording', 'Stop and save your current recording.')
    local open_editor = Items.MenuItem.new(
        'Rockstar Editor',
        'Open the rockstar editor, note you might want to quit the session first before doing this '
            .. 'to prevent some issues.'
    )

    menu:AddMenuItem(take_pic)
    menu:AddMenuItem(open_pm_gallery)
    menu:AddMenuItem(start_rec)
    menu:AddMenuItem(stop_rec)
    menu:AddMenuItem(open_editor)

    menu.OnItemSelect = function(_, item, _index)
        if item == start_rec then
            if IsRecording() then
                Notify.alert(
                    'You are already recording a clip, you need to stop recording first '
                        .. 'before you can start recording again!'
                )
            else
                StartRecording(1)
            end
        elseif item == open_pm_gallery then
            ActivateFrontendMenu(GetHashKey('FE_MENU_VERSION_MP_PAUSE'), true, 3)
        elseif item == take_pic then
            BeginTakeHighQualityPhoto()
            SaveHighQualityPhoto(-1)
            FreeMemoryForHighQualityPhoto()
        elseif item == stop_rec then
            if not IsRecording() then
                Notify.alert(
                    'You are currently NOT recording a clip, you need to start recording first '
                        .. 'before you can stop and save a clip.'
                )
            else
                StopRecordingAndSaveClip()
            end
        elseif item == open_editor then
            if Config.get_bool('vmenu_quit_session_in_rockstar_editor') then
                Common.quit_session()
            end
            ActivateRockstarEditor()
            -- wait for the editor to be closed again
            while IsPauseMenuActive() do
                Wait(0)
            end
            -- then fade in the screen
            DoScreenFadeIn(1)
            Notify.alert(
                'You left your previous session before entering the Rockstar Editor. '
                    .. "Restart the game to be able to rejoin the server's main session.",
                true,
                true
            )
        end
    end

    self.menu = menu
    return self
end

return Recording
