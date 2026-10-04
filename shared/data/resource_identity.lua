-- Port of vMenu.Enhanced.Data/ResourceIdentity.cs. The folder has to be named
-- vMenu.Enhanced: the filesystem permission, the exec @vMenu.Enhanced/...
-- lines, every generated example file, plugin event names, and player KVP all
-- depend on it, so a renamed copy refuses to start instead of failing later.

local ResourceIdentity = {}

ResourceIdentity.REQUIRED_NAME = 'vMenu.Enhanced'

local RULE = '###############################################################################'

function ResourceIdentity.is_correctly_named(resource_name)
    return resource_name == ResourceIdentity.REQUIRED_NAME
end

-- The lines to log when the resource is installed under the wrong name.
function ResourceIdentity.mismatch_report(resource_name, side)
    local actual = (resource_name == nil or resource_name:match('^%s*$')) and '<unknown>' or resource_name
    local required = ResourceIdentity.REQUIRED_NAME

    return {
        RULE,
        ('  vMenu Enhanced did not start (%s side).'):format(side),
        '',
        ("  It is installed as '%s', but it has to be named '%s'."):format(actual, required),
        '',
        '  Rename the folder in your resources directory to:',
        '      ' .. required,
        '',
        '  Then make your server.cfg match it:',
        ('      exec @%s/config/permissions.cfg'):format(required),
        ('      exec @%s/config/configuration.cfg'):format(required),
        ('      add_filesystem_permission %s write %s'):format(required, required),
        '      ensure ' .. required,
        RULE,
    }
end

return ResourceIdentity
