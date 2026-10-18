-- Port of vMenu.Enhanced.Menus/IntoxicationMenu.cs.

local Localization = require('shared.localization')
local Entries = require('client.framework.entries')
local Registry = require('client.framework.registry')
local Intoxication = require('client.menus.players.intoxication')

local STRENGTHS = {}
for level = 1, Intoxication.STRENGTH_LEVELS do
    STRENGTHS[level] = ('%d%%'):format(level * 100 // Intoxication.STRENGTH_LEVELS)
end

return Registry.definition({
    audit_name = 'IntoxicationMenu',
    title_key = 'playeroptions.intoxication',
    subtitle_key = 'playeroptions.intoxication.subtitle',
    description_key = 'playeroptions.intoxication.desc',
    permission = 'vMenu.Enhanced.Menus.PlayerOptions.Intoxication',
    build = function(menu)
        menu:add(Entries.checkbox({
            text = Localization.key('playeroptions.intoxication.enabled'),
            description = Localization.key('playeroptions.intoxication.enabled.desc'),
            read_state = Intoxication.enabled,
            on_changed = function(args)
                Intoxication.set_enabled(args.checked)
                menu:refresh()
            end,
        }))
        menu:add(Entries.list({
            text = Localization.key('playeroptions.intoxication.type'),
            description = Localization.key('playeroptions.intoxication.type.desc'),
            options = {
                Localization.key('playeroptions.intoxication.drunk'),
                Localization.key('playeroptions.intoxication.drugged'),
            },
            read_selected_index = function()
                return Intoxication.drugged() and 1 or 0
            end,
            read_enabled = Intoxication.enabled,
            on_index_changed = function(args)
                Intoxication.set_drugged(args.new_index == 1)
            end,
        }))
        menu:add(Entries.checkbox({
            text = Localization.key('playeroptions.intoxication.screen'),
            description = Localization.key('playeroptions.intoxication.screen.desc'),
            read_state = Intoxication.screen_effects,
            read_enabled = Intoxication.enabled,
            on_changed = function(args)
                Intoxication.set_screen_effects(args.checked)
                menu:refresh()
            end,
        }))
        menu:add(Entries.list({
            text = Localization.key('playeroptions.intoxication.strength'),
            description = Localization.key('playeroptions.intoxication.strength.desc'),
            options = STRENGTHS,
            read_selected_index = function()
                return Intoxication.strength() - 1
            end,
            read_enabled = function()
                return Intoxication.enabled() and Intoxication.screen_effects()
            end,
            on_index_changed = function(args)
                Intoxication.set_strength(args.new_index + 1)
            end,
        }))
        menu:add(Entries.checkbox({
            text = Localization.key('playeroptions.intoxication.walk'),
            description = Localization.key('playeroptions.intoxication.walk.desc'),
            read_state = Intoxication.walking_style,
            read_enabled = Intoxication.enabled,
            on_changed = function(args)
                Intoxication.set_walking_style(args.checked)
            end,
        }))
        menu:add(Entries.checkbox({
            text = Localization.key('playeroptions.intoxication.nosprint'),
            description = Localization.key('playeroptions.intoxication.nosprint.desc'),
            read_state = Intoxication.prevent_sprint,
            read_enabled = Intoxication.enabled,
            on_changed = function(args)
                Intoxication.set_prevent_sprint(args.checked)
            end,
        }))
        menu:add(Entries.checkbox({
            text = Localization.key('playeroptions.intoxication.driving'),
            description = Localization.key('playeroptions.intoxication.driving.desc'),
            read_state = Intoxication.driving,
            read_enabled = Intoxication.enabled,
            on_changed = function(args)
                Intoxication.set_driving(args.checked)
            end,
        }))
    end,
})
