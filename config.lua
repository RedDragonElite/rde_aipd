Config = {}

-- ============================================================================
-- CORE SETTINGS
-- ============================================================================

Config.Debug = GetConvar('police_debug', 'false') == 'true'
Config.Framework = 'ox_core'
Config.UseStateBags = true  -- ALWAYS USE STATEBAGS FOR REALTIME SYNC!
Config.SyncInterval = 500
Config.OptimizationMode = true

-- ============================================================================
-- ADMIN & POLICE JOBS
-- ============================================================================

Config.AdminGroups = {
    'owner',
    'admin',
    'superadmin',
    'god',
    'mod'
}

Config.PoliceJobs = {
    'police',
    'sheriff',
    'leo',
    'trooper'
}

-- 🔥 ADMIN EXEMPTION SETTINGS (NEW!)
Config.AdminSettings = {
    exemptFromWanted = false,        -- Admins don't get wanted levels
    exemptFromArrest = false,        -- Admins can't be arrested
    exemptFromJail = false,          -- Admins can't be jailed
    showAdminCrimes = true,         -- Show crimes in console even if exempt
    allowAdminCommands = true       -- Allow admin commands while on duty
}

-- ============================================================================
-- WANTED LEVELS - ULTRA REALISTIC
-- ============================================================================

Config.WantedLevels = {
    [0] = {
        label = "No Warrant",
        icon = "fa-solid fa-shield-check",
        time = 0,
        blip = {sprite = 0, color = 0, scale = 0.0},
        dispatchPriority = 'none'
    },
    [1] = {
        label = "Minor Warrant",
        icon = "fa-solid fa-exclamation",
        time = 90,
        blip = {sprite = 56, color = 5, scale = 0.6},
        dispatchPriority = 'low',
        peds = {
            amount = 2,
            models = {"s_m_y_cop_01"},
            weapons = {"WEAPON_PISTOL"},
            vehicles = {"police", "police2"},
            armor = 0,
            accuracy = 25,
            arrestDistance = 2.5,
            shootUnarmed = false,
            spawnDistance = 350.0,
            chaseSpeed = 25.0,
            combatRange = 40.0,
            fleeThreshold = 30,
            useCovers = false,
            tackleProbability = 0.15
        }
    },
    [2] = {
        label = "Standard Warrant",
        icon = "fa-solid fa-exclamation-circle",
        time = 150,
        blip = {sprite = 56, color = 3, scale = 0.7},
        dispatchPriority = 'normal',
        peds = {
            amount = 3,
            models = {"s_m_y_cop_01", "s_m_y_sheriff_01"},
            weapons = {"WEAPON_PISTOL", "WEAPON_PUMPSHOTGUN"},
            vehicles = {"police", "police2", "sheriff"},
            armor = 25,
            accuracy = 35,
            arrestDistance = 2.0,
            shootUnarmed = false,
            spawnDistance = 350.0,
            chaseSpeed = 35.0,
            combatRange = 50.0,
            fleeThreshold = 20,
            useCovers = true,
            tackleProbability = 0.25
        }
    },
    [3] = {
        label = "Serious Warrant",
        icon = "fa-solid fa-exclamation-triangle",
        time = 240,
        blip = {sprite = 56, color = 47, scale = 0.8},
        dispatchPriority = 'high',
        peds = {
            amount = 4,
            models = {"s_m_y_swat_01", "s_m_y_sheriff_01", "s_m_y_cop_01"},
            weapons = {"WEAPON_CARBINERIFLE", "WEAPON_PUMPSHOTGUN", "WEAPON_PISTOL"},
            vehicles = {"police3", "sheriff", "fbi"},
            armor = 50,
            accuracy = 45,
            arrestDistance = 1.5,
            shootUnarmed = false,
            spawnDistance = 400.0,
            chaseSpeed = 45.0,
            combatRange = 60.0,
            fleeThreshold = 15,
            useCovers = true,
            tackleProbability = 0.35
        }
    },
    [4] = {
        label = "Extreme Warrant",
        icon = "fa-solid fa-skull-crossbones",
        time = 360,
        blip = {sprite = 56, color = 1, scale = 0.9},
        dispatchPriority = 'critical',
        peds = {
            amount = 5,
            models = {"s_m_y_swat_01", "s_m_m_armoured_02", "cs_fbisuit_01"},
            weapons = {"WEAPON_CARBINERIFLE", "WEAPON_PUMPSHOTGUN", "WEAPON_SMG"},
            vehicles = {"riot", "fbi2", "police3"},
            armor = 75,
            accuracy = 55,
            arrestDistance = 1.0,
            shootUnarmed = false,
            spawnDistance = 450.0,
            chaseSpeed = 50.0,
            combatRange = 75.0,
            fleeThreshold = 10,
            useCovers = true,
            tackleProbability = 0.45,
            useHelicopters = true
        }
    },
    [5] = {
        label = "Maximum Warrant",
        icon = "fa-solid fa-radiation",
        time = 600,
        blip = {sprite = 56, color = 1, scale = 1.0},
        dispatchPriority = 'max',
        peds = {
            amount = 6,
            models = {"s_m_y_swat_01", "s_m_m_armoured_02", "s_m_m_armoured_01"},
            weapons = {"WEAPON_CARBINERIFLE", "WEAPON_PUMPSHOTGUN", "WEAPON_SMG", "WEAPON_COMBATMG"},
            vehicles = {"riot", "fbi2", "police4"},
            armor = 100,
            accuracy = 70,
            arrestDistance = 1.0,
            shootUnarmed = true,
            spawnDistance = 500.0,
            chaseSpeed = 55.0,
            combatRange = 100.0,
            fleeThreshold = 5,
            useCovers = true,
            tackleProbability = 0.55,
            useHelicopters = true,
            useRoadblocks = true
        }
    }
}

