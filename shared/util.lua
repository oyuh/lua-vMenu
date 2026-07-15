-- Shared helpers: logging and debug mode.
-- Debug mode mirrors upstream: driven by client_debug_mode / server_debug_mode
-- metadata in fxmanifest.lua (ConfigManager.DebugMode in C#).

local Util = {}

function Util.is_server()
    return IsDuplicityVersion()
end

function Util.is_debug_enabled()
    local key = Util.is_server() and 'server_debug_mode' or 'client_debug_mode'
    return (GetResourceMetadata('vMenu', key, 0) or ''):lower() == 'true'
end

function Util.log(message)
    print(('[vMenu] %s'):format(message))
end

function Util.debug_log(message)
    if Util.is_debug_enabled() then
        print(('[vMenu] [DEBUG] %s'):format(message))
    end
end

-- Server only: every identifier for a player (license/steam/discord/ip/...),
-- equivalent to CitizenFX's Player.Identifiers collection.
function Util.player_identifiers(player_handle)
    local handle = tostring(player_handle)
    local identifiers = {}
    for i = 0, GetNumPlayerIdentifiers(handle) - 1 do
        identifiers[#identifiers + 1] = GetPlayerIdentifier(handle, i)
    end
    return identifiers
end

return Util
