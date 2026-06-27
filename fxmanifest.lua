fx_version 'cerulean'

game 'gta5'

lua54 'yes'

version '1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/functions.lua',
    'shared/utils.lua',
    'config/main.lua',
    'config/furniture.lua',
    'config/missions.lua',
    'locales/locale.lua',
}

client_scripts {
    'custom/client.lua',
    'client/custom/**',
    'client/modules/**',
    'client/main.lua'
}

ox_libs {
    'table',
    'math'
}

-- ui_page 'http://localhost:3005/'
ui_page 'web/build/index.html'

files {
    'web/build/**',
    'web/images/**',
    'web/sounds/**',
    'locales/*.json',
    'custom/**',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/webhooks.lua',
    'custom/server.lua',
    'server/custom/**',

    'server/modules/db/main.lua',
    'server/modules/db/organization.lua',
    'server/modules/db/territory.lua',
    'server/modules/db/taxing.lua',
    'server/modules/db/vehicleStore.lua',
    'server/modules/db/finance.lua',
    'server/modules/db/garage.lua',
    'server/modules/db/organization_stats.lua',
    'server/modules/db/territory_war.lua',
    'server/modules/db/mission.lua',
    'server/modules/db/pvp.lua',

    'server/modules/*',
    'server/modules/house/**',
    'server/modules/pvp/**',
    'server/main.lua',
}

dependencies {
    '/onesync',
    'ox_lib',
}

escrow_ignore {
    'client/custom/**',
    'server/custom/**',
    'custom/**/*',
    'server/webhooks.lua',
    'config/*',
    'locales/*',
    'types.lua',
}

dependency '/assetpacks'