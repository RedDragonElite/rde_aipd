-- ============================================================================
--
--   🐉 RED DRAGON ELITE | rde_aipd
--   NOSTR INTEGRATION (SERVER)
--   Author: RDE | SerpentsByte | https://rd-elite.com/
--   Version: 1.0.0
--
--   Decentralized, uncensorable, permanent event logging.
--   Powered by rde_nostr_log + Nostr protocol.
--
--   To enable:  Config.Nostr.enabled = true   (already set in config.lua)
--   To disable: Config.Nostr.enabled = false
--
-- ============================================================================

-- Guard: only run if Nostr logging is enabled in config
if not Config.Nostr or not Config.Nostr.enabled then
    print('^3[RDE | AIPD | Nostr]^7 Nostr logging is DISABLED (Config.Nostr.enabled = false)')
    return
end

local Locale   = lib.load('locales.' .. GetConvar('ox:locale', 'en'))
local resource = Config.Nostr.resource or 'rde_nostr_log'

-- ============================================================================
--  AVAILABILITY CHECK
-- ============================================================================

local nostrAvailable = false

CreateThread(function()
    Wait(3000) -- Wait for rde_nostr_log to fully start
    local ok = pcall(function()
        exports[resource]:getBotNpub()
    end)
    nostrAvailable = ok
    if ok then
        print('^2[RDE | AIPD | Nostr]^7 ✓ Nostr logger connected to ' .. resource)
    else
        print('^1[RDE | AIPD | Nostr]^7 ✗ Resource "' .. resource .. '" not found – Nostr logging inactive')
        print('^3[RDE | AIPD | Nostr]^7   ➜ Install rde_nostr_log: https://github.com/RedDragonElite/rde_nostr_log')
    end
end)

-- ============================================================================
--  HELPER
-- ============================================================================

---Post a structured log to Nostr if available and the specific logLevel is on.
---@param message string   Formatted log message
---@param tags table       Nostr tags [{tag, value}, ...]
---@param logKey string    Key in Config.Nostr.logLevel to check
local function NostrLog(message, tags, logKey)
    if not nostrAvailable then return end
    if logKey and Config.Nostr.logLevel and Config.Nostr.logLevel[logKey] == false then return end

    -- Always add resource tag
    local fullTags = {
        { 'resource', 'rde_aipd' },
        { 'server',   GetConvar('sv_hostname', 'FiveM Server') },
    }
    if tags then
        for _, tag in ipairs(tags) do
            fullTags[#fullTags + 1] = tag
        end
    end

    local ok, err = pcall(function()
        exports[resource]:postLog(message, fullTags)
    end)

    if not ok and Config.Debug then
        print('^1[RDE | AIPD | Nostr]^7 postLog error: ' .. tostring(err))
    end
end

---Resolve a player's display name + identifier safely.
---@param source number
---@return string name, string identifier
local function GetPlayerInfo(source)
    local name = GetPlayerName(source) or ('Player #' .. tostring(source))
    local player = Ox and Ox.GetPlayer(source)
    local identifier = (player and player.getIdentifier and player.getIdentifier('license'))
        or GetPlayerIdentifierByType(source, 'license')
        or ('src:' .. tostring(source))
    return name, identifier
end

-- ============================================================================
--  PLAYER CONNECT / DISCONNECT
-- ============================================================================

if Config.Nostr.logLevel == nil or Config.Nostr.logLevel.player_connect ~= false then
    AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
        local source = source
        CreateThread(function()
            Wait(1000) -- Let ox_core settle
            local _, identifier = GetPlayerInfo(source)
            NostrLog(
                Locale.nostr_connect_event:format(name, identifier),
                { { 'event', 'player_connect' }, { 'player', name }, { 'identifier', identifier } },
                'player_connect'
            )
        end)
    end)
end

if Config.Nostr.logLevel == nil or Config.Nostr.logLevel.player_disconnect ~= false then
    AddEventHandler('playerDropped', function(reason)
        local source = source
        local name, identifier = GetPlayerInfo(source)
        NostrLog(
            Locale.nostr_disconnect_event:format(name, reason or 'unknown'),
            { { 'event', 'player_disconnect' }, { 'player', name }, { 'identifier', identifier }, { 'reason', reason or 'unknown' } },
            'player_disconnect'
        )
    end)
end

-- ============================================================================
--  WANTED LEVEL EVENTS
-- ============================================================================

RegisterNetEvent('police:nostr:wantedSet', function(level, reason)
    local source = source
    local name, identifier = GetPlayerInfo(source)
    NostrLog(
        Locale.nostr_wanted_event:format(name, level, reason or 'crime'),
        {
            { 'event',      'wanted_set'    },
            { 'player',     name            },
            { 'identifier', identifier      },
            { 'level',      tostring(level) },
            { 'reason',     reason or 'crime' },
        },
        'player_wanted'
    )
end)

RegisterNetEvent('police:nostr:wantedCleared', function()
    local source = source
    local name, identifier = GetPlayerInfo(source)
    NostrLog(
        Locale.nostr_wanted_cleared:format(name),
        {
            { 'event',      'wanted_cleared' },
            { 'player',     name             },
            { 'identifier', identifier       },
        },
        'player_wanted'
    )
end)

