-- Runtime module loader providing a require() with the same semantics busted
-- uses in tests: dot-separated module names, one execution per module, cached
-- return value.
--
-- Must be the FIRST script in shared_scripts. Every other file in this
-- resource is a plain module (`local M = {} ... return M`) reached via
-- require(); only entrypoints are listed as client/server scripts.
--
-- We install unconditionally rather than guarding on `require == nil`: newer
-- FiveM artifacts ship a built-in require() whose module resolution does not
-- understand our dot-pathed modules (it raises "module 'shared.util' not
-- found"), so we must override it with our LoadResourceFile-based loader. This
-- file only ever runs inside the CfxLua runtime; the busted suite loads
-- modules with Lua's native require and never executes bootstrap.lua.
do
    local loaded = {}

    function require(name)
        local cached = loaded[name]
        if cached ~= nil then
            return cached
        end

        local path = name:gsub('%.', '/') .. '.lua'
        local source = LoadResourceFile(GetCurrentResourceName(), path)
        if not source then
            error(("module '%s' not found (is '%s' in the fxmanifest files list?)"):format(name, path), 2)
        end

        local chunk, err = load(source, '@' .. path)
        if not chunk then
            error(("module '%s' failed to compile: %s"):format(name, err), 2)
        end

        local result = chunk()
        if result == nil then
            result = true
        end
        loaded[name] = result
        return result
    end
end
