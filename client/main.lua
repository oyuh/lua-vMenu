-- Port of vMenu.Enhanced.Core/Main.cs: the client entrypoint.

local Log = require('shared.log')
local Platform = require('shared.platform')
local ResourceIdentity = require('shared.data.resource_identity')
local Config = require('shared.config')
local Localization = require('shared.localization')
local Permissions = require('client.permissions')
local UserDefaults = require('client.user_defaults')
local UserPreferences = require('client.user_preferences')
local Skin = require('client.framework.skin')
local Notifications = require('client.framework.notifications')
local Registry = require('client.framework.registry')
local Controller = require('menu.controller')

local RESOURCE = GetCurrentResourceName()

if not ResourceIdentity.is_correctly_named(RESOURCE) then
    for _, line in ipairs(ResourceIdentity.mismatch_report(RESOURCE, 'client')) do
        Log.error(line)
    end
    return
end

Log.info(
    ('[Core] Loaded vMenu Enhanced (Lua) v%s on %s.'):format(
        GetResourceMetadata(RESOURCE, 'version', 0),
        Platform.describe()
    )
)

Permissions.register_events()
Notifications.register_events()
Config.init()
UserDefaults.init()

Controller.MenuToggleKeyDefault = Config.value('vMenu.Enhanced.KeyBindings.MenuToggleKey')
Skin.init()
Localization.load('vMenu.Enhanced.Languages', Config.value('vMenu.Enhanced.Languages'))
Controller.init()

-- The menus the main menu links to, in order (MainMenuComposition.cs). The
-- rest join as they are ported.
local MAIN_MENU = {
    require('client.menus.about'),
}

CreateThread(function()
    while not Permissions.has_received() do
        Wait(0)
    end
    UserPreferences.restore()
    Registry.build(MAIN_MENU)
end)
