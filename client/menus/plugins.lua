-- Port of vMenu.Enhanced.Plugins/PluginsMenu.cs: one row per plugin with a
-- menu, kept by client/plugins/host.lua. Hidden while no plugin is registered.

local Gate = require('client.framework.gate')
local Registry = require('client.framework.registry')
local PluginHost = require('client.plugins.host')

return Registry.definition({
    audit_name = 'PluginsMenu',
    title_key = 'plugins.title',
    subtitle_key = 'plugins.subtitle',
    description_key = 'plugins.link.desc',
    gate = Gate.when(function()
        return PluginHost.count() > 0
    end),
    link_behaviour = 'hide',
    build = PluginHost.attach_plugins_menu,
})
