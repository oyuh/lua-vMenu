-- Client entrypoint (MainMenu.cs port begins here; the full menu tree lands
-- in M5+). Boots the menu framework and wires the permission sync handlers.

local Util = require('shared.util')
local Events = require('client.events')
local Process = require('menu.process')

Events.register()
Process.start()

Util.debug_log('client booted')

-- ---------------------------------------------------------------------------
-- M3 verification demo: a menu exercising every item type, for side-by-side
-- comparison against C# vMenu + MenuAPI. Gated behind the same fxmanifest
-- flag upstream uses for its dev commands.
-- ---------------------------------------------------------------------------

local function experimental_features_enabled()
    return GetResourceMetadata(GetCurrentResourceName(), 'experimental_features_enabled', 0) == '1'
end

if experimental_features_enabled() then
    local Controller = require('menu.controller')
    local Menu = require('menu.menu')
    local Items = require('menu.items')

    local demo = nil

    local function build_demo_menu()
        local menu = Menu.new('vMenu', 'Framework demo')
        local submenu = Menu.new('vMenu', 'A submenu')
        submenu:AddMenuItem(Items.MenuItem.new('Nested item', 'Go back with backspace/right stick.'))

        local button = Items.MenuItem.new('Plain button', 'Fires OnItemSelect.')
        local locked = Items.MenuItem.new('Disabled item', 'Should play the error sound.')
        locked.Enabled = false
        locked.LeftIcon = Items.Icon.LOCK
        local checkbox = Items.MenuCheckboxItem.new('Checkbox', 'Toggles on select and on right-press.', true)
        local list = Items.MenuListItem.new('List item', { 'Alpha', 'Beta', 'Gamma' }, 0, 'Wraps both directions.')
        local slider = Items.MenuSliderItem.new('Slider', 0, 10, 5, 'Clamps at min/max.')
        local dynamic = Items.MenuDynamicListItem.new('Dynamic list', '50', function(item, left)
            local value = tonumber(item.CurrentItem) or 0
            return tostring(left and value - 5 or value + 5)
        end, 'Callback-driven values.')
        local opener = Items.MenuItem.new('Open submenu', 'Bound submenu navigation.')
        opener.Label = '→→→'

        for _, item in ipairs({ button, locked, checkbox, list, slider, dynamic }) do
            menu:AddMenuItem(item)
        end
        for i = 1, 12 do
            menu:AddMenuItem(Items.MenuItem.new(('Filler %d'):format(i), 'Scroll overflow test.'))
        end
        menu:AddMenuItem(opener)

        Controller.AddMenu(menu)
        Controller.BindMenuItem(menu, submenu, opener)
        menu.OnItemSelect = function(_, item, index)
            Util.debug_log(('demo select: %s (index %d)'):format(item.Text or '?', index))
        end
        return menu
    end

    RegisterCommand('vmenu_demo', function()
        demo = demo or build_demo_menu()
        if not demo.Visible then
            demo:OpenMenu()
        else
            demo:CloseMenu()
        end
    end, false)
end
