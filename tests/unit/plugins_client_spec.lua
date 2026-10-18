-- Specs for client/plugins, the client half of upstream's plugin protocol.
-- The other side of the protocol is upstream's own Lua plugin API
-- (tools/test-plugin/vmenu.lua, copied from enhanced-v1.0.16), loaded here as
-- a separate resource, so event names, payload fields and answers are checked
-- against the real thing instead of a restatement of it.

local CfxMock = require('tests.mocks.cfx')

local API = 'tools/test-plugin/vmenu.lua'

local function reset_modules()
    for name in pairs(package.loaded) do
        if name:match('^shared%.') or name:match('^client%.') or name:match('^menu%.') then
            package.loaded[name] = nil
        end
    end
end

-- CfxLua's promise, as much of it as the plugin API uses.
local function new_promise()
    local pending = { callbacks = {} }
    function pending:resolve(value)
        self.done, self.value = true, value
        for _, callback in ipairs(self.callbacks) do
            callback(value)
        end
    end
    function pending:next(callback)
        if self.done then
            callback(self.value)
        else
            self.callbacks[#self.callbacks + 1] = callback
        end
    end
    return pending
end

local function texts(menu)
    local shown = {}
    for _, item in ipairs(menu:GetMenuItems()) do
        shown[#shown + 1] = item.Text
    end
    return shown
end

describe('client plugin host', function()
    local cfx, Controller, Registry, PluginHost

    before_each(function()
        cfx = CfxMock.new({ resource_name = 'vMenu.Enhanced' }):install()
        rawset(_G, 'json', require('dkjson'))
        rawset(_G, 'promise', { new = new_promise })
        reset_modules()
        require('client.permissions').apply({ 'vMenu.Enhanced.Everything' })
        Controller = require('menu.controller')
        Registry = require('client.framework.registry')
        PluginHost = require('client.plugins.host')
        PluginHost.register_events()
        Registry.build({ (require('client.menus.plugins')) })
        PluginHost.announce_ready()
    end)

    after_each(function()
        cfx:uninstall()
        rawset(_G, 'json', nil)
        rawset(_G, 'promise', nil)
        rawset(_G, 'vMenu', nil)
    end)

    -- Loads the plugin API as resource and returns its vMenu table. Every
    -- event from then on comes from that resource.
    local function load_api(resource)
        local current = GetCurrentResourceName
        rawset(_G, 'GetCurrentResourceName', function()
            return resource
        end)
        dofile(API)
        rawset(_G, 'GetCurrentResourceName', current)
        cfx.invoking_resource = resource
        return rawget(_G, 'vMenu')
    end

    local function connect(plugin)
        local answer
        plugin:Connect(function(result)
            answer = result
        end)
        assert.is_table(answer, 'vMenu never answered the registration')
        return answer
    end

    local function plugins_menu()
        return Controller.bound_menu(Registry.main_menu():GetMenuItems()[1])
    end

    it('registers through the plugin API and routes a press back to the plugin', function()
        local vMenu = load_api('vMenu.TestPlugin')
        local plugin = vMenu.CreatePlugin('Test Plugin')
        local pressed = 0
        local button = plugin.RootMenu:AddButton('Press me')
        button:OnSelected(function()
            pressed = pressed + 1
        end)

        local answer = connect(plugin)
        assert.is_true(answer.Accepted)
        assert.same({}, answer.Errors)
        assert.is_true(Registry.main_menu():GetMenuItems()[1].Enabled)
        assert.same({ 'Test Plugin' }, texts(plugins_menu()))

        local menu = Controller.bound_menu(plugins_menu():GetMenuItems()[1])
        assert.same({ 'Press me' }, texts(menu))
        menu:OpenMenu()
        menu:SelectItem(menu:GetMenuItems()[1])
        assert.are.equal(1, pressed)
    end)

    it('applies the updates the plugin API sends once connected', function()
        local vMenu = load_api('vMenu.TestPlugin')
        local plugin = vMenu.CreatePlugin('Test Plugin')
        local first = plugin.RootMenu:AddButton('First')
        local second = plugin.RootMenu:AddButton('Second')
        plugin.Translations:Add('en', { greet = 'Hi {name}, {{literal}}' })
        connect(plugin)
        local menu = Controller.bound_menu(plugins_menu():GetMenuItems()[1])

        first:SetText(vMenu.Text.Key('greet', { name = 'Law' }))
        plugin.RootMenu:AddButton('Third')
        plugin.RootMenu:Remove(second)

        assert.same({ 'Hi Law, {literal}', 'Third' }, texts(menu))
    end)

    it('opens a standalone menu and keeps it from a lower priority plugin', function()
        local high = load_api('vMenu.HighPlugin').CreatePlugin('High')
        local alert = high:AddStandaloneMenu('alert', 'Alert')
        alert:AddButton('Read me')
        connect(high)
        local opened
        alert:RequestOpenWithPriority('high', false, function(result)
            opened = result
        end)
        assert.are.equal('opened', opened)

        local low = load_api('vMenu.LowPlugin').CreatePlugin('Low')
        local popup = low:AddStandaloneMenu('popup', 'Popup')
        popup:AddButton('Ignore me')
        connect(low)
        local blocked
        popup:RequestOpen(function(result)
            blocked = result
        end)
        assert.are.equal('blockedByPriority', blocked)
        assert.are.equal('Alert', Controller.GetCurrentMenu().MenuTitle)
    end)

    it("drops the plugin's row when its resource stops", function()
        local plugin = load_api('vMenu.TestPlugin').CreatePlugin('Test Plugin')
        plugin.RootMenu:AddButton('Press me')
        connect(plugin)
        local menu = plugins_menu()

        TriggerEvent('onResourceStop', 'vMenu.TestPlugin')
        assert.are.equal(0, PluginHost.count())
        assert.same({}, texts(menu))
    end)
end)
