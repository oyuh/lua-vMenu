-- Port of vMenu/menus/About.cs.

local Config = require('shared.config')
local Items = require('menu.items')
local Menu = require('menu.menu')

local About = {}

function About.create()
    local self = {}
    local menu = Menu.new('vMenu', 'About vMenu')

    local vmenu_version = GetResourceMetadata(GetCurrentResourceName(), 'version', 0)
    local version =
        Items.MenuItem.new('vMenu Version', ('This server is using vMenu ~b~~h~%s~h~~s~.'):format(vmenu_version))
    version.Label = ('~h~%s~h~'):format(vmenu_version)
    local credits = Items.MenuItem.new(
        'About vMenu / Credits',
        'vMenu is made by ~b~Vespura~s~. For more info, checkout ~b~www.vespura.com/vmenu~s~. '
            .. 'Thank you to: Deltanic, Brigliar, IllusiveTea, Shayan Doust, zr0iq and Golden for your contributions!'
    )
    local rewrite = Items.MenuItem.new(
        'Lua Rewrite',
        'This build is a ground-up ~b~Lua rewrite~s~ of vMenu by ~b~Lawson (oyuh)~s~, a drop-in '
            .. 'replacement for the original C# resource. Source: ~b~github.com/oyuh/lua-vMenu~s~.'
    )
    rewrite.Label = '~b~Lua~s~'

    local server_info_message = Config.get_string('vmenu_server_info_message')
    if server_info_message ~= nil and server_info_message ~= '' then
        local server_info = Items.MenuItem.new('Server Info', server_info_message)
        local site_url = Config.get_string('vmenu_server_info_website_url')
        if site_url ~= nil and site_url ~= '' then
            server_info.Label = site_url
        end
        menu:AddMenuItem(server_info)
    end
    menu:AddMenuItem(version)
    menu:AddMenuItem(credits)
    menu:AddMenuItem(rewrite)

    self.menu = menu
    return self
end

return About
