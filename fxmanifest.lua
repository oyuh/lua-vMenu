fx_version 'cerulean'
game 'gta5'
lua54 'yes'

-- Deploy this resource folder as "vMenu" so existing client KVP saves,
-- keybinds, and permissions.cfg keep working (see docs/contracts/).
name 'vMenu'
description 'Server sided trainer for FiveM, rewritten in Lua. Drop-in replacement for the original C# vMenu by Tom Grobbe.'
version '0.1.0'
author 'Tom Grobbe (original vMenu), Lawson (Lua rewrite)'
url 'https://github.com/tomgrobbe/vMenu'

-- Adds additional logging, useful when debugging issues.
client_debug_mode 'false'
server_debug_mode 'false'

files {
    'config/*.json',
}

shared_scripts {
    'shared/util.lua',
    'shared/config.lua',
    'shared/permissions.lua',
}

client_scripts {
    'vendor/json_compat.lua',
    'menu/*.lua',
    'client/data/*.lua',
    'client/*.lua',
    'client/menus/*.lua',
}

server_scripts {
    'vendor/json_compat.lua',
    'server/*.lua',
}
