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
-- ✅ FIX #27 (1.0.1-alpha): Locale-Loading via ox_lib (alle Notifications i18n)
-- ✅ FIX #28 (1.0.1-alpha): Admin-Block respektiert nun Config.AdminSettings.exemptFromWanted
--                          (vorher: ALLE Crimes für Admins hard-geblockt → kein Zeuge wurde gesucht)
--
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

-- ✅ FIX #31 (1.0.2-alpha): NPC sieht den Crime nur wenn er Sichtlinie hat UND
-- der Crime im Sichtfeld liegt. Vorher: jeder NPC im Radius war "Zeuge" — selbst
-- der NPC der hinter ner Wand stand oder dem Spieler den Rücken zukehrte.
--
-- ✅ FIX #40 (1.0.2-alpha hotfix): FOV-Mathe komplett umgestellt auf Forward-Vector
-- Dot-Product. Vorher: atan2+90 Hack der bei "Crime nördlich von Zeuge" ein angle
-- von 180 statt 0 lieferte → ALLE NPCs die nordwärts schauten wurden rejected.
-- Praktischer Effekt: man fuhr durch Vinewood vorbei an NPCs auf dem Gehweg
-- (die alle nordwärts liefen) und KEINER war Zeuge.
--
-- Außerdem: Default FOV 220° war zu strikt für Drive-By Szenarien.
-- Jetzt 280° default (nur direkt hinter dem NPC = blind), kann aber per Config
-- runtergeschraubt werden für strengere Realismus-Setups.
local witnessRejectStats = {fov = 0, los = 0, lastReset = 0}

local function WitnessCanSee(witnessPed, crimeCoords)
    local cfg = Config.WitnessSystem
    if not cfg or not cfg.requireLineOfSight then return true end
    if not DoesEntityExist(witnessPed) then return false end

    local witnessCoords = GetEntityCoords(witnessPed)

    -- ──── (0) PROXIMITY GRACE — sehr nahe NPCs hören & spüren immer ───────────
    -- ✅ FIX #41 (1.0.2-alpha hotfix2): Innerhalb von X Meter ignoriert man den
    -- FOV-Check komplett. Schuss 3m hinter dir = Mensch dreht sich um. Punkt.
    -- Vorher: NPC der zufällig von dir wegschaute war NICHT-Zeuge auch wenn er
    -- direkt neben dir stand → unrealistisches Gameplay.
    local grace = cfg.proximityGraceDistance or 12.0
    local dx    = crimeCoords.x - witnessCoords.x
    local dy    = crimeCoords.y - witnessCoords.y
    local dz    = crimeCoords.z - witnessCoords.z
    local dist3D = math.sqrt(dx*dx + dy*dy + dz*dz)
    local closeProximity = dist3D <= grace

    -- ──── (a) FIELD OF VIEW — Forward-Vector Dot-Product ──────────────────────
    local fov = cfg.fieldOfView or 320.0
    if fov < 359.0 and not closeProximity then
        local fwd = GetEntityForwardVector(witnessPed)
        local dist2D = math.sqrt(dx*dx + dy*dy)
        if dist2D > 0.01 then
            local dot = (fwd.x * dx + fwd.y * dy) / dist2D
            local cosHalfFov = math.cos(math.rad(fov / 2.0))
            if dot < cosHalfFov then
                witnessRejectStats.fov = witnessRejectStats.fov + 1
                return false
            end
        end
    end

    -- ──── (b) LINE OF SIGHT — World-Geometry-Only Raycast ─────────────────────
    -- flag = 1 → nur World/Buildings/Terrain blockt. Peds, Vehicles, Animals,
    -- Objects NICHT — dadurch blockt das eigene Auto des Spielers die Sichtlinie
    -- zum Spieler-Ped NICHT (wäre sonst false-negative bei jedem Drive-By).
    -- Synchroner Probe damit das Result IM SELBEN FRAME steht und nicht erst
    -- nächsten Tick als "noch nicht fertig" zurückkommt.
    -- ✅ FIX #41: Bei Proximity-Grace (< X m) skippen wir auch den LOS-Check —
    -- so nah dran "hört" der NPC das Crime auch durch eine dünne Wand.
    if not closeProximity then
        local ray = StartExpensiveSynchronousShapeTestLosProbe(
            witnessCoords.x, witnessCoords.y, witnessCoords.z + 1.0,
            crimeCoords.x,   crimeCoords.y,   crimeCoords.z   + 1.0,
            1, witnessPed, 0
        )
        local _, hit = GetShapeTestResult(ray)
        if hit then
            witnessRejectStats.los = witnessRejectStats.los + 1
            return false
        end
    end

    return true
