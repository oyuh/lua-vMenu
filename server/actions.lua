-- Port of vMenu.Enhanced.Actions.Server/ActionRegistry.cs and ActionResponse.cs:
-- the server half of client/actions.lua. A client asks for an action by id;
-- the server checks the permission tied to it before the handler runs, so a
-- modified client gets nothing a player without the permission could not.
--
-- Upstream also writes refusals to its security webhook and staff actions to
-- its staff webhook. Those come with the webhooks in phase 6.

local Log = require('shared.log')
local Permissions = require('server.permissions')

local Actions = {}

local EVENT_INVOKE = 'vMenu.Enhanced:Action:Invoke'
local EVENT_RESULT = 'vMenu.Enhanced:Action:Result'

-- ActionStatus.cs. The numbers travel to the client.
Actions.OK = 0
Actions.DENIED = 1
Actions.UNKNOWN_ACTION = 2
Actions.INVALID_REQUEST = 3
Actions.NOT_FOUND = 4
Actions.TOO_FAR = 5
Actions.FAILED = 6
Actions.REFUSED = 8
Actions.NOT_READY = 9

local UNGATED = {}
local registered = {}

-- handler(source, args) returns a status and optionally a list of strings.
function Actions.register(action_id, permission, handler)
    if registered[action_id] then
        Log.error(("[Actions] '%s' is registered twice. The second registration is ignored."):format(action_id))
        return
    end
    registered[action_id] = { permission = permission, handler = handler }
end

function Actions.register_ungated(action_id, handler)
    Actions.register(action_id, UNGATED, handler)
end

local function reply(source, request_id, status, data)
    if not DoesPlayerExist(tostring(source)) then
        Log.debug(('[Actions] Dropping reply %d: player %d is gone.'):format(request_id, source))
        return
    end
    TriggerClientEvent(EVENT_RESULT, source, request_id, status, data or {})
end

local function invoke(source, action_id, request_id, args)
    if type(action_id) ~= 'string' or math.type(request_id) ~= 'integer' then
        return
    end
    if type(args) ~= 'table' then
        args = {}
    end
    local action = registered[action_id]
    if not action then
        Log.warning(("[Actions] Player %d asked for '%s', which nothing is registered for."):format(source, action_id))
        reply(source, request_id, Actions.UNKNOWN_ACTION)
        return
    end
    if action.permission ~= UNGATED and not Permissions.is_allowed(source, action.permission) then
        Log.info(
            ("[Actions] %s was denied '%s': missing %s."):format(GetPlayerName(source), action_id, action.permission)
        )
        reply(source, request_id, Actions.DENIED)
        return
    end
    local ok, status, data = pcall(action.handler, source, args)
    if not ok then
        Log.error(("[Actions] '%s' threw for %s: %s"):format(action_id, GetPlayerName(source), tostring(status)))
        status, data = Actions.FAILED, nil
    end
    reply(source, request_id, status, data)
end

function Actions.register_events()
    RegisterNetEvent(EVENT_INVOKE, function(action_id, request_id, args)
        invoke(source, action_id, request_id, args)
    end)
    Log.debug('[Actions] Listening for actions.')
end

return Actions
