-- Port of MenuAPI/items/*.cs: the menu item model.
--
-- Public API deliberately mirrors MenuAPI (PascalCase members, 0-based
-- indices) so upstream vMenu menu code ports line-for-line. Rendering state
-- (icons, labels) is carried here; drawing happens in menu/draw.lua.

local Sounds = require('menu.sounds')

local Items = {}

-- MenuItem.Icon enum (order matters: serialized as numbers in category KVPs).
Items.Icon = {
    NONE = 0,
    LOCK = 1,
    STAR = 2,
    WARNING = 3,
    CROWN = 4,
    MEDAL_BRONZE = 5,
    MEDAL_GOLD = 6,
    MEDAL_SILVER = 7,
    CASH = 8,
    COKE = 9,
    HEROIN = 10,
    METH = 11,
    WEED = 12,
    AMMO = 13,
    ARMOR = 14,
    BARBER = 15,
    CLOTHING = 16,
    FRANKLIN = 17,
    BIKE = 18,
    CAR = 19,
    GUN = 20,
    HEALTH_HEART = 21,
    MAKEUP_BRUSH = 22,
    MASK = 23,
    MICHAEL = 24,
    TATTOO = 25,
    TICK = 26,
    TREVOR = 27,
    FEMALE = 28,
    MALE = 29,
    LOCK_ARENA = 30,
    ADVERSARY = 31,
    BASE_JUMPING = 32,
    BRIEFCASE = 33,
    MISSION_STAR = 34,
    DEATHMATCH = 35,
    CASTLE = 36,
    TROPHY = 37,
    RACE_FLAG = 38,
    RACE_FLAG_PLANE = 39,
    RACE_FLAG_BICYCLE = 40,
    RACE_FLAG_PERSON = 41,
    RACE_FLAG_CAR = 42,
    RACE_FLAG_BOAT_ANCHOR = 43,
    ROCKSTAR = 44,
    STUNT = 45,
    STUNT_PREMIUM = 46,
    RACE_FLAG_STUNT_JUMP = 47,
    SHIELD = 48,
    TEAM_DEATHMATCH = 49,
    VEHICLE_DEATHMATCH = 50,
}

-- ---------------------------------------------------------------------------
-- MenuItem (base)
-- ---------------------------------------------------------------------------

local MenuItem = {}
MenuItem.__index = MenuItem
Items.MenuItem = MenuItem

function MenuItem.new(text, description)
    return setmetatable({
        Text = text,
        Description = description,
        Label = nil,
        LeftIcon = Items.Icon.NONE,
        RightIcon = Items.Icon.NONE,
        Enabled = true,
        ItemData = nil,
        ParentMenu = nil,
        PositionOnScreen = 0,
    }, MenuItem)
end

-- 0-based index within the parent menu's active (possibly filtered) item
-- list, -1 when orphaned, exactly like MenuAPI's computed Index property.
function MenuItem:Index()
    if self.ParentMenu then
        return self.ParentMenu:IndexOf(self)
    end
    return -1
end

function MenuItem:Selected()
    if self.ParentMenu then
        return self.ParentMenu.CurrentIndex == self:Index()
    end
    return false
end

function MenuItem:Select()
    self.ParentMenu:ItemSelectedEvent(self, self:Index())
end

function MenuItem:GoLeft() end -- luacheck: ignore 212

function MenuItem:GoRight() end -- luacheck: ignore 212

local function subclass(base)
    local class = setmetatable({}, { __index = base })
    class.__index = class
    return class
end

-- ---------------------------------------------------------------------------
-- MenuCheckboxItem
-- ---------------------------------------------------------------------------

local MenuCheckboxItem = subclass(MenuItem)
Items.MenuCheckboxItem = MenuCheckboxItem

-- Checkbox visual styles.
MenuCheckboxItem.Style = { Tick = 0, Cross = 1 }

function MenuCheckboxItem.new(text, description, checked)
    local item = MenuItem.new(text, description)
    item.Checked = checked == true
    item.CheckboxStyle = MenuCheckboxItem.Style.Tick
    return setmetatable(item, MenuCheckboxItem)
end

function MenuCheckboxItem:Select()
    self.Checked = not self.Checked
    self.ParentMenu:CheckboxChangedEvent(self, self:Index(), self.Checked)
end

-- MenuAPI quirk: pressing right on a checkbox toggles it.
function MenuCheckboxItem:GoRight()
    self.ParentMenu:SelectItem(self)
end

-- ---------------------------------------------------------------------------
-- MenuListItem
-- ---------------------------------------------------------------------------

local MenuListItem = subclass(MenuItem)
Items.MenuListItem = MenuListItem

function MenuListItem.new(text, items, index, description)
    local item = MenuItem.new(text, description)
    item.ListItems = items or {}
    item.ListIndex = index or 0 -- 0-based, like MenuAPI
    item.HideArrowsWhenNotSelected = false
    item.ShowOpacityPanel = false
    item.ShowColorPanel = false
    return setmetatable(item, MenuListItem)
end

function MenuListItem:ItemsCount()
    return #self.ListItems
end

function MenuListItem:GetCurrentSelection()
    return self.ListItems[self.ListIndex + 1]
end

function MenuListItem:GoRight()
    local count = self:ItemsCount()
    if count > 0 then
        local old_index = self.ListIndex
        local new_index = old_index
        if old_index >= count - 1 then
            new_index = 0
        else
            new_index = new_index + 1
        end
        self.ListIndex = new_index
        self.ParentMenu:ListItemIndexChangeEvent(self.ParentMenu, self, old_index, new_index, self:Index())
        Sounds.nav_left_right()
    end
end

function MenuListItem:GoLeft()
    local count = self:ItemsCount()
    if count > 0 then
        local old_index = self.ListIndex
        local new_index = old_index
        if old_index < 1 then
            new_index = count - 1
        else
            new_index = new_index - 1
        end
        self.ListIndex = new_index
        self.ParentMenu:ListItemIndexChangeEvent(self.ParentMenu, self, old_index, new_index, self:Index())
        Sounds.nav_left_right()
    end
end

function MenuListItem:Select()
    self.ParentMenu:ListItemSelectEvent(self.ParentMenu, self, self.ListIndex, self:Index())
end

-- ---------------------------------------------------------------------------
-- MenuSliderItem
-- ---------------------------------------------------------------------------

local MenuSliderItem = subclass(MenuItem)
Items.MenuSliderItem = MenuSliderItem

function MenuSliderItem.new(text, min, max, position, description)
    local item = MenuItem.new(text, description)
    item.Min = min or 0
    item.Max = max or 10
    item.Position = position or 0
    item.ShowDivider = false
    item.SliderLeftIcon = Items.Icon.NONE
    item.SliderRightIcon = Items.Icon.NONE
    -- MenuAPI slider bar colors ({r,g,b,a}); verify against C# in-game (docs/VERIFY.md)
    item.BackgroundColor = { 23, 55, 93, 255 }
    item.BarColor = { 93, 182, 229, 255 }
    return setmetatable(item, MenuSliderItem)
end

function MenuSliderItem:GoLeft()
    if self.Position > self.Min then
        self.Position = self.Position - 1
        self.ParentMenu:SliderItemChangedEvent(self.ParentMenu, self, self.Position + 1, self.Position, self:Index())
        Sounds.nav_left_right()
    else
        Sounds.error_()
    end
end

function MenuSliderItem:GoRight()
    if self.Position < self.Max then
        self.Position = self.Position + 1
        self.ParentMenu:SliderItemChangedEvent(self.ParentMenu, self, self.Position - 1, self.Position, self:Index())
        Sounds.nav_left_right()
    else
        Sounds.error_()
    end
end

function MenuSliderItem:Select()
    self.ParentMenu:SliderSelectedEvent(self.ParentMenu, self, self.Position, self:Index())
end

-- ---------------------------------------------------------------------------
-- MenuDynamicListItem
-- ---------------------------------------------------------------------------

local MenuDynamicListItem = subclass(MenuItem)
Items.MenuDynamicListItem = MenuDynamicListItem

-- callback(item, going_left) -> new CurrentItem string
function MenuDynamicListItem.new(text, current_item, callback, description)
    local item = MenuItem.new(text, description)
    item.CurrentItem = current_item
    item.Callback = callback
    return setmetatable(item, MenuDynamicListItem)
end

local function dynamic_change(self, going_left)
    if not self.Callback then
        return
    end
    local old_value = self.CurrentItem
    local new_value = self.Callback(self, going_left)
    self.CurrentItem = new_value
    self.ParentMenu:DynamicListItemCurrentItemChanged(self.ParentMenu, self, old_value, new_value)
    Sounds.nav_left_right()
end

function MenuDynamicListItem:GoLeft()
    dynamic_change(self, true)
end

function MenuDynamicListItem:GoRight()
    dynamic_change(self, false)
end

function MenuDynamicListItem:Select()
    self.ParentMenu:DynamicListItemSelectEvent(self.ParentMenu, self, self.CurrentItem)
end

return Items
