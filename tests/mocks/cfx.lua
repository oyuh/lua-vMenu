-- In-process fake of the CitizenFX runtime for busted tests.
-- Install one instance per test (before requiring modules under test),
-- uninstall in teardown. Grows alongside the modules being ported;
-- semantics deliberately mimic the real runtime, quirks included.

local Cfx = {}
Cfx.__index = Cfx

local INSTALLED_GLOBALS = {
    'GetConvar',
    'GetConvarInt',
    'GetResourceMetadata',
    'GetCurrentResourceName',
    'LoadResourceFile',
    'SaveResourceFile',
    'IsDuplicityVersion',
    'IsPlayerAceAllowed',
    'DoesPlayerExist',
    'SetResourceKvp',
    'GetResourceKvpString',
    'DeleteResourceKvp',
    'StartFindKvp',
    'FindKvp',
    'EndFindKvp',
    'RegisterNetEvent',
    'AddEventHandler',
    'TriggerEvent',
    'TriggerServerEvent',
    'TriggerClientEvent',
    -- server runtime
    'SetConvarReplicated',
    'GetPlayers',
    'GetPlayerName',
    'GetNumPlayerIdentifiers',
    'GetPlayerIdentifier',
    'DropPlayer',
    'CancelEvent',
    'Player',
    'GetGameTimer',
    'CreateThread',
    'Wait',
    'RegisterCommand',
    'GlobalState',
    'GetPlayerPed',
    'GetEntityCoords',
    'DoesEntityExist',
    'vector3',
    -- typed kvp + keymapping + misc client runtime
    'SetResourceKvpInt',
    'GetResourceKvpInt',
    'SetResourceKvpFloat',
    'GetResourceKvpFloat',
    'RegisterKeyMapping',
    'GetHashKey',
    'LocalPlayer',
    'Entity',
}

