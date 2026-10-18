-- Ports of MenuAPI/TextureDictionaries.cs, nui/SpriteManifest.cs and
-- nui/SpritePreload.cs.
--
-- The page loads game textures from https://nui-img/<dict>/<name>, which only
-- answers while that dictionary is streamed in, and a background image that
-- 404'd is never retried. So at start every dictionary is held loaded, the
-- page copies every sprite into a Blob it keeps, and only then are the
-- dictionaries handed back. From then on the icons are local to the page.

local Log = require('shared.log')
local Icons = require('menu.icons')

local Sprites = {}

Sprites.TEXTURE_DICT = 'commonmenu'
Sprites.HEADER_TEXTURE = 'interaction_bgd'

local CALLBACK_NAME = 'menuapiSprites'
local MAX_ROUNDS = 3
local RETRY_DELAY_MS = 500
local DICTIONARY_WAIT_FRAMES = 600

local CHECKBOX_SPRITES = {
    'shop_box_tick',
    'shop_box_tickb',
    'shop_box_cross',
    'shop_box_crossb',
    'shop_box_blank',
    'shop_box_blankb',
}

local function invalidate()
    -- Required lazily: menu.nui requires this module.
    require('menu.nui').invalidate()
end

-- Texture dictionaries ----------------------------------------------------------
-- HasStreamedTextureDictLoaded hashes the name and searches the streaming
-- module, so a dictionary seen loaded is remembered until it is released.

local loaded = {}

function Sprites.is_loaded(dict)
    if loaded[dict] then
        return true
    end
    if not HasStreamedTextureDictLoaded(dict) then
        return false
    end
    loaded[dict] = true
    invalidate()
    return true
end

function Sprites.request(dict)
    if Sprites.is_loaded(dict) then
        return true
    end
    RequestStreamedTextureDict(dict, false)
    return false
end

function Sprites.request_all(dicts)
    local all_loaded = true
    for _, dict in ipairs(dicts) do
        all_loaded = Sprites.request(dict) and all_loaded
    end
    return all_loaded
end

function Sprites.release_all(dicts)
    for _, dict in ipairs(dicts) do
        if loaded[dict] then
            loaded[dict] = nil
            SetStreamedTextureDictAsNoLongerNeeded(dict)
        end
    end
end

-- Manifest -------------------------------------------------------------------------
-- Built from the icon tables, so a new icon is preloaded without a second list.

local manifest, dictionaries

local function key(dict, name)
    return dict .. '/' .. name
end

function Sprites.manifest()
    if manifest then
        return manifest
    end
    manifest = {}
    local seen = {}
    local function add(dict, name)
        if dict ~= '' and name ~= '' and not seen[key(dict, name)] then
            seen[key(dict, name)] = true
            manifest[#manifest + 1] = { dict = dict, name = name }
        end
    end
    add(Sprites.TEXTURE_DICT, Sprites.HEADER_TEXTURE)
    for index = 2, #Icons.NAMES do
        local icon = Icons.NAMES[index]
        add(Icons.dictionary(icon), Icons.sprite(icon, false))
        add(Icons.dictionary(icon), Icons.sprite(icon, true))
    end
    for _, name in ipairs(CHECKBOX_SPRITES) do
        add(Sprites.TEXTURE_DICT, name)
    end
    return manifest
end

-- Every dictionary the menu can draw from, in first-use order.
function Sprites.dictionaries()
    if dictionaries then
        return dictionaries
    end
    dictionaries = {}
    local seen = {}
    for _, sprite in ipairs(Sprites.manifest()) do
        if not seen[sprite.dict] then
            seen[sprite.dict] = true
            dictionaries[#dictionaries + 1] = sprite.dict
        end
    end
    return dictionaries
end

-- Preload -------------------------------------------------------------------------

local cached = {}
local round = {}
local rounds = 0
local running = false
local registered = false

function Sprites.cached()
    return next(cached) ~= nil
end

function Sprites.is_cached(dict, name)
    return cached[key(dict, name)] == true
end

local function hold_dictionaries()
    local frames = 0
    while not Sprites.request_all(Sprites.dictionaries()) and frames < DICTIONARY_WAIT_FRAMES do
        frames = frames + 1
        Wait(0)
    end
end

local function send(sprites)
    round = sprites
    rounds = rounds + 1
    local Nui = require('menu.nui')
    Nui.send_preload(rounds, sprites)
end

local function missing_set(body)
    local missing = {}
    local text = tostring(body.missing or '')
    for entry in text:gmatch('[^,]+') do
        missing[entry] = true
    end
    return missing
end

local function finish(copied, missing)
    running = false
    if copied then
        local Controller = require('menu.controller')
        if not Controller.IsAnyMenuOpen() then
            Sprites.release_all(Sprites.dictionaries())
        end
        local count = 0
        for _ in pairs(cached) do
            count = count + 1
        end
        Log.info(
            ('[MenuAPI] NUI holds %d of %d menu sprites, the game no longer has to.'):format(count, #Sprites.manifest())
        )
    else
        Log.warning("[MenuAPI] NUI could not copy the menu sprites, they stay on the game's texture dictionaries.")
    end
    local names = {}
    for entry in pairs(missing) do
        names[#names + 1] = entry
    end
    if #names > 0 then
        table.sort(names)
        Log.warning(('[MenuAPI] %d menu sprites never arrived: %s'):format(#names, table.concat(names, ', ')))
    end
    invalidate()
end

local function complete(body)
    if not running then
        return
    end
    local missing = missing_set(body)
    for _, sprite in ipairs(round) do
        if not missing[key(sprite.dict, sprite.name)] then
            cached[key(sprite.dict, sprite.name)] = true
        end
    end
    -- "live" means the page could not copy and reads from the game instead.
    local copied = body.mode ~= 'live'
    if not copied then
        cached = {}
    end
    if copied and next(missing) and rounds < MAX_ROUNDS then
        local again = {}
        for _, sprite in ipairs(round) do
            if missing[key(sprite.dict, sprite.name)] then
                again[#again + 1] = sprite
            end
        end
        CreateThread(function()
            Sprites.release_all(Sprites.dictionaries())
            hold_dictionaries()
            Wait(RETRY_DELAY_MS)
            send(again)
        end)
        return
    end
    finish(copied, missing)
end

local function begin()
    if running then
        return
    end
    running = true
    rounds = 0
    cached = {}
    CreateThread(function()
        hold_dictionaries()
        send(Sprites.manifest())
    end)
end

function Sprites.init()
    if registered then
        return
    end
    registered = true
    RegisterNUICallback(CALLBACK_NAME, function(body, reply)
        -- Replying is a courtesy; losing it must not stop the handler.
        pcall(reply, 'ok')
        body = type(body) == 'table' and body or {}
        if body.stage == 'ready' then
            begin()
        elseif body.stage == 'done' then
            complete(body)
        end
    end)
end

return Sprites
