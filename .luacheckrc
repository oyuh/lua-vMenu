std = 'lua54'
codes = true
max_line_length = 120
self = false

exclude_files = {
    'vendor/**',
    'client/data/**', -- generated tables
    '.upstream/**',
    -- CI installs the Lua toolchain into the workspace (leafo/gh-actions-*)
    '.lua/**',
    '.luarocks/**',
    '.install/**',
    '.source/**',
}

-- CitizenFX (CfxLua) runtime globals.
-- Every native the test mock fakes is automatically a known global — the
-- mock (tests/mocks/cfx.lua) is the single source of truth for the native
-- surface the ported code uses. Natives used only by the in-game rendering
-- layer (never faked in specs) are listed manually below.
local mock_natives = dofile('tests/mocks/cfx.lua').NATIVE_NAMES

read_globals = {
    -- events / runtime not covered by the mock's native list
    'RemoveEventHandler', 'SetTimeout',
    -- server-side natives without mock entries yet
    'NetworkGetEntityFromNetworkId', 'NetworkGetEntityOwner', 'IsPedAPlayer',
    'TaskLeaveVehicle', 'SetEntityCoords',
    -- game state / hud (rendering layer)
    'IsPauseMenuActive', 'IsPauseMenuRestarting', 'IsScreenFadedIn',
    'IsPlayerSwitchInProgress', 'IsEntityDead', 'IsWarningMessageActive',
    'PlaySoundFrontend',
    -- controls
    'IsControlPressed', 'IsDisabledControlPressed', 'IsControlJustPressed',
    'IsDisabledControlJustPressed', 'IsControlJustReleased', 'IsDisabledControlJustReleased',
    'DisableControlAction', 'IsInputDisabled', 'GetControlInstructionalButton',
    -- drawing / text
    'GetSafeZoneSize', 'SetScriptGfxAlign', 'SetScriptGfxAlignParams',
    'ResetScriptGfxAlign', 'SetScriptGfxDrawOrder', 'DrawRect', 'DrawSprite',
    'HasStreamedTextureDictLoaded', 'RequestStreamedTextureDict', 'SetStreamedTextureDictAsNoLongerNeeded',
    'BeginTextCommandDisplayText', 'EndTextCommandDisplayText', 'AddTextComponentSubstringPlayerName',
    'SetTextFont', 'SetTextScale', 'SetTextJustification', 'SetTextColour', 'SetTextWrap',
    'GetTextScaleHeight', 'BeginTextCommandLineCount', 'EndTextCommandLineCount',
    -- scaleforms
    'RequestScaleformMovie', 'HasScaleformMovieLoaded', 'SetScaleformMovieAsNoLongerNeeded',
    'BeginScaleformMovieMethod', 'EndScaleformMovieMethod', 'PushScaleformMovieMethodParameterString',
    'ScaleformMovieMethodAddParamInt', 'ScaleformMovieMethodAddParamBool',
    'BeginTextCommandScaleformString', 'EndTextCommandScaleformString', 'AddTextComponentInteger',
    'DrawScaleformMovie', 'DrawScaleformMovieFullscreen', 'GetHairRgbColor', 'GetMakeupRgbColor',
    -- cfx lua extensions
    'vector2', 'vector3', 'vector4', 'quat', 'json', 'msgpack',
    'exports', 'Citizen',
    'source', -- implicit event source (server-side handlers)
}
for _, name in ipairs(mock_natives) do
    read_globals[#read_globals + 1] = name
end

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
