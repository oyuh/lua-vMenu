-- Differences between FiveM Legacy and FiveM Enhanced that this resource has
-- to account for. Cfx documents no way for a script to ask which platform it
-- runs on, so for now this only reports what each side can see; the startup
-- log line it feeds is how we find a reliable signal on real servers.

local Platform = {}

-- One line for the startup log: the game build, the game name and, on the
-- server, the FXServer version string.
function Platform.describe()
    local parts = {
        ('build %s'):format(tostring(GetGameBuildNumber and GetGameBuildNumber() or '?')),
        ('game %s'):format(tostring(GetGameName and GetGameName() or '?')),
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
