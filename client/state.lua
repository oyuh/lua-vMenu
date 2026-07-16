-- Cross-module client state. Upstream keeps these as statics scattered over
-- MainMenu / EventManager / the menu classes; here they live in one dependency-
-- free module so client/events.lua, client/main.lua, and the menu modules
-- (M7+) can share them without require cycles.

return {
    -- MainMenu statics
    config_options_setup_complete = false, -- MainMenu.ConfigOptionsSetupComplete
    addon_permission_setup = false, -- MainMenu.AddonPermissionSetup
    menu_enabled = true, -- MainMenu.MenuEnabled

    -- Menu module registry: [name] = menu module table, filled by client/main
    -- as the menu waves land (OnlinePlayers, PlayerOptions, ...). Names match
    -- the MainMenu.<Name>Menu statics.
    menus = {},

    -- The root menus (set by PostPermissionsSetup when the staff gate passes).
    menu = nil, -- MainMenu.Menu
    player_submenu = nil,
    vehicle_submenu = nil,
    world_submenu = nil,

    -- EventManager.SetConfigOptions results (addons.json / model-whitelists /
    -- extras.json / tattoos.json). Keys are model names, values are hashes.
    addon_vehicles = {}, -- VehicleSpawner.AddonVehicles
    addon_weapons = {}, -- WeaponOptions.AddonWeapons
    addon_peds = {}, -- PlayerAppearance.AddonPeds
    extra_blendable_faces = {}, -- MpPedCustomization.ExtraBlendableFaces
    whitelist_vehicles = {}, -- VehicleSpawner.WhitelistVehicles
    whitelisted_peds = {}, -- PlayerAppearance.WhitelistedPeds
    weapon_whitelist = {}, -- WeaponOptions.WeaponWhitelist
    vehicle_extras = {}, -- VehicleOptions.VehicleExtras ([model hash] = { [extra] = label })
    tattoos = {}, -- TattoosData.Addons
    teleport_locations = {}, -- MiscSettings.TpLocations

    -- MainMenu.SetPermissions: VehicleSpawner.allowedCategories (23 bools, in
    -- upstream's fixed category order).
    allowed_vehicle_categories = {},

    -- FunctionsController.entityRange (dev tools dimensions radius, M9 tick).
    entity_range = 2000.0,
}
