-- Port of vMenu.Enhanced.Menus/UserPreferences.cs: turns stored preferences
-- into applied state, and back when the player changes one. The storage
-- module knows how to persist a value; this one knows what it means.

local Log = require('shared.log')
local Localization = require('shared.localization')
local UserDefaults = require('client.user_defaults')
local Controller = require('menu.controller')

local UserPreferences = {}

local function restore_language()
    local stored = UserDefaults.get('language')
    if stored == nil or stored:match('^%s*$') then
        return
    end
    if Localization.set_language(stored) then
        return
    end
    -- The preference is kept for servers that do offer the language.
    Log.debug(("[Localization] '%s' is not available here, so English is being used."):format(stored))
    Localization.set_language('en')
end

function UserPreferences.is_right_aligned()
    return Controller.MenuAlignment == 'Right'
end

-- MenuAPI declines a right alignment on wide screens. A rejection is written
-- back even without persist, so the player does not meet it on every restart.
local function apply_right_aligned(right, persist)
    Controller.MenuAlignment = right and 'Right' or 'Left'
    if right and not UserPreferences.is_right_aligned() then
        UserDefaults.set('displayRightAlignMenu', false)
        return
    end
    if persist then
        UserDefaults.set('displayRightAlignMenu', right)
    end
end

function UserPreferences.set_right_aligned(right)
    apply_right_aligned(right, true)
end

function UserPreferences.set_language(code)
    UserDefaults.set('language', code)
end

-- Call before the menus are built: the language decides every label.
function UserPreferences.restore()
    restore_language()
    apply_right_aligned(UserDefaults.get('displayRightAlignMenu'), false)
end

return UserPreferences
