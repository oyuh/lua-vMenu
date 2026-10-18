-- Differences between FiveM Legacy and FiveM Enhanced that this resource has
-- to account for. One build runs on both; code asks here instead of branching
-- on guesses.

local Platform = {}

-- IS_GAME_ENHANCED_VERSION. Only GTA V Enhanced knows it, so the call failing
-- on Legacy is the answer too.
local IS_GAME_ENHANCED_VERSION = 0x4DD998F6

local enhanced

-- Same checks upstream's Legacy build uses to refuse the wrong game
-- (vMenu.Legacy.Core/WrongGameBuild.cs): the native on the client, the
-- gamename convar on the server.
function Platform.is_enhanced()
    if enhanced == nil then
        if IsDuplicityVersion() then
            enhanced = GetConvar('gamename', ''):lower() == 'gta5enhanced'
        else
            local ok, result = pcall(Citizen.InvokeNative, IS_GAME_ENHANCED_VERSION, Citizen.ReturnResultAnyway())
            -- A BOOL native comes back as true or 1 depending on the runtime build.
            enhanced = ok and (result == true or result == 1)
        end
    end
    return enhanced
end

-- One line for the startup log.
function Platform.describe()
    local parts = {
        Platform.is_enhanced() and 'FiveM Enhanced' or 'FiveM Legacy',
        ('game build %s'):format(tostring(GetGameBuildNumber and GetGameBuildNumber() or '?')),
    }
    if IsDuplicityVersion() then
        parts[#parts + 1] = ('server %s'):format(GetConvar('version', '?'))
    end
    return table.concat(parts, ', ')
end

-- Natives are globals generated from each platform's native database, so one
-- the running game lacks is simply nil.
function Platform.has(native_name)
    return type(rawget(_G, native_name)) == 'function'
end

-- Writes a file into this resource. FiveM Enhanced refuses unless server.cfg
-- grants the resource write access to itself, so a failure names that line.
function Platform.save_file(path, contents)
    local resource = GetCurrentResourceName()
    if SaveResourceFile(resource, path, contents, -1) then
        return true
    end
    print(
        (
            "^1[ERROR]^7 Could not write %s. Add 'add_filesystem_permission "
            .. "%s write %s' to your server.cfg, above the line that starts %s."
        ):format(path, resource, resource, resource)
    )
    return false
end

return Platform
