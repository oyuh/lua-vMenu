-- Navigation/state specs for the MenuAPI port (menu/*.lua) against the
-- behaviors in MenuAPI/Menu.cs and MenuAPI/items/*.cs.

local Controller = require('menu.controller')
local Menu = require('menu.menu')
local Items = require('menu.items')

describe('menu framework', function()
    before_each(function()
        Controller._reset()
    end)

    local function menu_with_items(count)
        local menu = Menu.new('Title', 'Subtitle')
        for i = 1, count do
            menu:AddMenuItem(Items.MenuItem.new('Item ' .. i))
        end
        Controller.AddMenu(menu)
        return menu
    end

    describe('items', function()
        it('computes 0-based Index from the parent menu', function()
            local menu = menu_with_items(3)
            local items = menu:GetMenuItems()
            assert.equal(0, items[1]:Index())
            assert.equal(2, items[3]:Index())
            assert.equal(-1, Items.MenuItem.new('orphan'):Index())
        end)

        it('reports Selected for the item at CurrentIndex', function()
            local menu = menu_with_items(3)
            assert.is_true(menu:GetMenuItems()[1]:Selected())
            assert.is_false(menu:GetMenuItems()[2]:Selected())
        end)
    end)

    describe('GoDown / GoUp', function()
        it('does nothing when closed or fewer than 2 items', function()
            local menu = menu_with_items(5)
            menu:GoDown()
            assert.equal(0, menu.CurrentIndex)
            local tiny = menu_with_items(1)
            tiny:OpenMenu()
            tiny:GoDown()
            assert.equal(0, tiny.CurrentIndex)
        end)

        it('moves and wraps around, firing OnIndexChange', function()
            local menu = menu_with_items(3)
            menu:OpenMenu()
            local events = {}
            menu.OnIndexChange = function(_, old_item, new_item, old_index, new_index)
                events[#events + 1] = { old_item = old_item, new_item = new_item, old = old_index, new = new_index }
            end

            menu:GoDown()
            assert.equal(1, menu.CurrentIndex)
            assert.equal(0, events[1].old)
            assert.equal(1, events[1].new)

            menu:GoDown()
            menu:GoDown() -- wraps
            assert.equal(0, menu.CurrentIndex)

            menu:GoUp() -- wraps to end
            assert.equal(2, menu.CurrentIndex)
            assert.equal(4, #events)
        end)

        it('scrolls the view window like MenuAPI', function()
            local menu = menu_with_items(15)
            menu:OpenMenu()
            -- walk to the end: view offset should follow once past 10 items
            for _ = 1, 14 do
                menu:GoDown()
            end
            assert.equal(14, menu.CurrentIndex)
            assert.equal(5, menu.ViewIndexOffset)
            -- wrap to top resets the offset
            menu:GoDown()
            assert.equal(0, menu.CurrentIndex)
            assert.equal(0, menu.ViewIndexOffset)
            -- wrap upward jumps the window to the bottom
            menu:GoUp()
            assert.equal(14, menu.CurrentIndex)
            assert.equal(5, menu.ViewIndexOffset)
        end)
    end)

    describe('SelectItem', function()
        it('fires OnItemSelect for enabled items only', function()
            local menu = menu_with_items(2)
            menu:OpenMenu()
            local selected = nil
            menu.OnItemSelect = function(_, item, index)
                selected = { item = item, index = index }
            end

            menu:GetMenuItems()[2].Enabled = false
            menu:SelectItem(1)
            assert.is_nil(selected)

            menu:SelectItem(0)
            assert.equal(menu:GetMenuItems()[1], selected.item)
            assert.equal(0, selected.index)
        end)

        it('toggles checkboxes on right-press too (MenuAPI quirk)', function()
            local menu = Menu.new('t', 's')
            local checkbox = Items.MenuCheckboxItem.new('Seatbelt', nil, false)
            menu:AddMenuItem(checkbox)
            Controller.AddMenu(menu)
            menu:OpenMenu()

            menu:GoRight()
            assert.is_true(checkbox.Checked)
        end)

        it('toggles checkboxes and fires OnCheckboxChange instead', function()
            local menu = Menu.new('t', 's')
            local checkbox = Items.MenuCheckboxItem.new('God Mode', nil, false)
            menu:AddMenuItem(checkbox)
            Controller.AddMenu(menu)
            menu:OpenMenu()

            local fired = nil
            menu.OnCheckboxChange = function(_, item, index, checked)
                fired = { item = item, index = index, checked = checked }
            end
            local item_selected = false
            menu.OnItemSelect = function()
                item_selected = true
            end

            menu:SelectItem(checkbox)
            assert.is_true(checkbox.Checked)
            assert.is_true(fired.checked)
            assert.equal(0, fired.index)
            assert.is_false(item_selected)

            menu:SelectItem(checkbox)
            assert.is_false(checkbox.Checked)
        end)

        it('opens bound submenus and closes the current menu', function()
            local parent = menu_with_items(2)
            local child = Menu.new('t', 'child')
            local opener = parent:GetMenuItems()[1]
            Controller.BindMenuItem(parent, child, opener)
            parent:OpenMenu()

            parent:SelectItem(opener)
            assert.is_false(parent.Visible)
            assert.is_true(child.Visible)
            assert.equal(parent, child.ParentMenu)
            assert.equal(child, Controller.GetCurrentMenu())
        end)

        it('GoBack returns to the parent menu', function()
            local parent = menu_with_items(2)
            local child = Menu.new('t', 'child')
            local opener = parent:GetMenuItems()[1]
            Controller.BindMenuItem(parent, child, opener)
            parent:OpenMenu()
            parent:SelectItem(opener)

            child:GoBack()
            assert.is_false(child.Visible)
            assert.is_true(parent.Visible)
        end)
    end)

    describe('list, slider, and dynamic items', function()
        it('list items wrap both directions and fire index-change events', function()
            local menu = Menu.new('t', 's')
            local list = Items.MenuListItem.new('Hats', { 'None', 'Cap', 'Helmet' }, 0)
            menu:AddMenuItem(list)
            Controller.AddMenu(menu)
            menu:OpenMenu()

            local changes = {}
            menu.OnListIndexChange = function(_, _, old_index, new_index)
                changes[#changes + 1] = { old = old_index, new = new_index }
            end

            menu:GoRight()
            assert.equal(1, list.ListIndex)
            assert.equal('Cap', list:GetCurrentSelection())

            menu:GoRight()
            menu:GoRight() -- wraps to 0
            assert.equal(0, list.ListIndex)

            menu:GoLeft() -- wraps back to end
            assert.equal(2, list.ListIndex)
            assert.same({ old = 0, new = 2 }, changes[4])
        end)

        it('list select fires OnListItemSelect with the list index', function()
            local menu = Menu.new('t', 's')
            local list = Items.MenuListItem.new('Hats', { 'None', 'Cap' }, 1)
            menu:AddMenuItem(list)
            Controller.AddMenu(menu)
            menu:OpenMenu()

            local fired = nil
            menu.OnListItemSelect = function(_, item, selected_index, item_index)
                fired = { item = item, selected = selected_index, index = item_index }
            end
            menu:SelectItem(list)
            assert.equal(1, fired.selected)
            assert.equal(0, fired.index)
        end)

        it('sliders clamp at min/max without wrapping', function()
            local menu = Menu.new('t', 's')
            local slider = Items.MenuSliderItem.new('Density', 0, 2, 1)
            menu:AddMenuItem(slider)
            Controller.AddMenu(menu)
            menu:OpenMenu()

            local positions = {}
            menu.OnSliderPositionChange = function(_, _, old_position, new_position)
                positions[#positions + 1] = { old = old_position, new = new_position }
            end

            menu:GoRight()
            assert.equal(2, slider.Position)
            menu:GoRight() -- at max: no event
            assert.equal(2, slider.Position)
            assert.equal(1, #positions)

            menu:GoLeft()
            menu:GoLeft()
            assert.equal(0, slider.Position)
            menu:GoLeft() -- at min: no event
            assert.equal(0, slider.Position)
            assert.equal(3, #positions)
        end)

        it('dynamic list items delegate to their callback', function()
            local menu = Menu.new('t', 's')
            local dynamic = Items.MenuDynamicListItem.new('Value', '5', function(item, left)
                local value = tonumber(item.CurrentItem)
                return tostring(left and (value - 1) or (value + 1))
            end)
            menu:AddMenuItem(dynamic)
            Controller.AddMenu(menu)
            menu:OpenMenu()

            local changed = nil
            menu.OnDynamicListItemCurrentItemChange = function(_, _, old_value, new_value)
                changed = { old = old_value, new = new_value }
            end

            menu:GoRight()
            assert.equal('6', dynamic.CurrentItem)
            assert.same({ old = '5', new = '6' }, changed)
            menu:GoLeft()
            assert.equal('5', dynamic.CurrentItem)
        end)
    end)

    describe('GoLeft back-navigation (arrow navigation)', function()
        it('returns to the parent when the menu has no items', function()
            local parent = menu_with_items(1)
            local child = Menu.new('t', 'child')
            Controller.AddSubmenu(parent, child)
            child:OpenMenu()

            child:GoLeft()
            assert.is_false(child.Visible)
            assert.is_true(parent.Visible)
        end)

        it('respects PreventExitingMenu for root menus', function()
            local root = Menu.new('t', 'root')
            Controller.AddMenu(root)
            root:OpenMenu()
            Controller.PreventExitingMenu = true

            root:GoLeft()
            assert.is_true(root.Visible)
        end)
    end)

    describe('filtering', function()
        it('filters the active item list and resets indices', function()
            local menu = menu_with_items(5)
            menu:OpenMenu()
            menu:GoDown()
            menu:GoDown()

            menu:FilterMenuItems(function(item)
                return item.Text ~= 'Item 2'
            end)
            assert.equal(4, menu:Size())
            assert.equal(0, menu.CurrentIndex)
            assert.equal('Item 1', menu:GetCurrentMenuItem().Text)

            menu:ResetFilter()
            assert.equal(5, menu:Size())
        end)

        it('keeps Index consistent with the filtered view', function()
            local menu = menu_with_items(5)
            menu:FilterMenuItems(function(item)
                return item.Text == 'Item 4'
            end)
            local visible = menu:GetMenuItems()
            assert.equal(1, #visible)
            assert.equal(0, visible[1]:Index())
        end)
    end)

    describe('controller state', function()
        it('tracks open menus', function()
            local menu = menu_with_items(2)
            assert.is_false(Controller.IsAnyMenuOpen())
            menu:OpenMenu()
            assert.is_true(Controller.IsAnyMenuOpen())
            Controller.CloseAllMenus()
            assert.is_false(Controller.IsAnyMenuOpen())
        end)

        it('disables menu buttons globally', function()
            local menu = menu_with_items(2)
            local list = Items.MenuListItem.new('Hats', { 'a', 'b' }, 0)
            menu:AddMenuItem(list)
            menu:OpenMenu()
            menu:SetCurrentIndex(2)

            Controller.DisableMenuButtons = true
            menu:GoRight()
            assert.equal(0, list.ListIndex)

            Controller.DisableMenuButtons = false
            menu:GoRight()
            assert.equal(1, list.ListIndex)
        end)
    end)

    describe('item removal', function()
        it('adjusts the current index like MenuAPI', function()
            local menu = menu_with_items(4)
            menu:OpenMenu()
            menu:SetCurrentIndex(2)

            menu:RemoveMenuItem(1)
            assert.equal(3, menu:Size())
            assert.equal(1, menu.CurrentIndex)
        end)

        it('removes by item object', function()
            local menu = menu_with_items(3)
            local second = menu:GetMenuItems()[2]
            menu:RemoveMenuItem(second)
            assert.equal(2, menu:Size())
            assert.equal(-1, second:Index() >= 0 and second:Index() or -1)
        end)
    end)
end)
