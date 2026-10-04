-- Port of vMenu.Enhanced.Logging/Log.cs. Info and up by default; debug mode
-- (the vMenu.Enhanced.Debugging.Client/Server settings) opens up Debug.

local Log = {}

Log.levels = { debug = 0, info = 1, warning = 2, error = 3 }

local PREFIXES = {
    [Log.levels.debug] = '^7[DEBUG]^7 ',
    [Log.levels.info] = '^5[INFO]^7 ',
    [Log.levels.warning] = '^3[WARNING]^7 ',
    [Log.levels.error] = '^1[ERROR]^7 ',
}

local current = Log.levels.info

local function write(level, message)
    if level >= current then
        print(PREFIXES[level] .. tostring(message))
    end
end

function Log.is_enabled(level)
    return level >= current
end

function Log.set_debug(enabled)
    local level = enabled and Log.levels.debug or Log.levels.info
    if level == current then
        return
    end
    current = level
    write(Log.levels.info, ('[Logging] Log level is now %s.'):format(enabled and 'Debug' or 'Info'))
end

function Log.debug(message)
    write(Log.levels.debug, message)
end

function Log.info(message)
    write(Log.levels.info, message)
end

function Log.warning(message)
    write(Log.levels.warning, message)
end

function Log.error(message)
    write(Log.levels.error, message)
end

return Log
