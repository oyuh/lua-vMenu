-- Port of MenuAPI/MenuController.cs — menu registry, submenu binding, and
-- global menu state flags. Input processing and per-frame drawing attach to
-- this in the in-game layer (menu/draw.lua + the controller tick, later in
-- M3); everything here is game-independent.

local Controller = {
    Menus = {},
    MenuButtons = {}, -- [MenuItem] = bound submenu
    MainMenu = nil,

    DontOpenAnyMenu = false,
    DisableMenuButtons = false,
    PreventExitingMenu = false,
    NavigateMenuUsingArrows = true,
    DisableBackButton = false,
    EnableMenuToggleKeyOnController = true,
    SetDrawOrder = true,

    -- 'Left' | 'Right' (vMenu's MiscRightAlignMenu toggles this)
    MenuAlignment = 'Left',
    -- Control id; vMenu sets this to -1 and drives toggling via key mappings.
    MenuToggleKey = -1,
}

-- MenuAPI's MenuAlignment setter refuses right-alignment on ultra-wide
-- aspect ratios (> 17:9). Returns the effective alignment.
function Controller.SetMenuAlignment(alignment)
    if alignment == 'Right' and GetAspectRatio(false) > 1.888888888888889 then
        Controller.MenuAlignment = 'Left'
    else
        Controller.MenuAlignment = alignment
    end
    return Controller.MenuAlignment
end

function Controller.AddMenu(menu)
    for _, existing in ipairs(Controller.Menus) do
        if existing == menu then
            return
        end
    end
    Controller.Menus[#Controller.Menus + 1] = menu
end

function Controller.AddSubmenu(parent, child)
    child.ParentMenu = parent
    Controller.AddMenu(child)
end

-- Binds a menu item so selecting it opens the child menu (closing the
-- current one). The submenu relationship is (re)established at select time
-- too, matching MenuAPI.
function Controller.BindMenuItem(parent_menu, child_menu, item_to_bind)
    Controller.AddSubmenu(parent_menu, child_menu)
    Controller.MenuButtons[item_to_bind] = child_menu
end

function Controller.UnbindMenuItem(item)
    Controller.MenuButtons[item] = nil
end

function Controller.GetCurrentMenu()
    for _, menu in ipairs(Controller.Menus) do
        if menu.Visible then
            return menu
        end
    end
    return nil
end

function Controller.IsAnyMenuOpen()
    return Controller.GetCurrentMenu() ~= nil
end

function Controller.CloseAllMenus()
    for _, menu in ipairs(Controller.Menus) do
        if menu.Visible then
            menu:CloseMenu()
        end
    end
end

-- MenuAPI: menu buttons work only while a menu is open, the game is not
-- paused/faded/switching, the player is alive, and buttons aren't disabled.
-- The game-state natives are checked only when present so navigation logic
-- stays testable off-game.
function Controller.AreMenuButtonsEnabled()
    if not Controller.IsAnyMenuOpen() or Controller.DisableMenuButtons then
        return false
    end
    if IsPauseMenuActive and IsPauseMenuActive() then
        return false
    end
    if IsScreenFadedOut and IsScreenFadedOut() then
        return false
    end
    if IsPlayerSwitchInProgress and IsPlayerSwitchInProgress() then
        return false
    end
    if IsEntityDead and PlayerPedId and IsEntityDead(PlayerPedId()) then
        return false
    end
    return true
end

-- Test hook: wipes all registered menus and flags back to defaults.
function Controller._reset()
    Controller.Menus = {}
    Controller.MenuButtons = {}
    Controller.MainMenu = nil
    Controller.DontOpenAnyMenu = false
    Controller.DisableMenuButtons = false
    Controller.PreventExitingMenu = false
    Controller.NavigateMenuUsingArrows = true
    Controller.DisableBackButton = false
    Controller.MenuAlignment = 'Left'
    Controller.MenuToggleKey = -1
end

return Controller
