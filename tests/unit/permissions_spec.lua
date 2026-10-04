-- Specs for the server permission tree (server/permission_registry.lua,
-- server/catalogs.lua, server/permissions.lua). The generated example is
-- compared byte for byte with the one upstream vMenu Enhanced writes from the
-- same config files, which pins the declared tree, the runtime categories,
-- sorting, staff-only resolution and annotations at once.

local CfxMock = require('tests.mocks.cfx')

local MODULES = {
    'shared.log',
    'shared.platform',
    'shared.json_compat',
    'shared.permission_path',
    'shared.data.permissions_example',
    'server.permission_registry',
    'server.catalogs',
    'server.permissions',
}

local function read(path)
    local file = assert(io.open(path, 'rb'))
    local contents = file:read('a')
    file:close()
    return contents
end

local function start(cfx, files)
    for path, contents in pairs(files) do
        cfx:set_resource_file(path, contents)
    end
    for _, name in ipairs(MODULES) do
        package.loaded[name] = nil
    end
    local Permissions = require('server.permissions')
    Permissions.init()
    return Permissions
end

local SHIPPED = {
    'config/model-whitelists.json',
    'config/vehicle-categories.json',
    'config/ped-models.json',
    'config/weapons.json',
}

local function shipped_files()
    local files = {}
    for _, path in ipairs(SHIPPED) do
        files[path] = read(path)
    end
    return files
end

describe('permissions.cfg.example', function()
    local cfx

    before_each(function()
        cfx = CfxMock.new({ resource_name = 'vMenu.Enhanced', is_server = true }):install()
    end)

    after_each(function()
        cfx:uninstall()
    end)

    it('matches the file upstream generates from the shipped config', function()
        local Permissions = start(cfx, shipped_files())
        assert.are.equal(read('tests/fixtures/upstream/permissions.cfg.example'), Permissions.render_example())
    end)

    -- Owners hand-edit these files: order is menu order and the first
    -- category to claim a model keeps it.
    it('registers owner categories in file order, first claim wins', function()
        local files = shipped_files()
        files['config/vehicle-categories.json'] = [[{
            // comments and trailing commas are fine
            "Zeta Cars": ["Adder", "zentorno",],
            "Alpha": ["adder"],
            "Sports": ["t20"],
            "!!!": ["comet2"],
        }]]
        local Permissions = start(cfx, files)
        local Catalogs = require('server.catalogs')
        local Registry = require('server.permission_registry')

        local models, names = Catalogs.categorised_vehicles()
        assert.same({ 'adder', 'zentorno' }, models)
        assert.same({ 'Zeta Cars', 'Zeta Cars' }, names)
        assert.is_not_nil(Registry.get('vMenu.Enhanced.Menus.VehicleSpawner.Categories.zeta_cars'))
        -- Alpha lost its only model, Sports would hijack a game class, !!! has no usable name.
        assert.is_nil(Registry.get('vMenu.Enhanced.Menus.VehicleSpawner.Categories.alpha'))
        assert.matches(
            '# from config/vehicle%-categories.json\n      add_ace builtin.everyone '
                .. '"vMenu.Enhanced.Menus.VehicleSpawner.Categories.zeta_cars" allow',
            Permissions.render_example()
        )
    end)
end)

