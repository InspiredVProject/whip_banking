fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Lunny Dev'
description 'WHIP Banking — Fleeca, Maze Bank and Pacific Standard, cards, teller and DUI ATMs'
version '2.8.0'

dependency 'whip_core'
dependency 'oxmysql'
whip_requires '1.2.0'

ui_page 'html/index.html'

shared_scripts {
    '@whip_core/lib/satellite.lua',
    'config.lua',
    'shared/atm_hardware.lua',
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
    'html/keypad_align.css',
    'html/app.js',
    'html/align.js',
    'html/keypad_align.js',
    'html/dui.html',
    'html/dui.css',
    'html/dui.js',
    'html/card_insert.html',
    'html/card_insert.js',
    'html/fonts/*.woff2',
    'html/img/items/*.webp'
}
