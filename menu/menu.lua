-- Port of MenuAPI/Menu.cs — menu state, item management, navigation, and
-- event dispatch. Drawing (menu/draw.lua) consumes this state per frame.
--
-- Parity notes:
--   * CurrentIndex, ViewIndexOffset, and item indices are 0-based like C#.
--   * C# events become single callback fields (vMenu assigns exactly one
--     handler per event): menu.OnItemSelect = function(menu, item, index) end
--   * All navigation quirks (wrap rules, view offset math, remove-item index
--     adjustment) are ported behavior-for-behavior.

local Controller = require('menu.controller')
local Sounds = require('menu.sounds')

local Menu = {}
Menu.__index = Menu

local function clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

function Menu.new(title, subtitle)
    return setmetatable({
        MenuTitle = title,
        MenuSubtitle = subtitle,
        MenuItems = {},
        FilterItems = {},
        Visible = false,
        CurrentIndex = 0,
        ViewIndexOffset = 0,
        MaxItemsOnScreen = 10,
        CounterPreText = nil,
        ParentMenu = nil,
        IgnoreDontOpenMenus = false,
        EnableInstructionalButtons = true,
        ShowWeaponStatsPanel = false,
        ShowVehicleStatsPanel = false,

        -- rendering state (Menu.cs private fields; consumed by menu/render.lua)
        Position = { x = 0.0, y = 0.0 },
        MenuItemsYOffset = 0.0,
        HeaderTexture = nil, -- { dict = ..., name = ... } to override the default banner
        WeaponStats = { 0.0, 0.0, 0.0, 0.0 },
        WeaponComponentStats = { 0.0, 0.0, 0.0, 0.0 },
        VehicleStats = { 0.0, 0.0, 0.0, 0.0 },
        VehicleUpgradeStats = { 0.0, 0.0, 0.0, 0.0 },
        -- array of { control = <id>, label = <text> }; nil = default Select/Back
        InstructionalButtons = nil,
        -- Menu.ButtonPressHandler list: { control, check_type
        -- ('JUST_RELEASED'|'JUST_PRESSED'|'RELEASED'|'PRESSED'), handler,
        -- disable_control }; consumed by the in-game input tick.
        ButtonPressHandlers = nil,

        filter_active = false,

        -- event callbacks (single handler each)
        OnItemSelect = nil,
        OnCheckboxChange = nil,
        OnListItemSelect = nil,
        OnListIndexChange = nil,
        OnMenuClose = nil,
        OnMenuOpen = nil,
        OnIndexChange = nil,
        OnSliderPositionChange = nil,
        OnSliderItemSelect = nil,
        OnDynamicListItemCurrentItemChange = nil,
        OnDynamicListItemSelect = nil,
    }, Menu)
end

-- ---------------------------------------------------------------------------
-- Event dispatch (Menu.cs "virtual voids")
-- ---------------------------------------------------------------------------

local function fire(handler, ...)
    if handler then
        handler(...)
    end
end

function Menu:ItemSelectedEvent(item, index)
    fire(self.OnItemSelect, self, item, index)
end

function Menu:CheckboxChangedEvent(item, index, checked)
    fire(self.OnCheckboxChange, self, item, index, checked)
end

function Menu:ListItemSelectEvent(menu, item, selected_index, item_index)
    fire(self.OnListItemSelect, menu, item, selected_index, item_index)
end

function Menu:ListItemIndexChangeEvent(menu, item, old_index, new_index, item_index)
    fire(self.OnListIndexChange, menu, item, old_index, new_index, item_index)
end

function Menu:MenuCloseEvent(menu)
    fire(self.OnMenuClose, menu)
end

function Menu:MenuOpenEvent(menu)
    fire(self.OnMenuOpen, menu)
end

function Menu:IndexChangeEvent(menu, old_item, new_item, old_index, new_index)
    fire(self.OnIndexChange, menu, old_item, new_item, old_index, new_index)
end

function Menu:SliderItemChangedEvent(menu, item, old_position, new_position, item_index)
    fire(self.OnSliderPositionChange, menu, item, old_position, new_position, item_index)
end

function Menu:SliderSelectedEvent(menu, item, position, item_index)
    fire(self.OnSliderItemSelect, menu, item, position, item_index)
end

function Menu:DynamicListItemCurrentItemChanged(menu, item, old_value, new_value)
    fire(self.OnDynamicListItemCurrentItemChange, menu, item, old_value, new_value)
end

function Menu:DynamicListItemSelectEvent(menu, item, current_item)
    fire(self.OnDynamicListItemSelect, menu, item, current_item)
end

-- ---------------------------------------------------------------------------
-- Items & indices
-- ---------------------------------------------------------------------------

