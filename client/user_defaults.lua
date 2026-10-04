-- Port of vMenu.Enhanced.Storage/UserDefaults.cs and UserDefault.cs: one
-- player's own preferences, persisted through client/storage.lua under
-- vmenu_default_<name>. Gating belongs to whoever applies a value, never here,
-- so a player re-granted a permission gets their choice back.

local Log = require('shared.log')
local Config = require('shared.config')
local Storage = require('client.storage')

local UserDefaults = {}

local KEY_PREFIX = 'vmenu_default_'

-- { name, type, default }, in upstream's UserDefaults.All order (the dump order).
-- Converted from upstream at the pinned release; port later changes by hand.
local DECLARED = {
    { 'defaultCharacterName', 'string', '' },
    { 'characterCreatorFitTorso', 'bool', true },
    { 'characterCreatorDisableAutoCamera', 'bool', false },
    { 'displayRightAlignMenu', 'bool', true },
    { 'language', 'string', 'en' },
    { 'miscDisableIdleCamera', 'bool', false },
    { 'miscDisableVehicleIdleCamera', 'bool', false },
    { 'displayDeathNotifications', 'bool', true },
    { 'displayJoinLeaveNotifications', 'bool', true },
    { 'displayMinimapAction', 'int', 1 },
    { 'displayMinimapZoom', 'int', 5 },
    { 'displayMinimapAlwaysOn', 'bool', false },
    { 'miscFingerPointing', 'bool', true },
    { 'displayShowPlayerBlips', 'bool', true },
    { 'displayShowOverheadNames', 'bool', true },
    { 'displaySeeNoClipPlayers', 'bool', true },
    { 'miscHideStaffAlerts', 'bool', false },
    { 'displaySpeedometer', 'int', 3 },
    { 'displaySpeedometerPosition', 'int', 0 },
    { 'displayShowLocation', 'bool', true },
    { 'displayShowCoordinates', 'bool', false },
    { 'displayVehicleHealth', 'bool', false },
    { 'playerGodMode', 'bool', false },
    { 'playerSuperJump', 'bool', false },
    { 'playerFastRun', 'bool', false },
    { 'playerFastSwim', 'bool', false },
    { 'playerStatShooting', 'int', 100 },
    { 'playerStatStrength', 'int', 100 },
    { 'playerStatStamina', 'int', 100 },
    { 'playerStatStealth', 'int', 100 },
    { 'playerStatFlying', 'int', 100 },
    { 'playerStatDriving', 'int', 100 },
    { 'playerStatLungCapacity', 'int', 100 },
    { 'playerUnlimitedOxygen', 'bool', false },
    { 'playerNoRagdoll', 'bool', false },
    { 'playerNoHelmet', 'bool', false },
    { 'playerInvisible', 'bool', false },
    { 'playerStayInVehicle', 'bool', false },
    { 'playerEveryoneIgnores', 'bool', false },
    { 'playerNeverWanted', 'bool', false },
    { 'playerWalkingStyle', 'string', '' },
    { 'playerClothingGlow', 'int', 0 },
    { 'vehicleGodMode', 'bool', false },
    { 'vehicleGodInvincible', 'bool', true },
    { 'vehicleGodEngine', 'bool', true },
    { 'vehicleGodVisual', 'bool', true },
    { 'vehicleGodStrongWheels', 'bool', true },
    { 'vehicleGodBulletproofTyres', 'bool', true },
    { 'vehicleGodRamp', 'bool', true },
    { 'vehicleGodAutoRepair', 'bool', false },
    { 'vehicleKeepClean', 'bool', false },
    { 'vehicleEngineAlwaysOn', 'bool', false },
    { 'vehiclePowerMultiplierEnabled', 'bool', false },
    { 'vehiclePowerMultiplier', 'int', 2 },
    { 'vehicleTorqueMultiplierEnabled', 'bool', false },
    { 'vehicleTorqueMultiplier', 'int', 2 },
    { 'vehicleHeliTurbulence', 'int', 100 },
    { 'vehiclePlaneTurbulence', 'int', 100 },
    { 'vehicleAnchorBoat', 'bool', false },
    { 'vehicleDeleteRemovedDoors', 'bool', false },
    { 'vehicleDefaultRadioEnabled', 'bool', false },
    { 'vehicleDefaultRadioStation', 'string', 'OFF' },
    { 'vehicleBlockedRadioStations', 'string', '' },
    { 'personalVehicleBlip', 'bool', true },
    { 'vehicleSpawnerSpawnInside', 'bool', true },
    { 'vehicleSpawnerReplacePrevious', 'bool', true },
    { 'propSpawnerNetworked', 'bool', true },
    { 'propSpawnerFrozen', 'bool', true },
    { 'propSpawnerSnapGround', 'bool', false },
    { 'propSpawnerDistance', 'int', 10 },
    { 'displayWeatherForecast', 'bool', true },
    { 'displayWeatherForecastStyle', 'int', 1 },
    { 'displayShowTime', 'bool', true },
    { 'displayLocationBlips', 'bool', true },
    { 'weaponsUnlimitedAmmo', 'bool', false },
    { 'weaponsNoReload', 'bool', false },
    { 'weaponsAutoEquipParachute', 'bool', false },
    { 'weaponsUnlimitedParachutes', 'bool', false },
    { 'weaponLoadoutOnRespawn', 'bool', false },
    { 'weaponLoadoutDefaultName', 'string', '' },
    { 'weaponsKeepOnPedChange', 'bool', true },
    { 'teleportKeyAction', 'int', 0 },
    { 'devVehicleDimensions', 'bool', false },
    { 'devPropDimensions', 'bool', false },
    { 'devPedDimensions', 'bool', false },
    { 'devEntityHandles', 'bool', false },
    { 'devEntityModels', 'bool', false },
    { 'devNetworkOwners', 'bool', false },
    { 'devDrawRadius', 'int', 20 },
    { 'devBoxOpacity', 'int', 10 },
    { 'ticksOverlay', 'bool', false },
    { 'pointingDebug', 'bool', false },
    { 'autoPilotVehicleProfile', 'string', '' },
    { 'autoPilotPlaneProfile', 'string', '' },
    { 'autoPilotBoatProfile', 'string', '' },
    { 'autoPilotHeliProfile', 'string', '' },
    { 'autoPilotStopAction', 'int', 0 },
    { 'autoPilotCruiseSpeed', 'int', 0 },
    { 'autoPilotPathSpacing', 'int', 25 },
    { 'autoPilotAutoRecord', 'bool', true },
}

