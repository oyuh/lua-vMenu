-- Server half of the test plugin: the permissions, settings and logged rows
-- it declares, and one server event that checks a permission.

local declaration = vMenu.ServerPluginDeclaration('vMenu Test Plugin')
declaration:AddPermission('Basic', 'Use the test plugin.')
declaration:AddPermission('Staff', 'Use the staff-only test rows.', true)
declaration:AddBoolSetting('ShowSecret', false, 'Unlocks the rows gated by this setting.')
declaration:AddIntSetting('MaxRows', 10, 'How many rows "Add a row" may add.')
declaration:AddStringSetting('Greeting', 'Hello', 'What the greeting row says.')
declaration:AddLoggedItem('danger', 'the dangerous test button')

vMenu.Server.Register(declaration, function(result)
    print(('[vMenu.TestPlugin] Server registration accepted: %s'):format(tostring(result.Accepted)))
    for _, problem in ipairs(result.Errors) do
        print('[vMenu.TestPlugin]   error: ' .. problem)
    end
    for _, warning in ipairs(result.Warnings) do
        print('[vMenu.TestPlugin]   warning: ' .. warning)
    end
end)

RegisterNetEvent('vMenu.TestPlugin:CheckStaff', function()
    local player = source
    TriggerClientEvent('vMenu.TestPlugin:StaffChecked', player, vMenu.Server.RequirePermission(player, 'Staff'))
end)
