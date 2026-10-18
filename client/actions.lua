-- Port of vMenu.Enhanced.Actions/ServerActions.cs: asks the server to do
-- something only it may do, and waits for its answer. Waits, so call it from
-- a thread, such as an entry's *_async handler.

local Log = require('shared.log')

local Actions = {}

local EVENT_INVOKE = 'vMenu.Enhanced:Action:Invoke'
local EVENT_RESULT = 'vMenu.Enhanced:Action:Result'
local TIMEOUT_MS = 10000

-- ActionStatus.cs, as the server sends them.
Actions.OK = 0
Actions.DENIED = 1
Actions.UNKNOWN_ACTION = 2
Actions.INVALID_REQUEST = 3
Actions.NOT_FOUND = 4
Actions.TOO_FAR = 5
Actions.FAILED = 6
Actions.TIMEOUT = 7
Actions.REFUSED = 8
Actions.NOT_READY = 9
Actions.RATE_LIMITED = 10

local pending = {}
local last_request_id = 0
local registered = false

function Actions.register_events()
    if registered then
        return
    end
    registered = true
    RegisterNetEvent(EVENT_RESULT, function(request_id, status, data)
        local waiting = pending[request_id]
        if not waiting then
            Log.debug(('[Actions] Reply %s arrived with nothing waiting for it.'):format(tostring(request_id)))
            return
        end
        waiting.status, waiting.data = status, data or {}
    end)
end

-- Returns the status and the server's list of strings. Arguments are strings.
function Actions.invoke(action_id, ...)
    if not registered then
        Log.error(("[Actions] '%s' was invoked before register_events ran."):format(action_id))
        return Actions.FAILED, {}
    end
    last_request_id = last_request_id + 1
    local request_id = last_request_id
    local waiting = {}
    pending[request_id] = waiting
    TriggerServerEvent(EVENT_INVOKE, action_id, request_id, { ... })
    local started = GetGameTimer()
    while waiting.status == nil do
        if GetGameTimer() - started > TIMEOUT_MS then
            pending[request_id] = nil
            Log.error(("[Actions] '%s' got no answer within %dms."):format(action_id, TIMEOUT_MS))
            return Actions.TIMEOUT, {}
        end
        Wait(0)
    end
    pending[request_id] = nil
    return waiting.status, waiting.data
end

return Actions
