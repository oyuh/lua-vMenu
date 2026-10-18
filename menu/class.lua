-- Classes for MenuAPI objects. Assigning one of a class's listed properties
-- marks the NUI snapshot dirty when the value changes, like the C# setters
-- that go through MenuNui.Change. Without this, `item.Text = 'x'` from any
-- caller would leave the open menu showing the old text.

local Nui = require('menu.nui')

local Class = {}

-- properties: names to track, added to whatever base already tracks.
function Class.new(base, properties)
    local cls = {}
    cls.properties = setmetatable({}, { __index = base and base.properties or nil })
    for _, name in ipairs(properties or {}) do
        cls.properties[name] = true
    end

    cls.__index = function(self, key)
        local value = rawget(self, '_p')[key]
        if value ~= nil then
            return value
        end
        return cls[key]
    end

    cls.__newindex = function(self, key, value)
        if not cls.properties[key] then
            rawset(self, key, value)
            return
        end
        local values = rawget(self, '_p')
        if values[key] ~= value then
            values[key] = value
            Nui.invalidate()
        end
    end

    if base then
        setmetatable(cls, { __index = base })
    end
    return cls
end

function Class.instance(cls)
    return setmetatable({ _p = {} }, cls)
end

return Class
