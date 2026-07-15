-- Port of SharedClasses/PermissionsManager.cs and SupplementaryPermissionManager.cs.
-- Contract: docs/contracts/permissions.md — ace names, parent-permission fallback,
-- and the staff-only / use_permissions gates must match upstream exactly.
--
local Config = require('shared.config')
local Json = require('shared.json_compat')

local Permissions = {}

-- GEN-BEGIN permission-list (run scripts/gen-permissions.ps1 to update)
Permissions.list = {
    'Everything',
    'DontKickMe',
    'DontBanMe',
    'NoClip',
    'Staff',
    'OPMenu',
    'OPAll',
    'OPTeleport',
    'OPWaypoint',
    'OPSpectate',
    'OPSendMessage',
    'OPIdentifiers',
    'OPSummon',
    'OPKill',
    'OPKick',
    'OPPermBan',
    'OPTempBan',
    'OPUnban',
    'OPViewBannedPlayers',
    'OPSeePrivateMessages',
    'POMenu',
    'POAll',
    'POGod',
    'POInvisible',
    'POFastRun',
    'POFastSwim',
    'POSuperjump',
    'PONoRagdoll',
    'PONeverWanted',
    'POSetWanted',
    'POClearBlood',
    'POSetBlood',
    'POIgnored',
    'POStayInVehicle',
    'POMaxHealth',
    'POMaxArmor',
    'POCleanPlayer',
    'PODryPlayer',
    'POWetPlayer',
    'POVehicleAutoPilotMenu',
    'POFreeze',
    'POScenarios',
    'POUnlimitedStamina',
    'VOMenu',
    'VOAll',
    'VOGod',
    'VOKeepClean',
    'VORepair',
    'VOWash',
    'VOEngine',
    'VODestroyEngine',
    'VOBikeSeatbelt',
    'VOSpeedLimiter',
    'VOChangePlate',
    'VOMod',
    'VOColors',
    'VOLiveries',
    'VOComponents',
    'VODoors',
    'VOWindows',
    'VOFreeze',
    'VOInvisible',
    'VOTorqueMultiplier',
    'VOPowerMultiplier',
    'VOFlip',
    'VOAlarm',
    'VOCycleSeats',
    'VOEngineAlwaysOn',
    'VONoSiren',
    'VONoHelmet',
    'VOLights',
    'VOFixOrDestroyTires',
    'VODelete',
    'VOUnderglow',
    'VOFlashHighbeamsOnHonk',
    'VODisableTurbulence',
    'VOAnchorBoat',
    'VOInfiniteFuel',
    'VOFlares',
    'VOPlaneBombs',
    'VOBypassExtraDamage',
    'VSMenu',
    'VSAll',
    'VSBypassRateLimit',
    'VSDisableReplacePrevious',
    'VSSpawnByName',
    'VSAddon',
    'VSCompacts',
    'VSSedans',
    'VSSUVs',
    'VSCoupes',
    'VSMuscle',
    'VSSportsClassic',
    'VSSports',
    'VSSuper',
    'VSMotorcycles',
    'VSOffRoad',
    'VSIndustrial',
    'VSUtility',
    'VSVans',
    'VSCycles',
    'VSBoats',
    'VSHelicopters',
    'VSPlanes',
    'VSService',
    'VSEmergency',
    'VSMilitary',
    'VSCommercial',
    'VSTrains',
    'VSOpenWheel',
    'SVMenu',
    'SVAll',
    'SVSpawn',
    'PVMenu',
    'PVAll',
    'PVToggleEngine',
    'PVToggleLights',
    'PVToggleStance',
    'PVKickPassengers',
    'PVLockDoors',
    'PVDoors',
    'PVSoundHorn',
    'PVToggleAlarm',
    'PVAddBlip',
    'PVExclusiveDriver',
    'PAMenu',
    'PAAll',
    'PACustomize',
    'PASpawnSaved',
    'PASpawnNew',
    'PAAddonPeds',
    'TOMenu',
    'TOAll',
    'TOFreezeTime',
    'TOSetTime',
    'WOMenu',
    'WOAll',
    'WODynamic',
    'WOBlackout',
    'WOVehBlackout',
    'WOSetWeather',
    'WORemoveClouds',
    'WORandomizeClouds',
    'WPMenu',
    'WPAll',
    'WPGetAll',
    'WPRemoveAll',
    'WPUnlimitedAmmo',
    'WPNoReload',
    'WPSpawn',
    'WPSpawnByName',
    'WPSetAllAmmo',
    'WPAPPistol',
    'WPAdvancedRifle',
    'WPAssaultRifle',
    'WPAssaultRifleMk2',
    'WPAssaultSMG',
    'WPAssaultShotgun',
    'WPBZGas',
    'WPBall',
    'WPBat',
    'WPBattleAxe',
    'WPBottle',
    'WPBullpupRifle',
    'WPBullpupRifleMk2',
    'WPBullpupShotgun',
    'WPCarbineRifle',
    'WPCarbineRifleMk2',
    'WPCombatMG',
    'WPCombatMGMk2',
    'WPCombatPDW',
    'WPCombatPistol',
    'WPCompactGrenadeLauncher',
    'WPCompactRifle',
    'WPCrowbar',
    'WPDagger',
    'WPDoubleAction',
    'WPDoubleBarrelShotgun',
    'WPFireExtinguisher',
    'WPFirework',
    'WPFlare',
    'WPFlareGun',
    'WPFlashlight',
    'WPGolfClub',
    'WPGrenade',
    'WPGrenadeLauncher',
    'WPGrenadeLauncherSmoke',
    'WPGusenberg',
    'WPHammer',
    'WPHatchet',
    'WPHeavyPistol',
    'WPHeavyShotgun',
    'WPHeavySniper',
    'WPHeavySniperMk2',
    'WPHomingLauncher',
    'WPKnife',
    'WPKnuckleDuster',
    'WPMG',
    'WPMachete',
    'WPMachinePistol',
    'WPMarksmanPistol',
    'WPMarksmanRifle',
    'WPMarksmanRifleMk2',
    'WPMicroSMG',
    'WPMiniSMG',
    'WPMinigun',
    'WPMolotov',
    'WPMusket',
    'WPNightVision',
    'WPNightstick',
    'WPParachute',
    'WPPetrolCan',
    'WPPipeBomb',
    'WPPistol',
    'WPPistol50',
    'WPPistolMk2',
    'WPPoolCue',
    'WPProximityMine',
    'WPPumpShotgun',
    'WPPumpShotgunMk2',
    'WPRPG',
    'WPRailgun',
    'WPRevolver',
    'WPRevolverMk2',
    'WPSMG',
    'WPSMGMk2',
    'WPSNSPistol',
    'WPSNSPistolMk2',
    'WPSawnOffShotgun',
    'WPSmokeGrenade',
    'WPSniperRifle',
    'WPSnowball',
    'WPSpecialCarbine',
    'WPSpecialCarbineMk2',
    'WPStickyBomb',
    'WPStunGun',
    'WPSweeperShotgun',
    'WPSwitchBlade',
    'WPUnarmed',
    'WPVintagePistol',
    'WPWrench',
    'WPPlasmaPistol',
    'WPPlasmaCarbine',
    'WPPlasmaMinigun',
    'WPStoneHatchet',
    'WPCeramicPistol',
    'WPNavyRevolver',
    'WPHazardCan',
    'WPPericoPistol',
    'WPMilitaryRifle',
    'WPCombatShotgun',
    'WPEMPLauncher',
    'WPHeavyRifle',
    'WPFertilizerCan',
    'WPStunGunMP',
    'WPPrecisionRifle',
    'WPTacticalRifle',
    'WPPistolXM3',
    'WPCandyCane',
    'WPRailgunXM3',
    'WPAcidPackage',
    'WPTecPistol',
    'WPBattleRifle',
    'WPSnowLauncher',
    'WPHackingDevice',
    'WPStunRod',
    'WPNewspaper',
    'WLMenu',
    'WLAll',
    'WLEquip',
    'WLEquipOnRespawn',
    'MSAll',
    'MSClearArea',
    'MSTeleportToWp',
    'MSTeleportToCoord',
    'MSShowCoordinates',
    'MSShowLocation',
    'MSJoinQuitNotifs',
    'MSDeathNotifs',
    'MSNightVision',
    'MSThermalVision',
    'MSLocationBlips',
    'MSPlayerBlips',
    'MSOverheadNames',
    'MSTeleportLocations',
    'MSTeleportSaveLocation',
    'MSConnectionMenu',
    'MSRestoreAppearance',
    'MSRestoreWeapons',
    'MSDriftMode',
    'MSEntitySpawner',
    'MSDevTools',
    'VCMenu',
    'VCAll',
    'VCEnable',
    'VCShowSpeaker',
    'VCStaffChannel',
}
-- GEN-END permission-list

