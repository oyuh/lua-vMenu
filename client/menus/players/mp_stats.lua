-- Port of vMenu.Enhanced.Menus/Players/MpStats.cs: the GTA Online ability
-- stats. Each player picks a percentage, capped by a server setting.

local Config = require('shared.config')
local Permissions = require('client.permissions')
local UserDefaults = require('client.user_defaults')

local MpStats = {}

MpStats.STEP = 5
MpStats.FULL = 100

local PERMISSION = 'vMenu.Enhanced.Menus.PlayerOptions.MpStats'

local function stat(name, preference, limit, key)
    return {
        stat = name,
        preference = preference,
        limit = 'vMenu.Enhanced.PlayerOptions.' .. limit,
        text_key = 'playeroptions.mpstats.' .. key,
        description_key = 'playeroptions.mpstats.' .. key .. '.desc',
    }
end

MpStats.ALL = {
    stat('MP0_SHOOTING_ABILITY', 'playerStatShooting', 'MaxShooting', 'shooting'),
    stat('MP0_STRENGTH', 'playerStatStrength', 'MaxStrength', 'strength'),
    stat('MP0_STAMINA', 'playerStatStamina', 'MaxStamina', 'stamina'),
    stat('MP0_STEALTH_ABILITY', 'playerStatStealth', 'MaxStealth', 'stealth'),
    stat('MP0_FLYING_ABILITY', 'playerStatFlying', 'MaxFlying', 'flying'),
    stat('MP0_WHEELIE_ABILITY', 'playerStatDriving', 'MaxDriving', 'driving'),
    stat('MP0_LUNG_CAPACITY', 'playerStatLungCapacity', 'MaxLungCapacity', 'lungcapacity'),
}

local function round(percent)
    return math.max(0, math.min(MpStats.FULL, percent)) // MpStats.STEP * MpStats.STEP
end

function MpStats.allowed()
    return Permissions.is_allowed(PERMISSION)
end

function MpStats.chosen(entry)
    return round(UserDefaults.get(entry.preference))
end

function MpStats.limit_of(entry)
    return math.max(0, math.min(MpStats.FULL, Config.value(entry.limit)))
end

local function apply()
    if not MpStats.allowed() then
        return
    end
    for _, entry in ipairs(MpStats.ALL) do
        StatSetInt(GetHashKey(entry.stat), math.min(MpStats.chosen(entry), MpStats.limit_of(entry)), false)
    end
end

function MpStats.set_chosen(entry, percent)
    if not MpStats.allowed() then
        return
    end
    UserDefaults.set(entry.preference, round(percent))
    apply()
end

function MpStats.init()
    local limits = {}
    for index, entry in ipairs(MpStats.ALL) do
        limits[index] = entry.limit
    end
    Permissions.on_changed(apply)
    Config.watch(limits, apply)
    apply()
end

return MpStats
