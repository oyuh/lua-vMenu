-- Port of the parts of upstream's Streaming.cs that are in use: loads game
-- assets and waits for them. Waits, so call it from a thread.

local Streaming = {}

local TIMEOUT_MS = 5000

local function wait_for(loaded)
    local started = GetGameTimer()
    while not loaded() do
        if GetGameTimer() - started > TIMEOUT_MS then
            return false
        end
        Wait(0)
    end
    return true
end

-- False when it did not load in time; the request is dropped then.
function Streaming.clip_set(name)
    RequestClipSet(name)
    if wait_for(function()
        return HasClipSetLoaded(name)
    end) then
        return true
    end
    RemoveClipSet(name)
    return false
end

return Streaming
