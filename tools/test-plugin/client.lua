-- Client half of the test plugin. Every submenu covers one area of the plugin
-- API, so a broken feature shows up as a broken row.

local RESOURCE = GetCurrentResourceName()
local plugin = vMenu.CreatePlugin(vMenu.Text.Key('plugin.name'))
local Text, Gate = vMenu.Text, vMenu.Gate

local function say(style, message)
    plugin:Notify(style, message)
end

local function log(message)
    print('[vMenu.TestPlugin] ' .. message)
end

plugin.Translations:Add('en', {
    ['plugin.name'] = 'vMenu Test Plugin',
    ['plugin.description'] = 'Exercises every plugin feature.',
    ['greeting'] = '{greeting}, {name}! Braces stay: {{like this}}.',
})
plugin.Translations:Add('nl', {
    ['plugin.name'] = 'vMenu Testplugin',
    ['greeting'] = '{greeting}, {name}! Accolades blijven: {{zo}}.',
})
plugin:SetDescriptionKey('plugin.description')

local showSecret = plugin.Settings:Bool('ShowSecret', false, 'Unlocks the rows gated by this setting.')
local maxRows = plugin.Settings:Int('MaxRows', 10, 'How many rows "Add a row" may add.')
local greeting = plugin.Settings:String('Greeting', 'Hello', 'What the greeting row says.')

local root = plugin.RootMenu

-- Every row type ---------------------------------------------------------------------

local items = root:AddSubmenu('Every row type', { Subtitle = 'One of each' }).Menu

local presses = 0
local button = items:AddButton('Button', { Description = 'Counts presses in its label.', Label = '0' })
button:OnSelected(function()
    presses = presses + 1
    button:SetLabel(tostring(presses))
end)

items
    :AddConfirmButton('Confirm button', {
        Id = 'danger',
        Description = 'Asks once, acts on the second press. Logged to the webhook.',
        ConfirmationDescription = '~r~Press again to really do the dangerous thing.',
        Log = true,
        LeftIcon = 'WARNING',
    })
    :OnConfirmed(function()
        say('warning', 'You did the dangerous thing.')
    end)

items:AddCheckbox('Checkbox (remembered)', { Id = 'remembered', Persist = true }):OnChanged(function(checked)
    say('info', 'Checkbox is now ' .. (checked and 'on' or 'off') .. '. It survives a restart.')
end)

local colors = { 'Red', 'Green', 'Blue' }
local list = items:AddList('List', colors, { Description = 'Scroll it, then press it.' })
list:OnIndexChanged(function(_, new)
    list:SetDescription('You are on ' .. colors[new] .. '.')
end)
list:OnSelected(function(index)
    say('success', 'You picked ' .. colors[index] .. '.')
end)

items:AddConfirmList('Confirm list', { 'Small', 'Medium', 'Large' }):OnConfirmed(function(index)
    say('success', 'Confirmed option ' .. index .. '.')
end)

local slider = items:AddSlider('Slider', 0, 10, 5, { ShowDivider = true })
slider:OnMoved(function(_, new)
    slider:SetDescription('Position ' .. new .. '.')
end)
slider:OnSelected(function(position)
    say('info', 'Slider pressed at ' .. position .. '.')
end)

local number = items:AddDynamicList('Dynamic list', '0', { Description = 'Left and right count down and up.' })
number:SetChangeRequested(function(current, left)
    return tostring((tonumber(current) or 0) + (left and -1 or 1))
end)
number:OnSelected(function(value)
    say('info', 'Dynamic list pressed at ' .. value .. '.')
end)

items:AddSeparator('Separator')
items:AddButton('Icons', { LeftIcon = 'STAR', RightIcon = 'CROWN' })
items:AddButton('Disabled row', { Enabled = false, Description = 'Greyed out, but not locked.' })
items:AddButton(Text.Key('greeting', { greeting = greeting:GetValue(), name = GetPlayerName(PlayerId()) }), {
    Description = 'A translated row with placeholders.',
})

-- Live updates -----------------------------------------------------------------------

local live = root:AddSubmenu('Live updates', { Subtitle = 'Changes made while it is open' }).Menu
local added = {}

live:OnOpened(function()
    log('Live updates opened.')
end)
live:OnClosed(function()
    log('Live updates closed.')
end)

