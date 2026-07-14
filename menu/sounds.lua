-- Frontend sound cues used by the menu framework (MenuAPI parity).
-- Each call is a no-op outside the game runtime so navigation logic stays
-- unit-testable.

local Sounds = {}

local function play(name)
    if PlaySoundFrontend then
        PlaySoundFrontend(-1, name, 'HUD_FRONTEND_DEFAULT_SOUNDSET', false)
    end
end

function Sounds.nav_up_down()
    play('NAV_UP_DOWN')
end

function Sounds.nav_left_right()
    play('NAV_LEFT_RIGHT')
end

function Sounds.select()
    play('SELECT')
end

function Sounds.error_()
    play('ERROR')
end

function Sounds.back()
    play('BACK')
end

return Sounds
