-- Port of vMenu.Enhanced.Menus/PlayerMenu.cs. Its gate already names every
-- submenu upstream links here; the links themselves join as they are ported.

local Gate = require('client.framework.gate')
local Entries = require('client.framework.entries')
local Registry = require('client.framework.registry')

return Registry.definition({
    audit_name = 'PlayerMenu',
    title_key = 'playermenu.title',
    subtitle_key = 'playermenu.subtitle',
    description_key = 'playermenu.link.desc',
    gate = Gate.any(
        'vMenu.Enhanced.Menus.PlayerOptions.Menu',
        'vMenu.Enhanced.Menus.PedModels.Menu',
        'vMenu.Enhanced.Menus.PlayerAppearance.Menu',
        'vMenu.Enhanced.Menus.CharacterCreator.Menu',
        'vMenu.Enhanced.Menus.SavedPeds.Menu',
        'vMenu.Enhanced.Menus.WeaponOptions.Menu',
        'vMenu.Enhanced.Menus.WeaponLoadouts.Menu',
        'vMenu.Enhanced.Menus.WeaponOptions.GameLoadouts',
        'vMenu.Enhanced.Menus.AutoPilot.Menu'
    ),
    build = function(menu)
        menu:add(Entries.submenu_for(require('client.menus.player_options')))
        menu:add(Entries.submenu_for(require('client.menus.weapon_options')))
        menu:add(Entries.submenu_for(require('client.menus.weapon_loadouts')))
        menu:add(Entries.submenu_for(require('client.menus.game_loadouts')))
    end,
})
