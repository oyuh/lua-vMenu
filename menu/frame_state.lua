-- Port of MenuAPI/ticks/FrameState.cs: game state read at most once per
-- frame, however many ticks ask. The scheduler tick clears it every frame.

local FrameState = {}

local cache = {}

function FrameState.invalidate()
    cache = {}
end

local function cached(key, read)
    local value = cache[key]
    if value == nil then
        value = read()
        cache[key] = value
    end
    return value
end

function FrameState.ped()
    return cached('ped', PlayerPedId)
end

function FrameState.is_dead()
    return cached('dead', function()
        return IsPlayerDead(PlayerId())
    end)
end

function FrameState.is_in_vehicle()
    return cached('vehicle', function()
        return IsPedInAnyVehicle(FrameState.ped(), false)
    end)
end

function FrameState.is_screen_faded_in()
    return cached('faded_in', IsScreenFadedIn)
end

function FrameState.is_pause_menu_active()
    return cached('pause', IsPauseMenuActive)
end

function FrameState.is_player_switch_in_progress()
    return cached('switch', IsPlayerSwitchInProgress)
end

-- UpdateOnscreenKeyboard: 0 while the onscreen keyboard is open.
function FrameState.onscreen_keyboard()
    return cached('keyboard', UpdateOnscreenKeyboard)
end

return FrameState
