-- Port of vMenu.Enhanced.Menus/AboutMenu.cs. Upstream builds one subtitle
-- into each of its two builds; this build asks the platform instead.

local Config = require('shared.config')
local Platform = require('shared.platform')
local Localization = require('shared.localization')
local Entries = require('client.framework.entries')
local Registry = require('client.framework.registry')

-- A manifest value, or a marker when the key is absent.
local function metadata(key)
    return function()
        local resource = GetCurrentResourceName()
        if GetNumResourceMetadata(resource, key) == 0 then
            return 'Unknown'
        end
        local value = (GetResourceMetadata(resource, key, 0) or ''):match('^%s*(.-)%s*$')
        return value ~= '' and value or 'Unknown'
    end
end

-- A flag as words instead of true or false.
local function state(setting)
    return function()
        return Config.value(setting) and 'Enabled' or 'Disabled'
    end
end

local function fact(text, description, value)
    return Entries.button({ text = text, description = description, label = Localization.from(value) })
end

return Registry.definition({
    audit_name = 'AboutMenu',
    title = 'About vMenu',
    subtitle = Localization.from(function()
        return Platform.is_enhanced() and 'vMenu Enhanced (on Enhanced)' or 'vMenu Enhanced (on Legacy)'
    end),
    link_description = 'Version information, links and credits.',
    build = function(menu)
        menu:add(fact('Version', 'The version of vMenu this server is running.', metadata('version')))
        -- Not the manifest's author field, which carries a legal name.
        menu:add(fact('Author', 'Who made vMenu.', function()
            return 'Vespura'
        end))
        menu:add(
            fact(
                'Client Debug Mode',
                "Whether vMenu's diagnostic commands work in your own console.",
                state('vMenu.Enhanced.Debugging.Client')
            )
        )
        menu:add(
            fact(
                'Server Debug Mode',
                "Whether vMenu's diagnostic commands work in the server console.",
                state('vMenu.Enhanced.Debugging.Server')
            )
        )
        menu:add(
            fact(
                'Experimental Features',
                'Whether unfinished features are switched on.',
                state('vMenu.Enhanced.Debugging.ExperimentalFeatures')
            )
        )
        menu:add(Entries.button({
            text = 'Documentation',
            description = Localization.from(function()
                return Config.value('vMenu.Enhanced.DocumentationUrl')
            end),
        }))
        menu:add(Entries.button({
            text = 'Discord',
            description = Localization.from(function()
                return Config.value('vMenu.Enhanced.DiscordUrl')
            end),
        }))
        menu:add(Entries.button({
            text = 'Credits',
            description = 'Thank you to everyone who has contributed to vMenu over the years, and to '
                .. '~b~Ricky~s~ in particular for his help creating vMenu Enhanced. '
                .. 'Lua port by ~b~Lawson~s~ (oyuh).',
        }))
    end,
})
