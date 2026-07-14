-- Low-level drawing helpers shared by menu/render.lua (MenuAPI parity).
-- MenuAPI positions everything in a 1080p-relative coordinate space:
-- ScreenHeight is fixed at 1080 and ScreenWidth is 1080 * aspect ratio.

local Draw = {}

Draw.WIDTH = 500.0 -- Menu.Width (FiveM)
Draw.ROW_HEIGHT = 38.0 -- MenuItem.RowHeight
Draw.HEADER_WIDTH = 500.0
Draw.HEADER_HEIGHT = 110.0
Draw.TEXTURE_DICT = 'commonmenu' -- MenuController._texture_dict
Draw.HEADER_TEXTURE = 'interaction_bgd' -- MenuController._header_texture

function Draw.screen_width()
    return 1080.0 * GetAspectRatio(false)
end

function Draw.screen_height()
    return 1080.0
end

function Draw.aspect_ratio()
    return GetAspectRatio(false)
end

function Draw.safe_zone()
    return GetSafeZoneSize()
end

-- SetScriptGfxAlign(76='L'|82='R', 84='T') + params, as MenuAPI does before
-- every aligned draw call.
function Draw.set_gfx_align(left_aligned)
    SetScriptGfxAlign(left_aligned and 76 or 82, 84)
    SetScriptGfxAlignParams(0.0, 0.0, 0.0, 0.0)
end

function Draw.reset_gfx_align()
    ResetScriptGfxAlign()
end

-- AddTextComponentSubstringPlayerName caps at 99 characters; long strings
-- (descriptions) must be fed in chunks (CitizenFX.Core.UI.Screen.StringToArray).
function Draw.add_long_string(text)
    for i = 1, #text, 99 do
        AddTextComponentSubstringPlayerName(text:sub(i, i + 98))
    end
end

return Draw
