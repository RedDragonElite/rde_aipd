---@diagnostic disable: undefined-global
-- ════════════════════════════════════════════════════════════════════════════════
-- rde_aipd | CLIENT | crime.lua
-- Realistic Witness-Based Crime System — ox_core Edition
-- ════════════════════════════════════════════════════════════════════════════════
--
-- FEATURES:
--  ✅ Zeuge muss 911-Call VOLLSTÄNDIG abschließen → erst dann Wanted Level
--  ✅ Zeuge töten/einschüchtern unterbricht den Call → kein Wanted Level
--  ✅ Area-basierte Handy-Wahrscheinlichkeit (Stadt hoch, Wildnis niedrig)
--  ✅ Line-of-Sight Prüfung für Zeugen
--  ✅ Vollständige Crime Detection: Schießen, Fahrzeugdiebstahl, Unfall,
--     Einbruch, Vandalismus, Assault, Mord
--  ✅ Wanted Level Decay wenn Polizei keine Sichtlinie hat
--  ✅ Rein ox_core – kein ESX
--
-- ════════════════════════════════════════════════════════════════════════════════

local cache = {ped = 0, coords = vector3(0, 0, 0), vehicle = 0, inVehicle = false}

local crimeState = {
    isPoliceNearby    = false,
    cooldowns         = {},
    currentArea       = 'URBAN',
    areaMultiplier    = 1.0,
    isAdmin           = false,
    playerLoaded      = false,
    systemInitialized = false,
    lastSeenByCop     = 0,
    decayActive       = false,
    copsCanSeePlayer  = false,
    lastAreaCheck     = 0,
    lastPoliceCheck   = 0,
}

-- Telefon-Wahrscheinlichkeit je nach Gebiet (aus old system übernommen + verfeinert)
local PhoneChanceByArea = {
    CITY_CENTER = 0.90,
    URBAN       = 0.85,
    SUBURBAN    = 0.70,
    RURAL       = 0.45,
    WILDERNESS  = 0.15,
}

local CallDuration = {min = 3000, max = 6000}

-- Guard flags — verhindern doppelte Threads
local crimeThreadStarted  = false
local decayThreadStarted  = false
local vehicleThreadStarted = false

-- ════════════════════════════════════════════════════════════════════════════════
-- CACHE THREAD
-- ════════════════════════════════════════════════════════════════════════════════

CreateThread(function()
    while true do
        cache.ped = PlayerPedId()
        if DoesEntityExist(cache.ped) then
            cache.coords    = GetEntityCoords(cache.ped)
            cache.vehicle   = GetVehiclePedIsIn(cache.ped, false)
            cache.inVehicle = cache.vehicle ~= 0
        end
        Wait(500)
    end
end)

-- ════════════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════════════════════

local function Debug(...)
    if Config.Debug then
        print('^3[Crime | Client]^7', ...)
    end
end

local function IsCrimeOnCooldown(crimeType)
    local cfg = Config.CrimeTypes[crimeType]
    if not cfg then return true end
    local cd = cfg.cooldown or 30000
    return crimeState.cooldowns[crimeType] and (GetGameTimer() - crimeState.cooldowns[crimeType]) < cd
end

local function GetCurrentArea()
    if not Config.Areas then return 'URBAN', 1.0 end
    for _, area in pairs(Config.Areas) do
        if #(cache.coords - area.coords) <= area.radius then
            local mult = Config.WitnessSystem
                and Config.WitnessSystem.areaMultipliers
                and Config.WitnessSystem.areaMultipliers[area.type]
                or 1.0
            return area.type, mult
        end
    end
    return 'URBAN', 1.0
end

local function CheckPoliceProximity()
    local peds = GetGamePool('CPed')
    for _, ped in ipairs(peds) do
        if DoesEntityExist(ped) and not IsPedAPlayer(ped) and GetPedType(ped) == 6 then
            if #(cache.coords - GetEntityCoords(ped)) <= 150.0 then
                return true
            end
        end
    end
    return false
end

