-- Port of vMenu.Enhanced.Core/Main.cs: the client entrypoint.

local Log = require('shared.log')
local Platform = require('shared.platform')
local ResourceIdentity = require('shared.data.resource_identity')

local RESOURCE = GetCurrentResourceName()

if not ResourceIdentity.is_correctly_named(RESOURCE) then
    for _, line in ipairs(ResourceIdentity.mismatch_report(RESOURCE, 'client')) do
        Log.error(line)
    end
    return
end

Log.info(
    ('[Core] Loaded vMenu Enhanced (Lua) v%s on %s.'):format(
        GetResourceMetadata(RESOURCE, 'version', 0),
        Platform.describe()
    )
)
