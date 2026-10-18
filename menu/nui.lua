-- Ports of MenuAPI/nui/MenuNui.cs, NuiJson.cs, NuiTuning.cs and
-- ticks/MenuLayout.cs. Menus are drawn by MenuAPI's page (ui/menuapi), which
-- takes one JSON snapshot of the open menu. A snapshot is only rebuilt after
-- something marked it dirty, and only sent when it differs from the last one.
-- The JSON matches the C# writer, so the page sees the same messages.

local Icons = require('menu.icons')
local Sprites = require('menu.sprites')

local Nui = {}

local HIDE_MESSAGE = '{"type":"menuapi","visible":false}'
local ROTATION_TOLERANCE = 0.5
local FREEMODE_HUD_COLOUR = 116
local PAUSE_BACKGROUND_HUD_COLOUR = 117
local WHITE_HUD_COLOUR = 1
local PALETTE_SIZE = 64
local CHECKBOX_SPRITE_SIZE = 45
local MENU_WIDTH = 500

Nui.DEFAULT_TEXT_SIZE = 21
Nui.DEFAULT_TEXT_BRIGHTNESS = 225

local sent
local dirty = true
local pending_textures = {}
local heading = nil
local freemode, panel_background, panel_accent
local palette

local text_size = Nui.DEFAULT_TEXT_SIZE
local text_brightness = Nui.DEFAULT_TEXT_BRIGHTNESS
local text_weight = 'default' -- 'default', 'geometric' or 'supersampled'
local themes = {} -- lowercased name -> { name, path }
local theme

local screen_width, safe_zone

function Nui.invalidate()
    dirty = true
end

-- JSON -------------------------------------------------------------------------------

local ESCAPES = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }

local function string_json(value)
    return '"'
        .. value:gsub('[%c"\\]', function(char)
            return ESCAPES[char] or ('\\u%04x'):format(char:byte())
        end)
        .. '"'
end

-- C#'s float.ToString("0.####"): up to four decimals, no trailing zeros.
local function number_json(value)
    if math.type(value) == 'integer' then
        return tostring(value)
    end
    local text = ('%.4f'):format(value):gsub('0+$', ''):gsub('%.$', '')
    if text == '-0' then
        return '0'
    end
    return text
end

local function value_json(value)
    local kind = type(value)
    if kind == 'nil' then
        return 'null'
    elseif kind == 'boolean' then
        return value and 'true' or 'false'
    elseif kind == 'number' then
        return number_json(value)
    elseif kind == 'string' then
        return string_json(value)
    end
    error('cannot write a ' .. kind .. ' into a NUI message')
end

