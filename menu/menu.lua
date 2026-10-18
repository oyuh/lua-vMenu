-- Port of MenuAPI/Menu.cs (v4): item management, filtering, pagination,
-- navigation, events and key bindings. Drawing is menu/nui.lua's job.
--
-- Parity notes:
--   * CurrentIndex, ViewIndexOffset, PageIndex and item indices are 0-based.
--   * C# events become single callback fields, called with the menu first:
--     menu.OnItemSelect = function(menu, item, index) end
--   * Drawn properties go through menu/class.lua, so assigning one redraws.

local Class = require('menu.class')
local Items = require('menu.items')
local Nui = require('menu.nui')
local Sounds = require('menu.sounds')
local Ticks = require('menu.ticks')

local Menu = Class.new(nil, {
    'MenuTitle',
    'MenuSubtitle',
    'HeaderTexture',
    'HeaderImage',
    'MenuTitleFont',
    'MenuTitleAlignment',
    'ShowHeaderGlare',
    'MaxItemsOnScreen',
    'CounterPreText',
    'WeaponStats',
    'WeaponComponentStats',
    'VehicleStats',
    'VehicleUpgradeStats',
    'ShowWeaponStatsPanel',
    'ShowVehicleStatsPanel',
})

-- How wide every menu is, in pixels on a screen scaled to 1080 pixels high.
Menu.Width = 500

local WEAPON_STAT_LABELS = { 'PM_DAMAGE', 'PM_FIRERATE', 'PM_ACCURACY', 'PM_RANGE' }
local VEHICLE_STAT_LABELS = { 'FMMC_VEHST_0', 'FMMC_VEHST_1', 'FMMC_VEHST_2', 'FMMC_VEHST_3' }

local function controller()
    -- Required lazily: the controller requires this module.
    return require('menu.controller')
end

local function clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

local function weapon_wheel_active()
    return IsHudComponentActive(19)
end

local function fire(self, event, ...)
    local handler = self[event]
    if handler then
        handler(...)
    end
end

-- HeaderTexture is { dict, name }; HeaderImage is a file in ui/menuapi-banners
-- without its extension, or a full http(s)/nui url.
function Menu.new(title, subtitle)
    local self = Class.instance(Menu)
    rawset(self, 'menu_items', {})
    rawset(self, 'filter_items', {})
    rawset(self, 'filter_active', false)
    rawset(self, 'page_items', {})
    rawset(self, 'page_items_dirty', true)
    rawset(self, 'index', 0)
    rawset(self, 'view_index_offset', 0)
    rawset(self, 'page_index', 0)
    rawset(self, 'visible', false)

    self.MenuTitle = title
    self.MenuSubtitle = subtitle
    self.MaxItemsOnScreen = 10
    self.WeaponStats = { 0, 0, 0, 0 }
    self.WeaponComponentStats = { 0, 0, 0, 0 }
    self.VehicleStats = { 0, 0, 0, 0 }
    self.VehicleUpgradeStats = { 0, 0, 0, 0 }
    self.ShowWeaponStatsPanel = false
    self.ShowVehicleStatsPanel = false

    self.PageSize = 0
    self.WrapPages = true
    self.IgnoreDontOpenMenus = false
    self.EnableInstructionalButtons = true
    self.ShowSelectInstructionalButton = true
    self.ShowBackInstructionalButton = true
    self.SelectButtonText = GetLabelText('HUD_INPUT28')
    self.BackButtonText = GetLabelText('HUD_INPUT53')
    self.ShowPageInstructionalButtons = true
    self.PreviousPageButtonText = 'Previous page'
    self.NextPageButtonText = 'Next page'
    self.ShowChangeValueInstructionalButton = true
    self.ChangeValueButtonText = 'Change'
    -- { { controlString = ..., instructionText = ... } }
    self.CustomInstructionalButtons = {}
    self.KeyBindingHandlers = {}
    return self
end

-- State with change tracking -------------------------------------------------------
-- Read through these instead of fields, so a change always redraws.

local function set_current_index(self, value)
    local clamped = clamp(value, 0, math.max(0, self:Size() - 1))
    if self.index ~= clamped then
        self.index = clamped
        Nui.invalidate()
    end
