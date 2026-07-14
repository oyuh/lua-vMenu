-- Runtime module loader. CfxLua has no `require`, so this shim provides one
-- with the same semantics busted uses in tests: dot-separated module names,
-- one execution per module, cached return value.
--
-- Must be the FIRST script in shared_scripts. Every other file in this
-- resource is a plain module (`local M = {} ... return M`) reached via
-- require(); only entrypoints are listed as client/server scripts.

if require == nil then
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
