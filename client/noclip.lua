-- Ports of vMenu.Enhanced.NoClip (NoClip.cs, NoClipKeyBindings.cs, Controls.cs):
-- flying the player, or the vehicle they sit in, through the world. Every key
-- is a key mapping the player can rebind, and the server hears about it so
-- other players can see who is noclipping.
--
-- Upstream also lets staff lend or force noclip on a player from Online
-- Players; that comes with the Online Players menu.

local Config = require('shared.config')
local Localization = require('shared.localization')
local Permissions = require('client.permissions')
local Notifications = require('client.framework.notifications')
local Locks = require('client.framework.locks')
local Input = require('menu.input')
local Ticks = require('menu.ticks')

local NoClip = {}

local PERMISSION = 'vMenu.Enhanced.NoClip'
local EVENT_REPORT = 'vMenu.Enhanced:PlayerState:ReportNoClip'
local GROUP = 0
local VEHICLE_RADIO_WHEEL = 81

-- The game controls that would fight the movement keys.
local DISABLED_CONTROLS = { 85, 30, 31, 32, 33, 34, 35, 36, 44, 244, 74 }

local MOVE_SPEEDS = {
    { 0.1, '1' },
    { 0.25, '2' },
    { 0.75, '3' },
    { 1.15, '4' },
    { 2.5, '5' },
    { 5.5, '6' },
    { 8.5, '7' },
    { 12.5, '8' },
    { 18.5, '9' },
    { 25.5, '10' },
}

local FORWARD_STEP = 0.5
local VERTICAL_STEP = 0.21
local TURN_STEP = 3.0
local NOCLIP_ALPHA = 51

local active = false
local speed = 1
local follow_cam = true
local held = {}
local noclip_ped, noclip_entity, cached_entity = 0, 0, 0
local released_handlers = {}

function NoClip.is_active()
    return active
end

