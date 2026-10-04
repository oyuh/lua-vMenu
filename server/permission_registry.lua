-- Port of vMenu.Enhanced.Permissions.Server/PermissionRegistry.cs and
-- PermissionNode.cs: the permission tree. Structural edges follow the dotted
-- name (so the client can rebuild them from strings); extra parents come from
-- a category's additional_parents and are read when checking, never walked.
-- Names are case-insensitive, like the C# OrdinalIgnoreCase dictionaries.

local Log = require('shared.log')
local PermissionPath = require('shared.permission_path')
local Declared = require('shared.data.permissions')

local Registry = {}

local nodes = {} -- lowercased name -> node
local roots = {}
-- Tree topology never changes after startup except through register_dynamic /
-- unregister_dynamic, which clear this. Permission results are never cached.
local chain_cache = {}

local function by_name(left, right)
    return left.name < right.name
end

local function find_structural_parent(permission)
    for _, grant in ipairs(PermissionPath.container_grants(permission)) do
        local parent = nodes[grant:lower()]
        if parent then
            return parent
        end
    end
    return nil
end

local function mark_staff_only_below(node)
    for _, child in ipairs(node.children) do
        child.staff_only = child.staff_only or (node.staff_only and node.cascades)
        mark_staff_only_below(child)
    end
end

-- Builds the tree from shared/data/permissions.lua. Call once at startup.
function Registry.build()
    nodes, roots, chain_cache = {}, {}, {}

    local declared = {}
    for _, category in ipairs(Declared) do
        for _, permission in ipairs(category.permissions) do
            local key = permission.name:lower()
            if nodes[key] then
                Log.error(("[Permissions] Duplicate permission '%s'."):format(permission.name))
            elseif not PermissionPath.is_valid(permission.name) then
                Log.error(("[Permissions] '%s' is not a valid permission name."):format(permission.name))
            else
                local staff_only, cascades = category.staff_only, category.cascades
                if permission.staff_only ~= nil then
                    staff_only, cascades = permission.staff_only, permission.cascades
                end
                local node = {
                    name = permission.name,
                    staff_only = staff_only == true,
                    cascades = cascades ~= false,
                    extra_parents = category.additional_parents or {},
                    children = {},
                }
                nodes[key] = node
                declared[#declared + 1] = node
            end
        end
    end

    table.sort(declared, by_name)
    for _, node in ipairs(declared) do
        local parent = find_structural_parent(node.name)
        if parent then
            node.parent = parent
            table.insert(parent.children, node)
        else
            roots[#roots + 1] = node
        end
    end
    table.sort(roots, by_name)
    for _, node in pairs(nodes) do
        table.sort(node.children, by_name)
    end
    -- A container kept to staff is meaningless if the example hands its
    -- contents to everybody.
    for _, root in ipairs(roots) do
        mark_staff_only_below(root)
    end

    for _, node in pairs(nodes) do
        for _, extra in ipairs(node.extra_parents) do
            if not nodes[extra:lower()] then
                Log.error(
                    ("[Permissions] '%s' names unregistered permission '%s' as an additional parent."):format(
                        node.name,
                        extra
                    )
                )
            end
        end
    end

    Log.debug(('[Permissions] Registered %d permissions across %d roots.'):format(#declared, #roots))
end

-- source names the config file (or plugin) it came from in the generated
-- example. staff_only adds to whatever the parent already imposes.
function Registry.register_dynamic(permission, source, staff_only)
    if not PermissionPath.is_valid(permission) then
        Log.warning(("[Permissions] Ignoring runtime permission '%s': not a valid permission name."):format(permission))
        return false
    end
    if nodes[permission:lower()] then
        return true
    end
    local parent = find_structural_parent(permission)
    if not parent then
        Log.warning(
            ("[Permissions] Ignoring runtime permission '%s': no registered container grant above it."):format(
                permission
            )
        )
        return false
    end

    local node = {
        name = permission,
        source = source,
        staff_only = (parent.staff_only and parent.cascades) or staff_only == true,
        cascades = true,
        extra_parents = parent.extra_parents,
        parent = parent,
        children = {},
    }
    table.insert(parent.children, node)
    table.sort(parent.children, by_name)
    nodes[permission:lower()] = node
    chain_cache = {}
    return true
end

-- Only removes what register_dynamic added; vMenu's own permissions are fixed
-- for the lifetime of the resource. Returns how many nodes went.
function Registry.unregister_dynamic(permission)
    local node = nodes[permission:lower()]
    if not node or not node.source then
        return 0
    end
    if node.parent then
        for index = #node.parent.children, 1, -1 do
            if node.parent.children[index] == node then
                table.remove(node.parent.children, index)
            end
        end
    end
    local function drop(target)
        local removed = 1
        for _, child in ipairs(target.children) do
            removed = removed + drop(child)
        end
        nodes[target.name:lower()] = nil
        return removed
    end
    local removed = drop(node)
    chain_cache = {}
    return removed
end

function Registry.get(permission)
    return nodes[permission:lower()]
end

function Registry.count()
    local count = 0
    for _ in pairs(nodes) do
        count = count + 1
    end
    return count
end

function Registry.roots()
    return roots
end

-- Container grants nearest first, then cross-tree parents, then Everything
-- last, so the grant an owner actually wrote is usually found in a probe or two.
function Registry.ancestor_chain(permission)
    local key = permission:lower()
    local cached = chain_cache[key]
    if cached then
        return cached
    end

    local ordered, seen, queue, head = {}, {}, {}, 1
    local function enqueue(name)
        if not seen[name:lower()] then
            seen[name:lower()] = true
            ordered[#ordered + 1] = name
            queue[#queue + 1] = name
        end
    end

    enqueue(permission)
    while head <= #queue do
        local current = queue[head]
        head = head + 1
        for _, grant in ipairs(PermissionPath.container_grants(current)) do
            enqueue(grant)
        end
        local node = nodes[current:lower()]
        for _, extra in ipairs(node and node.extra_parents or {}) do
            enqueue(extra)
        end
    end
    enqueue(PermissionPath.EVERYTHING)

    chain_cache[key] = ordered
    return ordered
end

-- Pre-order walk as { node, depth } pairs, depth counted from start.
local function walk(node, depth, out)
    out[#out + 1] = { node = node, depth = depth }
    for _, child in ipairs(node.children) do
        walk(child, depth + 1, out)
    end
    return out
end

function Registry.tree()
    local out = {}
    for _, root in ipairs(roots) do
        walk(root, 0, out)
    end
    return out
end

function Registry.subtree(permission)
    local node = nodes[permission:lower()]
    return node and walk(node, 0, {}) or {}
end

return Registry
