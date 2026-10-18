-- Specs for the vehicle actions in server/vehicles.lua. Deleting goes through
-- the server, which has to check the player really drives the vehicle: the
-- client sends only a network id, which a modified client can pick freely.

local CfxMock = require('tests.mocks.cfx')

local function reset_modules()
    for name in pairs(package.loaded) do
        if name:match('^shared%.') or name:match('^server%.') then
            package.loaded[name] = nil
        end
    end
end

local PLAYER = 5
local PED = 60
local VEHICLE = 50

describe('vehicle delete action', function()
    local cfx

    before_each(function()
        cfx = CfxMock.new({ resource_name = 'vMenu.Enhanced', is_server = true }):install()
        reset_modules()
        cfx:add_player(PLAYER)
        cfx:grant_ace(PLAYER, 'vMenu.Enhanced.Menus.VehicleOptions.DeleteVehicle')
        cfx.entity_coords[VEHICLE] = { x = 0.0, y = 0.0, z = 0.0 }
        cfx.entity_coords[PED] = { x = 0.0, y = 0.0, z = 0.0 }
        cfx:stub_native('NetworkGetEntityFromNetworkId', function(network_id)
            return network_id == 7 and VEHICLE or 0
        end)
        cfx:stub_native('GetEntityType', function()
            return 2
        end)
        cfx:stub_native('GetPlayerPed', function()
            return PED
        end)
        cfx:stub_native('GetVehiclePedIsIn', function()
            return VEHICLE
        end)
        require('server.permissions').init()
        require('server.vehicles').register_events()
        require('server.actions').register_events()
    end)

    after_each(function()
        cfx:uninstall()
    end)

    local function delete(network_id)
        cfx:trigger_from(PLAYER, 'vMenu.Enhanced:Action:Invoke', 'VehicleOptions.DeleteVehicle', 1, { network_id })
        return cfx.triggered[#cfx.triggered].args[2]
    end

    it('refuses a passenger and deletes for the driver', function()
        cfx:stub_native('GetPedInVehicleSeat', function()
            return 61
        end)
        assert.are.equal(8, delete('7'))
        assert.are.equal(0, #cfx:calls('DeleteEntity'))

        cfx:stub_native('GetPedInVehicleSeat', function()
            return PED
        end)
        assert.are.equal(0, delete('7'))
        assert.same({ VEHICLE, n = 1 }, cfx:calls('DeleteEntity')[1])
    end)

    it('answers not found for a vehicle the server does not know', function()
        assert.are.equal(4, delete('99'))
    end)
end)
