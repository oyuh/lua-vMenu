-- Ports of vMenu.Enhanced.Menus/Teleport/TeleportTargets.cs and
-- TeleportKeyBinding.cs: teleporting to the waypoint or to typed coordinates,
-- from the menu or from a key the player picks the action for.
-- Waits, so call it from a thread.

local Log = require('shared.log')
local Config = require('shared.config')
local Localization = require('shared.localization')
local Permissions = require('client.permissions')
local UserDefaults = require('client.user_defaults')
local Notifications = require('client.framework.notifications')
local Input = require('client.framework.input')
local Locks = require('client.framework.locks')
local Teleport = require('client.menus.players.teleport')

local Targets = {}

Targets.KEY_DISABLED = 0
Targets.KEY_WAYPOINT = 1
Targets.KEY_COORDS = 2

local TEXT_LENGTH = 50
local WAYPOINT_BLIP_TYPE = 4
local FADE_WAIT_MS = 2000
local KEY_COMMAND = 'vmenu:teleport'
local PERMISSION = 'vMenu.Enhanced.Menus.TeleportMenu.'

local function waypoint_blip()
    local iterator = GetBlipInfoIdIterator()
    local blip = GetFirstBlipInfoId(iterator)
    while DoesBlipExist(blip) do
        if GetBlipInfoIdType(blip) == WAYPOINT_BLIP_TYPE then
            return blip
        end
        blip = GetNextBlipInfoId(iterator)
    end
    return nil
end

function Targets.to_waypoint()
    if not IsWaypointActive() then
        Notifications.error(Localization.key('teleportmenu.tptowp.nowp'))
        return
    end
    local blip = waypoint_blip()
    if not blip then
        Notifications.error(Localization.key('teleportmenu.tptowp.invalid'))
        return
    end
    local target = GetBlipInfoIdCoord(blip)
    if Teleport.to_ground(target.x, target.y) then
        return
    end
    Notifications.error(Localization.key('teleportmenu.groundnotfound'))
    -- The fade hides the map marker, so it goes back once the screen is up again.
    local started = GetGameTimer()
    while not IsScreenFadedIn() and GetGameTimer() - started < FADE_WAIT_MS do
        Wait(0)
    end
    SetNewWaypoint(target.x, target.y)
end

-- Three numbers, separated by commas or spaces. x, y, z or nil.
function Targets.parse_coords(typed)
    local parts = {}
    for part in typed:gmatch('[^,%s]+') do
        parts[#parts + 1] = tonumber(part)
        if parts[#parts] == nil then
            return nil
        end
    end
    if #parts ~= 3 then
        return nil
    end
    return parts[1], parts[2], parts[3]
end

function Targets.to_typed_coords()
    local typed = Input.get_text({
        title = Localization.key('teleportmenu.tptocoords.prompt'),
        max_length = TEXT_LENGTH,
        initial_value = '0, 0, 0',
    })
    if typed == nil or typed:match('^%s*$') then
        return
    end
    local x, y, z = Targets.parse_coords(typed)
    if not x then
        Notifications.error(Localization.key('teleportmenu.tptocoords.invalid'))
        return
    end
    Teleport.to_coords(x, y, z)
end

-- The key ---------------------------------------------------------------------------

local running = false

local function on_key()
    local action = UserDefaults.get('teleportKeyAction')
    if running or Locks.scene_active() or (action ~= Targets.KEY_WAYPOINT and action ~= Targets.KEY_COORDS) then
        return
    end
    local permission = PERMISSION .. (action == Targets.KEY_WAYPOINT and 'Waypoint' or 'Coords')
    if not Permissions.is_allowed(permission) then
        Notifications.error(Localization.key('teleportmenu.key.action.denied'))
        return
    end
    running = true
    CreateThread(function()
        local ok, err = pcall(action == Targets.KEY_WAYPOINT and Targets.to_waypoint or Targets.to_typed_coords)
        running = false
        if not ok then
            Log.error('[Teleport] The teleport key threw: ' .. tostring(err))
        end
    end)
end

function Targets.init()
    local key = Config.value('vMenu.Enhanced.KeyBindings.TeleportKey')
    if key == nil or key:match('^%s*$') then
        key = 'F10'
    end
    RegisterCommand(KEY_COMMAND, on_key, false)
    RegisterKeyMapping(KEY_COMMAND, 'vMenu: Teleport', 'keyboard', key)
end

return Targets
