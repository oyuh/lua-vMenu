-- Ports of vMenu.Enhanced.Menus/World/WorldBlackout.cs and WorldSnow.cs: the
-- city lights and the snow on the ground, as the world state says.

local WeatherCycle = require('shared.world.weather_cycle')
local Ticks = require('menu.ticks')
local Natives = require('client.natives')
local State = require('client.menus.world.state')

local Effects = {}

local BLACKOUT_INTERVAL_MS = 1000
local SNOW_INTERVAL_MS = 1000
local SNOW_ASSET = 'core_snow'

-- Blackout ---------------------------------------------------------------------------

local applied_blackout = 'off'

local function apply_blackout()
    local mode = State.effective_blackout()
    if mode == applied_blackout then
        return
    end
    applied_blackout = mode
    SetArtificialLightsState(mode ~= 'off')
    SetArtificialLightsStateAffectsVehicles(mode == 'all')
end

-- Snow -------------------------------------------------------------------------------

local snow_applied, snow_requested = false, false

function Effects.snow_wanted()
    return State.weather_enabled() and State.snow_wanted()
end

local function set_snow_effects(on)
    Natives.force_global_snow_fx(on)
    Natives.use_snow_foot_vfx_when_unsheltered(on)
    Natives.use_snow_wheel_vfx_when_unsheltered(on)
    Natives.foot_vfx_set_override_ice_with_snow(on)
end

local function drop_snow_asset()
    if snow_requested then
        snow_requested = false
        RemoveNamedPtfxAsset(SNOW_ASSET)
    end
end

local function apply_snow()
    local wanted = Effects.snow_wanted()
    if wanted == snow_applied then
        return
    end
    snow_applied = wanted
    set_snow_effects(wanted)
    if wanted and not snow_requested then
        snow_requested = true
        RequestNamedPtfxAsset(SNOW_ASSET)
    elseif not wanted then
        drop_snow_asset()
    end
end

local function release_snow()
    snow_applied = false
    set_snow_effects(false)
    drop_snow_asset()
end

function Effects.init()
    Ticks.register('World.Blackout', apply_blackout, {
        rate = BLACKOUT_INTERVAL_MS,
        condition = function()
            return State.blackout == 'dynamic' and WeatherCycle.has_scheduled_blackouts() and State.weather_enabled()
        end,
    })
    Ticks.register('World.Snow', apply_snow, {
        rate = SNOW_INTERVAL_MS,
        condition = State.weather_enabled,
        on_stopped = release_snow,
    })
    State.on_changed(function()
        Ticks.reevaluate()
        apply_blackout()
        apply_snow()
    end)
    apply_blackout()
end

return Effects
