-- NoClip module placeholder. The movement controller (vMenu/Noclip.cs) is a
-- Milestone 9 port; until then the toggle points are wired (key mapping,
-- menu item) but activating noclip tells the player it isn't available yet.

local Notification = require('client.notify')

local NoClip = {}

local active = false

function NoClip.is_noclip_active()
    return active
end

function NoClip.set_noclip_active(value)
    if value then
        Notification.Notify.alert('NoClip has not been ported to this build yet — it lands in a later milestone.')
        return
    end
    active = false
end

return NoClip
