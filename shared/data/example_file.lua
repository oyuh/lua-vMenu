-- Port of vMenu.Enhanced.Data/ExampleFile.cs: the banners and comment wrapping
-- shared by every generated *.cfg.example. Output must stay byte-identical to
-- upstream's, so server owners can diff the two builds' files.

local ExampleFile = {}

ExampleFile.EXTENSION = '.example'
ExampleFile.CONFIG_DIRECTORY = 'config'
-- One shipped folder for every plugin's templates: SaveResourceFile writes
-- files, never folders, so a folder per plugin could never be created.
ExampleFile.PLUGINS_DIRECTORY = ExampleFile.CONFIG_DIRECTORY .. '/plugins'

local RULE = '###############################################################################'

function ExampleFile.plugin_copy_name(resource, copy_name)
    return resource .. '.' .. copy_name
end

-- Character count, not bytes, matching C#'s string.Length for non-ASCII text.
local function length(text)
    return utf8.len(text) or #text
end

-- Wraps prose into # comment lines no wider than width, splitting on spaces.
function ExampleFile.comment(text, prefix, width)
    prefix = prefix or '#'
    width = width or 78
    local out = {}
    local line = prefix
    for word in text:gmatch('[^ ]+') do
        if length(line) + 1 + length(word) > width and length(line) > length(prefix) then
            out[#out + 1] = line
            line = prefix
        end
        line = line .. ' ' .. word
    end
    out[#out + 1] = line
    return table.concat(out, '\n') .. '\n'
end

local function append_notes(parts, notes)
    for _, note in ipairs(notes or {}) do
        parts[#parts + 1] = '#\n'
        parts[#parts + 1] = ExampleFile.comment(note, '# ')
    end
end

-- The banner for a file that sits in directory.
function ExampleFile.banner_in(directory, copy_name, notes)
    local parts = {
        RULE .. '\n',
        '#  THIS FILE IS REGENERATED EVERY TIME vMenu Enhanced STARTS.\n',
        '#  ANY CHANGES YOU MAKE TO IT WILL BE LOST.\n',
        '#\n',
        '#  To use it:\n',
        "#    1. Copy this file and name the copy '" .. copy_name .. "'.\n",
        '#    2. Edit that copy, never this one.\n',
        '#    3. Exec it from your server.cfg ABOVE the line that starts vMenu:\n',
        '#\n',
        '#         exec @vMenu.Enhanced/' .. directory .. '/' .. copy_name .. '\n',
        '#         ensure vMenu.Enhanced\n',
    }
    append_notes(parts, notes)
    parts[#parts + 1] = RULE .. '\n'
    return table.concat(parts)
end

function ExampleFile.banner(copy_name, notes)
    return ExampleFile.banner_in(ExampleFile.CONFIG_DIRECTORY, copy_name, notes)
end

-- For a copy handed out ready to use, which vMenu never writes to.
function ExampleFile.ready_banner(copy_name, notes)
    local parts = {
        RULE .. '\n',
        '#  THIS FILE IS YOURS TO EDIT. vMenu Enhanced NEVER CHANGES IT.\n',
        '#\n',
        "#  It starts out with vMenu's defaults. Every time vMenu starts, it also\n",
        "#  writes '" .. copy_name .. ExampleFile.EXTENSION .. "' next to this file, listing\n",
        '#  everything that version of vMenu knows about. After an update, compare\n',
        '#  the two to find anything new.\n',
        '#\n',
        '#  Your server.cfg has to exec this file ABOVE the line that starts vMenu:\n',
        '#\n',
        '#         exec @vMenu.Enhanced/' .. ExampleFile.CONFIG_DIRECTORY .. '/' .. copy_name .. '\n',
        '#         ensure vMenu.Enhanced\n',
    }
    append_notes(parts, notes)
    parts[#parts + 1] = RULE .. '\n'
    return table.concat(parts)
end

return ExampleFile
