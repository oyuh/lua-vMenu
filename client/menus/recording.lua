-- Port of vMenu.Enhanced.Menus/RecordingMenu.cs: screenshots, clips and the
-- Rockstar Editor. Nothing here needs a permission, like upstream.

local Localization = require('shared.localization')
local Entries = require('client.framework.entries')
local Registry = require('client.framework.registry')
local Notifications = require('client.framework.notifications')
local Natives = require('client.natives')

-- The gallery's upload button and its warning, in the player's language.
local UPLOAD_LABEL_HASH = 0x86F10CE6
local UPLOAD_WARNING_ENTRY = 'ERROR_UPLOAD'
local EDITOR_NOTICE_MS = 2500

local function apply_gallery_text()
    AddTextEntryByHash(UPLOAD_LABEL_HASH, Localization.get('recordingmenu.gallery.upload'))
    AddTextEntry(UPLOAD_WARNING_ENTRY, Localization.get('recordingmenu.gallery.upload.warning'))
end

return Registry.definition({
    audit_name = 'RecordingMenu',
    title_key = 'recordingmenu.title',
    subtitle_key = 'recordingmenu.subtitle',
    description_key = 'recordingmenu.link.desc',
    build = function(menu)
        apply_gallery_text()
        Localization.on_changed(apply_gallery_text)
        menu:add(Entries.button({
            text = Localization.key('recordingmenu.takepic'),
            description = Localization.key('recordingmenu.takepic.desc'),
            on_selected = function()
                BeginTakeHighQualityPhoto()
                SaveHighQualityPhoto(-1)
                FreeMemoryForHighQualityPhoto()
                Notifications.success(Localization.key('recordingmenu.takepic.done'))
            end,
        }))
        menu:add(Entries.button({
            text = Localization.key('recordingmenu.opengallery'),
            description = Localization.key('recordingmenu.opengallery.desc'),
            on_selected = function()
                ActivateFrontendMenu(GetHashKey('FE_MENU_VERSION_MP_PAUSE'), true, 3)
            end,
        }))
        menu:add(Entries.button({
            text = Localization.key('recordingmenu.startstoprecording'),
            description = Localization.key('recordingmenu.startstoprecording.desc'),
            on_selected = function()
                if not IsRecording() then
                    StartRecording(1)
                    Notifications.success(Localization.key('recordingmenu.recording.started'))
                else
                    StopRecordingAndSaveClip()
                    Notifications.success(Localization.key('recordingmenu.recording.saved'))
                end
            end,
        }))
        menu:add(Entries.button({
            text = Localization.key('recordingmenu.cancelrecording'),
            description = Localization.key('recordingmenu.cancelrecording.desc'),
            on_selected = function()
                if not IsRecording() then
                    Notifications.warning(Localization.key('recordingmenu.recording.none'))
                    return
                end
                StopRecordingAndDiscardClip()
                Notifications.info(Localization.key('recordingmenu.recording.cancelled'))
            end,
        }))
        menu:add(Entries.button({
            text = Localization.key('recordingmenu.openrockstareditor'),
            description = Localization.key('recordingmenu.openrockstareditor.desc'),
            on_selected_async = function()
                NetworkStartSoloTutorialSession()
                Natives.activate_rockstar_editor(3)
                while IsPauseMenuActive() do
                    Wait(0)
                end
                DoScreenFadeIn(1)
                NetworkEndTutorialSession()
                Notifications.info(Localization.key('recordingmenu.leftrockstareditor'), EDITOR_NOTICE_MS)
            end,
        }))
    end,
})