live:AddButton('Add a row', { Description = 'Adds a row at the bottom, up to the MaxRows setting.' })
    :OnSelected(function()
        if #added >= maxRows:GetValue() then
            say('warning', ('MaxRows is %d, so no more rows.'):format(maxRows:GetValue()))
            return
        end
        added[#added + 1] = live:AddButton('Added row ' .. (#added + 1))
    end)

live:AddButton('Remove the last added row'):OnSelected(function()
    local last = table.remove(added)
    if last then
        live:Remove(last)
    end
end)

live:AddButton('Rename the added rows in one batch'):OnSelected(function()
    plugin:Batch(function()
        for index, row in ipairs(added) do
            row:SetText(('Renamed row %d'):format(index))
        end
    end)
end)

live:AddButton('Move the last added row to the top'):OnSelected(function()
    if #added > 0 then
        live:Move(added[#added], 1)
    end
end)

live:AddButton('Select the last added row'):OnSelected(function()
    if #added > 0 then
        live:Select(added[#added])
    end
end)

local filtered = false
live:AddButton('Toggle a filter on the added rows'):OnSelected(function()
    filtered = not filtered
    if not filtered then
        live:ClearFilter()
        return
    end
    live:Filter(function(row)
        for index, candidate in ipairs(added) do
            if candidate == row then
                return index % 2 == 1
            end
        end
        return true
    end)
end)

local hidden = live:AddButton('Hidden row', { Visible = false })
live:AddCheckbox('Show the hidden row'):OnChanged(function(checked)
    hidden:SetVisible(checked)
end)

local toggled = live:AddButton('Row that can be disabled')
live:AddCheckbox('Disable that row'):OnChanged(function(checked)
    toggled:SetEnabled(not checked)
end)

live:AddButton('Rename this menu', { Description = 'Asks for a title through the input box.' }):OnSelected(function()
    plugin:GetText('New title', { MaxLength = 30, InitialValue = 'Live updates' }, function(title)
        if title then
            live:SetTitle(title)
        end
    end)
end)

live:AddKey('ping', 'Ping', 'G', { Description = 'Says which row the cursor is on.' }):OnPressed(function(pressed)
    local row = pressed.Item or pressed.DisabledItem
    local state = pressed.Item and 'usable' or 'locked or disabled'
    say('info', row and ('Cursor on %s (%s).'):format(tostring(row:GetText()), state) or 'Cursor on nothing.')
end)

-- Gates ------------------------------------------------------------------------------

local gates = root:AddSubmenu('Gates', { Subtitle = 'Permissions and settings' }).Menu
gates:AddButton('Needs Basic', { Gate = Gate.Permission('Basic') })
gates:AddButton('Needs Staff', { Gate = Gate.Permission('Staff') })
gates:AddButton('Locked by ShowSecret', {
    Gate = Gate.Setting(showSecret),
    LockedDescription = 'Run "setr vMenu.Enhanced.Plugins.vMenu_TestPlugin.ShowSecret true" to unlock.',
})
gates:AddButton('Hidden by ShowSecret', { Gate = Gate.Setting(showSecret), HideWhenLocked = true })
gates:AddButton('Needs Basic and ShowSecret', { Gate = Gate.Permission('Basic') & Gate.Setting(showSecret) })
gates:AddButton('Needs Staff or ShowSecret', { Gate = Gate.Permission('Staff') | Gate.Setting(showSecret) })
gates:AddButton('Ask the server about Staff'):OnSelected(function()
    TriggerServerEvent('vMenu.TestPlugin:CheckStaff')
end)
RegisterNetEvent('vMenu.TestPlugin:StaffChecked', function(allowed)
    say(allowed and 'success' or 'error', 'The server says Staff is ' .. (allowed and 'allowed.' or 'denied.'))
end)

-- Prompts and notifications ----------------------------------------------------------

local talk = root:AddSubmenu('Prompts and notifications').Menu
for _, style in ipairs({ 'info', 'success', 'warning', 'error' }) do
    talk:AddButton('Notify: ' .. style):OnSelected(function()
        say(style, 'This is a ' .. style .. ' notification.')
    end)
end
talk:AddButton('Ask two questions'):OnSelected(function()
    plugin:GetTexts({
        { Title = 'Your name', InitialValue = GetPlayerName(PlayerId()) },
        {
            Title = 'Favorite color',
            MaxLength = 20,
            Suggestions = { { Value = 'Blue', Description = 'The best one' }, { Value = 'Green' } },
        },
    }, function(answers)
        if answers then
            say('success', ('%s likes %s.'):format(answers[1], answers[2]))
        else
            say('warning', 'You canceled.')
        end
    end)
end)

-- Themes -----------------------------------------------------------------------------

local themes = root:AddSubmenu('Themes').Menu
local themeList = themes:AddList('Theme', { 'Waiting for vMenu' })
local themeIds = {}
plugin.Themes:OnChanged(function()
    local names, current = {}, 1
    themeIds = {}
    for index, theme in ipairs(plugin.Themes:GetAvailable()) do
        names[index] = theme.Name
        themeIds[index] = theme.Id
        if theme.IsCurrent then
            current = index
        end
    end
    if #names > 0 then
        themeList:SetOptions(names, current)
    end
end)
themeList:OnSelected(function(index)
    if themeIds[index] then
        plugin.Themes:Set(themeIds[index])
    end
end)
themes:AddButton('Back to the server theme'):OnSelected(function()
    plugin.Themes:Reset()
end)

-- The plugin API has no call for this, so it uses the protocol event directly.
AddEventHandler(('vMenu.Enhanced:Plugins:%s:ThemesRegistered'):format(RESOURCE), function(answer)
    log('Theme registration answered: ' .. answer)
end)
local function registerThemes()
    TriggerEvent(
        'vMenu.Enhanced:Plugins:RegisterThemes',
        json.encode({
            themes = { { id = 'testplugin-purple', name = 'Test Plugin Purple', css = 'themes/purple.css' } },
        })
    )
end

-- Standalone menus -------------------------------------------------------------------

local popup = plugin:AddStandaloneMenu('popup', 'Popup', 'A standalone menu at no priority')
popup:AddButton('Close'):OnSelected(function()
    popup:Close()
end)
popup:OnReplaced(function()
    say('info', 'Another menu replaced the popup.')
end)

local locked = plugin:AddStandaloneMenu('locked', 'Locked', 'Hold back to force it shut')
locked:AddButton('Close me properly'):OnSelected(function()
    locked:Close()
end)
locked:OnForceClosed(function()
    say('warning', 'You forced the locked menu shut.')
end)

local function reportOpen(name)
    return function(result)
        say(result == vMenu.OpenMenuResult.Opened and 'success' or 'warning', ('%s: %s'):format(name, result))
    end
end

local standalone = root:AddSubmenu('Standalone menus').Menu
standalone:AddButton('Open the popup'):OnSelected(function()
    popup:RequestOpen(reportOpen('Popup'))
end)
standalone:AddButton('Open the locked menu (high, do not close)'):OnSelected(function()
    locked:RequestOpenWithPriority(vMenu.MenuPriority.High, true, reportOpen('Locked'))
end)

-- From outside any menu. With a vMenu menu open it answers blockedByPriority.
RegisterCommand('testplugin_popup', function()
    popup:RequestOpen(reportOpen('Popup'))
end, false)

-- Player actions ---------------------------------------------------------------------

-- Shown under Online Players once that menu is ported.
plugin.PlayerActions:AddButton('Wave'):OnSelected(function(target)
    say('info', ('You waved at %s (%d).'):format(target.Name, target.ServerId))
end)
plugin.PlayerActions:AddConfirmButton('Pretend to kick'):OnConfirmed(function(target)
    say('warning', ('You pretended to kick %s.'):format(target.Name))
end)
plugin.PlayerActions:AddList('Send a greeting', { 'Hi', 'Hello', 'Hey' }):OnSelected(function(target, index)
    say('info', ('You sent greeting %d to %s.'):format(index, target.Name))
end)

-- Connecting -------------------------------------------------------------------------

plugin:OnRegistrationAnswered(function(result)
    log(('Registration accepted: %s'):format(tostring(result.Accepted)))
    for _, problem in ipairs(result.Errors) do
        log('  error: ' .. problem)
    end
    for _, warning in ipairs(result.Warnings) do
        log('  warning: ' .. warning)
    end
    if result.Accepted then
        registerThemes()
    end
end)

plugin:Connect(function() end)
