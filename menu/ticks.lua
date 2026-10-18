-- Port of MenuAPI/ticks/MenuTicks.cs, MenuTickEngine.cs, MenuTickHandle.cs
-- and MenuTickRate.cs. A tick runs only while its condition holds: stopping
-- ends its thread instead of idling it, so a closed menu costs nothing. The
-- wait comes after the handler returns, so a slow iteration delays the next
-- one instead of overlapping it. Handlers run in their own CfxLua thread, so
-- they may Wait() inside, like the C# handlers that await.

local Log = require('shared.log')
local FrameState = require('menu.frame_state')

local Ticks = {}

-- A per frame tick would log sixty errors a second while broken. Five is
-- enough to prove it was not a one off.
local MAX_FAILURES = 5

local handles = {}
local reevaluate_pending = false
local initialized = false

local function notify(handle, callback)
    if not callback then
        return
    end
    -- The lifecycle callbacks are the teardown path, so one throwing must not
    -- leave a scaleform loaded or a texture dictionary streamed in forever.
    local ok, err = pcall(callback)
    if not ok then
        Log.error(('[MenuAPI] %s lifecycle callback threw: %s'):format(handle.name, tostring(err)))
    end
end

-- Fails closed: a throwing condition must not leave a tick stuck on.
local function should_run(handle)
    if handle.disposed then
        return false
    end
    if handle.condition == nil then
        return handle.manually_started
    end
    local ok, result = pcall(handle.condition)
    if not ok then
        Log.error(
            ('[MenuAPI] %s condition threw and is being treated as off: %s'):format(handle.name, tostring(result))
        )
        return false
    end
    return result == true
end

local function drive(handle)
    handle.driver_in_flight = true
    CreateThread(function()
        -- Always yield first, so a tick body runs from the tick pump and not
        -- inside whatever callback started it.
        Wait(0)
        while handle.running do
            local ok, err = pcall(handle.handler)
            if ok then
                handle.failures = 0
            else
                Log.error(('[MenuAPI] %s threw: %s'):format(handle.name, tostring(err)))
                handle.failures = handle.failures + 1
                if handle.failures >= MAX_FAILURES then
                    Log.error(('[MenuAPI] %s stopped after %d consecutive failures.'):format(handle.name, MAX_FAILURES))
                    handle.running = false
                    notify(handle, handle.on_stopped)
                    break
                end
            end
            Wait(handle.rate)
        end
        handle.driver_in_flight = false
    end)
end

local function apply(handle)
    local run = should_run(handle)
    if run == handle.running then
        return
    end
    handle.running = run
    if not run then
        notify(handle, handle.on_stopped)
        return
    end
    handle.failures = 0
    notify(handle, handle.on_started)
    -- A restart inside one frame leaves the previous driver mid Wait; a second
    -- driver would be the overlap this module exists to prevent.
    if not handle.driver_in_flight then
        drive(handle)
    end
end

-- opts: rate (ms between iterations, 0 = every frame), condition, on_started,
-- on_stopped, auto_start (default true; only used without a condition).
function Ticks.register(name, handler, opts)
    opts = opts or {}
    local handle = {
        name = name,
        handler = handler,
        rate = opts.rate or 0,
        condition = opts.condition,
        on_started = opts.on_started,
        on_stopped = opts.on_stopped,
        manually_started = opts.auto_start ~= false,
        running = false,
        driver_in_flight = false,
        failures = 0,
        disposed = false,
    }
    handles[#handles + 1] = handle
    apply(handle)
    return handle
end

function Ticks.start(handle)
    handle.manually_started = true
    apply(handle)
end

function Ticks.stop(handle)
    handle.manually_started = false
    apply(handle)
end

function Ticks.dispose(handle)
    if handle.disposed then
        return
    end
    handle.disposed = true
    apply(handle)
    for index = #handles, 1, -1 do
        if handles[index] == handle then
            table.remove(handles, index)
        end
    end
end

-- Deliberately not immediate. Opening a submenu closes the parent and opens
-- the child in one go; acting on each half would see "no menu open" for an
-- instant and tear down the instructional buttons and textures only to build
-- them again. Waiting a frame lets a close and an open cancel out.
function Ticks.reevaluate()
    reevaluate_pending = true
end

function Ticks.describe()
    local lines = {}
    for _, handle in ipairs(handles) do
        local rate = handle.rate <= 0 and 'per frame' or ('every %dms'):format(handle.rate)
        lines[#lines + 1] = ('%s (%s): %s'):format(handle.name, rate, handle.running and 'running' or 'stopped')
    end
    return lines
end

local function flush()
    FrameState.invalidate()
    if not reevaluate_pending then
        return
    end
    reevaluate_pending = false
    -- Indexed, because a condition is caller code that may register or
    -- dispose a tick mid pass.
    local index = 1
    while index <= #handles do
        apply(handles[index])
        index = index + 1
    end
end

-- prefix is MenuInput's command prefix, so two resources shipping MenuAPI do
-- not fight over one command name.
function Ticks.init(prefix)
    if initialized then
        return
    end
    initialized = true
    RegisterCommand(prefix .. 'ticks', function()
        Log.info(('[MenuAPI] %d ticks registered:'):format(#handles))
        for _, line in ipairs(Ticks.describe()) do
            Log.info('[MenuAPI]   ' .. line)
        end
    end, false)
    Ticks.register('Menu.Scheduler', flush)
end

return Ticks
