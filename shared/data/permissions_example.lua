-- Port of vMenu.Enhanced.Data/Permissions/PermissionsExample.cs: renders
-- config/permissions.cfg.example, and one plugin's permissions into its own
-- template, from flattened tree entries:
--   { name = ..., depth = n, source = 'config/x.json' | nil, staff_only = bool, extra_parents = { ... } }

local ExampleFile = require('shared.data.example_file')

local PermissionsExample = {}

PermissionsExample.COPY_NAME = 'permissions.cfg'
PermissionsExample.RESOURCE_PATH = ('%s/%s%s'):format(
    ExampleFile.CONFIG_DIRECTORY,
    PermissionsExample.COPY_NAME,
    ExampleFile.EXTENSION
)

local EVERYONE_GROUP = 'builtin.everyone'
local STAFF_GROUP = 'group.admin'
local PLUGINS_ALL = 'vMenu.Enhanced.Plugins.All'

-- Entries at or above this depth get a blank line before them.
local SPACED_DEPTH = 1

function PermissionsExample.plugin_resource_path(resource)
    return ('%s/%s%s'):format(
        ExampleFile.PLUGINS_DIRECTORY,
        ExampleFile.plugin_copy_name(resource, PermissionsExample.COPY_NAME),
        ExampleFile.EXTENSION
    )
end

-- A container grants everything under it, so a staff-only child makes its
-- container staff-only too, else the container would hand that child out to
-- everybody. Walked backwards so each entry's children are already resolved.
local function resolve_staff_only(entries)
    local staff_only = {}
    for index = #entries, 1, -1 do
        staff_only[index] = entries[index].staff_only
        local below = index + 1
        while below <= #entries and entries[below].depth > entries[index].depth do
            if entries[below].depth == entries[index].depth + 1 and staff_only[below] then
                staff_only[index] = true
                break
            end
            below = below + 1
        end
    end
    return staff_only
end

