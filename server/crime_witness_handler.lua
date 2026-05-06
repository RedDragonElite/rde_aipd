---@diagnostic disable: undefined-global
-- ════════════════════════════════════════════════════════════════════════════════
-- SERVER-SIDE WITNESS CRIME SYSTEM ENHANCEMENT
-- ════════════════════════════════════════════════════════════════════════════════
-- Add this to your server/main.lua to support the new witness system
-- This replaces the standard police:reportCrime handler
-- ════════════════════════════════════════════════════════════════════════════════

-- NEW: Event for crimes detected but no witnesses
RegisterNetEvent('police:crimeDetectedNoWitness', function(crimeType, coords)
    local source = source
    if not source or source == 0 then return end
    
    -- ✅ FIX #3: totalCrimes wird NICHT mehr hier inkrementiert
    -- LogCrime() weiter unten macht das bereits — war vorher doppelt!
    
    local state = GetPlayerState(source)
    
    -- Store in crime history but mark as unwitnessed
    table.insert(state.crimeHistory, 1, {
        type = crimeType,
        coords = coords,
        timestamp = os.time(),
        witnessed = false,
        wantedBefore = state.level,
        wantedAfter = state.level  -- No change
    })
    
    -- Keep only last 50 crimes
    if #state.crimeHistory > 50 then
        table.remove(state.crimeHistory, 51)
    end
    
    -- Log to database (this also increments totalCrimes)
    LogCrime(source, crimeType, {
        coords = coords,
        witnessed = false,
        timestamp = os.time()
    })
    
    -- Optionally notify admins
    if Config.Debug then
        local playerName = GetPlayerName(source) or 'Unknown'
        print(string.format('^3[Crime NoWitness]^7 %s committed %s at %s - NO WANTED LEVEL',
            playerName, crimeType, coords))
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
        
        -- Show enhanced notification if witness data available
        if hasWitness and witnessData.witness then
            local distance = math.floor(witnessData.witness.distance)
            lib.notify(source, {
                type = 'error',
                description = ('🚨 Zeuge hat 911 angerufen! (~%dm entfernt)'):format(distance),
                duration = 5000
            })
        end
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