fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'CookieOCore'
description 'Maze Bank — WHIP native branch, card, loans and in-world ATM banking'
version '1.2.6'

dependency 'whip_core'
dependency 'oxmysql'
whip_requires '1.2.0'

ui_page 'html/index.html'

shared_scripts {
    '@whip_core/lib/satellite.lua',
    'config.lua',
    'shared/settings.lua'
}

client_scripts {
    '@whip_core/client/world_quad.lua',
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

files {
    'html/index.html',
    'html/style.css',
    'html/align.css',
    'html/app.js',
    'html/align.js',
    'html/dui.html',
    'html/dui.css',
    'html/dui.js',
    'html/fonts/*.woff2',
    'html/img/items/*.webp'
}