-- ============================================================================
--  ARREST EVENTS
-- ============================================================================

RegisterNetEvent('police:nostr:arrested', function(wantedLevel)
    local source = source
    local name, identifier = GetPlayerInfo(source)
    NostrLog(
        Locale.nostr_arrest_event:format(name, wantedLevel or 0),
        {
            { 'event',      'player_arrested'            },
            { 'player',     name                         },
            { 'identifier', identifier                   },
            { 'level',      tostring(wantedLevel or 0)   },
        },
        'player_arrested'
    )
end)

RegisterNetEvent('police:nostr:jailed', function(jailTime)
    local source = source
    local name, identifier = GetPlayerInfo(source)
    NostrLog(
        Locale.nostr_jail_event:format(name, jailTime or 0),
        {
            { 'event',      'player_jailed'           },
            { 'player',     name                      },
            { 'identifier', identifier                },
            { 'time',       tostring(jailTime or 0)   },
        },
        'player_jailed'
    )
end)

RegisterNetEvent('police:nostr:released', function()
    local source = source
    local name, identifier = GetPlayerInfo(source)
    NostrLog(
        Locale.nostr_release_event:format(name),
        {
            { 'event',      'player_released' },
            { 'player',     name              },
            { 'identifier', identifier        },
        },
        'player_released'
    )
end)

-- ============================================================================
--  SURRENDER EVENT
-- ============================================================================

RegisterNetEvent('police:nostr:surrendered', function()
    local source = source
    local name, identifier = GetPlayerInfo(source)
    NostrLog(
        Locale.nostr_surrender_event:format(name),
        {
            { 'event',      'player_surrendered' },
            { 'player',     name                 },
            { 'identifier', identifier           },
        },
        'player_arrested'
    )
end)

-- ============================================================================
--  CRIME EVENT
-- ============================================================================

RegisterNetEvent('police:nostr:crime', function(crimeType, area, witnessed)
    local source = source
    local name, identifier = GetPlayerInfo(source)
    local crimeDesc = (Config.CrimeTypes[crimeType] and Config.CrimeTypes[crimeType].description) or crimeType
    NostrLog(
        Locale.nostr_crime_event:format(name, crimeDesc, area or 'Unknown', witnessed and 'Yes' or 'No'),
        {
            { 'event',      'crime_detected'          },
            { 'player',     name                      },
            { 'identifier', identifier                },
            { 'crime',      crimeType                 },
            { 'area',       area or 'Unknown'         },
            { 'witnessed',  witnessed and 'true' or 'false' },
        },
        'crime_detected'
    )
end)

-- ============================================================================
--  OFFICER DOWN
-- ============================================================================

RegisterNetEvent('police:nostr:copKilled', function()
    local source = source
    local name, identifier = GetPlayerInfo(source)
    NostrLog(
        Locale.nostr_cop_killed_event:format(name),
        {
            { 'event',      'officer_down' },
            { 'player',     name           },
            { 'identifier', identifier     },
            { 'priority',   'CRITICAL'     },
        },
        'cop_killed'
    )
end)

-- ============================================================================
--  ESCAPE EVENT
-- ============================================================================

RegisterNetEvent('police:nostr:escaped', function(prevLevel)
    local source = source
    local name, identifier = GetPlayerInfo(source)
    NostrLog(
        Locale.nostr_escape_event:format(name, prevLevel or 0),
        {
            { 'event',      'player_escaped'           },
            { 'player',     name                       },
            { 'identifier', identifier                 },
            { 'prev_level', tostring(prevLevel or 0)   },
        },
        'player_wanted'
    )
end)

-- ============================================================================
--  ADMIN ACTION (optional)
-- ============================================================================

RegisterNetEvent('police:nostr:adminAction', function(action, targetName)
    local source = source
    local adminName, adminId = GetPlayerInfo(source)
    if not (Config.AdminSettings and Config.AdminSettings.allowAdminCommands) then return end
    NostrLog(
        Locale.nostr_admin_action:format(adminName, action or 'unknown', targetName or 'N/A'),
        {
            { 'event',  'admin_action'           },
            { 'admin',  adminName                },
            { 'id',     adminId                  },
            { 'action', action or 'unknown'      },
            { 'target', targetName or 'N/A'      },
        },
        'admin_action'
    )
end)

-- ============================================================================
--  EXPORT — for other resources to fire logs into rde_aipd's Nostr channel
-- ============================================================================

exports('nostrLog', function(message, tags, logKey)
    NostrLog(message, tags, logKey)
end)

-- ============================================================================
--  STARTUP
-- ============================================================================

print('^2[RDE | AIPD | Nostr]^7 ✓ Nostr integration module loaded (v1.0.0)')
print('^2[RDE | AIPD | Nostr]^7 ✓ Using resource: ' .. resource)
print('^2[RDE | AIPD | Nostr]^7 ✓ Waiting for ' .. resource .. ' to connect...')