end

local function set_view_index_offset(self, value)
    if self.view_index_offset ~= value then
        self.view_index_offset = value
        Nui.invalidate()
    end
end

local function set_page_index(self, value)
    if self.page_index ~= value then
        self.page_index = value
        Nui.invalidate()
    end
end

-- CurrentIndex, ViewIndexOffset and PageIndex read like fields.
local base_index = Menu.__index
Menu.__index = function(self, key)
    if key == 'CurrentIndex' then
        return rawget(self, 'index')
    elseif key == 'ViewIndexOffset' then
        return rawget(self, 'view_index_offset')
    elseif key == 'PageIndex' then
        return rawget(self, 'page_index')
    elseif key == 'Visible' then
        return rawget(self, 'visible')
    end
    return base_index(self, key)
end

-- Visible goes through SetVisible, like the C# setter; the indices are only
-- moved through RefreshIndex and navigation, so a stray write cannot desync
-- them from the drawn menu.
local base_newindex = Menu.__newindex
local READ_ONLY = { CurrentIndex = 'RefreshIndex', ViewIndexOffset = 'RefreshIndex', PageIndex = 'GoToPage' }
Menu.__newindex = function(self, key, value)
    if key == 'Visible' then
        self:SetVisible(value == true)
    elseif READ_ONLY[key] then
        error(('%s is read-only, use %s'):format(key, READ_ONLY[key]), 2)
    else
        base_newindex(self, key, value)
    end
end

-- Item lists -------------------------------------------------------------------------

local function invalidate_page(self)
    self.page_items_dirty = true
    Nui.invalidate()
end

local function source_items(self)
    return self.filter_active and self.filter_items or self.menu_items
end

function Menu:Paginated()
    return self.PageSize > 0
end