function Menu:Size()
    if self.filter_active then
        return #self.FilterItems
    end
    return #self.MenuItems
end

function Menu:GetMenuItems()
    if self.filter_active then
        return self.FilterItems
    end
    return self.MenuItems
end

-- 0-based index of the item in the active list, or -1.
function Menu:IndexOf(item)
    for i, candidate in ipairs(self:GetMenuItems()) do
        if candidate == item then
            return i - 1
        end
    end
    return -1
end

function Menu:GetCurrentMenuItem()
    return self:GetMenuItems()[self.CurrentIndex + 1]
end

function Menu:SetCurrentIndex(value)
    self.CurrentIndex = clamp(value, 0, math.max(0, self:Size() - 1))
end

function Menu:SetMaxItemsOnScreen(max)
    self.MaxItemsOnScreen = clamp(max, 3, 10)
end

function Menu:RefreshIndex(index, view_offset)
    index = index or 0
    if view_offset == nil then
        view_offset = index > self.MaxItemsOnScreen and (index - self.MaxItemsOnScreen) or 0
    end
    self:SetCurrentIndex(index)
    self.ViewIndexOffset = view_offset
end

function Menu:AddMenuItem(item)
    self.MenuItems[#self.MenuItems + 1] = item
    item.PositionOnScreen = #self.MenuItems - 1
    item.ParentMenu = self
end

function Menu:ClearMenuItems(dont_reset_index)
    if not dont_reset_index then
        self.CurrentIndex = 0
        self.ViewIndexOffset = 0
    end
    self.MenuItems = {}
    self.FilterItems = {}
end

function Menu:RemoveMenuItem(item)
    if type(item) == 'number' then
        local index = item
        if self.CurrentIndex >= index then
            if self:Size() > self.CurrentIndex then
                self:SetCurrentIndex(self.CurrentIndex - 1)
            else
                self.CurrentIndex = 0
            end
        end
        if index > -1 and index < self:Size() then
            local target = self.MenuItems[index + 1]
            if target then
                self:_remove_item_object(target, true)
            end
        end
        return
    end
    self:_remove_item_object(item, false)
end

function Menu:_remove_item_object(item, index_already_adjusted)
    local position = nil
    for i, candidate in ipairs(self.MenuItems) do
        if candidate == item then
            position = i
            break
        end
    end
    if not position then
        return
    end
    if not index_already_adjusted and self.CurrentIndex >= (position - 1) then
        if self:Size() > self.CurrentIndex then
            self:SetCurrentIndex(self.CurrentIndex - 1)
        else
            self.CurrentIndex = 0
        end
    end
    table.remove(self.MenuItems, position)
end

-- ---------------------------------------------------------------------------
-- Open / close / navigation
-- ---------------------------------------------------------------------------

function Menu:OpenMenu()
    self.Visible = true
    self:MenuOpenEvent(self)
end

function Menu:CloseMenu()
    self.Visible = false
    self:MenuCloseEvent(self)
end

function Menu:GoBack()
    Sounds.back()
    self:CloseMenu()
    if self.ParentMenu then
        self.ParentMenu:OpenMenu()
    end
end

function Menu:SelectItem(item)
    if type(item) == 'number' then
        local list = self:GetMenuItems()
        local target = list[item + 1]
        if target then
            self:SelectItem(target)
        end
        return
    end
    if item == nil then
        return
    end
    if not item.Enabled then
        Sounds.error_()
        return
    end
    Sounds.select()
    item:Select()
    local bound = Controller.MenuButtons[item]
    if bound then
        Controller.AddSubmenu(Controller.GetCurrentMenu(), bound)
        Controller.GetCurrentMenu():CloseMenu()
        bound:OpenMenu()
    end
end

local function in_visible_window(self)
    return self.CurrentIndex >= self.ViewIndexOffset
        and self.CurrentIndex < self.ViewIndexOffset + self.MaxItemsOnScreen
end

function Menu:GoUp()
    if not self.Visible or self:Size() < 2 then
        return
    end
    local old_item = self:GetMenuItems()[self.CurrentIndex + 1]

    if self.CurrentIndex == 0 then
        self.CurrentIndex = self:Size() - 1
    else
        self.CurrentIndex = self.CurrentIndex - 1
    end

    local current = self:GetCurrentMenuItem()
    if current == nil or not in_visible_window(self) then
        self.ViewIndexOffset = self.ViewIndexOffset - 1
        if self.ViewIndexOffset < 0 then
            self.ViewIndexOffset = math.max(self:Size() - self.MaxItemsOnScreen, 0)
        end
    end

    self:IndexChangeEvent(self, old_item, current, old_item:Index(), self.CurrentIndex)
    Sounds.nav_up_down()
end

function Menu:GoDown()
    if not self.Visible or self:Size() < 2 then
        return
    end
    local old_item = self:GetMenuItems()[self.CurrentIndex + 1]

    if self.CurrentIndex > 0 and self.CurrentIndex >= self:Size() - 1 then
        self.CurrentIndex = 0
    else
        self.CurrentIndex = self.CurrentIndex + 1
    end

    local current = self:GetCurrentMenuItem()
    if current == nil or not in_visible_window(self) then
        self.ViewIndexOffset = self.ViewIndexOffset + 1
        if self.CurrentIndex == 0 then
            self.ViewIndexOffset = 0
        end
    end

    self:IndexChangeEvent(self, old_item, current, old_item:Index(), self.CurrentIndex)
    Sounds.nav_up_down()
end

function Menu:GoLeft()
    if not Controller.AreMenuButtonsEnabled() then
        return
    end
    local item = self:GetCurrentMenuItem()
    if item ~= nil then
        item:GoLeft()
    elseif
        Controller.NavigateMenuUsingArrows
        and not Controller.DisableBackButton
        and not (Controller.PreventExitingMenu and self.ParentMenu == nil)
    then
        self:GoBack()
    end
end

function Menu:GoRight()
    if not Controller.AreMenuButtonsEnabled() then
        return
    end
    local item = self:GetCurrentMenuItem()
    if item ~= nil then
        item:GoRight()
    end
end

-- ---------------------------------------------------------------------------
-- Sorting & filtering
-- ---------------------------------------------------------------------------

function Menu:SortMenuItems(compare)
    if self.filter_active then
        self.filter_active = false
        self.FilterItems = {}
    end
    table.sort(self.MenuItems, compare)
end

function Menu:FilterMenuItems(predicate)
    if self.filter_active then
        self:ResetFilter()
    end
    self:RefreshIndex(0, 0)
    self.ViewIndexOffset = 0
    local filtered = {}
    for _, item in ipairs(self.MenuItems) do
        if predicate(item) then
            filtered[#filtered + 1] = item
        end
    end
    self.FilterItems = filtered
    self.filter_active = true
end

function Menu:ResetFilter()
    self:RefreshIndex(0, 0)
    self.filter_active = false
    self.FilterItems = {}
end

-- ---------------------------------------------------------------------------
-- Stats panels & instructional buttons (Menu.cs public setters)
-- ---------------------------------------------------------------------------

local function clamp01(value)
    return clamp(value, 0.0, 1.0)
end

function Menu:SetWeaponStats(damage, fire_rate, accuracy, range)
    self.WeaponStats = { clamp01(damage), clamp01(fire_rate), clamp01(accuracy), clamp01(range) }
end

function Menu:SetWeaponComponentStats(damage, fire_rate, accuracy, range)
    self.WeaponComponentStats = {
        clamp01(self.WeaponStats[1] + damage),
        clamp01(self.WeaponStats[2] + fire_rate),
        clamp01(self.WeaponStats[3] + accuracy),
        clamp01(self.WeaponStats[4] + range),
    }
end

function Menu:SetVehicleStats(top_speed, acceleration, braking, traction)
    self.VehicleStats = { clamp01(top_speed), clamp01(acceleration), clamp01(braking), clamp01(traction) }
end

function Menu:SetVehicleUpgradeStats(top_speed, acceleration, braking, traction)
    self.VehicleUpgradeStats = {
        clamp01(self.VehicleStats[1] + top_speed),
        clamp01(self.VehicleStats[2] + acceleration),
        clamp01(self.VehicleStats[3] + braking),
        clamp01(self.VehicleStats[4] + traction),
    }
end

function Menu:AddInstructionalButton(control, label)
    self.InstructionalButtons = self.InstructionalButtons or {}
    self.InstructionalButtons[#self.InstructionalButtons + 1] = { control = control, label = label }
end

-- Menu.ButtonPressHandlers.Add: fire handler(menu, control) when the given
-- control matches the check type while this menu is open.
function Menu:AddButtonPressHandler(control, check_type, handler, disable_control)
    self.ButtonPressHandlers = self.ButtonPressHandlers or {}
    self.ButtonPressHandlers[#self.ButtonPressHandlers + 1] = {
        control = control,
        check_type = check_type,
        handler = handler,
        disable_control = disable_control ~= false,
    }
end

function Menu:RemoveInstructionalButton(control)
    if not self.InstructionalButtons then
        return
    end
    for i, button in ipairs(self.InstructionalButtons) do
        if button.control == control then
            table.remove(self.InstructionalButtons, i)
            return
        end
    end
end

return Menu