-- Client-side game natives faked as recording no-ops. Each entry is
-- { name, default } where default may be a plain value or a function of the
-- call args. Calls are recorded in mock.native_calls for assertions.
local NATIVE_DEFAULTS = {
    -- notifications / text
    { 'SetNotificationTextEntry' },
    { 'AddTextComponentSubstringPlayerName' },
    { 'DrawNotification' },
    { 'SetNotificationMessage' },
    { 'BeginTextCommandPrint' },
    { 'EndTextCommandPrint' },
    { 'BeginTextCommandDisplayHelp' },
    { 'EndTextCommandDisplayHelp' },
    { 'IsHelpMessageBeingDisplayed', false },
    { 'ClearAllHelpMessages' },
    { 'AddTextEntry' },
    -- identity instead of 'NULL' so label-keyed dicts (VehicleClasses) keep
    -- distinct keys in specs
    {
        'GetLabelText',
        function(label)
            return label
        end,
    },
    { 'DisplayHelpTextThisFrame' },
    { 'ClearBrief' },
    { 'SetRichPresence' },
    -- stats / pvp
    { 'StatSetInt' },
    { 'StatSetFloat' },
    { 'NetworkSetFriendlyFireOption' },
    { 'SetCanAttackFriendly' },
    -- local player / players
    { 'PlayerId', 0 },
    { 'PlayerPedId', 900 },
    { 'IsPedInAnyVehicle', false },
    { 'GetVehiclePedIsIn', 0 },
    { 'GetPedInVehicleSeat', 0 },
    { 'NetworkIsPlayerActive', true },
    {
        'GetActivePlayers',
        function()
            return {}
        end,
    },
    { 'GetPlayerFromServerId', -1 },
    { 'GetPlayerServerId', 0 },
    -- world / entities
    { 'SetEntityHealth' },
    { 'ClearAreaOfEverything' },
    { 'ForceSocialClubUpdate' },
    -- clouds / snow / lights
    { 'ClearCloudHat' },
    { 'SetCloudHatOpacity' },
    { 'SetCloudHatTransition' },
    { 'ForceSnowPass' },
    { 'SetForceVehicleTrails' },
    { 'SetForcePedFootstepsTracks' },
    { 'HasNamedPtfxAssetLoaded', true },
    { 'RequestNamedPtfxAsset' },
    { 'UseParticleFxAssetNextCall' },
    { 'RemoveNamedPtfxAsset' },
    { 'SetArtificialLightsState' },
    { 'SetArtificialLightsStateAffectsVehicles' },
    -- weather / time sync
    { 'GetNextWeatherType', 0 },
    { 'SetWeatherTypeOvertimePersist' },
    { 'NetworkOverrideClockTime' },
    -- spawn / screen state
    { 'IsScreenFadedIn', true },
    { 'IsPlayerSwitchInProgress', false },
    { 'IsPauseMenuActive', false },
    { 'GetIsLoadingScreenActive', false },
    -- ped headshots (private messages)
    { 'RegisterPedheadshot', 1 },
    { 'IsPedheadshotReady', true },
    { 'IsPedheadshotValid', true },
    { 'GetPedheadshotTxdString', 'headshot_txd' },
    { 'UnregisterPedheadshot' },
    -- drawing / alignment
    { 'GetAspectRatio', 1.7777778 },
    -- weapons / models (data layer)
    { 'DoesWeaponTakeWeaponComponent', false },
    {
        'GetMaxAmmo',
        function()
            return true, 250
        end,
    },
    { 'GetEntityModel', 0 },
    { 'IsThisModelABike', false },
    { 'IsThisModelABoat', false },
    { 'IsThisModelAHeli', false },
    { 'IsThisModelAPlane', false },
    -- onscreen keyboard (default: "cancelled" so get_user_input returns nil
    -- instead of spinning forever in specs)
    { 'DisplayOnscreenKeyboard' },
    { 'UpdateOnscreenKeyboard', 2 },
    { 'GetOnscreenKeyboardResult', '' },
    -- recording / editor
    { 'IsRecording', false },
    { 'StartRecording' },
    { 'StopRecordingAndSaveClip' },
    { 'ActivateFrontendMenu' },
    { 'BeginTakeHighQualityPhoto' },
    { 'SaveHighQualityPhoto' },
    { 'FreeMemoryForHighQualityPhoto' },
    { 'ActivateRockstarEditor' },
    { 'AddTextEntryByHash' },
    { 'DoScreenFadeIn' },
    { 'DoScreenFadeOut' },
    { 'IsScreenFadedOut', true },
    -- session / connection
    { 'NetworkSessionEnd' },
    { 'NetworkSessionHost' },
    { 'NetworkIsSessionActive', false },
    { 'NetworkIsHost', false },
    { 'ExecuteCommand' },
    -- hud / vision / timecycle
    { 'DisplayHud' },
    { 'DisplayRadar' },
    { 'SetNightvision' },
    { 'SetSeethrough' },
    { 'SetTimecycleModifier' },
    { 'SetTimecycleModifierStrength' },
    { 'ClearTimecycleModifier' },
    -- blips
    { 'AddBlipForCoord', 1 },
    { 'SetBlipSprite' },
    { 'BeginTextCommandSetBlipName' },
    { 'EndTextCommandSetBlipName' },
    { 'SetBlipColour' },
    { 'SetBlipAsShortRange' },
    { 'DoesBlipExist', false },
    { 'RemoveBlip' },
    { 'IsWaypointActive', false },
    { 'GetFirstBlipInfoId', 0 },
    {
        'GetBlipInfoIdCoord',
        function()
            return { x = 0.0, y = 0.0, z = 0.0 }
        end,
    },
    -- player state / stats (player options)
    { 'GetPlayerWantedLevel', 0 },
    { 'SetPlayerWantedLevel' },
    { 'SetPlayerWantedLevelNow' },
    { 'SetMaxWantedLevel' },
    { 'SetRunSprintMultiplierForPlayer' },
    { 'SetSwimMultiplierForPlayer' },
    { 'SetEveryoneIgnorePlayer' },
    { 'SetPoliceIgnorePlayer' },
    { 'SetPlayerCanBeHassledByGangs' },
    { 'SetEntityVisible' },
    { 'IsEntityVisible', true },
    { 'FreezeEntityPosition' },
    { 'ApplyPedDamagePack' },
    { 'SetPedArmour' },
    { 'ClearPedBloodDamage' },
    { 'ResetPedVisibleDamage' },
    { 'ClearPedDamageDecalByZone' },
    { 'GetEntityMaxHealth', 200 },
    { 'SetPedWetnessHeight' },
    -- scenarios / tasks
    { 'IsPedRunning', false },
    { 'IsEntityDead', false },
    { 'IsPlayerInCutscene', false },
    { 'IsPedFalling', false },
    { 'IsPedRagdoll', false },
    { 'IsPedOnFoot', true },
    { 'NetworkIsInSpectatorMode', false },
    { 'GetEntitySpeed', 0.0 },
    {
        'GetOffsetFromEntityInWorldCoords',
        function()
            return { x = 0.0, y = 0.0, z = 0.0 }
        end,
    },
    { 'GetEntityHeading', 0.0 },
    { 'TaskStartScenarioAtPosition' },
    { 'TaskStartScenarioInPlace' },
    { 'ClearPedTasks' },
    { 'ClearPedSecondaryTask' },
    { 'ClearPedTasksImmediately' },
    { 'SetDriveTaskDrivingStyle' },
    { 'SetDriverAbility' },
    { 'SetDriverAggressiveness' },
    { 'TaskVehicleDriveToCoordLongrange' },
    { 'TaskVehicleDriveWander' },
    { 'TaskVehiclePark' },
    { 'SetVehicleHalt' },
    {
        'GetNthClosestVehicleNode',
        function()
            return false, { x = 0.0, y = 0.0, z = 0.0 }
        end,
    },
    -- suicide anims
    { 'RequestAnimDict' },
    { 'HasAnimDictLoaded', true },
    { 'RemoveAnimDict' },
    { 'HasPedGotWeapon', false },
    { 'SetCurrentPedWeapon' },
    { 'SetPedDropsWeaponsWhenDead' },
    { 'GiveWeaponToPed' },
    { 'TaskPlayAnim' },
    { 'GetEntityAnimCurrentTime', 1.0 },
    { 'HasAnimEventFired', false },
    { 'ClearEntityLastDamageEntity' },
    { 'SetPedShootsAtCoord' },
    -- vehicle spawning
    { 'GetVehicleClassFromName', 0 },
    { 'IsModelInCdimage', true },
    { 'IsModelAVehicle', true },
    { 'RequestModel' },
    { 'HasModelLoaded', true },
    { 'SetModelAsNoLongerNeeded' },
    { 'GetDisplayNameFromVehicleModel', 'NULL' },
    { 'GetVehicleModelEstimatedMaxSpeed', 0.0 },
    { 'GetVehicleModelAcceleration', 0.0 },
    { 'GetVehicleModelMaxBraking', 0.0 },
    { 'GetVehicleModelMaxTraction', 0.0 },
    { 'GetVehicleModelMaxSpeed', 0.0 },
    { 'CreateVehicle', 2000 },
    { 'DeleteVehicle' },
    { 'SetEntityAsMissionEntity' },
    { 'SetVehicleNeedsToBeHotwired' },
    { 'SetVehicleHasBeenOwnedByPlayer' },
    { 'SetVehicleIsStolen' },
    { 'SetVehicleIsWanted' },
    { 'SetVehicleEngineOn' },
    { 'SetPedIntoVehicle' },
    { 'GetVehicleClass', 0 },
    { 'GetEntityHeightAboveGround', 0.0 },
    { 'SetVehicleOnGroundProperly' },
    { 'IsThisModelATrain', false },
    { 'SetVehicleForwardSpeed' },
    { 'GetVehicleCurrentRpm', 0.0 },
    { 'SetVehicleCurrentRpm' },
    {
        'GetEntitySpeedVector',
        function()
            return { x = 0.0, y = 0.0, z = 0.0 }
        end,
    },
    { 'GetVehicleNumberOfPassengers', 0 },
    { 'IsVehicleSeatFree', true },
    { 'IsVehicleDriveable', true },
    { 'DoesPlayerVehHaveRadio', false },
    { 'IsRadioRetuning', false },
    { 'SetVehRadioStation' },
    { 'GetRadioStationName', '' },
    { 'SetHeliBladesFullSpeed' },
    { 'GetPlayersLastVehicle', 0 },
    -- vehicle mods / colors (VehicleInfo capture + application)
    { 'GetNumVehicleMods', 0 },
    { 'GetVehicleMod', -1 },
    { 'SetVehicleModKit' },
    { 'ToggleVehicleMod' },
    { 'SetVehicleWheelType' },
    { 'GetVehicleWheelType', 0 },
    { 'SetVehicleMod' },
    { 'GetVehicleModVariation', false },
    { 'IsToggleModOn', false },
    { 'SetVehicleTyreSmokeColor' },
    {
        'GetVehicleTyreSmokeColor',
        function()
            return 0, 0, 0
        end,
    },
    { 'SetVehicleLivery' },
    { 'GetVehicleLivery', -1 },
    {
        'GetVehicleColours',
        function()
            return 0, 0
        end,
    },
    { 'SetVehicleColours' },
    {
        'GetVehicleExtraColours',
        function()
            return 0, 0
        end,
    },
    { 'SetVehicleExtraColours' },
    { 'SetVehicleCustomPrimaryColour' },
    { 'SetVehicleCustomSecondaryColour' },
    { 'ClearVehicleCustomPrimaryColour' },
    { 'ClearVehicleCustomSecondaryColour' },
    { 'GetIsVehiclePrimaryColourCustom', false },
    { 'GetIsVehicleSecondaryColourCustom', false },
    {
        'GetVehicleCustomPrimaryColour',
        function()
            return 0, 0, 0
        end,
    },
    {
        'GetVehicleCustomSecondaryColour',
        function()
            return 0, 0, 0
        end,
    },
    { 'SetVehicleModColor_1' },
    { 'SetVehicleModColor_2' },
    { 'SetVehicleInteriorColour' },
    { 'GetVehicleInteriorColour', 0 },
    { 'SetVehicleDashboardColour' },
    { 'GetVehicleDashboardColour', 0 },
    { 'SetVehicleNumberPlateText' },
    { 'GetVehicleNumberPlateText', '' },
    { 'SetVehicleNumberPlateTextIndex' },
    { 'GetVehicleNumberPlateTextIndex', 0 },
    { 'SetVehicleWindowTint' },
    { 'GetVehicleWindowTint', 0 },
    { 'SetVehicleTyresCanBurst' },
    { 'GetVehicleTyresCanBurst', true },
    { 'SetVehicleEnveffScale' },
    { 'GetVehicleEnveffScale', 0.0 },
    { 'SetVehicleHeadlightsColour' },
    { 'GetVehicleHeadlightsColour', -1 },
    { 'SetVehicleXenonLightsCustomColor' },
    { 'ClearVehicleXenonLightsCustomColor' },
    {
        'GetVehicleXenonLightsCustomColor',
        function()
            return false, 0, 0, 0
        end,
    },
    { 'SetVehicleNeonLightsColour' },
    {
        'GetVehicleNeonLightsColour',
        function()
            return 255, 255, 255
        end,
    },
    { 'SetVehicleNeonLightEnabled' },
    { 'IsVehicleNeonLightEnabled', false },
    { 'DoesExtraExist', false },
    { 'IsVehicleExtraTurnedOn', false },
    { 'SetVehicleExtra' },
    -- vehicle options menu (repair/wash/lights/tires/engine/plates/liveries)
    { 'SetVehicleFixed' },
    { 'GetVehicleDirtLevel', 0.0 },
    { 'SetVehicleDirtLevel' },
    { 'SetVehicleDoorsShut' },
    { 'GetVehicleIndicatorLights', 0 },
    { 'SetVehicleIndicatorLights' },
    { 'IsVehicleInteriorLightOn', false },
    { 'SetVehicleInteriorlight' },
    { 'IsVehicleSearchlightOn', false },
    { 'SetVehicleSearchlight' },
    { 'SetEntityMaxSpeed' },
    { 'IsVehicleTyreBurst', false },
    { 'SetVehicleTyreFixed' },
    { 'SetVehicleTyreBurst' },
    { 'SetVehicleEngineHealth' },
    { 'GetVehicleEngineHealth', 1000.0 },
    { 'GetVehicleBodyHealth', 1000.0 },
    { 'GetVehicleLiveryCount', 0 },
    { 'GetLiveryName', '' },
    { 'GetGameBuildNumber', 2802 },
    { 'GetDriftTyresEnabled', false },
    { 'SetDriftTyresEnabled' },
    { 'RemoveVehicleMod' },
    { 'ShouldUseMetricMeasurements', false },
    { 'AreAnyVehicleSeatsFree', false },
    { 'SetVehicleEnginePowerMultiplier' },
    { 'SetPlaneTurbulenceMultiplier' },
    { 'SetHeliTurbulenceScalar' },
    { 'CanAnchorBoatHere', false },
    { 'SetBoatAnchor' },
    { 'SetBoatFrozenWhenAnchored' },
    { 'SetForcedBoatLocationWhenAnchored' },
    { 'RollUpWindow' },
    { 'RollDownWindow' },
    { 'IsThisModelABicycle', false },
    { 'DisableVehicleImpactExplosionActivation' },
    { 'SetVehicleRadioEnabled' },
    { 'GetNumberOfVehicleColours', 0 },
    { 'GetVehicleColourCombination', -1 },
    { 'SetVehicleColourCombination' },
    -- noclip / entity spawner
    { 'IsModelValid', true },
    { 'IsModelAPed', false },
    { 'CreatePed', 1500 },
    { 'DeleteEntity' },
    { 'PlaceObjectOnGroundProperly' },
    { 'ResetEntityAlpha' },
    { 'SetEntityAlpha' },
    { 'SetEntityCollision' },
    { 'SetEntityInvincible' },
    { 'GetFrameTime', 0.016 },
    { 'IsHudHidden', false },
    { 'SetEntityVelocity' },
    { 'SetEntityRotation' },
    { 'SetEntityCoordsNoOffset' },
    { 'GetGameplayCamRelativeHeading', 0.0 },
    { 'SetLocalPlayerVisibleLocally' },
    {
        'GetGameplayCamRot',
        function()
            return vector3(0.0, 0.0, 0.0)
        end,
    },
    {
        'GetGameplayCamCoord',
        function()
            return vector3(0.0, 0.0, 0.0)
        end,
    },
    { 'StartExpensiveSynchronousShapeTestLosProbe', 1 },
    -- ped appearance (SetPlayerSkin / SavePed / customization menus)
    { 'SetPlayerModel' },
    { 'GetEntityHealth', 200 },
    { 'GetPedMaxHealth', 200 },
    { 'SetPedMaxHealth' },
    { 'GetPedArmour', 0 },
    { 'GetPlayerMaxArmour', 100 },
    { 'SetPlayerMaxArmour' },
    { 'SetPedComponentVariation' },
    { 'SetPedDefaultComponentVariation' },
    { 'ClearAllPedProps' },
    { 'ClearPedDecorations' },
    { 'ClearPedFacialDecorations' },
    { 'ClearPedProp' },
    { 'SetPedPropIndex' },
    { 'GetPedDrawableVariation', 0 },
    { 'GetPedTextureVariation', 0 },
    { 'GetPedPropIndex', -1 },
    { 'GetPedPropTextureIndex', 0 },
    { 'GetNumberOfPedDrawableVariations', 0 },
    { 'GetNumberOfPedTextureVariations', 0 },
    { 'GetNumberOfPedPropDrawableVariations', 0 },
    { 'GetNumberOfPedPropTextureVariations', 0 },
    { 'SetPedHeadBlendData' },
    { 'HasPedHeadBlendFinished', true },
    { 'ClearPedAlternateMovementAnim' },
    { 'ClearPedAlternateWalkAnim' },
    { 'SetPedAlternateMovementAnim' },
    { 'IsPedModel', false },
    { 'IsEntityInWater', false },
    { 'GetHashNameForProp', 0 },
    { 'GetShopPedApparelVariantPropCount', 0 },
    -- functions controller ticks
    { 'SetPedCanLosePropsOnDamage' },
    { 'SetSuperJumpThisFrame' },
    { 'SetPedCanRagdoll' },
    { 'ClearPlayerWantedLevel' },
    { 'GetMaxWantedLevel', 0 },
    { 'SetPedCanBeDraggedOut' },
    { 'SetPedCanBeShotInVehicle' },
    { 'SetPedCanBeKnockedOffVehicle' },
    { 'SetRampVehicleReceivesRampDamage' },
    { 'IsVehicleDamaged', false },
    { 'RemoveDecalsFromVehicle' },
    { 'SetVehicleCanBeVisiblyDamaged' },
    { 'SetVehicleEngineCanDegrade' },
    { 'SetVehicleWheelsCanBreak' },
    { 'SetVehicleHasStrongAxles' },
    { 'SetEntityProofs' },
    { 'GetIsDoorValid', false },
    { 'SetVehicleDoorBreakable' },
    { 'SetVehicleEngineTorqueMultiplier' },
    { 'GetVehicleHandlingFloat', 100.0 },
    { 'GetVehicleFuelLevel', 50.0 },
    { 'DecorIsRegisteredAsType', true },
    { 'DecorSetFloat' },
    { 'DecorSetInt' },
    { 'DecorGetInt', 0 },
    { 'DecorExistOn', false },
    { 'DecorRegister' },
    { 'SetPedHelmet' },
    { 'IsPedWearingHelmet', false },
    { 'RemovePedHelmet' },
    { 'SetVehicleFullbeam' },
    { 'GetVehiclePetrolTankHealth', 1000.0 },
    { 'IsRadarHidden', false },
    { 'IsRadarPreferenceSwitchedOn', true },
    { 'SetGameplayCamRelativePitch' },
    { 'SetGameplayCamRelativeHeading' },
    { 'GetGameplayCamRelativePitch', 0.0 },
    { 'IsTaskMoveNetworkActive', false },
    { 'TaskMoveNetworkByName' },
    { 'SetTaskMoveNetworkSignalFloat' },
    { 'SetTaskMoveNetworkSignalBool' },
    { 'GetFollowPedCamViewMode', 0 },
    { 'GetProfileSetting', 0 },
    { 'SetBigmapActive' },
    { 'IsBigmapActive', false },
    { 'IsControlEnabled', true },
    { 'StopRecordingAndDiscardClip' },
    { 'DrawNotificationWithButton', 1 },
    { 'RemoveNotification' },
    { 'NetworkSetVoiceActive' },
    { 'NetworkSetTalkerProximity' },
    { 'NetworkClearVoiceChannel' },
    { 'NetworkSetVoiceChannel' },
    { 'NetworkIsPlayerTalking', false },
    { 'GetClockHours', 12 },
    { 'GetClockMinutes', 0 },
    { 'GetNameOfZone', '' },
    {
        'GetNthClosestVehicleNode',
        function()
            return true, vector3(0.0, 0.0, 0.0)
        end,
    },
    {
        'GetStreetNameAtCoord',
        function()
            return 0, 0
        end,
    },
    { 'GetStreetNameFromHashKey', '' },
    { 'Vdist2', 0.0 },
    {
        'GetActiveScreenResolution',
        function()
            return 1920, 1080
        end,
    },
    { 'SetPedIlluminatedClothingGlowIntensity' },
    { 'ShowHeadingIndicatorOnBlip' },
    { 'SetBlipRotation' },
    { 'SetBlipNameToPlayerName' },
    { 'SetBlipCategory' },
    { 'SetBlipDisplay' },
    { 'CreateMpGamerTag', 1 },
    { 'RemoveMpGamerTag' },
    { 'SetMpGamerTagVisibility' },
    { 'SetMpGamerTagWantedLevel' },
    { 'IsPedInAnyHeli', false },
    { 'IsPedInAnyPlane', false },
    { 'GetPlayerHasReserveParachute', false },
    { 'SetPedInfiniteAmmo' },
    { 'GetAnimDuration', 1.0 },
    { 'SetPedCurrentWeaponVisible' },
    { 'GetInteriorFromEntity', 0 },
    { 'IsPedInParachuteFreeFall', false },
    { 'IsPedBeingStunned', false },
    { 'IsPedWalking', false },
    { 'IsPedSprinting', false },
    { 'IsPedSwimming', false },
    { 'IsPedSwimmingUnderWater', false },
    { 'IsPedDiving', false },
    { 'DisableFirstPersonCamThisFrame' },
    { 'GetVehicleDoorsLockedForPlayer', false },
    { 'SetDrawOrigin' },
    { 'ClearDrawOrigin' },
    {
        'GetGamePool',
        function()
            return {}
        end,
    },
    { 'IsEntityOnScreen', false },
    {
        'GetModelDimensions',
        function()
            return vector3(-1.0, -1.0, -1.0), vector3(1.0, 1.0, 1.0)
        end,
    },
    { 'DrawLine' },
    { 'IsPedGettingIntoAVehicle', false },
    { 'BeginTextCommandIsThisHelpMessageBeingDisplayed' },
    { 'EndTextCommandIsThisHelpMessageBeingDisplayed', false },
    { 'IsHudPreferenceSwitchedOn', true },
    { 'IsFrontendFading', false },
    { 'HideHudComponentThisFrame' },
    { 'SetVehicleReduceGrip' },
    { 'SetCamActiveWithInterp' },
    { 'IsCamInterpolating', false },
    { 'IsCamActive', true },
    { 'SetCamFov' },
    { 'DoesCamExist', false },
    { 'TaskGoStraightToCoord' },
    { 'DisableAllControlActions' },
    { 'TaskLookAtCoord' },
    { 'SetTextOutline' },
    { 'GetPedSourceOfDeath', 0 },
    { 'GetSafeZoneSize', 1.0 },
    { 'GetTextScaleHeight', 0.05 },
    {
        'GetCamCoord',
        function()
            return vector3(0.0, 0.0, 0.0)
        end,
    },
    { 'IsThisModelAQuadbike', false },
    -- control state (menus poll these; process.lua uses them via luacheckrc)
    { 'IsControlPressed', false },
    { 'IsDisabledControlPressed', false },
    { 'IsControlJustPressed', false },
    { 'IsDisabledControlJustPressed', false },
    { 'IsControlJustReleased', false },
    { 'IsDisabledControlJustReleased', false },
    -- raw physical-key state (keyboard menu nav; bypasses GTA control bindings)
    { 'IsRawKeyDown', false },
    { 'IsRawKeyPressed', false },
    { 'IsRawKeyReleased', false },
    -- mp ped customization (head blends, overlays, tattoos, preview clone)
    { 'GetNumHairColors', 64 },
    { 'GetNumHeadOverlayValues', 0 },
    { 'GetPedHeadOverlayValue', 255 },
    { 'SetPedHeadOverlay' },
    { 'SetPedHeadOverlayColor' },
    { 'SetPedEyeColor' },
    { 'SetPedHairColor' },
    { 'SetPedFaceFeature' },
    { 'SetFacialIdleAnimOverride' },
    { 'AddPedDecorationFromHashes' },
    { 'SetPedFacialDecoration' },
    { 'GetNumParentPedsOfType', 0 },
    {
        'GetWorldCoordFromScreenCoord',
        function()
            return vector3(0.0, 0.0, 0.0), vector3(0.0, 1.0, 0.0)
        end,
    },
    { 'SetEntityCanBeDamaged' },
    { 'SetPedAoBlobRendering' },
    { 'SetBlockingOfNonTemporaryEvents' },
    { 'SetWarningMessage' },
    { 'ClampGameplayCamPitch' },
    -- ped collections (gen9-era collection-indexed variations)
    { 'GetPedCollectionsCount', 0 },
    { 'GetPedCollectionName', '' },
    { 'GetNumberOfPedCollectionDrawableVariations', 0 },
    { 'IsPedCollectionComponentVariationValid', false },
    { 'IsPedCollectionComponentVariationGen9Exclusive', false },
    { 'GetPedCollectionNameFromDrawable', '' },
    { 'GetPedCollectionLocalIndexFromDrawable', 0 },
    { 'GetNumberOfPedCollectionTextureVariations', 0 },
    { 'SetPedCollectionComponentVariation' },
    { 'GetNumberOfPedCollectionPropDrawableVariations', 0 },
    { 'GetPedCollectionNameFromProp', '' },
    { 'GetPedCollectionLocalIndexFromProp', 0 },
    { 'GetNumberOfPedCollectionPropTextureVariations', 0 },
    { 'SetPedCollectionPropIndex' },
    -- localized mod names (CitizenFX VehicleMod port)
    { 'HasThisAdditionalTextLoaded', true },
    { 'ClearAdditionalText' },
    { 'RequestAdditionalText' },
    { 'GetModSlotName', '' },
    { 'GetModTextLabel', '' },
    { 'DoesTextLabelExist', false },
    { 'GetEntityBoneIndexByName', -1 },
    -- weapon loadouts / weapon options
    { 'GetPedWeaponTintIndex', 0 },
    { 'SetPedWeaponTintIndex' },
    { 'GetAmmoInPedWeapon', 0 },
    { 'HasPedGotWeaponComponent', false },
    { 'GiveWeaponComponentToPed' },
    { 'RemoveWeaponComponentFromPed' },
    { 'RemoveAllPedWeapons' },
    { 'RemoveWeaponFromPed' },
    { 'IsWeaponValid', true },
    { 'GetMaxAmmoInClip', 30 },
    { 'SetAmmoInClip' },
    { 'SetPedAmmo' },
    { 'AddAmmoToPed' },
    { 'GetSelectedPedWeapon', 0 },
    { 'SetPedInfiniteAmmoClip' },
    { 'SetPedCanSwitchWeapon' },
    { 'GetWeapontypeGroup', 0 },
    { 'SetPlayerHasReserveParachute' },
    { 'SetPlayerCanLeaveParachuteSmokeTrail' },
    { 'SetPlayerParachuteSmokeTrailColor' },
    { 'SetPlayerParachuteTintIndex' },
    { 'SetPlayerReserveParachuteTintIndex' },
    -- spectate / cameras / player blips (online players)
    { 'NetworkSetInSpectatorMode' },
    { 'IsScreenFadingOut', false },
    { 'CreateCam', 1 },
    { 'SetCamCoord' },
    { 'PointCamAtCoord' },
    { 'SetCamActive' },
    { 'RenderScriptCams' },
    { 'DestroyCam' },
    { 'GetVehicleModelNumberOfSeats', 4 },
    { 'IsAnyVehicleSeatEmpty', true },
    { 'TaskWarpPedIntoVehicle' },
    { 'AddBlipForEntity', 1 },
    { 'GetBlipFromEntity', 0 },
    { 'SetBlipRoute' },
    { 'SetBlipRouteColour' },
    -- personal vehicle / key fob / doors / alarm
    { 'NetworkHasControlOfEntity', true },
    { 'NetworkGetNetworkIdFromEntity', 0 },
    { 'SetVehicleLights' },
    { 'SetReduceDriftVehicleSuspension' },
    { 'SetVehicleExclusiveDriver' },
    { 'SetVehicleExclusiveDriver_2' },
    { 'GetIsVehicleEngineRunning', false },
    { 'SetVehicleDoorBroken' },
    { 'GetVehicleDoorAngleRatio', 0.0 },
    { 'SetVehicleDoorShut' },
    { 'SetVehicleDoorOpen' },
    { 'AreBombBayDoorsOpen', false },
    { 'OpenBombBayDoors' },
    { 'CloseBombBayDoors' },
    { 'CreateObject', 3000 },
    { 'AttachEntityToEntity' },
    { 'DetachEntity' },
    { 'DeleteObject' },
    { 'GetPedBoneIndex', 0 },
    { 'TaskTurnPedToFaceEntity' },
    { 'PlaySoundFromEntity' },
    { 'SoundVehicleHornThisFrame' },
    { 'SetVehicleDoorsLockedForAllPlayers' },
    { 'IsVehicleAlarmActivated', false },
    { 'SetVehicleAlarm' },
    { 'SetVehicleAlarmTimeLeft' },
    { 'StartVehicleAlarm' },
    -- raycasts (delete vehicle)
    { 'StartShapeTestCapsule', 1 },
    {
        'GetShapeTestResult',
        function()
            return 0, false, { x = 0.0, y = 0.0, z = 0.0 }, { x = 0.0, y = 0.0, z = 0.0 }, 0
        end,
    },
    { 'IsEntityAVehicle', false },
    { 'NetworkRequestControlOfEntity' },
    -- safe teleport
    { 'RequestCollisionAtCoord' },
    { 'SetFocusPosAndVel' },
    { 'NewLoadSceneStart' },
    { 'IsNewLoadSceneLoaded', true },
    { 'ClearFocus' },
    { 'NewLoadSceneStop' },
    { 'HasCollisionLoadedAroundEntity', true },
    {
        'GetGroundZFor_3dCoord',
        function()
            return true, 30.0
        end,
    },
    { 'NetworkFadeOutEntity' },
    { 'NetworkFadeInEntity' },
    { 'SetEntityHeading' },
}

