-- Port of the DebugLog class in vMenuServer/MainServer.cs, plus the mutable
-- MainServer.DebugMode flag. Debug mode starts from the server_debug_mode
-- manifest metadata and can be toggled at runtime with `vmenuserver debug`.

local Log = {}

-- DebugLog.LogLevel (numeric values preserved from the C# enum).
Log.levels = { none = 0, error_ = 1, success = 2, warning = 3, info = 4 }

Log.debug_mode = (GetResourceMetadata(GetCurrentResourceName(), 'server_debug_mode', 0) or '') == 'true'

local PREFIXES = {
    [Log.levels.error_] = '^1[vMenu] [ERROR]^7 ',
    [Log.levels.success] = '^2[vMenu] [SUCCESS]^7 ',
    [Log.levels.warning] = '^3[vMenu] [WARNING]^7 ',
    [Log.levels.info] = '^5[vMenu] [INFO]^7 ',
}

-- Only prints when debug mode is on, except errors and warnings which always
-- print (matching DebugLog.Log).
function Log.log(data, level)
    level = level or Log.levels.none
    if Log.debug_mode or level == Log.levels.error_ or level == Log.levels.warning then
        local prefix = PREFIXES[level] or '[vMenu] '
        print(('%s[DEBUG LOG] %s'):format(prefix, tostring(data)))
    end
end

return Log