-- handler(entity) after noclip lets go of an entity, so features that change
-- the same flags (god mode, invisible) can put theirs back.
function NoClip.on_released(handler)
    released_handlers[#released_handlers + 1] = handler
end

local function allowed()
    return Permissions.is_allowed(PERMISSION)
end

-- Instructional buttons ----------------------------------------------------------------

local scaleform = -1
local rebuild_buttons = true

local function icon(command)
    return GetControlInstructionalButton(0, Input.binding_control(command), true)
end

local function pair(first, second)
    return icon(first) .. '%b_998%' .. icon(second)
end

local function buttons()
    local list = {
        {
            ('Change Speed (%sx)'):format(MOVE_SPEEDS[speed][2]),
            pair('vmenu:noclip:speeddown', 'vmenu:noclip:speedup'),
        },
        { 'Up / Down', pair('+vmenu:noclip:down', '+vmenu:noclip:up') },
        { 'Forward / Backward', pair('+vmenu:noclip:backward', '+vmenu:noclip:forward') },
        { follow_cam and 'Follow Cam: On' or 'Follow Cam: Off', icon('vmenu:noclip:followcam') },
    }
    if not follow_cam then
        list[#list + 1] = { 'Turn Left / Right', pair('+vmenu:noclip:turnleft', '+vmenu:noclip:turnright') }
    end
    return list
end

local function build_buttons()
    CallScaleformMovieMethod(scaleform, 'CLEAR_ALL')
    BeginScaleformMovieMethod(scaleform, 'TOGGLE_MOUSE_BUTTONS')
    ScaleformMovieMethodAddParamInt(0)
    EndScaleformMovieMethod()
    for slot, button in ipairs(buttons()) do
        BeginScaleformMovieMethod(scaleform, 'SET_DATA_SLOT')
        ScaleformMovieMethodAddParamInt(slot - 1)
        ScaleformMovieMethodAddParamTextureNameString(button[2])
        ScaleformMovieMethodAddParamTextureNameString(button[1])
        EndScaleformMovieMethod()
    end
    CallScaleformMovieMethod(scaleform, 'DRAW_INSTRUCTIONAL_BUTTONS')
end

local function draw_buttons()
    if IsHudHidden() then
        return
    end
    if scaleform == -1 or not HasScaleformMovieLoaded(scaleform) then
        scaleform = RequestScaleformMovie('INSTRUCTIONAL_BUTTONS')
        while not HasScaleformMovieLoaded(scaleform) do
            Wait(0)
        end
        rebuild_buttons = true
    end
    if rebuild_buttons then
        build_buttons()
        rebuild_buttons = false
    end
    DrawScaleformMovieFullscreen(scaleform, 255, 255, 255, 255, 0)
end

local function release_buttons()
    if scaleform ~= -1 then
        SetScaleformMovieAsNoLongerNeeded(scaleform)
        scaleform = -1
        rebuild_buttons = true
    end
end

-- Moving ---------------------------------------------------------------------------

local function entity_for(ped)
    local in_vehicle = IsPedInAnyVehicle(ped, false)
    return in_vehicle and GetVehiclePedIsIn(ped, false) or ped, in_vehicle
end

local function reset_entity(ped, entity)
    FreezeEntityPosition(entity, false)
    SetEntityInvincible(entity, false, false)
    SetEntityCollision(entity, true, true)
    SetEntityVisible(ped, true, false)
    SetLocalPlayerVisibleLocally(true)
    if entity ~= ped then
        SetEntityVisible(entity, true, false)
    end
    ActivatePhysics(entity)
    ResetEntityAlpha(entity)
    if IsEntityAPed(ped) then
        SetEveryoneIgnorePlayer(ped, false)
        SetPoliceIgnorePlayer(ped, false)
    end
    for _, handler in ipairs(released_handlers) do
        handler(entity)
    end
end

-- A vehicle the player left mid-flight gets its physics back.
local function release_entity(entity)
    if IsEntityAVehicle(entity) then
        reset_entity(entity, entity)
    end
end

local function read_move()
    if IsPauseMenuActive() then
        return 0.0, 0.0, 0.0
    end
    local forward, vertical, turn = 0.0, 0.0, 0.0
    if held.forward then
        forward = FORWARD_STEP
    end
    if held.backward then
        forward = -FORWARD_STEP
    end
    if not follow_cam then
        if held.turnleft then
            turn = turn + TURN_STEP
        end
        if held.turnright then
            turn = turn - TURN_STEP
        end
    end
    if held.up then
        vertical = VERTICAL_STEP
    end
    if held.down then
        vertical = -VERTICAL_STEP
    end
    return forward, vertical, turn
end

local function frame()
    if noclip_entity ~= cached_entity then
        release_entity(cached_entity)
        cached_entity = noclip_entity
    end
    noclip_ped = PlayerPedId()
    local entity, in_vehicle = entity_for(noclip_ped)
    noclip_entity = entity

    FreezeEntityPosition(entity, true)
    SetEntityInvincible(entity, true, false)
    for _, control in ipairs(DISABLED_CONTROLS) do
        DisableControlAction(GROUP, control, false)
    end
    if in_vehicle then
        DisableControlAction(GROUP, VEHICLE_RADIO_WHEEL, false)
    end

    local forward, vertical, turn = read_move()
    local multiplier = MOVE_SPEEDS[speed][1]
    local position = GetOffsetFromEntityInWorldCoords(entity, 0.0, forward * multiplier, vertical * multiplier)
    SetEntityVelocity(entity, 0.0, 0.0, 0.0)
    SetEntityRotation(entity, 0.0, 0.0, 0.0, 0, false)
    SetEntityHeading(entity, follow_cam and GetGameplayCamRelativeHeading() or GetEntityHeading(entity) + turn)
    SetEntityCollision(entity, false, false)
    SetEntityCoordsNoOffset(entity, position.x, position.y, position.z, true, true, true)

    SetEntityVisible(entity, false, false)
    SetLocalPlayerVisibleLocally(true)
    SetEntityAlpha(entity, NOCLIP_ALPHA, false)
    SetEveryoneIgnorePlayer(noclip_ped, true)
    SetPoliceIgnorePlayer(noclip_ped, true)
end

local function begin()
    noclip_ped = PlayerPedId()
    noclip_entity = entity_for(noclip_ped)
    cached_entity = noclip_entity
end

local function finish()
    if cached_entity ~= noclip_entity then
        release_entity(cached_entity)
    end
    reset_entity(noclip_ped, noclip_entity)
    release_buttons()
end

-- Switching --------------------------------------------------------------------------

function NoClip.set_active(on)
    if on and (not allowed() or Locks.scene_active()) then
        return
    end
    if on == active then
        return
    end
    active = on
    TriggerServerEvent(EVENT_REPORT, on)
    Ticks.reevaluate()
end

local function toggle_requested()
    if not allowed() and not active then
        Notifications.warning(Localization.key('noclip.toggle.denied'))
        return
    end
    if not IsPauseMenuActive() then
        NoClip.set_active(not active)
    end
end

local function adjust_speed(steps)
    if active and not IsPauseMenuActive() then
        speed = (speed - 1 + steps) % #MOVE_SPEEDS + 1
        rebuild_buttons = true
    end
end

local function register_press(command, description, key, handler)
    RegisterCommand(command, handler, false)
    RegisterKeyMapping(command, description, 'keyboard', key)
end

local function register_hold(name, description, key)
    local command = 'vmenu:noclip:' .. name
    RegisterCommand('+' .. command, function()
        held[name] = true
    end, false)
    RegisterCommand('-' .. command, function()
        held[name] = false
    end, false)
    RegisterKeyMapping('+' .. command, description, 'keyboard', key)
end

function NoClip.init()
    RegisterCommand('nc', toggle_requested, false)
    local toggle_key = Config.value('vMenu.Enhanced.KeyBindings.NoClipToggleKey')
    if toggle_key == nil or toggle_key:match('^%s*$') then
        toggle_key = 'F2'
    end
    register_press('vmenu:noclip:togglenc', 'vMenu NoClip: Toggle on/off', toggle_key, toggle_requested)
    register_press('vmenu:noclip:speedup', 'vMenu NoClip: Increase speed', 'LSHIFT', function()
        adjust_speed(1)
    end)
    register_press('vmenu:noclip:speeddown', 'vMenu NoClip: Decrease speed', 'LCONTROL', function()
        adjust_speed(-1)
    end)
    register_press('vmenu:noclip:followcam', 'vMenu NoClip: Toggle follow cam', 'H', function()
        if active and not IsPauseMenuActive() then
            follow_cam = not follow_cam
            rebuild_buttons = true
        end
    end)
    register_hold('forward', 'vMenu NoClip: Move forward', 'W')
    register_hold('backward', 'vMenu NoClip: Move backward', 'S')
    register_hold('turnleft', 'vMenu NoClip: Turn left', 'A')
    register_hold('turnright', 'vMenu NoClip: Turn right', 'D')
    register_hold('up', 'vMenu NoClip: Move up', 'Q')
    register_hold('down', 'vMenu NoClip: Move down', 'Z')

    local function is_active()
        return active
    end
    Ticks.register('NoClip.Move', frame, { condition = is_active, on_started = begin, on_stopped = finish })
    Ticks.register('NoClip.InstructionalButtons', draw_buttons, { condition = is_active })
    Permissions.on_changed(function()
        if not allowed() then
            NoClip.set_active(false)
        end
    end)
end

return NoClip
