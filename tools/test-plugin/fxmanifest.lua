-- A plugin that uses every part of upstream's plugin API, for testing the
-- Lua vMenu by hand. Never shipped: the release only packs vMenu's own folders.
-- Link this folder into a test server's resources as vMenu.TestPlugin and
-- ensure it after vMenu.Enhanced.

fx_version 'cerulean'
game 'gta5'

name 'vMenu Test Plugin'
description 'Exercises every plugin feature of vMenu Enhanced.'
version '1.0.0'

shared_script 'vmenu.lua'
client_script 'client.lua'
server_script 'server.lua'

files {
    'themes/*.css',
}
