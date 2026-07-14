std = 'lua54'
codes = true
max_line_length = 120
self = false

exclude_files = {
    'vendor/**',
    'client/data/**', -- generated tables
    '.upstream/**',
}

-- CitizenFX (CfxLua) runtime globals. Extend as modules get ported.
read_globals = {
    -- convars / resource metadata
    'GetConvar', 'GetConvarInt', 'GetResourceMetadata', 'GetCurrentResourceName',
    'LoadResourceFile', 'SaveResourceFile',
    -- commands / keymapping
    'RegisterCommand', 'RegisterKeyMapping',
    -- events
    'RegisterNetEvent', 'AddEventHandler', 'RemoveEventHandler',
    'TriggerEvent', 'TriggerServerEvent', 'TriggerClientEvent',
    -- kvp
    'SetResourceKvp', 'GetResourceKvpString', 'DeleteResourceKvp',
    'StartFindKvp', 'FindKvp', 'EndFindKvp',
    -- runtime
    'CreateThread', 'Wait', 'SetTimeout', 'IsDuplicityVersion',
    'GetPlayers', 'GetPlayerName', 'GetPlayerPed', 'PlayerId', 'PlayerPedId', 'GetPlayerServerId',
    'IsPlayerAceAllowed', 'DoesPlayerExist', 'ExecuteCommand',
    -- game state / hud
    'IsPauseMenuActive', 'IsScreenFadedOut', 'IsPlayerSwitchInProgress', 'IsEntityDead',
    'PlaySoundFrontend',
    -- cfx lua extensions
    'vector2', 'vector3', 'vector4', 'quat', 'json', 'msgpack',
    'exports', 'Citizen', 'GlobalState', 'LocalPlayer',
}

-- fxmanifest.lua is a DSL, not a script: every directive is a "global" call.
files['fxmanifest.lua'] = {
    max_line_length = false,
    read_globals = {
        'fx_version', 'game', 'games', 'lua54', 'name', 'description', 'version', 'author', 'url',
        'client_debug_mode', 'server_debug_mode', 'files',
        'shared_scripts', 'client_scripts', 'server_scripts', 'shared_script', 'client_script', 'server_script',
        'dependency', 'dependencies', 'export', 'exports', 'server_exports', 'ui_page', 'loadscreen',
    },
}

-- The bootstrap installs a require() shim in the CfxLua runtime by design.
files['shared/bootstrap.lua'] = {
    globals = { 'require' },
}

files['tests/**'] = {
    std = '+busted',
    -- tests are allowed to install fake natives into the global table
    allow_defined_top = true,
    globals = { '_G' },
}
files['scripts/**'] = { std = 'lua54' }