-- What the menu acts on: the filtered list, narrowed to the current page.
local function active_items(self)
    if not self:Paginated() then
        return source_items(self)
    end
    if self.page_items_dirty then
        local source = source_items(self)
        local start = clamp(self.page_index * self.PageSize, 0, #source)
        local page = {}
        for index = start + 1, math.min(start + self.PageSize, #source) do
            page[#page + 1] = source[index]
        end
        self.page_items = page
        self.page_items_dirty = false
    end
    return self.page_items
end

local function index_in(list, item)
    for index, entry in ipairs(list) do
        if entry == item then
            return index - 1
        end
    end
    return -1
end

function Menu:IndexOf(item)
    return index_in(active_items(self), item)
end

function Menu:Size()
    return #active_items(self)
end

function Menu:PageCount()
    if not self:Paginated() then
        return 1
    end
    return math.max(1, (#source_items(self) + self.PageSize - 1) // self.PageSize)
end

function Menu:VisibleMenuItems()
    local items = active_items(self)
    local visible = {}
    local first = self.view_index_offset
    for index = first + 1, math.min(first + self.MaxItemsOnScreen, #items) do
        visible[#visible + 1] = items[index]
    end
    return visible
end

-- A copy, so callers can change the menu while walking it.
function Menu:GetMenuItems()
    return table.move(active_items(self), 1, #active_items(self), 1, {})
end

function Menu:GetCurrentMenuItem()
    return active_items(self)[self.index + 1]
end

-- Visibility -------------------------------------------------------------------------

-- The single funnel for open, close and back, so every tick learns about a
-- menu opening or closing from here.
function Menu:SetVisible(value)
    controller().set_visible(self, value)
    self.visible = value
    Nui.invalidate()
    Ticks.reevaluate()
end

function Menu:LeftAligned()
    return controller().MenuAlignment == 'Left'
end

function Menu:ResolvedTitleFont()
    return self.MenuTitleFont or controller().DefaultTitleFont
end

-- 'left', 'center' or 'right' for the page.
function Menu:ResolvedTitleAlignment()
    return (self.MenuTitleAlignment or controller().DefaultTitleAlignment):lower()
end

function Menu:ResolvedShowHeaderGlare()
    if self.ShowHeaderGlare ~= nil then
        return self.ShowHeaderGlare
    end
    return controller().DefaultShowHeaderGlare
end

function Menu:StatLabelKey(index)
    return self.ShowWeaponStatsPanel and WEAPON_STAT_LABELS[index] or VEHICLE_STAT_LABELS[index]
end

-- Configuration ----------------------------------------------------------------------

function Menu:SetMaxItemsOnScreen(max)
    self.MaxItemsOnScreen = clamp(max, 3, 10)
end

-- Splits the menu into pages of size items, navigated with left and right. 0
-- turns pagination off. A page still scrolls MaxItemsOnScreen rows at a time.
function Menu:SetPageSize(size)
    self.PageSize = math.max(0, size)
    set_page_index(self, 0)
    invalidate_page(self)
    self:RefreshIndex(0, 0)
end

local function go_to_page(self, page, wrapped)
    if not self:Paginated() then
        return false
    end
    local target = clamp(page, 0, self:PageCount() - 1)
    if target == self.page_index then
        return false
    end
    local old_page = self.page_index
    set_page_index(self, target)
    invalidate_page(self)
    -- A page is a fresh list, so the cursor starts at its top.
    self:RefreshIndex(0, 0)
    Sounds.nav_left_right()
    fire(self, 'OnPageChange', self, old_page, self.page_index, wrapped)
    return true
end

-- Clamped, never wraps. Returns whether the page changed.
function Menu:GoToPage(page)
    return go_to_page(self, page, false)
end

function Menu:NextPage()
    if not self:Paginated() then
        return false
    end
    if self.page_index < self:PageCount() - 1 then
        return go_to_page(self, self.page_index + 1, false)
    end
    return self.WrapPages and go_to_page(self, 0, true)
end

function Menu:PreviousPage()
    if not self:Paginated() then
        return false
    end
    if self.page_index > 0 then
        return go_to_page(self, self.page_index - 1, false)
    end
    return self.WrapPages and go_to_page(self, self:PageCount() - 1, true)
end

-- Puts PageIndex back in range after the items changed underneath it.
local function clamp_page_index(self)
    if not self:Paginated() then
        return
    end
    local target = clamp(self.page_index, 0, self:PageCount() - 1)
    if target ~= self.page_index then
        set_page_index(self, target)
        invalidate_page(self)
    end
end

-- RefreshIndex() resets to the top; RefreshIndex(i) highlights i and scrolls it
-- into view; RefreshIndex(i, offset) also sets the first row on screen.
function Menu:RefreshIndex(index, view_offset)
    index = index or 0
    if view_offset == nil then
        view_offset = index >= self.MaxItemsOnScreen and (index - self.MaxItemsOnScreen + 1) or 0
    end
    set_current_index(self, index)
    set_view_index_offset(self, view_offset)
end

local function keep_cursor_in_view(self)
    local max = self.MaxItemsOnScreen
    local offset = math.min(self.view_index_offset, math.max(self:Size() - max, 0))
    set_view_index_offset(self, clamp(offset, math.max(self.index - max + 1, 0), self.index))
end

-- Adding and removing ----------------------------------------------------------------

function Menu:AddMenuItem(item)
    self.menu_items[#self.menu_items + 1] = item
    item.ParentMenu = self
    invalidate_page(self)
end

-- index counts every item, filtered ones included, and is clamped. The
-- highlighted item stays highlighted, except in a paginated menu.
function Menu:InsertMenuItem(index, item)
    index = clamp(index, 0, #self.menu_items)
    local shift_cursor = not self.filter_active
        and not self:Paginated()
        and #self.menu_items > 0
        and index <= self.index
    table.insert(self.menu_items, index + 1, item)
    item.ParentMenu = self
    invalidate_page(self)
    if shift_cursor then
        set_current_index(self, self.index + 1)
        keep_cursor_in_view(self)
    end
end

-- Moves an item already in this menu, also within an active filter.
function Menu:MoveMenuItem(item, index)
    local from = index_in(self.menu_items, item)
    if from < 0 then
        return
    end
    local current = not self:Paginated() and self:GetCurrentMenuItem() or nil
    table.remove(self.menu_items, from + 1)
    table.insert(self.menu_items, clamp(index, 0, #self.menu_items) + 1, item)

    local filtered_at = self.filter_active and index_in(self.filter_items, item) or -1
    if filtered_at >= 0 then
        table.remove(self.filter_items, filtered_at + 1)
        -- Re-insert after the filtered items that now come before it.
        local position = 0
        for _, other in ipairs(self.menu_items) do
            if other == item then
                break
            end
            if self.filter_items[position + 1] == other then
                position = position + 1
            end
        end
        table.insert(self.filter_items, position + 1, item)
    end

    invalidate_page(self)
    if current then
        set_current_index(self, index_in(source_items(self), current))
        keep_cursor_in_view(self)
    end
end

-- Removes an item by reference, or by its index in the active list.
function Menu:RemoveMenuItem(item)
    if type(item) == 'number' then
        item = active_items(self)[item + 1]
        if not item then
            return
        end
    end
    if index_in(self.menu_items, item) < 0 then
        return
    end
    -- -1 for an item the filter or another page holds back.
    local index = item:Index()
    if index > -1 and self.index >= index then
        if self:Size() > self.index then
            set_current_index(self, self.index - 1)
        else
            set_current_index(self, 0)
        end
    end
    table.remove(self.menu_items, index_in(self.menu_items, item) + 1)
    local filtered_at = index_in(self.filter_items, item)
    if filtered_at >= 0 then
        table.remove(self.filter_items, filtered_at + 1)
    end
    controller().unbind(item)
    item.ParentMenu = nil
    invalidate_page(self)
    clamp_page_index(self)
end

-- Menus the rows opened stay registered, so new rows can bind them again.
-- removed is the RemoveMenu cascade's visited set, when called from there.
function Menu:ClearMenuItems(dont_reset_index, removed)
    if not dont_reset_index then
        set_current_index(self, 0)
        set_view_index_offset(self, 0)
        set_page_index(self, 0)
    end
    if controller().has_bound_menus() then
        -- Over a snapshot: unbinding cascades, and a menu bound in a loop
        -- back to this one would empty this list while it is walked.
        for _, item in ipairs(table.move(self.menu_items, 1, #self.menu_items, 1, {})) do
            controller().unbind(item, removed)
        end
    end
    for _, item in ipairs(self.menu_items) do
        item.ParentMenu = nil
    end
    self.menu_items = {}
    self.filter_items = {}
    self.page_items = {}
    self.filter_active = false
    invalidate_page(self)
end

-- Lets go of everything this menu holds. Only Controller.RemoveMenu calls it.
function Menu:Detach(removed)
    self:ClearMenuItems(false, removed)
    for _, event in ipairs({
        'OnItemSelect',
        'OnCheckboxChange',
        'OnListItemSelect',
        'OnListIndexChange',
        'OnMenuClose',
        'OnMenuOpen',
        'OnIndexChange',
        'OnSliderPositionChange',
        'OnSliderItemSelect',
        'OnDynamicListItemCurrentItemChange',
        'OnDynamicListItemSelect',
        'OnPageChange',
    }) do
        self[event] = nil
    end
    self.KeyBindingHandlers = {}
    self.CustomInstructionalButtons = {}
    self.ParentMenu = nil
end

-- Sorting and filtering --------------------------------------------------------------

-- compare(a, b) returns true when a goes first, like table.sort.
function Menu:SortMenuItems(compare)
    if self.filter_active then
        self.filter_active = false
        self.filter_items = {}
    end
    table.sort(self.menu_items, compare)
    invalidate_page(self)
end

function Menu:FilterMenuItems(predicate)
    if self.filter_active then
        self:ResetFilter()
    end
    self:RefreshIndex(0, 0)
    local filtered = {}
    for _, item in ipairs(self.menu_items) do
        if predicate(item) then
            filtered[#filtered + 1] = item
        end
    end
    self.filter_items = filtered
    self.filter_active = true
    set_page_index(self, 0)
    invalidate_page(self)
end

function Menu:ResetFilter()
    self:RefreshIndex(0, 0)
    self.filter_active = false
    self.filter_items = {}
    set_page_index(self, 0)
    invalidate_page(self)
end

-- Selecting and navigating -----------------------------------------------------------

function Menu:SelectItem(item)
    if weapon_wheel_active() then
        return
    end
    if type(item) == 'number' then
        item = active_items(self)[item + 1]
    end
    if item == nil or item:Kind() == 'separator' then
        return
    end
    if not item.Enabled then
        Sounds.error_()
        return
    end
    Sounds.select()
    item:Select()
    Nui.invalidate()
    local child = controller().bound_menu(item)
    if child then
        local current = controller().GetCurrentMenu()
        if current then
            controller().AddSubmenu(current, child)
            current:CloseMenu()
        end
        child:OpenMenu()
    end
end

function Menu:GoBack()
    if weapon_wheel_active() then
        return
    end
    Sounds.back()
    self:CloseMenu()
    if self.ParentMenu then
        self.ParentMenu:OpenMenu()
    end
end

function Menu:CloseMenu()
    self:SetVisible(false)
    fire(self, 'OnMenuClose', self)
end

function Menu:OpenMenu()
    self:SetVisible(true)
    fire(self, 'OnMenuOpen', self)
end

function Menu:GoUp()
    if not self.visible or self:Size() < 2 or weapon_wheel_active() then
        return
    end
    local old_item = active_items(self)[self.index + 1]
    if self.index == 0 then
        set_current_index(self, self:Size() - 1)
    else
        set_current_index(self, self.index - 1)
    end
    local current = self:GetCurrentMenuItem()
    if current == nil or index_in(self:VisibleMenuItems(), current) < 0 then
        set_view_index_offset(self, self.view_index_offset - 1)
        if self.view_index_offset < 0 then
            set_view_index_offset(self, math.max(self:Size() - self.MaxItemsOnScreen, 0))
        end
    end
    fire(self, 'OnIndexChange', self, old_item, current, old_item:Index(), self.index)
    Sounds.nav_up_down()
end

function Menu:GoDown()
    if not self.visible or self:Size() < 2 or weapon_wheel_active() then
        return
    end
    local old_item = active_items(self)[self.index + 1]
    if self.index > 0 and self.index >= self:Size() - 1 then
        set_current_index(self, 0)
    else
        set_current_index(self, self.index + 1)
    end
    local current = self:GetCurrentMenuItem()
    if current == nil or index_in(self:VisibleMenuItems(), current) < 0 then
        set_view_index_offset(self, self.view_index_offset + 1)
        if self.index == 0 then
            set_view_index_offset(self, 0)
        end
    end
    fire(self, 'OnIndexChange', self, old_item, current, old_item:Index(), self.index)
    Sounds.nav_up_down()
end

-- Whether left and right turn the page instead of acting on item. Items that
-- hold a value keep their arrows.
function Menu:IsPageNavigation(item)
    return self:Paginated() and not Items.holds_value(item)
end

local function go_sideways(self, step)
    local Controller = controller()
    if not Controller.AreMenuButtonsEnabled() or weapon_wheel_active() then
        return
    end
    local item = self:GetCurrentMenuItem()
    if self:IsPageNavigation(item) then
        if step < 0 then
            self:PreviousPage()
        else
            self:NextPage()
        end
        return
    end
    if item then
        if step < 0 then
            item:GoLeft()
        else
            item:GoRight()
        end
        Nui.invalidate()
    elseif
        step < 0
        and Controller.NavigateMenuUsingArrows
        and not Controller.DisableBackButton
        and not (Controller.PreventExitingMenu and self.ParentMenu == nil)
    then
        self:GoBack()
    end
end

function Menu:GoLeft()
    go_sideways(self, -1)
end

function Menu:GoRight()
    go_sideways(self, 1)
end

-- Event dispatch, called by the items --------------------------------------------------

function Menu:ItemSelectedEvent(item, index)
    fire(self, 'OnItemSelect', self, item, index)
end

function Menu:CheckboxChangedEvent(item, index, checked)
    fire(self, 'OnCheckboxChange', self, item, index, checked)
end

function Menu:ListItemSelectEvent(menu, item, selected_index, index)
    fire(self, 'OnListItemSelect', menu, item, selected_index, index)
end

function Menu:ListItemIndexChangeEvent(menu, item, old_index, new_index, index)
    fire(self, 'OnListIndexChange', menu, item, old_index, new_index, index)
end

function Menu:SliderItemChangedEvent(menu, item, old_position, new_position, index)
    fire(self, 'OnSliderPositionChange', menu, item, old_position, new_position, index)
end

function Menu:SliderSelectedEvent(menu, item, position, index)
    fire(self, 'OnSliderItemSelect', menu, item, position, index)
end

function Menu:DynamicListItemCurrentItemChanged(menu, item, old_value, new_value)
    fire(self, 'OnDynamicListItemCurrentItemChange', menu, item, old_value, new_value)
end

function Menu:DynamicListItemSelectEvent(menu, item, current)
    fire(self, 'OnDynamicListItemSelect', menu, item, current)
end

-- Stats panels -------------------------------------------------------------------------

local function clamp_stat(value)
    if value ~= value or value == math.huge or value == -math.huge then
        return 0
    end
    return clamp(value, 0, 1)
end

-- Values from 0 to 1.
function Menu:SetWeaponStats(damage, fire_rate, accuracy, range)
    self.WeaponStats = { clamp_stat(damage), clamp_stat(fire_rate), clamp_stat(accuracy), clamp_stat(range) }
end

-- Added on top of the weapon stats.
function Menu:SetWeaponComponentStats(damage, fire_rate, accuracy, range)
    local base = self.WeaponStats
    self.WeaponComponentStats = {
        clamp_stat(base[1] + damage),
        clamp_stat(base[2] + fire_rate),
        clamp_stat(base[3] + accuracy),
        clamp_stat(base[4] + range),
    }
end

function Menu:SetVehicleStats(top_speed, acceleration, braking, traction)
    self.VehicleStats = { clamp_stat(top_speed), clamp_stat(acceleration), clamp_stat(braking), clamp_stat(traction) }
end

-- Added on top of the vehicle stats.
function Menu:SetVehicleUpgradeStats(top_speed, acceleration, braking, traction)
    local base = self.VehicleStats
    self.VehicleUpgradeStats = {
        clamp_stat(base[1] + top_speed),
        clamp_stat(base[2] + acceleration),
        clamp_stat(base[3] + braking),
        clamp_stat(base[4] + traction),
    }
end

-- Key bindings -------------------------------------------------------------------------

-- Registers a key the player can rebind, and calls handler(menu, binding)
-- while this menu is open. press_type: 'JUST_RELEASED' (default),
-- 'JUST_PRESSED', 'RELEASED' or 'PRESSED'.
function Menu:AddKeyBinding(name, description, keyboard_key, controller_button, press_type, handler, button_text)
    local Input = require('menu.input')
    local entry = {
        Binding = Input.register_custom(name, description, keyboard_key, controller_button),
        PressType = press_type or 'JUST_RELEASED',
        Handler = handler,
        ButtonText = button_text,
    }
    self.KeyBindingHandlers[#self.KeyBindingHandlers + 1] = entry
    return entry
end

-- Whether a press on binding reaches a handler here, so the rest can be dropped.
function Menu:Handles(binding)
    if controller().DisableMenuButtons then
        return false
    end
    for _, entry in ipairs(self.KeyBindingHandlers) do
        if entry.Handler and entry.Binding == binding then
            return true
        end
    end
    return false
end

function Menu:ProcessKeyBindings()
    if #self.KeyBindingHandlers == 0 or controller().DisableMenuButtons then
        return
    end
    for _, entry in ipairs(self.KeyBindingHandlers) do
        if entry.Handler then
            local binding = entry.Binding
            local triggered
            if entry.PressType == 'JUST_PRESSED' then
                triggered = binding:consume_press()
            elseif entry.PressType == 'JUST_RELEASED' then
                triggered = binding:consume_release()
            elseif entry.PressType == 'PRESSED' then
                triggered = binding:held()
            elseif entry.PressType == 'RELEASED' then
                triggered = not binding:held()
            end
            if triggered then
                entry.Handler(self, binding)
            end
        end
    end
end

return Menu
