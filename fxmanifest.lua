fx_version 'cerulean'
game 'gta5'
lua54 'yes'

-- Deploy this resource folder as "vMenu.Enhanced". Plugins, permission and
-- setting names, the generated example files, and player KVP saves all depend
-- on that name, and the resource refuses to start under any other.
name 'vMenu Enhanced'
description 'vMenu Enhanced rewritten in Lua. Runs on FiveM Legacy and FiveM Enhanced.'
version '0.0.0'
author 'Tom Grobbe (vMenu Enhanced), Lawson / oyuh (Lua port)'
url 'https://github.com/oyuh/lua-vMenu/tree/stable'

-- Architecture: shared/bootstrap.lua installs a require() shim; everything
-- else is a plain Lua module listed under files and loaded on demand. Only
-- entrypoints execute directly.
files {
    'shared/*.lua',
    'shared/data/*.lua',
    'menu/*.lua',
    'client/*.lua',
    'server/*.lua',
}

shared_script 'shared/bootstrap.lua'
client_script 'client/main.lua'
server_script 'server/main.lua'
