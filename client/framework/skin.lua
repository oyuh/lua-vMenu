-- Ports of vMenu.Enhanced.MenuFramework/MenuSkin.cs and HeaderStyle.cs: the
-- server-wide menu theme (vMenu.Enhanced.MenuAppearance.Skin), plugin-made
-- custom themes, a per-player override, and the title alignment and glare.

local Log = require('shared.log')
local Config = require('shared.config')
local Controller = require('menu.controller')
local Nui = require('menu.nui')

local Skin = {}

local SKIN_SETTING = 'vMenu.Enhanced.MenuAppearance.Skin'
local ALIGNMENT_SETTING = 'vMenu.Enhanced.MenuAppearance.TitleAlignment'
local GLARE_SETTING = 'vMenu.Enhanced.MenuAppearance.HeaderGlare'
local MAX_ID_LENGTH = 40
local MAX_PATH_LENGTH = 400
local CHALET_COMPRIME_COLOGNE = 4

-- Paths resolve against the NUI page (ui/index.html), so these are ui/themes
-- and ui/menuapi-banners on disk. The first alias is the id.
local SKINS = {
    {
        aliases = { 'default', 'vmenu' },
        name = 'Default',
        theme = 'Default',
        path = 'themes/default.css',
        banner = 'default',
    },
    {
        aliases = { 'gold', 'vmenugold', 'vmenu-gold' },
        name = 'vMenu Gold',
        theme = 'Gold',
        path = 'themes/gold.css',
        banner = 'gold',
    },
    {
        aliases = { 'green', 'vmenugreen', 'vmenu-green' },
        name = 'vMenu Green',
        theme = 'Green',
        path = 'themes/green.css',
        banner = 'green',
    },
    {
        aliases = { 'red', 'vmenured', 'vmenu-red' },
        name = 'vMenu Red',
        theme = 'Red',
        path = 'themes/red.css',
        banner = 'red',
    },
    { aliases = { 'gta', 'none', 'vanilla' }, name = 'GTA V' },
    {
        aliases = { 'dark', 'vmenudark', 'vmenu-dark', 'vmenu dark' },
        name = 'Dark',
        theme = 'Dark',
        path = 'themes/dark.css',
        banner = 'dark',
    },
    { aliases = { 'cartoon' }, name = 'Cartoon', theme = 'Cartoon', path = 'themes/cartoon.css', banner = 'cartoon' },
}

local customs = {}
local override
local banner
local reported = {}
local listeners = {}

local function report_once(key, message)
    if reported[key] ~= message then
        reported[key] = message
        Log.warning('[Menu] ' .. message)
    end
end

local function index_of_skin(value)
    value = (value or ''):lower()
    for index, skin in ipairs(SKINS) do
        for _, alias in ipairs(skin.aliases) do
            if alias == value then
                return index
            end
        end
    end
    return nil
end

local function find_custom(value)
    value = (value or ''):lower()
    for _, custom in ipairs(customs) do
        if custom.id:lower() == value then
            return custom
        end
    end
    return nil
end

local function skin_at(index)
    local skin = SKINS[index]
    return { id = skin.aliases[1], theme = skin.theme, banner = skin.banner }
end

local function find(value)
    local index = index_of_skin(value)
    if index then
        return skin_at(index)
    end
    local custom = find_custom(value)
    return custom and { id = custom.id, theme = custom.id, banner = custom.banner } or nil
end

local function configured()
    local raw = Config.value(SKIN_SETTING)
    local skin = find(raw:match('^%s*(.-)%s*$'))
    if skin then
        return skin
    end
    report_once(
        'skin',
        ("%s is set to '%s', which is not a skin vMenu knows about. Using '%s'. "):format(
            SKIN_SETTING,
            raw,
            SKINS[1].aliases[1]
        ) .. 'A theme another resource provides only counts once that resource has registered it.'
    )
    return skin_at(1)
end

local function current()
    if override then
        local skin = find(override)
        if skin then
            return skin
        end
        override = nil
    end
    return configured()
end

local function apply()
    local skin = current()
    Nui.set_theme(skin.theme)
    banner = skin.banner
    require('client.framework.registry').apply_banner(banner)
    for _, listener in ipairs(listeners) do
        local ok, err = pcall(listener)
        if not ok then
            Log.error('[Menu] A skin listener threw: ' .. tostring(err))
        end
    end
end

-- Read by every new framework menu, so menus built later get the banner too.
function Skin.banner()
    return banner
end

function Skin.current_id()
    return current().id
end

function Skin.configured_id()
    return configured().id
end

function Skin.is_overridden()
    return override ~= nil
end

