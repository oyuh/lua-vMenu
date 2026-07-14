# Contract: ACE permissions

Source: `SharedClasses/PermissionsManager.cs`, `SharedClasses/SupplementaryPermissionManager.cs`
(upstream @ `49e53065`). Implemented by `shared/permissions.lua`.

An existing `permissions.cfg` must produce **identical menu visibility and action gating** in the
Lua rewrite. That means identical ace names, identical implication rules, and identical behavior
of the global gates.

## Resolution rules

1. **Ace naming.** `vMenu.` + category expansion. Two-letter category prefixes map as:
   OP→OnlinePlayers, PO→PlayerOptions, VO→VehicleOptions, VS→VehicleSpawner, SV→SavedVehicles,
   PV→PersonalVehicle, PA→PlayerAppearance, TO→TimeOptions, WO→WeatherOptions, WP→WeaponOptions,
   WL→WeaponLoadouts, MS→MiscSettings, VC→VoiceChat — e.g. `OPKick` → `vMenu.OnlinePlayers.Kick`.
   Everything else (`Everything`, `Staff`, `NoClip`, `DontKickMe`, `DontBanMe`) is `vMenu.<Name>`.
2. **Implication (parents).** A permission is granted if the player has *any* of:
   its own ace, `vMenu.Everything`, or — for category members whose suffix is neither `All` nor
   `Menu` — the category's `<XX>All` ace. Quirk preserved on purpose: `<XX>All` does **not**
   imply `<XX>Menu`; menu visibility needs the Menu ace or Everything (upstream menus typically
   check `XXMenu or XXAll` explicitly at creation time instead).
3. **Server side** checks `IsPlayerAceAllowed` per parent; **client side** checks the permission
   dictionary pushed by the server, with a local memo cache.
4. **Staff-only gate.** If `vmenu_menu_staff_only` is true, the client returns false for every
   permission unless `Staff` or `Everything` was granted.
5. **Permissions disabled mode.** If `vmenu_use_permissions` is false, the server grants
   everyone everything **except**: `Everything`, `OPAll`, `OPKick`, `OPKill`, `OPPermBan`,
   `OPTempBan`, `OPUnban`, `OPIdentifiers`, `OPViewBannedPlayers`.
6. **Sync.** On join (and on request) the server serializes `{ [PermissionName] = bool }` to
   JSON and fires `vMenu:SetPermissions`; supplementary permissions go via
   `vMenu:SetSupplementaryPermissions` with the same shape. See
   [events.md](events.md) for ordering (`SetConfigOptions` and `UpdateTeleportLocations` follow).

## Supplementary (model-whitelist) permissions

Separate string-keyed system with three members and their own ace expansion:

| Permission | Ace name | Client fallback when unset |
|---|---|---|
| `VWAll` | `vMenu.VehicleSpawner.WhitelistedModels.All` | granted if `VSAll` is allowed |
| `PWAll` | `vMenu.PlayerAppearance.WhitelistedModels.All` | granted if `PAAll` is allowed |
| `WWAll` | `vMenu.WeaponOptions.WhitelistedModels.All` | granted if `WPAll` is allowed |

Per-model whitelist aces (`vMenu.<Category>.WhitelistedModels.<model>`) are checked dynamically
against `config/model-whitelists.json` entries; the parent rule (`Everything`, `<XX>All`) applies
with only the `All` suffix excluded.

## Intentional deviation: no dev backdoor

Upstream `SetPermissionsForPlayer` grants `Everything` to a hardcoded player identifier hash
(`4510587c…`, the original author) when the server has granted the `vMenu.Dev` ace **and** debug
mode is on. The Lua rewrite does **not** port this backdoor. Nothing else references
`vMenu.Dev`. This is the only intentional behavioral difference in the permission system.

## Full permission → ace table