-- ============================================================================
-- PRISON SYSTEM
-- ============================================================================

Config.Prison = {
    enabled = true,
    jailTimeMultiplier = 1.0,
    saveInventory = true,
    clearWeapons = true,
    
    entrance = vector4(433.07, -982.04, 30.71, 94.02),
    exit = vector4(442.15, -981.38, 30.69, 47.58),
    
    cells = {
        vector4(460.06, -994.26, 24.91, 268.89),
        vector4(459.60, -997.64, 24.91, 264.71),
        vector4(459.68, -1001.43, 24.91, 265.66)
    },
    
    activities = {
        enabled = false,
        mining = {reward = 50, time = 30},
        cleaning = {reward = 30, time = 20}
    }
}

-- ============================================================================
-- ANIMATIONS - ULTRA REALISTIC
-- ============================================================================

Config.Animations = {
    handsUp = {
        dict = "missminuteman_1ig_2",
        anim = "handsup_base",
        flag = 49
    },
    surrender = {
        dict = "random@arrests@busted",
        anim = "idle_a",
        flag = 49
    },
    arrest = {
        dict = "mp_arrest_paired",
        anim = "crook_p2_back_right",
        flag = 1
    },
    cuffed = {
        dict = "mp_arresting",
        anim = "idle",
        flag = 49
    },
    tackle = {
        dict = "missmic2ig_11",
        anim = "mic_2_ig_11_intro_goon",
        flag = 0
    }
}

-- ============================================================================
-- SURRENDER SYSTEM
-- ============================================================================

Config.SurrenderKey = 'X'
Config.SurrenderDistance = 10.0
Config.SurrenderTime = 3000

-- ============================================================================
-- CRIME TYPES - COMPREHENSIVE
-- ============================================================================

