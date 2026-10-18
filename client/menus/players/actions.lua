-- Ports of vMenu.Enhanced.Menus/Players/PlayerActions.cs and
-- PlayerScenarios.cs: the one-shot things Player Options does to your ped.

local Localization = require('shared.localization')
local DamagePacks = require('shared.data.ped_damage_packs')
local Scenarios = require('shared.data.ped_scenarios')
local Permissions = require('client.permissions')
local Notifications = require('client.framework.notifications')
local Toggles = require('client.menus.players.toggles')

local Actions = {}

Actions.ARMOR_TIERS = 5

local SOAKED = 2.0
local DRY = 0.0
local DAMAGE_ZONES = 6
local SCENARIO_PERMISSION = 'vMenu.Enhanced.Menus.PlayerOptions.Scenarios'
local TOO_FAST = 5.0
local SEAT_BACK = -0.5
local SEAT_DOWN = -0.5

function Actions.heal()
    local ped = PlayerPedId()
    -- The two zeros are the extra arguments newer native databases declare, as upstream passes them.
    SetEntityHealth(ped, GetEntityMaxHealth(ped), 0, 0)
    Notifications.success(Localization.key('playeroptions.healplayer.done'))
end

function Actions.commit_suicide()
    local ped = PlayerPedId()
    SetPlayerInvincibleKeepRagdollEnabled(PlayerId(), false)
    SetEntityInvincible(ped, false, false)
    SetEntityHealth(ped, 0, 0, 0)
    Toggles.god_mode:reapply()
end

-- 0 for none up to ARMOR_TIERS for full.
function Actions.armor_tier()
    local max = GetPlayerMaxArmour(PlayerId())
    if max <= 0 then
        return 0
    end
    local tier = math.floor(GetPedArmour(PlayerPedId()) * Actions.ARMOR_TIERS / max + 0.5)
    return math.max(0, math.min(Actions.ARMOR_TIERS, tier))
end

function Actions.set_armor_tier(tier)
    local max = GetPlayerMaxArmour(PlayerId())
    tier = math.max(0, math.min(Actions.ARMOR_TIERS, tier))
    SetPedArmour(PlayerPedId(), tier * max // Actions.ARMOR_TIERS)
end

-- 1-based, into shared/data/ped_damage_packs.lua.
function Actions.apply_damage_pack(index)
    local name = DamagePacks[index]
    if name then
        ApplyPedDamagePack(PlayerPedId(), name, 100.0, 100.0)
    end
end

function Actions.clear_blood()
    local ped = PlayerPedId()
    ClearPedBloodDamage(ped)
    ResetPedVisibleDamage(ped)
    for zone = 0, DAMAGE_ZONES - 1 do
        ClearPedDamageDecalByZone(ped, zone, 'ALL')
    end
    Notifications.success(Localization.key('playeroptions.clearblood.done'))
end

function Actions.clean_clothes()
    ClearPedBloodDamage(PlayerPedId())
    Notifications.success(Localization.key('playeroptions.cleanplayer.done'))
end

function Actions.dry_clothes()
    SetPedWetnessHeight(PlayerPedId(), DRY)
    Notifications.success(Localization.key('playeroptions.dryplayer.done'))
end

function Actions.wet_clothes()
    SetPedWetnessHeight(PlayerPedId(), SOAKED)
    Notifications.success(Localization.key('playeroptions.wetplayer.done'))
end

function Actions.wanted_level()
    return GetPlayerWantedLevel(PlayerId())
end

function Actions.set_wanted_level(stars)
    local player = PlayerId()
    SetPlayerWantedLevel(player, stars, false)
    SetPlayerWantedLevelNow(player, false)
end

-- Scenarios --------------------------------------------------------------------------

local playing = ''

-- The reason a scenario cannot start right now, or nil.
local function refusal()
    local ped = PlayerPedId()
    if IsEntityDead(ped, false) then
        return Localization.key('playeroptions.scenario.dead')
    elseif IsPlayerInCutscene(PlayerId()) then
        return Localization.key('playeroptions.scenario.cutscene')
    elseif NetworkIsInSpectatorMode() then
        return Localization.key('playeroptions.scenario.spectating')
    elseif not IsPedOnFoot(ped) then
        return Localization.key('playeroptions.scenario.notonfoot')
    elseif IsPedFalling(ped) or IsPedRagdoll(ped) then
        return Localization.key('playeroptions.scenario.falling')
    elseif IsPedRunning(ped) or GetEntitySpeed(ped) > TOO_FAST then
        return Localization.key('playeroptions.scenario.moving')
    end
    return nil
end

function Actions.stop_scenario()
    playing = ''
    local ped = PlayerPedId()
    ClearPedTasks(ped)
    ClearPedSecondaryTask(ped)
end

function Actions.force_stop_scenario()
    playing = ''
    local ped = PlayerPedId()
    ClearPedTasks(ped)
    ClearPedTasksImmediately(ped)
end

-- 1-based, into shared/data/ped_scenarios.lua. Picking the playing one again stops it.
function Actions.play_scenario(index)
    local scenario = Scenarios[index]
    if not scenario or not Permissions.is_allowed(SCENARIO_PERMISSION) then
        return
    end
    local name, position_based = scenario[2], scenario[3]
    local ped = PlayerPedId()
    if playing == name and IsPedUsingScenario(ped, name) then
        Actions.stop_scenario()
        return
    end
    local reason = refusal()
    if reason then
        Notifications.warning(reason)
        return
    end
    ClearPedTasks(ped)
    playing = name
    if position_based then
        local seat = GetOffsetFromEntityInWorldCoords(ped, 0.0, SEAT_BACK, SEAT_DOWN)
        TaskStartScenarioAtPosition(ped, name, seat.x, seat.y, seat.z, GetEntityHeading(ped), -1, true, false)
        return
    end
    TaskStartScenarioInPlace(ped, name, 0, true)
end

return Actions