-- Exported so .luacheckrc can declare every faked native as a known global
-- (one source of truth for the native surface used by the ported code).
Cfx.NATIVE_NAMES = {}
for _, spec in ipairs(NATIVE_DEFAULTS) do
    Cfx.NATIVE_NAMES[#Cfx.NATIVE_NAMES + 1] = spec[1]
end
for _, name in ipairs(INSTALLED_GLOBALS) do
    Cfx.NATIVE_NAMES[#Cfx.NATIVE_NAMES + 1] = name
end

function Cfx.new(opts)
    opts = opts or {}
    return setmetatable({
        resource_name = opts.resource_name or 'vMenu',
        is_server = opts.is_server or false,
        convars = {},
        metadata = {},
        resource_files = {},
        kvp = {},
        players = {}, -- [handle] = { aces = {}, name = ..., identifiers = {}, state = {}, ped = int }
        event_handlers = {},
        triggered = {}, -- log of every TriggerEvent/Server/Client call, for assertions
        commands = {}, -- [name] = { handler = fn, restricted = bool }
        threads = {}, -- functions passed to CreateThread (recorded, not run)
        dropped = {}, -- { handle = ..., reason = ... } per DropPlayer call
        global_state = {},
        entity_coords = {}, -- [entity handle] = vector3-like table
        game_timer = 0,
        event_cancelled = false,
        kvp_typed = {}, -- [key] = { kind = 'int'|'float', value = ... }
        key_mappings = {}, -- { command, description, mapper, key } per RegisterKeyMapping
        native_calls = {}, -- [native name] = list of arg packs
        local_player_state = {}, -- LocalPlayer.state statebag
        entity_state = {}, -- [entity handle] = statebag table (Entity(h).state)
        _find_handles = {},
        _next_handle = 1,
        _next_ped = 100,
        _saved_globals = {},
    }, Cfx)
end

-- Test setup helpers ---------------------------------------------------------

function Cfx:set_convar(name, value)
    self.convars[name] = tostring(value)
end

function Cfx:set_metadata(key, value)
    self.metadata[key] = tostring(value)
end

function Cfx:set_resource_file(path, contents)
    self.resource_files[path] = contents
end

function Cfx:add_player(handle, opts)
    opts = opts or {}
    local ped = self._next_ped
    self._next_ped = self._next_ped + 1
    self.players[tostring(handle)] = {
        aces = {},
        name = opts.name or ('Player' .. tostring(handle)),
        identifiers = opts.identifiers or {},
        state = opts.state or {},
        ped = ped,
    }
    self.entity_coords[ped] = opts.coords or { x = 0.0, y = 0.0, z = 0.0 }
end

function Cfx:grant_ace(handle, ace)
    local player = self.players[tostring(handle)]
    assert(player, 'add_player first')
    player.aces[ace] = true
end

-- Global installation --------------------------------------------------------

function Cfx:install()
    local mock = self
    for _, name in ipairs(INSTALLED_GLOBALS) do
        mock._saved_globals[name] = _G[name]
    end

    -- convars / metadata / files

    _G.GetConvar = function(name, default)
        local value = mock.convars[name]
        if value == nil then
            return default
        end
        return value
    end

    -- Real runtime behaves atoi-like on non-numeric values (yields 0),
    -- and returns the default only when the convar is unset.
    _G.GetConvarInt = function(name, default)
        local value = mock.convars[name]
        if value == nil then
            return default
        end
        local leading_int = value:match('^%s*(%-?%d+)')
        return leading_int and math.tointeger(tonumber(leading_int)) or 0
    end

    _G.SetConvarReplicated = function(name, value)
        mock.convars[name] = tostring(value)
    end

    _G.GetResourceMetadata = function(resource, key, _index)
        if resource ~= mock.resource_name then
            return nil
        end
        return mock.metadata[key]
    end

    _G.GetCurrentResourceName = function()
        return mock.resource_name
    end

    _G.LoadResourceFile = function(resource, path)
        if resource ~= mock.resource_name then
            return nil
        end
        return mock.resource_files[path]
    end

    _G.SaveResourceFile = function(resource, path, contents, _length)
        if resource ~= mock.resource_name then
            return false
        end
        mock.resource_files[path] = contents
        return true
    end

    _G.IsDuplicityVersion = function()
        return mock.is_server
    end

    _G.DoesPlayerExist = function(handle)
        return mock.players[tostring(handle)] ~= nil
    end

    _G.GetPlayers = function()
        local handles = {}
        for handle in pairs(mock.players) do
            handles[#handles + 1] = handle
        end
        table.sort(handles)
        return handles
    end

    _G.GetPlayerName = function(handle)
        local player = mock.players[tostring(handle)]
        return player and player.name or nil
    end

    _G.GetNumPlayerIdentifiers = function(handle)
        local player = mock.players[tostring(handle)]
        return player and #player.identifiers or 0
    end

    _G.GetPlayerIdentifier = function(handle, index)
        local player = mock.players[tostring(handle)]
        return player and player.identifiers[index + 1] or nil
    end

    _G.DropPlayer = function(handle, reason)
        table.insert(mock.dropped, { handle = tostring(handle), reason = reason })
        mock.players[tostring(handle)] = nil
    end

    _G.CancelEvent = function()
        mock.event_cancelled = true
    end

    -- Statebag access: Player(id).state.key
    _G.Player = function(handle)
        local player = mock.players[tostring(handle)]
        return { state = player and player.state or {} }
    end

    _G.GetGameTimer = function()
        return mock.game_timer
    end

    -- Threads are recorded, never run: loops with Wait would hang the specs.
    _G.CreateThread = function(fn)
        table.insert(mock.threads, fn)
    end

    _G.Wait = function() end

    _G.RegisterCommand = function(name, handler, restricted)
        mock.commands[name] = { handler = handler, restricted = restricted }
    end

    _G.GlobalState = setmetatable({
        set = function(_, key, value, _replicated)
            mock.global_state[key] = value
        end,
    }, {
        __index = function(_, key)
            return mock.global_state[key]
        end,
    })

    _G.RegisterKeyMapping = function(command, description, mapper, key)
        table.insert(mock.key_mappings, { command = command, description = description, mapper = mapper, key = key })
    end

    -- Entity statebags: Entity(handle).state.key / :set().
    _G.Entity = function(handle)
        mock.entity_state[handle] = mock.entity_state[handle] or {}
        local bag = mock.entity_state[handle]
        return {
            state = setmetatable({
                set = function(_, key, value, _replicated)
                    bag[key] = value
                end,
            }, {
                __index = function(_, key)
                    return bag[key]
                end,
            }),
        }
    end

    -- Local player statebag: LocalPlayer.state.key / LocalPlayer.state:set().
    _G.LocalPlayer = {
        state = setmetatable({
            set = function(_, key, value, _replicated)
                mock.local_player_state[key] = value
            end,
        }, {
            __index = function(_, key)
                return mock.local_player_state[key]
            end,
        }),
    }

    -- Deterministic stand-in for joaat; stable across runs, distinct enough
    -- for table keys in specs.
    _G.GetHashKey = function(input)
        local text = tostring(input)
        local hash = 0
        for i = 1, #text do
            hash = (hash * 31 + text:byte(i)) % 4294967296
        end
        return hash
    end

    _G.GetPlayerPed = function(handle)
        local player = mock.players[tostring(handle)]
        return player and player.ped or 0
    end

    _G.GetEntityCoords = function(entity)
        return mock.entity_coords[entity] or { x = 0.0, y = 0.0, z = 0.0 }
    end

    _G.DoesEntityExist = function(entity)
        return mock.entity_coords[entity] ~= nil
    end

    _G.vector3 = function(x, y, z)
        return { x = x, y = y, z = z }
    end

    _G.IsPlayerAceAllowed = function(handle, ace)
        local player = mock.players[tostring(handle)]
        return player ~= nil and player.aces[ace] == true
    end

    -- KVP (with StartFindKvp/FindKvp/EndFindKvp iteration semantics)

    _G.SetResourceKvp = function(key, value)
        mock.kvp[key] = tostring(value)
    end

    _G.GetResourceKvpString = function(key)
        return mock.kvp[key]
    end

    _G.DeleteResourceKvp = function(key)
        mock.kvp[key] = nil
        mock.kvp_typed[key] = nil
    end

    -- Typed KVPs share the key namespace with string KVPs (find iterates all).
    _G.SetResourceKvpInt = function(key, value)
        mock.kvp_typed[key] = { kind = 'int', value = math.tointeger(value) or 0 }
    end

    _G.GetResourceKvpInt = function(key)
        local entry = mock.kvp_typed[key]
        return (entry and entry.kind == 'int') and entry.value or 0
    end

    _G.SetResourceKvpFloat = function(key, value)
        mock.kvp_typed[key] = { kind = 'float', value = value + 0.0 }
    end

    _G.GetResourceKvpFloat = function(key)
        local entry = mock.kvp_typed[key]
        return (entry and entry.kind == 'float') and entry.value or 0.0
    end

    _G.StartFindKvp = function(prefix)
        local keys = {}
        for key in pairs(mock.kvp) do
            if key:sub(1, #prefix) == prefix then
                keys[#keys + 1] = key
            end
        end
        for key in pairs(mock.kvp_typed) do
            if key:sub(1, #prefix) == prefix then
                keys[#keys + 1] = key
            end
        end
        table.sort(keys)
        local handle = mock._next_handle
        mock._next_handle = mock._next_handle + 1
        mock._find_handles[handle] = { keys = keys, index = 0 }
        return handle
    end

    _G.FindKvp = function(handle)
        local it = mock._find_handles[handle]
        if not it then
            return nil
        end
        it.index = it.index + 1
        return it.keys[it.index]
    end

    _G.EndFindKvp = function(handle)
        mock._find_handles[handle] = nil
    end

    -- Events: one in-process bus. Client/server distinction is recorded in the
    -- trigger log so specs can assert on direction and payloads.

    _G.RegisterNetEvent = function(name, handler)
        if handler then
            mock:_add_handler(name, handler)
        end
        return name
    end

    _G.AddEventHandler = function(name, handler)
        mock:_add_handler(name, handler)
    end

    _G.TriggerEvent = function(name, ...)
        mock:_record('local', name, ...)
        mock:_dispatch(mock.is_server and 'server' or 'client', name, ...)
    end

    _G.TriggerServerEvent = function(name, ...)
        mock:_record('to_server', name, ...)
        mock:_dispatch('server', name, ...)
    end

    _G.TriggerClientEvent = function(name, _target, ...)
        mock:_record('to_client', name, ...)
        mock:_dispatch('client', name, ...)
    end

    -- Recording no-op natives with canned defaults.
    for _, spec in ipairs(NATIVE_DEFAULTS) do
        local name, default = spec[1], spec[2]
        if mock._saved_globals[name] == nil then
            mock._saved_globals[name] = _G[name]
        end
        _G[name] = function(...)
            mock.native_calls[name] = mock.native_calls[name] or {}
            table.insert(mock.native_calls[name], table.pack(...))
            if type(default) == 'function' then
                return default(...)
            end
            return default
        end
    end

    return self
end

function Cfx:uninstall()
    for _, name in ipairs(INSTALLED_GLOBALS) do
        _G[name] = self._saved_globals[name]
    end
    for _, spec in ipairs(NATIVE_DEFAULTS) do
        _G[spec[1]] = self._saved_globals[spec[1]]
    end
    for _, name in ipairs(self._extra_stubs or {}) do
        _G[name] = self._saved_globals[name]
    end
end

-- All recorded calls to a faked native (empty list when never called).
function Cfx:calls(native_name)
    return self.native_calls[native_name] or {}
end

-- Replaces one native with a custom function for this test (restored on
-- uninstall like everything else).
function Cfx:stub_native(name, fn)
    if self._saved_globals[name] == nil then
        self._saved_globals[name] = _G[name]
    end
    self._extra_stubs = self._extra_stubs or {}
    table.insert(self._extra_stubs, name)
    _G[name] = fn
end

-- Triggers a server event as if a client sent it: the `source` global is set
-- to the given handle for the duration of the dispatch, like the real runtime.
function Cfx:trigger_from(source_handle, name, ...)
    self:_record('to_server', name, ...)
    local previous = rawget(_G, 'source')
    _G.source = source_handle
    self:_dispatch('server', name, ...)
    _G.source = previous
end

-- Internals -------------------------------------------------------------------

-- Handlers register on the side the mock is running as, so a server-side
-- handler never catches its own TriggerClientEvent broadcast (e.g. the
-- vMenu:ClearArea request/broadcast pair sharing one event name).
function Cfx:_add_handler(name, handler)
    local side = self.is_server and 'server' or 'client'
    self.event_handlers[side] = self.event_handlers[side] or {}
    self.event_handlers[side][name] = self.event_handlers[side][name] or {}
    table.insert(self.event_handlers[side][name], handler)
end

function Cfx:_dispatch(side, name, ...)
    local handlers = self.event_handlers[side] and self.event_handlers[side][name] or nil
    for _, handler in ipairs(handlers or {}) do
        handler(...)
    end
end

function Cfx:_record(direction, name, ...)
    table.insert(self.triggered, { direction = direction, name = name, args = table.pack(...) })
end

return Cfx
