-- Rendering layer: ports Menu.Draw() and MenuItem.Draw() (FiveM branches of
-- Menu.cs / items/*.cs) onto the classes from menu/menu.lua and menu/items.lua.
-- Requiring this module augments those classes with Draw methods; nothing here
-- runs outside the game (every function touches natives).
--
-- The icon sprite table covers the icons upstream vMenu actually uses
-- (LOCK, WARNING, TICK, GUN, AMMO, MALE, FEMALE, CAR + NONE); extend it from
-- MenuItem.cs when new upstream code needs more.

local Controller = require('menu.controller')
local Draw = require('menu.draw')
local Items = require('menu.items')
local Menu = require('menu.menu')

local Icon = Items.Icon
local ROW_HEIGHT = Draw.ROW_HEIGHT
local WIDTH = Draw.WIDTH

local function clamp(value, minimum, maximum)
    return math.min(math.max(value, minimum), maximum)
end

local function left_aligned()
    return Controller.MenuAlignment == 'Left'
end

-- ---------------------------------------------------------------------------
-- Icon sprites (MenuItem.cs GetSprite* helpers, subset)
-- ---------------------------------------------------------------------------

-- monochrome = true: colour flips black-on-white when the row is selected
-- (upstream: selected ? (enabled ? 0 : 50) : (enabled ? 255 : 109)).
-- Others stay white/grey (enabled ? 255 : 109) and may swap _a/_b sprites.
local ICON_SPRITES = {
    [Icon.LOCK] = { dict = 'commonmenu', name = 'shop_lock', monochrome = true, w = 24.0, h = 30.0 },
    [Icon.TICK] = { dict = 'commonmenu', name = 'shop_tick_icon', monochrome = true, w = 16.0, h = 24.0 },
    [Icon.WARNING] = { dict = 'commonmenu', name = 'mp_alerttriangle', w = 38.0, h = 38.0 },
    [Icon.GUN] = {
        dict = 'commonmenu',
        name = 'shop_gunclub_icon_a',
        selected_name = 'shop_gunclub_icon_b',
        w = 38.0,
        h = 38.0,
    },
    [Icon.AMMO] = {
        dict = 'commonmenu',
        name = 'shop_ammo_icon_a',
        selected_name = 'shop_ammo_icon_b',
        w = 38.0,
        h = 38.0,
    },
    [Icon.CAR] = {
        dict = 'commonmenu',
        name = 'shop_garage_icon_a',
        selected_name = 'shop_garage_icon_b',
        w = 38.0,
        h = 38.0,
    },
    [Icon.MALE] = { dict = 'mpleaderboard', name = 'leaderboard_male_icon', monochrome = true, w = 16.0, h = 24.0 },
    [Icon.FEMALE] = { dict = 'mpleaderboard', name = 'leaderboard_female_icon', monochrome = true, w = 16.0, h = 26.0 },
}

local function icon_colour(sprite, selected, enabled)
    if sprite.monochrome then
        local shade
        if selected then
            shade = enabled and 0 or 50
        else
            shade = enabled and 255 or 109
        end
        return shade, shade, shade
    end
    local shade = enabled and 255 or 109
    return shade, shade, shade
end

local function draw_icon(icon, selected, enabled, x, y)
    local sprite = ICON_SPRITES[icon]
    if not sprite then
        return
    end
    local W, H = Draw.screen_width(), Draw.screen_height()
    local name = (selected and sprite.selected_name) or sprite.name
    local r, g, b = icon_colour(sprite, selected, enabled)
    Draw.set_gfx_align(true)
    DrawSprite(sprite.dict, name, x, y, sprite.w / W, sprite.h / H, 0.0, r, g, b, 255)
    Draw.reset_gfx_align()
end

-- ---------------------------------------------------------------------------
-- MenuItem.Draw (base)
-- ---------------------------------------------------------------------------

function Items.MenuItem:Draw(index_offset)
    local menu = self.ParentMenu
    if not menu then
        return
    end
    local W, H = Draw.screen_width(), Draw.screen_height()
    local font = 0
    local text_size = (14.0 * 27.0) / H
    local selected, enabled = self:Selected(), self.Enabled
    local text_color = selected and (enabled and 0 or 50) or (enabled and 255 or 109)

    local y_offset = menu.MenuItemsYOffset + 1.0 - (ROW_HEIGHT * clamp(menu:Size(), 0, menu.MaxItemsOnScreen))
    local text_x_offset = 0.0
    local right_icon_offset = 0.0

    -- background highlight + row position (MenuItem.DrawBackground)
    local x = (menu.Position.x + (WIDTH / 2.0)) / W
    local y = (menu.Position.y + ((self:Index() - index_offset) * ROW_HEIGHT) + 20.0 + y_offset) / H
    if selected then
        Draw.set_gfx_align(left_aligned())
        DrawRect(x, y, WIDTH / W, ROW_HEIGHT / H, 255, 255, 255, 225)
        Draw.reset_gfx_align()
    end

    local text_min_x = (text_x_offset / W) + (10.0 / W)
    local text_max_x = (WIDTH - 10.0) / W
    local text_y = y - ((30.0 / 2.0) / H)

    -- left icon
    if self.LeftIcon and self.LeftIcon ~= Icon.NONE then
        text_x_offset = 25.0
        local sprite_x = left_aligned() and (20.0 / W) or (Draw.safe_zone() - ((WIDTH - 20.0) / W))
        draw_icon(self.LeftIcon, selected, enabled, sprite_x, y)
        text_min_x = (text_x_offset / W) + (10.0 / W)
    end

    -- right icon
    if self.RightIcon and self.RightIcon ~= Icon.NONE then
        right_icon_offset = 25.0
        local sprite_x = left_aligned() and ((WIDTH - 20.0) / W) or (Draw.safe_zone() - (20.0 / W))
        draw_icon(self.RightIcon, selected, enabled, sprite_x, y)
    end

    -- label (right-justified)
    if self.Label and self.Label ~= '' then
        Draw.set_gfx_align(true)
        BeginTextCommandDisplayText('STRING')
        SetTextFont(font)
        SetTextScale(text_size, text_size)
        SetTextJustification(2)
        AddTextComponentSubstringPlayerName(self.Label)
        if selected or not enabled then
            SetTextColour(text_color, text_color, text_color, 255)
        end
        if left_aligned() then
            SetTextWrap(0.0, (490.0 - right_icon_offset) / W)
            EndTextCommandDisplayText((10.0 + right_icon_offset) / W, text_y)
        else
            SetTextWrap(0.0, Draw.safe_zone() - ((10.0 + right_icon_offset) / W))
            EndTextCommandDisplayText(0.0, text_y)
        end
        Draw.reset_gfx_align()
    end

    -- item text (left-justified)
    Draw.set_gfx_align(true)
    SetTextFont(font)
    SetTextScale(text_size, text_size)
    SetTextJustification(1)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(self.Text or 'N/A')
    if selected or not enabled then
        SetTextColour(text_color, text_color, text_color, 255)
    end
    if left_aligned() then
        SetTextWrap(text_min_x, text_max_x)
        EndTextCommandDisplayText(text_min_x, text_y)
    else
        text_min_x = (text_x_offset / W) + Draw.safe_zone() - ((WIDTH - 10.0) / W)
        text_max_x = Draw.safe_zone() - (10.0 / W)
        SetTextWrap(text_min_x, text_max_x)
        EndTextCommandDisplayText(text_min_x, text_y)
    end
    Draw.reset_gfx_align()
end

-- ---------------------------------------------------------------------------
-- MenuCheckboxItem.Draw
-- ---------------------------------------------------------------------------

function Items.MenuCheckboxItem:Draw(index_offset)
    self.RightIcon = Icon.NONE
    self.Label = nil
    Items.MenuItem.Draw(self, index_offset)

    local menu = self.ParentMenu
    local W, H = Draw.screen_width(), Draw.screen_height()
    local y_offset = menu.MenuItemsYOffset + 1.0 - (ROW_HEIGHT * clamp(menu:Size(), 0, menu.MaxItemsOnScreen))

    local name
    if self.Checked then
        if self.CheckboxStyle == Items.MenuCheckboxItem.Style.Tick then
            name = self:Selected() and 'shop_box_tickb' or 'shop_box_tick'
        else
            name = self:Selected() and 'shop_box_crossb' or 'shop_box_cross'
        end
    else
        name = self:Selected() and 'shop_box_blankb' or 'shop_box_blank'
    end

    local sprite_y = (menu.Position.y + ((self:Index() - index_offset) * ROW_HEIGHT) + 20.0 + y_offset) / H
    local sprite_x = left_aligned() and ((WIDTH - 20.0) / W) or (Draw.safe_zone() - (20.0 / W))
    local color = self.Enabled and 255 or 109

    Draw.set_gfx_align(true)
    DrawSprite('commonmenu', name, sprite_x, sprite_y, 45.0 / W, 45.0 / H, 0.0, color, color, color, 255)
    Draw.reset_gfx_align()
end

-- ---------------------------------------------------------------------------
-- MenuListItem.Draw / MenuDynamicListItem.Draw
-- ---------------------------------------------------------------------------

function Items.MenuListItem:Draw(index_offset)
    if self:ItemsCount() < 1 then
        self.ListItems[#self.ListItems + 1] = 'N/A'
    end
    while self.ListIndex < 0 do
        self.ListIndex = self.ListIndex + self:ItemsCount()
    end
    while self.ListIndex >= self:ItemsCount() do
        self.ListIndex = self.ListIndex - self:ItemsCount()
    end

    if self.HideArrowsWhenNotSelected and not self:Selected() then
        self.Label = self:GetCurrentSelection() or '~r~N/A'
    else
        self.Label = ('~s~← %s ~s~→'):format(self:GetCurrentSelection() or '~r~N/A~s~')
    end

    Items.MenuItem.Draw(self, index_offset)
end

function Items.MenuDynamicListItem:Draw(index_offset)
    self.Label = ('~s~← %s ~s~→'):format(self.CurrentItem or '~r~N/A~s~')
    Items.MenuItem.Draw(self, index_offset)
end

-- ---------------------------------------------------------------------------
-- MenuSliderItem.Draw
-- ---------------------------------------------------------------------------

local function map_range(value, in_min, in_max, out_min, out_max)
    return (value - in_min) / (in_max - in_min) * (out_max - out_min) + out_min
end

function Items.MenuSliderItem:Draw(index_offset)
    Items.MenuItem.Draw(self, index_offset)

    if self.Position > self.Max or self.Position < self.Min then
        self.Position = math.floor((self.Max - self.Min) / 2)
    end

    local menu = self.ParentMenu
    local W, H = Draw.screen_width(), Draw.screen_height()
    local y_offset = menu.MenuItemsYOffset + 1.0 - (ROW_HEIGHT * clamp(menu:Size(), 0, menu.MaxItemsOnScreen))

    local width = 150.0 / W
    local height = 10.0 / H
    local y = (menu.Position.y + ((self:Index() - index_offset) * ROW_HEIGHT) + 20.0 + y_offset) / H
    local x = (menu.Position.x + WIDTH) / W - (width / 2.0) - (8.0 / W)
    if not left_aligned() then
        x = (width / 2.0) - (8.0 / W)
    end

    if self.SliderLeftIcon ~= Icon.NONE and self.SliderRightIcon ~= Icon.NONE then
        x = x - (40.0 / W)
        local sprite = ICON_SPRITES[self.SliderLeftIcon]
        if sprite then
            local r, g, b = icon_colour(sprite, self:Selected(), self.Enabled)
            local name = (self:Selected() and sprite.selected_name) or sprite.name
            Draw.set_gfx_align(left_aligned())
            if left_aligned() then
                DrawSprite(
                    sprite.dict,
                    name,
                    x - (width / 2.0 + (4.0 / W)) - ((sprite.w / W) / 2.0),
                    y,
                    sprite.w / W,
                    sprite.h / H,
                    0.0,
                    r,
                    g,
                    b,
                    255
                )
            else
                DrawSprite(
                    sprite.dict,
                    name,
                    x - (width + (4.0 / W)) - (sprite.w / W) - (20.0 / W),
                    y,
                    sprite.w / W,
                    sprite.h / H,
                    0.0,
                    r,
                    g,
                    b,
                    255
                )
            end
            Draw.reset_gfx_align()
        end
    end

    Draw.set_gfx_align(left_aligned())

    local bg = self.BackgroundColor
    DrawRect(x, y, width, height, bg[1], bg[2], bg[3], bg[4])

    local x_offset =
        map_range(self.Position + 0.0, self.Min + 0.0, self.Max + 0.0, -((width / 4.0) * W), (width / 4.0) * W)
    x_offset = x_offset / W

    local bar = self.BarColor
    if not left_aligned() then
        DrawRect(x - (width / 2.0) + x_offset, y, width / 2.0, height, bar[1], bar[2], bar[3], bar[4])
    else
        DrawRect(x + x_offset, y, width / 2.0, height, bar[1], bar[2], bar[3], bar[4])
    end

    if self.ShowDivider then
        if not left_aligned() then
            DrawRect(x - width + (4.0 / W), y, 4.0 / W, ROW_HEIGHT / H / 2.0, 255, 255, 255, 255)
        else
            DrawRect(x + (2.0 / W), y, 4.0 / W, ROW_HEIGHT / H / 2.0, 255, 255, 255, 255)
        end
    end
    Draw.reset_gfx_align()
end

-- ---------------------------------------------------------------------------
-- Menu.Draw pipeline (Menu.cs private Draw* functions, FiveM branches)
-- ---------------------------------------------------------------------------

local WEAPON_STAT_LABELS = { 'PM_DAMAGE', 'PM_FIRERATE', 'PM_ACCURACY', 'PM_RANGE' }
local VEHICLE_STAT_LABELS = { 'FMMC_VEHST_0', 'FMMC_VEHST_1', 'FMMC_VEHST_2', 'FMMC_VEHST_3' }

function Menu:DrawHeader()
    if not self.MenuTitle or self.MenuTitle == '' then
        return
    end
    local W, H = Draw.screen_width(), Draw.screen_height()

    Draw.set_gfx_align(left_aligned())
    local x = (self.Position.x + (Draw.HEADER_WIDTH / 2.0)) / W
    local y = (self.Position.y + (Draw.HEADER_HEIGHT / 2.0)) / H
    local width = Draw.HEADER_WIDTH / W
    local height = Draw.HEADER_HEIGHT / H

    if self.HeaderTexture and self.HeaderTexture.dict and self.HeaderTexture.name then
        if not HasStreamedTextureDictLoaded(self.HeaderTexture.dict) then
            RequestStreamedTextureDict(self.HeaderTexture.dict, false)
        end
        DrawSprite(self.HeaderTexture.dict, self.HeaderTexture.name, x, y, width, height, 0.0, 255, 255, 255, 255)
    else
        DrawSprite(Draw.TEXTURE_DICT, Draw.HEADER_TEXTURE, x, y, width, height, 0.0, 255, 255, 255, 255)
    end
    Draw.reset_gfx_align()

    -- title
    local font = 1
    local size = (45.0 * 27.0) / H
    Draw.set_gfx_align(true)
    BeginTextCommandDisplayText('STRING')
    SetTextFont(font)
    SetTextColour(255, 255, 255, 255)
    SetTextScale(size, size)
    SetTextJustification(0)
    AddTextComponentSubstringPlayerName(self.MenuTitle)
    if left_aligned() then
        EndTextCommandDisplayText((Draw.HEADER_WIDTH / 2.0) / W, y - (GetTextScaleHeight(size, font) / 2.0))
    else
        EndTextCommandDisplayText(
            Draw.safe_zone() - ((Draw.HEADER_WIDTH / 2.0) / W),
            y - (GetTextScaleHeight(size, font) / 2.0)
        )
    end
    Draw.reset_gfx_align()
    self.MenuItemsYOffset = Draw.HEADER_HEIGHT
end

function Menu:DrawSubtitle()
    local W, H = Draw.screen_width(), Draw.screen_height()
    local bg_height = 38.0

    Draw.set_gfx_align(left_aligned())
    local x = (self.Position.x + (Draw.HEADER_WIDTH / 2.0)) / W
    local y = (self.Position.y + self.MenuItemsYOffset + (bg_height / 2.0)) / H
    DrawRect(x, y, Draw.HEADER_WIDTH / W, bg_height / H, 0, 0, 0, 250)
    Draw.reset_gfx_align()

    local font = 0
    local size = (14.0 * 27.0) / H

    if self.MenuSubtitle and self.MenuSubtitle ~= '' then
        Draw.set_gfx_align(true)
        BeginTextCommandDisplayText('STRING')
        SetTextFont(font)
        SetTextScale(size, size)
        SetTextJustification(1)
        -- keep the freemode blue unless the subtitle carries its own colours
        if self.MenuSubtitle:find('~', 1, true) or not self.MenuTitle or self.MenuTitle == '' then
            AddTextComponentSubstringPlayerName(self.MenuSubtitle:upper())
        else
            AddTextComponentSubstringPlayerName('~HUD_COLOUR_FREEMODE~' .. self.MenuSubtitle:upper())
        end
        if left_aligned() then
            EndTextCommandDisplayText(10.0 / W, y - (GetTextScaleHeight(size, font) / 2.0 + (4.0 / H)))
        else
            EndTextCommandDisplayText(
                Draw.safe_zone() - ((Draw.HEADER_WIDTH - 10.0) / W),
                y - (GetTextScaleHeight(size, font) / 2.0 + (4.0 / H))
            )
        end
        Draw.reset_gfx_align()
    end

    -- counter
    local counter_text = ('%s%d / %d'):format(self.CounterPreText or '', self.CurrentIndex + 1, self:Size())
    if (self.CounterPreText and self.CounterPreText ~= '') or self.MaxItemsOnScreen < self:Size() then
        Draw.set_gfx_align(true)
        BeginTextCommandDisplayText('STRING')
        SetTextFont(font)
        SetTextScale(size, size)
        SetTextJustification(2)
        local has_colour_codes = (self.MenuSubtitle or ''):find('~', 1, true)
            or (self.CounterPreText or ''):find('~', 1, true)
        if has_colour_codes or not self.MenuTitle or self.MenuTitle == '' then
            AddTextComponentSubstringPlayerName(counter_text:upper())
        else
            AddTextComponentSubstringPlayerName('~HUD_COLOUR_FREEMODE~' .. counter_text:upper())
        end
        if left_aligned() then
            SetTextWrap(0.0, 485.0 / W)
            EndTextCommandDisplayText(10.0 / W, y - (GetTextScaleHeight(size, font) / 2.0 + (4.0 / H)))
        else
            SetTextWrap(0.0, Draw.safe_zone() - (10.0 / W))
            EndTextCommandDisplayText(0.0, y - (GetTextScaleHeight(size, font) / 2.0 + (4.0 / H)))
        end
        Draw.reset_gfx_align()
    end

    if
        (self.MenuSubtitle and self.MenuSubtitle ~= '')
        or self.CounterPreText ~= nil
        or self.MaxItemsOnScreen < self:Size()
    then
        self.MenuItemsYOffset = self.MenuItemsYOffset + bg_height - 1.0
    end
end

function Menu:DrawBackgroundGradient()
    if self:Size() < 1 then
        return
    end
    local W, H = Draw.screen_width(), Draw.screen_height()
    Draw.set_gfx_align(left_aligned())
    local bg_height = 38.0 * clamp(self:Size(), 0, self.MaxItemsOnScreen)
    local x = (self.Position.x + (Draw.HEADER_WIDTH / 2.0)) / W
    local y = (self.Position.y + self.MenuItemsYOffset + ((bg_height + 1.0) / 2.0)) / H
    DrawRect(x, y, Draw.HEADER_WIDTH / W, (bg_height + 1.0) / H, 0, 0, 0, 180)
    self.MenuItemsYOffset = self.MenuItemsYOffset + bg_height - 1.0
    Draw.reset_gfx_align()
end

-- Copy of the visible slice, like MenuAPI's VisibleMenuItems property.
function Menu:VisibleMenuItems()
    local items = self:GetMenuItems()
    local visible = {}
    local first = self.ViewIndexOffset + 1
    local last = math.min(self.ViewIndexOffset + self.MaxItemsOnScreen, #items)
    for i = first, last do
        visible[#visible + 1] = items[i]
    end
    return visible
end

function Menu:DrawActiveMenuItems()
    if self:Size() < 1 then
        return
    end
    for _, item in ipairs(self:VisibleMenuItems()) do
        item:Draw(self.ViewIndexOffset)
    end
end

function Menu:DrawUpDownOverflowIndicators()
    if self:Size() < 1 or self:Size() <= self.MaxItemsOnScreen then
        return 0.0
    end
    local W, H = Draw.screen_width(), Draw.screen_height()
    local width = WIDTH / W
    local height = 60.0 / W -- upstream divides by ScreenWidth here (quirk preserved)
    local x = (self.Position.x + (WIDTH / 2.0)) / W
    local y = (self.MenuItemsYOffset / H) + (height / 2.0) + (6.0 / H)

    Draw.set_gfx_align(left_aligned())
    DrawRect(x, y, width, height, 0, 0, 0, 180)
    Draw.reset_gfx_align()

    Draw.set_gfx_align(true)
    local x_min = 0.0
    local x_max = WIDTH / W
    local x_center = 250.0 / W
    if not left_aligned() then
        x_min = Draw.safe_zone() - ((WIDTH - 10.0) / W)
        x_max = Draw.safe_zone() - (10.0 / W)
        x_center = Draw.safe_zone() - (250.0 / W)
    end
    local y_top = y - (20.0 / H)
    local y_bottom = y - (10.0 / H)

    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName('↑')
    SetTextFont(0)
    SetTextScale(1.0, (14.0 * 27.0) / H)
    SetTextJustification(0)
    SetTextWrap(x_min, x_max)
    EndTextCommandDisplayText(x_center, y_top)

    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName('↓')
    SetTextFont(0)
    SetTextScale(1.0, (14.0 * 27.0) / H)
    SetTextJustification(0)
    SetTextWrap(x_min, x_max)
    EndTextCommandDisplayText(x_center, y_bottom)

    Draw.reset_gfx_align()
    return height
end

function Menu:DrawDescription(description_y_offset)
    if self:Size() < 1 then
        return description_y_offset
    end
    local current = self:GetCurrentMenuItem()
    local W, H = Draw.screen_width(), Draw.screen_height()

    if current and current.Description and current.Description ~= '' then
        local font = 0
        local text_size = (14.0 * 27.0) / H
        local text_min_x = 10.0 / W
        local text_max_x = (WIDTH - 10.0) / W
        local text_y = (self.MenuItemsYOffset / H) + (16.0 / H) + description_y_offset

        if not left_aligned() then
            text_min_x = Draw.safe_zone() - ((WIDTH - 10.0) / W)
            text_max_x = Draw.safe_zone() - (10.0 / W)
        end

        Draw.set_gfx_align(true)
        BeginTextCommandDisplayText('CELL_EMAIL_BCON')
        SetTextFont(font)
        SetTextScale(text_size, text_size)
        SetTextJustification(1)
        Draw.add_long_string(current.Description)
        SetTextWrap(text_min_x, text_max_x)
        EndTextCommandDisplayText(text_min_x, text_y)
        Draw.reset_gfx_align()

        local text_height = GetTextScaleHeight(text_size, font)

        Draw.set_gfx_align(true)
        BeginTextCommandLineCount('CELL_EMAIL_BCON')
        SetTextScale(text_size, text_size)
        SetTextJustification(1)
        SetTextFont(font)
        Draw.add_long_string(current.Description)
        SetTextWrap(text_min_x, text_max_x)
        local line_count = EndTextCommandLineCount(text_min_x, text_y)
        Draw.reset_gfx_align()

        -- description background
        local desc_width = WIDTH / W
        local desc_height = (text_height + 0.005) * line_count + (8.0 / H) + (2.5 / H)
        local desc_x = (self.Position.x + (WIDTH / 2.0)) / W
        local desc_y = text_y - (6.0 / H) + (desc_height / 2.0)

        Draw.set_gfx_align(left_aligned())
        DrawRect(desc_x, desc_y - (desc_height / 2.0) + (2.0 / H), desc_width, 4.0 / H, 0, 0, 0, 200)
        DrawRect(desc_x, desc_y, desc_width, desc_height, 0, 0, 0, 180)
        Draw.reset_gfx_align()

        return description_y_offset + desc_y + (desc_height / 2.0) - (4.0 / H)
    end
    return description_y_offset + (self.MenuItemsYOffset / H) + (2.0 / H) + description_y_offset
end

function Menu:DrawWeaponOrVehicleStatsPanel(description_y_offset)
    if self:Size() < 1 then
        return
    end
    local current = self:GetCurrentMenuItem()
    if not current then
        return
    end
    if getmetatable(current) == Items.MenuListItem and (current.ShowColorPanel or current.ShowOpacityPanel) then
        return
    end
    if not self.ShowWeaponStatsPanel and not self.ShowVehicleStatsPanel then
        return
    end

    local W, H = Draw.screen_width(), Draw.screen_height()
    local text_size = (14.0 * 27.0) / H
    local width = WIDTH / W
    local height = 140.0 / H
    local x = (WIDTH / 2.0) / W
    local y = description_y_offset + (height / 2.0) + (8.0 / H)
    if self:Size() > self.MaxItemsOnScreen then
        y = y - (30.0 / H)
    end

    Draw.set_gfx_align(left_aligned())
    DrawRect(x, y, width, height, 0, 0, 0, 180)
    Draw.reset_gfx_align()

    local bg_bar_width = (WIDTH / 2.0) / W
    local bg_bar_x = x + (bg_bar_width / 2.0) - (10.0 / W)
    if not left_aligned() then
        bg_bar_x = x - (bg_bar_width / 2.0) - (10.0 / W)
    end
    local bar_y = y - (height / 2.0) + (25.0 / H)
    local bg_bar_height = 10.0 / H

    local stats = self.ShowWeaponStatsPanel and self.WeaponStats or self.VehicleStats
    local component_stats = self.ShowWeaponStatsPanel and self.WeaponComponentStats or self.VehicleUpgradeStats

    for i = 1, 4 do
        local r, g, b = 93, 182, 229
        local bar_width = bg_bar_width * stats[i]
        local component_bar_width = bg_bar_width * component_stats[i]
        if component_bar_width < bar_width then
            local diff = bar_width - component_bar_width
            bar_width = bar_width - diff
            component_bar_width = component_bar_width + diff
            r, g, b = 224, 50, 50
        end
        local bar_x, component_bar_x
        if left_aligned() then
            bar_x = bg_bar_x - (bg_bar_width / 2.0) + (bar_width / 2.0)
            component_bar_x = bg_bar_x - (bg_bar_width / 2.0) + (component_bar_width / 2.0)
        else
            bar_x = (bar_width * 1.5) - bg_bar_width - (10.0 / W)
            component_bar_x = (component_bar_width * 1.5) - bg_bar_width - (10.0 / W)
        end
        Draw.set_gfx_align(left_aligned())
        DrawRect(bg_bar_x, bar_y, bg_bar_width, bg_bar_height, 100, 100, 100, 180)
        DrawRect(component_bar_x, bar_y, component_bar_width, bg_bar_height, r, g, b, 255)
        DrawRect(bar_x, bar_y, bar_width, bg_bar_height, 255, 255, 255, 255)
        Draw.reset_gfx_align()
        bar_y = bar_y + (30.0 / H)
    end

    -- stat labels
    local labels = self.ShowWeaponStatsPanel and WEAPON_STAT_LABELS or VEHICLE_STAT_LABELS
    local text_x = left_aligned() and (x - (width / 2.0) + (10.0 / W)) or (Draw.safe_zone() - ((WIDTH - 10.0) / W))
    local text_y = y - (height / 2.0) + (10.0 / H)
    for i = 1, 4 do
        Draw.set_gfx_align(true)
        BeginTextCommandDisplayText(labels[i])
        SetTextJustification(1)
        SetTextScale(text_size, text_size)
        EndTextCommandDisplayText(text_x, text_y)
        Draw.reset_gfx_align()
        text_y = text_y + (30.0 / H)
    end
end

function Menu:DrawColorAndOpacityPanel(description_y_offset)
    if self:Size() < 1 then
        return
    end
    local current = self:GetCurrentMenuItem()
    if not current or getmetatable(current) ~= Items.MenuListItem then
        return
    end
    local W, H = Draw.screen_width(), Draw.screen_height()

    if current.ShowOpacityPanel then
        self._opacity_panel = self._opacity_panel or RequestScaleformMovie('COLOUR_SWITCHER_01')
        BeginScaleformMovieMethod(self._opacity_panel, 'SET_TITLE')
        PushScaleformMovieMethodParameterString('Opacity')
        PushScaleformMovieMethodParameterString('')
        ScaleformMovieMethodAddParamInt(current.ListIndex * 10)
        EndScaleformMovieMethod()

        local width = WIDTH / W
        local height = ((700.0 / 500.0) * WIDTH) / H
        local x = (WIDTH / 2.0) / W
        local y = description_y_offset + (height / 2.0) + (4.0 / H)
        if self:Size() > self.MaxItemsOnScreen then
            y = y - (30.0 / H)
        end
        Draw.set_gfx_align(left_aligned())
        DrawScaleformMovie(self._opacity_panel, x, y, width, height, 255, 255, 255, 255, 0)
        Draw.reset_gfx_align()
    elseif current.ShowColorPanel then
        self._color_panel = self._color_panel or RequestScaleformMovie('COLOUR_SWITCHER_02')
        BeginScaleformMovieMethod(self._color_panel, 'SET_TITLE')
        PushScaleformMovieMethodParameterString('Opacity')
        BeginTextCommandScaleformString('FACE_COLOUR')
        AddTextComponentInteger(current.ListIndex + 1)
        AddTextComponentInteger(current:ItemsCount())
        EndTextCommandScaleformString()
        ScaleformMovieMethodAddParamInt(0)
        ScaleformMovieMethodAddParamBool(true)
        EndScaleformMovieMethod()

        BeginScaleformMovieMethod(self._color_panel, 'SET_DATA_SLOT_EMPTY')
        EndScaleformMovieMethod()

        for i = 0, 63 do
            local r, g, b
            if current.ColorPanelColorType == 'Makeup' then
                r, g, b = GetMakeupRgbColor(i)
            else
                r, g, b = GetHairRgbColor(i)
            end
            BeginScaleformMovieMethod(self._color_panel, 'SET_DATA_SLOT')
            ScaleformMovieMethodAddParamInt(i)
            ScaleformMovieMethodAddParamInt(r)
            ScaleformMovieMethodAddParamInt(g)
            ScaleformMovieMethodAddParamInt(b)
            EndScaleformMovieMethod()
        end

        BeginScaleformMovieMethod(self._color_panel, 'DISPLAY_VIEW')
        EndScaleformMovieMethod()

        BeginScaleformMovieMethod(self._color_panel, 'SET_HIGHLIGHT')
        ScaleformMovieMethodAddParamInt(current.ListIndex)
        EndScaleformMovieMethod()

        BeginScaleformMovieMethod(self._color_panel, 'SHOW_OPACITY')
        ScaleformMovieMethodAddParamBool(false)
        ScaleformMovieMethodAddParamBool(true)
        EndScaleformMovieMethod()

        local width = WIDTH / W
        local height = ((700.0 / 500.0) * WIDTH) / H
        local x = (WIDTH / 2.0) / W
        local y = description_y_offset + (height / 2.0) + (4.0 / H)
        if self:Size() > self.MaxItemsOnScreen then
            y = y - (30.0 / H)
        end
        Draw.set_gfx_align(left_aligned())
        DrawScaleformMovie(self._color_panel, x, y, width, height, 255, 255, 255, 255, 0)
        Draw.reset_gfx_align()
    end
end

-- Menu.cs internal Draw(): the per-frame pipeline.
function Menu:Draw()
    if not IsScreenFadedIn() or IsPauseMenuActive() or IsEntityDead(PlayerPedId()) or IsPlayerSwitchInProgress() then
        return
    end

    self.MenuItemsYOffset = 0.0
    if Controller.SetDrawOrder then
        SetScriptGfxDrawOrder(1)
    end

    self:DrawHeader()
    self:DrawSubtitle()
    self:DrawBackgroundGradient()
    self:DrawActiveMenuItems()
    local description_y_offset = self:DrawUpDownOverflowIndicators()
    description_y_offset = self:DrawDescription(description_y_offset)
    self:DrawWeaponOrVehicleStatsPanel(description_y_offset)
    self:DrawColorAndOpacityPanel(description_y_offset)
end

return true
