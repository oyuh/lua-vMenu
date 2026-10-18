-- Ports of vMenu.Enhanced.MenuFramework/MenuButtonLock.cs and SceneLock.cs.

local Controller = require('menu.controller')

local Locks = {}

-- The key or click that closed a screen is still held when focus returns to
-- the game, and MenuAPI selects on release: without this grace the row that
-- opened the screen opens it again.
local GRACE_MS = 300

local holders = 0
local owned = false
local scene_active = false

-- Stops the menu reacting to buttons, for example while a text box has focus.
function Locks.take_buttons()
    if holders == 0 and not Controller.DisableMenuButtons then
        owned = true
    end
    holders = holders + 1
    Controller.DisableMenuButtons = true
end

function Locks.release_buttons()
    SetTimeout(GRACE_MS, function()
        holders = holders - 1
        if holders > 0 or not owned then
            return
        end
        owned = false
        Controller.DisableMenuButtons = false
    end)
end

-- For a cutscene or camera that owns the screen: closes every menu and keeps
-- them shut until released. The HUD stops drawing meanwhile.
function Locks.take_scene()
    if scene_active then
        return
    end
    scene_active = true
    Controller.CloseAllMenus()
    Locks.take_buttons()
end

function Locks.release_scene()
    if not scene_active then
        return
    end
    scene_active = false
    Locks.release_buttons()
end

function Locks.scene_active()
    return scene_active
end

return Locks