-- Writes an object from an ordered list of { key, value } pairs. A value that
-- is a function is called with the parts list to write a nested value.
local function object_json(parts, fields)
    parts[#parts + 1] = '{'
    for index, field in ipairs(fields) do
        if index > 1 then
            parts[#parts + 1] = ','
        end
        parts[#parts + 1] = string_json(field[1])
        parts[#parts + 1] = ':'
        local value = field[2]
        if type(value) == 'function' then
            value(parts)
        else
            parts[#parts + 1] = value_json(value)
        end
    end
    parts[#parts + 1] = '}'
end

local function array_json(parts, list, write_entry)
    parts[#parts + 1] = '['
    for index, entry in ipairs(list) do
        if index > 1 then
            parts[#parts + 1] = ','
        end
        write_entry(parts, entry)
    end
    parts[#parts + 1] = ']'
end

-- The raw native: the JSON is already built, so no second encode.
local function send(message)
    SendNuiMessage(message)
end

-- Layout ---------------------------------------------------------------------------
-- Aspect ratio and safe zone only change in the pause menu, so a slow tick
-- re-reads them while a menu is open.

function Nui.refresh_layout()
    local width = 1080.0 * GetScreenAspectRatio(false)
    local zone = GetSafeZoneSize()
    if width ~= screen_width or zone ~= safe_zone then
        screen_width, safe_zone = width, zone
        dirty = true
    end
end

function Nui.ensure_layout()
    if not screen_width then
        Nui.refresh_layout()
    end
end

-- Textures -------------------------------------------------------------------------

local function texture_ready(dict)
    if Sprites.request(dict) then
        return true
    end
    pending_textures[dict] = true
    return false
end

-- The page keeps its own copy of every preloaded sprite. Anything else, such
-- as a header texture a resource set itself, still has to stream in.
local function sprite_ready(dict, name)
    return Sprites.is_cached(dict, name) or texture_ready(dict)
end

function Nui.request_pending_textures()
    for dict in pairs(pending_textures) do
        if Sprites.request(dict) then
            pending_textures[dict] = nil
        end
    end
end

-- Colours --------------------------------------------------------------------------

local function freemode_colour()
    if not freemode then
        local r, g, b = GetHudColour(FREEMODE_HUD_COLOUR)
        freemode = ('rgb(%d %d %d)'):format(r, g, b)
    end
    return freemode
end

local function background_colour()
    if not panel_background then
        local r, g, b, a = GetHudColour(PAUSE_BACKGROUND_HUD_COLOUR)
        local alpha = ('%.3f'):format(a / 255):gsub('0+$', ''):gsub('%.$', '')
        panel_background = ('rgb(%d %d %d / %s)'):format(r, g, b, alpha)
    end
    return panel_background
end

-- Comma separated: the page uses it as rgba(var(--accent), 0.3).
local function accent_colour()
    if not panel_accent then
        local r, g, b = GetHudColour(WHITE_HUD_COLOUR)
        panel_accent = ('%d, %d, %d'):format(r, g, b)
    end
    return panel_accent
end

local function hex(colour)
    return ('#%02x%02x%02x'):format(colour[1], colour[2], colour[3])
end

-- Snapshot -------------------------------------------------------------------------

local function icon_json(item, icon, selected)
    return function(parts)
        if icon == nil or icon == 'NONE' then
            parts[#parts + 1] = 'null'
            return
        end
        local dict = Icons.dictionary(icon)
        local name = Icons.sprite(icon, selected)
        if not sprite_ready(dict, name) then
            parts[#parts + 1] = 'null'
            return
        end
        local r, g, b = Icons.colour(icon, selected, item.Enabled)
        object_json(parts, {
            { 'dict', dict },
            { 'name', name },
            { 'size', Icons.size(icon) },
            { 'r', r },
            { 'g', g },
            { 'b', b },
        })
    end
end

local function row_json(menu, item, position)
    item:PrepareForDisplay()
    local selected = menu.CurrentIndex == menu.ViewIndexOffset + position
    local kind = item:Kind()
    local page_kind = (kind == 'checkbox' or kind == 'slider' or kind == 'separator') and kind or 'item'
    local fields = {
        { 'kind', page_kind },
        { 'text', item.Text },
        { 'label', item.Label },
        { 'enabled', item.Enabled },
        { 'selected', selected },
        { 'leftIcon', icon_json(item, item.LeftIcon, selected) },
        { 'rightIcon', icon_json(item, item.RightIcon, selected) },
    }
    if kind == 'checkbox' then
        local box = item:GetSpriteName(selected)
        if sprite_ready(Sprites.TEXTURE_DICT, box) then
            fields[#fields + 1] = {
                'checkbox',
                function(parts)
                    object_json(parts, {
                        { 'dict', Sprites.TEXTURE_DICT },
                        { 'name', box },
                        { 'size', CHECKBOX_SPRITE_SIZE },
                        { 'shade', item.Enabled and 255 or 109 },
                    })
                end,
            }
        end
    elseif kind == 'slider' then
        fields[#fields + 1] = {
            'slider',
            function(parts)
                object_json(parts, {
                    { 'min', item.Min },
                    { 'max', item.Max },
                    { 'position', item.Position },
                    { 'divider', item.ShowDivider },
                    { 'background', hex(item.BackgroundColor) },
                    { 'bar', hex(item.BarColor) },
                    { 'sliderLeftIcon', icon_json(item, item.SliderLeftIcon, selected) },
                })
            end,
        }
    elseif kind == 'separator' then
        fields[#fields + 1] = { 'arrows', item.ShowArrows }
    end
    return fields
end

local function colour_name(position, count)
    local template = GetLabelText('FACE_COLOUR')
    if template == nil or template == '' or template == 'NULL' then
        return position .. ' / ' .. count
    end
    local function substitute(text, value)
        local at = text:find('~1~', 1, true)
        return at and (text:sub(1, at - 1) .. value .. text:sub(at + 3)) or text
    end
    return substitute(substitute(template, position), count)
end

local function send_palette(kind)
    if palette == kind then
        return
    end
    palette = kind
    local colours = {}
    for index = 0, PALETTE_SIZE - 1 do
        local r, g, b
        if kind == 'Hair' then
            r, g, b = GetHairRgbColor(index)
        else
            r, g, b = GetMakeupRgbColor(index)
        end
        colours[#colours + 1] = { r, g, b }
    end
    local parts = {}
    object_json(parts, {
        { 'type', 'menuapi:palette' },
        {
            'colours',
            function(out)
                array_json(out, colours, function(inner, rgb)
                    inner[#inner + 1] = ('[%d,%d,%d]'):format(rgb[1], rgb[2], rgb[3])
                end)
            end,
        },
    })
    send(table.concat(parts))
end

local function panel_field(menu)
    local item = menu:GetCurrentMenuItem()
    if not item or item:Kind() ~= 'list' or (not item.ShowColorPanel and not item.ShowOpacityPanel) then
        return { 'panel', nil }
    end
    if item.ShowColorPanel then
        send_palette(item.ColorPanelColorType)
    end
    return {
        'panel',
        function(parts)
            object_json(parts, {
                { 'colours', item.ShowColorPanel },
                { 'index', item.ListIndex },
                { 'title', 'Opacity' },
                { 'opacity', item.ShowOpacityPanel and item:ResolvedOpacityPercent() or nil },
                { 'name', item.ShowColorPanel and colour_name(item.ListIndex + 1, item:ItemsCount()) or nil },
            })
        end,
    }
end

local function stats_field(menu)
    local item = menu:GetCurrentMenuItem()
    local panel = item and item:Kind() == 'list' and (item.ShowColorPanel or item.ShowOpacityPanel)
    if panel or (not menu.ShowWeaponStatsPanel and not menu.ShowVehicleStatsPanel) then
        return { 'stats', nil }
    end
    local weapon = menu.ShowWeaponStatsPanel
    local values = weapon and menu.WeaponStats or menu.VehicleStats
    local upgrades = weapon and menu.WeaponComponentStats or menu.VehicleUpgradeStats
    return {
        'stats',
        function(parts)
            array_json(parts, { 1, 2, 3, 4 }, function(out, index)
                object_json(out, {
                    { 'label', GetLabelText(menu:StatLabelKey(index)) },
                    { 'value', values[index] },
                    { 'upgrade', upgrades[index] },
                })
            end)
        end,
    }
end

local function header_field(menu)
    if menu.MenuTitle == nil or menu.MenuTitle == '' then
        return { 'header', nil }
    end
    local custom = menu.HeaderTexture
    local use_custom = custom and custom[1] and custom[1] ~= '' and custom[2] and custom[2] ~= ''
    local dict = use_custom and custom[1] or Sprites.TEXTURE_DICT
    local name = use_custom and custom[2] or Sprites.HEADER_TEXTURE
    return {
        'header',
        function(parts)
            local fields = {
                { 'title', menu.MenuTitle },
                { 'font', menu:ResolvedTitleFont() },
                { 'titleAlign', menu:ResolvedTitleAlignment() },
                { 'glare', menu:ResolvedShowHeaderGlare() },
            }
            if menu.HeaderImage and menu.HeaderImage ~= '' then
                fields[#fields + 1] = { 'image', menu.HeaderImage }
            end
            -- Sent even when not streamed in: the page may have a file replacing it.
            fields[#fields + 1] = {
                'texture',
                function(out)
                    object_json(out, { { 'dict', dict }, { 'name', name }, { 'ready', sprite_ready(dict, name) } })
                end,
            }
            object_json(parts, fields)
        end,
    }
end

local function subtitle_field(menu)
    local counter = nil
    local pre = menu.CounterPreText
    if (pre and pre ~= '') or menu.MaxItemsOnScreen < menu:Size() then
        counter = (pre or '') .. (menu.CurrentIndex + 1) .. ' / ' .. menu:Size()
    end
    local subtitle = menu.MenuSubtitle
    local freemode_style = not (subtitle or ''):find('~', 1, true)
        and not (pre or ''):find('~', 1, true)
        and menu.MenuTitle ~= nil
        and menu.MenuTitle ~= ''
    return {
        'subtitle',
        function(parts)
            object_json(parts, {
                { 'text', subtitle },
                { 'counter', counter },
                { 'colour', freemode_colour() },
                { 'freemode', freemode_style },
            })
        end,
    }
end

local function build(menu)
    pending_textures = {}
    local inset = (1.0 - safe_zone) / 2.0
    local x = menu:LeftAligned() and inset or (1.0 - inset - (MENU_WIDTH / screen_width))
    local theme_url = theme and themes[theme:lower()] and themes[theme:lower()].path or nil

    local fields = {
        { 'type', 'menuapi' },
        { 'visible', true },
        { 'align', menu:LeftAligned() and 'left' or 'right' },
        {
            'origin',
            function(parts)
                object_json(parts, { { 'x', x }, { 'y', inset } })
            end,
        },
        { 'panelBackground', background_colour() },
        { 'panelAccent', accent_colour() },
    }
    if theme_url then
        fields[#fields + 1] = { 'theme', theme_url }
    end
    fields[#fields + 1] = {
        'text',
        function(parts)
            object_json(parts, { { 'size', text_size }, { 'brightness', text_brightness }, { 'weight', text_weight } })
        end,
    }
    fields[#fields + 1] = header_field(menu)
    fields[#fields + 1] = subtitle_field(menu)
    fields[#fields + 1] = {
        'rows',
        function(parts)
            local visible = menu:VisibleMenuItems()
            parts[#parts + 1] = '['
            for position, item in ipairs(visible) do
                if position > 1 then
                    parts[#parts + 1] = ','
                end
                object_json(parts, row_json(menu, item, position - 1))
            end
            parts[#parts + 1] = ']'
        end,
    }
    fields[#fields + 1] = { 'overflow', menu:Size() > menu.MaxItemsOnScreen }
    local current = menu:GetCurrentMenuItem()
    fields[#fields + 1] = { 'description', current and current.Description or nil }
    fields[#fields + 1] = panel_field(menu)
    fields[#fields + 1] = stats_field(menu)

    local parts = {}
    object_json(parts, fields)
    return table.concat(parts)
end

function Nui.send_snapshot(menu)
    dirty = false
    Nui.ensure_layout()
    local snapshot = build(menu)
    if snapshot == sent then
        return
    end
    sent = snapshot
    send(snapshot)
end

local function send_heading()
    local rotation = GetFinalRenderedCamRot(2)
    local degrees = rotation.z % 360.0
    if heading and math.abs(heading - degrees) <= ROTATION_TOLERANCE then
        return
    end
    heading = degrees
    local parts = {}
    object_json(parts, { { 'type', 'menuapi:glare' }, { 'heading', degrees } })
    send(table.concat(parts))
end

function Nui.send_changes(menu)
    if dirty then
        Nui.send_snapshot(menu)
    end
    if menu:ResolvedShowHeaderGlare() then
        send_heading()
    end
end

function Nui.hide()
    if sent == HIDE_MESSAGE then
        return
    end
    sent = HIDE_MESSAGE
    dirty = true
    heading = nil
    palette = nil
    pending_textures = {}
    send(HIDE_MESSAGE)
end

-- Sprite preload message, see menu/sprites.lua.
function Nui.send_preload(round, sprites)
    local parts = {}
    object_json(parts, {
        { 'type', 'menuapi:preload' },
        { 'round', round },
        {
            'sprites',
            function(out)
                array_json(out, sprites, function(inner, sprite)
                    object_json(inner, { { 'dict', sprite.dict }, { 'name', sprite.name } })
                end)
            end,
        },
    })
    send(table.concat(parts))
end

-- Tuning (NuiTuning.cs) ----------------------------------------------------------------

function Nui.set_text_size(size)
    text_size = math.max(8, math.min(48, size))
    dirty = true
end

function Nui.set_text_brightness(brightness)
    text_brightness = math.max(0, math.min(255, math.floor(brightness)))
    dirty = true
end

-- 'default', 'geometric' or 'supersampled'.
function Nui.set_text_weight(weight)
    assert(weight == 'default' or weight == 'geometric' or weight == 'supersampled', 'unknown text weight')
    text_weight = weight
    dirty = true
end

-- Registers a stylesheet, relative to the NUI page, under a name.
function Nui.register_theme(name, path)
    assert(type(name) == 'string' and not name:match('^%s*$'), 'A theme name cannot be empty.')
    assert(
        type(path) == 'string' and not path:match('^%s*$'),
        ("The path for theme '%s' cannot be empty."):format(name)
    )
    assert(
        not path:match('^%s*[jJ][aA][vV][aA][sS][cC][rR][iI][pP][tT]:'),
        ("The path for theme '%s' must point at a stylesheet."):format(name)
    )
    themes[name:lower()] = { name = name, path = path }
    if theme and theme:lower() == name:lower() then
        dirty = true
    end
end

function Nui.unregister_theme(name)
    if not name or not themes[name:lower()] then
        return false
    end
    themes[name:lower()] = nil
    if theme and theme:lower() == name:lower() then
        theme = nil
    end
    dirty = true
    return true
end

-- Applies a registered theme, or nil for the default look.
function Nui.set_theme(name)
    if name == nil then
        if theme ~= nil then
            theme = nil
            dirty = true
        end
        return
    end
    assert(themes[name:lower()], ("No theme named '%s' is registered. Call register_theme first."):format(name))
    if theme and theme:lower() == name:lower() then
        return
    end
    theme = name
    dirty = true
end

function Nui.theme()
    return theme
end

function Nui.themes()
    local names = {}
    for _, entry in pairs(themes) do
        names[#names + 1] = entry.name
    end
    table.sort(names)
    return names
end

function Nui.reset_tuning()
    text_size = Nui.DEFAULT_TEXT_SIZE
    text_brightness = Nui.DEFAULT_TEXT_BRIGHTNESS
    text_weight = 'default'
    theme = nil
    dirty = true
end

return Nui
