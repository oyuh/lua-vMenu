fx_version 'cerulean'
game 'gta5'
lua54 'yes'

-- Deploy this resource folder as "vMenu" so existing client KVP saves,
-- keybinds, and permissions.cfg keep working (see docs/contracts/).
name 'vMenu'
description 'Server sided trainer for FiveM, rewritten in Lua. Drop-in replacement for the original C# vMenu by Tom Grobbe.'
version '1.0.4'
author 'Tom Grobbe (original vMenu), Lawson (Lua rewrite)'
url 'https://github.com/tomgrobbe/vMenu'

-- Adds additional logging, useful when debugging issues.
client_debug_mode 'false'
server_debug_mode 'false'

-- Architecture: shared/bootstrap.lua installs a require() shim; everything
-- else is a plain Lua module listed under files and loaded on demand. Only
-- entrypoints execute directly.
files {
    'config/*.json',
    'shared/*.lua',
    'menu/*.lua',
    'client/*.lua',
    'client/data/*.lua',
    'client/data/overlays.json',
    'client/functions_controller/*.lua',
    'client/menus/*.lua',
    'server/*.lua',
}

shared_script 'shared/bootstrap.lua'
client_script 'client/main.lua'
server_script 'server/main.lua'
