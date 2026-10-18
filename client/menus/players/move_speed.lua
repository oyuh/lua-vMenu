-- Port of vMenu.Enhanced.Menus/Players/PlayerMoveSpeed.cs: a custom walk and
-- swim speed. The game resets the rate override every frame, and only for
-- peds this client applies it to, so each player publishes their rate in
-- their state bag and every client applies it to everyone it streams.

local Permissions = require('client.permissions')
local UserDefaults = require('client.user_defaults')
local Ticks = require('menu.ticks')
local Roster = require('client.menus.players.roster')

local MoveSpeed = {}

local NORMAL_INDEX = 10
local SCAN_MS = 1000

local ALL_SPEEDS = {
    0.1,
    0.2,
    0.3,
    0.4,
    0.5,
    0.6,
    0.7,
    0.8,
    0.9,
    1.0,
    1.1,
    1.2,
    1.3,
    1.4,
    1.5,
    1.6,
    1.7,
    1.8,
    1.9,
    2.0,
    2.5,
    3.0,
    3.5,
    4.0,
    4.5,
    5.0,
    5.5,
    6.0,
    6.5,
    7.0,
    7.5,
    8.0,
    8.5,
    9.0,
    9.5,
    10.0,
}

local Speed = {}
Speed.__index = Speed

local function speed(spec)
    local self = setmetatable(spec, Speed)
    self.speeds = {}
    for _, rate in ipairs(ALL_SPEEDS) do
        if rate <= self.max then
            self.speeds[#self.speeds + 1] = rate
        end
    end
    self.remote = {}
    return self
end

function Speed:allowed()
    return Permissions.is_allowed(self.permission)
end

function Speed:enabled()
    return UserDefaults.get(self.enabled_preference) == true and self:allowed()
end

-- 1-based, into self.speeds. A saved rate that is not on the list reads as 1x.
function Speed:index()
    local stored = UserDefaults.get(self.rate_preference)
    for index, rate in ipairs(self.speeds) do
        if math.abs(rate - stored) < 0.001 then
            return index
        end
    end
    return NORMAL_INDEX
end

function Speed:rate()
    return self.speeds[self:index()]
end

function Speed:set_enabled(on)
    if on and not self:allowed() then
        return
    end
    UserDefaults.set(self.enabled_preference, on)
end

function Speed:set_index(index)
    local rate = self.speeds[index]
    if rate then
        UserDefaults.set(self.rate_preference, rate)
    end
end

-- 0 means "no override", which is what other clients read when it is off.
function Speed:publish()
    local rate = self:enabled() and self:rate() or 0.0
    if self.published ~= rate then
        LocalPlayer.state:set(self.state_key, rate, true)
        self.published = rate
    end
end

function Speed:reload()
    self:publish()
    Ticks.reevaluate()
end

function Speed:read(player)
    local rate = tonumber(Player(player.server_id).state[self.state_key]) or 0
    if rate > 0 then
        self.remote[#self.remote + 1] = { ped = player.ped, rate = math.max(self.speeds[1], math.min(rate, self.max)) }
    end
end

function Speed:frame()
    if self:enabled() then
        self.apply(PlayerPedId(), self:rate())
    end
    for _, overridden in ipairs(self.remote) do
        if DoesEntityExist(overridden.ped) then
            self.apply(overridden.ped, overridden.rate)
        end
    end
end

function Speed:register()
    UserDefaults.on_changed(self.enabled_preference, function()
        self:reload()
    end)
    UserDefaults.on_changed(self.rate_preference, function()
        self:reload()
    end)
    Ticks.register(self.name, function()
        self:frame()
    end, {
        condition = function()
            return self:enabled() or #self.remote > 0
        end,
    })
end

MoveSpeed.walk = speed({
    name = 'Player.MoveSpeed',
    permission = 'vMenu.Enhanced.Menus.PlayerOptions.MoveSpeed',
    state_key = 'vMenu:moveSpeed',
    enabled_preference = 'playerMoveSpeedEnabled',
    rate_preference = 'playerMoveSpeed',
    max = 10.0,
    apply = function(ped, rate)
        SetPedMoveRateOverride(ped, rate)
    end,
})

MoveSpeed.swim = speed({
    name = 'Player.SwimSpeed',
    permission = 'vMenu.Enhanced.Menus.PlayerOptions.SwimSpeed',
    state_key = 'vMenu:swimSpeed',
    enabled_preference = 'playerSwimSpeedEnabled',
    rate_preference = 'playerSwimSpeed',
    max = 3.0,
    apply = function(ped, rate)
        SetPedMoveRateInWaterOverride(ped, rate)
    end,
})

local function scan()
    local walk, swim = MoveSpeed.walk, MoveSpeed.swim
    walk:publish()
    swim:publish()
    walk.remote, swim.remote = {}, {}
    Roster.refresh()
    local own = PlayerId()
    for _, player in ipairs(Roster.all()) do
        if player.slot ~= own then
            walk:read(player)
            swim:read(player)
        end
    end
    Ticks.reevaluate()
end

function MoveSpeed.init()
    MoveSpeed.walk:register()
    MoveSpeed.swim:register()
    Ticks.register('Player.MoveSpeed.Scan', scan, { rate = SCAN_MS })
end

return MoveSpeed
