-- Port of MenuAPI/items/*.cs. Indices (Index, ListIndex) are 0-based like the
-- C#. Icons are named by their C# enum name ('LOCK', 'STAR', ...), see
-- menu/icons.lua. Colors are { r, g, b }.

local Class = require('menu.class')
local Sounds = require('menu.sounds')

local Items = {}

local function navigates_back(item)
    -- Required lazily: the controller requires the menu, which requires this.
    local Controller = require('menu.controller')
    return Controller.NavigateMenuUsingArrows
        and not Controller.DisableBackButton
        and not (Controller.PreventExitingMenu and item.ParentMenu and item.ParentMenu.ParentMenu == nil)
end

-- MenuItem --------------------------------------------------------------------------

local MenuItem = Class.new(nil, { 'Text', 'Label', 'LeftIcon', 'RightIcon', 'Enabled', 'Description' })
Items.MenuItem = MenuItem

-- Fields that are not drawn: ParentMenu (set by Menu:AddMenuItem) and
-- ItemData (yours, to identify the item by).
function MenuItem.new(text, description)
    local self = Class.instance(MenuItem)
    self.Text = text or ''
    self.Description = description
    self.LeftIcon = 'NONE'
    self.RightIcon = 'NONE'
    self.Enabled = true
    return self
end

-- The page's row kind, plus 'list' and 'dynamic_list' for the value items.
function MenuItem:Kind()
    return 'item'
end

-- The position in the parent menu's active list, or -1.
function MenuItem:Index()
    return self.ParentMenu and self.ParentMenu:IndexOf(self) or -1
end

function MenuItem:Selected()
    return self.ParentMenu ~= nil and self.ParentMenu.CurrentIndex == self:Index()
end

function MenuItem:PrepareForDisplay() end

function MenuItem:GoRight()
    if self.Enabled and self.ParentMenu then
        self.ParentMenu:SelectItem(self)
    end
end

function MenuItem:GoLeft()
    if self.ParentMenu and navigates_back(self) then
        self.ParentMenu:GoBack()
    end
end

function MenuItem:Select()
    if self.ParentMenu then
        self.ParentMenu:ItemSelectedEvent(self, self:Index())
    end
end

-- MenuCheckboxItem ------------------------------------------------------------------

local MenuCheckboxItem = Class.new(MenuItem, { 'Checked', 'Style' })
Items.MenuCheckboxItem = MenuCheckboxItem

-- style: 'Tick' (default) or 'Cross'.
function MenuCheckboxItem.new(text, description, checked)
    local self = MenuItem.new(text, description)
    setmetatable(self, MenuCheckboxItem)
    self.Checked = checked == true
    self.Style = 'Tick'
    return self
end

function MenuCheckboxItem:Kind()
    return 'checkbox'
end

function MenuCheckboxItem:GetSpriteName(selected)
    local suffix = selected and 'b' or ''
    if not self.Checked then
        return 'shop_box_blank' .. suffix
    end
    if self.Style == 'Cross' then
        return 'shop_box_cross' .. suffix
    end
    return 'shop_box_tick' .. suffix
end

function MenuCheckboxItem:PrepareForDisplay()
    self.RightIcon = 'NONE'
    self.Label = nil
end

function MenuCheckboxItem:GoRight()
    if self.ParentMenu then
        self.ParentMenu:SelectItem(self)
    end
end

function MenuCheckboxItem:Select()
    self.Checked = not self.Checked
    if self.ParentMenu then
        self.ParentMenu:CheckboxChangedEvent(self, self:Index(), self.Checked)
    end
end

-- MenuListItem ----------------------------------------------------------------------

local MenuListItem = Class.new(MenuItem, {
    'ListIndex',
    'ListItems',
    'HideArrowsWhenNotSelected',
    'ShowOpacityPanel',
    'ShowColorPanel',
    'ColorPanelColorType',
    'OpacityPercent',
})
Items.MenuListItem = MenuListItem

-- items: a Lua array of strings. Assign a new array to ListItems to change the
-- values; editing the array in place does not redraw an open menu.
-- ColorPanelColorType is 'Hair' (default) or 'Makeup'.
function MenuListItem.new(text, items, index, description)
    local self = MenuItem.new(text, description)
    setmetatable(self, MenuListItem)
    self.ListItems = items or {}
    self.ListIndex = index or 0
    self.HideArrowsWhenNotSelected = false
    self.ShowOpacityPanel = false
    self.ShowColorPanel = false
    self.ColorPanelColorType = 'Hair'
    self.OpacityPercent = 0
    return self
end

function MenuListItem:Kind()
    return 'list'
end

function MenuListItem:ItemsCount()
    return #self.ListItems
end

function MenuListItem:GetCurrentSelection()
    local count = self:ItemsCount()
    if count > 0 and self.ListIndex >= 0 and self.ListIndex < count then
        return self.ListItems[self.ListIndex + 1]
    end
    return nil
end

function MenuListItem:SetOpacityPercent(percent)
    self.OpacityPercent = math.max(0, math.min(100, percent))
end

function MenuListItem:ResolvedOpacityPercent()
    if self.ShowColorPanel then
        return self.OpacityPercent
    end
    return math.max(0, math.min(100, self.ListIndex * 10))
end

function MenuListItem:PrepareForDisplay()
    if self:ItemsCount() < 1 then
        -- A placeholder value, so the index wrapping below cannot loop forever.
        self.ListItems = { 'N/A' }
    end
    local count = self:ItemsCount()
    self.ListIndex = self.ListIndex % count
    if self.HideArrowsWhenNotSelected and not self:Selected() then
        self.Label = self:GetCurrentSelection() or '~r~N/A'
    else
        self.Label = ('~s~← %s ~s~→'):format(self:GetCurrentSelection() or '~r~N/A~s~')
    end
end

local function change_list_index(self, new_index)
    local old_index = self.ListIndex
    self.ListIndex = new_index
    if self.ParentMenu then
        self.ParentMenu:ListItemIndexChangeEvent(self.ParentMenu, self, old_index, new_index, self:Index())
    end
    Sounds.nav_left_right()
end

function MenuListItem:GoRight()
    local count = self:ItemsCount()
    if count > 0 then
        change_list_index(self, self.ListIndex >= count - 1 and 0 or self.ListIndex + 1)
    end
end

function MenuListItem:GoLeft()
    local count = self:ItemsCount()
    if count > 0 then
        change_list_index(self, self.ListIndex < 1 and count - 1 or self.ListIndex - 1)
    end
end

function MenuListItem:Select()
    if self.ParentMenu then
        self.ParentMenu:ListItemSelectEvent(self.ParentMenu, self, self.ListIndex, self:Index())
    end
end

-- MenuSliderItem --------------------------------------------------------------------

local MenuSliderItem = Class.new(
    MenuItem,
    { 'ShowDivider', 'Position', 'SliderLeftIcon', 'SliderRightIcon', 'BackgroundColor', 'BarColor' }
)
Items.MenuSliderItem = MenuSliderItem

function MenuSliderItem.new(text, min, max, position, description, show_divider)
    local self = MenuItem.new(text, description)
    setmetatable(self, MenuSliderItem)
    rawset(self, 'Min', min)
    rawset(self, 'Max', max)
    self.Position = position
    self.ShowDivider = show_divider == true
    self.SliderLeftIcon = 'NONE'
    self.SliderRightIcon = 'NONE'
    self.BackgroundColor = { 24, 93, 151 }
    self.BarColor = { 53, 165, 223 }
    return self
end

function MenuSliderItem:Kind()
    return 'slider'
end

function MenuSliderItem:PrepareForDisplay()
    self.RightIcon = self.SliderRightIcon
    self.Label = nil
    if self.Position > self.Max or self.Position < self.Min then
        self.Position = (self.Max - self.Min) // 2
    end
end

local function move_slider(self, step)
    local target = self.Position + step
    if target > self.Max or target < self.Min then
        Sounds.error_()
        return
    end
    self.Position = target
    if self.ParentMenu then
        self.ParentMenu:SliderItemChangedEvent(self.ParentMenu, self, target - step, target, self:Index())
    end
    Sounds.nav_left_right()
end

function MenuSliderItem:GoRight()
    move_slider(self, 1)
end

function MenuSliderItem:GoLeft()
    move_slider(self, -1)
end

function MenuSliderItem:Select()
    if self.ParentMenu then
        self.ParentMenu:SliderSelectedEvent(self.ParentMenu, self, self.Position, self:Index())
    end
end

-- MenuDynamicListItem ---------------------------------------------------------------

local MenuDynamicListItem = Class.new(MenuItem, { 'HideArrowsWhenNotSelected', 'CurrentItem' })
Items.MenuDynamicListItem = MenuDynamicListItem

-- callback(item, left) returns the new current value.
function MenuDynamicListItem.new(text, current_item, callback, description)
    local self = MenuItem.new(text, description)
    setmetatable(self, MenuDynamicListItem)
    self.CurrentItem = current_item
    self.HideArrowsWhenNotSelected = false
    rawset(self, 'Callback', callback)
    return self
end

function MenuDynamicListItem:Kind()
    return 'dynamic_list'
end

function MenuDynamicListItem:PrepareForDisplay()
    if self.HideArrowsWhenNotSelected and not self:Selected() then
        self.Label = self.CurrentItem or '~r~N/A'
    else
        self.Label = ('~s~← %s ~s~→'):format(self.CurrentItem or '~r~N/A~s~')
    end
end

local function change_dynamic(self, left)
    local old_value = self.CurrentItem
    local new_value = self.Callback(self, left)
    self.CurrentItem = new_value
    if self.ParentMenu then
        self.ParentMenu:DynamicListItemCurrentItemChanged(self.ParentMenu, self, old_value, new_value)
    end
    Sounds.nav_left_right()
end

function MenuDynamicListItem:GoRight()
    change_dynamic(self, false)
end

function MenuDynamicListItem:GoLeft()
    change_dynamic(self, true)
end

function MenuDynamicListItem:Select()
    if self.ParentMenu then
        self.ParentMenu:DynamicListItemSelectEvent(self.ParentMenu, self, self.CurrentItem)
    end
end

-- SeparatorMenuItem -----------------------------------------------------------------
-- A label, not a row: it never selects, and Menu:SelectItem turns it away
-- silently instead of with the error sound a disabled row gets.

local SeparatorMenuItem = Class.new(MenuItem, { 'ShowArrows' })
Items.SeparatorMenuItem = SeparatorMenuItem

function SeparatorMenuItem.new(text, description, show_arrows)
    local self = MenuItem.new(text, description)
    setmetatable(self, SeparatorMenuItem)
    self.ShowArrows = show_arrows ~= false
    -- What the controller's left and right handling checks.
    self.Enabled = false
    return self
end

function SeparatorMenuItem:Kind()
    return 'separator'
end

function SeparatorMenuItem:Select() end
function SeparatorMenuItem:GoLeft() end
function SeparatorMenuItem:GoRight() end

-- Whether left and right change a value on this item instead of paging or
-- going back.
function Items.holds_value(item)
    local kind = item and item:Kind()
    return kind == 'list' or kind == 'slider' or kind == 'dynamic_list'
end

return Items