Config.CrimeTypes = {
    MURDER = {
        level = 3,
        description = "Homicide",
        cooldown = 10000,
        witnessChance = 0.95,
        policeAlert = true,
        severity = 'critical'
    },
    MURDER_COP = {
        level = 5,
        description = "Officer Down",
        cooldown = 5000,
        witnessChance = 1.0,
        policeAlert = true,
        severity = 'critical'
    },
    ASSAULT = {
        level = 1,
        description = "Assault",
        cooldown = 8000,
        witnessChance = 0.7,
        policeAlert = false,
        severity = 'high'
    },
    ASSAULT_COP = {
        level = 3,
        description = "Officer Assault",
        cooldown = 5000,
        witnessChance = 1.0,
        policeAlert = true,
        severity = 'critical'
    },
    SHOOTING = {
        level = 2,
        description = "Shots Fired",
        cooldown = 10000,
        witnessChance = 0.9,
        policeAlert = true,
        severity = 'critical'
    },
    BRANDISHING = {
        level = 1,
        description = "Brandishing Weapon",
        cooldown = 15000,
        witnessChance = 0.6,
        policeAlert = false,
        severity = 'medium'
    },
    VEHICLE_THEFT = {
        level = 1,
        description = "Grand Theft Auto",
        cooldown = 15000,
        witnessChance = 0.65,
        policeAlert = false,
        severity = 'high'
    },
    RECKLESS_DRIVING = {
        level = 1,
        description = "Reckless Driving",
        cooldown = 30000,
        witnessChance = 0.4,
        policeAlert = false,
        severity = 'low'
    },
    HIT_AND_RUN = {
        level = 1,
        description = "Hit and Run",
        cooldown = 15000,
        witnessChance = 0.8,
        policeAlert = false,
        severity = 'high'
    },
    SPEEDING = {
        level = 1,
        description = "Speeding",
        cooldown = 60000,
        witnessChance = 0.3,
        policeAlert = false,
        severity = 'low',
        speedThreshold = 120
    },
    ROBBERY = {
        level = 3,
        description = "Armed Robbery",
        cooldown = 10000,
        witnessChance = 0.9,
        policeAlert = true,
        severity = 'critical'
    },
    BURGLARY = {
        level = 3,
        description = "Burglary",
        cooldown = 10000,
        witnessChance = 0.5,
        policeAlert = false,
        severity = 'high'
    },
    TRESPASSING = {
        level = 1,
        description = "Trespassing",
        cooldown = 45000,
        witnessChance = 0.4,
        policeAlert = false,
        severity = 'low'
    },
    DRUG_POSSESSION = {
        level = 1,
        description = "Drug Possession",
        cooldown = 60000,
        witnessChance = 0.2,
        policeAlert = false,
        severity = 'low'
    },
    DRUG_DEALING = {
        level = 2,
        description = "Drug Trafficking",
        cooldown = 30000,
        witnessChance = 0.5,
        policeAlert = false,
        severity = 'medium'
    },
    VANDALISM = {
        level = 1,
        description = "Vandalism",
        cooldown = 30000,
        witnessChance = 0.5,
        policeAlert = false,
        severity = 'low'
    }
}

-- ============================================================================
-- WITNESS SYSTEM - ADVANCED
-- ============================================================================

Config.WitnessSystem = {
    enabled = true,
    baseDistance = 50.0,
    checkInterval = 1000,
    reportDelay = 5000,
    cooldown = 300000,
    
    areaMultipliers = {
        CITY_CENTER = 1.5,
        URBAN = 1.2,
        SUBURBAN = 1.0,
        RURAL = 0.6,
        WILDERNESS = 0.3
    }
}

-- ============================================================================
-- AREA DEFINITIONS - COMPREHENSIVE
-- ============================================================================