local function GetWantedLevel()
    -- ✅ FIX: Server setzt wantedLevel auf Entity(ped).state, NICHT auf LocalPlayer.state!
    -- LocalPlayer.state.wantedLevel war IMMER nil → 0 → Decay + LOS-Check waren tot
    local ped = cache.ped
    if ped and ped ~= 0 and DoesEntityExist(ped) then
        local ok, val = pcall(function()
            return Entity(ped).state.wantedLevel
        end)
        if ok and val and type(val) == 'number' then return val end
    end
    return 0
end

-- ════════════════════════════════════════════════════════════════════════════════
-- LINE-OF-SIGHT
-- ════════════════════════════════════════════════════════════════════════════════

local function HasLineOfSight(fromCoords, toCoords, maxDistance)
    maxDistance = maxDistance or 60.0
    if #(fromCoords - toCoords) > maxDistance then return false end

    local ray = StartShapeTestRay(
        fromCoords.x, fromCoords.y, fromCoords.z + 1.0,
        toCoords.x,   toCoords.y,   toCoords.z + 1.0,
        -1, cache.ped, 0
    )
    local _, hit, _, _, entityHit = GetShapeTestResult(ray)
    return not (hit and entityHit ~= cache.ped)
end

local function CheckCopsLineOfSight()
    if GetWantedLevel() == 0 then return false end

    local peds = GetGamePool('CPed')
    for _, ped in ipairs(peds) do
        if DoesEntityExist(ped) and not IsPedAPlayer(ped) and GetPedType(ped) == 6 then
            local copCoords = GetEntityCoords(ped)
            local dist      = #(cache.coords - copCoords)
            if dist <= 120.0 and HasLineOfSight(copCoords, cache.coords, 120.0) then
                local heading   = GetEntityHeading(ped)
                local angle     = math.deg(math.atan2(
                    cache.coords.y - copCoords.y,
                    cache.coords.x - copCoords.x
                ))
                local diff = math.abs(heading - angle) % 360
                if diff < 120 or diff > 240 then
                    return true, ped, dist
                end
            end
        end
    end
    return false
end

-- ════════════════════════════════════════════════════════════════════════════════
-- WITNESS SYSTEM
-- ════════════════════════════════════════════════════════════════════════════════

local function GetNearbyWitnesses(coords, radius)
    local areaType    = crimeState.currentArea
    local phoneChance = PhoneChanceByArea[areaType] or 0.85

    local result = {npcs = {}, players = {}}

    -- NPC Zeugen
    local peds = GetGamePool('CPed')
    for _, ped in ipairs(peds) do
        if DoesEntityExist(ped)
            and not IsPedAPlayer(ped)
            and not IsPedDeadOrDying(ped, true)
        then
            local pedCoords = GetEntityCoords(ped)
            local distance  = #(coords - pedCoords)
            if distance <= radius then
                local pedType = GetPedType(ped)
                -- Keine Polizisten (6), Tiere (27/28)
                if pedType ~= 6 and pedType ~= 27 and pedType ~= 28 then
                    result.npcs[#result.npcs + 1] = {
                        ped          = ped,
                        distance     = distance,
                        hasPhone     = math.random() < phoneChance,
                        awareness    = math.random(60, 100) / 100,
                        callDuration = math.random(CallDuration.min, CallDuration.max),
                    }
                end
            end
        end
    end

    -- Spieler als Zeugen
    for _, pid in ipairs(GetActivePlayers()) do
        if pid ~= PlayerId() then
            local targetPed = GetPlayerPed(pid)
            if DoesEntityExist(targetPed) and not IsPedDeadOrDying(targetPed, true) then
                local dist = #(coords - GetEntityCoords(targetPed))
                if dist <= radius then
                    result.players[#result.players + 1] = {
                        player   = pid,
                        distance = dist,
                        hasPhone = true,
                    }
                end
            end
        end
    end

    Debug(('Witnesses: %d NPC, %d Player | Phone chance: %.0f%%'):format(
        #result.npcs, #result.players, phoneChance * 100
    ))
    return result
end

