-- Port of vMenu.Enhanced.Data/Configuration/ConfigurationExample.cs: renders
-- config/configuration.cfg.example from the settings catalog, and one plugin's
-- settings into its own template under config/plugins/.

local Config = require('shared.config')
local Catalog = require('shared.data.settings')
local ExampleFile = require('shared.data.example_file')

local ConfigurationExample = {}

ConfigurationExample.COPY_NAME = 'configuration.cfg'
ConfigurationExample.RESOURCE_PATH = ('%s/%s%s'):format(
    ExampleFile.CONFIG_DIRECTORY,
    ConfigurationExample.COPY_NAME,
    ExampleFile.EXTENSION
)

function ConfigurationExample.plugin_resource_path(resource)
    return ('%s/%s%s'):format(
        ExampleFile.PLUGINS_DIRECTORY,
        ExampleFile.plugin_copy_name(resource, ConfigurationExample.COPY_NAME),
        ExampleFile.EXTENSION
    )
end

local function describe(setting)
    return ('Default value: "%s" (%s)'):format(Config.default_value(setting), setting.type)
end

local function append_setting(parts, setting, keyword)
    parts[#parts + 1] = '\n'
    parts[#parts + 1] = ExampleFile.comment(setting.description)
    parts[#parts + 1] = ExampleFile.comment(describe(setting))
    parts[#parts + 1] = keyword .. ' ' .. setting.name .. ' ' .. Config.default_text(setting) .. '\n'
end

local NOTES = {
    "Most options below use 'setr' so they are replicated to clients. "
        .. "A few use plain 'set' instead, which keeps the value on the server where no player can "
        .. 'read it. Those are the ones holding something secret, such as a webhook URL, and you '
        .. "must not change their 'set' into a 'setr'.",
    "Deleting an option, or commenting it out, restores vMenu's own default for it. "
        .. 'Although I do recommend that you manually set it to the default yourself instead of '
        .. "commenting it out, because if the default ever changes with an update, you won't be "
        .. "surprised when it's suddenly changed in-game!",
}

function ConfigurationExample.render(ready)
    local copy = ConfigurationExample.COPY_NAME
    local parts = { ready and ExampleFile.ready_banner(copy, NOTES) or ExampleFile.banner(copy, NOTES) }

    for _, section in ipairs(Catalog) do
        parts[#parts + 1] = '\n### ' .. section.title .. ' ###\n'
        for _, setting in ipairs(section.settings) do
            append_setting(parts, setting, setting.server_only and 'set' or 'setr')
        end
    end

    return table.concat(parts)
end

-- settings are full setting records (name, type, default, description).
function ConfigurationExample.render_for_plugin(resource, display_name, settings)
    local parts = {
        ExampleFile.banner_in(
            ExampleFile.PLUGINS_DIRECTORY,
            ExampleFile.plugin_copy_name(resource, ConfigurationExample.COPY_NAME),
            {
                "These options belong to the plugin '"
                    .. display_name
                    .. "', which the resource '"
                    .. resource
                    .. "' provides. They are listed here and not in vMenu's own configuration.cfg, so removing "
                    .. 'the plugin means removing the files named after it rather than hunting through that one.',
                'Nothing here is written while the plugin is not running, so start it before you read '
                    .. 'this. If you have removed the plugin for good, delete every file in this folder whose '
                    .. "name starts with '"
                    .. resource
                    .. ".'.",
                "Every option uses 'setr' so it is replicated to clients. Deleting an option, or "
                    .. "commenting it out, restores the plugin's own default for it.",
            }
        ),
    }

    if #settings == 0 then
        parts[#parts + 1] = '\n'
        parts[#parts + 1] = ExampleFile.comment('This plugin declares no options, so there is nothing to set here.')
        return table.concat(parts)
    end

    for _, setting in ipairs(settings) do
        append_setting(parts, setting, 'setr')
    end

    return table.concat(parts)
end

return ConfigurationExample