local function annotation(entry)
    local notes = {}
    if entry.source then
        notes[#notes + 1] = 'from ' .. entry.source
    end
    if entry.extra_parents and #entry.extra_parents > 0 then
        notes[#notes + 1] = 'also granted by ' .. table.concat(entry.extra_parents, ', ')
    end
    return table.concat(notes, ', ')
end

local function append_entries(parts, entries, spaced_depth, annotate)
    local staff_only = resolve_staff_only(entries)
    for index, entry in ipairs(entries) do
        local indent = (' '):rep(entry.depth * 2)
        if entry.depth <= spaced_depth then
            parts[#parts + 1] = '\n'
        end
        -- Above the command, not trailing it: the console does not treat a
        -- mid-line # as a comment.
        local note = annotate and annotation(entry) or ''
        if note ~= '' then
            parts[#parts + 1] = indent .. '# ' .. note .. '\n'
        end
        local principal = staff_only[index] and STAFF_GROUP or EVERYONE_GROUP
        parts[#parts + 1] = indent .. 'add_ace ' .. principal .. ' "' .. entry.name .. '" allow\n'
    end
end

local LIVE_NOTE = 'Permissions are checked live. HOWEVER, the permissions.cfg '
    .. 'does not re-execute itself. You can either '
    .. 'execute it manually again, but I do not recommend this if you made big changes, because conflicting aces '
    .. 'and principals will cause issues. Instead, if all you did was add somebody to a group, simply execute that '
    .. 'one command in the server console manually. Then execute `vmenu_refresh_permissions` in the server console '
    .. 'and every person should have their menu permissions refreshed automatically. '
    .. 'For big permissions.cfg changes I still recommend to restart your server!'

function PermissionsExample.render(entries, ready)
    local copy = PermissionsExample.COPY_NAME
    local comment = ExampleFile.comment
    local parts = {
        ready and ExampleFile.ready_banner(copy, { LIVE_NOTE }) or ExampleFile.banner(copy, { LIVE_NOTE }),
        '\n',
        comment(
            "vMenu needs these two lines so an integration's role sync can add and remove permission groups "
                .. 'for players. They do nothing if you do not use role sync.'
        ),
        'add_ace resource.vMenu.Enhanced command.add_principal allow\n',
        'add_ace resource.vMenu.Enhanced command.remove_principal allow\n',
        '\n',
        comment(
            'Give a player a group by one of their identifiers. '
                .. 'Use whichever you can look up most easily. Note, Steam '
                .. 'identifiers no longer work in FiveM Enhanced, so use either '
                .. 'license, license2, discord or fivem identifiers. (You can also use '
                .. "the IP identifier, but I don't really recommended that one). "
                .. '!!! Make sure you replace these with your own identifiers and remove the # !!! '
                .. "If you're using another system to add people to principal groups during runtime "
                .. '(for example TxAdmin for your admins), then you do not need to manually add them here.'
        ),
        '# add_principal identifier.discord:223799456162775043 ' .. STAFF_GROUP .. '\n',
        '# add_principal identifier.fivem:25104 ' .. STAFF_GROUP .. '\n',
        '\n',
        comment(
            'Groups inherit from each other (if you set it up correctly). This one gives everybody in '
                .. STAFF_GROUP
                .. ' everything group.mod may do, on top of whatever '
                .. STAFF_GROUP
                .. ' is granted below.'
        ),
        'add_principal ' .. STAFF_GROUP .. ' group.mod\n',
        '\n',
        comment(
            'Every permission vMenu Enhanced knows about is listed below, ready to run as it is. '
                .. 'Each line already suggests who gets it: '
                .. EVERYONE_GROUP
                .. ' for the permissions that are fine for any player, and '
                .. STAFF_GROUP
                .. ' for the few that should stay with your staff. Change that principal if somebody else should '
                .. 'have them.'
        ),
        '#\n',
        comment(
            'A line that has other lines indented under it hands out every one of them, so it is suggested to '
                .. STAFF_GROUP
                .. ' as soon as anything below it is. That is why a .All can say '
                .. STAFF_GROUP
                .. ' while most of what sits under it says '
                .. EVERYONE_GROUP
                .. '. Those lines are still there on their own, so your players keep them.'
        ),
        '#\n',
        comment(
            'A permission ending in .All grants everything nested underneath it, so keeping only the '
                .. '.All line is usually all you need. When you want to restrict some features, delete '
                .. 'the .All and keep only the specific lines below it instead, or put a # in front of '
                .. 'the ones you do not want. '
                .. 'Checkout https://docs.vespura.com/vMenu/Enhanced/ for more permissions information.'
        ),
        '#\n',
        comment(
            'Permissions that a plugin brings along are not listed here. Every plugin gets its own '
                .. 'pair of templates in '
                .. ExampleFile.PLUGINS_DIRECTORY
                .. '/, named after the resource they came from. The '
                .. PLUGINS_ALL
                .. ' line below still grants all of them at once, '
                .. "so you only need those files to hand out a plugin's permissions one by one."
        ),
        '\n',
        comment(
            "Note: While some of the permissions below are indented, that's only to show you to "
                .. 'which parent they belong. You do not need to have them indented inside the '
                .. 'permissions.cfg like this to function correctly while executing the file. '
                .. "It doesn't make a difference when executing the permissions.cfg from your server.cfg."
        ),
    }

    append_entries(parts, entries, SPACED_DEPTH, true)
    return table.concat(parts)
end

function PermissionsExample.render_for_plugin(resource, display_name, entries)
    local parts = {
        ExampleFile.banner_in(
            ExampleFile.PLUGINS_DIRECTORY,
            ExampleFile.plugin_copy_name(resource, PermissionsExample.COPY_NAME),
            {
                "These permissions belong to the plugin '"
                    .. display_name
                    .. "', which the resource '"
                    .. resource
                    .. "' provides. They are listed here and not in vMenu's own permissions.cfg, "
                    .. 'so removing the plugin means removing the files named after it rather than hunting '
                    .. 'through that one.',
                'Nothing here is written while the plugin is not running, so start it before you read '
                    .. 'this. If you have removed the plugin for good, delete every file in this folder whose '
                    .. "name starts with '"
                    .. resource
                    .. ".'.",
                "The same rules as vMenu's own permissions apply: "
                    .. EVERYONE_GROUP
                    .. ' is suggested for what any player may have and '
                    .. STAFF_GROUP
                    .. ' for what your staff should keep, a line ending in .All hands out everything indented '
                    .. 'under it, and the indentation is only there to show you what belongs to what.',
            }
        ),
    }

    if #entries == 0 then
        parts[#parts + 1] = '\n'
        parts[#parts + 1] =
            ExampleFile.comment('This plugin declares no permissions, so there is nothing to hand out here.')
        return table.concat(parts)
    end

    -- Only the plugin's own container is spaced; everything else sits under it.
    append_entries(parts, entries, 0, false)
    return table.concat(parts)
end

return PermissionsExample