Config.Areas = {
    {
        name = 'DOWNTOWN_LS',
        coords = vector3(153.9, -1036.4, 29.3),
        radius = 1000.0,
        type = 'CITY_CENTER',
        description = 'Downtown Los Santos'
    },
    {
        name = 'PILLBOX_HILL',
        coords = vector3(56.5, -876.5, 30.7),
        radius = 500.0,
        type = 'CITY_CENTER',
        description = 'Pillbox Hill'
    },
    {
        name = 'VESPUCCI',
        coords = vector3(-1111.9, -1497.8, 4.9),
        radius = 700.0,
        type = 'URBAN',
        description = 'Vespucci Beach'
    },
    {
        name = 'VINEWOOD',
        coords = vector3(131.0, 564.0, 183.9),
        radius = 800.0,
        type = 'URBAN',
        description = 'Vinewood Hills'
    },
    {
        name = 'ROCKFORD_HILLS',
        coords = vector3(-1034.0, -2735.0, 20.2),
        radius = 600.0,
        type = 'URBAN',
        description = 'Rockford Hills'
    },
    {
        name = 'DEL_PERRO',
        coords = vector3(-1470.0, -503.0, 32.8),
        radius = 500.0,
        type = 'URBAN',
        description = 'Del Perro'
    },
    {
        name = 'SANDY_SHORES',
        coords = vector3(1959.9, 3741.5, 32.3),
        radius = 800.0,
        type = 'SUBURBAN',
        description = 'Sandy Shores'
    },
    {
        name = 'PALETO_BAY',
        coords = vector3(-279.0, 6230.0, 31.7),
        radius = 700.0,
        type = 'SUBURBAN',
        description = 'Paleto Bay'
    },
    {
        name = 'HARMONY',
        coords = vector3(1185.0, 2637.0, 38.4),
        radius = 500.0,
        type = 'SUBURBAN',
        description = 'Harmony'
    },
    {
        name = 'GRAPESEED',
        coords = vector3(1686.2, 4815.3, 42.0),
        radius = 800.0,
        type = 'RURAL',
        description = 'Grapeseed'
    },
    {
        name = 'GREAT_OCEAN_HIGHWAY',
        coords = vector3(-2500.0, 2500.0, 20.0),
        radius = 1000.0,
        type = 'RURAL',
        description = 'Great Ocean Highway'
    },
    {
        name = 'MOUNT_CHILIAD',
        coords = vector3(493.9, 5588.7, 794.0),
        radius = 1500.0,
        type = 'WILDERNESS',
        description = 'Mount Chiliad'
    },
    {
        name = 'RATON_CANYON',
        coords = vector3(-1652.0, 4445.0, 15.0),
        radius = 1200.0,
        type = 'WILDERNESS',
        description = 'Raton Canyon'
    },
    {
        name = 'ALAMO_SEA',
        coords = vector3(1370.0, 3800.0, 34.0),
        radius = 1500.0,
        type = 'WILDERNESS',
        description = 'Alamo Sea'
    }
}

-- ============================================================================
-- POLICE BLIPS
-- ============================================================================

Config.PoliceBlips = {
    sprite = 56,
    color = 1,
    scale = 0.4,
    alpha = 255,
    displayTime = 120000,
    flash = true
}

-- ============================================================================
-- OPTIMIZATION SETTINGS
-- ============================================================================

Config.Optimization = {
    maxPoliceUnits = 8,
    spawnCooldown = 5000,
    updateInterval = 500,
    cleanupInterval = 10000,
    maxRenderDistance = 500.0,
    cullDistance = 600.0,
    entityPoolSize = 20,
    useEntityCulling = true
}

-- ============================================================================
-- NOTIFICATIONS
-- ============================================================================

Config.Notifications = {
    wantedSet = "Wanted level: %d stars",
    wantedRemoved = "You are no longer wanted",
    wantedIncrease = "Wanted level increased",
    wantedDecrease = "Wanted level decreased",
    surrendering = "Surrendering to police...",
    arrested = "You have been arrested",
    jailed = "Jailed for %d seconds",
    jailReleased = "You have been released",
    policeAlert = "Code %s: %s at %s",
    seconds = "seconds",
    crimeReported = "%s detected!",
    crimeWitnessed = "%d witness(es) reported crime",
    policeNotified = "Police have been notified"
}

-- ============================================================================
-- DEBUG COMMANDS
-- ============================================================================

Config.DebugCommands = {
    enabled = Config.Debug,
    commands = {
        'debugpolice',
        'clearcops',
        'testwanted',
        'spawncop',
        'testcrime',
        'crimestatus'
    }
}

-- ============================================================================
-- COMPATIBILITY SETTINGS
-- ============================================================================

Config.Compatibility = {
    useLegacyEvents = false,
    
    integrations = {
        esx_policejob = false,
        qb_policejob = false,
        ps_dispatch = false
    }
}

-- ============================================================================
-- LOCALE SETTINGS
-- ============================================================================