function Skin.on_changed(listener)
    listeners[#listeners + 1] = listener
end

-- Every theme a player could pick: { id, name, resource } with resource nil
-- for vMenu's own.
function Skin.choices()
    local choices = {}
    for _, skin in ipairs(SKINS) do
        choices[#choices + 1] = { id = skin.aliases[1], name = skin.name }
    end
    for _, custom in ipairs(customs) do
        choices[#choices + 1] = { id = custom.id, name = custom.name, resource = custom.resource }
    end
    return choices
end

-- A path inside the resource, or a full https://cfx-nui-<resource>/ or nui://
-- url. nil for anything else, including path traversal.
local function resource_url(resource, path)
    if #path == 0 or #path > MAX_PATH_LENGTH or path:find('..', 1, true) then
        return nil
    end
    local lower = path:lower()
    if lower:sub(1, 16) == 'https://cfx-nui-' or lower:sub(1, 6) == 'nui://' then
        return path
    end
    if path:find('://', 1, true) or path:sub(1, 1) == '/' or path:sub(1, 1) == '\\' then
        return nil
    end
    return ('https://cfx-nui-%s/%s'):format(resource, path)
end

local function is_image_path(value)
    local lower = value:lower()
    for _, extension in ipairs({ '.png', '.jpg', '.jpeg', '.webp' }) do
        if lower:sub(-#extension) == extension then
            return true
        end
    end
    return false
end

local function banner_for(resource, value)
    value = (value or ''):match('^%s*(.-)%s*$')
    if value == '' then
        return SKINS[1].banner
    end
    local index = index_of_skin(value)
    if index then
        return SKINS[index].banner
    end
    if is_image_path(value) then
        local url = resource_url(resource, value)
        if url then
            return url
        end
    end
    local warning = "'%s' is not one of vMenu's banners (default, gold, green, red, dark, cartoon, none) "
        .. "and not an image inside your resource, so '%s' is used instead. "
        .. 'An image is a path ending in .png, .jpg or .webp.'
    return SKINS[1].banner, warning:format(value, SKINS[1].aliases[1])
end

-- Registers a plugin's theme. Returns true, or false and the reason, plus a
-- warning when it was accepted with a fallback banner.
function Skin.register_custom(resource, id, name, css, banner_value)
    id = (id or ''):match('^%s*(.-)%s*$')
    if #id == 0 or #id > MAX_ID_LENGTH or not id:match('^[%w%-_%.]+$') then
        local reason = "'%s' is not a usable theme id. Use letters, digits, dashes, underscores and dots, "
            .. 'up to %d characters.'
        return false, reason:format(id, MAX_ID_LENGTH)
    end
    if index_of_skin(id) then
        return false, ("'%s' is one of vMenu's own theme names, pick another id."):format(id)
    end
    local taken = find_custom(id)
    if taken and taken.resource:lower() ~= resource:lower() then
        return false, ("'%s' is already registered by resource '%s'."):format(id, taken.resource)
    end
    local url = resource_url(resource, (css or ''):match('^%s*(.-)%s*$'))
    if not url then
        return false,
            ("'%s' is not a stylesheet vMenu can load for theme '%s'. Use a path inside your own resource, "):format(
                tostring(css),
                id
            ) .. "like 'themes/mytheme.css', or a full https://cfx-nui-<resource>/ url."
    end
    local display = (name or ''):match('^%s*(.-)%s*$')
    Nui.register_theme(id, url)
    local resolved_banner, warning = banner_for(resource, banner_value)
    local entry = { id = id, name = display ~= '' and display or id, resource = resource, banner = resolved_banner }
    if taken then
        for index, custom in ipairs(customs) do
            if custom == taken then
                customs[index] = entry
            end
        end
    else
        customs[#customs + 1] = entry
    end
    return true, nil, warning
end

-- Drops every theme a resource registered. Returns how many went.
function Skin.remove_custom_from(resource)
    local removed = 0
    for index = #customs, 1, -1 do
        local custom = customs[index]
        if custom.resource:lower() == resource:lower() then
            table.remove(customs, index)
            Nui.unregister_theme(custom.id)
            removed = removed + 1
        end
    end
    if removed > 0 then
        apply()
    end
    return removed
end

function Skin.refresh()
    apply()
end

-- A player's own choice over the server's. False for an unknown id.
function Skin.apply_override(id)
    local skin = find(id)
    if not skin then
        return false
    end
    override = skin.id
    apply()
    return true
end

function Skin.clear_override()
    if override == nil then
        return
    end
    override = nil
    apply()
end

-- HeaderStyle ----------------------------------------------------------------------------

local function title_alignment()
    local raw = Config.value(ALIGNMENT_SETTING)
    local value = raw:match('^%s*(.-)%s*$'):lower()
    if value == 'left' then
        return 'Left'
    elseif value == 'center' or value == 'centre' then
        return 'Center'
    elseif value == 'right' then
        return 'Right'
    end
    report_once(
        'alignment',
        ("%s is set to '%s', which is not left, center or right. Using left."):format(ALIGNMENT_SETTING, raw)
    )
    return 'Left'
end

local function apply_header_style()
    Controller.DefaultTitleAlignment = title_alignment()
    Controller.DefaultTitleFont = CHALET_COMPRIME_COLOGNE
    Controller.DefaultShowHeaderGlare = Config.value(GLARE_SETTING)
end

-- Call after Config.init, before the menus are built.
function Skin.init()
    for _, skin in ipairs(SKINS) do
        if skin.theme then
            Nui.register_theme(skin.theme, skin.path)
        end
    end
    Config.watch({ SKIN_SETTING }, apply)
    Config.watch({ ALIGNMENT_SETTING, GLARE_SETTING }, apply_header_style)
    apply_header_style()
    apply()
end

return Skin
