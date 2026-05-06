---@diagnostic disable: undefined-global
-- ════════════════════════════════════════════════════════════════
-- POLICE SYSTEM - SERVER (NEXT-GEN + ADDITIVE WANTED + DECAY)
-- ════════════════════════════════════════════════════════════════
-- ✅ FIX #1: AddEventHandler statt RegisterNetEvent für ox:playerLoaded
-- ✅ FIX #1b: police:systemReady wird auch bei invalid charid gesendet
-- ✅ FIX #5: Jail Restore Timing — teleportToJail erst NACH systemReady
-- ✅ FIX #11: Race Condition — teleportToJail nach Delay gesendet damit
--             MySQL-Query abgeschlossen ist, bevor der Client restored.
--             checkJailStatus-Callback allein ist nicht zuverlässig genug,
--             da er vor MySQL-Completion aufgerufen werden kann.
-- ════════════════════════════════════════════════════════════════

local Ox = require '@ox_core.lib.init'
local PlayerStates = {}

-- ════════════════════════════════════════════════════════════════
-- RDE SYNC PATTERN - BROADCAST SYSTEM
-- ════════════════════════════════════════════════════════════════
local lastBroadcast = {}
local broadcastCooldown = 100  -- milliseconds
local initialized = true

function Debug(...)
    if Config.Debug then
        print('^3[AIPD | Server]^7', ...)
    end
end

-- ════════════════════════════════════════════════════════════════
-- PERMISSION CHECKS
-- ════════════════════════════════════════════════════════════════

function HasGroup(source, groups)
    if not source or source == 0 then return false end

    local player = Ox.GetPlayer(source)
    if not player then return false end

    for _, group in ipairs(groups) do
        if player.getGroup(group) then return true end
    end
    return false
end

function IsPolice(source)
    return HasGroup(source, Config.PoliceJobs)
end

function IsAdmin(source)
    return HasGroup(source, Config.AdminGroups)
end

function IsExemptFromWanted(source)
    if not Config.AdminSettings.exemptFromWanted then return false end
    return IsAdmin(source)
end

function IsExemptFromArrest(source)
    if not Config.AdminSettings.exemptFromArrest then return false end
    return IsAdmin(source)
end

function IsExemptFromJail(source)
    if not Config.AdminSettings.exemptFromJail then return false end
    return IsAdmin(source)
end

-- ════════════════════════════════════════════════════════════════
-- RDE BROADCAST PATTERN - BROADCAST TO ALL PLAYERS
-- ════════════════════════════════════════════════════════════════

local function BroadcastPlayerState(source, state)
    if not source or source == 0 then return end
    if not state then state = GetPlayerState(source) end
    
    -- Rate limiting
    local currentTime = GetGameTimer()
    if lastBroadcast[source] and (currentTime - lastBroadcast[source] < broadcastCooldown) then
        return  -- Too soon, skip broadcast
    end
    lastBroadcast[source] = currentTime
    
    -- Broadcast to ALL players (-1)
    TriggerClientEvent('police:playerStateUpdate', -1, source, {
        level = state.level or 0,
        isJailed = state.isJailed or false,
        jailTime = state.jailTime or 0,
        totalCrimes = state.totalCrimes or 0,
        isAdmin = state.isAdmin or false,
        isPolice = state.isPolice or false
    })
    
    Debug(('Broadcast state for player %d | Wanted: %d | Jailed: %s'):format(
        source, state.level, tostring(state.isJailed)
    ))
end

