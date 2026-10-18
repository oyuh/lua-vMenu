-- Ports of the on-off player features in vMenu.Enhanced.Menus/Players
-- (PlayerGodMode.cs, PlayerInvisible.cs, PlayerNoRagdoll.cs,
-- PlayerStayInVehicle.cs, PlayerFreeze.cs, EveryoneIgnoresPlayer.cs,
-- PlayerFastRun.cs, PlayerFastSwim.cs, PlayerUnlimitedOxygen.cs,
-- PlayerNeverWanted.cs, PlayerNoHelmet.cs). Upstream gives each its own class
-- with the same shape, which here is one Toggle: a saved preference, a
-- permission, and on_apply(on). A feature is on only while both agree, so losing
-- the permission switches it off and getting it back restores the choice.

local Permissions = require('client.permissions')
local UserDefaults = require('client.user_defaults')
local Ticks = require('menu.ticks')
local PlayerEvents = require('client.events.player_events')
local Protection = require('client.menus.players.protection')

local Toggles = {}

local PERMISSION = 'vMenu.Enhanced.Menus.PlayerOptions.'

local Toggle = {}
Toggle.__index = Toggle

-- spec: { permission, preference (nil keeps the choice for this session only),
-- on_apply(on), watch (player events after which to apply again) }
local function toggle(spec)
    spec.session = false
    return setmetatable(spec, Toggle)
end

function Toggle:wanted()
    if self.preference then
        return UserDefaults.get(self.preference) == true
    end
    return self.session
end

function Toggle:allowed()
    return Permissions.is_allowed(self.permission)
end

function Toggle:enabled()
    return self:wanted() and self:allowed()
end

function Toggle:apply()
    local on = self:enabled()
    if self.watch and on ~= (self.unsubscribers ~= nil) then
        if on then
            self.unsubscribers = {}
            for index, name in ipairs(self.watch) do
                self.unsubscribers[index] = PlayerEvents.on(name, function()
                    self:apply()
                end)
            end
        else
            for _, unsubscribe in ipairs(self.unsubscribers) do
                unsubscribe()
            end
            self.unsubscribers = nil
        end
    end
    self.on_apply(on)
end

function Toggle:set_enabled(on)
    if on and not self:allowed() then
        return
    end
    if self.preference then
        UserDefaults.set(self.preference, on)
    else
        self.session = on
    end
    self:apply()
end

local function player_ped()
    local ped = PlayerPedId()
    if ped ~= 0 and DoesEntityExist(ped) then
        return ped
    end
    return nil
end

local REVIVED = { 'ped_changed', 'revived' }
local NEW_PED = { 'ped_changed' }

-- God mode ---------------------------------------------------------------------------

local god_protection = Protection.claim()
local GOD_PROTECTIONS = Protection.NOT_DRAGGED_OUT | Protection.NOT_SHOT_IN_VEHICLE

Toggles.god_mode = toggle({
    permission = PERMISSION .. 'Godmode',
    preference = 'playerGodMode',
    on_apply = function(on)
        god_protection:set(on, GOD_PROTECTIONS)
        SetPlayerInvincibleKeepRagdollEnabled(PlayerId(), on)
        local ped = not on and player_ped()
        if ped then
            SetEntityInvincible(ped, false, false)
        end
        Ticks.reevaluate()
    end,
})

-- Something else may have cleared the flag, so it is written again now and then.
local GOD_MODE_INTERVAL_MS = 1000

function Toggles.god_mode:reapply()
    self:apply()
    Protection.reapply()
end

-- Protection -------------------------------------------------------------------------

Toggles.invisible = toggle({
    permission = PERMISSION .. 'Invisible',
    preference = 'playerInvisible',
    watch = REVIVED,
    on_apply = function(on)
        local ped = player_ped()
        if ped then
            SetEntityVisible(ped, not on, false)
        end
    end,
})

local ragdoll_protection = Protection.claim()

Toggles.no_ragdoll = toggle({
    permission = PERMISSION .. 'NoRagdoll',
    preference = 'playerNoRagdoll',
    watch = REVIVED,
    on_apply = function(on)
        ragdoll_protection:set(on, Protection.NOT_KNOCKED_OFF_BIKE)
        local ped = player_ped()
        if ped then
            SetPedCanRagdoll(ped, not on)
        end
    end,
})

local vehicle_protection = Protection.claim()

Toggles.stay_in_vehicle = toggle({
    permission = PERMISSION .. 'StayInVehicle',
    preference = 'playerStayInVehicle',
    on_apply = function(on)
        vehicle_protection:set(on, Protection.NOT_DRAGGED_OUT)
    end,
})

