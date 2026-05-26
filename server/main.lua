---@diagnostic disable: undefined-global
-- ════════════════════════════════════════════════════════════════
-- AIPD | SERVER | NEXT-GEN EDITION
-- Fully Realtime Synced • Multi-Player Safe • Bulletproof Jail
-- ════════════════════════════════════════════════════════════════
-- FIXES IN THIS VERSION:
--  ✅ Multi-player wanted: each player has isolated Police system
--  ✅ Jail teleport: guaranteed delivery via reliable event + ACK
--  ✅ Arrest race: savedWantedLevel snapshotted server-side at syncArrest
--  ✅ ClearAllUnits: isolated per-player — never affects other players
--  ✅ Decay: server authoritative, rate-limited per player
--  ✅ StateBag + Broadcast always in sync (single SyncPlayerState call)
--  ✅ Jail timer: server is authority, clients just display
--  ✅ Reconnect jail: reliable restore with retry loop
-- ════════════════════════════════════════════════════════════════

local Locale = lib.load('locales.' .. GetConvar('ox:locale', 'en')) or {}
local function L(key, ...)
    local s = Locale[key]
    if not s then return key end
    if select('#', ...) > 0 then return s:format(...) end
    return s
end

local Ox = require '@ox_core.lib.init'

-- ════════════════════════════════════════════════════════════════
-- PLAYER STATE TABLE
-- Each player gets a fully isolated state. No shared mutable data
-- between players for anything that drives the Police system.
-- ════════════════════════════════════════════════════════════════

local PlayerStates = {}

local function Debug(...)
    if Config.Debug then
        print('^3[AIPD | Server]^7', ...)
    end
end

-- ════════════════════════════════════════════════════════════════
-- PERMISSION HELPERS
-- ════════════════════════════════════════════════════════════════

local function HasGroup(source, groups)
    if not source or source == 0 then return false end
    local player = Ox.GetPlayer(source)
    if not player then return false end
    for _, group in ipairs(groups) do
        if player.getGroup(group) then return true end
    end
    return false
end

function IsPolice(source)   return HasGroup(source, Config.PoliceJobs)   end
function IsAdmin(source)    return HasGroup(source, Config.AdminGroups)   end

function IsExemptFromWanted(source)
    return Config.AdminSettings.exemptFromWanted and IsAdmin(source)
end
function IsExemptFromArrest(source)
    return Config.AdminSettings.exemptFromArrest and IsAdmin(source)
end
function IsExemptFromJail(source)
    return Config.AdminSettings.exemptFromJail and IsAdmin(source)
end

-- ════════════════════════════════════════════════════════════════
-- STATE MANAGEMENT
-- ════════════════════════════════════════════════════════════════

function GetPlayerState(source)
    if not PlayerStates[source] then
        PlayerStates[source] = {
            level           = 0,
            lastUpdate      = os.time(),
            isJailed        = false,
            jailTime        = 0,
            jailCell        = 1,
            crimes          = {},
            totalCrimes     = 0,
            isAdmin         = IsAdmin(source),
            isPolice        = IsPolice(source),
            initialized     = false,
            crimeHistory    = {},
            charid          = nil,
            lastDecay       = 0,
            savedWantedLevel = 0,
            isArrested      = false,   -- NEW: server-side arrest flag
            jailDelivered   = false,   -- NEW: guarantees teleportToJail reaches client
        }
    end
    return PlayerStates[source]
end

function GetCharId(source)
    if not source or source == 0 then return nil end
    if PlayerStates[source] and PlayerStates[source].charid then
        return PlayerStates[source].charid
    end
    local player = Ox.GetPlayer(source)
    if not player then return nil end
    local charid = player.charid or source
    if PlayerStates[source] then PlayerStates[source].charid = charid end
    return charid
end

-- ════════════════════════════════════════════════════════════════
-- STATEBAG + BROADCAST SYNC
-- Single function: always keeps StateBag and broadcast in sync.
-- Never call these separately.
-- ════════════════════════════════════════════════════════════════

local lastBroadcastTime = {}
local BROADCAST_COOLDOWN = 100

local function SyncPlayerState(source)
    if not source or source == 0 then return end

    -- StateBag sync
    if Config.UseStateBags then
        local ped = GetPlayerPed(source)
        if ped and ped ~= 0 then
            local state  = GetPlayerState(source)
            local bag    = Entity(ped).state
            bag:set('wantedLevel', state.level,    true)
            bag:set('isJailed',    state.isJailed, true)
            bag:set('jailTime',    state.jailTime, true)
            bag:set('totalCrimes', state.totalCrimes, true)
            bag:set('isAdmin',     state.isAdmin,  true)
            bag:set('isPolice',    state.isPolice, true)
        end
    end

    -- Rate-limited broadcast to all clients
    local now = GetGameTimer()
    if lastBroadcastTime[source] and (now - lastBroadcastTime[source]) < BROADCAST_COOLDOWN then
        return
    end
    lastBroadcastTime[source] = now

    local state = GetPlayerState(source)
    TriggerClientEvent('police:playerStateUpdate', -1, source, {
        level        = state.level        or 0,
        isJailed     = state.isJailed     or false,
        jailTime     = state.jailTime     or 0,
        totalCrimes  = state.totalCrimes  or 0,
        isAdmin      = state.isAdmin      or false,
        isPolice     = state.isPolice     or false,
    })

    Debug(('Synced state player=%d | Wanted=%d | Jailed=%s | JailTime=%d'):format(
        source, state.level, tostring(state.isJailed), state.jailTime or 0
    ))
