-- Specs for the MenuAPI port (menu/*.lua) against MenuAPI v4: the navigation
-- behavior vMenu's menus are built on, and the JSON snapshot that MenuAPI's
-- page (ui/menuapi) reads. The page is upstream's file, so a field name or
-- shape that drifts from the C# writer breaks the menu in game.

local CfxMock = require('tests.mocks.cfx')
local dkjson = require('dkjson')

local MODULES = {
    'shared.log',
    'menu.frame_state',
    'menu.ticks',
    'menu.icons',
    'menu.sprites',
    'menu.nui',
    'menu.class',
    'menu.sounds',
    'menu.items',
    'menu.menu',
    'menu.input',
    'menu.controller',
}

describe('MenuAPI port', function()
    local cfx, Controller, Menu, Items, Nui

    before_each(function()
        cfx = CfxMock.new({ resource_name = 'vMenu.Enhanced' }):install()
        for _, name in ipairs(MODULES) do
            package.loaded[name] = nil
        end
        Controller = require('menu.controller')
        Menu = require('menu.menu')
        Items = require('menu.items')
        Nui = require('menu.nui')
    end)

    after_each(function()
        cfx:uninstall()
    end)

    local function menu_with(count)
        local menu = Menu.new('Title', 'Subtitle')
        for index = 1, count do
            menu:AddMenuItem(Items.MenuItem.new('Item ' .. index, 'Description ' .. index))
        end
        Controller.AddMenu(menu)
        return menu
    end

    local function sounds()
        local played = {}
        for _, call in ipairs(cfx.native_calls.PlaySoundFrontend or {}) do
            played[#played + 1] = call[2]
        end
        return played
    end

    local function messages()
        local sent = {}
        for _, call in ipairs(cfx.native_calls.SendNuiMessage or {}) do
            sent[#sent + 1] = call[1]
        end
        return sent
    end

    describe('navigation', function()
        it('wraps around and keeps the highlighted row on screen', function()
            local menu = menu_with(15)
            menu:OpenMenu()
            for _ = 1, 14 do
                menu:GoDown()
            end
            assert.are.equal(14, menu.CurrentIndex)
            assert.are.equal(5, menu.ViewIndexOffset)

            menu:GoDown()
            assert.are.equal(0, menu.CurrentIndex)
            assert.are.equal(0, menu.ViewIndexOffset)

            menu:GoUp()
            assert.are.equal(14, menu.CurrentIndex)
            assert.are.equal(5, menu.ViewIndexOffset)
        end)

        it('keeps the same row highlighted when rows are added or removed above it', function()
            local menu = menu_with(5)
            menu:OpenMenu()
            menu:RefreshIndex(3)
            local highlighted = menu:GetCurrentMenuItem()

            menu:InsertMenuItem(0, Items.MenuItem.new('New'))
            assert.are.equal(highlighted, menu:GetCurrentMenuItem())

            menu:RemoveMenuItem(menu:GetMenuItems()[1])
            assert.are.equal(highlighted, menu:GetCurrentMenuItem())
        end)

        it('pages with left and right, except on rows that hold a value', function()
            local menu = menu_with(25)
            menu:SetPageSize(10)
            menu:OpenMenu()
            assert.are.equal(10, menu:Size())
            assert.are.equal(3, menu:PageCount())

            menu:GoRight()
            assert.are.equal(1, menu.PageIndex)
            assert.are.equal('Item 11', menu:GetCurrentMenuItem().Text)

            menu:GoLeft()
            menu:GoLeft()
            assert.are.equal(2, menu.PageIndex) -- wrapped to the last page
            assert.are.equal(5, menu:Size())

            local list = Items.MenuListItem.new('List', { 'a', 'b' }, 0)
            menu:InsertMenuItem(20, list)
            menu:RefreshIndex(0)
            menu:GoRight()
            assert.are.equal(2, menu.PageIndex)
            assert.are.equal(1, list.ListIndex)
        end)

        it('opens a bound submenu on select and goes back to its parent', function()
            local main = menu_with(1)
            local child = Menu.new('Child')
            local button = main:GetMenuItems()[1]
            Controller.BindMenuItem(main, child, button)

            main:OpenMenu()
            main:SelectItem(button)
            assert.is_false(main.Visible)
            assert.is_true(child.Visible)
            assert.are.equal(child, Controller.GetCurrentMenu())

            child:GoBack()
            assert.is_true(main.Visible)
            assert.is_false(child.Visible)
        end)

        it('never selects a separator, and does so without the error sound', function()
            local menu = menu_with(0)
            local separator = Items.SeparatorMenuItem.new('Section')
            menu:AddMenuItem(separator)
            local selected = false
            menu.OnItemSelect = function()
                selected = true
            end
            menu:OpenMenu()
            menu:SelectItem(0)
            assert.is_false(selected)
            assert.same({}, sounds())
        end)
    end)

    describe('items', function()
        it('wraps a list both ways and reports old and new index', function()
            local menu = menu_with(0)
            local list = Items.MenuListItem.new('List', { 'a', 'b', 'c' }, 0)
            menu:AddMenuItem(list)
            local changes = {}
            menu.OnListIndexChange = function(_, _, old_index, new_index)
                changes[#changes + 1] = { old_index, new_index }
            end
            list:GoLeft()
            list:GoRight()
            assert.same({ { 0, 2 }, { 2, 0 } }, changes)
        end)

        it('stops a slider at its bounds with the error sound', function()
            local menu = menu_with(0)
            local slider = Items.MenuSliderItem.new('Slider', 0, 2, 2)
            menu:AddMenuItem(slider)
            slider:GoRight()
            assert.are.equal(2, slider.Position)
            assert.same({ 'ERROR' }, sounds())
        end)

        it('toggles a checkbox and reports the new state', function()
            local menu = menu_with(0)
            local checkbox = Items.MenuCheckboxItem.new('Check', nil, false)
            menu:AddMenuItem(checkbox)
            local reported
            menu.OnCheckboxChange = function(_, _, _, checked)
                reported = checked
            end
            menu:OpenMenu()
            menu:SelectItem(checkbox)
            assert.is_true(checkbox.Checked)
            assert.is_true(reported)
        end)
    end)

    describe('NUI snapshot', function()
        it('describes the open menu in the shape the page reads', function()
            local menu = menu_with(12)
            local checkbox = Items.MenuCheckboxItem.new('Check', 'Check description', true)
            local list = Items.MenuListItem.new('List', { 'a', 'b' }, 1)
            local slider = Items.MenuSliderItem.new('Slider', 0, 10, 4)
            menu:InsertMenuItem(0, checkbox)
            menu:InsertMenuItem(1, list)
            menu:InsertMenuItem(2, slider)
            menu:RefreshIndex(0)
            menu:OpenMenu()

            Nui.send_changes(menu)
            local snapshot = dkjson.decode(messages()[1])

            assert.are.equal('menuapi', snapshot.type)
            assert.is_true(snapshot.visible)
            assert.are.equal('left', snapshot.align)
            assert.are.equal('Title', snapshot.header.title)
            assert.are.equal('center', snapshot.header.titleAlign)
            assert.are.equal('interaction_bgd', snapshot.header.texture.name)
            assert.are.equal('1 / 15', snapshot.subtitle.counter)
            assert.are.equal(10, #snapshot.rows)
            assert.is_true(snapshot.overflow)
            assert.are.equal('Check description', snapshot.description)

            local check_row, list_row, slider_row = snapshot.rows[1], snapshot.rows[2], snapshot.rows[3]
            assert.are.equal('checkbox', check_row.kind)
            assert.is_true(check_row.selected)
            assert.are.equal('shop_box_tickb', check_row.checkbox.name)
            assert.are.equal('item', list_row.kind)
            assert.are.equal('~s~← b ~s~→', list_row.label)
            assert.are.equal('slider', slider_row.kind)
            assert.are.equal(4, slider_row.slider.position)
            assert.are.equal('#185d97', slider_row.slider.background)
        end)

        it('sends again only after something drawn changed', function()
            local menu = menu_with(3)
            menu:OpenMenu()
            Nui.send_changes(menu)
            Nui.send_changes(menu)
            assert.are.equal(1, #messages())

            menu:GetMenuItems()[2].Text = 'Renamed'
            Nui.send_changes(menu)
            assert.are.equal(2, #messages())
            assert.matches('Renamed', messages()[2])
        end)
    end)
end)