local by_name = {}
for _, declared in ipairs(DECLARED) do
    by_name[declared[1]] = { name = declared[1], type = declared[2], default = declared[3] }
end

local listeners = {} -- name -> { fn, ... }

local function preference(name)
    return assert(by_name[name], ("'%s' is not a declared user default"):format(tostring(name)))
end

-- C#'s float.ToString("0.0###") for the dump.
local function describe(pref, value)
    if pref.type == 'string' then
        return "'" .. value .. "'"
    elseif pref.type == 'float' then
        local text = ('%.4f'):format(value):gsub('0+$', '')
        return text:sub(-1) == '.' and text .. '0' or text
    end
    return tostring(value)
end

-- Reading a preference that was never set writes its default, so a dump lists
-- everything vMenu knows about.
function UserDefaults.get(name)
    local pref = preference(name)
    local key = KEY_PREFIX .. name
    local stored = Storage.read(key, pref.type, Storage.INITIAL_VERSION)
    if stored ~= nil then
        return stored
    end
    Storage.write(key, pref.type, Storage.INITIAL_VERSION, pref.default)
    return pref.default
end

local function notify(name)
    for _, listener in ipairs(listeners[name] or {}) do
        local ok, err = pcall(listener)
        if not ok then
            Log.error(('[Defaults] A listener for %s threw: %s'):format(name, tostring(err)))
        end
    end
end

-- Persists value and notifies listeners, unless it already holds that value
-- or a newer vMenu's data refuses the write.
function UserDefaults.set(name, value)
    local pref = preference(name)
    if pref.type == 'int' then
        value = math.tointeger(value) or math.floor(value)
    end
    if UserDefaults.get(name) == value then
        return
    end
    if Storage.write(KEY_PREFIX .. name, pref.type, Storage.INITIAL_VERSION, value) then
        notify(name)
    end
end

-- Forgets the stored value, so the default applies again.
function UserDefaults.reset(name)
    preference(name)
    Storage.delete(KEY_PREFIX .. name)
    notify(name)
end

-- Raised when the stored value moves, never on a read.
function UserDefaults.on_changed(name, listener)
    preference(name)
    listeners[name] = listeners[name] or {}
    table.insert(listeners[name], listener)
end

function UserDefaults.declared()
    return DECLARED
end

-- Forgets every declared preference, and anything under the prefix no longer declared.
function UserDefaults.reset_all()
    for _, declared in ipairs(DECLARED) do
        UserDefaults.reset(declared[1])
    end
    for _, key in ipairs(Storage.keys(KEY_PREFIX)) do
        Storage.delete(key)
    end
    Log.info('[Defaults] Every stored preference has been reset.')
end

local function gated(dump)
    return function()
        local setting = 'vMenu.Enhanced.Debugging.Client'
        if not Config.value(setting) then
            Log.info(('[vMenu] This command only reports while %s is set to true.'):format(setting))
            return
        end
        dump()
    end
end

-- Call once from the client entrypoint, after Config.init.
function UserDefaults.init()
    RegisterCommand(
        'vmenu_defaults',
        gated(function()
            Log.info('[Defaults] Declared:')
            for _, declared in ipairs(DECLARED) do
                local pref = by_name[declared[1]]
                Log.info(
                    ('[Defaults]   %s = %s (default %s)'):format(
                        pref.name,
                        describe(pref, UserDefaults.get(pref.name)),
                        describe(pref, pref.default)
                    )
                )
            end
            Log.info('[Defaults] Stored:')
            for _, line in ipairs(Storage.describe(KEY_PREFIX)) do
                Log.info('[Defaults]   ' .. line)
            end
        end),
        false
    )
    RegisterCommand('vmenu_defaults_reset', gated(UserDefaults.reset_all), false)
end

return UserDefaults
