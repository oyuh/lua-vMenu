-- Specs for server/teleport.lua, server/noclip.lua and the coordinates parser.
-- Teleport categories are a file the server owner edits by hand and staff
-- edit from the menu, so a save has to keep it readable and a failed save
-- must not leave the menu showing what the file does not hold.

local CfxMock = require('tests.mocks.cfx')
local dkjson = require('dkjson')

local function reset_modules()
    for name in pairs(package.loaded) do
        if name:match('^shared%.') or name:match('^server%.') or name:match('^client%.') or name:match('^menu%.') then
            package.loaded[name] = nil
        end
    end
end

local FILE = 'config/teleport-categories.json'
local STAFF = 3

describe('teleport categories', function()
    local cfx

    before_each(function()
        cfx = CfxMock.new({ resource_name = 'vMenu.Enhanced', is_server = true }):install()
        cfx:set_resource_file(
            FILE,
            '[{"name":"City","description":"","locations":[{"name":"Airport","description":"",'
                .. '"position":{"x":1.5,"y":2,"z":3}}]}]'
        )
        cfx:add_player(STAFF)
        cfx:grant_ace(STAFF, 'vMenu.Enhanced.Menus.TeleportMenu.All')
        reset_modules()
        require('server.permissions').init()
        require('server.teleport').init()
        require('server.actions').register_events()
    end)

    after_each(function()
        cfx:uninstall()
    end)

    local function invoke(action, ...)
        cfx:trigger_from(STAFF, 'vMenu.Enhanced:Action:Invoke', action, 1, { ... })
        local reply
        for index = #cfx.triggered, 1, -1 do
            if cfx.triggered[index].name == 'vMenu.Enhanced:Action:Result' then
                reply = cfx.triggered[index]
                break
            end
        end
        return reply.args[2]
    end

    it('saves a new location into the file and refuses a duplicate name', function()
        assert.are.equal(0, invoke('TeleportMenu.AddLocation', 'city', 'Beach', 'Sand', '10.5', '-20', '30', '90'))
        local saved = dkjson.decode(cfx.resource_files[FILE])
        assert.are.equal('Beach', saved[1].locations[2].name)
        assert.same({ x = 10.5, y = -20, z = 30 }, saved[1].locations[2].position)
        assert.are.equal(90, saved[1].locations[2].heading)
        -- Hand-editors keep upstream's layout: indented, name first.
        assert.matches('^%[\n  {\n    "name": "City"', cfx.resource_files[FILE])

        assert.are.equal(8, invoke('TeleportMenu.AddLocation', 'City', 'beach', '', '0', '0', '0'))
    end)

    it('puts the list back when the file cannot be written', function()
        cfx:stub_native('SaveResourceFile', function()
            return false
        end)
        assert.are.equal(6, invoke('TeleportMenu.RemoveCategory', 'City'))
        -- Still there: adding its location again is refused as a duplicate, not "not found".
        assert.are.equal(8, invoke('TeleportMenu.AddLocation', 'City', 'Airport', '', '0', '0', '0'))
    end)
end)

describe('noclip reports', function()
    local cfx

    before_each(function()
        cfx = CfxMock.new({ resource_name = 'vMenu.Enhanced', is_server = true }):install()
        reset_modules()
        require('server.permissions').init()
        require('server.noclip').register_events()
        cfx:add_player(4)
    end)

    after_each(function()
        cfx:uninstall()
    end)

    it('only believes players who may noclip', function()
        local NoClip = require('server.noclip')
        cfx:trigger_from(4, 'vMenu.Enhanced:PlayerState:ReportNoClip', true)
        assert.is_false(NoClip.is_active(4))

        cfx:grant_ace(4, 'vMenu.Enhanced.NoClip')
        cfx:trigger_from(4, 'vMenu.Enhanced:PlayerState:ReportNoClip', true)
        assert.is_true(NoClip.is_active(4))
    end)
end)

describe('typed coordinates', function()
    local cfx

    before_each(function()
        cfx = CfxMock.new({ resource_name = 'vMenu.Enhanced' }):install()
        reset_modules()
    end)

    after_each(function()
        cfx:uninstall()
    end)

    it('takes three numbers separated by commas or spaces', function()
        local Targets = require('client.menus.teleport.targets')
        assert.same({ 1, -2.5, 30 }, { Targets.parse_coords('1, -2.5, 30') })
        assert.same({ 1, 2, 3 }, { Targets.parse_coords('1 2 3') })
        assert.is_nil(Targets.parse_coords('1, 2'))
        assert.is_nil(Targets.parse_coords('1, 2, 3, 4'))
        assert.is_nil(Targets.parse_coords('a, b, c'))
    end)
end)