-- Not saved: nobody wants to join a server frozen in place.
Toggles.freeze = toggle({
    permission = PERMISSION .. 'Freeze',
    watch = REVIVED,
    on_apply = function(on)
        local ped = player_ped()
        if ped then
            FreezeEntityPosition(ped, on)
        end
    end,
})

Toggles.everyone_ignores = toggle({
    permission = PERMISSION .. 'Ignored',
    preference = 'playerEveryoneIgnores',
    on_apply = function(on)
        local player = PlayerId()
        SetEveryoneIgnorePlayer(player, on)
        SetPoliceIgnorePlayer(player, on)
        SetPlayerCanBeHassledByGangs(player, not on)
    end,
})

-- Movement ---------------------------------------------------------------------------

-- The highest multiplier the game accepts.
local FAST = 1.49

Toggles.fast_run = toggle({
    permission = PERMISSION .. 'FastRun',
    preference = 'playerFastRun',
    watch = NEW_PED,
    on_apply = function(on)
        SetRunSprintMultiplierForPlayer(PlayerId(), on and FAST or 1.0)
    end,
})

Toggles.fast_swim = toggle({
    permission = PERMISSION .. 'FastSwim',
    preference = 'playerFastSwim',
    watch = NEW_PED,
    on_apply = function(on)
        SetSwimMultiplierForPlayer(PlayerId(), on and FAST or 1.0)
    end,
})

local FOREVER_UNDERWATER = 1000000.0
local FALLBACK_CEILING = 20.0
local oxygen = { ceiling = FALLBACK_CEILING, ceiling_of = 0, raised = false }

Toggles.unlimited_oxygen = toggle({
    permission = PERMISSION .. 'UnlimitedOxygen',
    preference = 'playerUnlimitedOxygen',
    watch = REVIVED,
    on_apply = function(on)
        if not on and not oxygen.raised then
            return
        end
        local ped = player_ped()
        if not ped then
            return
        end
        -- Remember this ped's own limit, so turning it off puts that back.
        if on and not (oxygen.raised and ped == oxygen.ceiling_of) then
            local remaining = GetPlayerUnderwaterTimeRemaining(PlayerId())
            oxygen.ceiling_of = ped
            oxygen.ceiling = remaining > 0 and remaining or FALLBACK_CEILING
        end
        oxygen.raised = on
        SetPedMaxTimeUnderwater(ped, on and FOREVER_UNDERWATER or oxygen.ceiling)
        SetPedDiesInWater(ped, not on)
    end,
})

-- Wanted level -----------------------------------------------------------------------

local DEFAULT_WANTED_CEILING = 5
local wanted = { restore = DEFAULT_WANTED_CEILING, held = false }

Toggles.never_wanted = toggle({
    permission = PERMISSION .. 'NeverWanted',
    preference = 'playerNeverWanted',
    on_apply = function(on)
        if on == wanted.held then
            return
        end
        wanted.held = on
        if not on then
            SetMaxWantedLevel(wanted.restore)
            return
        end
        local ceiling = GetMaxWantedLevel()
        wanted.restore = ceiling > 0 and ceiling or DEFAULT_WANTED_CEILING
        SetMaxWantedLevel(0)
        local player = PlayerId()
        SetPlayerWantedLevel(player, 0, false)
        SetPlayerWantedLevelNow(player, false)
    end,
})

-- Appearance -------------------------------------------------------------------------

local DISABLE_AUTO_EQUIP_HELMETS_IN_BIKES = 380
local DISABLE_AUTO_EQUIP_HELMETS_IN_AIRCRAFT = 381

Toggles.no_helmet = toggle({
    permission = PERMISSION .. 'NoHelmet',
    preference = 'playerNoHelmet',
    watch = NEW_PED,
    on_apply = function(on)
        local ped = player_ped()
        if ped then
            SetPedConfigFlag(ped, DISABLE_AUTO_EQUIP_HELMETS_IN_BIKES, on)
            SetPedConfigFlag(ped, DISABLE_AUTO_EQUIP_HELMETS_IN_AIRCRAFT, on)
        end
    end,
})

local ORDER = {
    'god_mode',
    'unlimited_oxygen',
    'no_ragdoll',
    'no_helmet',
    'invisible',
    'stay_in_vehicle',
    'freeze',
    'everyone_ignores',
    'never_wanted',
    'fast_run',
    'fast_swim',
}

-- Call once at startup; every feature applies again when permissions change.
function Toggles.init()
    Ticks.register('Player.GodMode', function()
        SetPlayerInvincibleKeepRagdollEnabled(PlayerId(), true)
    end, {
        rate = GOD_MODE_INTERVAL_MS,
        condition = function()
            return Toggles.god_mode:enabled()
        end,
    })
    for _, name in ipairs(ORDER) do
        local feature = Toggles[name]
        Permissions.on_changed(function()
            feature:apply()
        end)
        feature:apply()
    end
end

return Toggles