-- Findet den besten NPC-Zeugen mit Telefon.
-- BEWUSST EINFACH gehalten: StartShapeTestRay ist asynchron und liefert im
-- selben Frame kein zuverlässiges Ergebnis → kein Raycast hier.
-- Die phone-Wahrscheinlichkeit (area-basiert) ist die einzige Hürde.
local function FindBestCaller(witnesses, crimeCoords)
    -- Bevorzuge den nächsten NPC mit Telefon der noch lebt
    local bestNPC, bestDist = nil, math.huge
    for _, w in ipairs(witnesses.npcs) do
        if w.hasPhone
            and DoesEntityExist(w.ped)
            and not IsPedDeadOrDying(w.ped, true)
        then
            if w.distance < bestDist then
                bestNPC  = w
                bestDist = w.distance
            end
        end
    end

    if bestNPC then
        Debug(('FindBestCaller: NPC-Zeuge gewählt | %.1fm | hasPhone=true'):format(bestDist))
        return bestNPC
    end

    -- Spieler-Zeuge als Fallback
    for _, w in ipairs(witnesses.players) do
        Debug('FindBestCaller: Spieler-Zeuge als Fallback gewählt')
        return w
    end

    Debug(('FindBestCaller: kein Zeuge – %d NPCs geprüft (ohne Telefon oder tot)'):format(#witnesses.npcs))
    return nil
end

-- ════════════════════════════════════════════════════════════════════════════════
-- 911-CALL SEQUENZ
-- ════════════════════════════════════════════════════════════════════════════════
--
-- DAS IST DAS HERZSTÜCK:
-- Zeuge führt erst den kompletten 911-Call durch,
-- DANN wird das Verbrechen an den Server gemeldet.
-- Wird der Zeuge unterbrochen → kein Wanted Level.
--
-- ════════════════════════════════════════════════════════════════════════════════

local function Execute911CallSequence(caller, crimeType, crimeCoords, crimeLevel, witnessCount)
    local isPlayerWitness = caller.player ~= nil
    local callerPed       = not isPlayerWitness and caller.ped or nil
    local callDuration    = caller.callDuration or math.random(CallDuration.min, CallDuration.max)

    CreateThread(function()
        -- Reaktionsverzögerung (Zeuge schaut erstmal)
        local reactionDelay = math.random(1500, 3500)

        if callerPed then
            TaskLookAtEntity(callerPed, cache.ped, callDuration + reactionDelay + 2000, 2048, 3)
        end

        Wait(reactionDelay)

        -- Prüfen ob Zeuge noch lebt
        if callerPed and (not DoesEntityExist(callerPed) or IsPedDeadOrDying(callerPed, true)) then
            Debug('Zeuge vor dem Call gestorben')
            TriggerServerEvent('police:crimeDetectedNoWitness', crimeType, crimeCoords)
            lib.notify({
                type        = 'success',
                description = '✓ Zeuge ausgeschaltet – kein 911-Call',
                duration    = 3000,
            })
            return
        end

        -- Telefon-Animation starten
        if callerPed then
            local animDict = 'cellphone@call_listen_base'
            RequestAnimDict(animDict)
            local timeout = 0
            while not HasAnimDictLoaded(animDict) and timeout < 100 do
                Wait(10)
                timeout = timeout + 1
            end
            if HasAnimDictLoaded(animDict) then
                TaskPlayAnim(callerPed, animDict, 'cellphone_call_listen_base',
                    8.0, -8.0, -1, 49, 0, false, false, false)
            end
        end

        -- Warte die gesamte Call-Dauer
        -- In dieser Zeit kann der Spieler den Zeugen unterbrechen!
        Wait(callDuration)

        -- Nochmal prüfen ob Zeuge überlebt hat
        if callerPed and (not DoesEntityExist(callerPed) or IsPedDeadOrDying(callerPed, true)) then
            Debug('Zeuge WÄHREND des Calls gestorben → kein Wanted Level')
            TriggerServerEvent('police:crimeDetectedNoWitness', crimeType, crimeCoords)
            lib.notify({
                type        = 'success',
                description = '✓ Zeuge unterbrochen – Call abgebrochen',
                duration    = 3000,
            })
            return
        end

        -- ✅ Call erfolgreich abgeschlossen → jetzt erst Wanted Level
        Debug(('911-Call abgeschlossen! Melde Verbrechen: %s'):format(crimeType))

        TriggerServerEvent('police:reportCrime', {
            type         = crimeType,
            coords       = crimeCoords,
            level        = crimeLevel,
            witnessCount = witnessCount,
            crimeTime    = GetGameTimer(),
            callCompleted = true,
            witness      = {
                distance      = caller.distance or 0,
                isPlayerCaller = isPlayerWitness,
            },
        })

        -- Nostr Logging
        TriggerServerEvent('police:nostr:crime',
            crimeType,
            crimeState.currentArea,
            true
        )
    end)
end

-- ════════════════════════════════════════════════════════════════════════════════
-- LOG CRIME — Hauptfunktion
-- ════════════════════════════════════════════════════════════════════════════════

function LogCrime(crimeType, coords, force)
    if not crimeState.systemInitialized then
        Debug('System noch nicht initialisiert')
        return false
    end

    if crimeState.isAdmin and not force then
        Debug(('Admin-Verbrechen unterdrückt: %s'):format(crimeType))
        return false
    end

    local crimeConfig = Config.CrimeTypes[crimeType]
    if not crimeConfig then
        Debug(('Unbekannter Crime-Typ: %s'):format(crimeType))
        return false
    end

    if not force and IsCrimeOnCooldown(crimeType) then
        return false
    end

    if not DoesEntityExist(cache.ped) then return false end

    -- Cooldown sofort setzen
    crimeState.cooldowns[crimeType] = GetGameTimer()

    local crimeCoords  = coords or cache.coords
    local crimeLevel   = crimeConfig.level or 1
    local currentWanted = GetWantedLevel()

    -- Additives Wanted-Level-System
    if currentWanted > 0 then
        if crimeLevel < currentWanted then
            Debug(('%s ignoriert (Level %d < aktuell %d)'):format(crimeType, crimeLevel, currentWanted))
            return false
        elseif crimeLevel == currentWanted then
            crimeLevel = math.min(5, currentWanted + 1)
        end
    end
    crimeLevel = math.min(crimeLevel, 5)

    -- Zeuge-Radius je nach Schwere
    local baseRadius = (Config.WitnessSystem and Config.WitnessSystem.baseDistance) or 50.0
    local severity   = crimeConfig.severity or 'medium'
    local radius     = baseRadius * (
        severity == 'critical' and 1.8 or
        severity == 'high'     and 1.4 or
        1.0
    )

    local witnesses = GetNearbyWitnesses(crimeCoords, radius)
    local withPhone = 0
    for _, w in ipairs(witnesses.npcs) do
        if w.hasPhone then withPhone = withPhone + 1 end
    end
    Debug(('LogCrime %s | %d NPCs gefunden | %d mit Telefon | %d Spieler | Area: %s'):format(
        crimeType, #witnesses.npcs, withPhone, #witnesses.players, crimeState.currentArea
    ))
    local caller    = FindBestCaller(witnesses, crimeCoords)

    if not caller then
        -- Kein Zeuge → kein Wanted Level
        Debug(('%s: kein Zeuge mit Telefon'):format(crimeType))
        TriggerServerEvent('police:crimeDetectedNoWitness', crimeType, crimeCoords)
        TriggerServerEvent('police:nostr:crime', crimeType, crimeState.currentArea, false)

        lib.notify({
            type        = 'success',
            description = '✓ Keine Zeugen in der Nähe',
            duration    = 2500,
        })
        return false
    end

    -- Zeuge gefunden → 911-Call starten
    local totalWitnesses = #witnesses.npcs + #witnesses.players

    Debug(('%s: Zeuge gefunden (%.0fm) – 911-Call läuft...'):format(crimeType, caller.distance or 0))

    lib.notify({
        type        = 'warning',
        description = ('⚠ Zeuge hat dich gesehen! %s'):format(crimeConfig.description or crimeType),
        duration    = 3000,
    })

    Execute911CallSequence(caller, crimeType, crimeCoords, crimeLevel, totalWitnesses)
    return true
end

-- ════════════════════════════════════════════════════════════════════════════════
-- WANTED LEVEL DECAY
-- ════════════════════════════════════════════════════════════════════════════════

local decayConfig = {
    enabled         = true,
    checkInterval   = 2000,
    timeBeforeDecay = 15000,
    decayInterval   = 20000,
    lastDecayTime   = 0,
}

local function StartWantedDecaySystem()
    if decayThreadStarted then return end
    decayThreadStarted = true

    CreateThread(function()
        while true do
            Wait(decayConfig.checkInterval)
            if not decayConfig.enabled then goto continue end

            local wantedLevel = GetWantedLevel()
            if wantedLevel > 0 then
                local canSee = CheckCopsLineOfSight()
                crimeState.copsCanSeePlayer = canSee

                if canSee then
                    crimeState.lastSeenByCop = GetGameTimer()
                    crimeState.decayActive   = false
                else
                    local timeSince = GetGameTimer() - crimeState.lastSeenByCop

                    if timeSince >= decayConfig.timeBeforeDecay then
                        if not crimeState.decayActive then
                            crimeState.decayActive    = true
                            decayConfig.lastDecayTime = GetGameTimer()
                            lib.notify({
                                type        = 'inform',
                                description = '👁 Außer Sichtweite – Fahndungslevel sinkt...',
                                duration    = 3000,
                            })
                        end

                        if (GetGameTimer() - decayConfig.lastDecayTime) >= decayConfig.decayInterval then
                            if GetWantedLevel() > 0 then
                                TriggerServerEvent('police:decayWantedLevel')
                                decayConfig.lastDecayTime = GetGameTimer()
                            else
                                crimeState.decayActive = false
                            end
                        end
                    end
                end
            else
                crimeState.decayActive   = false
                crimeState.lastSeenByCop = 0
            end

            ::continue::
        end
    end)
    Debug('Wanted Decay System gestartet')
end

-- ════════════════════════════════════════════════════════════════════════════════
-- STATEBAG SYNC
-- ════════════════════════════════════════════════════════════════════════════════

-- ✅ FIX #12: StateBag Handler ENTFERNT — main.lua hat den korrekten entity-basierten Handler.
-- Der alte Handler hier nutzte 'player:X' Format, aber ox_core setzt StateBags auf Entity(ped).
-- Doppelter Handler wäre sowieso redundant.

-- ════════════════════════════════════════════════════════════════════════════════
-- MURDER / ASSAULT — gameEventTriggered
-- ════════════════════════════════════════════════════════════════════════════════

AddEventHandler('gameEventTriggered', function(name, args)
    if not crimeState.systemInitialized or not crimeState.playerLoaded then return end
    if name ~= 'CEventNetworkEntityDamage' then return end

    local victim     = args[1]
    local attacker   = args[2]
    local isFatal    = args[6]

    if attacker ~= cache.ped or victim == cache.ped then return end
    if not DoesEntityExist(victim) then return end

    local victimType = GetPedType(victim)

    if isFatal == 1 or IsEntityDead(victim) then
        if victimType == 6 then
            LogCrime('MURDER_COP', nil, true)
            TriggerServerEvent('police:nostr:copKilled')
        elseif IsPedAPlayer(victim) or (victimType ~= 27 and victimType ~= 28) then
            LogCrime('MURDER', nil, true)
        end
    else
        if victimType == 6 then
            LogCrime('ASSAULT_COP')
        elseif IsPedAPlayer(victim) or (victimType ~= 27 and victimType ~= 28) then
            LogCrime('ASSAULT')
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════════════════
-- CRIME DETECTION THREADS
-- (aus dem alten System portiert + ESX entfernt + ox_core/ox_inventory)
-- ════════════════════════════════════════════════════════════════════════════════

local function StartCrimeDetectionThread()
    if crimeThreadStarted then
        Debug('Crime-Thread läuft bereits')
        return
    end
    crimeThreadStarted = true

    -- ── Area & Police Proximity Checks ──────────────────────────────────────
    CreateThread(function()
        while true do
            Wait(2000)
            if not crimeState.systemInitialized then goto nextAreaCheck end

            local now = GetGameTimer()
            if now - crimeState.lastAreaCheck > 5000 then
                crimeState.currentArea, crimeState.areaMultiplier = GetCurrentArea()
                crimeState.lastAreaCheck = now
            end
            if now - crimeState.lastPoliceCheck > 3000 then
                crimeState.isPoliceNearby = CheckPoliceProximity()
                crimeState.lastPoliceCheck = now
            end

            ::nextAreaCheck::
        end
    end)

    -- ── SHOOTING — Schuss abgefeuert ─────────────────────────────────────────
    CreateThread(function()
        while true do
            Wait(100)
            if not crimeState.systemInitialized then goto nextShoot end

            if IsPedShooting(cache.ped) and not IsCrimeOnCooldown('SHOOTING') then
                LogCrime('SHOOTING')
            end

            ::nextShoot::
        end
    end)

    -- ── BRANDISHING — Waffe gezogen ──────────────────────────────────────────
    CreateThread(function()
        while true do
            Wait(1000)
            if not crimeState.systemInitialized or cache.inVehicle then goto nextBrand end

            if IsPedArmed(cache.ped, 4) and not IsCrimeOnCooldown('BRANDISHING') then
                local weapon = GetSelectedPedWeapon(cache.ped)
                if weapon ~= GetHashKey('WEAPON_UNARMED') then
                    local chance = crimeState.isPoliceNearby and 0.04 or 0.006
                    if math.random() < chance then
                        LogCrime('BRANDISHING')
                    end
                end
            end

            ::nextBrand::
        end
    end)

    -- ── BURGLARY — Aufbruch-Animation erkannt ────────────────────────────────
    -- (aus old system, portiert auf GTA-native-Checks)
    CreateThread(function()
        while true do
            Wait(1000)
            if not crimeState.systemInitialized or cache.inVehicle then goto nextBurg end

            local ped = cache.ped
            local isLockpicking =
                IsEntityPlayingAnim(ped, 'mini@safe_cracking', 'idle_base', 3) or
                IsEntityPlayingAnim(ped, 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', 'machinic_loop_mechandplayer', 3) or
                IsEntityPlayingAnim(ped, 'veh@break_in@0h@std@ds', 'low_stance_ds', 3) or
                IsEntityPlayingAnim(ped, 'missheist_apartment2', 'loop_hacker', 3)

            if isLockpicking and not IsCrimeOnCooldown('BURGLARY') then
                LogCrime('BURGLARY')
            end

            ::nextBurg::
        end
    end)

    -- ── VANDALISM — Melee auf Objekte ────────────────────────────────────────
    CreateThread(function()
        while true do
            Wait(1000)
            if not crimeState.systemInitialized then goto nextVand end

            local ped = cache.ped
            if IsPedArmed(ped, 1) and IsPedInMeleeCombat(ped) then
                local entityHit = GetEntityPlayerIsFreeAimingAt(PlayerId())
                if entityHit and entityHit ~= 0
                    and not IsEntityAPed(entityHit)
                    and not IsEntityAVehicle(entityHit)
                    and not IsCrimeOnCooldown('VANDALISM')
                then
                    LogCrime('VANDALISM')
                end
            end

            ::nextVand::
        end
    end)

    -- ── SPEEDING / RECKLESS DRIVING / HIT_AND_RUN ────────────────────────────
    CreateThread(function()
        local lastHitCheck = 0

        while true do
            Wait(500)
            if not crimeState.systemInitialized then goto nextVeh end
            if not cache.inVehicle then goto nextVeh end
            if GetPedInVehicleSeat(cache.vehicle, -1) ~= cache.ped then goto nextVeh end

            local speed   = GetEntitySpeed(cache.vehicle) * 3.6  -- km/h
            local area    = crimeState.currentArea
            local limit   = area == 'CITY_CENTER' and 60
                         or area == 'URBAN'       and 80
                         or area == 'SUBURBAN'    and 100
                         or 120

            -- SPEEDING
            if speed > (limit + 20) and not IsCrimeOnCooldown('SPEEDING') then
                LogCrime('SPEEDING')
            end

            -- RECKLESS DRIVING (sehr hohe Geschwindigkeit + Schräglage)
            if speed > (limit + 40) and not IsCrimeOnCooldown('RECKLESS_DRIVING') then
                local roll = GetEntityRoll(cache.vehicle)
                if math.abs(roll) > 20.0 then
                    LogCrime('RECKLESS_DRIVING')
                end
            end

            -- HIT AND RUN
            local now = GetGameTimer()
            if now - lastHitCheck > 1500 and HasEntityCollidedWithAnything(cache.vehicle) then
                lastHitCheck = now
                local vCoords = GetEntityCoords(cache.vehicle)
                local pool    = GetGamePool('CPed')

                for _, ped in ipairs(pool) do
                    if ped ~= cache.ped and not IsPedInAnyVehicle(ped, true) then
                        local pCoords = GetEntityCoords(ped)
                        if #(pCoords - vCoords) < 4.0
                            and IsEntityTouchingEntity(cache.vehicle, ped)
                            and not IsCrimeOnCooldown('HIT_AND_RUN')
                        then
                            if IsPedAPlayer(ped) or not IsPedDeadOrDying(ped, true) then
                                LogCrime('HIT_AND_RUN')
                                break
                            end
                        end
                    end
                end
            end

            ::nextVeh::
        end
    end)

    -- ── VEHICLE THEFT — Fahrzeugjacking ──────────────────────────────────────
    -- (aus old system portiert)
    CreateThread(function()
        while true do
            Wait(500)
            if not crimeState.systemInitialized then goto nextTheft end

            if (IsPedTryingToEnterALockedVehicle(cache.ped) or IsPedJacking(cache.ped))
                and not IsCrimeOnCooldown('VEHICLE_THEFT')
            then
                LogCrime('VEHICLE_THEFT')
            end

            ::nextTheft::
        end
    end)

    -- ── ASSAULT — Nahkampf (nicht-fatal) ─────────────────────────────────────
    CreateThread(function()
        while true do
            Wait(500)
            if not crimeState.systemInitialized or cache.inVehicle then goto nextAssault end

            if IsPedInMeleeCombat(cache.ped) then
                local target = GetMeleeTargetForPed(cache.ped)
                if target ~= 0 and not IsPedDeadOrDying(target, true) then
                    if not IsCrimeOnCooldown('ASSAULT') then
                        if GetPedType(target) == 6 then
                            LogCrime('ASSAULT_COP')
                        else
                            LogCrime('ASSAULT')
                        end
                    end
                end
            end

            ::nextAssault::
        end
    end)

    -- ── DRUG_POSSESSION — ox_inventory Check ─────────────────────────────────
    -- Intervall-Check alle 90s wenn Polizei in der Nähe ist
    if Config.CrimeTypes.DRUG_POSSESSION then
        CreateThread(function()
            while true do
                Wait(90000)
                if not crimeState.systemInitialized then goto nextDrug end
                if not crimeState.isPoliceNearby then goto nextDrug end
                if IsCrimeOnCooldown('DRUG_POSSESSION') then goto nextDrug end

                local ok, inv = pcall(function()
                    return exports.ox_inventory:GetPlayerItems()
                end)

                if ok and inv then
                    local illegalDrugs = {
                        'weed', 'cocaine', 'heroin', 'meth', 'oxy',
                        'weed_seeds', 'drug_', 'drugs_',
                    }
                    for _, item in pairs(inv) do
                        if item and item.name then
                            for _, keyword in ipairs(illegalDrugs) do
                                if string.find(item.name:lower(), keyword) then
                                    LogCrime('DRUG_POSSESSION')
                                    goto nextDrug
                                end
                            end
                        end
                    end
                end

                ::nextDrug::
            end
        end)
    end

    Debug('Crime Detection Threads gestartet')
end

-- ════════════════════════════════════════════════════════════════════════════════
-- EXTERNE CRIME-TRIGGER
-- (für andere Ressourcen wie Raub, Drogenverkauf etc.)
-- ════════════════════════════════════════════════════════════════════════════════

-- Allgemeiner Trigger von anderen Ressourcen
RegisterNetEvent('rde_aipd:triggerCrime', function(crimeType, coords)
    if not crimeState.systemInitialized then return end
    if not Config.CrimeTypes[crimeType] then
        Debug(('Unbekannter externer Crime-Typ: %s'):format(tostring(crimeType)))
        return
    end
    local c = coords and type(coords) == 'vector3' and coords or cache.coords
    LogCrime(crimeType, c, false)
end)

-- Kompatibilität mit alten ESX-Ereignissen → einfach weiterleiten
RegisterNetEvent('rde_crimes:clientCrime', function(crimeType)
    LogCrime(crimeType)
end)

-- ════════════════════════════════════════════════════════════════════════════════
-- SERVER EVENTS
-- ════════════════════════════════════════════════════════════════════════════════

RegisterNetEvent('police:setWantedLevel', function(level)
    level = level or 0
    Debug(('Wanted Level via Event: %d'):format(level))
end)

RegisterNetEvent('police:systemReady', function(data)
    CreateThread(function()
        Wait(1000)
        crimeState.systemInitialized = false
        InitializeCrimeSystem()
    end)
end)

-- ════════════════════════════════════════════════════════════════════════════════
-- INITIALIZATION
-- ════════════════════════════════════════════════════════════════════════════════

function InitializeCrimeSystem()
    if crimeState.systemInitialized then return end
    Debug('Initialisiere Enhanced Crime System...')

    crimeState.playerLoaded = true

    local ok, isAdmin = pcall(function()
        return lib.callback.await('police:isAdmin', false)
    end)

    crimeState.isAdmin = ok and isAdmin or false

    if crimeState.isAdmin then
        Debug('Admin-Modus aktiv – Verbrechen werden geloggt, nicht eskaliert')
    end

    crimeState.lastSeenByCop = GetGameTimer()
    crimeState.currentArea, crimeState.areaMultiplier = GetCurrentArea()

    StartCrimeDetectionThread()
    StartWantedDecaySystem()

    crimeState.systemInitialized = true
    Debug('Crime System initialisiert')
end

AddEventHandler('ox:playerLoaded', function()
    CreateThread(function()
        Wait(3000)
        InitializeCrimeSystem()
    end)
end)

AddEventHandler('onResourceStart', function(name)
    if GetCurrentResourceName() == name then
        CreateThread(function()
            Wait(5000)
            InitializeCrimeSystem()
        end)
    end
end)

-- ════════════════════════════════════════════════════════════════════════════════
-- DEBUG COMMANDS
-- ════════════════════════════════════════════════════════════════════════════════

if Config.Debug then
    RegisterCommand('testcrime', function(_, args)
        local crimeType = args[1] or 'ASSAULT'
        if not Config.CrimeTypes[crimeType] then
            lib.notify({type='error', description='Unbekannt: ' .. crimeType})
            return
        end
        lib.notify({type='inform', description='Test: ' .. crimeType})
        LogCrime(crimeType, nil, true)
    end, false)

    RegisterCommand('crimestatus', function()
        lib.notify({
            type        = 'inform',
            duration    = 8000,
            description = ('Init:%s | Admin:%s | Police:%s | Area:%s | Wanted:%d | Decay:%s'):format(
                tostring(crimeState.systemInitialized),
                tostring(crimeState.isAdmin),
                tostring(crimeState.isPoliceNearby),
                crimeState.currentArea,
                GetWantedLevel(),
                tostring(crimeState.decayActive)
            ),
        })
    end, false)

    RegisterCommand('testwitness', function(_, args)
        local crimeType = args[1] or 'ROBBERY'
        lib.notify({type='inform', description='Witness-Test: ' .. crimeType})
        -- Erzwingt vollen Zeuge-Flow (kein force-flag → Zeuge nötig)
        LogCrime(crimeType, cache.coords, false)
    end, false)
end

-- ════════════════════════════════════════════════════════════════════════════════
-- EXPORTS
-- ════════════════════════════════════════════════════════════════════════════════

exports('LogCrime',             LogCrime)
exports('IsCrimeOnCooldown',    IsCrimeOnCooldown)
exports('GetCurrentArea',       GetCurrentArea)
exports('CheckCopsLineOfSight', CheckCopsLineOfSight)
exports('IsDecayActive',        function() return crimeState.decayActive end)
exports('GetWantedLevel',       GetWantedLevel)

-- ════════════════════════════════════════════════════════════════════════════════
print('^2[AIPD | Crime]^7 ✅ Zeuge-basiertes 911-Call-System aktiv')
print('^2[AIPD | Crime]^7 ✅ Zeuge unterbrechen = kein Wanted Level')
print('^2[AIPD | Crime]^7 ✅ Alle Crime-Typen erkannt (Schuss, Diebstahl, Unfall, Einbruch...)')
print('^2[AIPD | Crime]^7 ✅ ox_core only – kein ESX')