end

local function GetNearbyWitnesses(coords, radius, excludePed)
    local cfg         = Config.WitnessSystem or {}
    local areaType    = crimeState.currentArea
    local phoneChance = PhoneChanceByArea[areaType] or 0.85

    local result = {npcs = {}, players = {}}

    -- ✅ FIX #40: Reset & report Rejection-Stats pro LogCrime-Call
    local startFov, startLos = witnessRejectStats.fov, witnessRejectStats.los

    -- ✅ FIX #44 (1.0.2-alpha hotfix3): Opfer aus Zeugen-Liste rauswerfen.
    -- Der gejackte Fahrer, der geprügelte NPC, der überfahrene NPC ist KEIN Zeuge.
    -- Vorher: das Opfer wurde als nächster Zeuge gepickt, dann ragdollte/starb es,
    -- → "Witness eliminated" Notification obwohl niemand was gemacht hat.
    local excludeId = excludePed and DoesEntityExist(excludePed) and excludePed or nil

    -- NPC-Zeugen
    local peds = GetGamePool('CPed')
    for _, ped in ipairs(peds) do
        if DoesEntityExist(ped)
            and ped ~= excludeId
            and not IsPedAPlayer(ped)
            and not IsPedDeadOrDying(ped, true)
        then
            local pedType = GetPedType(ped)
            -- Keine Polizisten (6), Tiere (27/28)
            if pedType ~= 6 and pedType ~= 27 and pedType ~= 28 then
                local pedCoords = GetEntityCoords(ped)
                local distance  = #(coords - pedCoords)
                if distance <= radius then
                    -- ✅ FIX #31: LOS + FOV Prüfung
                    if WitnessCanSee(ped, coords) then
                        result.npcs[#result.npcs + 1] = {
                            ped          = ped,
                            distance     = distance,
                            hasPhone     = math.random() < phoneChance,
                            awareness    = math.random(60, 100) / 100,
                            callDuration = math.random(
                                cfg.callDurationMin or CallDuration.min,
                                cfg.callDurationMax or CallDuration.max
                            ),
                        }
                    end
                end
            end
        end
    end

    -- ✅ FIX #32 (1.0.2-alpha): Andere Spieler sind NICHT mehr automatisch Zeugen.
    -- Vorher: Tochter/Crew/Freunde standen in der Liste → wurden in FindBestCaller
    -- als Fallback genutzt → riefen die Cops auf den eigenen Daddy/Bruder.
    -- Jetzt: Nur wenn Config.WitnessSystem.playersAsAutoWitnesses = true (default false).
    -- Für "Spieler ruft manuell 911" → kommt später als /call911 Command, separat.
    if cfg.playersAsAutoWitnesses then
        for _, pid in ipairs(GetActivePlayers()) do
            if pid ~= PlayerId() then
                local targetPed = GetPlayerPed(pid)
                if DoesEntityExist(targetPed) and not IsPedDeadOrDying(targetPed, true) then
                    local dist = #(coords - GetEntityCoords(targetPed))
                    if dist <= radius and WitnessCanSee(targetPed, coords) then
                        result.players[#result.players + 1] = {
                            player   = pid,
                            distance = dist,
                            hasPhone = true,
                        }
                    end
                end
            end
        end
    end

    local fovRej = witnessRejectStats.fov - startFov
    local losRej = witnessRejectStats.los - startLos
    Debug(('Witnesses: %d NPC, %d Player | Phone chance: %.0f%% | LOS: %s | FOV: %.0f° | Rejected: %d FOV / %d LOS'):format(
        #result.npcs, #result.players, phoneChance * 100,
        cfg.requireLineOfSight and 'on' or 'off',
        cfg.fieldOfView or 360.0,
        fovRej, losRej
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
-- VEHICLE CO-OCCUPANCY (1.0.2-alpha)
-- ════════════════════════════════════════════════════════════════════════════════
--
-- Wenn der Crime in einem Fahrzeug passiert, sammle die Server-IDs aller
-- Mitfahrer ein. Der Server propagiert dann den Wanted Level auf sie.
--
local function GetVehicleCoOccupantServerIds()
    if not Config.VehicleCoOccupancy or not Config.VehicleCoOccupancy.enabled then return {} end
    if not cache.inVehicle or not DoesEntityExist(cache.vehicle) then return {} end

    local ids   = {}
    local maxSeats = GetVehicleModelNumberOfSeats(GetEntityModel(cache.vehicle))
    -- Seats: -1 = driver, 0..n = passengers
    for seat = -1, maxSeats - 2 do
        local seatPed = GetPedInVehicleSeat(cache.vehicle, seat)
        if seatPed and seatPed ~= 0 and seatPed ~= cache.ped
            and DoesEntityExist(seatPed) and IsPedAPlayer(seatPed)
        then
            local otherPlayer = NetworkGetPlayerIndexFromPed(seatPed)
            if otherPlayer ~= -1 then
                local serverId = GetPlayerServerId(otherPlayer)
                if serverId and serverId > 0 then
                    ids[#ids + 1] = serverId
                end
            end
        end
    end
    return ids
end

-- ════════════════════════════════════════════════════════════════════════════════
-- WITNESS VISUAL TEARDOWN — sicheres Cleanup für Phone-Prop + Blip
-- ════════════════════════════════════════════════════════════════════════════════
local function TeardownWitnessVisuals(visuals)
    if not visuals then return end
    if visuals.phone and DoesEntityExist(visuals.phone) then
        DetachEntity(visuals.phone, true, true)
        DeleteObject(visuals.phone)
    end
    if visuals.blip and DoesBlipExist(visuals.blip) then
        RemoveBlip(visuals.blip)
    end
    if visuals.pulseThreadId then
        visuals.pulseStop = true
    end
    if visuals.callerPed and DoesEntityExist(visuals.callerPed) then
        ClearPedTasks(visuals.callerPed)
        -- ✅ FIX #45 (1.0.2-alpha hotfix4): Mission-Entity-Lock wieder lösen
        -- damit die Engine den NPC wieder normal streamen/despawnen kann.
        -- Sonst hätten wir nach jedem Call leichende Geist-NPCs in der Welt.
        SetBlockingOfNonTemporaryEvents(visuals.callerPed, false)
        SetEntityAsMissionEntity(visuals.callerPed, false, true)
        SetPedAsNoLongerNeeded(visuals.callerPed)
    end
end

-- ════════════════════════════════════════════════════════════════════════════════
-- 911-CALL SEQUENZ — Sichtbar, unterbrechbar, immersiv
-- ════════════════════════════════════════════════════════════════════════════════
--
-- DAS IST DAS HERZSTÜCK:
-- 1. Zeuge schaut den Spieler an (Reaktion)
-- 2. Spawnt sichtbares Handy in der Hand des Zeugen
-- 3. Setzt Blip über den Kopf des Zeugen
-- 4. Spielt Dial-Anim, dann Talk-Anim
-- 5. Erst nach komplettem Call → Wanted Level
-- 6. Wird der Zeuge erledigt → kompletter Teardown, kein Wanted Level
--
-- ════════════════════════════════════════════════════════════════════════════════

local function Execute911CallSequence(caller, crimeType, crimeCoords, crimeLevel, witnessCount)
    local cfg             = Config.WitnessSystem or {}
    local isPlayerWitness = caller.player ~= nil
    local callerPed       = (not isPlayerWitness) and caller.ped or nil
    local callDuration    = caller.callDuration or math.random(
        cfg.callDurationMin or 4000,
        cfg.callDurationMax or 7000
    )
    local reactionDelay   = math.random(
        cfg.reactionMin or 1500,
        cfg.reactionMax or 3500
    )

    -- Co-Occupant Server-IDs JETZT sammeln (bevor wir möglicherweise aussteigen)
    local coOccupants = GetVehicleCoOccupantServerIds()

    local visuals = {
        phone         = nil,
        blip          = nil,
        callerPed     = callerPed,
        pulseStop     = false,
    }

    CreateThread(function()
        -- ✅ FIX #45 (1.0.2-alpha hotfix4): Caller gegen Engine-Despawn pinnen.
        -- Vorher: Engine konnte den Witness-NPC mitten im Call wegcleanen
        -- (Population-Limit, Streaming, neue NPCs spawnen → alte fliegen raus).
        -- → DoesEntityExist = false → "Witness eliminated" obwohl niemand was tat.
        -- Jetzt: NPC ist für die Dauer des Calls mission-locked, kann nicht despawnen.
        -- TeardownWitnessVisuals löst den Lock am Ende wieder.
        if callerPed and DoesEntityExist(callerPed) then
            SetEntityAsMissionEntity(callerPed, true, true)
            SetBlockingOfNonTemporaryEvents(callerPed, true)
            SetPedKeepTask(callerPed, true)
        end

        -- ──────── 1. REAKTIONSPHASE — Zeuge schaut den Spieler an ─────────────
        if callerPed then
            TaskLookAtEntity(callerPed, cache.ped, callDuration + reactionDelay + 2000, 2048, 3)
        end

        Wait(reactionDelay)

        if callerPed and (not DoesEntityExist(callerPed) or IsPedDeadOrDying(callerPed, true)) then
            Debug('Zeuge vor dem Call gestorben')
            TeardownWitnessVisuals(visuals)
            TriggerServerEvent('police:crimeDetectedNoWitness', crimeType, crimeCoords)
            lib.notify({
                type        = 'success',
                description = L('witness_killed_before_call'),
                duration    = 3000,
            })
            return
        end

        -- ──────── 2. HANDY-PROP SPAWNEN (nur für NPCs) ─────────────────────────
        if callerPed and cfg.visiblePhoneCall ~= false then
            local phoneModel = joaat(cfg.phonePropModel or 'prop_npc_phone_02')
            RequestModel(phoneModel)
            local timeout = 0
            while not HasModelLoaded(phoneModel) and timeout < 60 do
                Wait(20); timeout = timeout + 1
            end
            if HasModelLoaded(phoneModel) then
                local pedCoords = GetEntityCoords(callerPed)
                local phoneObj  = CreateObject(phoneModel, pedCoords.x, pedCoords.y, pedCoords.z + 0.2, true, true, false)
                if DoesEntityExist(phoneObj) then
                    -- Bone 28422 = SKEL_R_Hand (rechte Hand)
                    AttachEntityToEntity(phoneObj, callerPed, GetPedBoneIndex(callerPed, 28422),
                        0.0, 0.0, 0.025,   -- offset
                        10.0, 160.0, 0.0,  -- rotation (Handy aufrecht in der Hand)
                        true, true, false, true, 1, true)
                    visuals.phone = phoneObj
                end
                SetModelAsNoLongerNeeded(phoneModel)
            end
        end

        -- ──────── 3. CALLER-BLIP über Kopf des Zeugen ──────────────────────────
        if callerPed and cfg.callerBlip and cfg.callerBlip.enabled then
            local b = AddBlipForEntity(callerPed)
            if DoesBlipExist(b) then
                SetBlipSprite(b,    cfg.callerBlip.sprite or 280)
                SetBlipColour(b,    cfg.callerBlip.color  or 1)
                SetBlipScale(b,     cfg.callerBlip.scale  or 0.8)
                SetBlipAsShortRange(b, cfg.callerBlip.shortRange or false)
                BeginTextCommandSetBlipName("STRING")
                AddTextComponentString("📞 Zeuge ruft 911")
                EndTextCommandSetBlipName(b)
                visuals.blip = b

                -- Pulse-Animation
                if cfg.callerBlip.pulseAlpha then
                    CreateThread(function()
                        while not visuals.pulseStop and DoesBlipExist(b) do
                            SetBlipAlpha(b, 255); Wait(400)
                            SetBlipAlpha(b, 120); Wait(400)
                        end
                    end)
                end
            end
        end

        -- Frühe Spieler-Notification — gibt ihm die Chance einzugreifen
        lib.notify({
            type        = 'warning',
            description = L('witness_dialing'),
            duration    = 2500,
            icon        = 'phone',
        })

        -- ──────── 4. DIAL-ANIM (kurzes Tippen) ─────────────────────────────────
        if callerPed and DoesEntityExist(callerPed) then
            local dialDict = 'cellphone@'
            RequestAnimDict(dialDict)
            local timeout = 0
            while not HasAnimDictLoaded(dialDict) and timeout < 100 do
                Wait(10); timeout = timeout + 1
            end
            if HasAnimDictLoaded(dialDict) then
                -- "cellphone_text_in" — kurze Tipp-Animation
                TaskPlayAnim(callerPed, dialDict, 'cellphone_text_in',
                    8.0, -8.0, 1200, 50, 0, false, false, false)
            end
        end

        Wait(1200)

        -- Check #2 — während des Dialvorgangs
        if callerPed and (not DoesEntityExist(callerPed) or IsPedDeadOrDying(callerPed, true)) then
            Debug('Zeuge WÄHREND des Wählens gestorben')
            TeardownWitnessVisuals(visuals)
            TriggerServerEvent('police:crimeDetectedNoWitness', crimeType, crimeCoords)
            lib.notify({
                type        = 'success',
                description = L('witness_killed_during_call'),
                duration    = 3000,
            })
            return
        end

        -- ──────── 5. TALK-ANIM (Handy am Ohr) ─────────────────────────────────
        if callerPed and DoesEntityExist(callerPed) then
            local talkDict = 'cellphone@'
            if HasAnimDictLoaded(talkDict) then
                TaskPlayAnim(callerPed, talkDict, 'cellphone_call_listen_base',
                    8.0, -8.0, -1, 49, 0, false, false, false)
            end
        end

        -- Warte die Talk-Dauer ab — Spieler kann immer noch eingreifen!
        local remaining = callDuration - 1200
        if remaining > 0 then Wait(remaining) end

        -- ──────── 6. FINAL CHECK — Überlebt der Zeuge den Call? ───────────────
        if callerPed and (not DoesEntityExist(callerPed) or IsPedDeadOrDying(callerPed, true)) then
            Debug('Zeuge WÄHREND des Calls gestorben → kein Wanted Level')
            TeardownWitnessVisuals(visuals)
            TriggerServerEvent('police:crimeDetectedNoWitness', crimeType, crimeCoords)
            lib.notify({
                type        = 'success',
                description = L('witness_killed_during_call'),
                duration    = 3000,
            })
            return
        end

        -- ──────── 7. CALL ERFOLGREICH — Crime an Server melden ────────────────
        Debug(('911-Call abgeschlossen! Melde Verbrechen: %s'):format(crimeType))

        TriggerServerEvent('police:reportCrime', {
            type          = crimeType,
            coords        = crimeCoords,
            level         = crimeLevel,
            witnessCount  = witnessCount,
            crimeTime     = GetGameTimer(),
            callCompleted = true,
            -- ✅ FIX #33 (1.0.2-alpha): Co-Occupants mitliefern damit Server
            -- auch die Beifahrer als wanted markieren kann.
            coOccupants   = coOccupants,
            witness       = {
                distance       = caller.distance or 0,
                isPlayerCaller = isPlayerWitness,
            },
        })

        -- Nostr Logging
        TriggerServerEvent('police:nostr:crime',
            crimeType,
            crimeState.currentArea,
            true
        )

        -- ──────── 8. CLEANUP — Phone+Blip nach kurzer Auslaufzeit weg ─────────
        SetTimeout(2000, function()
            TeardownWitnessVisuals(visuals)
        end)
    end)
end

-- ════════════════════════════════════════════════════════════════════════════════
-- LOG CRIME — Hauptfunktion
-- ════════════════════════════════════════════════════════════════════════════════

function LogCrime(crimeType, coords, force, victimPed)
    if not crimeState.systemInitialized then
        Debug('System noch nicht initialisiert')
        return false
    end

    -- ✅ FIX #28: Nur blocken wenn Admin TATSÄCHLICH exempt ist (Config-Setting respektieren!)
    -- Vorher: jeder Admin → ALLE Crimes geblockt → kein Zeuge wurde je gesucht.
    -- Jetzt: nur wenn Config.AdminSettings.exemptFromWanted = true → blocken.
    -- Sonst: normaler Crime-Flow (Witness → 911-Call → Wanted Level).
    if crimeState.isAdmin and not force
        and Config.AdminSettings
        and Config.AdminSettings.exemptFromWanted
    then
        Debug(('Admin-Verbrechen unterdrückt (exemptFromWanted=true): %s'):format(crimeType))
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

    local witnesses = GetNearbyWitnesses(crimeCoords, radius, victimPed)
    local withPhone = 0
    for _, w in ipairs(witnesses.npcs) do
        if w.hasPhone then withPhone = withPhone + 1 end
    end
    Debug(('LogCrime %s | %d NPCs gefunden | %d mit Telefon | %d Spieler | Area: %s'):format(
        crimeType, #witnesses.npcs, withPhone, #witnesses.players, crimeState.currentArea
    ))
    local caller    = FindBestCaller(witnesses, crimeCoords)

    -- ✅ FIX #42 (1.0.2-alpha hotfix2): Delayed Re-Scan.
    -- Wenn beim ersten Scan kein Zeuge da war, scannen wir nochmal nach 2-3s.
    -- Realistisches Szenario: Schuss fällt → NPCs hören das → laufen zum Tatort →
    -- werden JETZT Zeugen. Vorher: "kein Zeuge im exakten Moment des Crimes" =
    -- never wanted. Jetzt: NPCs die nach der Tat ankommen werden erfasst.
    if not caller then
        local rescans  = Config.WitnessSystem and Config.WitnessSystem.delayedRescans or 2
        local rescanMs = Config.WitnessSystem and Config.WitnessSystem.delayedRescanInterval or 2500
        if rescans > 0 then
            CreateThread(function()
                for attempt = 1, rescans do
                    Wait(rescanMs)
                    -- Crime ist veraltet wenn der Spieler tot/verhaftet ist oder schon Wanted
                    if WantedSystem and WantedSystem.isArrested then return end
                    if WantedSystem and WantedSystem.isDead     then return end
                    local nowWanted = WantedSystem and WantedSystem.level or 0
                    if nowWanted > 0 and nowWanted >= crimeLevel then return end

                    -- Re-Scan mit gleichen Coords (Tatort-Position)
                    local w2 = GetNearbyWitnesses(crimeCoords, radius, victimPed)
                    local c2 = FindBestCaller(w2, crimeCoords)
                    if c2 then
                        Debug(('%s: Re-Scan #%d hat Zeuge gefunden!'):format(crimeType, attempt))
                        local tw = #w2.npcs + #w2.players
                        lib.notify({
                            type        = 'warning',
                            description = L('witness_spotted_you', crimeConfig.description or crimeType),
                            duration    = 3000,
                        })
                        Execute911CallSequence(c2, crimeType, crimeCoords, crimeLevel, tw)
                        return
                    end
                    Debug(('%s: Re-Scan #%d/%d auch leer'):format(crimeType, attempt, rescans))
                end
                -- Alle Re-Scans leer → JETZT erst das "No witnesses" Event/Notif
                TriggerServerEvent('police:crimeDetectedNoWitness', crimeType, crimeCoords)
                TriggerServerEvent('police:nostr:crime', crimeType, crimeState.currentArea, false)
                lib.notify({
                    type        = 'success',
                    description = L('no_witnesses_nearby'),
                    duration    = 2500,
                })
            end)
        else
            -- Re-Scans deaktiviert → altes Verhalten
            TriggerServerEvent('police:crimeDetectedNoWitness', crimeType, crimeCoords)
            TriggerServerEvent('police:nostr:crime', crimeType, crimeState.currentArea, false)
            lib.notify({
                type        = 'success',
                description = L('no_witnesses_nearby'),
                duration    = 2500,
            })
        end
        Debug(('%s: kein Zeuge im ersten Scan, Re-Scan-Loop gestartet'):format(crimeType))
        return false
    end

    -- Zeuge gefunden → 911-Call starten
    local totalWitnesses = #witnesses.npcs + #witnesses.players

    Debug(('%s: Zeuge gefunden (%.0fm) – 911-Call läuft...'):format(crimeType, caller.distance or 0))

    lib.notify({
        type        = 'warning',
        description = L('witness_spotted_you', crimeConfig.description or crimeType),
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

            -- BUG FIX: Do NOT decay while arrested/surrendered.
            -- Race condition: GetWantedLevel() returns >0 in the ~6500ms window between
            -- TriggerServerEvent('police:syncArrest') and lib.callback.await('police:arrestPlayer').
            -- If decay fires here, server state.level hits 0 before arrestPlayer callback
            -- arrives → server rejects arrest (level<=0 && !isJailed) → no jail teleport.
            if WantedSystem and (WantedSystem.isArrested or WantedSystem.isSurrendered) then
                crimeState.decayActive = false
                goto continue
            end

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
                                description = L('wanted_decay_start'),
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
            LogCrime('MURDER_COP', nil, true, victim)
            TriggerServerEvent('police:nostr:copKilled')
        elseif IsPedAPlayer(victim) or (victimType ~= 27 and victimType ~= 28) then
            LogCrime('MURDER', nil, true, victim)
        end
    else
        if victimType == 6 then
            LogCrime('ASSAULT_COP', nil, false, victim)
        elseif IsPedAPlayer(victim) or (victimType ~= 27 and victimType ~= 28) then
            LogCrime('ASSAULT', nil, false, victim)
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
    -- ✅ FIX #34 (1.0.2-alpha): Nur triggern wenn TATSÄCHLICH ein Ziel im Spiel ist.
    -- Vorher: jeder Schuss in die Luft → SHOOTING → 0.9 witnessChance → Wanted Level.
    -- Jetzt: muss aimen auf Entity ODER es muss ein Treffer passiert sein.
    CreateThread(function()
        while true do
            Wait(100)
            if not crimeState.systemInitialized then goto nextShoot end

            if IsPedShooting(cache.ped) and not IsCrimeOnCooldown('SHOOTING') then
                local requiresTarget = Config.CrimeRealism and Config.CrimeRealism.shootingRequiresTarget
                local hasTarget = false

                if requiresTarget then
                    -- (a) Free-aim auf eine Entity?
                    local aiming, aimEntity = GetEntityPlayerIsFreeAimingAt(PlayerId())
                    if aiming and aimEntity and aimEntity ~= 0 and DoesEntityExist(aimEntity) then
                        hasTarget = true
                    end
                    -- (b) Auto-Lock-Ziel? (Konsolen-Style)
                    if not hasTarget then
                        local lockTarget = GetPlayerTargetEntity(PlayerId())
                        if lockTarget and lockTarget ~= 0 then hasTarget = true end
                    end
                    -- (c) Treffer in den letzten paar Frames?
                    if not hasTarget and HasEntityBeenDamagedByEntity then
                        -- gameEventTriggered handelt damage events bereits separat —
                        -- aber wenn eine Entity in 30m getroffen wurde nehmen wir das mit
                        if IsBulletInArea(cache.coords.x, cache.coords.y, cache.coords.z, 25.0, true) then
                            -- Prüfen ob ein NPC in der Nähe getroffen wurde
                            local peds = GetGamePool('CPed')
                            for _, p in ipairs(peds) do
                                if p ~= cache.ped and HasEntityBeenDamagedByEntity(p, cache.ped, 1) then
                                    hasTarget = true
                                    ClearEntityLastDamageEntity(p)
                                    break
                                end
                            end
                        end
                    end
                else
                    hasTarget = true  -- Old behavior wenn Config aus
                end

                if hasTarget then
                    LogCrime('SHOOTING')
                else
                    -- Cooldown trotzdem setzen damit wir nicht jeden Frame neu prüfen
                    crimeState.cooldowns['SHOOTING'] = GetGameTimer() - (Config.CrimeTypes.SHOOTING.cooldown - 2000)
                    Debug('SHOOTING ignoriert: kein Ziel (Schuss in die Luft)')
                end
            end

            ::nextShoot::
        end
    end)

    -- ── BRANDISHING — Waffe gezogen ──────────────────────────────────────────
    -- ✅ FIX #36 (1.0.2-alpha): Nur triggern wenn ein NPC/Cop dich tatsächlich sieht.
    -- Vorher: rein zufällig — auch wenn niemand in der Nähe.
    CreateThread(function()
        while true do
            Wait(1000)
            if not crimeState.systemInitialized or cache.inVehicle then goto nextBrand end

            if IsPedArmed(cache.ped, 4) and not IsCrimeOnCooldown('BRANDISHING') then
                local weapon = GetSelectedPedWeapon(cache.ped)
                if weapon ~= GetHashKey('WEAPON_UNARMED') then
                    local realism = Config.CrimeRealism or {}
                    local requireLOS = realism.brandishingRequiresLOS

                    -- LOS-Check: gibt es einen NPC der mich gerade mit Waffe sieht?
                    local seen = false
                    if requireLOS then
                        -- Cops in der Nähe?
                        if crimeState.isPoliceNearby and CheckCopsLineOfSight() then
                            seen = true
                        else
                            -- Mindestens 1 NPC in 20m mit Sichtlinie?
                            local witnesses = GetNearbyWitnesses(cache.coords, 20.0)
                            seen = #witnesses.npcs > 0
                        end
                    else
                        seen = true
                    end

                    if seen then
                        local chance = crimeState.isPoliceNearby and 0.04 or 0.006
                        if math.random() < chance then
                            LogCrime('BRANDISHING')
                        end
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
    -- ✅ FIX #35 (1.0.2-alpha): SPEEDING braucht jetzt Cop-Sichtlinie.
    -- Auch konfigurierbare Toleranz pro Area-Typ statt fixer "+20".
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

            -- ✅ FIX #35: Konfigurierbare Toleranz pro Area-Typ
            local realism = Config.CrimeRealism or {}
            local tolByArea = realism.speedingTolerance or {}
            local tolerance = tolByArea[area] or 30

            -- ✅ FIX #35: Cop-LOS Check für SPEEDING (verkehrsdelikt → muss gesehen werden)
            local copSees = false
            if realism.speedingRequiresCopLOS then
                copSees = CheckCopsLineOfSight() == true
            end

            -- SPEEDING — erst wenn deutlich über limit UND ein Cop es sieht
            if speed > (limit + tolerance) and not IsCrimeOnCooldown('SPEEDING') then
                if (not realism.speedingRequiresCopLOS) or copSees then
                    LogCrime('SPEEDING')
                end
            end

            -- RECKLESS DRIVING — sehr hohe Geschwindigkeit + Schräglage
            if speed > (limit + tolerance + 20) and not IsCrimeOnCooldown('RECKLESS_DRIVING') then
                local roll = GetEntityRoll(cache.vehicle)
                if math.abs(roll) > 20.0 then
                    if (not realism.recklessRequiresWitness) or copSees or crimeState.isPoliceNearby then
                        LogCrime('RECKLESS_DRIVING')
                    end
                end
            end

            -- HIT AND RUN — wenn ein NPC getroffen wurde
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
                                -- ✅ FIX #44: Überfahrener NPC als Opfer markieren
                                LogCrime('HIT_AND_RUN', nil, false, ped)
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
    -- ✅ FIX #44 (1.0.2-alpha hotfix3): Fahrer des Zielautos als Opfer übergeben
    -- damit er nicht selber als Zeuge gepickt wird (führte zum "Witness eliminated"
    -- Bug — Spieler jackt Fahrer raus, Fahrer ragdollt, "Zeuge eliminiert").
    CreateThread(function()
        while true do
            Wait(500)
            if not crimeState.systemInitialized then goto nextTheft end

            if (IsPedTryingToEnterALockedVehicle(cache.ped) or IsPedJacking(cache.ped))
                and not IsCrimeOnCooldown('VEHICLE_THEFT')
            then
                -- Opfer ermitteln: Fahrer des Fahrzeugs das gerade gejackt/aufgebrochen wird
                local targetVeh = GetVehiclePedIsTryingToEnter(cache.ped)
                if not targetVeh or targetVeh == 0 then
                    targetVeh = GetVehiclePedIsEntering(cache.ped)
                end
                local victimDriver = nil
                if targetVeh and targetVeh ~= 0 and DoesEntityExist(targetVeh) then
                    local drv = GetPedInVehicleSeat(targetVeh, -1)
                    if drv and drv ~= 0 and drv ~= cache.ped and DoesEntityExist(drv) then
                        victimDriver = drv
                    end
                end
                LogCrime('VEHICLE_THEFT', nil, false, victimDriver)
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
                        -- ✅ FIX #44: Nahkampf-Opfer rauswerfen aus Witness-Liste
                        if GetPedType(target) == 6 then
                            LogCrime('ASSAULT_COP', nil, false, target)
                        else
                            LogCrime('ASSAULT', nil, false, target)
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
            lib.notify({type='error', description=L('unknown_crime', crimeType)})
            return
        end
        lib.notify({type='inform', description=L('testing_crime', crimeType)})
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
        lib.notify({type='inform', description=L('testing_crime', crimeType)})
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