-- Port of vMenu.Enhanced.Events/LocalPlayerTicks.cs: events about the local
-- player's ped, found by polling. Each poll only runs while something listens.
--
-- PlayerEvents.on(name, handler) returns a function that unsubscribes.
--   'ped_changed'    { ped, previous }
--   'model_changed'  { ped, model, previous }
--   'damaged'        { ped, health, health_lost, armour, armour_lost }
--   'died'           { ped, killer, cause }
--   'revived'        { ped, health, respawned }

local Log = require('shared.log')
local Ticks = require('menu.ticks')

local PlayerEvents = {}

local IDENTITY_INTERVAL_MS = 250
local HEALTH_INTERVAL_MS = 100
local RESPAWN_DISTANCE = 25.0

local IDENTITY = { ped_changed = true, model_changed = true }
local HEALTH = { damaged = true, died = true, revived = true }

local handlers = {
    ped_changed = {},
    model_changed = {},
    damaged = {},
    died = {},
    revived = {},
}

local ped, model = 0, 0
local health_ped, health, armour, dead = 0, 0, 0, false
local died_as, died_at = 0, nil

local function exists(handle)
    return handle ~= 0 and DoesEntityExist(handle)
end

local function raise(name, event)
    for _, handler in ipairs(handlers[name]) do
        local ok, err = pcall(handler, event)
        if not ok then
            Log.error(("[Events] A '%s' handler threw: %s"):format(name, tostring(err)))
        end
    end
end

local function any(names)
    for name in pairs(names) do
        if #handlers[name] > 0 then
            return true
        end
    end
    return false
end

local function seed_identity()
    local current = PlayerPedId()
    if exists(current) then
        ped, model = current, GetEntityModel(current)
    end
end

local function seed_health()
    local current = PlayerPedId()
    if not exists(current) then
        return
    end
    health_ped, health, armour = current, GetEntityHealth(current), GetPedArmour(current)
    dead, died_as = IsEntityDead(current, false), 0
end

local function poll_identity()
    local current = PlayerPedId()
    if not exists(current) then
        return
    end
    local current_model = GetEntityModel(current)
    if current ~= ped then
        local previous = ped
        ped = current
        raise('ped_changed', { ped = current, previous = previous })
    end
    if current_model ~= model then
        local previous = model
        model = current_model
        raise('model_changed', { ped = current, model = current_model, previous = previous })
    end
end

local function raise_died(current)
    died_as, died_at = current, GetEntityCoords(current, true)
    raise('died', { ped = current, killer = GetPedSourceOfDeath(current), cause = GetPedCauseOfDeath(current) })
end

local function raise_revived(current, current_health)
    local respawned = current ~= died_as
        or died_at == nil
        or #(GetEntityCoords(current, true) - died_at) > RESPAWN_DISTANCE
    died_as = 0
    raise('revived', { ped = current, health = current_health, respawned = respawned })
end

local function poll_health()
    local current = PlayerPedId()
    if not exists(current) then
        return
    end
    local now_health, now_armour = GetEntityHealth(current), GetPedArmour(current)
    local now_dead = IsEntityDead(current, false)
    if current ~= health_ped then
        local was_dead = dead
        health_ped, health, armour, dead = current, now_health, now_armour, now_dead
        if was_dead and not now_dead then
            raise_revived(current, now_health)
        end
        return
    end
    if now_dead ~= dead then
        dead, health, armour = now_dead, now_health, now_armour
        if now_dead then
            raise_died(current)
        else
            raise_revived(current, now_health)
        end
        return
    end
    local health_lost, armour_lost = health - now_health, armour - now_armour
    health, armour = now_health, now_armour
    if now_dead or (health_lost <= 0 and armour_lost <= 0) then
        return
    end
    raise('damaged', {
        ped = current,
        health = now_health,
        health_lost = math.max(health_lost, 0),
        armour = now_armour,
        armour_lost = math.max(armour_lost, 0),
    })
end

local registered = false

local function register_ticks()
    if registered then
        return
    end
    registered = true
    Ticks.register('Events.Player.Identity', poll_identity, {
        rate = IDENTITY_INTERVAL_MS,
        condition = function()
            return any(IDENTITY)
        end,
        on_started = seed_identity,
    })
    Ticks.register('Events.Player.Health', poll_health, {
        rate = HEALTH_INTERVAL_MS,
        condition = function()
            return any(HEALTH)
        end,
        on_started = seed_health,
    })
end

function PlayerEvents.on(name, handler)
    local list = assert(handlers[name], ('unknown player event %s'):format(tostring(name)))
    register_ticks()
    list[#list + 1] = handler
    Ticks.reevaluate()
    return function()
        for index = #list, 1, -1 do
            if list[index] == handler then
                table.remove(list, index)
            end
        end
        Ticks.reevaluate()
    end
end

return PlayerEvents