describe('permission checks', function()
    local cfx, Permissions

    before_each(function()
        cfx = CfxMock.new({ resource_name = 'vMenu.Enhanced', is_server = true }):install()
        local files = shipped_files()
        files['config/model-whitelists.json'] = '{ "vehicles": ["Rhino"] }'
        Permissions = start(cfx, files)
        cfx:add_player(1)
    end)

    after_each(function()
        cfx:uninstall()
    end)

    it('grants through every .All container above a permission', function()
        assert.is_false(Permissions.is_allowed(1, 'vMenu.Enhanced.Menus.Admin.Kick'))
        cfx:grant_ace(1, 'vMenu.Enhanced.Menus.All')
        assert.is_true(Permissions.is_allowed(1, 'vMenu.Enhanced.Menus.Admin.ClearArea'))
        assert.is_false(Permissions.is_allowed(1, 'vMenu.Enhanced.NoClip'))
    end)

    -- AdditionalParents: the spawner's .All also covers whitelisted vehicles.
    it('grants whitelisted models through the extra parent', function()
        local rhino = 'vMenu.Enhanced.SupplementalPermissions.VehicleModels.rhino'
        assert.is_false(Permissions.is_allowed(1, rhino))
        cfx:grant_ace(1, 'vMenu.Enhanced.Menus.VehicleSpawner.All')
        assert.is_true(Permissions.is_allowed(1, rhino))
    end)

    it('sends the smallest granted set', function()
        cfx:grant_ace(1, 'vMenu.Enhanced.Menus.PlayerOptions.All')
        cfx:grant_ace(1, 'vMenu.Enhanced.Menus.PlayerOptions.Godmode')
        cfx:grant_ace(1, 'vMenu.Enhanced.NoClip')
        assert.same({ 'vMenu.Enhanced.Menus.PlayerOptions.All', 'vMenu.Enhanced.NoClip' }, Permissions.granted(1))
        cfx:grant_ace(1, 'vMenu.Enhanced.Everything')
        assert.same({ 'vMenu.Enhanced.Everything' }, Permissions.granted(1))
    end)

    it('refuses players who are not connected', function()
        cfx:grant_ace(1, 'vMenu.Enhanced.Everything')
        assert.is_false(Permissions.is_allowed(2, 'vMenu.Enhanced.NoClip'))
        assert.same({}, Permissions.granted(2))
    end)
end)

-- The server -> client payload is positional, so the round trip is tested
-- through the real event tuple rather than by calling the client directly.
describe('client permissions after a sync', function()
    local function sync(grants, whitelist)
        local server = CfxMock.new({ resource_name = 'vMenu.Enhanced', is_server = true }):install()
        local files = shipped_files()
        files['config/model-whitelists.json'] = whitelist
        files['config/vehicle-categories.json'] = '{ "Staff Cars": ["police"] }'
        local Permissions = start(server, files)
        server:add_player(1)
        for _, ace in ipairs(grants) do
            server:grant_ace(1, ace)
        end
        Permissions.send(1)
        local sent = server.triggered[#server.triggered]
        server:uninstall()

        local client = CfxMock.new({ resource_name = 'vMenu.Enhanced' }):install()
        package.loaded['client.permissions'] = nil
        local ClientPermissions = require('client.permissions')
        ClientPermissions.register_events()
        client:_dispatch('client', sent.name, table.unpack(sent.args, 1, sent.args.n))
        return ClientPermissions, client
    end

    it('answers inside a granted container and nothing outside it', function()
        local P, client = sync({ 'vMenu.Enhanced.Menus.PlayerOptions.All' }, '{}')
        assert.is_true(P.has_received())
        assert.is_true(P.is_allowed('vMenu.Enhanced.Menus.PlayerOptions.Godmode'))
        assert.is_false(P.is_allowed('vMenu.Enhanced.Menus.PlayerOptions'))
        assert.is_false(P.is_allowed('vMenu.Enhanced.NoClip'))
        client:uninstall()
    end)

    it('holds whitelisted and recategorised vehicles back from their class grant', function()
        local P, client = sync({ 'vMenu.Enhanced.Menus.VehicleSpawner.Categories.Super' }, '{ "vehicles": ["adder"] }')
        assert.is_true(P.can_spawn_vehicle('zentorno', 7))
        assert.is_false(P.can_spawn_vehicle('adder', 7))
        assert.is_false(P.can_spawn_vehicle('police', 18))
        assert.are.equal('Staff Cars', P.vehicle_category_of('POLICE'))
        client:uninstall()
    end)
end)
