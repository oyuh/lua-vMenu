-- Port of vMenu.Enhanced.Menus/Misc/NoClipSmoke.cs: a puff of smoke where a
-- player starts or stops noclipping, read from their state bag. The server
-- owner turns it on with vMenu.Enhanced.Gameplay.NoClipSmoke.

local Config = require('shared.config')
local Ticks = require('menu.ticks')
local Streaming = require('client.streaming')
local Roster = require('client.menus.players.roster')

local NoClipSmoke = {}

local SETTING = 'vMenu.Enhanced.Gameplay.NoClipSmoke'
local ASSET = 'scr_powerplay'
local VANISH = 'scr_powerplay_beast_vanish'
local APPEAR = 'scr_powerplay_beast_appear'
local VANISH_SCALE = 1.0
local APPEAR_SCALE = 0.75
local HEIGHT_OFFSET = -0.3
local SCAN_MS = 200
local HOLD_MS = 5000

local known = {}
local loaded = false
local release_at = 0

local function enabled()
    return Config.value(SETTING)
end

local function puff(position, entering)
    if not loaded then
        loaded = Streaming.ptfx(ASSET)
        if not loaded then
            return
        end
    end
    release_at = GetGameTimer() + HOLD_MS
    UseParticleFxAssetNextCall(ASSET)
    StartParticleFxNonLoopedAtCoord(
        entering and VANISH or APPEAR,
        position.x,
        position.y,
        position.z + HEIGHT_OFFSET,
        0.0,
        0.0,
        0.0,
        entering and VANISH_SCALE or APPEAR_SCALE,
        false,
        false,
        false
    )
end

local function unload()
    if loaded then
        loaded = false
        RemoveNamedPtfxAsset(ASSET)
    end
end

local function scan()
    Roster.refresh()
    local seen = {}
    for _, player in ipairs(Roster.all()) do
        local noclip = Player(player.server_id).state['vMenu:noclip'] == true
        local was = known[player.server_id]
        if was ~= nil and was ~= noclip then
            local position = player.position
            CreateThread(function()
                puff(position, noclip)
            end)
        end
        seen[player.server_id] = noclip
    end
    known = seen
    if loaded and GetGameTimer() >= release_at then
        unload()
    end
end

function NoClipSmoke.init()
    Ticks.register('Misc.NoClipSmoke', scan, {
        rate = SCAN_MS,
        condition = enabled,
        on_stopped = function()
            known = {}
            unload()
        end,
    })
    Config.watch({ SETTING }, Ticks.reevaluate)
end

return NoClipSmoke
