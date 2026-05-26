---@diagnostic disable: undefined-global
-- ════════════════════════════════════════════════════════════════════════════════
-- SERVER-SIDE WITNESS CRIME SYSTEM ENHANCEMENT
-- ════════════════════════════════════════════════════════════════════════════════
-- Add this to your server/main.lua to support the new witness system
-- This replaces the standard police:reportCrime handler
-- ✅ FIX #27 (1.0.1-alpha): Locale-Loading via ox_lib
-- ✅ FIX #29 (1.0.1-alpha): Doppel-Notification entfernt — SetWantedLevel zeigt
--                           bereits "Wanted Level: X ⭐" direkt danach.
-- ✅ FIX #34 (1.0.3-alpha): Eigenes lokales Debug() — main.lua's Debug ist `local`
--                           und nicht cross-file erreichbar (RDE OX Standard:
--                           jede Datei hat ihr eigenes Logging).
-- ✅ FIX #35 (1.0.3-alpha): Doppel-Insert in crimeHistory bei
--                           police:crimeDetectedNoWitness entfernt — LogCrime()
--                           macht das bereits.
-- ✅ FIX #38 (1.0.4-alpha): Server-side CrimeReportCache als defense-in-depth
--                           gegen Doppel-Trigger (analog zu NotificationCache aus
--                           RDE OX Standards). Verhindert dass derselbe Crime
--                           vom selben Player innerhalb von 2s zweimal in der DB
--                           landet — egal ob Race, Spam-Command oder externes
--                           Resource ihn doppelt feuert.
-- ════════════════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════════════════════
-- LOCALE LOADER (FIX #27)
-- ════════════════════════════════════════════════════════════════════════════════
local Locale = lib.load('locales.' .. GetConvar('ox:locale', 'en')) or {}
local function L(key, ...)
    local s = Locale[key]
    if not s then return key end
    if select('#', ...) > 0 then return s:format(...) end
    return s
end

-- ════════════════════════════════════════════════════════════════════════════════
-- LOCAL DEBUG (FIX #34)
-- main.lua hat ein lokales Debug() das hier nicht erreichbar ist.
-- RDE OX Standard: jede Datei bekommt ihr eigenes lokales Logging.
-- ════════════════════════════════════════════════════════════════════════════════
local function Debug(...)
    if Config.Debug then
        print('^3[AIPD | CrimeWitness]^7', ...)
    end
end

-- ════════════════════════════════════════════════════════════════════════════════
-- CRIME REPORT CACHE (FIX #38) — Server-side Dedup
-- Analog zu NotificationCache aus den RDE OX Standards. 2s Window per Player+Crime.
-- Schützt gegen:
--   • Race conditions am Client (zwei Coroutines triggern denselben Crime im Frame)
--   • Externe Resources die LogCrime-Export doppelt aufrufen
--   • Spam von Test-Commands wie /testwitness
-- Auto-cleanup beim playerDropped (ganz unten in dieser Datei).
-- ════════════════════════════════════════════════════════════════════════════════
local CrimeReportCache = {}
local CRIME_DEDUP_WINDOW = 2000  -- ms

local function IsCrimeRecentlyReported(source, crimeType)
    local cache = CrimeReportCache[source]
    if not cache or not cache[crimeType] then return false end
    return (GetGameTimer() - cache[crimeType]) < CRIME_DEDUP_WINDOW
end

local function MarkCrimeReported(source, crimeType)
    CrimeReportCache[source] = CrimeReportCache[source] or {}
    CrimeReportCache[source][crimeType] = GetGameTimer()
end

AddEventHandler('playerDropped', function()
    local src = source
    if src and CrimeReportCache[src] then CrimeReportCache[src] = nil end
end)

-- NEW: Event for crimes detected but no witnesses
RegisterNetEvent('police:crimeDetectedNoWitness', function(crimeType, coords)
    local source = source
    if not source or source == 0 then return end

    -- ✅ FIX #38: Server-side Dedup (2s Window)
    if IsCrimeRecentlyReported(source, crimeType) then
        Debug(('🚫 Dedup: %s von Player %d innerhalb %dms — skipped'):format(
            crimeType, source, CRIME_DEDUP_WINDOW))
        return
    end
    MarkCrimeReported(source, crimeType)

    -- ✅ FIX #3:  totalCrimes wird NICHT mehr hier inkrementiert
    -- ✅ FIX #35: table.insert in crimeHistory entfernt — LogCrime() macht das
    --            bereits (main.lua:400). Vorher war der Eintrag doppelt.

    -- Log to database — LogCrime kümmert sich um:
    --   • state.crimes[crimeType] +1
    --   • state.totalCrimes +1
    --   • state.crimeHistory insert (mit data.witnessed=false)
    --   • DB-Insert in crime_logs
    --   • SyncPlayerState
    LogCrime(source, crimeType, {
        coords    = coords,
        witnessed = false,
        timestamp = os.time()
    })

    -- Optionally notify admins
    if Config.Debug then
        local playerName = GetPlayerName(source) or 'Unknown'
        print(string.format('^3[Crime NoWitness]^7 %s committed %s at %s - NO WANTED LEVEL',
            playerName, crimeType, tostring(coords)))
    end
end)

-- MODIFIED: Standard crime report - ONLY when witness successfully calls 911
-- Client sends a single table: { type, coords, level, witnessCount, callCompleted, witness, ... }
RegisterNetEvent('police:reportCrime', function(data)
    local source = source
    if not source or source == 0 then return end

    -- Support both new (single-table) and old (3-arg) calling convention
    local crimeType, coords, witnessData
    if type(data) == 'table' and data.type then
        -- New style: single table from crime.lua Execute911CallSequence
        crimeType   = data.type
        coords      = data.coords
        witnessData = data   -- the whole table IS the witnessData
    else
        -- Old style fallback: (crimeType, coords, witnessData) — should not happen
        crimeType   = data
        coords      = nil
        witnessData = nil
    end

    -- Validate crime type
    local crimeConfig = Config.CrimeTypes[crimeType]
    if not crimeConfig then
        Debug(('Unknown crime type: %s'):format(tostring(crimeType)))
        return
    end

    -- ✅ FIX #38: Server-side Dedup (2s Window)
    -- Schützt den `witnessed=true` Pfad gegen Race/Spam — analog zum
    -- crimeDetectedNoWitness Handler oben. Vorher konnte ein doppelt
    -- gefeuertes Event (z.B. /testwitness Spam oder externes Resource)
    -- den Crime zweimal in die DB schreiben.
    if IsCrimeRecentlyReported(source, crimeType) then
        Debug(('🚫 Dedup: %s von Player %d innerhalb %dms — skipped (witnessed path)'):format(
            crimeType, source, CRIME_DEDUP_WINDOW))
        return
    end
    MarkCrimeReported(source, crimeType)

    -- Check if this report came from a witness (new system)
    local hasWitness = witnessData and witnessData.callCompleted

    if not hasWitness then
        Debug(('⚠️ Crime reported without witness confirmation: %s'):format(crimeType))
        -- Fallback to old system for compatibility
    end

    Debug(('🚨 Crime reported WITH witness: %s by player %d'):format(crimeType, source))
    
    -- Log the crime
    LogCrime(source, crimeType, {
        coords = coords,
        witnessed = hasWitness,
        witnessCount = witnessData and witnessData.witnessCount or 0,
        witnessData = witnessData,
        timestamp = os.time()
    })
    
    -- Apply wanted level ONLY if not exempt
    if not IsExemptFromWanted(source) then
        local state = GetPlayerState(source)
        local currentLevel = state.level
        local crimeLevel = crimeConfig.level or 1
        local newLevel = currentLevel
        
        -- Additive wanted level system
        if currentLevel == 0 then
            newLevel = crimeLevel
            Debug(('First crime: %s | Level 0 -> %d'):format(crimeType, newLevel))
        else
            if crimeLevel > currentLevel then
                newLevel = crimeLevel
                Debug(('Crime upgrade: %s | %d -> %d'):format(crimeType, currentLevel, newLevel))
            elseif crimeLevel == currentLevel then
                newLevel = math.min(5, currentLevel + 1)
                Debug(('Same level crime: %s | %d -> %d'):format(crimeType, currentLevel, newLevel))
            else
                Debug(('Ignoring lower crime: %s | current %d > crime %d'):format(
                    crimeType, currentLevel, crimeLevel
                ))
                NotifyPolice(crimeType, coords, witnessData)
                return
            end
        end
        
        newLevel = math.min(5, newLevel)
        
        -- Update crime history
        if state.crimeHistory[1] then
            state.crimeHistory[1].wantedAfter = newLevel
        end
        
        -- Set wanted level
        SetWantedLevel(source, newLevel, crimeConfig.description or crimeType)

        -- ✅ FIX #33 (1.0.2-alpha): Co-Occupant Wanted Propagation
        -- Beifahrer im selben Fahrzeug erben den Wanted Level (wie GTA Online).
        -- Client hat die Server-IDs im witnessData.coOccupants Feld mitgeschickt.
        if witnessData and witnessData.coOccupants and #witnessData.coOccupants > 0 then
            PropagateWantedToCoOccupants(
                source,
                newLevel,
                witnessData.coOccupants,
                crimeConfig.description or crimeType
            )
        end

        -- ✅ FIX #29: Extra "Zeuge hat 911 angerufen" Notification entfernt.
        -- War redundant — SetWantedLevel() unten schickt bereits "Wanted Level: X ⭐".
        -- Vorher hatte der Spieler 3 Notifications pro Crime:
        --   1) crime.lua: "Zeuge hat dich gesehen"  (vor 911-Call)
        --   2) hier:      "Zeuge hat 911 angerufen" (← entfernt, redundant)
        --   3) main.lua:  "Wanted Level: X ⭐"      (von SetWantedLevel)
        -- Jetzt: nur noch (1) + (3). Der Witness-Distance-Wert wird trotzdem
        -- via state.crimeHistory persistiert für /crimes & Nostr-Logs.
    else
        if Config.AdminSettings.showAdminCrimes then
            Debug(('Admin %d committed %s (exempt from wanted)'):format(source, crimeType))
        end
    end
    
    -- Polizei benachrichtigen (NotifyPolice kommt aus main.lua)
    -- witnessData wird als data-Parameter übergeben
    local notifyData = witnessData or {}
    notifyData.type  = crimeType
    notifyData.coords = coords
    NotifyPolice(crimeType, coords, notifyData)
end)

-- NotifyPolice ist in main.lua definiert und direkt verwendbar (gleicher Resource-Scope).
-- Hier wird witnessData als zusätzlicher Parameter weitergegeben.

-- Print initialization message
print('^2[AIPD | Server NextGen]^7 ✅ Witness-based crime reporting enabled')
print('^2[AIPD | Server NextGen]^7 ✅ Crimes without witnesses are logged but don\'t give wanted level')
print(('^2[AIPD | Server NextGen]^7 ✅ Server-side dedup active (window=%dms)'):format(CRIME_DEDUP_WINDOW))