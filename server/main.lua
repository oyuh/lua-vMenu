-- Port of vMenu.Enhanced.Core.Server/CoreServer.cs: the server entrypoint.

local Log = require('shared.log')
local Platform = require('shared.platform')
local ResourceIdentity = require('shared.data.resource_identity')
local Config = require('shared.config')
local ConfigurationExample = require('shared.data.configuration_example')
local Permissions = require('server.permissions')

local RESOURCE = GetCurrentResourceName()

if not ResourceIdentity.is_correctly_named(RESOURCE) then
    for _, line in ipairs(ResourceIdentity.mismatch_report(RESOURCE, 'server')) do
        Log.error(line)
    end
    return
end

Permissions.init()
Config.init()

if Platform.save_file(ConfigurationExample.RESOURCE_PATH, ConfigurationExample.render()) then
    Log.debug(('[Config] Wrote %s.'):format(ConfigurationExample.RESOURCE_PATH))
end
Permissions.write_example()

Permissions.register_events()

Log.info(
    ('[Core] Loaded vMenu Enhanced (Lua) v%s on %s.'):format(
        GetResourceMetadata(RESOURCE, 'version', 0),
        Platform.describe()
    )
)
