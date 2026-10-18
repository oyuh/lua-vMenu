-- Ports of vMenu.Enhanced.MenuFramework/Hud.cs and HudAnchor.cs: on-screen
-- text and the screen position just above the minimap.

local Locks = require('client.framework.locks')

local Hud = {}

Hud.NEW_LINE = '~n~'
Hud.CENTER, Hud.LEFT, Hud.RIGHT = 0, 1, 2

local DEFAULT_FONT = 6
local DEFAULT_SIZE = 0.48
local MINIMAP_HEIGHT = 1 / 5.674
local BIGMAP_HEIGHT = 1 / 2.35

function Hud.can_draw()
    return not Locks.scene_active()
        and IsHudPreferenceSwitchedOn()
        and not IsHudHidden()
        and not IsPlayerSwitchInProgress()
        and IsScreenFadedIn()
        and not IsPauseMenuActive()
        and not IsFrontendFading()
        and not IsPauseMenuRestarting()
end

-- alignment: Hud.LEFT (default), Hud.CENTER or Hud.RIGHT.
function Hud.draw_text(text, x, y, size, alignment, font, disable_outline)
    if not Hud.can_draw() then
        return
    end
    alignment = alignment or Hud.LEFT
    SetTextFont(font or DEFAULT_FONT)
    SetTextScale(1.0, size or DEFAULT_SIZE)
    if alignment == Hud.RIGHT then
        SetTextWrap(0.0, x)
    end
    SetTextJustification(alignment)
    if not disable_outline then
        SetTextOutline()
    end
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    -- The third argument only exists on FiveM Enhanced; Legacy reads two and
    -- ignores the rest.
    EndTextCommandDisplayText(x, y, 0)
end

function Hud.draw_text_3d(text, x, y, z, size, alignment, font)
    -- Checked before the origin is set, so a hidden HUD costs nothing for
    -- callers drawing one of these per entity per frame.
    if not Hud.can_draw() then
        return
    end
    SetDrawOrigin(x, y, z, false)
    Hud.draw_text(text, 0.0, 0.0, size, alignment or Hud.CENTER, font or 0)
    ClearDrawOrigin()
end

function Hud.inset()
    return (1.0 - GetSafeZoneSize()) / 2.0
end

function Hud.minimap_width()
    local aspect = GetScreenAspectRatio(false)
    return aspect > 0 and 1 / (4 * aspect) or 0.25
end

-- left, bottom and width of the area just above the minimap, as screen fractions.
function Hud.above_minimap()
    local inset = Hud.inset()
    local map = 0.0
    if not IsRadarHidden() then
        map = IsBigmapActive() and BIGMAP_HEIGHT or MINIMAP_HEIGHT
    end
    return inset, inset + map, Hud.minimap_width()
end

-- Rounded to five places, like the C# MathF.Round, for messages to the page.
function Hud.fraction(value)
    return math.floor(value * 100000 + 0.5) / 100000
end

return Hud
