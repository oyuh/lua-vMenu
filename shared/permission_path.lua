-- Port of vMenu.Enhanced.Data/Permissions/PermissionPath.cs, plus the two name
-- sanitizers that feed it (Menus/CategoryName.cs, PluginContracts/PluginId.cs).
-- A permission whose last segment is All grants everything in its container,
-- which is what lets the client resolve inheritance from names alone.

local PermissionPath = {}

PermissionPath.ROOT = 'vMenu.Enhanced'
PermissionPath.EVERYTHING = 'vMenu.Enhanced.Everything'
PermissionPath.ALL_SUFFIX = '.All'

-- Case-insensitive, like the C# OrdinalIgnoreCase comparisons.
function PermissionPath.is_container_grant(permission)
    return permission:sub(-#PermissionPath.ALL_SUFFIX):lower() == PermissionPath.ALL_SUFFIX:lower()
end

-- nil when the permission sits directly under ROOT.
function PermissionPath.get_container(permission)
    local index = permission:match('^.*()%.')
    if index and index > #PermissionPath.ROOT + 1 then
        return permission:sub(1, index - 1)
    end
    return nil
end

-- The .All permissions that grant this one, nearest first.
function PermissionPath.container_grants(permission)
    local grants = {}
    local container = PermissionPath.get_container(permission)
    while container do
        local grant = container .. PermissionPath.ALL_SUFFIX
        -- A container grant is never listed as its own parent.
        if grant:lower() ~= permission:lower() then
            grants[#grants + 1] = grant
        end
        container = PermissionPath.get_container(container)
    end
    return grants
end

function PermissionPath.is_valid_segment(segment)
    return type(segment) == 'string' and segment:match('^[%w_]+$') ~= nil
end

function PermissionPath.is_valid(permission)
    if type(permission) ~= 'string' or permission:sub(1, #PermissionPath.ROOT + 1) ~= PermissionPath.ROOT .. '.' then
        return false
    end
    for segment in (permission:sub(#PermissionPath.ROOT + 2) .. '.'):gmatch('([^.]*)%.') do
        if not PermissionPath.is_valid_segment(segment) then
            return false
        end
    end
    return true
end

-- CategoryName.ToPermissionSegment: lowercased, every run of unusable
-- characters collapsed into one underscore, no leading or trailing ones.
function PermissionPath.category_segment(name)
    local segment = (name or ''):lower():gsub('[^%w]+', '_'):gsub('^_+', ''):gsub('_+$', '')
    return segment
end

-- PluginId.Sanitize: every character that is not an ASCII letter or digit
-- becomes an underscore, so the id fits inside ACE and convar names.
function PermissionPath.plugin_id(resource_name)
    -- Per character, not per byte, so a non-ASCII letter is one underscore.
    local id = (resource_name or ''):gsub(utf8.charpattern, function(char)
        return char:match('^[%w]$') and char or '_'
    end)
    return id
end

return PermissionPath
