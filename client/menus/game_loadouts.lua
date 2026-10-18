-- Port of vMenu.Enhanced.Menus/GameLoadoutsMenu.cs.

local Localization = require('shared.localization')
local Entries = require('client.framework.entries')
local Registry = require('client.framework.registry')
local Notifications = require('client.framework.notifications')
local GameLoadouts = require('client.menus.weapons.game_loadouts')

local function equip(name)
    local given, removed = GameLoadouts.apply(name)
    if removed > 0 then
        Notifications.warning(Localization.key('weaponoptions.gameloadout.removed', { count = tostring(removed) }))
    end
    if given == 0 then
        Notifications.error(Localization.key('weaponoptions.gameloadout.empty'))
        return
    end
    Notifications.success(Localization.key('weaponoptions.gameloadout.done', { count = tostring(given) }))
end

return Registry.definition({
    audit_name = 'GameLoadoutsMenu',
    title_key = 'weaponoptions.gameloadout',
    subtitle_key = 'weaponoptions.gameloadout.subtitle',
    description_key = 'weaponoptions.gameloadout.desc',
    permission = 'vMenu.Enhanced.Menus.WeaponOptions.GameLoadouts',
    build = function(menu)
        for _, group in ipairs(GameLoadouts.GROUPS) do
            menu:add(Entries.separator({ text = group.heading }))
            for _, loadout in ipairs(group.loadouts) do
                local name = loadout[1]
                menu:add(Entries.button({
                    text = loadout[2],
                    description = name,
                    on_selected = function()
                        equip(name)
                    end,
                }))
            end
        end
    end,
})