local function SyncAllPlayers(targetSource)
    if not targetSource or targetSource == 0 then return end
    
    -- Wait for initialization
    local attempts = 0
    while not initialized and attempts < 20 do
        Wait(100)
        attempts = attempts + 1
    end
    
    if not initialized then
        Debug('SyncAllPlayers failed - not initialized')
        return
    end
    
    -- Convert table to array
    local stateArray = {}
    for source, state in pairs(PlayerStates) do
        if GetPlayerName(source) then  -- Only online players
            table.insert(stateArray, {
                source = source,
                level = state.level or 0,
                isJailed = state.isJailed or false,
                jailTime = state.jailTime or 0,
                totalCrimes = state.totalCrimes or 0,
                isAdmin = state.isAdmin or false,
                isPolice = state.isPolice or false
            })
        end
    end
    
    -- Send complete state to this player
    TriggerClientEvent('police:syncAllStates', targetSource, stateArray)
    
    Debug(('Synced %d player states to %s'):format(#stateArray, GetPlayerName(targetSource)))
end

-- ════════════════════════════════════════════════════════════════
-- PLAYER STATE MANAGEMENT
-- ════════════════════════════════════════════════════════════════

function GetPlayerState(source)
    if not PlayerStates[source] then
        PlayerStates[source] = {
            level = 0,
            lastUpdate = os.time(),
            isJailed = false,
            jailTime = 0,
            jailCell = 1,
            crimes = {},
            totalCrimes = 0,
            isAdmin = IsAdmin(source),
            isPolice = IsPolice(source),
            initialized = false,
            crimeHistory = {},
            -- ✅ FIX #9: charid cachen damit playerDropped es nach Disconnect
            -- noch lesen kann — Ox.GetPlayer gibt nach Disconnect nil zurück
            charid = nil,
            -- ✅ FIX #7: lastDecay für Rate-Limiting
            lastDecay = 0,
        }
    end
    return PlayerStates[source]
end

function GetCharId(source)
    if not source or source == 0 then return nil end

    -- ✅ FIX #9: Erst gecachten charid prüfen (funktioniert auch nach Disconnect)
    if PlayerStates[source] and PlayerStates[source].charid then
        return PlayerStates[source].charid
    end

    local player = Ox.GetPlayer(source)
    if not player then return nil end

    local charid = player.charid or source

    -- Im State cachen für spätere Aufrufe (playerDropped etc.)
    if PlayerStates[source] then
        PlayerStates[source].charid = charid
    end

    return charid
end

-- ════════════════════════════════════════════════════════════════
-- STATEBAG SYNC
-- ════════════════════════════════════════════════════════════════

function SyncPlayerState(source)
    if not Config.UseStateBags then return end
    if not source or source == 0 then return end

    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return end

    local state = GetPlayerState(source)
    local stateBag = Entity(ped).state

    stateBag:set('wantedLevel', state.level, true)
    stateBag:set('isJailed', state.isJailed, true)
    stateBag:set('jailTime', state.jailTime, true)
    stateBag:set('totalCrimes', state.totalCrimes, true)
    stateBag:set('isAdmin', state.isAdmin, true)
    stateBag:set('isPolice', state.isPolice, true)
    
    -- ✅ RDE SYNC PATTERN: Broadcast to ALL players
    BroadcastPlayerState(source, state)

    Debug(('Synced state for player %d | Wanted: %d | Jailed: %s'):format(
        source, state.level, tostring(state.isJailed)
    ))
end

-- ════════════════════════════════════════════════════════════════
-- ADDITIVE WANTED LEVEL SYSTEM
-- ════════════════════════════════════════════════════════════════

function SetWantedLevel(source, level, reason)
    if not source or source == 0 then return end

    if IsExemptFromWanted(source) then
        if Config.AdminSettings.showAdminCrimes then
            Debug(('Admin %d would have wanted level %d (exempt)'):format(source, level))
        end
        return
    end

    level = math.max(0, math.min(5, level))
    local state = GetPlayerState(source)
    local oldLevel = state.level
    state.level = level
    state.lastUpdate = os.time()

    -- ✅ RDE SYNC PATTERN: Broadcast to ALL via statebag sync
    SyncPlayerState(source)

    if level > oldLevel then
        lib.notify(source, {
            type = 'error',
            description = ('Wanted Level: %d ⭐'):format(level),
            icon = 'shield-alert'
        })
    elseif level == 0 then
        lib.notify(source, {
            type = 'success',
            description = 'No longer wanted',
            icon = 'shield-check'
        })
    end

    Debug(('Set wanted level for player %d: %d -> %d (Reason: %s)'):format(
        source, oldLevel, level, reason or 'Unknown'
    ))
end

-- ════════════════════════════════════════════════════════════════
-- INVENTORY MANAGEMENT
-- ════════════════════════════════════════════════════════════════

function SaveInventory(source)
    if not Config.Prison.saveInventory then return end
    if not source or source == 0 then return end

    local player = Ox.GetPlayer(source)
    if not player then return end

    local state = GetPlayerState(source)

    local success, inv = pcall(function()
        return exports.ox_inventory:GetInventory(source, false)
    end)

    if success and inv then
        state.savedInventory = {
            items = inv.items or {},
            weight = inv.weight or 0
        }

        pcall(function()
            exports.ox_inventory:ClearInventory(source)
        end)

        if Config.Prison.clearWeapons then
            TriggerClientEvent('police:clearWeapons', source)
        end

        Debug(('Saved %d items for player %d'):format(#(inv.items or {}), source))
    end
end

function RestoreInventory(source)
    if not Config.Prison.saveInventory then return end
    if not source or source == 0 then return end

    local player = Ox.GetPlayer(source)
    if not player then return end

    local state = GetPlayerState(source)

    if state.savedInventory and state.savedInventory.items then
        for _, item in pairs(state.savedInventory.items) do
            if item and item.name and item.count then
                pcall(function()
                    exports.ox_inventory:AddItem(source, item.name, item.count, item.metadata)
                end)
            end
        end
        state.savedInventory = nil
        Debug(('Restored inventory for player %d'):format(source))
    end
end

-- ════════════════════════════════════════════════════════════════
-- JAIL SYSTEM
-- ════════════════════════════════════════════════════════════════

function JailPlayer(source, time, cell)
    if not source or source == 0 then return end

    -- ✅ FIX #17: Eingangs-Validierung. Vorher konnte ein nil/string-Time den
    -- Server-Timer-Thread mit `nil > 0` zum Crash bringen → ALLE Spieler hängen für immer im Jail.
    time = tonumber(time)
    if not time or time < 10 then time = 60 end
    time = math.floor(time)

    if IsExemptFromJail(source) then
        lib.notify(source, {
            type = 'info',
            description = 'Admin exemption: Cannot be jailed',
            icon = 'shield-check'
        })
        Debug(('Admin %d is exempt from jail'):format(source))
        return
    end

    local charid = GetCharId(source)
    if not charid then return end

    local state = GetPlayerState(source)
    state.isJailed = true
    state.jailTime = time
    state.jailCell = tonumber(cell) or math.random(#Config.Prison.cells)
    if not Config.Prison.cells[state.jailCell] then
        state.jailCell = math.random(#Config.Prison.cells)
    end
    state.level = 0

    SaveInventory(source)
    
    -- ✅ RDE SYNC PATTERN: Broadcast to ALL via statebag sync
    SyncPlayerState(source)

    if MySQL then
        MySQL.Async.execute([[
            INSERT INTO police_records (charid, is_jailed, jail_time, jail_cell, jail_start, saved_inventory, wanted_level)
            VALUES (?, 1, ?, ?, NOW(), ?, 0)
            ON DUPLICATE KEY UPDATE
                is_jailed = 1,
                jail_time = VALUES(jail_time),
                jail_cell = VALUES(jail_cell),
                jail_start = NOW(),
                saved_inventory = VALUES(saved_inventory),
                wanted_level = 0
        ]], {
            charid,
            time,
            state.jailCell,
            state.savedInventory and json.encode(state.savedInventory) or nil
        })
    end

    TriggerClientEvent('police:teleportToJail', source, state.jailCell, time)
    Debug(('Jailed player %d for %ds in cell %d'):format(source, time, state.jailCell))
end

function ReleasePlayer(source)
    if not source or source == 0 then return end

    local charid = GetCharId(source)
    if not charid then return end

    local state = GetPlayerState(source)
    if not state.isJailed then return end

    state.isJailed = false
    state.jailTime = 0

    RestoreInventory(source)
    
    -- ✅ RDE SYNC PATTERN: Broadcast to ALL via statebag sync
    SyncPlayerState(source)

    if MySQL then
        MySQL.Async.execute([[
            UPDATE police_records
            SET is_jailed = 0, jail_time = 0, jail_start = NULL, saved_inventory = NULL, last_arrest = NOW()
            WHERE charid = ?
        ]], {charid})
    end

    TriggerClientEvent('police:teleportFromJail', source)
    lib.notify(source, {
        type = 'success',
        description = 'Released from jail',
        icon = 'door-open'
    })

    Debug(('Released player %d from jail'):format(source))
end

-- ════════════════════════════════════════════════════════════════
-- CRIME LOGGING
-- ════════════════════════════════════════════════════════════════

function LogCrime(source, crimeType, data)
    if not source or source == 0 then return end

    local state = GetPlayerState(source)

    -- ✅ FIX #4: crimes ist NUR ein Dictionary für Zähler (String-Keys)
    -- crimeHistory ist NUR ein Array für die letzten Einträge (numerische Keys)
    -- Keine Vermischung mehr → sauberes json.encode für DB
    state.crimes[crimeType] = (state.crimes[crimeType] or 0) + 1
    state.totalCrimes = state.totalCrimes + 1

    table.insert(state.crimeHistory, 1, {
        type = crimeType,
        time = os.time(),
        data = data,
        wantedBefore = state.level,
        wantedAfter = state.level
    })

    if #state.crimeHistory > 50 then
        table.remove(state.crimeHistory, 51)
    end

    SyncPlayerState(source)

    local charid = GetCharId(source)
    if charid and MySQL then
        MySQL.Async.execute([[
            INSERT INTO crime_logs (charid, crime_type, area_type, witness_count, crime_data, reported_time)
            VALUES (?, ?, ?, ?, ?, NOW())
        ]], {
            charid,
            crimeType,
            data and data.areaType or 'UNKNOWN',
            data and data.witnessCount or 0,
            data and json.encode(data) or nil
        })
    end

    Debug(('Logged crime %s for player %d (Total: %d)'):format(
        crimeType, source, state.totalCrimes
    ))
end

-- ════════════════════════════════════════════════════════════════
-- POLICE NOTIFICATIONS
-- ════════════════════════════════════════════════════════════════

function NotifyPolice(crimeType, coords, data)
    local crimeConfig = Config.CrimeTypes[crimeType]
    if not crimeConfig then return end

    local players = GetPlayers()
    local notifiedCount = 0

    for _, playerId in ipairs(players) do
        local pid = tonumber(playerId)
        if pid and IsPolice(pid) then
            local alertChance = crimeConfig.policeAlert and 0.9 or 0.6
            if math.random() < alertChance then
                TriggerClientEvent('police:crimeAlert', pid, {
                    type = crimeType,
                    coords = coords,
                    data = data,
                    time = os.time(),
                    severity = crimeConfig.severity or 'medium',
                    description = crimeConfig.description or crimeType
                })
                notifiedCount = notifiedCount + 1
            end
        end
    end

    Debug(('Notified %d police officers about %s'):format(notifiedCount, crimeType))
end

-- ════════════════════════════════════════════════════════════════
-- CALLBACKS
-- ════════════════════════════════════════════════════════════════

lib.callback.register('police:getWantedLevel', function(source)
    if not source or source == 0 then return 0 end
    return GetPlayerState(source).level
end)

lib.callback.register('police:checkJailStatus', function(source)
    if not source or source == 0 then return {jailed = false} end

    local state = GetPlayerState(source)
    return {
        jailed = state.isJailed,
        time = state.jailTime,
        cell = state.jailCell
    }
end)

lib.callback.register('police:isAdmin', function(source)
    if not source or source == 0 then return false end
    return IsAdmin(source)
end)

lib.callback.register('police:isPolice', function(source)
    if not source or source == 0 then return false end
    return IsPolice(source)
end)

lib.callback.register('police:arrestPlayer', function(source, jailTime, cell)
    if not source or source == 0 then return false end
    -- ✅ FIX #8: Validierung — nur wenn tatsächlich Wanted Level vorhanden
    local state = GetPlayerState(source)
    if state.level <= 0 and not state.isJailed then
        Debug(('arrestPlayer rejected: player %d has no wanted level'):format(source))
        return false
    end
    -- Minimum Jail-Time erzwingen (gegen 1s-Jail Exploit)
    if type(jailTime) ~= 'number' or jailTime < 30 then
        jailTime = Config.WantedLevels[state.level] and Config.WantedLevels[state.level].time or 60
    end
    JailPlayer(source, jailTime, cell)
    return true
end)

lib.callback.register('police:releasePlayer', function(source)
    if not source or source == 0 then return false end
    -- ✅ FIX #9: Nur releasen wenn tatsächlich im Jail UND jailTime abgelaufen
    local state = GetPlayerState(source)
    if not state.isJailed then
        Debug(('releasePlayer rejected: player %d is not jailed'):format(source))
        return false
    end
    -- Nur vom Server-Timer oder Admin — Client darf nicht selbst releasen
    -- Wenn jailTime > 0 ist, wurde der Release NICHT vom Timer ausgelöst
    if state.jailTime > 5 then
        Debug(('releasePlayer rejected: player %d still has %ds remaining'):format(source, state.jailTime))
        return false
    end
    ReleasePlayer(source)
    return true
end)

lib.callback.register('police:playerDied', function(source)
    if not source or source == 0 then return false end
    local state = GetPlayerState(source)
    if state.level > 0 then
        SetWantedLevel(source, 0, 'Death')
    end
    return true
end)

lib.callback.register('police:getCrimeHistory', function(source, targetSource)
    targetSource = targetSource or source
    if not targetSource or targetSource == 0 then return {} end
    local state = GetPlayerState(targetSource)
    return state.crimeHistory or {}
end)

-- ════════════════════════════════════════════════════════════════
-- NET EVENTS
-- ════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════
-- HINWEIS: police:reportCrime wird NICHT hier behandelt.
-- Der Handler lebt in server/crime_witness_handler.lua
-- und erwartet witnessData.callCompleted == true (911-Call abgeschlossen).
--
-- Direkter Zugriff auf interne Funktionen ist möglich da beide
-- Dateien im selben Resource-Scope laufen:
--   SetWantedLevel(), IsExemptFromWanted(), LogCrime(), NotifyPolice()
--   GetPlayerState() → alle aus main.lua, direkt verwendbar.
-- ════════════════════════════════════════════════════════════════

RegisterNetEvent('police:decayWantedLevel', function()
    local source = source
    if not source or source == 0 then return end

    local state = GetPlayerState(source)
    local currentLevel = state.level

    -- ✅ FIX #7: Rate-Limiting gegen Exploit-Spam (min. 15s zwischen Decays)
    local now = os.time()
    if state.lastDecay and (now - state.lastDecay) < 15 then
        Debug(('Decay rate-limited for player %d'):format(source))
        return
    end
    state.lastDecay = now

    if currentLevel > 0 then
        local newLevel = currentLevel - 1
        SetWantedLevel(source, newLevel, 'Evaded Police')
        Debug(('Wanted decay: Player %d | %d -> %d'):format(source, currentLevel, newLevel))
    end
end)

RegisterNetEvent('police:arrest', function(targetId)
    local source = source
    if not source or source == 0 then return end
    if not IsPolice(source) then return end
    if not targetId or targetId == 0 then return end

    if IsExemptFromArrest(targetId) then
        lib.notify(source, {
            type = 'error',
            description = 'Cannot arrest admin',
            icon = 'shield-check'
        })
        return
    end

    local state = GetPlayerState(targetId)
    if state.level > 0 then
        local jailTime = Config.WantedLevels[state.level].time or 60
        jailTime = math.floor(jailTime * Config.Prison.jailTimeMultiplier)
        JailPlayer(targetId, jailTime)
    end
end)

-- ════════════════════════════════════════════════════════════════
-- SYNCED ANIMATIONS
-- ════════════════════════════════════════════════════════════════

RegisterNetEvent('police:syncTackle', function(targetPlayerId, forwardVector)
    local source = source
    if not source or source == 0 then return end
    if not targetPlayerId or not forwardVector then return end

    local targetPed = GetPlayerPed(targetPlayerId)
    if not targetPed or targetPed == 0 then return end

    local targetCoords = GetEntityCoords(targetPed)

    for _, playerId in ipairs(GetPlayers()) do
        local pid = tonumber(playerId)
        if pid then
            local playerPed = GetPlayerPed(pid)
            if playerPed and playerPed ~= 0 then
                local playerCoords = GetEntityCoords(playerPed)
                if #(targetCoords - playerCoords) < 100.0 then
                    TriggerClientEvent('police:applySyncedTackle', pid, targetPlayerId, forwardVector)
                end
            end
        end
    end

    Debug(('Synced tackle for player %d'):format(targetPlayerId))
end)

RegisterNetEvent('police:syncArrest', function(targetPlayerId, policeNetId)
    local source = source
    if not source or source == 0 then return end
    if not targetPlayerId then return end

    local targetPed = GetPlayerPed(targetPlayerId)
    if not targetPed or targetPed == 0 then return end

    local targetCoords = GetEntityCoords(targetPed)

    for _, playerId in ipairs(GetPlayers()) do
        local pid = tonumber(playerId)
        if pid then
            local playerPed = GetPlayerPed(pid)
            if playerPed and playerPed ~= 0 then
                local playerCoords = GetEntityCoords(playerPed)
                if #(targetCoords - playerCoords) < 100.0 then
                    TriggerClientEvent('police:applySyncedArrest', pid, targetPlayerId, policeNetId)
                end
            end
        end
    end

    Debug(('Synced arrest for player %d'):format(targetPlayerId))
end)

-- ════════════════════════════════════════════════════════════════
-- COMMANDS
-- ════════════════════════════════════════════════════════════════

lib.addCommand('setwanted', {
    help = 'Set player wanted level',
    params = {
        {name = 'target', type = 'playerId', help = 'Target player ID'},
        {name = 'level', type = 'number', help = 'Wanted level (0-5)'}
    },
    restricted = 'group.admin'
}, function(source, args)
    local level = math.max(0, math.min(5, args.level))
    SetWantedLevel(args.target, level, 'Admin Command')
    local targetName = GetPlayerName(args.target) or 'Unknown'
    lib.notify(source, {
        type = 'success',
        description = ('Set %s wanted level to %d'):format(targetName, level)
    })
end)

lib.addCommand('wanted', {
    help = 'Set wanted level (alias for setwanted)',
    params = {
        {name = 'target', type = 'playerId'},
        {name = 'level', type = 'number'}
    },
    restricted = 'group.admin'
}, function(source, args)
    local level = math.max(0, math.min(5, args.level))
    SetWantedLevel(args.target, level, 'Admin Command')
    local targetName = GetPlayerName(args.target) or 'Unknown'
    lib.notify(source, {
        type = 'success',
        description = ('Set %s wanted level to %d'):format(targetName, level)
    })
end)

lib.addCommand('clearwanted', {
    help = 'Clear player wanted level',
    params = {
        {name = 'target', type = 'playerId', help = 'Target player ID'}
    },
    restricted = 'group.admin'
}, function(source, args)
    SetWantedLevel(args.target, 0, 'Admin Cleared')
    local targetName = GetPlayerName(args.target) or 'Unknown'
    lib.notify(source, {
        type = 'success',
        description = ('Cleared %s wanted level'):format(targetName)
    })
end)

lib.addCommand('jail', {
    help = 'Jail a player',
    params = {
        {name = 'target', type = 'playerId', help = 'Target player ID'},
        {name = 'time', type = 'number', help = 'Jail time in seconds'}
    },
    restricted = 'group.admin'
}, function(source, args)
    local time = math.max(10, args.time)
    JailPlayer(args.target, time)
    local targetName = GetPlayerName(args.target) or 'Unknown'
    lib.notify(source, {
        type = 'success',
        description = ('Jailed %s for %d seconds'):format(targetName, time)
    })
end)

lib.addCommand('unjail', {
    help = 'Release a player from jail',
    params = {
        {name = 'target', type = 'playerId', help = 'Target player ID'}
    },
    restricted = 'group.admin'
}, function(source, args)
    ReleasePlayer(args.target)
    local targetName = GetPlayerName(args.target) or 'Unknown'
    lib.notify(source, {
        type = 'success',
        description = ('Released %s from jail'):format(targetName)
    })
end)

lib.addCommand('arrest', {
    help = 'Arrest a player (Police only)',
    params = {
        {name = 'target', type = 'playerId', help = 'Target player ID'}
    }
}, function(source, args)
    if not IsPolice(source) then
        lib.notify(source, {
            type = 'error',
            description = 'You must be police to use this command'
        })
        return
    end

    local state = GetPlayerState(args.target)
    if state.level <= 0 then
        lib.notify(source, {
            type = 'error',
            description = 'Target has no wanted level'
        })
        return
    end

    if IsExemptFromArrest(args.target) then
        lib.notify(source, {
            type = 'error',
            description = 'Cannot arrest this player (Admin exemption)'
        })
        return
    end

    local jailTime = Config.WantedLevels[state.level].time or 60
    jailTime = math.floor(jailTime * Config.Prison.jailTimeMultiplier)
    JailPlayer(args.target, jailTime)

    local targetName = GetPlayerName(args.target) or 'Unknown'
    lib.notify(source, {
        type = 'success',
        description = ('Arrested %s for %d seconds'):format(targetName, jailTime)
    })
end)

lib.addCommand('checkwanted', {
    help = 'Check player wanted level',
    params = {
        {name = 'target', type = 'playerId', help = 'Target player ID'}
    }
}, function(source, args)
    if not IsPolice(source) and not IsAdmin(source) then
        lib.notify(source, {
            type = 'error',
            description = 'You must be police or admin to use this command'
        })
        return
    end

    local state = GetPlayerState(args.target)
    local targetName = GetPlayerName(args.target) or 'Unknown'

    lib.notify(source, {
        type = 'inform',
        description = ('%s - Wanted: %d ⭐ | Jailed: %s | Crimes: %d'):format(
            targetName,
            state.level,
            state.isJailed and 'Yes' or 'No',
            state.totalCrimes
        ),
        duration = 5000
    })
end)

lib.addCommand('mywanted', {
    help = 'Check your own wanted level'
}, function(source)
    local state = GetPlayerState(source)
    lib.notify(source, {
        type = 'inform',
        description = ('Wanted Level: %d ⭐ | Total Crimes: %d'):format(
            state.level,
            state.totalCrimes
        ),
        duration = 5000
    })
end)

lib.addCommand('crimehistory', {
    help = 'View player crime history',
    params = {
        {name = 'target', type = 'playerId', help = 'Target player ID'}
    },
    restricted = 'group.admin'
}, function(source, args)
    local charid = GetCharId(args.target)
    if not charid then
        lib.notify(source, {type = 'error', description = 'Player not found'})
        return
    end

    local state = GetPlayerState(args.target)
    local targetName = GetPlayerName(args.target) or 'Unknown'

    print('^3========================================^7')
    print(('^2Crime History for %s (ID: %d)^7'):format(targetName, args.target))
    print(('^3Current Wanted: ^7%d ⭐'):format(state.level))
    print(('^3Total Crimes: ^7%d'):format(state.totalCrimes))
    print('^3========================================^7')

    if state.crimeHistory and #state.crimeHistory > 0 then
        print('^6Recent Crimes (In-Memory):^7')
        for i, crime in ipairs(state.crimeHistory) do
            if i <= 10 then
                print(('%d. ^5%s^7 (%s -> %s) - Witnesses: %d'):format(
                    i, crime.type,
                    tostring(crime.wantedBefore),
                    tostring(crime.wantedAfter),
                    crime.data and crime.data.witnesses or 0
                ))
            end
        end
    end

    if MySQL then
        MySQL.Async.fetchAll('SELECT * FROM crime_logs WHERE charid = ? ORDER BY reported_time DESC LIMIT 10', {charid}, function(result)
            if result and #result > 0 then
                print('^6Database Records:^7')
                for i, crime in ipairs(result) do
                    print(('%d. %s - %s - %d witnesses'):format(
                        i, crime.crime_type, crime.reported_time, crime.witness_count
                    ))
                end
                lib.notify(source, {
                    type = 'success',
                    description = ('Found %d crimes - Check console'):format(#result)
                })
            else
                print('^5No database records found^7')
            end
            print('^3========================================^7')
        end)
    else
        print('^3========================================^7')
        lib.notify(source, {type = 'success', description = 'Crime history printed to console'})
    end
end)

lib.addCommand('backup', {
    help = 'Call for backup (Police only)'
}, function(source)
    if not IsPolice(source) then
        lib.notify(source, {type = 'error', description = 'You must be police to use this command'})
        return
    end

    local players = GetPlayers()
    for _, playerId in ipairs(players) do
        local pid = tonumber(playerId)
        if pid and IsPolice(pid) and pid ~= source then
            lib.notify(pid, {
                type = 'warning',
                description = 'Officer requesting backup!',
                icon = 'shield-exclamation',
                duration = 8000
            })
        end
    end

    lib.notify(source, {type = 'success', description = 'Backup called'})
end)

lib.addCommand('panic', {
    help = 'Send panic button (Police only)'
}, function(source)
    if not IsPolice(source) then
        lib.notify(source, {type = 'error', description = 'You must be police to use this command'})
        return
    end

    local coords = GetEntityCoords(GetPlayerPed(source))
    local players = GetPlayers()
    local officerName = GetPlayerName(source)

    for _, playerId in ipairs(players) do
        local pid = tonumber(playerId)
        if pid and IsPolice(pid) then
            lib.notify(pid, {
                type = 'error',
                description = ('🚨 PANIC BUTTON: %s'):format(officerName),
                icon = 'circle-exclamation',
                duration = 10000
            })
            TriggerClientEvent('police:createPanicBlip', pid, coords)
        end
    end
end)

-- ════════════════════════════════════════════════════════════════
-- DEBUG COMMANDS
-- ════════════════════════════════════════════════════════════════

if Config.Debug then
    RegisterCommand('debugpolice_sv', function(source)
        local state = GetPlayerState(source)
        print('=== Police Server Debug ===')
        print('Player:', source)
        print('Wanted Level:', state.level)
        print('Is Jailed:', state.isJailed)
        print('Jail Time:', state.jailTime)
        print('Total Crimes:', state.totalCrimes)
        print('Recent Crimes:', #state.crimeHistory)
        print('Is Admin:', state.isAdmin)
        print('Is Police:', state.isPolice)
        print('Active Players:', #PlayerStates)
        print('=======================')
    end, false)

    RegisterCommand('forcecrime', function(source, args)
        local crimeType = args[1] or 'ASSAULT'
        local coords = GetEntityCoords(GetPlayerPed(source))

        TriggerEvent('police:reportCrime', source, {
            type = crimeType,
            coords = coords,
            witnesses = 1,
            areaType = 'CITY_CENTER',
            severity = 'high',
            policeAlert = true,
            level = Config.CrimeTypes[crimeType] and Config.CrimeTypes[crimeType].level or 1
        })

        print('^2[Police]^7 Forced crime:', crimeType)
    end, false)
end

-- ════════════════════════════════════════════════════════════════
-- PLAYER HANDLERS
-- ════════════════════════════════════════════════════════════════

AddEventHandler('playerDropped', function()
    local source = source
    if not source or source == 0 then return end

    if PlayerStates[source] then
        local state = PlayerStates[source]
        -- ✅ FIX #9: charid aus gecachtem State lesen, NICHT GetCharId() aufrufen.
        local charid = state.charid or GetCharId(source)
        if charid and MySQL then

                source, tostring(charid), tostring(state.isJailed), tostring(state.jailTime)
            ))
            if state.isJailed and state.jailTime > 0 then
                -- ✅ FIX #8: Beim Disconnect sofort aktuelle jail_time + neuen jail_start speichern.
                MySQL.Async.execute([[
                    UPDATE police_records
                    SET
                        jail_time    = ?,
                        jail_start   = NOW(),
                        wanted_level = ?,
                        total_crimes = ?,
                        crimes_data  = ?
                    WHERE charid = ?
                ]], {
                    state.jailTime,
                    state.level,
                    state.totalCrimes,
                    json.encode(state.crimes),
                    charid,
                })
                Debug(('playerDropped: saved jail_time=%ds for charid=%s'):format(
                    state.jailTime, tostring(charid)
                ))
            else
                MySQL.Async.execute([[
                    INSERT INTO police_records (charid, wanted_level, total_crimes, crimes_data)
                    VALUES (?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE
                        wanted_level = VALUES(wanted_level),
                        total_crimes = VALUES(total_crimes),
                        crimes_data  = VALUES(crimes_data)
                ]], {
                    charid,
                    state.level,
                    state.totalCrimes,
                    json.encode(state.crimes),
                })
            end
        end
        
        -- ✅ RDE SYNC PATTERN: Broadcast player disconnect to all clients
        TriggerClientEvent('police:playerDisconnected', -1, source)
        
        PlayerStates[source] = nil
    end
end)

-- ════════════════════════════════════════════════════════════════
-- ✅ FIX #1 + FIX #5 + FIX #11: ox:playerLoaded Handler
--
-- FIX #11: Race Condition beim Reconnect mit Jail behoben.
--
-- Das Problem mit FIX #10 (nur via checkJailStatus-Callback):
--   Der Client ruft police:checkJailStatus in InitializeSystem() auf,
--   ABER InitializeSystem() startet schon nach 2s (via onResourceStart).
--   Die MySQL-Query in ox:playerLoaded braucht typisch 50-200ms PLUS
--   den Wait(2000) auf dem Server. Der Client feuert seinen Callback
--   also bevor PlayerStates[source] befüllt ist → bekommt {jailed=false}.
--
-- Lösung (dualer Restore-Pfad):
--   1. Server sendet police:systemReady (Trigger für Client-Init)
--   2. Server sendet police:teleportToJail nach 5s Delay
--      (MySQL ist dann garantiert fertig, Client ist initialisiert)
--   3. Client-seitiger jailRestoreHandled-Flag verhindert Doppel-Restore,
--      falls der checkJailStatus-Callback diesmal doch rechtzeitig war.
-- ════════════════════════════════════════════════════════════════
AddEventHandler('ox:playerLoaded', function(playerId, userId, charId)
    local source = playerId

    if not source or source == 0 then return end

    CreateThread(function()
        Wait(2000)

        -- ✅ FIX #23: charId-Parameter von ox:playerLoaded kann nil/0 sein je nach ox_core-Version.
        -- Stattdessen: Ox.GetPlayer() mit Retry-Loop — das ist immer zuverlässig.
        local player = nil
        local resolvedCharId = charId  -- Fallback: Parameter
        for i = 1, 10 do
            player = Ox.GetPlayer(source)
            if player then
                resolvedCharId = player.charid or player.charId or charId
                break
            end
            Wait(500)
        end

            source, tostring(charId), tostring(resolvedCharId), tostring(player ~= nil)
        ))

        if not resolvedCharId or resolvedCharId == 0 then
            TriggerClientEvent('police:systemReady', source, {
                wantedLevel = 0,
                isJailed    = false,
                jailTime    = 0,
                jailCell    = 1,
            })
            return
        end

        -- charId für diesen Aufruf nutzen
        charId = resolvedCharId

        local state = GetPlayerState(source)
        state.initialized = false
        -- ✅ FIX #9: charid sofort cachen
        state.charid = charId

        if MySQL then
            -- ✅ FIX #8b: TIMESTAMPDIFF direkt in MySQL berechnen
            -- ✅ FIX #23: jail_start Spalte ist DATE (nicht DATETIME) → TIMESTAMPDIFF
            -- liefert die Sekunden seit Mitternacht, nicht seit dem echten Jail-Zeitpunkt.
            -- Lösung: jail_start als UNIX-Timestamp in einer zweiten Spalte (jail_start_unix)
            -- ist der sauberste Fix — aber ohne Schema-Änderung:
            -- Wir lesen jail_time direkt und speichern beim Disconnect den aktuellen Wert.
            -- Die "offline Zeit abziehen"-Logik wird in Lua mit os.time() gemacht,
            -- sofern jail_start_unix vorhanden ist (neue Spalte, optional).
            MySQL.Async.fetchAll([[
                SELECT
                    *,
                    jail_time AS jail_remaining_calc,
                    UNIX_TIMESTAMP(jail_start) AS jail_start_unix
                FROM police_records
                WHERE charid = ?
            ]], {charId}, function(result)
                if result and result[1] then
                    local data = result[1]
                        tostring(data.is_jailed), tostring(data.jail_time), tostring(data.jail_remaining_calc), tostring(data.charid)
                    ))

                    state.level = data.wanted_level or 0
                    state.totalCrimes = data.total_crimes or 0

                    if data.crimes_data then
                        local ok, decoded = pcall(json.decode, data.crimes_data)
                        state.crimes = ok and decoded or {}
                    end

                    local jailRemaining = 0
                    local jailCell = data.jail_cell or 1

                    -- ✅ FIX #24: MySQL gibt TINYINT je nach Treiber als boolean ODER als Zahl zurück.
                    -- `== 1` schlägt fehl wenn der Treiber `true` liefert. Truthy-Check löst beides.
                    if data.is_jailed and data.is_jailed ~= 0 and data.jail_time and data.jail_time > 0 then
                        -- ✅ FIX #24: jail_time aus DB direkt als remaining nutzen.
                        -- playerDropped speichert beim Disconnect den aktuellen Countdown-Stand.
                        -- Kein elapsed-Abzug nötig — der Wert in der DB IST bereits die Restzeit.
                        -- (Server-Restart-Szenario: Zeit läuft nicht ab während Server offline ist,
                        --  das ist bewusstes Design — Spieler werden nicht bestraft für Server-Restarts.)
                        local remaining = tonumber(data.jail_time) or 0

                        Debug(('Jail restore check: jail_time=%d, remaining=%d'):format(
                            data.jail_time, remaining
                        ))

                        if remaining > 0 then
                            state.isJailed = true
                            state.jailTime = remaining
                            state.jailCell = jailCell
                            jailRemaining  = remaining

                            if data.saved_inventory then
                                local ok, decoded = pcall(json.decode, data.saved_inventory)
                                if ok then state.savedInventory = decoded end
                            end

                            -- DB sofort mit korrekter remaining Zeit updaten
                            MySQL.Async.execute([[
                                UPDATE police_records
                                SET jail_time = ?, jail_start = NOW()
                                WHERE charid = ?
                            ]], { remaining, charId })

                            Debug(('Jail restored for player %d: %ds remaining in cell %d'):format(
                                source, remaining, jailCell
                            ))
                        else
                            -- Zeit abgelaufen während offline → freilassen
                            state.isJailed = false
                            state.jailTime = 0

                            if data.saved_inventory then
                                local ok, decoded = pcall(json.decode, data.saved_inventory)
                                if ok then
                                    state.savedInventory = decoded
                                    -- ✅ FIX #12: Delay RestoreInventory — ox_inventory braucht
                                    -- Zeit um das Player-Inventar zu laden. Nach nur 2s Wait
                                    -- ist ox_inventory oft noch nicht bereit → Items gehen verloren.
                                    -- DB cleanup passiert NACH dem Restore, nicht vorher!
                                    local _source = source
                                    local _charId = charId
                                    SetTimeout(8000, function()
                                        if _source and _source > 0 then
                                            local player = Ox.GetPlayer(_source)
                                            if player then
                                                RestoreInventory(_source)
                                                Debug(('Delayed inventory restore for player %d (jail expired offline)'):format(_source))
                                            else
                                                Debug(('Delayed inventory restore FAILED — player %d no longer online'):format(_source))
                                            end
                                        end
                                        -- ✅ DB cleanup NACH restore
                                        MySQL.Async.execute([[
                                            UPDATE police_records
                                            SET is_jailed = 0, jail_time = 0, jail_start = NULL, saved_inventory = NULL
                                            WHERE charid = ?
                                        ]], {_charId})
                                    end)
                                end
                            else
                                -- Kein saved_inventory → nur DB cleanen
                                MySQL.Async.execute([[
                                    UPDATE police_records
                                    SET is_jailed = 0, jail_time = 0, jail_start = NULL
                                    WHERE charid = ?
                                ]], {charId})
                            end

                            Debug(('Jail time expired while offline for player %d'):format(source))
                        end
                    end

                    state.initialized = true
                    SyncPlayerState(source)

                    -- ✅ Sende systemReady - Client benutzt jetzt die Daten direkt!
                        tostring(state.isJailed), state.jailTime or 0
                    ))
                    TriggerClientEvent('police:systemReady', source, {
                        wantedLevel = state.level    or 0,
                        isJailed    = state.isJailed or false,
                        jailTime    = state.jailTime or 0,
                        jailCell    = state.jailCell or 1,
                    })
                    
                    -- ✅ RDE SYNC PATTERN: Send all player states to this joining player
                    SetTimeout(1000, function()
                        SyncAllPlayers(source)
                    end)
                    
                    -- ✅ No delayed teleportToJail — player already spawns in jail via ox_core
                    -- Timer is started directly by client via police:systemReady data

                else
                    -- Keine DB-Einträge → frischer Spieler
                    state.initialized = true
                    SyncPlayerState(source)

                    TriggerClientEvent('police:systemReady', source, {
                        wantedLevel = 0,
                        isJailed    = false,
                        jailTime    = 0,
                        jailCell    = 1,
                    })
                    
                    -- ✅ RDE SYNC PATTERN: Send all player states to this joining player
                    SetTimeout(1000, function()
                        SyncAllPlayers(source)
                    end)
                    
                    -- ✅ Kein delayed teleportToJail - Client macht eigenen Check
                end

                Debug(('Player %d loaded — Level: %d, Jailed: %s, JailTime: %d'):format(
                    source,
                    state.level,
                    tostring(state.isJailed),
                    state.jailTime or 0
                ))
            end)
        else
            state.initialized = true
            SyncPlayerState(source)

            TriggerClientEvent('police:systemReady', source, {
                wantedLevel = 0,
                isJailed    = false,
                jailTime    = 0,
                jailCell    = 1,
            })
            
            -- ✅ RDE SYNC PATTERN: Send all player states to this joining player
            SetTimeout(1000, function()
                SyncAllPlayers(source)
            end)
            
            -- ✅ Kein delayed teleportToJail - Client macht eigenen Check
        end
    end)
end)

-- ════════════════════════════════════════════════════════════════
-- JAIL TIMER (Server-seitig — Authoritative)
-- ✅ FIX #17: Type-Checks + pcall damit ein einzelner kaputter State
-- niemals den Thread für ALLE Spieler abschießt.
-- ════════════════════════════════════════════════════════════════

CreateThread(function()
    while true do
        Wait(1000)
        for source, state in pairs(PlayerStates) do
            local ok, err = pcall(function()
                if state and state.isJailed
                    and type(state.jailTime) == 'number'
                    and state.jailTime > 0
                then
                    state.jailTime = state.jailTime - 1

                    if state.jailTime % 5 == 0 then
                        -- ✅ RDE SYNC PATTERN: Broadcast every 5 seconds
                        SyncPlayerState(source)
                        TriggerClientEvent('police:updateJailTime', source, state.jailTime)

                        -- ✅ FIX #8: DB-Update alle 10s
                        if MySQL and state.jailTime % 10 == 0 then
                            local charid = state.charid or GetCharId(source)
                            if charid then
                                MySQL.Async.execute([[
                                    UPDATE police_records
                                    SET jail_time = ?, jail_start = NOW()
                                    WHERE charid = ?
                                ]], {
                                    state.jailTime, charid
                                })
                            end
                        end
                    end

                    if state.jailTime <= 0 then
                        ReleasePlayer(source)
                    end
                end
            end)
            if not ok then
                Debug(('Jail timer error for player %s: %s'):format(tostring(source), tostring(err)))
            end
        end
    end
end)

-- ════════════════════════════════════════════════════════════════
-- DATABASE SETUP
-- ════════════════════════════════════════════════════════════════

if MySQL then
    MySQL.ready(function()
        MySQL.Async.execute([[
            CREATE TABLE IF NOT EXISTS `police_records` (
                `charid` int(11) NOT NULL,
                `wanted_level` int(11) DEFAULT 0,
                `total_crimes` int(11) DEFAULT 0,
                `is_jailed` tinyint(1) DEFAULT 0,
                `jail_time` int(11) DEFAULT 0,
                `jail_cell` int(11) DEFAULT 1,
                `jail_start` timestamp NULL,
                `saved_inventory` LONGTEXT,
                `last_arrest` timestamp NULL,
                `crimes_data` LONGTEXT,
                PRIMARY KEY (`charid`),
                INDEX `idx_wanted` (`wanted_level`),
                INDEX `idx_jailed` (`is_jailed`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        ]])
        MySQL.Async.execute([[
            CREATE TABLE IF NOT EXISTS `crime_logs` (
                `id` int(11) NOT NULL AUTO_INCREMENT,
                `charid` int(11) NOT NULL,
                `crime_type` varchar(50) NOT NULL,
                `area_type` varchar(50) DEFAULT 'UNKNOWN',
                `witness_count` int(11) DEFAULT 0,
                `crime_data` LONGTEXT,
                `reported_time` timestamp DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                INDEX `idx_charid` (`charid`),
                INDEX `idx_crime_type` (`crime_type`),
                INDEX `idx_reported_time` (`reported_time`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        ]])
        print('^2[AIPD | Server]^7 Database tables created/verified')
    end)
end

-- ════════════════════════════════════════════════════════════════
-- CLEANUP
-- ════════════════════════════════════════════════════════════════

CreateThread(function()
    while true do
        Wait(300000)
        local removed = 0
        for source in pairs(PlayerStates) do
            if not GetPlayerName(source) then
                -- ✅ FIX #16: State sichern bevor wir löschen (falls playerDropped nicht feuerte)
                local state = PlayerStates[source]
                if state and state.charid and MySQL then
                    if state.isJailed and state.jailTime > 0 then
                        MySQL.Async.execute([[
                            UPDATE police_records
                            SET jail_time = ?, jail_start = NOW(), wanted_level = ?, total_crimes = ?
                            WHERE charid = ?
                        ]], { state.jailTime, state.level, state.totalCrimes, state.charid })
                    end
                end
                PlayerStates[source] = nil
                removed = removed + 1
            end
        end
        if removed > 0 then
            Debug(('Cleanup: removed %d stale player states'):format(removed))
        end
    end
end)

-- ════════════════════════════════════════════════════════════════
-- EXPORTS
-- ════════════════════════════════════════════════════════════════

exports('SetWantedLevel', SetWantedLevel)
exports('GetWantedLevel', function(source) return GetPlayerState(source).level end)
exports('JailPlayer', JailPlayer)
exports('ReleasePlayer', ReleasePlayer)
exports('IsPolice', IsPolice)
exports('IsAdmin', IsAdmin)
exports('IsExemptFromWanted', IsExemptFromWanted)
exports('IsExemptFromArrest', IsExemptFromArrest)
exports('IsExemptFromJail', IsExemptFromJail)
exports('GetPlayerState', GetPlayerState)

-- ════════════════════════════════════════════════════════════════
-- STARTUP
-- ════════════════════════════════════════════════════════════════

print('^2════════════════════════════════════════════════^0')
-- ✅ FIX #23: jail_start Spalte auf DATETIME upgraden falls noch DATE
-- Einmalig beim Serverstart — schadet nicht wenn bereits DATETIME
if MySQL then
    MySQL.Async.execute([[
        ALTER TABLE police_records
        MODIFY COLUMN jail_start DATETIME NULL DEFAULT NULL
    ]], {}, function()
        print('^2[AIPD | Server]^0 ✅ FIX #23: jail_start Spalte ist jetzt DATETIME')
    end)
end

print('^2[AIPD | Server]^0 ✓ NEXT-GEN Edition initialized')
print('^2[AIPD | Server]^0 Framework: ox_core')
print('^2[AIPD | Server]^0 Statebag Sync: ' .. tostring(Config.UseStateBags))
print('^2[AIPD | Server]^0 🔥 Additive Wanted System: ENABLED')
print('^2[AIPD | Server]^0 🔥 Decay System: ENABLED')
print('^2[AIPD | Server]^0 Admin Exemption: ' .. tostring(Config.AdminSettings.exemptFromWanted))
print('^2[AIPD | Server]^0 ✅ FIX #5: Jail restore timing — teleportToJail nach systemReady')
print('^2[AIPD | Server]^0 ✅ FIX #8: Jail persist on disconnect — sofortiger DB-Save')
print('^2[AIPD | Server]^0 ✅ FIX #8b: TIMESTAMPDIFF in MySQL — kein Timezone-Bug mehr')
print('^2[AIPD | Server]^0 ✅ FIX #9: charid cached in State — playerDropped save immer zuverlässig')
print('^2[AIPD | Server]^0 ✅ FIX #11: Dual restore path — teleportToJail nach 5s Delay als Fallback')
print('^2[AIPD | Server]^0 🐉 RDE SYNC PATTERN: Broadcast to ALL players with rate limiting')
print('^2[AIPD | Server]^0 🐉 RDE SYNC PATTERN: Initial sync for late-joining players')
print('^2[AIPD | Server]^0 🐉 RDE SYNC PATTERN: Server is authority - state always synced')
print('^2[AIPD | Server]^0 Version: 1.0.0-alpha')
print('^2════════════════════════════════════════════════^0')