-- Default language for the system.
-- Supported: 'en' (English) | 'de' (Deutsch)
-- Override on your server with:  set ox:locale "de"
Config.Locale = GetConvar('ox:locale', 'en')

-- ============================================================================
--
--   🐉 RED DRAGON ELITE | rde_aipd
--   CONFIG EXTENSION — rde_nostr_log Integration
--   Author: RDE | SerpentsByte | https://rd-elite.com/
--   Version: 1.1.0
--
--   INSTRUCTIONS:
--     Paste this block INTO your existing config.lua (anywhere after the
--     existing Config table declaration).
--     Requires: rde_nostr_log resource to be started BEFORE rde_aipd.
--
--   SETUP:
--     1. ensure rde_nostr_log   ← must come BEFORE rde_aipd in server.cfg
--     2. ensure rde_aipd
--
-- ============================================================================
--
--  Decentralized, uncensorable, permanent logging.
--  Replace Discord webhooks forever. Powered by rde_nostr_log.
--
--  Install: https://github.com/RedDragonElite/rde_nostr_log
--  Set enabled = false to completely disable all Nostr logging.
--
-- ============================================================================
-- ─────────────────────────────────────────────────────────────────────────────
--  NOSTR LOGGING INTEGRATION
--  Powers every police event into the decentralized Nostr network via
--  rde_nostr_log's export API. Zero overhead — all calls are fire-and-forget.
-- ─────────────────────────────────────────────────────────────────────────────

Config.Nostr = {

    -- Master switch: set false to completely disable all Nostr logging
    enabled  = true,

    -- The resource name of your rde_nostr_log installation.
    -- Change this only if you renamed the resource folder.
    resource = 'rde_nostr_log',

    -- ── PER-CATEGORY SWITCHES ───────────────────────────────────────────────
    -- Set any category to false to silence that event type entirely.
    -- Useful for high-traffic servers that want to cut Nostr noise.

    logLevel = {
        player_connect    = false,   -- 🟢 Player joined the server
        player_disconnect = false,   -- 🔴 Player left the server
        player_wanted     = true,   -- ⭐ Wanted level set / cleared
        crime_detected    = true,   -- 🚨 Crime event detected
        player_arrested   = true,   -- 🚔 Player arrested (before jail)
        player_jailed     = true,   -- ⛓  Player teleported to jail
        player_released   = true,   -- ✅ Player released from jail
        cop_killed        = true,   -- 💀 Player killed a police officer
        admin_action      = true,   -- 🛡  Admin used a police command
    },

}

-- ─────────────────────────────────────────────────────────────────────────────
--  QUICK REFERENCE — What triggers each log category
-- ─────────────────────────────────────────────────────────────────────────────
--
--  player_connect    → ox:playerLoaded  (fires after charid loads)
--  player_disconnect → playerDropped    (fires before state cleanup)
--  player_wanted     → SetWantedLevel() (both increase AND clear)
--  crime_detected    → police:reportCrime event  (every crime type)
--  player_arrested   → police:arrestPlayer callback (paired with anim)
--  player_jailed     → JailPlayer()     (after inventory is saved)
--  player_released   → ReleasePlayer()  (after inventory is restored)
--  cop_killed        → MURDER_COP crime type specifically
--  admin_action      → /setwanted /clearwanted /jail /unjail /panic
--
-- ─────────────────────────────────────────────────────────────────────────────
-- ============================================================================
-- ICONS & COLORS  (RDE Standard)
-- ============================================================================

Config.Icons = {
    success  = 'check-circle',
    error    = 'x-circle',
    warning  = 'alert-triangle',
    info     = 'info',
    police   = 'shield',
    skull    = 'skull',
    star     = 'star',
    jail     = 'lock',
    escape   = 'wind',
    weapon   = 'crosshair',
}

Config.Colors = {
    success  = '#10b981',
    error    = '#ef4444',
    warning  = '#f59e0b',
    info     = '#3b82f6',
    police   = '#60a5fa',
    skull    = '#f43f5e',
    jail     = '#a78bfa',
}