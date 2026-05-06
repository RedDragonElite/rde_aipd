---@diagnostic disable: undefined-global, missing-parameter
-- Version: 1.0.1-alpha
-- ✅ FIX #13: lib.onCache('ped') für echten Spawn-Detection
--             ox_core Character Selection wird jetzt korrekt abgewartet
-- ✅ RDE SYNC PATTERN: Broadcast event handlers für alle player states
-- ✅ RDE SYNC PATTERN: Initial sync beim Join für late-joiners
-- ✅ FIX #27 (1.0.1-alpha): Locale-Loading via ox_lib (alle Notifications i18n)

-- ============================================================================
-- LOCALE LOADER (FIX #27)
-- ============================================================================
local Locale = lib.load('locales.' .. GetConvar('ox:locale', 'en')) or {}
local function L(key, ...)
    local s = Locale[key]
    if not s then return key end
    if select('#', ...) > 0 then return s:format(...) end
    return s
end

-- ============================================================================
-- CACHE SYSTEM
-- ============================================================================

-- HINWEIS: Diese lokale 'cache' Variable existiert NEBEN ox_lib's globalem 'cache'.
-- ox_lib's cache wird per lib.onCache() überwacht (FIX #13).
-- Unsere lokale cache wird für Koordinaten/Fahrzeug etc. weitergenutzt.
local cache = {
    ped = 0,
    coords = vector3(0, 0, 0),
    vehicle = 0,
    inVehicle = false,
    isAlive = true
}

local function UpdateCache()
    cache.ped = PlayerPedId()
    if DoesEntityExist(cache.ped) then
        cache.coords = GetEntityCoords(cache.ped)
        cache.vehicle = GetVehiclePedIsIn(cache.ped, false)
        cache.inVehicle = cache.vehicle ~= 0
        cache.isAlive = not IsEntityDead(cache.ped)
    end
end

CreateThread(function()
    while true do
        UpdateCache()
        Wait(500)
    end
end)

-- ============================================================================
-- ✅ FIX #13: SPAWN DETECTION via lib.onCache('ped')
-- lib.onCache feuert wenn ox_lib's interner cache.ped sich ändert — das passiert
-- NACH der Character Selection, wenn der Spieler seinen echten Ped bekommt.
-- NativeCheck (IsScreenFadedOut / NetworkIsPlayerActive) war unzuverlässig weil
-- der Screen während des ox_core Spawn-Menüs NICHT gefadet ist.
-- ============================================================================

local playerHasPed = false

lib.onCache('ped', function(ped)
    if ped and ped ~= 0 and DoesEntityExist(ped) then
        playerHasPed = true
        UpdateCache()
    else
        playerHasPed = false
    end
end)

local function WaitForRealPed()
    -- Schritt 1: Warte bis ox_lib einen echten Ped meldet (nach Character Selection)
    local timeout = GetGameTimer() + 60000
    while not playerHasPed and GetGameTimer() < timeout do
        Wait(500)
    end

    if not playerHasPed then
        -- Fallback: direkt prüfen falls lib.onCache schon vor unserem Listener feuerte
        local ped = PlayerPedId()
        if DoesEntityExist(ped) and not IsEntityDead(ped) then
            playerHasPed = true
            UpdateCache()
        else
            print('^3[AIPD]^7 WaitForRealPed: timeout — continuing anyway')
            return false
        end
    end

    -- Schritt 2: Buffer damit ox_core seine Spawn-Sequenz abschließt
    -- (Teleport zur Spawn-Location, Fadein, etc.)
    Wait(3000)
    UpdateCache()

    print('^2[AIPD]^7 WaitForRealPed: ped confirmed, proceeding with init')
    return true
end

-- ============================================================================
-- WANTED SYSTEM
-- ============================================================================

local WantedSystem = {
    level = 0,
    isArrested = false,
    isDead = false,
    isSurrendered = false,
    isJailed = false,
    jailTime = 0,
    jailTimerActive = false,
    pursuingUnits = {},
    policeActive = false,
    lastSpawnTime = 0,
    updateInterval = 500,
    cleanupInterval = 10000,
    lastCleanup = 0,
    systemReady = false,
    lastSeenByCop = 0,
    decayActive = false,
    copsCanSeePlayer = false
}

-- ✅ FIX #18: Forward-Deklarationen damit State-Bag- und Broadcast-Handler
-- die Prison-Funktionen referenzieren können (Lua: locals existieren ab Deklarations-Zeile).
local Prison = {}
local jailTimerGen = 0
local ensureRunningInProgress = false

local function Debug(...)
    if Config.Debug then
        print('^3[AIPD | Client]^7', ...)
    end
end

local function Notify(data)
    if data and type(data) == "table" then
        lib.notify(data)
    end
end

-- ============================================================================
-- LINE OF SIGHT SYSTEM
-- ============================================================================

local function HasLineOfSight(witnessCoords, targetCoords, maxDistance)
    maxDistance = maxDistance or 100.0
    if #(witnessCoords - targetCoords) > maxDistance then return false end
    local raycast = StartShapeTestRay(
        witnessCoords.x, witnessCoords.y, witnessCoords.z + 1.0,
        targetCoords.x, targetCoords.y, targetCoords.z + 1.0,
        -1, cache.ped, 0
    )
    local _, hit, _, _, entityHit = GetShapeTestResult(raycast)
    if hit and entityHit ~= cache.ped then return false end
    return true
end

local function CopCanSeePlayer(copPed, playerPed, maxDistance)
    if not DoesEntityExist(copPed) or not DoesEntityExist(playerPed) then return false end
    local copCoords    = GetEntityCoords(copPed)
    local playerCoords = GetEntityCoords(playerPed)
    local distance     = #(copCoords - playerCoords)
    if distance > (maxDistance or 100.0) then return false end
    if not HasLineOfSight(copCoords, playerCoords, maxDistance) then return false end
    local copHeading    = GetEntityHeading(copPed)
    local angleToPlayer = math.deg(math.atan2(playerCoords.y - copCoords.y, playerCoords.x - copCoords.x))
    local angleDiff     = math.abs(copHeading - angleToPlayer)
    if angleDiff > 180 then angleDiff = 360 - angleDiff end
    if angleDiff < 120 then return true, distance end
    return false
end

local function CheckCopsLineOfSight()
    if WantedSystem.level == 0 then return false end
    for _, unit in ipairs(WantedSystem.pursuingUnits) do
        if unit and DoesEntityExist(unit.ped) then
            local canSee, distance = CopCanSeePlayer(unit.ped, cache.ped, 150.0)
            if canSee then return true, unit.ped, distance end
        end
    end
    local peds = GetGamePool('CPed')
    for _, ped in ipairs(peds) do
        if DoesEntityExist(ped) and not IsPedAPlayer(ped) and GetPedType(ped) == 6 then
            local canSee, distance = CopCanSeePlayer(ped, cache.ped, 100.0)
            if canSee then return true, ped, distance end
        end
    end
    return false
end

-- ============================================================================
-- DECAY SYSTEM
-- ============================================================================

-- ✅ FIX #1: Decay System ENTFERNT aus main.lua
-- Das Decay läuft NUR noch über crime.lua → TriggerServerEvent('police:decayWantedLevel')
-- main.lua's Version war client-seitig und hat den Server-State desynchronisiert.
-- Die LOS-Tracking-Variablen bleiben für die Police Unit AI erhalten.

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

local function LoadAnimDict(dict)
    if not dict or type(dict) ~= "string" then return false end
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 2000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(0) end
    return HasAnimDictLoaded(dict)
end

local function LoadModel(model)
    if not model then return false end
    local hash = type(model) == 'string' and joaat(model) or model
    if HasModelLoaded(hash) then return true end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    return HasModelLoaded(hash)
end

local function GetClosestRoad(coords, radius)
    if not coords then return false, nil, 0 end
    local retval, pos, heading = GetClosestVehicleNodeWithHeading(
        coords.x, coords.y, coords.z, 1, radius or 3.0, 0
    )
    return retval, pos and vec3(pos.x, pos.y, pos.z) or nil, heading or 0
end

-- ============================================================================
-- STATE BAG INTEGRATION
-- ============================================================================

if Config.UseStateBags then
    local function OnStateBagChange(bagName, key, value)
        if not bagName or not bagName:find('entity:') then return end
        local entity = GetEntityFromStateBagName(bagName)
        if not entity or entity ~= cache.ped then return end
        if key == 'wantedLevel' then
            -- ✅ FIX: SetLevel() aufrufen statt nur die Variable setzen!
            -- Nur SetLevel() startet StartPoliceSystem() → ohne das spawnen keine Cops
            if value ~= WantedSystem.level then
                WantedSystem.SetLevel(value)
            end
        elseif key == 'isJailed' then
            local wasJailed = WantedSystem.isJailed
            WantedSystem.isJailed = value
            -- ✅ FIX #18: Auto-Start Timer wenn Server uns als jailed meldet
            -- aber lokal noch kein Timer läuft (Race-Sicherung)
            if value and not wasJailed and Prison and Prison.EnsureRunning then
                Prison.EnsureRunning()
            end
        elseif key == 'jailTime' then
            WantedSystem.jailTime = value
            -- Falls Timer-Start verpasst wurde: nachholen sobald Server eine Zeit broadcastet
            if WantedSystem.isJailed and value and value > 0
                and Prison and Prison.EnsureRunning
            then
                Prison.EnsureRunning()
            end
        end
    end
    AddStateBagChangeHandler('wantedLevel', nil, OnStateBagChange)
    AddStateBagChangeHandler('isJailed',    nil, OnStateBagChange)
    AddStateBagChangeHandler('jailTime',    nil, OnStateBagChange)
end

-- ============================================================================
-- UI MANAGEMENT
-- ============================================================================

UI = {}
local nuiReady   = false
local nuiPending = nil

CreateThread(function()
    Wait(3000)
    nuiReady = true
    Debug('NUI ready')
    if nuiPending and nuiPending > 0 then
        SendNUIMessage({type='updateWantedLevel', level=nuiPending, config=Config.WantedLevels and Config.WantedLevels[nuiPending] or {}})
        nuiPending = nil
    end
end)

function UI.UpdateWantedLevel(level)
    if not level then return end
    if not nuiReady then nuiPending = level; return end
    SendNUIMessage({type='updateWantedLevel', level=level, config=Config.WantedLevels and Config.WantedLevels[level] or {}})
end

function UI.HideWantedLevel()
    if not nuiReady then return end
    SendNUIMessage({type='hideWantedUI'})
end

function UI.Reset()
    if not nuiReady then return end
    SendNUIMessage({type='forceReset'})
    Wait(50)
    UI.HideWantedLevel()
end

function UI.DrawJailTimer(time)
    if not time or time <= 0 then return end
    DrawRect(0.5, 0.05, 0.18,  0.05,  0,   0,   0,   220)
    DrawRect(0.5, 0.05, 0.182, 0.052, 220, 38,  38,  255)
    DrawRect(0.5, 0.05, 0.18,  0.05,  0,   0,   0,   220)
    SetTextScale(0.45, 0.45)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 255)
    SetTextEntry("STRING")
    SetTextCentre(1)
    SetTextDropShadow()
    AddTextComponentString(('⏱️ Jail Time: %dm %ds'):format(math.floor(time / 60), time % 60))
    DrawText(0.5, 0.038)