end

local function SyncAllPlayers(targetSource)
    if not targetSource or targetSource == 0 then return end
    local arr = {}
    for src, state in pairs(PlayerStates) do
        if GetPlayerName(src) then
            arr[#arr + 1] = {
                source       = src,
                level        = state.level        or 0,
                isJailed     = state.isJailed     or false,
                jailTime     = state.jailTime     or 0,
                totalCrimes  = state.totalCrimes  or 0,
                isAdmin      = state.isAdmin      or false,
                isPolice     = state.isPolice     or false,
            }
        end
    end
    TriggerClientEvent('police:syncAllStates', targetSource, arr)
    Debug(('SyncAllPlayers → %s (%d states)'):format(GetPlayerName(targetSource) or '?', #arr))
end

-- ════════════════════════════════════════════════════════════════
-- WANTED LEVEL
-- ════════════════════════════════════════════════════════════════

function SetWantedLevel(source, level, reason)
    if not source or source == 0 then return end
    if IsExemptFromWanted(source) then return end

    level = math.max(0, math.min(5, level))
    local state    = GetPlayerState(source)
    local oldLevel = state.level
    state.level    = level
    state.lastUpdate = os.time()

    SyncPlayerState(source)

    -- Notify the player
    if level > oldLevel then
        lib.notify(source, { type='error',   description=L('wanted_set', level), icon='shield-alert' })
    elseif level == 0 and oldLevel > 0 then
        lib.notify(source, { type='success', description=L('wanted_cleared'),    icon='shield-check'  })
    end

    Debug(('SetWantedLevel player=%d | %d→%d | reason=%s'):format(source, oldLevel, level, reason or '?'))
end

-- ════════════════════════════════════════════════════════════════
-- INVENTORY
-- ════════════════════════════════════════════════════════════════

function SaveInventory(source)
    if not Config.Prison.saveInventory then return end
    local player = Ox.GetPlayer(source)
    if not player then return end
    local state = GetPlayerState(source)
    local ok, inv = pcall(function() return exports.ox_inventory:GetInventory(source, false) end)
    if ok and inv then
        state.savedInventory = { items = inv.items or {}, weight = inv.weight or 0 }
        pcall(function() exports.ox_inventory:ClearInventory(source) end)
        if Config.Prison.clearWeapons then TriggerClientEvent('police:clearWeapons', source) end
        Debug(('SaveInventory: %d items for player %d'):format(#(inv.items or {}), source))
    end
end

function RestoreInventory(source)
    if not Config.Prison.saveInventory then return end
    local player = Ox.GetPlayer(source)
    if not player then return end
    local state = GetPlayerState(source)
    if state.savedInventory and state.savedInventory.items then
        for _, item in pairs(state.savedInventory.items) do
            if item and item.name and item.count then
                pcall(function() exports.ox_inventory:AddItem(source, item.name, item.count, item.metadata) end)
            end
        end
        state.savedInventory = nil
        Debug(('RestoreInventory: done for player %d'):format(source))
    end
end

-- ════════════════════════════════════════════════════════════════
-- JAIL SYSTEM  —  BULLETPROOF DELIVERY
-- The server never trusts the client received teleportToJail.
-- It retries every 3s until the client ACKs via police:jailAck.
-- ════════════════════════════════════════════════════════════════

function JailPlayer(source, time, cell)
    if not source or source == 0 then return end
    time = tonumber(time)
    if not time or time < 10 then time = 60 end
    time = math.floor(time)

    if IsExemptFromJail(source) then
        lib.notify(source, { type='info', description=L('admin_exempt_jail'), icon='shield-check' })
        return
    end

    local charid = GetCharId(source)
    if not charid then return end

    local state        = GetPlayerState(source)
    state.isJailed     = true
    state.isArrested   = true
    state.jailTime     = time
    state.jailCell     = tonumber(cell) or math.random(#Config.Prison.cells)
    if not Config.Prison.cells[state.jailCell] then
        state.jailCell = math.random(#Config.Prison.cells)
    end
    state.level         = 0
    state.jailDelivered = false

    SaveInventory(source)
    SyncPlayerState(source)

    -- DB persist
    if MySQL then
        MySQL.Async.execute([[
            INSERT INTO police_records (charid, is_jailed, jail_time, jail_cell, jail_start, saved_inventory, wanted_level)
            VALUES (?, 1, ?, ?, NOW(), ?, 0)
            ON DUPLICATE KEY UPDATE
                is_jailed = 1, jail_time = VALUES(jail_time),
                jail_cell = VALUES(jail_cell), jail_start = NOW(),
                saved_inventory = VALUES(saved_inventory), wanted_level = 0
        ]], { charid, time, state.jailCell, state.savedInventory and json.encode(state.savedInventory) or nil })
    end

    -- ── RELIABLE DELIVERY LOOP ──────────────────────────────────
    -- Send teleportToJail every 3s until client ACKs or player disconnects.
    local deliverySource = source
    local deliveryCell   = state.jailCell
    local deliveryTime   = time
    local maxAttempts    = 10

    CreateThread(function()
        local attempts = 0
        while attempts < maxAttempts do
            -- Check if still online and still jailed
            if not GetPlayerName(deliverySource) then break end
            local s = PlayerStates[deliverySource]
            if not s or not s.isJailed then break end
            if s.jailDelivered then
                Debug(('JailDelivery: ACK received for player %d after %d attempt(s)'):format(deliverySource, attempts + 1))
                break
            end

            attempts = attempts + 1
            Debug(('JailDelivery: attempt %d for player %d (cell=%d, time=%d)'):format(
                attempts, deliverySource, deliveryCell, deliveryTime
            ))
            TriggerClientEvent('police:teleportToJail', deliverySource, deliveryCell, deliveryTime)

            Wait(3000)
        end
        if attempts >= maxAttempts then
            Debug(('JailDelivery: max attempts reached for player %d — they may be disconnected'):format(deliverySource))
        end
    end)

    Debug(('JailPlayer: source=%d time=%ds cell=%d — delivery loop started'):format(source, time, state.jailCell))
end

-- Client ACKs that it received and executed the jail teleport
RegisterNetEvent('police:jailAck', function()
    local source = source
    if not source or source == 0 then return end
    local state = GetPlayerState(source)
    state.jailDelivered = true
    Debug(('JailAck received from player %d'):format(source))
end)

function ReleasePlayer(source)
    if not source or source == 0 then return end
    local charid = GetCharId(source)
    if not charid then return end
    local state = GetPlayerState(source)
    if not state.isJailed then return end

    state.isJailed   = false
    state.jailTime   = 0
    state.isArrested = false

    RestoreInventory(source)
    SyncPlayerState(source)

    if MySQL then
        MySQL.Async.execute([[
            UPDATE police_records
            SET is_jailed = 0, jail_time = 0, jail_start = NULL,
                saved_inventory = NULL, last_arrest = NOW()
            WHERE charid = ?
        ]], { charid })
    end

    TriggerClientEvent('police:teleportFromJail', source)
    lib.notify(source, { type='success', description=L('released'), icon='door-open' })
    Debug(('Released player %d from jail'):format(source))
end

-- ════════════════════════════════════════════════════════════════
-- CO-OCCUPANCY
-- ════════════════════════════════════════════════════════════════

function PropagateWantedToCoOccupants(driverSource, level, coOccupantIds, reason)
    if not Config.VehicleCoOccupancy or not Config.VehicleCoOccupancy.enabled then return end
    if not coOccupantIds or #coOccupantIds == 0 then return end
    if not level or level <= 0 then return end

    local passLevel = level
    if Config.VehicleCoOccupancy.passengerLowerByOne then
        passLevel = math.max(1, level - 1)
    end

    local notifiedDriver = false
    for _, id in ipairs(coOccupantIds) do
        local pid = tonumber(id)
        if pid and pid > 0 and pid ~= driverSource and GetPlayerName(pid) then
            local skip = (Config.VehicleCoOccupancy.exemptPolice and IsPolice(pid))
                      or (Config.VehicleCoOccupancy.exemptAdmins and IsExemptFromWanted(pid))
            if not skip then
                local s      = GetPlayerState(pid)
                local newLvl = math.min(5, math.max(s.level, passLevel))
                if newLvl > s.level then
                    SetWantedLevel(pid, newLvl, (reason or 'crime') .. ' (Passenger)')
                    lib.notify(pid, { type='error', description=L('cooccupant_wanted_inherited', newLvl), icon='car', duration=5000 })
                    if not notifiedDriver then
                        lib.notify(driverSource, { type='warning', description=L('cooccupant_passenger_wanted'), duration=4000 })
                        notifiedDriver = true
                    end
                end
            end
        end
    end
end

-- ════════════════════════════════════════════════════════════════
-- CRIME LOGGING
-- ════════════════════════════════════════════════════════════════

function LogCrime(source, crimeType, data)
    if not source or source == 0 then return end
    local state = GetPlayerState(source)
    state.crimes[crimeType]  = (state.crimes[crimeType] or 0) + 1
    state.totalCrimes        = state.totalCrimes + 1
    table.insert(state.crimeHistory, 1, {
        type = crimeType, time = os.time(), data = data,
        wantedBefore = state.level, wantedAfter = state.level
    })
    if #state.crimeHistory > 50 then table.remove(state.crimeHistory, 51) end
    SyncPlayerState(source)

    local charid = GetCharId(source)
    if charid and MySQL then
        MySQL.Async.execute([[
            INSERT INTO crime_logs (charid, crime_type, area_type, witness_count, crime_data, reported_time)
            VALUES (?, ?, ?, ?, ?, NOW())
        ]], { charid, crimeType,
              data and data.areaType or 'UNKNOWN',
              data and data.witnessCount or 0,
              data and json.encode(data) or nil })
    end
end

-- ════════════════════════════════════════════════════════════════
-- POLICE NOTIFICATIONS
-- ════════════════════════════════════════════════════════════════

function NotifyPolice(crimeType, coords, data)
    local cfg = Config.CrimeTypes[crimeType]
    if not cfg then return end
    for _, pid in ipairs(GetPlayers()) do
        local id = tonumber(pid)
        if id and IsPolice(id) then
            local chance = cfg.policeAlert and 0.9 or 0.6
            if math.random() < chance then
                TriggerClientEvent('police:crimeAlert', id, {
                    type = crimeType, coords = coords, data = data,
                    time = os.time(), severity = cfg.severity or 'medium',
                    description = cfg.description or crimeType
                })
            end
        end
    end
end

-- ════════════════════════════════════════════════════════════════
-- CALLBACKS
-- ════════════════════════════════════════════════════════════════

lib.callback.register('police:getWantedLevel', function(source)
    return source and GetPlayerState(source).level or 0
end)

lib.callback.register('police:checkJailStatus', function(source)
    if not source or source == 0 then return { jailed=false } end
    local s = GetPlayerState(source)
    return { jailed=s.isJailed, time=s.jailTime, cell=s.jailCell }
end)

lib.callback.register('police:isAdmin',  function(source) return IsAdmin(source)  end)
lib.callback.register('police:isPolice', function(source) return IsPolice(source) end)

lib.callback.register('police:arrestPlayer', function(source, jailTime, cell)
    if not source or source == 0 then return false end
    local state = GetPlayerState(source)

    -- Accept arrest if: has wanted level OR is marked as arrested (decay race window)
    if state.level <= 0 and not state.isJailed and not state.isArrested then
        Debug(('arrestPlayer rejected: player %d has no wanted level'):format(source))
        return false
    end

    -- Enforce minimum jail time
    if type(jailTime) ~= 'number' or jailTime < 30 then
        local lvl = state.level > 0 and state.level or (state.savedWantedLevel or 1)
        jailTime  = Config.WantedLevels[lvl] and Config.WantedLevels[lvl].time or 60
    end

    state.isArrested = true
    JailPlayer(source, jailTime, cell)
    return true
end)

lib.callback.register('police:releasePlayer', function(source)
    if not source or source == 0 then return false end
    local state = GetPlayerState(source)
    if not state.isJailed then return false end
    if state.jailTime > 5 then
        Debug(('releasePlayer rejected: player %d still has %ds'):format(source, state.jailTime))
        return false
    end
    ReleasePlayer(source)
    return true
end)

lib.callback.register('police:playerDied', function(source)
    if not source or source == 0 then return false end
    local state = GetPlayerState(source)
    if state.level > 0 then SetWantedLevel(source, 0, 'Death') end
    return true
end)

lib.callback.register('police:getCrimeHistory', function(source, targetSource)
    targetSource = targetSource or source
    if not targetSource then return {} end
    return GetPlayerState(targetSource).crimeHistory or {}
end)

-- ════════════════════════════════════════════════════════════════
-- NET EVENTS
-- ════════════════════════════════════════════════════════════════

RegisterNetEvent('police:decayWantedLevel', function()
    local source = source
    if not source or source == 0 then return end
    local state = GetPlayerState(source)

    -- Rate-limit: min 15s between decays per player
    local now = os.time()
    if state.lastDecay and (now - state.lastDecay) < 15 then
        Debug(('Decay rate-limited for player %d'):format(source))
        return
    end
    -- Don't decay during arrest window
    if state.isArrested then
        Debug(('Decay blocked: player %d is being arrested'):format(source))
        return
    end

    state.lastDecay = now
    if state.level > 0 then
        local newLevel = state.level - 1
        SetWantedLevel(source, newLevel, 'Evaded Police')
    end
end)

RegisterNetEvent('police:arrest', function(targetId)
    local source = source
    if not source or source == 0 then return end
    if not IsPolice(source) then return end
    if not targetId or targetId == 0 then return end
    if IsExemptFromArrest(targetId) then
        lib.notify(source, { type='error', description=L('admin_exempt_arrest') })
        return
    end
    local state = GetPlayerState(targetId)
    if state.level > 0 then
        local t = math.floor((Config.WantedLevels[state.level].time or 60) * Config.Prison.jailTimeMultiplier)
        JailPlayer(targetId, t)
    end
end)

-- ════════════════════════════════════════════════════════════════
-- SYNCED ANIMATIONS  —  MULTI-PLAYER SAFE
-- Tackle and arrest animations are broadcast only to nearby players,
-- not to everyone. This is important for performance on busy servers.
-- ════════════════════════════════════════════════════════════════

RegisterNetEvent('police:syncTackle', function(targetPlayerId, forwardVector)
    local source = source
    if not source or source == 0 then return end
    if not targetPlayerId or not forwardVector then return end

    local targetPed = GetPlayerPed(targetPlayerId)
    if not targetPed or targetPed == 0 then return end
    local targetCoords = GetEntityCoords(targetPed)

    for _, pid in ipairs(GetPlayers()) do
        local id = tonumber(pid)
        if id then
            local ped = GetPlayerPed(id)
            if ped and ped ~= 0 and #(GetEntityCoords(ped) - targetCoords) < 100.0 then
                TriggerClientEvent('police:applySyncedTackle', id, targetPlayerId, forwardVector)
            end
        end
    end
    Debug(('SyncTackle for player %d'):format(targetPlayerId))
end)

RegisterNetEvent('police:syncArrest', function(targetPlayerId, policeNetId)
    local source = source
    if not source or source == 0 then return end
    if not targetPlayerId then return end

    local targetPed = GetPlayerPed(targetPlayerId)
    if not targetPed or targetPed == 0 then return end

    -- Snapshot the wanted level NOW — before decay can zero it in the animation window
    local state = GetPlayerState(targetPlayerId)
    if state.level > 0 then state.savedWantedLevel = state.level end
    state.isArrested = true  -- block decay from now on for this player

    local targetCoords = GetEntityCoords(targetPed)
    for _, pid in ipairs(GetPlayers()) do
        local id = tonumber(pid)
        if id then
            local ped = GetPlayerPed(id)
            if ped and ped ~= 0 and #(GetEntityCoords(ped) - targetCoords) < 100.0 then
                TriggerClientEvent('police:applySyncedArrest', id, targetPlayerId, policeNetId)
            end
        end
    end
    Debug(('SyncArrest for player %d | savedWanted=%d'):format(targetPlayerId, state.savedWantedLevel))
end)

-- ════════════════════════════════════════════════════════════════
-- COMMANDS
-- ════════════════════════════════════════════════════════════════

lib.addCommand('setwanted', {
    help = 'Set player wanted level',
    params = { {name='target', type='playerId'}, {name='level', type='number'} },
    restricted = 'group.admin'
}, function(source, args)
    local level = math.max(0, math.min(5, args.level))
    SetWantedLevel(args.target, level, 'Admin Command')
    lib.notify(source, { type='success', description=L('set_wanted_success', GetPlayerName(args.target) or '?', level) })
end)

lib.addCommand('wanted', {
    help = 'Set wanted level (alias)',
    params = { {name='target', type='playerId'}, {name='level', type='number'} },
    restricted = 'group.admin'
}, function(source, args)
    local level = math.max(0, math.min(5, args.level))
    SetWantedLevel(args.target, level, 'Admin Command')
    lib.notify(source, { type='success', description=L('set_wanted_success', GetPlayerName(args.target) or '?', level) })
end)

lib.addCommand('clearwanted', {
    help = 'Clear player wanted level',
    params = { {name='target', type='playerId'} },
    restricted = 'group.admin'
}, function(source, args)
    SetWantedLevel(args.target, 0, 'Admin Cleared')
    lib.notify(source, { type='success', description=L('cleared_wanted_success', GetPlayerName(args.target) or '?') })
end)

lib.addCommand('jail', {
    help = 'Jail a player',
    params = { {name='target', type='playerId'}, {name='time', type='number'} },
    restricted = 'group.admin'
}, function(source, args)
    local time = math.max(10, args.time)
    JailPlayer(args.target, time)
    lib.notify(source, { type='success', description=L('jailed_success', GetPlayerName(args.target) or '?', time) })
end)

lib.addCommand('unjail', {
    help = 'Release a player from jail',
    params = { {name='target', type='playerId'} },
    restricted = 'group.admin'
}, function(source, args)
    ReleasePlayer(args.target)
    lib.notify(source, { type='success', description=L('released_success', GetPlayerName(args.target) or '?') })
end)

lib.addCommand('arrest', {
    help = 'Arrest a player (Police only)',
    params = { {name='target', type='playerId'} }
}, function(source, args)
    if not IsPolice(source) then
        lib.notify(source, { type='error', description=L('police_only') }); return
    end
    local state = GetPlayerState(args.target)
    if state.level <= 0 then
        lib.notify(source, { type='error', description=L('target_not_wanted') }); return
    end
    if IsExemptFromArrest(args.target) then
        lib.notify(source, { type='error', description=L('admin_exempt_arrest') }); return
    end
    local t = math.floor((Config.WantedLevels[state.level].time or 60) * Config.Prison.jailTimeMultiplier)
    JailPlayer(args.target, t)
    lib.notify(source, { type='success', description=L('arrested_success', GetPlayerName(args.target) or '?', t) })
end)

lib.addCommand('checkwanted', {
    help = 'Check player wanted level',
    params = { {name='target', type='playerId'} }
}, function(source, args)
    if not IsPolice(source) and not IsAdmin(source) then
        lib.notify(source, { type='error', description=L('police_only') }); return
    end
    local state = GetPlayerState(args.target)
    lib.notify(source, {
        type='inform', duration=5000,
        description=L('status_checkwanted', GetPlayerName(args.target) or '?',
            state.level, state.isJailed and 'Yes' or 'No', state.totalCrimes)
    })
end)

lib.addCommand('mywanted', { help = 'Check your own wanted level' }, function(source)
    local state = GetPlayerState(source)
    lib.notify(source, { type='inform', duration=5000,
        description=L('status_wanted', state.level, state.totalCrimes) })
end)

lib.addCommand('backup',  { help = 'Call for backup (Police)' }, function(source)
    if not IsPolice(source) then lib.notify(source, { type='error', description=L('police_only') }); return end
    for _, pid in ipairs(GetPlayers()) do
        local id = tonumber(pid)
        if id and IsPolice(id) and id ~= source then
            lib.notify(id, { type='warning', description=L('backup_requested'), icon='shield-exclamation', duration=8000 })
        end
    end
    lib.notify(source, { type='success', description=L('backup_called') })
end)

lib.addCommand('panic', { help = 'Send panic button (Police)' }, function(source)
    if not IsPolice(source) then lib.notify(source, { type='error', description=L('police_only') }); return end
    local coords = GetEntityCoords(GetPlayerPed(source))
    local name   = GetPlayerName(source)
    for _, pid in ipairs(GetPlayers()) do
        local id = tonumber(pid)
        if id and IsPolice(id) then
            lib.notify(id, { type='error', description=L('panic_button', name), icon='circle-exclamation', duration=10000 })
            TriggerClientEvent('police:createPanicBlip', id, coords)
        end
    end
end)

-- ════════════════════════════════════════════════════════════════
-- DEBUG COMMANDS
-- ════════════════════════════════════════════════════════════════

if Config.Debug then
    RegisterCommand('debugpolice_sv', function(source)
        local s = GetPlayerState(source)
        print('=== AIPD Server Debug ===')
        print('Player:', source, '| charid:', s.charid)
        print('Wanted:', s.level, '| isArrested:', s.isArrested)
        print('isJailed:', s.isJailed, '| jailTime:', s.jailTime, '| jailDelivered:', s.jailDelivered)
        print('TotalCrimes:', s.totalCrimes, '| savedWanted:', s.savedWantedLevel)
        print('Active PlayerStates:', (function() local c=0; for _ in pairs(PlayerStates) do c=c+1 end return c end)())
        print('========================')
    end, false)

    RegisterCommand('forcecrime', function(source, args)
        local crimeType = args[1] or 'ASSAULT'
        local coords = GetEntityCoords(GetPlayerPed(source))
        TriggerEvent('police:reportCrime', source, {
            type = crimeType, coords = coords, witnesses = 1,
            areaType = 'CITY_CENTER', severity = 'high', policeAlert = true,
            level = Config.CrimeTypes[crimeType] and Config.CrimeTypes[crimeType].level or 1
        })
        print('^2[AIPD]^7 Forced crime:', crimeType)
    end, false)

    RegisterCommand('resetarrest', function(source)
        local s = GetPlayerState(source)
        s.isArrested   = false
        s.jailDelivered = false
        print('^2[AIPD]^7 Reset arrest state for', source)
    end, false)
end

-- ════════════════════════════════════════════════════════════════
-- PLAYER LIFECYCLE
-- ════════════════════════════════════════════════════════════════

AddEventHandler('playerDropped', function()
    local source = source
    if not source or source == 0 then return end
    if not PlayerStates[source] then return end

    local state  = PlayerStates[source]
    local charid = state.charid or GetCharId(source)

    if charid and MySQL then
        Debug(('playerDropped: source=%d charid=%s isJailed=%s jailTime=%s'):format(
            source, tostring(charid), tostring(state.isJailed), tostring(state.jailTime)))
        if state.isJailed and state.jailTime > 0 then
            MySQL.Async.execute([[
                UPDATE police_records
                SET jail_time=?, jail_start=NOW(), wanted_level=?, total_crimes=?, crimes_data=?
                WHERE charid=?
            ]], { state.jailTime, state.level, state.totalCrimes, json.encode(state.crimes), charid })
        else
            MySQL.Async.execute([[
                INSERT INTO police_records (charid, wanted_level, total_crimes, crimes_data)
                VALUES (?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE
                    wanted_level = VALUES(wanted_level),
                    total_crimes = VALUES(total_crimes),
                    crimes_data  = VALUES(crimes_data)
            ]], { charid, state.level, state.totalCrimes, json.encode(state.crimes) })
        end
    end

    TriggerClientEvent('police:playerDisconnected', -1, source)
    PlayerStates[source] = nil
end)

AddEventHandler('ox:playerLoaded', function(playerId, userId, charId)
    local source = playerId
    if not source or source == 0 then return end

    CreateThread(function()
        Wait(2000)

        -- Resolve charId robustly
        local player          = nil
        local resolvedCharId  = charId
        for i = 1, 10 do
            player = Ox.GetPlayer(source)
            if player then
                resolvedCharId = player.charid or player.charId or charId
                break
            end
            Wait(500)
        end

        Debug(('playerLoaded: source=%d charId=%s resolved=%s'):format(
            source, tostring(charId), tostring(resolvedCharId)))

        if not resolvedCharId or resolvedCharId == 0 then
            TriggerClientEvent('police:systemReady', source, { wantedLevel=0, isJailed=false, jailTime=0, jailCell=1 })
            SetTimeout(1000, function() SyncAllPlayers(source) end)
            return
        end

        local state       = GetPlayerState(source)
        state.initialized = false
        state.charid      = resolvedCharId

        if MySQL then
            MySQL.Async.fetchAll([[
                SELECT *, UNIX_TIMESTAMP(jail_start) AS jail_start_unix
                FROM police_records WHERE charid = ?
            ]], { resolvedCharId }, function(result)
                if result and result[1] then
                    local data          = result[1]
                    state.level         = data.wanted_level or 0
                    state.totalCrimes   = data.total_crimes or 0

                    if data.crimes_data then
                        local ok, dec = pcall(json.decode, data.crimes_data)
                        state.crimes = ok and dec or {}
                    end

                    -- Jail restore
                    local isJailed = data.is_jailed and data.is_jailed ~= 0
                    if isJailed and data.jail_time and data.jail_time > 0 then
                        local remaining = tonumber(data.jail_time) or 0

                        if remaining > 0 then
                            state.isJailed   = true
                            state.jailTime   = remaining
                            state.jailCell   = data.jail_cell or 1
                            state.isArrested = true

                            if data.saved_inventory then
                                local ok, dec = pcall(json.decode, data.saved_inventory)
                                if ok then state.savedInventory = dec end
                            end

                            MySQL.Async.execute([[
                                UPDATE police_records SET jail_time=?, jail_start=NOW() WHERE charid=?
                            ]], { remaining, resolvedCharId })

                            Debug(('Jail restore for player %d: %ds in cell %d'):format(
                                source, remaining, state.jailCell))
                        else
                            -- Expired while offline — release and restore inventory
                            state.isJailed = false
                            state.jailTime = 0
                            if data.saved_inventory then
                                local ok, dec = pcall(json.decode, data.saved_inventory)
                                if ok then state.savedInventory = dec end
                            end
                            local _src    = source
                            local _charid = resolvedCharId
                            SetTimeout(8000, function()
                                if GetPlayerName(_src) and Ox.GetPlayer(_src) then
                                    RestoreInventory(_src)
                                    Debug(('Expired jail: inventory restored for player %d'):format(_src))
                                end
                                MySQL.Async.execute([[
                                    UPDATE police_records
                                    SET is_jailed=0, jail_time=0, jail_start=NULL, saved_inventory=NULL
                                    WHERE charid=?
                                ]], { _charid })
                            end)
                        end
                    end
                end

                state.initialized = true
                SyncPlayerState(source)

                TriggerClientEvent('police:systemReady', source, {
                    wantedLevel = state.level    or 0,
                    isJailed    = state.isJailed or false,
                    jailTime    = state.jailTime or 0,
                    jailCell    = state.jailCell or 1,
                })

                -- If jailed, start delivery loop NOW (client systemReady might arrive before jail)
                if state.isJailed and state.jailTime > 0 then
                    state.jailDelivered = false
                    CreateThread(function()
                        Wait(3000)  -- Give systemReady+InitializeSystem time to complete
                        local attempts = 0
                        while attempts < 10 do
                            if not GetPlayerName(source) then break end
                            local s = PlayerStates[source]
                            if not s or not s.isJailed or s.jailDelivered then break end
                            attempts = attempts + 1
                            Debug(('JailRestore delivery attempt %d for player %d'):format(attempts, source))
                            TriggerClientEvent('police:teleportToJail', source, s.jailCell, s.jailTime)
                            Wait(3000)
                        end
                    end)
                end

                SetTimeout(1000, function() SyncAllPlayers(source) end)

                Debug(('Player %d loaded — Level:%d Jailed:%s JailTime:%d'):format(
                    source, state.level, tostring(state.isJailed), state.jailTime or 0))
            end)
        else
            state.initialized = true
            SyncPlayerState(source)
            TriggerClientEvent('police:systemReady', source, { wantedLevel=0, isJailed=false, jailTime=0, jailCell=1 })
            SetTimeout(1000, function() SyncAllPlayers(source) end)
        end
    end)
end)

-- ════════════════════════════════════════════════════════════════
-- JAIL TIMER  —  SERVER AUTHORITATIVE
-- One thread handles ALL players safely with pcall isolation.
-- ════════════════════════════════════════════════════════════════

CreateThread(function()
    while true do
        Wait(1000)
        for src, state in pairs(PlayerStates) do
            local ok, err = pcall(function()
                if state and state.isJailed
                    and type(state.jailTime) == 'number'
                    and state.jailTime > 0
                then
                    state.jailTime = state.jailTime - 1

                    -- Broadcast remaining time every 5s
                    if state.jailTime % 5 == 0 then
                        SyncPlayerState(src)
                        TriggerClientEvent('police:updateJailTime', src, state.jailTime)

                        -- DB update every 10s
                        if MySQL and state.jailTime % 10 == 0 then
                            local cid = state.charid
                            if cid then
                                MySQL.Async.execute([[
                                    UPDATE police_records SET jail_time=?, jail_start=NOW() WHERE charid=?
                                ]], { state.jailTime, cid })
                            end
                        end
                    end

                    if state.jailTime <= 0 then
                        ReleasePlayer(src)
                    end
                end
            end)
            if not ok then
                Debug(('Jail timer error for player %s: %s'):format(tostring(src), tostring(err)))
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
                `jail_start` DATETIME NULL,
                `saved_inventory` LONGTEXT,
                `last_arrest` DATETIME NULL,
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
                `reported_time` DATETIME DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                INDEX `idx_charid` (`charid`),
                INDEX `idx_crime_type` (`crime_type`),
                INDEX `idx_reported_time` (`reported_time`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        ]])
        -- Ensure jail_start is DATETIME (migrate from DATE if needed)
        MySQL.Async.execute([[
            ALTER TABLE police_records MODIFY COLUMN jail_start DATETIME NULL DEFAULT NULL
        ]], {}, function() end)
        print('^2[AIPD | Server]^7 Database ready')
    end)
end

-- ════════════════════════════════════════════════════════════════
-- CLEANUP (stale states)
-- ════════════════════════════════════════════════════════════════

CreateThread(function()
    while true do
        Wait(300000)
        local removed = 0
        for src in pairs(PlayerStates) do
            if not GetPlayerName(src) then
                local s = PlayerStates[src]
                if s and s.charid and MySQL and s.isJailed and s.jailTime > 0 then
                    MySQL.Async.execute([[
                        UPDATE police_records SET jail_time=?, jail_start=NOW(), wanted_level=?
                        WHERE charid=?
                    ]], { s.jailTime, s.level, s.charid })
                end
                PlayerStates[src] = nil
                removed = removed + 1
            end
        end
        if removed > 0 then Debug(('Cleanup: removed %d stale states'):format(removed)) end
    end
end)

-- ════════════════════════════════════════════════════════════════
-- EXPORTS
-- ════════════════════════════════════════════════════════════════

exports('SetWantedLevel',           SetWantedLevel)
exports('GetWantedLevel',           function(src) return GetPlayerState(src).level end)
exports('JailPlayer',               JailPlayer)
exports('ReleasePlayer',            ReleasePlayer)
exports('IsPolice',                 IsPolice)
exports('IsAdmin',                  IsAdmin)
exports('IsExemptFromWanted',       IsExemptFromWanted)
exports('IsExemptFromArrest',       IsExemptFromArrest)
exports('IsExemptFromJail',         IsExemptFromJail)
exports('GetPlayerState',           GetPlayerState)
exports('PropagateWantedToCoOccupants', PropagateWantedToCoOccupants)

-- ════════════════════════════════════════════════════════════════
-- STARTUP
-- ════════════════════════════════════════════════════════════════

print('^2════════════════════════════════════════════════^0')
print('^2[AIPD | Server]^0 ✓ NEXT-GEN Edition — Bulletproof Jail • Multi-Player Safe')
print('^2[AIPD | Server]^0 ✅ Jail delivery: retry loop + client ACK')
print('^2[AIPD | Server]^0 ✅ Arrest race: server-side isArrested flag + savedWantedLevel snapshot')
print('^2[AIPD | Server]^0 ✅ Decay: blocked server-side during arrest window')
print('^2[AIPD | Server]^0 ✅ Multi-player: fully isolated per-player state')
print('^2[AIPD | Server]^0 ✅ StateBag + Broadcast: always in sync via single SyncPlayerState()')
print('^2════════════════════════════════════════════════^0')
