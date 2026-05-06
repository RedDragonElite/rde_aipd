fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'RDE | SerpentsByte'
name 'rde_aipd'
description 'RDE AIPD | Next-Gen Crime & AI Police System'
version '1.0.1-alpha'

-- ============================================================================
--     NUI
-- ============================================================================
ui_page 'html/wanted_stars.html'

files {
    'html/wanted_stars.html',
    'html/star.png',
    'html/star2.png',
    'html/star3.png',
    'html/star4.png',
    -- Locales must be listed here so ox_lib can load them on the client side
    'locales/en.lua',
    'locales/de.lua'
}

-- ============================================================================
--     SHARED
-- ============================================================================
shared_scripts {
    '@ox_lib/init.lua',
    '@ox_core/lib/init.lua',	
    'config.lua'
}

-- ============================================================================
--     SERVER
-- ============================================================================
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
	'server/crime_witness_handler.lua',
    'server/nostr.lua'     -- 🐉 Nostr decentralized logging integration
}

-- ============================================================================
--     CLIENT
-- ============================================================================
client_scripts {
    'client/main.lua',
    'client/crime.lua'
}

-- ============================================================================
--     DEPENDENCIES
-- ============================================================================
dependencies {
    '/server:7290',
    'oxmysql',
    'ox_lib',
    'ox_core',
    'ox_inventory'
}

-- ============================================================================
--     PROVIDES
-- ============================================================================
provides {
    'police_system',
    'wanted_system',
    'jail_system'
}

-- Performance optimization
experimental_features_enabled '1'