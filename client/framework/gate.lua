-- Port of vMenu.Enhanced.MenuFramework/MenuGate.cs: whether one entry is
-- available to the player. Anywhere a gate is accepted, a permission name
-- string works as shorthand for Gate.permission(name).

local Log = require('shared.log')
local Config = require('shared.config')
local Permissions = require('client.permissions')

local Gate = {}

local function new(evaluate)
    return { evaluate = evaluate }
end

Gate.ALWAYS = new(function()
    return true
end)

Gate.NEVER = new(function()
    return false
end)

function Gate.permission(permission)
    return new(function()
        return Permissions.is_allowed(permission)
    end)
end

-- A gate the server owner controls through a bool setting instead of aces.
function Gate.setting(name)
    return new(function()
        return Config.value(name) == true
    end)
end

function Gate.when(predicate)
    return new(predicate)
end

local function normalize(gate)
    if gate == nil then
        return Gate.ALWAYS
    elseif type(gate) == 'string' then
        return Gate.permission(gate)
    end
    return gate
end

Gate.normalize = normalize

-- Fails closed: a refresh walks every entry in every menu, so one throwing
-- predicate must not abort it.
function Gate.evaluate(gate)
    local ok, result = pcall(normalize(gate).evaluate)
    if not ok then
        Log.error('[Menu] A gate threw and is being treated as denied: ' .. tostring(result))
        return false
    end
    return result == true
end

function Gate.all(...)
    local gates = { ... }
    return new(function()
        for _, gate in ipairs(gates) do
            if not Gate.evaluate(gate) then
                return false
            end
        end
        return true
    end)
end

function Gate.any(...)
    local gates = { ... }
    return new(function()
        for _, gate in ipairs(gates) do
            if Gate.evaluate(gate) then
                return true
            end
        end
        return false
    end)
end

return Gate