-- Supplementary (model-whitelist) permissions, checked separately upstream.
Permissions.supplementary_list = { 'VWAll', 'PWAll', 'WWAll' }

-- Server startup (MainServer.SetupAddonPerms) extends the list with one
-- permission per whitelisted model from config/model-whitelists.json.
function Permissions.register_supplementary(name)
    for _, existing in ipairs(Permissions.supplementary_list) do
        if existing == name then
            return
        end
    end
    Permissions.supplementary_list[#Permissions.supplementary_list + 1] = name
end

-- Category expansion used by GetAceName.
local CATEGORY_PREFIXES = {
    OP = 'OnlinePlayers',
    PO = 'PlayerOptions',
    VO = 'VehicleOptions',
    VS = 'VehicleSpawner',
    SV = 'SavedVehicles',
    PV = 'PersonalVehicle',
    PA = 'PlayerAppearance',
    TO = 'TimeOptions',
    WO = 'WeatherOptions',
    WP = 'WeaponOptions',
    WL = 'WeaponLoadouts',
    MS = 'MiscSettings',
    VC = 'VoiceChat',
}

local SUPPLEMENTARY_PREFIXES = {
    VW = 'VehicleSpawner.WhitelistedModels',
    PW = 'PlayerAppearance.WhitelistedModels',
    WW = 'WeaponOptions.WhitelistedModels',
}

-- vMenu.<Category>.<Rest> for the 13 two-letter categories, vMenu.<Name> otherwise.
function Permissions.ace_name(permission)
    local category = CATEGORY_PREFIXES[permission:sub(1, 2)]
    if category then
        return ('vMenu.%s.%s'):format(category, permission:sub(3))
    end
    return 'vMenu.' .. permission
end

function Permissions.supplementary_ace_name(permission)
    local category = SUPPLEMENTARY_PREFIXES[permission:sub(1, 2)]
    if category then
        return ('vMenu.%s.%s'):format(category, permission:sub(3))
    end
    return 'vMenu.' .. permission
end

local function starts_with_category(permission)
    local prefix = permission:sub(1, 2)
    return prefix:upper() == prefix
end

local list_set = nil
local function is_known(permission)
    if not list_set then
        list_set = {}
        for _, name in ipairs(Permissions.list) do
            list_set[name] = true
        end
    end
    return list_set[permission] == true
end

local supplementary_set = { VWAll = true, PWAll = true, WWAll = true }

-- Upstream GetPermissionAndParentPermissions: every permission is implied by
-- Everything; category members are additionally implied by their <XX>All —
-- except the All and Menu members themselves (quirk preserved: <XX>All does
-- NOT imply <XX>Menu). The <XX>All parent is only added when that member
-- actually exists in the enum (upstream filters against Enum.GetValues).
function Permissions.parents(permission)
    local list = { 'Everything', permission }
    if starts_with_category(permission) then
        local rest = permission:sub(3)
        if rest ~= 'All' and rest ~= 'Menu' then
            local all = permission:sub(1, 2) .. 'All'
            if is_known(all) then
                list[#list + 1] = all
            end
        end
    end
    return list
end

-- Supplementary variant only excludes the All suffix, and filters against the
-- 3-member supplementary list (so VW<model> perms gain VWAll as a parent).
function Permissions.supplementary_parents(permission)
    local list = { 'Everything', permission }
    if starts_with_category(permission) and permission:sub(3) ~= 'All' then
        local all = permission:sub(1, 2) .. 'All'
        if supplementary_set[all] then
            list[#list + 1] = all
        end
    end
    return list
end

-- Permissions that stay denied when vmenu_use_permissions is false
-- (everyone gets everything else). Upstream: SetPermissionsForPlayer.
Permissions.denied_without_permission_system = {
    'Everything',
    'OPAll',
    'OPKick',
    'OPKill',
    'OPPermBan',
    'OPTempBan',
    'OPUnban',
    'OPIdentifiers',
    'OPViewBannedPlayers',
}

-- ---------------------------------------------------------------------------
-- Server side: ACE collection (PermissionsManager server region)
-- ---------------------------------------------------------------------------

function Permissions.is_allowed_server(permission, player_handle)
    if player_handle == nil or not DoesPlayerExist(tostring(player_handle)) then
        return false
    end
    for _, parent in ipairs(Permissions.parents(permission)) do
        if IsPlayerAceAllowed(tostring(player_handle), Permissions.ace_name(parent)) then
            return true
        end
    end
    return false
end

function Permissions.is_supplementary_allowed_server(permission, player_handle)
    if player_handle == nil or not DoesPlayerExist(tostring(player_handle)) then
        return false
    end
    for _, parent in ipairs(Permissions.supplementary_parents(permission)) do
        if IsPlayerAceAllowed(tostring(player_handle), Permissions.supplementary_ace_name(parent)) then
            return true
        end
    end
    return false
end

-- Builds the { [name] = bool } table pushed to a client. With the permission
-- system disabled everyone gets everything, except the denylist entries which
-- are OMITTED entirely (not false) — upstream skips the dict.Add.
-- The upstream dev backdoor (vMenu.Dev + hardcoded identifier) is intentionally
-- not ported; see docs/contracts/permissions.md.
function Permissions.collect_for_player(player_handle)
    local perms = {}
    if not Config.get_bool('vmenu_use_permissions') then
        local denied = {}
        for _, name in ipairs(Permissions.denied_without_permission_system) do
            denied[name] = true
        end
        for _, name in ipairs(Permissions.list) do
            if not denied[name] then
                perms[name] = true
            end
        end
    else
        for _, name in ipairs(Permissions.list) do
            perms[name] = Permissions.is_allowed_server(name, player_handle)
        end
    end
    return perms
end

function Permissions.collect_supplementary_for_player(player_handle)
    local perms = {}
    for _, name in ipairs(Permissions.supplementary_list) do
        perms[name] = Permissions.is_supplementary_allowed_server(name, player_handle)
    end
    return perms
end

-- ---------------------------------------------------------------------------
-- Client side: receive + resolve (PermissionsManager client region)
-- ---------------------------------------------------------------------------

Permissions.are_setup = false
Permissions.supplementary_are_setup = false

local granted = {}
local supplementary_granted = {}
-- Upstream's allowedPerms memo is a static that persists across permission
-- pushes; only positive entries short-circuit. Quirk preserved.
local memo = {}
local supplementary_memo = {}

function Permissions.set_from_json(payload)
    granted = Json.decode(payload) or {}
    Permissions.are_setup = true
end

function Permissions.set_supplementary_from_json(payload)
    supplementary_granted = Json.decode(payload) or {}
    Permissions.supplementary_are_setup = true
end

function Permissions.is_allowed(permission, check_anyway)
    if Permissions.are_setup or check_anyway then
        -- Staff-only gate: with vmenu_menu_staff_only, non-staff get nothing.
        local staff_allowed = granted['Staff'] == true or granted['Everything'] == true
        if Config.get_bool('vmenu_menu_staff_only') and not staff_allowed then
            return false
        end

        if memo[permission] then
            return true
        end
        if memo[permission] == nil then
            memo[permission] = false
        end

        for _, parent in ipairs(Permissions.parents(permission)) do
            if granted[parent] == true then
                memo[permission] = true
                return true
            end
        end
    end
    return false
end

local SUPPLEMENTARY_FALLBACK = { VW = 'VSAll', PW = 'PAAll', WW = 'WPAll' }

function Permissions.is_supplementary_allowed(permission, check_anyway)
    if Permissions.supplementary_are_setup or check_anyway then
        if supplementary_memo[permission] then
            return true
        end
        if supplementary_memo[permission] == nil then
            supplementary_memo[permission] = false
        end

        for _, parent in ipairs(Permissions.supplementary_parents(permission)) do
            if supplementary_granted[parent] == true then
                supplementary_memo[permission] = true
                return true
            end
        end
    end
    -- Upstream fallback (outside the setup gate): whitelist categories defer
    -- to the matching main-permission All when no supplementary grant exists.
    local fallback = SUPPLEMENTARY_FALLBACK[permission:sub(1, 2)]
    if fallback then
        local allowed = Permissions.is_allowed(fallback)
        supplementary_memo[permission] = allowed
        return allowed
    end
    return false
end

return Permissions