<!-- GEN-BEGIN ace-table (run scripts/gen-permissions.ps1 to update) -->
| Permission | Ace name |
|---|---|
| `Everything` | `vMenu.Everything` |
| `DontKickMe` | `vMenu.DontKickMe` |
| `DontBanMe` | `vMenu.DontBanMe` |
| `NoClip` | `vMenu.NoClip` |
| `Staff` | `vMenu.Staff` |
| `OPMenu` | `vMenu.OnlinePlayers.Menu` |
| `OPAll` | `vMenu.OnlinePlayers.All` |
| `OPTeleport` | `vMenu.OnlinePlayers.Teleport` |
| `OPWaypoint` | `vMenu.OnlinePlayers.Waypoint` |
| `OPSpectate` | `vMenu.OnlinePlayers.Spectate` |
| `OPSendMessage` | `vMenu.OnlinePlayers.SendMessage` |
| `OPIdentifiers` | `vMenu.OnlinePlayers.Identifiers` |
| `OPSummon` | `vMenu.OnlinePlayers.Summon` |
| `OPKill` | `vMenu.OnlinePlayers.Kill` |
| `OPKick` | `vMenu.OnlinePlayers.Kick` |
| `OPPermBan` | `vMenu.OnlinePlayers.PermBan` |
| `OPTempBan` | `vMenu.OnlinePlayers.TempBan` |
| `OPUnban` | `vMenu.OnlinePlayers.Unban` |
| `OPViewBannedPlayers` | `vMenu.OnlinePlayers.ViewBannedPlayers` |
| `OPSeePrivateMessages` | `vMenu.OnlinePlayers.SeePrivateMessages` |
| `POMenu` | `vMenu.PlayerOptions.Menu` |
| `POAll` | `vMenu.PlayerOptions.All` |
| `POGod` | `vMenu.PlayerOptions.God` |
| `POInvisible` | `vMenu.PlayerOptions.Invisible` |
| `POFastRun` | `vMenu.PlayerOptions.FastRun` |
| `POFastSwim` | `vMenu.PlayerOptions.FastSwim` |
| `POSuperjump` | `vMenu.PlayerOptions.Superjump` |
| `PONoRagdoll` | `vMenu.PlayerOptions.NoRagdoll` |
| `PONeverWanted` | `vMenu.PlayerOptions.NeverWanted` |
| `POSetWanted` | `vMenu.PlayerOptions.SetWanted` |
| `POClearBlood` | `vMenu.PlayerOptions.ClearBlood` |
| `POSetBlood` | `vMenu.PlayerOptions.SetBlood` |
| `POIgnored` | `vMenu.PlayerOptions.Ignored` |
| `POStayInVehicle` | `vMenu.PlayerOptions.StayInVehicle` |
| `POMaxHealth` | `vMenu.PlayerOptions.MaxHealth` |
| `POMaxArmor` | `vMenu.PlayerOptions.MaxArmor` |
| `POCleanPlayer` | `vMenu.PlayerOptions.CleanPlayer` |
| `PODryPlayer` | `vMenu.PlayerOptions.DryPlayer` |
| `POWetPlayer` | `vMenu.PlayerOptions.WetPlayer` |
| `POVehicleAutoPilotMenu` | `vMenu.PlayerOptions.VehicleAutoPilotMenu` |
| `POFreeze` | `vMenu.PlayerOptions.Freeze` |
| `POScenarios` | `vMenu.PlayerOptions.Scenarios` |
| `POUnlimitedStamina` | `vMenu.PlayerOptions.UnlimitedStamina` |
| `VOMenu` | `vMenu.VehicleOptions.Menu` |
| `VOAll` | `vMenu.VehicleOptions.All` |
| `VOGod` | `vMenu.VehicleOptions.God` |
| `VOKeepClean` | `vMenu.VehicleOptions.KeepClean` |
| `VORepair` | `vMenu.VehicleOptions.Repair` |
| `VOWash` | `vMenu.VehicleOptions.Wash` |
| `VOEngine` | `vMenu.VehicleOptions.Engine` |
| `VODestroyEngine` | `vMenu.VehicleOptions.DestroyEngine` |
| `VOBikeSeatbelt` | `vMenu.VehicleOptions.BikeSeatbelt` |
| `VOSpeedLimiter` | `vMenu.VehicleOptions.SpeedLimiter` |
| `VOChangePlate` | `vMenu.VehicleOptions.ChangePlate` |
| `VOMod` | `vMenu.VehicleOptions.Mod` |
| `VOColors` | `vMenu.VehicleOptions.Colors` |
| `VOLiveries` | `vMenu.VehicleOptions.Liveries` |
| `VOComponents` | `vMenu.VehicleOptions.Components` |
| `VODoors` | `vMenu.VehicleOptions.Doors` |
| `VOWindows` | `vMenu.VehicleOptions.Windows` |
| `VOFreeze` | `vMenu.VehicleOptions.Freeze` |
| `VOInvisible` | `vMenu.VehicleOptions.Invisible` |
| `VOTorqueMultiplier` | `vMenu.VehicleOptions.TorqueMultiplier` |
| `VOPowerMultiplier` | `vMenu.VehicleOptions.PowerMultiplier` |
| `VOFlip` | `vMenu.VehicleOptions.Flip` |
| `VOAlarm` | `vMenu.VehicleOptions.Alarm` |
| `VOCycleSeats` | `vMenu.VehicleOptions.CycleSeats` |
| `VOEngineAlwaysOn` | `vMenu.VehicleOptions.EngineAlwaysOn` |
| `VONoSiren` | `vMenu.VehicleOptions.NoSiren` |
| `VONoHelmet` | `vMenu.VehicleOptions.NoHelmet` |
| `VOLights` | `vMenu.VehicleOptions.Lights` |
| `VOFixOrDestroyTires` | `vMenu.VehicleOptions.FixOrDestroyTires` |
| `VODelete` | `vMenu.VehicleOptions.Delete` |
| `VOUnderglow` | `vMenu.VehicleOptions.Underglow` |
| `VOFlashHighbeamsOnHonk` | `vMenu.VehicleOptions.FlashHighbeamsOnHonk` |
| `VODisableTurbulence` | `vMenu.VehicleOptions.DisableTurbulence` |
| `VOAnchorBoat` | `vMenu.VehicleOptions.AnchorBoat` |
| `VOInfiniteFuel` | `vMenu.VehicleOptions.InfiniteFuel` |
| `VOFlares` | `vMenu.VehicleOptions.Flares` |
| `VOPlaneBombs` | `vMenu.VehicleOptions.PlaneBombs` |
| `VOBypassExtraDamage` | `vMenu.VehicleOptions.BypassExtraDamage` |
| `VSMenu` | `vMenu.VehicleSpawner.Menu` |
| `VSAll` | `vMenu.VehicleSpawner.All` |
| `VSBypassRateLimit` | `vMenu.VehicleSpawner.BypassRateLimit` |
| `VSDisableReplacePrevious` | `vMenu.VehicleSpawner.DisableReplacePrevious` |
| `VSSpawnByName` | `vMenu.VehicleSpawner.SpawnByName` |
| `VSAddon` | `vMenu.VehicleSpawner.Addon` |
| `VSCompacts` | `vMenu.VehicleSpawner.Compacts` |
| `VSSedans` | `vMenu.VehicleSpawner.Sedans` |
| `VSSUVs` | `vMenu.VehicleSpawner.SUVs` |
| `VSCoupes` | `vMenu.VehicleSpawner.Coupes` |
| `VSMuscle` | `vMenu.VehicleSpawner.Muscle` |
| `VSSportsClassic` | `vMenu.VehicleSpawner.SportsClassic` |
| `VSSports` | `vMenu.VehicleSpawner.Sports` |
| `VSSuper` | `vMenu.VehicleSpawner.Super` |
| `VSMotorcycles` | `vMenu.VehicleSpawner.Motorcycles` |
| `VSOffRoad` | `vMenu.VehicleSpawner.OffRoad` |
| `VSIndustrial` | `vMenu.VehicleSpawner.Industrial` |
| `VSUtility` | `vMenu.VehicleSpawner.Utility` |
| `VSVans` | `vMenu.VehicleSpawner.Vans` |
| `VSCycles` | `vMenu.VehicleSpawner.Cycles` |
| `VSBoats` | `vMenu.VehicleSpawner.Boats` |
| `VSHelicopters` | `vMenu.VehicleSpawner.Helicopters` |
| `VSPlanes` | `vMenu.VehicleSpawner.Planes` |
| `VSService` | `vMenu.VehicleSpawner.Service` |
| `VSEmergency` | `vMenu.VehicleSpawner.Emergency` |
| `VSMilitary` | `vMenu.VehicleSpawner.Military` |
| `VSCommercial` | `vMenu.VehicleSpawner.Commercial` |
| `VSTrains` | `vMenu.VehicleSpawner.Trains` |
| `VSOpenWheel` | `vMenu.VehicleSpawner.OpenWheel` |
| `SVMenu` | `vMenu.SavedVehicles.Menu` |
| `SVAll` | `vMenu.SavedVehicles.All` |
| `SVSpawn` | `vMenu.SavedVehicles.Spawn` |
| `PVMenu` | `vMenu.PersonalVehicle.Menu` |
| `PVAll` | `vMenu.PersonalVehicle.All` |
| `PVToggleEngine` | `vMenu.PersonalVehicle.ToggleEngine` |
| `PVToggleLights` | `vMenu.PersonalVehicle.ToggleLights` |
| `PVToggleStance` | `vMenu.PersonalVehicle.ToggleStance` |
| `PVKickPassengers` | `vMenu.PersonalVehicle.KickPassengers` |
| `PVLockDoors` | `vMenu.PersonalVehicle.LockDoors` |
| `PVDoors` | `vMenu.PersonalVehicle.Doors` |
| `PVSoundHorn` | `vMenu.PersonalVehicle.SoundHorn` |
| `PVToggleAlarm` | `vMenu.PersonalVehicle.ToggleAlarm` |
| `PVAddBlip` | `vMenu.PersonalVehicle.AddBlip` |
| `PVExclusiveDriver` | `vMenu.PersonalVehicle.ExclusiveDriver` |
| `PAMenu` | `vMenu.PlayerAppearance.Menu` |
| `PAAll` | `vMenu.PlayerAppearance.All` |
| `PACustomize` | `vMenu.PlayerAppearance.Customize` |
| `PASpawnSaved` | `vMenu.PlayerAppearance.SpawnSaved` |
| `PASpawnNew` | `vMenu.PlayerAppearance.SpawnNew` |
| `PAAddonPeds` | `vMenu.PlayerAppearance.AddonPeds` |
| `TOMenu` | `vMenu.TimeOptions.Menu` |
| `TOAll` | `vMenu.TimeOptions.All` |
| `TOFreezeTime` | `vMenu.TimeOptions.FreezeTime` |
| `TOSetTime` | `vMenu.TimeOptions.SetTime` |
| `WOMenu` | `vMenu.WeatherOptions.Menu` |
| `WOAll` | `vMenu.WeatherOptions.All` |
| `WODynamic` | `vMenu.WeatherOptions.Dynamic` |
| `WOBlackout` | `vMenu.WeatherOptions.Blackout` |
| `WOVehBlackout` | `vMenu.WeatherOptions.VehBlackout` |
| `WOSetWeather` | `vMenu.WeatherOptions.SetWeather` |
| `WORemoveClouds` | `vMenu.WeatherOptions.RemoveClouds` |
| `WORandomizeClouds` | `vMenu.WeatherOptions.RandomizeClouds` |
| `WPMenu` | `vMenu.WeaponOptions.Menu` |
| `WPAll` | `vMenu.WeaponOptions.All` |
| `WPGetAll` | `vMenu.WeaponOptions.GetAll` |
| `WPRemoveAll` | `vMenu.WeaponOptions.RemoveAll` |
| `WPUnlimitedAmmo` | `vMenu.WeaponOptions.UnlimitedAmmo` |
| `WPNoReload` | `vMenu.WeaponOptions.NoReload` |
| `WPSpawn` | `vMenu.WeaponOptions.Spawn` |
| `WPSpawnByName` | `vMenu.WeaponOptions.SpawnByName` |
| `WPSetAllAmmo` | `vMenu.WeaponOptions.SetAllAmmo` |
| `WPAPPistol` | `vMenu.WeaponOptions.APPistol` |
| `WPAdvancedRifle` | `vMenu.WeaponOptions.AdvancedRifle` |
| `WPAssaultRifle` | `vMenu.WeaponOptions.AssaultRifle` |
| `WPAssaultRifleMk2` | `vMenu.WeaponOptions.AssaultRifleMk2` |
| `WPAssaultSMG` | `vMenu.WeaponOptions.AssaultSMG` |
| `WPAssaultShotgun` | `vMenu.WeaponOptions.AssaultShotgun` |
| `WPBZGas` | `vMenu.WeaponOptions.BZGas` |
| `WPBall` | `vMenu.WeaponOptions.Ball` |
| `WPBat` | `vMenu.WeaponOptions.Bat` |
| `WPBattleAxe` | `vMenu.WeaponOptions.BattleAxe` |
| `WPBottle` | `vMenu.WeaponOptions.Bottle` |
| `WPBullpupRifle` | `vMenu.WeaponOptions.BullpupRifle` |
| `WPBullpupRifleMk2` | `vMenu.WeaponOptions.BullpupRifleMk2` |
| `WPBullpupShotgun` | `vMenu.WeaponOptions.BullpupShotgun` |
| `WPCarbineRifle` | `vMenu.WeaponOptions.CarbineRifle` |
| `WPCarbineRifleMk2` | `vMenu.WeaponOptions.CarbineRifleMk2` |
| `WPCombatMG` | `vMenu.WeaponOptions.CombatMG` |
| `WPCombatMGMk2` | `vMenu.WeaponOptions.CombatMGMk2` |
| `WPCombatPDW` | `vMenu.WeaponOptions.CombatPDW` |
| `WPCombatPistol` | `vMenu.WeaponOptions.CombatPistol` |
| `WPCompactGrenadeLauncher` | `vMenu.WeaponOptions.CompactGrenadeLauncher` |
| `WPCompactRifle` | `vMenu.WeaponOptions.CompactRifle` |
| `WPCrowbar` | `vMenu.WeaponOptions.Crowbar` |
| `WPDagger` | `vMenu.WeaponOptions.Dagger` |
| `WPDoubleAction` | `vMenu.WeaponOptions.DoubleAction` |
| `WPDoubleBarrelShotgun` | `vMenu.WeaponOptions.DoubleBarrelShotgun` |
| `WPFireExtinguisher` | `vMenu.WeaponOptions.FireExtinguisher` |
| `WPFirework` | `vMenu.WeaponOptions.Firework` |
| `WPFlare` | `vMenu.WeaponOptions.Flare` |
| `WPFlareGun` | `vMenu.WeaponOptions.FlareGun` |
| `WPFlashlight` | `vMenu.WeaponOptions.Flashlight` |
| `WPGolfClub` | `vMenu.WeaponOptions.GolfClub` |
| `WPGrenade` | `vMenu.WeaponOptions.Grenade` |
| `WPGrenadeLauncher` | `vMenu.WeaponOptions.GrenadeLauncher` |
| `WPGrenadeLauncherSmoke` | `vMenu.WeaponOptions.GrenadeLauncherSmoke` |
| `WPGusenberg` | `vMenu.WeaponOptions.Gusenberg` |
| `WPHammer` | `vMenu.WeaponOptions.Hammer` |
| `WPHatchet` | `vMenu.WeaponOptions.Hatchet` |
| `WPHeavyPistol` | `vMenu.WeaponOptions.HeavyPistol` |
| `WPHeavyShotgun` | `vMenu.WeaponOptions.HeavyShotgun` |
| `WPHeavySniper` | `vMenu.WeaponOptions.HeavySniper` |
| `WPHeavySniperMk2` | `vMenu.WeaponOptions.HeavySniperMk2` |
| `WPHomingLauncher` | `vMenu.WeaponOptions.HomingLauncher` |
| `WPKnife` | `vMenu.WeaponOptions.Knife` |
| `WPKnuckleDuster` | `vMenu.WeaponOptions.KnuckleDuster` |
| `WPMG` | `vMenu.WeaponOptions.MG` |
| `WPMachete` | `vMenu.WeaponOptions.Machete` |
| `WPMachinePistol` | `vMenu.WeaponOptions.MachinePistol` |
| `WPMarksmanPistol` | `vMenu.WeaponOptions.MarksmanPistol` |
| `WPMarksmanRifle` | `vMenu.WeaponOptions.MarksmanRifle` |
| `WPMarksmanRifleMk2` | `vMenu.WeaponOptions.MarksmanRifleMk2` |
| `WPMicroSMG` | `vMenu.WeaponOptions.MicroSMG` |
| `WPMiniSMG` | `vMenu.WeaponOptions.MiniSMG` |
| `WPMinigun` | `vMenu.WeaponOptions.Minigun` |
| `WPMolotov` | `vMenu.WeaponOptions.Molotov` |
| `WPMusket` | `vMenu.WeaponOptions.Musket` |
| `WPNightVision` | `vMenu.WeaponOptions.NightVision` |
| `WPNightstick` | `vMenu.WeaponOptions.Nightstick` |
| `WPParachute` | `vMenu.WeaponOptions.Parachute` |
| `WPPetrolCan` | `vMenu.WeaponOptions.PetrolCan` |
| `WPPipeBomb` | `vMenu.WeaponOptions.PipeBomb` |
| `WPPistol` | `vMenu.WeaponOptions.Pistol` |
| `WPPistol50` | `vMenu.WeaponOptions.Pistol50` |
| `WPPistolMk2` | `vMenu.WeaponOptions.PistolMk2` |
| `WPPoolCue` | `vMenu.WeaponOptions.PoolCue` |
| `WPProximityMine` | `vMenu.WeaponOptions.ProximityMine` |
| `WPPumpShotgun` | `vMenu.WeaponOptions.PumpShotgun` |
| `WPPumpShotgunMk2` | `vMenu.WeaponOptions.PumpShotgunMk2` |
| `WPRPG` | `vMenu.WeaponOptions.RPG` |
| `WPRailgun` | `vMenu.WeaponOptions.Railgun` |
| `WPRevolver` | `vMenu.WeaponOptions.Revolver` |
| `WPRevolverMk2` | `vMenu.WeaponOptions.RevolverMk2` |
| `WPSMG` | `vMenu.WeaponOptions.SMG` |
| `WPSMGMk2` | `vMenu.WeaponOptions.SMGMk2` |
| `WPSNSPistol` | `vMenu.WeaponOptions.SNSPistol` |
| `WPSNSPistolMk2` | `vMenu.WeaponOptions.SNSPistolMk2` |
| `WPSawnOffShotgun` | `vMenu.WeaponOptions.SawnOffShotgun` |
| `WPSmokeGrenade` | `vMenu.WeaponOptions.SmokeGrenade` |
| `WPSniperRifle` | `vMenu.WeaponOptions.SniperRifle` |
| `WPSnowball` | `vMenu.WeaponOptions.Snowball` |
| `WPSpecialCarbine` | `vMenu.WeaponOptions.SpecialCarbine` |
| `WPSpecialCarbineMk2` | `vMenu.WeaponOptions.SpecialCarbineMk2` |
| `WPStickyBomb` | `vMenu.WeaponOptions.StickyBomb` |
| `WPStunGun` | `vMenu.WeaponOptions.StunGun` |
| `WPSweeperShotgun` | `vMenu.WeaponOptions.SweeperShotgun` |
| `WPSwitchBlade` | `vMenu.WeaponOptions.SwitchBlade` |
| `WPUnarmed` | `vMenu.WeaponOptions.Unarmed` |
| `WPVintagePistol` | `vMenu.WeaponOptions.VintagePistol` |
| `WPWrench` | `vMenu.WeaponOptions.Wrench` |
| `WPPlasmaPistol` | `vMenu.WeaponOptions.PlasmaPistol` |
| `WPPlasmaCarbine` | `vMenu.WeaponOptions.PlasmaCarbine` |
| `WPPlasmaMinigun` | `vMenu.WeaponOptions.PlasmaMinigun` |
| `WPStoneHatchet` | `vMenu.WeaponOptions.StoneHatchet` |
| `WPCeramicPistol` | `vMenu.WeaponOptions.CeramicPistol` |
| `WPNavyRevolver` | `vMenu.WeaponOptions.NavyRevolver` |
| `WPHazardCan` | `vMenu.WeaponOptions.HazardCan` |
| `WPPericoPistol` | `vMenu.WeaponOptions.PericoPistol` |
| `WPMilitaryRifle` | `vMenu.WeaponOptions.MilitaryRifle` |
| `WPCombatShotgun` | `vMenu.WeaponOptions.CombatShotgun` |
| `WPEMPLauncher` | `vMenu.WeaponOptions.EMPLauncher` |
| `WPHeavyRifle` | `vMenu.WeaponOptions.HeavyRifle` |
| `WPFertilizerCan` | `vMenu.WeaponOptions.FertilizerCan` |
| `WPStunGunMP` | `vMenu.WeaponOptions.StunGunMP` |
| `WPPrecisionRifle` | `vMenu.WeaponOptions.PrecisionRifle` |
| `WPTacticalRifle` | `vMenu.WeaponOptions.TacticalRifle` |
| `WPPistolXM3` | `vMenu.WeaponOptions.PistolXM3` |
| `WPCandyCane` | `vMenu.WeaponOptions.CandyCane` |
| `WPRailgunXM3` | `vMenu.WeaponOptions.RailgunXM3` |
| `WPAcidPackage` | `vMenu.WeaponOptions.AcidPackage` |
| `WPTecPistol` | `vMenu.WeaponOptions.TecPistol` |
| `WPBattleRifle` | `vMenu.WeaponOptions.BattleRifle` |
| `WPSnowLauncher` | `vMenu.WeaponOptions.SnowLauncher` |
| `WPHackingDevice` | `vMenu.WeaponOptions.HackingDevice` |
| `WPStunRod` | `vMenu.WeaponOptions.StunRod` |
| `WPNewspaper` | `vMenu.WeaponOptions.Newspaper` |
| `WLMenu` | `vMenu.WeaponLoadouts.Menu` |
| `WLAll` | `vMenu.WeaponLoadouts.All` |
| `WLEquip` | `vMenu.WeaponLoadouts.Equip` |
| `WLEquipOnRespawn` | `vMenu.WeaponLoadouts.EquipOnRespawn` |
| `MSAll` | `vMenu.MiscSettings.All` |
| `MSClearArea` | `vMenu.MiscSettings.ClearArea` |
| `MSTeleportToWp` | `vMenu.MiscSettings.TeleportToWp` |
| `MSTeleportToCoord` | `vMenu.MiscSettings.TeleportToCoord` |
| `MSShowCoordinates` | `vMenu.MiscSettings.ShowCoordinates` |
| `MSShowLocation` | `vMenu.MiscSettings.ShowLocation` |
| `MSJoinQuitNotifs` | `vMenu.MiscSettings.JoinQuitNotifs` |
| `MSDeathNotifs` | `vMenu.MiscSettings.DeathNotifs` |
| `MSNightVision` | `vMenu.MiscSettings.NightVision` |
| `MSThermalVision` | `vMenu.MiscSettings.ThermalVision` |
| `MSLocationBlips` | `vMenu.MiscSettings.LocationBlips` |
| `MSPlayerBlips` | `vMenu.MiscSettings.PlayerBlips` |
| `MSOverheadNames` | `vMenu.MiscSettings.OverheadNames` |
| `MSTeleportLocations` | `vMenu.MiscSettings.TeleportLocations` |
| `MSTeleportSaveLocation` | `vMenu.MiscSettings.TeleportSaveLocation` |
| `MSConnectionMenu` | `vMenu.MiscSettings.ConnectionMenu` |
| `MSRestoreAppearance` | `vMenu.MiscSettings.RestoreAppearance` |
| `MSRestoreWeapons` | `vMenu.MiscSettings.RestoreWeapons` |
| `MSDriftMode` | `vMenu.MiscSettings.DriftMode` |
| `MSEntitySpawner` | `vMenu.MiscSettings.EntitySpawner` |
| `MSDevTools` | `vMenu.MiscSettings.DevTools` |
| `VCMenu` | `vMenu.VoiceChat.Menu` |
| `VCAll` | `vMenu.VoiceChat.All` |
| `VCEnable` | `vMenu.VoiceChat.Enable` |
| `VCShowSpeaker` | `vMenu.VoiceChat.ShowSpeaker` |
| `VCStaffChannel` | `vMenu.VoiceChat.StaffChannel` |
<!-- GEN-END ace-table -->