end

-- ============================================================================
-- SPAWN SYSTEM
-- ============================================================================

local Spawner = {}

function Spawner.GetSpawnPoints(coords, count, maxDistance)
    if not coords or not count or count <= 0 or not maxDistance then return {} end
    local points = {}
    local attempts = 0
    local maxAttempts = count * 4
    local minDistance = 150.0
    for angle = 0, 359, 30 do
        if #points >= count or attempts >= maxAttempts then break end
        local rad = math.rad(angle)
        for dist = minDistance, maxDistance, 75 do
            if #points >= count or attempts >= maxAttempts then break end
            attempts = attempts + 1
            local x = coords.x + math.cos(rad) * dist
            local y = coords.y + math.sin(rad) * dist
            local success, pos, heading = GetClosestRoad(vec3(x, y, coords.z))
            if success and pos then
                local actualDist = #(coords - pos)
                if actualDist >= minDistance and actualDist <= maxDistance then
                    points[#points + 1] = {coords=pos, heading=heading, distance=actualDist}
                end
            end
        end
    end
    return points
end

function Spawner.PreloadModels(models)
    if not models or type(models) ~= "table" then return false end
    local toLoad = {}
    if models.peds    then for _, m in ipairs(models.peds)    do toLoad[#toLoad+1] = joaat(m) end end
    if models.vehicles then for _, m in ipairs(models.vehicles) do toLoad[#toLoad+1] = joaat(m) end end
    for _, hash in ipairs(toLoad) do if not LoadModel(hash) then return false end end
    return true
end

function Spawner.ReleaseModels(models)
    if not models or type(models) ~= "table" then return end
    if models.peds    then for _, m in ipairs(models.peds)    do SetModelAsNoLongerNeeded(joaat(m)) end end
    if models.vehicles then for _, m in ipairs(models.vehicles) do SetModelAsNoLongerNeeded(joaat(m)) end end
end

-- ============================================================================
-- POLICE UNIT MANAGEMENT
-- ============================================================================

local Police = {}

function Police.SpawnUnit(spawnPoint, config, level)
    if not spawnPoint or not config or not level then return false end
    local pedModel = config.models[math.random(#config.models)]
    local vehModel = config.vehicles[math.random(#config.vehicles)]
    local vehicle = CreateVehicle(joaat(vehModel),
        spawnPoint.coords.x, spawnPoint.coords.y, spawnPoint.coords.z,
        spawnPoint.heading, true, true)
    if not DoesEntityExist(vehicle) then return false end
    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleOnGroundProperly(vehicle)
    SetVehicleEngineOn(vehicle, true, true, false)
    SetVehicleSiren(vehicle, true)
    SetVehicleDoorsLocked(vehicle, 1)
    SetVehicleNeedsToBeHotwired(vehicle, false)
    local chaseSpeed = (config.chaseSpeed or 25.0) / 3.6
    ModifyVehicleTopSpeed(vehicle, chaseSpeed)
    SetEntityMaxSpeed(vehicle, chaseSpeed + 2.0)
    local ped = CreatePed(4, joaat(pedModel),
        spawnPoint.coords.x, spawnPoint.coords.y, spawnPoint.coords.z,
        spawnPoint.heading, true, true)
    if not DoesEntityExist(ped) then DeleteEntity(vehicle); return false end
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 46, true)
    SetPedCombatAttributes(ped, 5, true)
    SetPedCombatAttributes(ped, 0, true)
    SetPedCombatAttributes(ped, 1, true)
    SetPedCombatAttributes(ped, 2, true)
    SetPedCombatAttributes(ped, 3, true)
    SetPedCombatAttributes(ped, 52, true)
    SetPedRelationshipGroupHash(ped, joaat('COP'))
    SetPedAccuracy(ped, config.accuracy or 25)
    SetPedArmour(ped, config.armor or 0)
    SetPedCanSwitchWeapon(ped, true)
    SetPedAsCop(ped, true)
    SetPedCombatRange(ped, 2)
    SetPedCombatMovement(ped, 2)
    if config.useCovers then SetPedConfigFlag(ped, 50, true) end
    SetDriverAbility(ped, 100.0)
    SetDriverAggressiveness(ped, 100.0)
    local weapon = config.weapons[math.random(#config.weapons)]
    if weapon then
        GiveWeaponToPed(ped, joaat(weapon), 250, false, true)
        SetCurrentPedWeapon(ped, joaat(weapon), true)
    end
    SetPedIntoVehicle(ped, vehicle, -1)
    SetDriverAbility(ped, 100.0)
    SetDriverAggressiveness(ped, 100.0)
    SetTaskVehicleChaseBehaviorFlag(ped, 0, true)
    SetTaskVehicleChaseBehaviorFlag(ped, 1, true)
    SetTaskVehicleChaseBehaviorFlag(ped, 2, true)
    SetTaskVehicleChaseBehaviorFlag(ped, 3, true)
    local blip = AddBlipForEntity(ped)
    SetBlipSprite(blip, 56)
    SetBlipColour(blip, 3)
    SetBlipScale(blip, 0.7)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Police Unit")
    EndTextCommandSetBlipName(blip)
    CreateThread(function()
        while DoesBlipExist(blip) do
            SetBlipColour(blip, 1); Wait(500)
            SetBlipColour(blip, 3); Wait(500)
        end
    end)
    WantedSystem.pursuingUnits[#WantedSystem.pursuingUnits + 1] = {
        ped=ped, vehicle=vehicle, blip=blip, config=config, level=level,
        state='pursuing', lastUpdate=GetGameTimer(), spawnTime=GetGameTimer(),
        lastTackle=0, lastPIT=0, lastRoadblock=0, lastStateChange=GetGameTimer(),
        draggingOut=false, hasLOS=false, lastLOSTime=0
    }
    Debug(('Spawned unit at %.0fm'):format(spawnPoint.distance))
    return true
end

local function PlayerIsArmed()
    local _, weapon = GetCurrentPedWeapon(cache.ped, true)
    if not weapon or weapon == joaat('WEAPON_UNARMED') then return false end
    return true
end

function Police.UpdateBehavior(unit)
    if not unit or not DoesEntityExist(unit.ped) or IsEntityDead(unit.ped) then return false end
    local pedCoords   = GetEntityCoords(unit.ped)
    local distance    = #(cache.coords - pedCoords)
    local playerInVeh = cache.inVehicle
    local pedInVeh    = IsPedInAnyVehicle(unit.ped, false)
    local playerVeh   = cache.vehicle
    local now         = GetGameTimer()
    if distance > (Config.Optimization.cullDistance or 600.0) then Police.TeleportUnit(unit); return true end
    local hasLOS = CopCanSeePlayer(unit.ped, cache.ped, 150.0)
    unit.hasLOS = hasLOS
    if hasLOS then
        unit.lastLOSTime           = now
        WantedSystem.lastSeenByCop = now
        WantedSystem.decayActive   = false
    end
    if distance < (unit.config.arrestDistance or 2.5) and WantedSystem.isSurrendered then
        if unit.state ~= 'arresting' then
            unit.state = 'arresting'
            CreateThread(function() Police.AttemptArrest(unit.ped) end)
        end
        return true
    end
    if pedInVeh then
        local copVeh = GetVehiclePedIsIn(unit.ped, false)
        if playerInVeh and DoesEntityExist(playerVeh) then
            local playerSpeed = GetEntitySpeed(playerVeh) * 3.6
            if distance < 15.0 and playerSpeed > 30 and (not unit.lastPIT or (now - unit.lastPIT) > 8000) then
                unit.lastPIT = now
                local angleDiff = math.abs(GetEntityHeading(playerVeh) - GetEntityHeading(copVeh))
                if (angleDiff > 70 and angleDiff < 110) or (angleDiff > 250 and angleDiff < 290) then
                    TaskVehicleTempAction(unit.ped, copVeh, 6, 2000)
                    CreateThread(function()
                        Wait(500)
                        local fwd = GetEntityForwardVector(copVeh)
                        ApplyForceToEntity(playerVeh, 1, fwd.x*25.0, fwd.y*25.0, 0, 0,0,0, 0, false, true, true, true, true)
                    end)
                end
            end
            if distance > 80.0 and distance < 200.0 and (not unit.lastRoadblock or (now - unit.lastRoadblock) > 20000) then
                unit.lastRoadblock = now
                Police.CreateRoadblock(unit)
            end
            if distance > 30.0 and distance < 80.0 and math.random() < 0.3 then
                Police.FlankPlayer(unit, copVeh)
            else
                TaskVehicleChase(unit.ped, cache.ped)
                SetDriverAbility(unit.ped, 100.0)
                SetDriverAggressiveness(unit.ped, 100.0)
                if distance > 50.0 then
                    -- ✅ FIX #25: Moderater Speed-Boost statt 999 (unrealistisch)
                    ModifyVehicleTopSpeed(copVeh, 1.3)
                    SetVehicleEnginePowerMultiplier(copVeh, 2.0)
                end
            end
            unit.state = 'pursuing_vehicle'
        elseif not playerInVeh then
            if distance < 25.0 and unit.state ~= 'exiting' then
                unit.state = 'exiting'; unit.lastStateChange = now
                TaskLeaveVehicle(unit.ped, copVeh, 256)
            elseif distance >= 25.0 then
                unit.state = 'pursuing'
                TaskVehicleDriveToCoord(unit.ped, copVeh, cache.coords.x, cache.coords.y, cache.coords.z, 35.0, 0, GetEntityModel(copVeh), 262656, 5.0, true)
                SetDriverAbility(unit.ped, 100.0); SetDriverAggressiveness(unit.ped, 100.0)
            end
        end
        Police.MaintainVehicle(copVeh)
    else
        if unit.state == 'exiting' and (now - unit.lastStateChange) > 2000 then unit.state = 'on_foot' end
        if unit.state == 'on_foot' or unit.state == 'exiting' then
            if playerInVeh and DoesEntityExist(playerVeh) then
                if distance < 4.0 and GetEntitySpeed(playerVeh)*3.6 < 15.0 then
                    if not unit.draggingOut then
                        unit.draggingOut = true
                        CreateThread(function()
                            Police.DragPlayerFromVehicle(unit.ped, cache.ped, playerVeh)
                            Wait(3000); unit.draggingOut = false
                        end)
                    end
                else
                    TaskGoToEntity(unit.ped, playerVeh, -1, 3.0, 4.0, 0, 0)
                    SetPedMoveRateOverride(unit.ped, 2.0)
                end
            else
                local playerRunning = IsPedRunning(cache.ped) or IsPedSprinting(cache.ped)
                local playerArmed   = PlayerIsArmed()
                if playerArmed and distance < (unit.config.combatRange or 50.0) then
                    if not IsPedInCombat(unit.ped, cache.ped) then
                        TaskCombatPed(unit.ped, cache.ped, 0, 16)
                        SetPedCombatRange(unit.ped, 2); SetPedCombatMovement(unit.ped, 2)
                    end
                    unit.state = 'combat'
                elseif distance < 5.0 and playerRunning and not WantedSystem.isSurrendered then
                    if Police.TryTackle(unit) then
                        CreateThread(function()
                            Wait(2000)
                            if IsPedRagdoll(cache.ped) then Wait(1500); Police.AttemptArrest(unit.ped) end
                        end)
                    end
                elseif distance < (unit.config.arrestDistance or 2.5) and not playerRunning then
                    CreateThread(function() Police.AttemptArrest(unit.ped) end)
                elseif unit.config.shootUnarmed and distance > 5.0 and distance < (unit.config.combatRange or 15.0) then
                    if not IsPedInCombat(unit.ped, cache.ped) then
                        TaskCombatPed(unit.ped, cache.ped, 0, 16); SetPedCombatRange(unit.ped, 2)
                    end
                else
                    if not IsPedInCombat(unit.ped, cache.ped) then
                        TaskGoToEntity(unit.ped, cache.ped, -1, unit.config.arrestDistance or 2.5, 3.0, 0, 0)
                        SetPedMoveRateOverride(unit.ped, 1.5)
                        if distance < 20.0 and math.random() < 0.01 then
                            PlayPedAmbientSpeechNative(unit.ped, 'GENERIC_CURSE_MED', 'SPEECH_PARAMS_FORCE_SHOUTED')
                        end
                    end
                end
            end
        end
    end
    return true
end

function Police.DragPlayerFromVehicle(copPed, playerPed, vehicle)
    if not DoesEntityExist(copPed) or not DoesEntityExist(playerPed) or not DoesEntityExist(vehicle) then return end
    local doorPos = GetWorldPositionOfEntityBone(vehicle, GetEntityBoneIndexByName(vehicle, 'door_dside_f'))
    TaskGoToCoordAnyMeans(copPed, doorPos.x, doorPos.y, doorPos.z, 3.0, 0, 0, 786603, 0xbf800000)
    Wait(1500)
    SetVehicleDoorOpen(vehicle, 0, false, false); Wait(500)
    if LoadAnimDict('mp_arresting') then
        TaskPlayAnim(copPed, 'mp_arresting', 'a_uncuff', 8.0,-8.0, 2000, 0, 0, false, false, false)
    end
    TaskLeaveVehicle(playerPed, vehicle, 256)
    SetPedToRagdoll(playerPed, 2000, 2000, 0, true, true, false)
    Wait(1000)
    local pc = GetEntityCoords(playerPed)
    TaskGoToCoordAnyMeans(copPed, pc.x, pc.y, pc.z, 2.0, 0, 0, 786603, 0xbf800000)
    Wait(1500)
    Police.AttemptArrest(copPed)
    Notify({type='error', description=L('dragged_from_vehicle'), duration=3000})
end

function Police.CreateRoadblock(unit)
    if not unit or not DoesEntityExist(unit.vehicle) then return end
    local vel = GetEntityVelocity(cache.vehicle)
    local ahead = cache.coords + (vel * 5.0)
    local success, roadPos, heading = GetClosestRoad(ahead, 50.0)
    if not success or not roadPos then return end
    TaskVehicleDriveToCoord(unit.ped, unit.vehicle, roadPos.x, roadPos.y, roadPos.z, 50.0, 0, GetEntityModel(unit.vehicle), 4, 10.0, true)
    CreateThread(function()
        Wait(5000)
        if DoesEntityExist(unit.vehicle) then
            SetEntityHeading(unit.vehicle, heading + 90.0)
            SetVehicleOnGroundProperly(unit.vehicle)
            TaskLeaveVehicle(unit.ped, unit.vehicle, 0)
        end
    end)
end

function Police.FlankPlayer(unit, vehicle)
    if not DoesEntityExist(vehicle) then return end
    local fa = GetEntityHeading(cache.vehicle) + (math.random(0,1)==0 and 90 or -90)
    local rad = math.rad(fa)
    local fp = vec3(cache.coords.x + math.cos(rad)*40.0, cache.coords.y + math.sin(rad)*40.0, cache.coords.z)
    TaskVehicleDriveToCoord(unit.ped, vehicle, fp.x, fp.y, fp.z, 45.0, 0, GetEntityModel(vehicle), 262656, 5.0, true)
end

function Police.TryTackle(unit)
    if not unit then return false end
    local now = GetGameTimer()
    -- 10s Cooldown zwischen Tackle-Versuchen (wie original)
    if unit.lastTackle and (now - unit.lastTackle) < 10000 then return false end
    local playerPed = cache.ped
    -- Nicht tacklen wenn Spieler bereits am Boden liegt oder aufsteht
    if IsPedRagdoll(playerPed) or IsPedGettingUp(playerPed) then return false end
    if not DoesEntityExist(unit.ped) or IsPedDeadOrDying(unit.ped, true) then return false end
    -- Wahrscheinlichkeit aus Config (30% Basis wie original, skaliert per Level)
    local sc = unit.config.tackleProbability or 0.30
    if math.random(100) > (sc * 100) then return false end
    unit.lastTackle = now
    -- Richtungsvektor Cop → Spieler (wie original AttemptTackle)
    local playerCoords = GetEntityCoords(playerPed)
    local copCoords    = GetEntityCoords(unit.ped)
    local dx           = copCoords.x - playerCoords.x
    local dy           = copCoords.y - playerCoords.y
    local distance     = math.sqrt(dx * dx + dy * dy)
    local direction    = vector3(
        distance > 0 and (dx / distance) or 0.0,
        distance > 0 and (dy / distance) or 0.0,
        0.0
    )
    -- Zufällige Ragdoll-Dauer 3–7s (wie original)
    local playerRagdollDuration = math.random(3000, 7000)
    -- Spieler zu Boden bringen
    SetPedToRagdollWithFall(playerPed,
        playerRagdollDuration, playerRagdollDuration,
        0, direction,
        10.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
    )
    -- Cop fällt auch kurz
    SetPedToRagdollWithFall(unit.ped,
        3000, 3000,
        0, direction,
        10.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
    )
    -- Spieler fliegt etwas weiter weg (wie original)
    ApplyForceToEntity(playerPed, 1,
        direction.x * 5.0, direction.y * 5.0, 0.0,
        0.0, 0.0, 0.0,
        1, false, true, true, true, true
    )
    -- Server-Sync + Sound
    TriggerServerEvent('police:syncTackle', GetPlayerServerId(PlayerId()), direction)
    PlaySoundFrontend(-1, "TACKLE", "PLAYER_TACKLE_SOUNDSET", 1)
    Notify({type='error', description=L('tackled'), duration=3000})
    Debug(('Tackle! Prob: %.0f%% | Dist: %.1fm | Duration: %dms'):format(sc*100, distance, playerRagdollDuration))
    return true
end

function Police.TeleportUnit(unit)
    if not unit or not DoesEntityExist(unit.vehicle) then return end
    local angle = math.random() * 2.0 * math.pi
    local dist  = math.random(250, 350)
    local x = cache.coords.x + math.cos(angle)*dist
    local y = cache.coords.y + math.sin(angle)*dist
    local success, pos, heading = GetClosestRoad(vec3(x, y, cache.coords.z))
    if success and pos then
        SetEntityCoords(unit.vehicle, pos.x, pos.y, pos.z, false, false, false, true)
        SetEntityHeading(unit.vehicle, heading)
        SetVehicleOnGroundProperly(unit.vehicle)
        unit.state = 'pursuing'
    end
end

function Police.MaintainVehicle(vehicle)
    if not DoesEntityExist(vehicle) then return end
    if GetVehicleBodyHealth(vehicle) < 500 or GetVehicleEngineHealth(vehicle) < 500 then
        SetVehicleFixed(vehicle); SetVehicleEngineHealth(vehicle, 1000.0); SetVehicleBodyHealth(vehicle, 1000.0)
    end
    if not GetIsVehicleEngineRunning(vehicle) then SetVehicleEngineOn(vehicle, true, true, false) end
end

function Police.AttemptArrest(policePed)
    if WantedSystem.isArrested or WantedSystem.isDead or cache.inVehicle then return end
    WantedSystem.isSurrendered = true
    WantedSystem.isArrested    = true
    local policeNetId = DoesEntityExist(policePed) and NetworkGetNetworkIdFromEntity(policePed) or 0
    TriggerServerEvent('police:syncArrest', GetPlayerServerId(PlayerId()), policeNetId)
    Wait(4500)
    FreezeEntityPosition(cache.ped, false)
    UI.Reset()
    DoScreenFadeOut(2000); Wait(2000)
    Police.ClearAllUnits()
    -- jailTime BEVOR level=0 berechnen sonst kennt der Lookup das Level nicht mehr
    local jailTime = 60
    if WantedSystem.level > 0 and Config.WantedLevels and Config.WantedLevels[WantedSystem.level] then
        jailTime = Config.WantedLevels[WantedSystem.level].time or 60
    end
    WantedSystem.level = 0

    -- ✅ FIX #16: Server-Antwort prüfen + KEIN eigener FadeIn mehr.
    -- Vorher: lib.callback.await → DoScreenFadeIn(2000) hat mit dem teleportToJail-Handler-Fade
    -- gerace't → Spieler hat sich kurz an Originalposition gesehen oder Teleport flackerte.
    -- Jetzt: teleportToJail-Handler ist Single Source of Truth für Visuals/Timer/Notify.
    local ok = lib.callback.await('police:arrestPlayer', false, jailTime, math.random(#Config.Prison.cells))

    if not ok then
        -- Server hat Arrest abgelehnt (z.B. wanted level wurde grade auf 0 gesetzt).
        -- Spieler darf nicht mit schwarzem Screen hängenbleiben.
        Debug('AttemptArrest: server rejected arrest — restoring state')
        WantedSystem.isArrested    = false
        WantedSystem.isSurrendered = false
        DoScreenFadeIn(1000)
        Notify({type='error', description=L('arrest_cancelled'), duration=3000})
        return
    end

    -- Safety-Net: falls police:teleportToJail aus irgendeinem Grund nicht ankommt,
    -- nicht ewig im Schwarzbild stecken bleiben.
    CreateThread(function()
        local timeout = GetGameTimer() + 8000
        while GetGameTimer() < timeout do
            Wait(200)
            if WantedSystem.isJailed then return end -- handler hat übernommen, alles gut
        end
        Debug('AttemptArrest safety net: teleportToJail event did not arrive — recovering')
        WantedSystem.isArrested = false
        DoScreenFadeIn(1500)
        Notify({type='error', description=L('connection_issue'), duration=5000})
    end)
end

function Police.ClearAllUnits()
    local units = WantedSystem.pursuingUnits
    WantedSystem.pursuingUnits = {}
    WantedSystem.policeActive  = false
    -- ✅ FIX #26: collectgarbage('collect') entfernt — verursacht Micro-Stutters in FiveM
    -- Sanfter Despawn: Cops steigen ins Auto und fahren weg, DANN löschen
    CreateThread(function()
        for _, unit in ipairs(units) do
            if unit then
                if unit.blip and DoesBlipExist(unit.blip) then RemoveBlip(unit.blip) end
                local ped     = unit.ped
                local vehicle = unit.vehicle
                if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true)
                    and DoesEntityExist(vehicle)
                then
                    -- Tasks clearen + ins Fahrzeug steigen lassen
                    ClearPedTasks(ped)
                    local inVeh = GetVehiclePedIsIn(ped, false)
                    if inVeh == 0 then
                        TaskEnterVehicle(ped, vehicle, 8000, -1, 2.0, 1, 0)
                        local waited = 0
                        while waited < 8000 do
                            Wait(500); waited = waited + 500
                            if not DoesEntityExist(ped) then break end
                            if GetVehiclePedIsIn(ped, false) == vehicle then break end
                        end
                    end
                    -- Wegfahren sobald im Auto
                    if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true)
                        and GetVehiclePedIsIn(ped, false) == vehicle
                    then
                        local angle  = math.rad(math.random(0, 359))
                        local target = cache.coords + vector3(
                            math.cos(angle) * 500.0,
                            math.sin(angle) * 500.0,
                            0.0
                        )
                        SetVehicleSiren(vehicle, false)
                        TaskVehicleDriveToCoord(ped, vehicle,
                            target.x, target.y, target.z,
                            25.0, 0, GetEntityModel(vehicle),
                            786603, 10.0, true
                        )
                        -- Warten bis weit genug weg (max 20s)
                        local t = 0
                        while t < 20000 do
                            Wait(1000); t = t + 1000
                            if not DoesEntityExist(vehicle) then break end
                            if #(GetEntityCoords(vehicle) - cache.coords) > 180.0 then break end
                        end
                    end
                end
                -- Jetzt löschen
                if DoesEntityExist(ped)     then SetEntityAsMissionEntity(ped,     false, true); DeleteEntity(ped)     end
                if DoesEntityExist(vehicle) then SetEntityAsMissionEntity(vehicle, false, true); DeleteEntity(vehicle) end
            end
        end
        Debug('ClearAllUnits: alle Einheiten abgezogen')
    end)
end

function Police.CleanupInvalid()
    for i = #WantedSystem.pursuingUnits, 1, -1 do
        local unit = WantedSystem.pursuingUnits[i]
        if not unit or not DoesEntityExist(unit.ped) or IsEntityDead(unit.ped) then
            if unit then
                if unit.blip    and DoesBlipExist(unit.blip)      then RemoveBlip(unit.blip)     end
                if unit.vehicle and DoesEntityExist(unit.vehicle) then DeleteEntity(unit.vehicle) end
            end
            table.remove(WantedSystem.pursuingUnits, i)
        end
    end
end

-- ============================================================================
-- PRISON SYSTEM
-- ============================================================================

-- ✅ FIX #15/#18: Prison, jailTimerGen, ensureRunningInProgress sind oben in
-- der Datei forward-deklariert damit State-Bag-Handler darauf zugreifen können.

function Prison.StartTimer()
    -- ✅ FIX #30 (1.0.1-alpha): Debug-Call-Anfang war im 1.0.0-alpha Release
    -- versehentlich abgeschnitten → ressource konnte gar nicht laden.
    Debug(('Prison.StartTimer called: timerActive=%s, isJailed=%s, jailTime=%d'):format(
        tostring(WantedSystem.jailTimerActive), tostring(WantedSystem.isJailed), WantedSystem.jailTime or 0
    ))
    if WantedSystem.jailTimerActive then
        Debug('Prison.StartTimer: already active — skipping')
        return
    end
    if type(WantedSystem.jailTime) ~= 'number' or WantedSystem.jailTime <= 0 then
        WantedSystem.jailTime = 60
    end
    jailTimerGen = jailTimerGen + 1
    local myGen = jailTimerGen
    WantedSystem.jailTimerActive = true
    Debug(('Prison.StartTimer: starting with %ds, isJailed=%s, isArrested=%s, gen=%d'):format(
        WantedSystem.jailTime, tostring(WantedSystem.isJailed), tostring(WantedSystem.isArrested), myGen
    ))

    -- ✅ FIX #15: Authoritativer Timer = Server. Server broadcastet jailTime alle 5s
    -- (via state bag + police:updateJailTime). Client tickt LOKAL pro Sekunde runter
    -- damit die UI flüssig läuft — Server-Updates korrigieren ggf. minimalen Drift.
    -- Release wird WEITERHIN nur vom Server getriggert (police:teleportFromJail).
    CreateThread(function()
        local lastTick = GetGameTimer()
        while myGen == jailTimerGen
            and WantedSystem.jailTime > 0
            and (WantedSystem.isJailed or WantedSystem.isArrested)
            and WantedSystem.jailTimerActive
        do
            Wait(0)
            UI.DrawJailTimer(WantedSystem.jailTime)

            -- Pro-Sekunde-Tick lokal — Server überschreibt alle 5s mit autoritativem Wert
            local now = GetGameTimer()
            if now - lastTick >= 1000 then
                local elapsed = math.floor((now - lastTick) / 1000)
                lastTick = lastTick + elapsed * 1000
                if WantedSystem.jailTime > 0 then
                    WantedSystem.jailTime = math.max(0, WantedSystem.jailTime - elapsed)
                end
            end
        end
        -- Nur deaktivieren wenn wir noch die aktuelle Generation sind
        if myGen == jailTimerGen then
            WantedSystem.jailTimerActive = false
        end
        Debug(('Prison.StartTimer: display thread exited (gen=%d)'):format(myGen))
    end)
end

function Prison.Release()
    if not WantedSystem.isArrested and not WantedSystem.isJailed then return end
    WantedSystem.isArrested      = false
    WantedSystem.isJailed        = false  -- ✅ FIX #5: isJailed wird jetzt auch zurückgesetzt
    WantedSystem.jailTimerActive = false
    WantedSystem.jailTime        = 0
    UI.Reset()
    DoScreenFadeOut(3000); Wait(3000)
    local exitCoords = Config.Prison.exit
    SetEntityCoords(cache.ped, exitCoords.x, exitCoords.y, exitCoords.z)
    SetEntityHeading(cache.ped, exitCoords.w)
    ClearPedTasksImmediately(cache.ped)
    Wait(500)
    DoScreenFadeIn(3000)
    Notify({type='success', description=L('released')})
end

-- ✅ FIX #18: Defensiver Catch-All. Wird von State-Bag-Handler, Broadcast-Handler
-- und Watchdog aufgerufen. Sorgt dafür dass der Timer IMMER läuft wenn isJailed=true.
-- Ist idempotent — mehrfacher Aufruf verursacht keinen Schaden.
function Prison.EnsureRunning()
    -- ✅ FIX #30 (1.0.1-alpha): Debug-Call-Anfang rekonstruiert (war im 1.0.0 abgeschnitten)
    Debug(('Prison.EnsureRunning: inProgress=%s, timerActive=%s, isJailed=%s, jailTime=%d'):format(
        tostring(ensureRunningInProgress), tostring(WantedSystem.jailTimerActive),
        tostring(WantedSystem.isJailed), WantedSystem.jailTime or 0
    ))
    if ensureRunningInProgress then return end
    if WantedSystem.jailTimerActive then return end
    if not WantedSystem.isJailed then return end

    ensureRunningInProgress = true
    CreateThread(function()
        -- ✅ FIX #18: Anderen Pfaden Vorrang geben (z.B. teleportToJail-Handler nach
        -- frischer Festnahme). Wenn die ihren Job machen, wird jailTimerActive=true
        -- gesetzt und wir können hier abbrechen — sonst Doppel-Teleport.
        Wait(2500)
        if WantedSystem.jailTimerActive or not WantedSystem.isJailed then
            Debug('EnsureRunning: another path handled it — aborting')
            ensureRunningInProgress = false
            return
        end

        -- Wenn jailTime fehlt oder 0 ist, Server fragen
        if not WantedSystem.jailTime or WantedSystem.jailTime <= 0 then
            local ok, jailData = pcall(function()
                return lib.callback.await('police:checkJailStatus', false)
            end)
            if ok and jailData and jailData.jailed
                and type(jailData.time) == 'number' and jailData.time > 0
            then
                WantedSystem.jailTime = jailData.time
                if jailData.cell and not WantedSystem.jailCell then
                    WantedSystem.jailCell = jailData.cell
                end
            else
                -- Server sagt nicht jailed → lokalen State korrigieren
                WantedSystem.isJailed = false
                WantedSystem.isArrested = false
                ensureRunningInProgress = false
                return
            end
        end

        -- Optional: Wenn nicht in einer Zelle, dorthin teleportieren
        if DoesEntityExist(cache.ped) and Config.Prison.cells and #Config.Prison.cells > 0 then
            local pedCoords = GetEntityCoords(cache.ped)
            local nearestDist = math.huge
            local nearestCell = nil
            for _, cell in ipairs(Config.Prison.cells) do
                local d = #(pedCoords - vector3(cell.x, cell.y, cell.z))
                if d < nearestDist then
                    nearestDist = d
                    nearestCell = cell
                end
            end
            if nearestDist > 8.0 and nearestCell then
                Debug(('EnsureRunning: %dm from nearest cell — teleporting'):format(math.floor(nearestDist)))
                DoScreenFadeOut(800); Wait(800)
                SetEntityCoords(cache.ped, nearestCell.x, nearestCell.y, nearestCell.z, false, false, false, false)
                SetEntityHeading(cache.ped, nearestCell.w)
                ClearPedTasksImmediately(cache.ped)
                Wait(300)
                DoScreenFadeIn(800)
                Wait(800)
            end
        end

        WantedSystem.isArrested = true -- damit der Timer-Loop-Guard greift
        if not WantedSystem.jailTimerActive then
            Debug('EnsureRunning: starting jail timer')
            Prison.StartTimer()
        end
        ensureRunningInProgress = false
    end)
end

-- ✅ FIX #18: Watchdog. Letzter Sicherheitsnetz falls alle anderen Pfade versagen.
-- Prüft alle 5s ob isJailed=true aber kein Timer läuft → triggert EnsureRunning.
CreateThread(function()
    Wait(15000) -- Initial-Spawn-Phase abwarten
    while true do
        Wait(5000)
        if WantedSystem.isJailed
            and not WantedSystem.jailTimerActive
            and not ensureRunningInProgress
        then
            Debug('Jail watchdog: isJailed=true but timer not running — calling EnsureRunning')
            Prison.EnsureRunning()
        end
    end
end)

-- ============================================================================
-- WANTED SYSTEM CORE
-- ============================================================================

function WantedSystem.SetLevel(level)
    if not level then return end
    local changed = level ~= WantedSystem.level
    WantedSystem.level = level
    if level > 0 and not WantedSystem.isArrested and not WantedSystem.isDead then
        UI.UpdateWantedLevel(level)
        if changed or not WantedSystem.policeActive then WantedSystem.StartPoliceSystem() end
        WantedSystem.lastSeenByCop = GetGameTimer()
        WantedSystem.decayActive   = false
    else
        UI.Reset()
        Police.ClearAllUnits()
        WantedSystem.isSurrendered = false
        WantedSystem.policeActive  = false
        WantedSystem.decayActive   = false
    end
end

function WantedSystem.StartPoliceSystem()
    if WantedSystem.policeActive then return end
    WantedSystem.policeActive = true
    CreateThread(function()
        while WantedSystem.level > 0 and not WantedSystem.isArrested and not WantedSystem.isDead and WantedSystem.policeActive do
            local levelCfg = Config.WantedLevels and Config.WantedLevels[WantedSystem.level]
            if levelCfg and levelCfg.peds then
                local needed = math.min(
                    levelCfg.peds.amount - #WantedSystem.pursuingUnits,
                    (Config.Optimization.maxPoliceUnits or 8) - #WantedSystem.pursuingUnits
                )
                if needed > 0 and (GetGameTimer() - WantedSystem.lastSpawnTime) >= (Config.Optimization.spawnCooldown or 5000) then
                    WantedSystem.lastSpawnTime = GetGameTimer()
                    local models = {peds=levelCfg.peds.models, vehicles=levelCfg.peds.vehicles}
                    if Spawner.PreloadModels(models) then
                        local points = Spawner.GetSpawnPoints(cache.coords, needed, levelCfg.peds.spawnDistance or 350.0)
                        for i = 1, math.min(needed, #points) do
                            Police.SpawnUnit(points[i], levelCfg.peds, WantedSystem.level)
                            if i % 2 == 0 then Wait(100) end
                        end
                        Spawner.ReleaseModels(models)
                    end
                end
            end
            Wait(5000)
        end
        WantedSystem.policeActive = false
    end)
    CreateThread(function()
        while WantedSystem.policeActive do
            for i = #WantedSystem.pursuingUnits, 1, -1 do
                local unit = WantedSystem.pursuingUnits[i]
                local now  = GetGameTimer()
                if not unit or (now - (unit.lastUpdate or 0)) < WantedSystem.updateInterval then goto continue end
                unit.lastUpdate = now
                if not Police.UpdateBehavior(unit) then
                    if unit.blip    and DoesBlipExist(unit.blip)      then RemoveBlip(unit.blip)     end
                    if unit.vehicle and DoesEntityExist(unit.vehicle) then DeleteEntity(unit.vehicle) end
                    table.remove(WantedSystem.pursuingUnits, i)
                end
                ::continue::
            end
            Wait(WantedSystem.updateInterval)
        end
    end)
    CreateThread(function()
        while WantedSystem.policeActive do
            if (GetGameTimer() - WantedSystem.lastCleanup) >= WantedSystem.cleanupInterval then
                Police.CleanupInvalid()
                WantedSystem.lastCleanup = GetGameTimer()
            end
            Wait(5000)
        end
    end)
end

function WantedSystem.ToggleSurrender()
    if cache.inVehicle then
        Notify({type='error', description=L('cannot_surrender_vehicle'), duration=3000})
        return
    end
    if WantedSystem.isSurrendered then
        WantedSystem.isSurrendered = false
        ClearPedTasks(cache.ped)
    else
        WantedSystem.isSurrendered = true
        if LoadAnimDict(Config.Animations.surrender.dict) then
            TaskPlayAnim(cache.ped, Config.Animations.surrender.dict, Config.Animations.surrender.anim, 8.0,-8,-1,49,0,false,false,false)
        end
        CreateThread(function()
            Wait(1000)
            local nearest, nearestDist = nil, 999.0
            for _, unit in pairs(WantedSystem.pursuingUnits) do
                if DoesEntityExist(unit.ped) and not IsEntityDead(unit.ped) then
                    local dist = #(GetEntityCoords(unit.ped) - cache.coords)
                    if dist < (unit.config.arrestDistance or 2.5) and dist < nearestDist then
                        nearest = unit.ped; nearestDist = dist
                    end
                end
            end
            if nearest then Wait(2000); Police.AttemptArrest(nearest) end
        end)
    end
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

RegisterNetEvent('police:setWantedLevel', function(level)
    if type(level) == "number" then WantedSystem.SetLevel(level) end
end)

-- ============================================================================
-- ✅ SIMPLIFIED: teleportToJail nur für FRESH jails (admin/arrest)
-- Jail RESTORES passieren via checkJailStatus in InitializeSystem!
-- ============================================================================

RegisterNetEvent('police:teleportToJail', function(cell, time)
    Debug(('teleportToJail (FRESH JAIL): cell=%s time=%s'):format(tostring(cell), tostring(time)))

    -- Eingangs-Validierung
    time = tonumber(time) or 60
    cell = tonumber(cell) or 1
    if time < 1 then time = 60 end

    -- Set jail state
    WantedSystem.jailTime        = time
    WantedSystem.isArrested      = true
    WantedSystem.isJailed        = true
    WantedSystem.level           = 0
    WantedSystem.jailTimerActive = false

    UI.Reset()
    Police.ClearAllUnits()

    CreateThread(function()
        -- ✅ FIX #16: Robustes Ped-Wait. Vorher war abort möglich → Spieler im Limbo
        -- mit isJailed=true aber ohne Teleport und ohne Timer.
        if not playerHasPed or not DoesEntityExist(cache.ped) then
            Debug('teleportToJail: waiting for valid ped...')
            local timeout = GetGameTimer() + 30000
            while (not playerHasPed or not DoesEntityExist(cache.ped)) and GetGameTimer() < timeout do
                Wait(500)
                UpdateCache()
            end
            Wait(1000)
            UpdateCache()
        end

        -- Letzter Fallback — direktes PlayerPedId() falls cache veraltet
        if not DoesEntityExist(cache.ped) then
            local ped = PlayerPedId()
            if ped ~= 0 and DoesEntityExist(ped) then
                cache.ped = ped
                UpdateCache()
            end
        end

        -- Auch wenn Ped nicht da ist: Timer trotzdem starten damit Countdown läuft.
        -- Der Server-State ist konsistent (isJailed=true). Nächster sync korrigiert.
        if not DoesEntityExist(cache.ped) then
            Debug('teleportToJail: ped invalid even after timeout — starting timer without teleport')
            DoScreenFadeIn(1000)
            if not WantedSystem.jailTimerActive then Prison.StartTimer() end
            Notify({type='error', description=L('jailed', time), duration=5000})
            return
        end

        -- Teleport zur Cell
        local cellCoords = Config.Prison.cells[cell] or Config.Prison.cells[1]
        if cellCoords then
            -- ✅ FIX #16: Nur faden wenn nicht bereits schwarz (AttemptArrest hat evtl. schon gefadet).
            -- Verhindert die Race aus AttemptArrest's altem DoScreenFadeIn(2000).
            if not IsScreenFadedOut() then
                DoScreenFadeOut(800)
                Wait(800)
            end
            SetEntityCoords(cache.ped, cellCoords.x, cellCoords.y, cellCoords.z, false, false, false, false)
            SetEntityHeading(cache.ped, cellCoords.w)
            ClearPedTasksImmediately(cache.ped)
            Wait(300)
            DoScreenFadeIn(800)
            Wait(800) -- Fade-In abwarten bevor Timer-UI erscheint
        else
            -- Fallback wenn Cell-Config kaputt ist: nicht im Schwarz hängen bleiben
            if IsScreenFadedOut() then DoScreenFadeIn(800) end
        end

        -- START TIMER
        if not WantedSystem.jailTimerActive then
            Prison.StartTimer()
        end
        Notify({type='error', description=L('jailed', time), duration=5000})
        Debug(('FRESH JAIL: Timer started, %ds, isJailed=%s, cell=%d'):format(
            WantedSystem.jailTime, tostring(WantedSystem.isJailed), cell
        ))
    end)
end)

RegisterNetEvent('police:teleportFromJail', function() Prison.Release() end)

RegisterNetEvent('police:clearWeapons', function()
    RemoveAllPedWeapons(cache.ped, true)
end)

RegisterNetEvent('police:updateJailTime', function(time)
    if type(time) == "number" then WantedSystem.jailTime = time end
end)

RegisterNetEvent('police:applySyncedTackle', function(targetPlayerId, forwardVector)
    local targetPed = GetPlayerPed(GetPlayerFromServerId(targetPlayerId))
    if DoesEntityExist(targetPed) then
        SetPedToRagdollWithFall(targetPed, 4000, 5000, 0, forwardVector, 12.0, 0,0,0,0,0,0)
        ApplyForceToEntity(targetPed, 1, forwardVector.x*10.0, forwardVector.y*10.0, 0, 0,0,0, 0, false, true, true, true, true)
    end
end)

RegisterNetEvent('police:applySyncedArrest', function(targetPlayerId, policeNetId)
    local targetPed = GetPlayerPed(GetPlayerFromServerId(targetPlayerId))
    local policePed = policeNetId > 0 and NetworkGetEntityFromNetworkId(policeNetId) or nil
    if not DoesEntityExist(targetPed) then return end
    FreezeEntityPosition(targetPed, true)
    if policePed and DoesEntityExist(policePed) then
        local dist = #(GetEntityCoords(policePed) - GetEntityCoords(targetPed))
        if dist > 2.0 then TaskGoToEntity(policePed, targetPed,-1,1.0,2.0,0,0); Wait(math.min(dist*500,2000)) end
        TaskTurnPedToFaceEntity(policePed, targetPed, 1000)
        TaskTurnPedToFaceEntity(targetPed, policePed, 1000)
        Wait(500)
    end
    if policePed and DoesEntityExist(policePed) and LoadAnimDict('mp_arrest_paired') then
        TaskPlayAnim(policePed,'mp_arrest_paired','cop_p2_back_right',  8.0,-8.0,3500,49,0,false,false,false)
        Wait(100)
        TaskPlayAnim(targetPed,'mp_arrest_paired','crook_p2_back_right',8.0,-8.0,3500,49,0,false,false,false)
        if #(GetEntityCoords(targetPed)-GetEntityCoords(PlayerPedId())) < 30.0 then
            PlaySoundFrontend(-1,"Cuff_Shackles","GTAO_FM_Events_Soundset",1)
        end
        Wait(3500)
    else
        Wait(2000)
    end
    if LoadAnimDict('mp_arresting') then
        TaskPlayAnim(targetPed,'mp_arresting','idle',8.0,-8,-1,49,0,false,false,false)
    end
    Wait(500)
    FreezeEntityPosition(targetPed, false)
end)

RegisterNetEvent('police:createPanicBlip', function(coords)
    if not coords then return end
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip,161); SetBlipColour(blip,1); SetBlipScale(blip,1.2)
    SetBlipAsShortRange(blip,false)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("🚨 PANIC BUTTON")
    EndTextCommandSetBlipName(blip)
    CreateThread(function()
        local t = GetGameTimer()
        while GetGameTimer()-t < 30000 do
            SetBlipAlpha(blip,255); Wait(500)
            SetBlipAlpha(blip,100); Wait(500)
        end
        RemoveBlip(blip)
    end)
    PlaySoundFrontend(-1,"CHECKPOINT_PERFECT","HUD_MINI_GAME_SOUNDSET",1)
end)

AddEventHandler('gameEventTriggered', function(name, args)
    if name == 'CEventNetworkEntityDamage' then
        local victim = args[1]
        if victim == cache.ped and IsEntityDead(victim) then
            WantedSystem.isDead = true
            WantedSystem.SetLevel(0)
            lib.callback.await('police:playerDied', false)
        end
    end
end)

if Config.SurrenderKey then
    RegisterCommand('+surrender', function()
        if WantedSystem.level > 0 and not WantedSystem.isArrested then WantedSystem.ToggleSurrender() end
    end, false)
    RegisterCommand('-surrender', function() end, false)
    RegisterKeyMapping('+surrender', 'Surrender to Police', 'keyboard', Config.SurrenderKey)
end

-- ============================================================================
-- ✅ FIX #13: INITIALIZATION
-- Wartet per lib.onCache('ped') auf echten Spawn (nach Character Selection)
-- ============================================================================

-- ✅ FIX #13: Jail-Data wird hier zwischengespeichert und in InitializeSystem verarbeitet
-- Kein separater Thread mit WaitForRealPed() mehr nötig
local pendingJailRestore = nil

-- ✅ FIX #19: Race Condition Guard — verhindert dass ox:playerLoaded + police:systemReady
-- gleichzeitig zwei InitializeSystem-Threads starten die sich gegenseitig überschreiben.
-- Jeder neue Aufruf inkrementiert initGen; laufende Threads prüfen ob sie noch aktuell sind.
local initGen = 0

local function InitializeSystem()
    if WantedSystem.systemReady then return end
    WantedSystem.systemReady = true
    initGen = initGen + 1
    local myGen = initGen

    Debug('InitializeSystem: waiting for real ped via lib.onCache...')

    CreateThread(function()
        -- ✅ Warte auf echten Ped nach Character Selection — NUR EINMAL
        WaitForRealPed()
        -- ✅ FIX #19: Abbrechen wenn ein neuerer Init-Thread gestartet wurde
        if myGen ~= initGen then
            Debug(('InitializeSystem gen %d aborted (newer gen %d active)'):format(myGen, initGen))
            return
        end

        Debug('Real ped confirmed — fetching server data...')

        -- Wanted Level restore
        local wantedOk, level = pcall(function()
            return lib.callback.await('police:getWantedLevel', false)
        end)

        if wantedOk and level and type(level) == "number" and level > 0 then
            Debug(('Restoring wanted level: %d'):format(level))
            WantedSystem.SetLevel(level)
        end

        -- ✅ FIX #1: Decay wird NUR von crime.lua gestartet (via Server-Event)

        -- ✅ FIX #21: Jail Restore läuft jetzt direkt im police:systemReady Handler.
        -- Kein Fallback-Callback mehr nötig — der systemReady-Thread startet Timer selbst.

        -- ✅ FIX #13 + #16: Jail Restore — nutzt den gleichen robusten Pfad wie teleportToJail.
        -- Kein eigener Abort wenn Ped fehlt — Timer startet trotzdem damit der Countdown läuft.
        -- ✅ FIX #19: Nochmal prüfen ob wir noch der aktuelle Thread sind (nach den Callbacks oben)
        if myGen ~= initGen then
            Debug(('InitializeSystem gen %d aborted before jail restore (newer gen %d active)'):format(myGen, initGen))
            return
        end

        -- ✅ FIX #21: Jail Restore läuft jetzt im police:systemReady Handler (eigener Thread).
        -- InitializeSystem muss hier nichts mehr tun — pendingJailRestore nur als Fallback-Check.
        if pendingJailRestore then
            Debug('InitializeSystem: pendingJailRestore still set — systemReady thread handles it')
            -- Watchdog übernimmt falls der systemReady-Thread ebenfalls versagt
        end
        
        Debug('System fully initialized')
    end)
end

RegisterNetEvent('police:systemReady', function(data)
    Debug(('police:systemReady received — jailed: %s, jailTime: %d'):format(
        tostring(data and data.isJailed), data and data.jailTime or 0
    ))

    if data and data.wantedLevel and data.wantedLevel > 0 then
        WantedSystem.level = data.wantedLevel
    end

    -- ✅ FIX #20/#21: State SOFORT setzen + eigener Restore-Thread.
    -- Trennt Jail-Restore komplett von InitializeSystem/initGen-Race.
    -- ox:playerLoaded kann jetzt keinen laufenden Restore-Thread mehr killen.
    if data and data.isJailed and data.jailTime and data.jailTime > 0 then
        WantedSystem.isJailed   = true
        WantedSystem.isArrested = true
        WantedSystem.jailTime   = data.jailTime
        pendingJailRestore = {
            jailTime = data.jailTime,
            jailCell = data.jailCell or 1,
        }
        -- Eigener Restore-Thread — unabhängig von initGen
        local restoreTime = data.jailTime
        local restoreCell = data.jailCell or 1
        CreateThread(function()
            -- Warte auf Ped ohne extra WaitForRealPed()-Aufruf (kein doppelter Print)
            local timeout = 15000
            local t = 0
            while t < timeout do
                local ped = cache.ped or PlayerPedId()
                if ped ~= 0 and DoesEntityExist(ped) and not IsEntityDead(ped) then break end
                Wait(200)
                t = t + 200
            end
            Wait(500) -- kurzer Extra-Buffer
            -- ✅ FIX #30 (1.0.1-alpha): Debug-Call-Anfang rekonstruiert (war im 1.0.0 abgeschnitten)
            Debug(('systemReady jail restore: timerActive=%s, isJailed=%s, jailTime=%d, restoreTime=%d'):format(
                tostring(WantedSystem.jailTimerActive), tostring(WantedSystem.isJailed),
                WantedSystem.jailTime or 0, restoreTime
            ))
            if WantedSystem.jailTimerActive then
                Debug('systemReady jail thread: timer already running — skipping')
                pendingJailRestore = nil
                return
            end
            local currentTime = WantedSystem.jailTime
            if not currentTime or currentTime <= 0 then currentTime = restoreTime end
            WantedSystem.isJailed   = true
            WantedSystem.isArrested = true
            WantedSystem.jailTime   = currentTime
            WantedSystem.level      = 0
            local cellCoords = Config.Prison.cells[restoreCell] or Config.Prison.cells[1]
            if not DoesEntityExist(cache.ped) then
                local ped = PlayerPedId()
                if ped ~= 0 and DoesEntityExist(ped) then cache.ped = ped; UpdateCache() end
            end
            if cellCoords and DoesEntityExist(cache.ped) then
                if not IsScreenFadedOut() then DoScreenFadeOut(800); Wait(800) end
                SetEntityCoords(cache.ped, cellCoords.x, cellCoords.y, cellCoords.z, false, false, false, false)
                SetEntityHeading(cache.ped, cellCoords.w)
                ClearPedTasksImmediately(cache.ped)
                Wait(300)
                DoScreenFadeIn(800)
                Wait(800)
            else
                if IsScreenFadedOut() then DoScreenFadeIn(800) end
                Debug('systemReady jail restore: ped/cellCoords invalid — timer only')
            end
            if not WantedSystem.jailTimerActive then
                Debug(('systemReady jail restore: starting timer %ds cell=%d'):format(currentTime, restoreCell))
                Prison.StartTimer()
            end
            pendingJailRestore = nil
        end)
    else
        if not WantedSystem.isJailed then
            WantedSystem.isArrested = false
            WantedSystem.jailTime   = 0
        end
        pendingJailRestore = nil
    end

    WantedSystem.systemReady = false
    InitializeSystem()
end)
-- ════════════════════════════════════════════════════════════════
-- RDE SYNC PATTERN - CLIENT EVENT HANDLERS
-- ════════════════════════════════════════════════════════════════

-- Storage for other players' states (for potential future use)
local OtherPlayerStates = {}

-- Receive broadcast update for a single player
RegisterNetEvent('police:playerStateUpdate', function(playerSource, stateData)
    if not playerSource or not stateData then return end
    
    -- Store state for other players
    OtherPlayerStates[playerSource] = stateData
    
    -- If it's our own state update from server, sync our local state
    local mySource = GetPlayerServerId(PlayerId())
    if playerSource == mySource then
        if stateData.level then
            -- ✅ FIX: IMMER SetLevel aufrufen — auch wenn der Wert gleich ist!
            -- StateBag kann den Level schon gesetzt haben OHNE StartPoliceSystem()
            -- Broadcast muss sicherstellen dass die Cops laufen.
            if stateData.level ~= WantedSystem.level then
                WantedSystem.SetLevel(stateData.level)
                Debug(('Received wanted level update from server: %d'):format(stateData.level))
            elseif stateData.level > 0 and not WantedSystem.policeActive then
                -- Level ist gleich, aber Police System läuft nicht → starten!
                Debug(('Police system not active for level %d — starting now'):format(stateData.level))
                WantedSystem.StartPoliceSystem()
            end
        end
        
        if stateData.isJailed ~= nil then
            local wasJailed = WantedSystem.isJailed
            WantedSystem.isJailed = stateData.isJailed
            -- ✅ FIX #18: Auto-Start Timer wenn Server uns als jailed broadcastet
            -- aber lokal noch kein Timer läuft (Race-Sicherung)
            if stateData.isJailed and not wasJailed and Prison and Prison.EnsureRunning then
                Prison.EnsureRunning()
            end
        end
        
        if stateData.jailTime then
            WantedSystem.jailTime = stateData.jailTime
            if WantedSystem.isJailed and stateData.jailTime > 0
                and not WantedSystem.jailTimerActive
                and Prison and Prison.EnsureRunning
            then
                Prison.EnsureRunning()
            end
        end
    end
    
    Debug(('State update received for player %d | Wanted: %d | Jailed: %s'):format(
        playerSource, stateData.level or 0, tostring(stateData.isJailed or false)
    ))
end)

-- Receive initial sync of all player states (when joining)
RegisterNetEvent('police:syncAllStates', function(stateArray)
    if not stateArray or type(stateArray) ~= 'table' then return end
    
    Debug(('Received initial sync for %d players'):format(#stateArray))
    
    OtherPlayerStates = {}
    local mySource = GetPlayerServerId(PlayerId())
    
    for _, state in ipairs(stateArray) do
        if state.source and state.source ~= mySource then
            OtherPlayerStates[state.source] = state
        end
    end
    
    Debug(('Synced %d other player states'):format(#stateArray - 1))
end)

-- Receive player disconnect notification
RegisterNetEvent('police:playerDisconnected', function(playerSource)
    if not playerSource then return end
    
    -- Clean up disconnected player's state
    if OtherPlayerStates[playerSource] then
        OtherPlayerStates[playerSource] = nil
        Debug(('Removed state for disconnected player %d'):format(playerSource))
    end
end)

-- ════════════════════════════════════════════════════════════════
-- RESOURCE LIFECYCLE
-- ════════════════════════════════════════════════════════════════

AddEventHandler('onResourceStart', function(resource)
    if GetCurrentResourceName() ~= resource then return end
    CreateThread(function()
        Wait(1000)
        WantedSystem.systemReady = false
        InitializeSystem()
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if GetCurrentResourceName() ~= resource then return end
    Police.ClearAllUnits()
    UI.Reset()
    if WantedSystem.jailTimerActive then WantedSystem.jailTimerActive = false end
end)

-- ✅ FIX #22: ox:playerLoaded startet KEIN InitializeSystem mehr.
-- police:systemReady kommt immer kurz danach und macht das zuverlässig.
-- Zwei gleichzeitige InitializeSystem-Threads waren die Ursache für den
-- doppelten WaitForRealPed-Print und den initGen-Race der Thread 1 killte.
AddEventHandler('ox:playerLoaded', function()
    -- Nur State zurücksetzen damit police:systemReady frisch starten kann.
    WantedSystem.systemReady = false
end)

AddEventHandler('ox:playerDeath', function()
    WantedSystem.isDead = true
    WantedSystem.SetLevel(0)
end)

AddEventHandler('ox:playerRevived', function()
    WantedSystem.isDead = false
    Debug('isDead reset via ox:playerRevived')
end)

AddEventHandler('rde_death:adminRevive', function()
    WantedSystem.isDead = false
    Debug('isDead reset via rde_death:adminRevive')
end)

AddEventHandler('rde_death:doctorRevive', function()
    WantedSystem.isDead = false
    Debug('isDead reset via rde_death:doctorRevive')
end)

AddEventHandler('rde_death:doRespawn', function()
    WantedSystem.isDead = false
    Debug('isDead reset via rde_death:doRespawn')
end)

-- ✅ FIX: FEHLENDER HANDLER! rde_aimd feuert TriggerEvent('rde_death:localRevive')
-- als letzten Schritt in RevivePlayer() und im isDead-Failsafe-Thread.
-- Ohne diesen Handler bleibt WantedSystem.isDead = true hängen wenn die
-- Network-Events (adminRevive etc.) nicht rechtzeitig ankommen.
AddEventHandler('rde_death:localRevive', function()
    WantedSystem.isDead = false
    Debug('isDead reset via rde_death:localRevive')
end)

CreateThread(function()
    while true do
        Wait(3000)
        if WantedSystem.isDead then
            local ped = cache.ped
            if DoesEntityExist(ped) and not IsEntityDead(ped) and GetEntityHealth(ped) > 100 then
                WantedSystem.isDead = false
                Debug('isDead Failsafe: player alive — isDead reset')
            end
        end
    end
end)

-- ============================================================================
-- EXPORTS
-- ============================================================================

exports('getWantedLevel',   function() return WantedSystem.level end)
exports('isArrested',       function() return WantedSystem.isArrested end)
exports('isSurrendered',    function() return WantedSystem.isSurrendered end)
exports('isJailed',         function() return WantedSystem.isJailed end)
exports('getJailTime',      function() return WantedSystem.jailTime end)
exports('getPursuingUnits', function() return #WantedSystem.pursuingUnits end)
exports('copsCanSeePlayer', function() return WantedSystem.copsCanSeePlayer end)
exports('isDecayActive',    function() return WantedSystem.decayActive end)
exports('setWantedLevel', function(level)
    if type(level) == "number" then WantedSystem.SetLevel(level) end
end)
exports('surrender',   function() WantedSystem.ToggleSurrender() end)
exports('clearPolice', function() Police.ClearAllUnits() end)

-- ============================================================================
-- DEBUG COMMANDS
-- ============================================================================

if Config.Debug then
    RegisterCommand('debugpolice', function()
        print('=== Police Debug Info ===')
        print('Wanted Level:',       WantedSystem.level)
        print('Is Arrested:',        WantedSystem.isArrested)
        print('Is Jailed:',          WantedSystem.isJailed)
        print('Jail Time:',          WantedSystem.jailTime)
        print('jailTimerActive:',    WantedSystem.jailTimerActive)
        print('pendingJailRestore:', pendingJailRestore and 'set' or 'nil')
        print('playerHasPed:',       playerHasPed)
        print('cache.ped:',          cache.ped)
        print('Is Surrendered:',     WantedSystem.isSurrendered)
        print('Pursuing Units:',     #WantedSystem.pursuingUnits)
        print('Police Active:',      WantedSystem.policeActive)
        print('System Ready:',       WantedSystem.systemReady)
        print('======================')
    end, false)

    RegisterCommand('clearcops',   function() Police.ClearAllUnits(); print('^2[Police]^7 Cleared all units') end, false)
    RegisterCommand('testwanted',  function(s,a) local l=tonumber(a[1])or 3; WantedSystem.SetLevel(l); print('^2[Police]^7 Set wanted level to',l) end, false)
    RegisterCommand('testjail',    function(s,a) local t=tonumber(a[1])or 60; TriggerEvent('police:teleportToJail',1,t); print('^2[Police]^7 Jailed for',t,'seconds') end, false)
    RegisterCommand('unjail',      function() Prison.Release(); print('^2[Police]^7 Released from jail') end, false)
    RegisterCommand('toggledecay', function() decayConfig.enabled=not decayConfig.enabled; print('^2[Police]^7 Decay:',decayConfig.enabled and 'ON' or 'OFF') end, false)

    RegisterCommand('spawncop', function()
        local lc = Config.WantedLevels[WantedSystem.level] or Config.WantedLevels[3]
        if lc and lc.peds then
            local m={peds=lc.peds.models,vehicles=lc.peds.vehicles}
            if Spawner.PreloadModels(m) then
                local pts=Spawner.GetSpawnPoints(cache.coords,1,300.0)
                if #pts>0 then Police.SpawnUnit(pts[1],lc.peds,WantedSystem.level); print('^2[Police]^7 Spawned test unit') end
                Spawner.ReleaseModels(m)
            end
        end
    end, false)
end

-- ============================================================================
-- STARTUP
-- ============================================================================

CreateThread(function()
    Wait(5000)
    print('^2[AIPD | Client]^7 ✓ AAA+ AI Police initialized')
    print('^2[AIPD | Client]^7 ✅ FIX #13: lib.onCache(ped) Spawn-Detection — kein Spawn-Menü Bug mehr')
    print('^2[AIPD | Client]^7 ✅ FIX #11: jailTimerActive force-reset')
    print('^2[AIPD | Client]^7 ✅ FIX #10: jailRestoreHandled flag')
    print('^2[AIPD | Client]^7 ✅ FIX #7: isDead sync + Failsafe')
    print('^2[AIPD | Client]^7 ✅ FIX #4: Police shooting logic')
    print('^2[AIPD | Client]^7 ✅ Verbessertes Tackle: Richtungsvektor + 3–7s Ragdoll (originaler Style)')
    print('^2[AIPD | Client]^7 ✅ Sanfter Despawn: Cops steigen ins Auto und fahren weg')
    print('^2[AIPD | Client]^7 ✅ FIX #14: Jail Restore Teleport — Spawnt korrekt in Zelle nach Reconnect')
    print('^2[AIPD | Client]^7 ✅ FIX #15: Jail-Timer tickt jetzt LOKAL pro Sekunde + Generation-Counter gegen Re-Jail-Race')
    print('^2[AIPD | Client]^7 ✅ FIX #16: Teleport nach Festnahme — keine Fade-Race mehr, Single Source of Truth + Safety-Net')
    print('^2[AIPD | Client]^7 ✅ FIX #18: Reconnect-Jail-Timer — aktive Server-Query + Watchdog + State-Bag Auto-Start')
    print('^2[AIPD | Client]^7 ✅ FIX #22: ox:playerLoaded startet kein InitializeSystem mehr — kein doppelter WaitForRealPed')
    print('^2[AIPD | Client]^7 Version: 1.0.0-alpha')
    print('^2[AIPD | Client]^7 Framework: ox_core')
    if Config.Debug then print('^3[AIPD | Client]^7 ⚠ Debug mode active') end
end)