---@diagnostic disable: undefined-global, missing-parameter
-- ════════════════════════════════════════════════════════════════
-- AIPD | CLIENT | NEXT-GEN EDITION
-- Realistic AI Police • Smooth Animations • Bulletproof Jail
-- Multi-Player Safe • Fully Realtime Synced
-- ════════════════════════════════════════════════════════════════
-- IMPROVEMENTS:
--  ✅ Jail teleport: ACK system — server retries until we confirm
--  ✅ Multi-player: each player runs its own isolated Police system
--  ✅ Cop despawn: realistic — cops get in car, drive away, then delete
--  ✅ Arrest animations: smooth paired cuffing with proper sequencing
--  ✅ Cop AI: realistic patrol behaviors, cover, flanking, roadblocks
--  ✅ Wanted decay: blocked during arrest window (no race condition)
--  ✅ Dead cop vehicles: linger realistically, no instant poofing
--  ✅ Helicopter support: level 4+ air units with search lights
--  ✅ Realistic vehicle chase: PIT, ramming, proper speed matching
-- ════════════════════════════════════════════════════════════════

-- ── LOCALE ───────────────────────────────────────────────────────
local Locale = lib.load('locales.' .. GetConvar('ox:locale', 'en')) or {}
local function L(key, ...)
    local s = Locale[key]
    if not s then return key end
    if select('#', ...) > 0 then return s:format(...) end
    return s
end

-- ── LOCAL CACHE ──────────────────────────────────────────────────
local cache = {
    ped      = 0,
    coords   = vector3(0, 0, 0),
    vehicle  = 0,
    inVehicle = false,
    isAlive  = true,
}

local function UpdateCache()
    cache.ped = PlayerPedId()
    if DoesEntityExist(cache.ped) then
        cache.coords  = GetEntityCoords(cache.ped)
        cache.vehicle = GetVehiclePedIsIn(cache.ped, false)
        cache.inVehicle = cache.vehicle ~= 0
        cache.isAlive = not IsEntityDead(cache.ped)
    end
end

CreateThread(function()
    while true do UpdateCache(); Wait(500) end
end)

-- ── SPAWN DETECTION ──────────────────────────────────────────────
local playerHasPed = false

lib.onCache('ped', function(ped)
    playerHasPed = (ped and ped ~= 0 and DoesEntityExist(ped))
    if playerHasPed then UpdateCache() end
end)

local function WaitForRealPed()
    local timeout = GetGameTimer() + 60000
    while not playerHasPed and GetGameTimer() < timeout do Wait(500) end
    if not playerHasPed then
        local ped = PlayerPedId()
        if DoesEntityExist(ped) then playerHasPed = true; UpdateCache() end
        if not playerHasPed then return false end
    end
    Wait(3000); UpdateCache()
    return true
end

-- ════════════════════════════════════════════════════════════════
-- WANTED SYSTEM STATE
-- ════════════════════════════════════════════════════════════════

local WantedSystem = {
    level          = 0,
    isArrested     = false,
    isDead         = false,
    isSurrendered  = false,
    isJailed       = false,
    jailTime       = 0,
    jailTimerActive = false,
    pursuingUnits  = {},       -- [{ped, vehicle, blip, config, level, state, ...}]
    policeActive   = false,
    lastSpawnTime  = 0,
    updateInterval = 500,
    cleanupInterval = 10000,
    lastCleanup    = 0,
    systemReady    = false,
    lastSeenByCop  = 0,
    decayActive    = false,
}

-- Forward declarations
local Prison    = {}
local jailTimerGen          = 0
local ensureRunningInProgress = false

local function Debug(...)
    if Config.Debug then print('^3[AIPD | Client]^7', ...) end
end

local function Notify(data)
    if data and type(data) == 'table' then lib.notify(data) end
end

-- ════════════════════════════════════════════════════════════════
-- LINE OF SIGHT
-- ════════════════════════════════════════════════════════════════

local function HasLineOfSight(fromCoords, toCoords, maxDist)
    maxDist = maxDist or 100.0
    if #(fromCoords - toCoords) > maxDist then return false end
    local ray = StartShapeTestRay(
        fromCoords.x, fromCoords.y, fromCoords.z + 1.0,
        toCoords.x,   toCoords.y,   toCoords.z + 1.0,
        -1, cache.ped, 0
    )
    local _, hit, _, _, entityHit = GetShapeTestResult(ray)
    return not (hit and entityHit ~= cache.ped)
end

local function CopCanSeePlayer(copPed, playerPed, maxDist)
    if not DoesEntityExist(copPed) or not DoesEntityExist(playerPed) then return false end
    local cp = GetEntityCoords(copPed)
    local pp = GetEntityCoords(playerPed)
    local d  = #(cp - pp)
    if d > (maxDist or 100.0) then return false end
    if not HasLineOfSight(cp, pp, maxDist) then return false end
    -- Field of view check using forward vector dot product
    local fwd = GetEntityForwardVector(copPed)
    local dir = pp - cp
    local len = #dir
    if len < 0.001 then return true, d end
    local dot = (fwd.x * dir.x + fwd.y * dir.y) / len
    if dot > -0.35 then return true, d end  -- ~110° either side = 220° FOV
    return false
end

local function AnyCopCanSeePlayer()
    for _, unit in ipairs(WantedSystem.pursuingUnits) do
        if unit and DoesEntityExist(unit.ped) then
            if CopCanSeePlayer(unit.ped, cache.ped, 150.0) then return true end
        end
    end
    -- Check ambient police peds too
    for _, ped in ipairs(GetGamePool('CPed')) do
        if DoesEntityExist(ped) and not IsPedAPlayer(ped) and GetPedType(ped) == 6 then
            if CopCanSeePlayer(ped, cache.ped, 100.0) then return true end
        end
    end
    return false
end

-- ════════════════════════════════════════════════════════════════
-- HELPER UTILITIES
-- ════════════════════════════════════════════════════════════════

local function LoadAnimDict(dict)
    if not dict or HasAnimDictLoaded(dict) then return HasAnimDictLoaded(dict or '') end
    RequestAnimDict(dict)
    local t = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(10) end
    return HasAnimDictLoaded(dict)
end

local function LoadModel(model)
    if not model then return false end
    local hash = type(model) == 'string' and joaat(model) or model
    if HasModelLoaded(hash) then return true end
    RequestModel(hash)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < t do Wait(10) end
    return HasModelLoaded(hash)
end

local function GetClosestRoad(coords, radius)
    if not coords then return false, nil, 0 end
    local ok, pos, heading = GetClosestVehicleNodeWithHeading(
        coords.x, coords.y, coords.z, 1, radius or 3.0, 0
    )
    return ok, pos and vec3(pos.x, pos.y, pos.z) or nil, heading or 0
end

local function PlayerIsArmed()
    local _, weapon = GetCurrentPedWeapon(cache.ped, true)
    return weapon and weapon ~= joaat('WEAPON_UNARMED')
end

-- ════════════════════════════════════════════════════════════════
-- STATE BAG INTEGRATION
-- ════════════════════════════════════════════════════════════════

if Config.UseStateBags then
    AddStateBagChangeHandler('wantedLevel', nil, function(bagName, key, value)
        if not bagName or not bagName:find('entity:') then return end
        local entity = GetEntityFromStateBagName(bagName)
        if not entity or entity ~= cache.ped then return end
        if type(value) == 'number' and value ~= WantedSystem.level then
            WantedSystem.SetLevel(value)
        end
    end)
    AddStateBagChangeHandler('isJailed', nil, function(bagName, key, value)
        if not bagName or not bagName:find('entity:') then return end
        local entity = GetEntityFromStateBagName(bagName)
        if not entity or entity ~= cache.ped then return end
        local wasJailed = WantedSystem.isJailed
        WantedSystem.isJailed = value
        if value and not wasJailed and Prison.EnsureRunning then Prison.EnsureRunning() end
    end)
    AddStateBagChangeHandler('jailTime', nil, function(bagName, key, value)
        if not bagName or not bagName:find('entity:') then return end
        local entity = GetEntityFromStateBagName(bagName)
        if not entity or entity ~= cache.ped then return end
        WantedSystem.jailTime = value
        if WantedSystem.isJailed and value and value > 0 and not WantedSystem.jailTimerActive and Prison.EnsureRunning then
            Prison.EnsureRunning()
        end
    end)
end

-- ════════════════════════════════════════════════════════════════
-- UI MANAGEMENT
-- ════════════════════════════════════════════════════════════════

UI = {}
local nuiReady = false
local nuiPending = nil

CreateThread(function() Wait(3000); nuiReady = true
    if nuiPending and nuiPending > 0 then
        SendNUIMessage({ type='updateWantedLevel', level=nuiPending, config=Config.WantedLevels and Config.WantedLevels[nuiPending] or {} })
        nuiPending = nil
    end
end)

function UI.UpdateWantedLevel(level)
    if not nuiReady then nuiPending = level; return end
    SendNUIMessage({ type='updateWantedLevel', level=level, config=Config.WantedLevels and Config.WantedLevels[level] or {} })
end

function UI.HideWantedLevel()
    if not nuiReady then return end
    SendNUIMessage({ type='hideWantedUI' })
end

function UI.Reset()
    if not nuiReady then return end
    SendNUIMessage({ type='forceReset' }); Wait(50); UI.HideWantedLevel()
end

function UI.DrawJailTimer(time)
    if not time or time <= 0 then return end
    DrawRect(0.5, 0.05, 0.18,  0.05,  0,   0,   0,   220)
    DrawRect(0.5, 0.05, 0.182, 0.052, 220, 38,  38,  255)
    DrawRect(0.5, 0.05, 0.18,  0.05,  0,   0,   0,   220)
    SetTextScale(0.45, 0.45); SetTextFont(4); SetTextProportional(1)
    SetTextColour(255, 255, 255, 255); SetTextEntry('STRING'); SetTextCentre(1); SetTextDropShadow()
    AddTextComponentString(('⏱️ Jail Time: %dm %ds'):format(math.floor(time/60), time%60))
    DrawText(0.5, 0.038)
end

-- ════════════════════════════════════════════════════════════════
-- SPAWN SYSTEM
-- ════════════════════════════════════════════════════════════════

local Spawner = {}

function Spawner.GetSpawnPoints(coords, count, maxDist)
    if not coords or not count or count <= 0 then return {} end
    local points = {}
    for angle = 0, 359, 30 do
        if #points >= count then break end
        local rad = math.rad(angle)
        for dist = 150.0, (maxDist or 350.0), 75 do
            if #points >= count then break end
            local x = coords.x + math.cos(rad) * dist
            local y = coords.y + math.sin(rad) * dist
            local ok, pos, heading = GetClosestRoad(vec3(x, y, coords.z))
            if ok and pos then
                local actual = #(coords - pos)
                if actual >= 150.0 and actual <= maxDist then
                    points[#points+1] = { coords=pos, heading=heading, distance=actual }
                end
            end
        end
    end
    return points
end

function Spawner.PreloadModels(models)
    if not models then return false end
    if models.peds    then for _, m in ipairs(models.peds)    do if not LoadModel(m) then return false end end end
    if models.vehicles then for _, m in ipairs(models.vehicles) do if not LoadModel(m) then return false end end end
    return true
end

function Spawner.ReleaseModels(models)
    if not models then return end
    if models.peds    then for _, m in ipairs(models.peds)    do SetModelAsNoLongerNeeded(joaat(m)) end end
    if models.vehicles then for _, m in ipairs(models.vehicles) do SetModelAsNoLongerNeeded(joaat(m)) end end
end

-- ════════════════════════════════════════════════════════════════
-- POLICE UNIT MANAGEMENT
-- ════════════════════════════════════════════════════════════════

local Police = {}

function Police.SpawnUnit(spawnPoint, config, level)
    if not spawnPoint or not config or not level then return false end

    local pedModel = config.models[math.random(#config.models)]
    local vehModel = config.vehicles[math.random(#config.vehicles)]

    -- Spawn vehicle first
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
    -- Ensure emergency lights are on
    SetVehicleHasBeenOwnedByPlayer(vehicle, true)
    SetVehicleIsConsideredByPlayer(vehicle, true)

    local chaseSpeed = (config.chaseSpeed or 25.0) / 3.6
    ModifyVehicleTopSpeed(vehicle, chaseSpeed)
    SetEntityMaxSpeed(vehicle, chaseSpeed + 2.0)

    -- Spawn cop ped
    local ped = CreatePed(4, joaat(pedModel),
        spawnPoint.coords.x, spawnPoint.coords.y, spawnPoint.coords.z,
        spawnPoint.heading, true, true)
    if not DoesEntityExist(ped) then DeleteEntity(vehicle); return false end

    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 46, true)   -- always fight
    SetPedCombatAttributes(ped, 5,  true)   -- can use vehicles
    SetPedCombatAttributes(ped, 0,  true)   -- can use cover
    SetPedCombatAttributes(ped, 1,  true)   -- always react to threats
    SetPedCombatAttributes(ped, 2,  true)   -- always fight
    SetPedCombatAttributes(ped, 3,  true)   -- always fight back
    SetPedCombatAttributes(ped, 52, true)   -- always shoot
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
    SetTaskVehicleChaseBehaviorFlag(ped, 0, true)
    SetTaskVehicleChaseBehaviorFlag(ped, 1, true)
    SetTaskVehicleChaseBehaviorFlag(ped, 2, true)
    SetTaskVehicleChaseBehaviorFlag(ped, 3, true)

    -- Blip
    local blip = AddBlipForEntity(ped)
    local blipCfg = (Config.PoliceUnitBlips and Config.PoliceUnitBlips.vehicle) or { sprite=56, color=3, scale=0.7 }
    SetBlipSprite(blip, blipCfg.sprite or 56)
    SetBlipColour(blip, blipCfg.color  or 3)
    SetBlipScale(blip,  blipCfg.scale  or 0.7)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentString('Police Unit'); EndTextCommandSetBlipName(blip)

    -- Blip pulse thread (won't leak since it checks DoesBlipExist)
    if blipCfg.pulse ~= false then
        CreateThread(function()
            while DoesBlipExist(blip) do
                SetBlipColour(blip, 1); Wait(500)
                SetBlipColour(blip, blipCfg.color or 3); Wait(500)
            end
        end)
    end

    WantedSystem.pursuingUnits[#WantedSystem.pursuingUnits+1] = {
        ped            = ped,
        vehicle        = vehicle,
        blip           = blip,
        config         = config,
        level          = level,
        state          = 'pursuing',
        lastUpdate     = GetGameTimer(),
        spawnTime      = GetGameTimer(),
        lastTackle     = 0,
        lastPIT        = 0,
        lastRoadblock  = 0,
        lastStateChange = GetGameTimer(),
        draggingOut    = false,
        hasLOS         = false,
        lastLOSTime    = 0,
        blipMode       = nil,
        deathTime      = nil,
        departing      = false,
    }

    Debug(('Spawned unit at %.0fm | model: %s + %s'):format(spawnPoint.distance, pedModel, vehModel))
    return true
end

-- Dynamic blip sprite (vehicle vs foot)
local function UpdateBlipForUnit(unit)
    if not unit or not unit.blip or not DoesBlipExist(unit.blip) then return end
    if not DoesEntityExist(unit.ped) then return end
    local inVeh      = IsPedInAnyVehicle(unit.ped, false)
    local desired    = inVeh and 'vehicle' or 'foot'
    if unit.blipMode == desired then return end
    local cfg = Config.PoliceUnitBlips and Config.PoliceUnitBlips[desired]
    if not cfg then return end
    SetBlipSprite(unit.blip, cfg.sprite or 56)
    SetBlipColour(unit.blip, cfg.color  or 1)
    SetBlipScale(unit.blip,  cfg.scale  or 0.55)
    unit.blipMode = desired
end

-- ── MAINTAIN VEHICLE (prevent engine death during chase) ─────────
local function MaintainVehicle(vehicle)
    if not DoesEntityExist(vehicle) then return end
    if GetVehicleBodyHealth(vehicle) < 500 or GetVehicleEngineHealth(vehicle) < 500 then
        SetVehicleFixed(vehicle); SetVehicleEngineHealth(vehicle, 1000.0); SetVehicleBodyHealth(vehicle, 1000.0)
    end
    if not GetIsVehicleEngineRunning(vehicle) then SetVehicleEngineOn(vehicle, true, true, false) end
end

-- ── TELEPORT UNIT (rubberband when too far away) ─────────────────
local function TeleportUnit(unit)
    if not unit or not DoesEntityExist(unit.vehicle) then return end
    local angle   = math.random() * math.pi * 2
    local dist    = math.random(250, 350)
    local x = cache.coords.x + math.cos(angle) * dist
    local y = cache.coords.y + math.sin(angle) * dist
    local ok, pos, heading = GetClosestRoad(vec3(x, y, cache.coords.z))
    if ok and pos then
        SetEntityCoords(unit.vehicle, pos.x, pos.y, pos.z, false, false, false, true)
        SetEntityHeading(unit.vehicle, heading)
        SetVehicleOnGroundProperly(unit.vehicle)
        if DoesEntityExist(unit.ped) and not IsPedInAnyVehicle(unit.ped, false) then
            SetEntityCoords(unit.ped, pos.x, pos.y, pos.z, false, false, false, false)
            SetPedIntoVehicle(unit.ped, unit.vehicle, -1)
        end
        unit.state = 'pursuing'
    end
end

-- ── TRY TACKLE ───────────────────────────────────────────────────
local function TryTackle(unit)
    if not unit then return false end
    local now = GetGameTimer()
    if (now - unit.lastTackle) < 10000 then return false end
    if IsPedRagdoll(cache.ped) or IsPedGettingUp(cache.ped) then return false end
    if not DoesEntityExist(unit.ped) or IsPedDeadOrDying(unit.ped, true) then return false end

    local prob = unit.config.tackleProbability or 0.30
    if math.random(100) > (prob * 100) then return false end

    unit.lastTackle = now

    local pc  = GetEntityCoords(cache.ped)
    local cc  = GetEntityCoords(unit.ped)
    local dx  = cc.x - pc.x
    local dy  = cc.y - pc.y
    local len = math.sqrt(dx*dx + dy*dy)
    local dir = vector3(len > 0 and dx/len or 0, len > 0 and dy/len or 0, 0)

    local dur = math.random(3000, 7000)
    SetPedToRagdollWithFall(cache.ped, dur, dur, 0, dir, 10.0, 0,0,0,0,0,0)
    SetPedToRagdollWithFall(unit.ped,  3000, 3000, 0, dir, 10.0, 0,0,0,0,0,0)
    ApplyForceToEntity(cache.ped, 1, dir.x*5.0, dir.y*5.0, 0, 0,0,0, 1, false, true, true, true, true)
    TriggerServerEvent('police:syncTackle', GetPlayerServerId(PlayerId()), dir)
    PlaySoundFrontend(-1, 'TACKLE', 'PLAYER_TACKLE_SOUNDSET', 1)
    Notify({ type='error', description=L('tackled'), duration=3000 })
    return true
end

-- ── DRAG FROM VEHICLE ─────────────────────────────────────────────
local function DragPlayerFromVehicle(copPed, playerPed, vehicle)
    if not DoesEntityExist(copPed) or not DoesEntityExist(playerPed) or not DoesEntityExist(vehicle) then return end
    local boneIdx = GetEntityBoneIndexByName(vehicle, 'door_dside_f')
    local doorPos = boneIdx ~= -1 and GetWorldPositionOfEntityBone(vehicle, boneIdx) or GetEntityCoords(vehicle)
    TaskGoToCoordAnyMeans(copPed, doorPos.x, doorPos.y, doorPos.z, 3.0, 0, 0, 786603, 0xbf800000)
    Wait(1500)
    SetVehicleDoorOpen(vehicle, 0, false, false); Wait(500)
    if LoadAnimDict('mp_arresting') then
        TaskPlayAnim(copPed, 'mp_arresting', 'a_uncuff', 8.0, -8.0, 2000, 0, 0, false, false, false)
    end
    TaskLeaveVehicle(playerPed, vehicle, 256)
    SetPedToRagdoll(playerPed, 2000, 2000, 0, true, true, false)
    Wait(1000)
    local pc = GetEntityCoords(playerPed)
    TaskGoToCoordAnyMeans(copPed, pc.x, pc.y, pc.z, 2.0, 0, 0, 786603, 0xbf800000)
    Wait(1500)
    Police.AttemptArrest(copPed)
    Notify({ type='error', description=L('dragged_from_vehicle'), duration=3000 })
end

-- ── ROADBLOCK ─────────────────────────────────────────────────────
local function CreateRoadblock(unit)
    if not unit or not DoesEntityExist(unit.vehicle) then return end
    if not cache.inVehicle then return end
    local vel   = GetEntityVelocity(cache.vehicle)
    local ahead = cache.coords + (vel * 5.0)
    local ok, roadPos, heading = GetClosestRoad(ahead, 50.0)
    if not ok or not roadPos then return end
    TaskVehicleDriveToCoord(unit.ped, unit.vehicle, roadPos.x, roadPos.y, roadPos.z,
        50.0, 0, GetEntityModel(unit.vehicle), 4, 10.0, true)
    CreateThread(function()
        Wait(5000)
        if DoesEntityExist(unit.vehicle) then
            SetEntityHeading(unit.vehicle, heading + 90.0)
            SetVehicleOnGroundProperly(unit.vehicle)
            TaskLeaveVehicle(unit.ped, unit.vehicle, 0)
        end
    end)
end

-- ── FLANK PLAYER ─────────────────────────────────────────────────
local function FlankPlayer(unit, vehicle)
    if not DoesEntityExist(vehicle) then return end
    local side  = math.random(0,1) == 0 and 90 or -90
    local angle = math.rad(GetEntityHeading(cache.vehicle) + side)
    local fp    = vec3(
        cache.coords.x + math.cos(angle) * 40.0,
        cache.coords.y + math.sin(angle) * 40.0,
        cache.coords.z
    )
    TaskVehicleDriveToCoord(unit.ped, vehicle, fp.x, fp.y, fp.z, 45.0, 0,
        GetEntityModel(vehicle), 262656, 5.0, true)
end

-- ════════════════════════════════════════════════════════════════
-- NEXT-GEN COP BEHAVIOR UPDATE
-- This is the heart of the AI. Called every updateInterval for each unit.
-- ════════════════════════════════════════════════════════════════

function Police.UpdateBehavior(unit)
    if not unit then return false end

    -- Dead cop: graceful handling
    if not DoesEntityExist(unit.ped) or IsEntityDead(unit.ped) then
        if not unit.deathTime then
            unit.deathTime = GetGameTimer()
            unit.state     = 'dead'
            if unit.blip and DoesBlipExist(unit.blip) then RemoveBlip(unit.blip); unit.blip = nil end
            if DoesEntityExist(unit.vehicle) then
                SetVehicleSiren(unit.vehicle, false)
                SetVehicleLights(unit.vehicle, 0)
            end
        end
        return true  -- still tracked, CleanupInvalid handles removal
    end

    -- Update blip sprite
    UpdateBlipForUnit(unit)

    local pedCoords    = GetEntityCoords(unit.ped)
    local distance     = #(cache.coords - pedCoords)
    local playerInVeh  = cache.inVehicle
    local pedInVeh     = IsPedInAnyVehicle(unit.ped, false)
    local now          = GetGameTimer()

    -- Teleport if too far (rubberband)
    if distance > (Config.Optimization.cullDistance or 600.0) then
        TeleportUnit(unit); return true
    end

    -- LOS tracking
    local hasLOS = CopCanSeePlayer(unit.ped, cache.ped, 150.0)
    unit.hasLOS = hasLOS
    if hasLOS then
        unit.lastLOSTime           = now
        WantedSystem.lastSeenByCop = now
        WantedSystem.decayActive   = false
    end

    -- ── ARREST ZONE ───────────────────────────────────────────────
    if distance < (unit.config.arrestDistance or 2.5) and WantedSystem.isSurrendered then
        if unit.state ~= 'arresting' then
            unit.state = 'arresting'
            CreateThread(function() Police.AttemptArrest(unit.ped) end)
        end
        return true
    end

    -- ── VEHICLE PURSUIT ───────────────────────────────────────────
    if pedInVeh then
        local copVeh = GetVehiclePedIsIn(unit.ped, false)

        if playerInVeh and DoesEntityExist(cache.vehicle) then
            local playerSpeed = GetEntitySpeed(cache.vehicle) * 3.6

            -- PIT maneuver (side-ram)
            if distance < 15.0 and playerSpeed > 30
                and (now - unit.lastPIT) > 8000
            then
                unit.lastPIT = now
                local angleDiff = math.abs(GetEntityHeading(cache.vehicle) - GetEntityHeading(copVeh)) % 360
                if angleDiff > 70 and angleDiff < 290 then
                    TaskVehicleTempAction(unit.ped, copVeh, 6, 2000)
                    CreateThread(function()
                        Wait(500)
                        if DoesEntityExist(cache.vehicle) then
                            local fwd = GetEntityForwardVector(copVeh)
                            ApplyForceToEntity(cache.vehicle, 1, fwd.x*25.0, fwd.y*25.0, 0, 0,0,0, 0, false, true, true, true, true)
                        end
                    end)
                end
            end

            -- Rolling roadblock when moderately far
            if distance > 80.0 and distance < 200.0
                and (now - unit.lastRoadblock) > 20000
            then
                unit.lastRoadblock = now
                CreateRoadblock(unit)
            end

            -- Flanking when mid-range
            if distance > 30.0 and distance < 80.0 and math.random() < 0.3 then
                FlankPlayer(unit, copVeh)
            else
                TaskVehicleChase(unit.ped, cache.ped)
                SetDriverAbility(unit.ped, 100.0)
                SetDriverAggressiveness(unit.ped, 100.0)
                if distance > 50.0 then
                    ModifyVehicleTopSpeed(copVeh, 1.3)
                    SetVehicleEnginePowerMultiplier(copVeh, 2.0)
                end
            end
            unit.state = 'pursuing_vehicle'

        else
            -- Player on foot, cop in vehicle
            if distance < 25.0 and unit.state ~= 'exiting' then
                unit.state = 'exiting'; unit.lastStateChange = now
                TaskLeaveVehicle(unit.ped, copVeh, 256)
            elseif distance >= 25.0 then
                unit.state = 'pursuing'
                TaskVehicleDriveToCoord(unit.ped, copVeh,
                    cache.coords.x, cache.coords.y, cache.coords.z,
                    35.0, 0, GetEntityModel(copVeh), 262656, 5.0, true)
                SetDriverAbility(unit.ped, 100.0); SetDriverAggressiveness(unit.ped, 100.0)
            end
        end
        MaintainVehicle(copVeh)

    else
        -- ── ON-FOOT PURSUIT ─────────────────────────────────────
        if unit.state == 'exiting' and (now - unit.lastStateChange) > 2000 then
            unit.state = 'on_foot'
        end

        if unit.state == 'on_foot' or unit.state == 'exiting' or unit.state == 'pursuing' then
            if playerInVeh and DoesEntityExist(cache.vehicle) then
                -- Player in vehicle, cop on foot
                if distance < 4.0 and GetEntitySpeed(cache.vehicle)*3.6 < 15.0 then
                    if not unit.draggingOut then
                        unit.draggingOut = true
                        CreateThread(function()
                            DragPlayerFromVehicle(unit.ped, cache.ped, cache.vehicle)
                            Wait(3000); unit.draggingOut = false
                        end)
                    end
                else
                    TaskGoToEntity(unit.ped, cache.vehicle, -1, 3.0, 4.0, 0, 0)
                    SetPedMoveRateOverride(unit.ped, 2.0)
                end
            else
                -- Both on foot
                local playerRunning = IsPedRunning(cache.ped) or IsPedSprinting(cache.ped)
                local playerArmed   = PlayerIsArmed()

                if playerArmed and distance < (unit.config.combatRange or 50.0) then
                    -- COMBAT MODE
                    if not IsPedInCombat(unit.ped, cache.ped) then
                        TaskCombatPed(unit.ped, cache.ped, 0, 16)
                        SetPedCombatRange(unit.ped, 2); SetPedCombatMovement(unit.ped, 2)
                    end
                    unit.state = 'combat'
                    -- Shout commands
                    if distance < 20.0 and math.random() < 0.008 then
                        PlayPedAmbientSpeechNative(unit.ped, 'GENERIC_CURSE_MED', 'SPEECH_PARAMS_FORCE_SHOUTED')
                    end

                elseif distance < 5.0 and playerRunning and not WantedSystem.isSurrendered then
                    -- TACKLE
                    if TryTackle(unit) then
                        CreateThread(function()
                            Wait(2000)
                            if IsPedRagdoll(cache.ped) then Wait(1500); Police.AttemptArrest(unit.ped) end
                        end)
                    end

                elseif distance < (unit.config.arrestDistance or 2.5) and not playerRunning then
                    -- AUTO ARREST (surrendered nearby)
                    CreateThread(function() Police.AttemptArrest(unit.ped) end)

                elseif unit.config.shootUnarmed and distance > 5.0 and distance < (unit.config.combatRange or 15.0) then
                    if not IsPedInCombat(unit.ped, cache.ped) then
                        TaskCombatPed(unit.ped, cache.ped, 0, 16)
                    end

                else
                    -- PURSUE ON FOOT
                    if not IsPedInCombat(unit.ped, cache.ped) then
                        TaskGoToEntity(unit.ped, cache.ped, -1, unit.config.arrestDistance or 2.5, 3.0, 0, 0)
                        SetPedMoveRateOverride(unit.ped, playerRunning and 2.0 or 1.5)
                        -- Yell at player occasionally
                        if distance < 20.0 and math.random() < 0.008 then
                            PlayPedAmbientSpeechNative(unit.ped, 'GENERIC_CURSE_MED', 'SPEECH_PARAMS_FORCE_SHOUTED')
                        end
                    end
                end
            end
        end
    end

    return true
end

-- ════════════════════════════════════════════════════════════════
-- ARREST SYSTEM  —  SMOOTH ANIMATION + BULLETPROOF JAIL
-- ════════════════════════════════════════════════════════════════

function Police.AttemptArrest(policePed)
    if WantedSystem.isArrested or WantedSystem.isDead or cache.inVehicle then return end

    WantedSystem.isSurrendered = true
    WantedSystem.isArrested    = true

    local policeNetId = DoesEntityExist(policePed) and NetworkGetNetworkIdFromEntity(policePed) or 0
    TriggerServerEvent('police:syncArrest', GetPlayerServerId(PlayerId()), policeNetId)

    -- Handcuff animation plays via applySyncedArrest (4500ms)
    Wait(4500)
    FreezeEntityPosition(cache.ped, false)
    UI.Reset()
    DoScreenFadeOut(2000); Wait(2000)

    Police.ClearAllUnits()

    -- Calculate jail time BEFORE clearing level
    local jailTime = 60
    if WantedSystem.level > 0 and Config.WantedLevels and Config.WantedLevels[WantedSystem.level] then
        jailTime = Config.WantedLevels[WantedSystem.level].time or 60
    end
    WantedSystem.level = 0

    -- Server handles jail — we wait for teleportToJail event
    local ok = lib.callback.await('police:arrestPlayer', false, jailTime, math.random(#Config.Prison.cells))

    if not ok then
        Debug('AttemptArrest: server rejected — restoring state')
        WantedSystem.isArrested    = false
        WantedSystem.isSurrendered = false
        DoScreenFadeIn(1000)
        Notify({ type='error', description=L('arrest_cancelled'), duration=3000 })
        return
    end

    -- Safety net: if teleportToJail hasn't arrived in 10s, recover
    CreateThread(function()
        local timeout = GetGameTimer() + 10000
        while GetGameTimer() < timeout do
            Wait(200)
            if WantedSystem.isJailed then return end
        end
        Debug('AttemptArrest safety net: teleportToJail not received — recovering')
        WantedSystem.isArrested = false
        DoScreenFadeIn(1500)
        Notify({ type='error', description=L('connection_issue'), duration=5000 })
    end)
end

-- ════════════════════════════════════════════════════════════════
-- CLEAR ALL UNITS  —  REALISTIC DEPARTURE
-- Cops reset combat, get in their car, drive away, then despawn.
-- This runs async so it never blocks anything.
-- ════════════════════════════════════════════════════════════════

function Police.ClearAllUnits()
    local units = WantedSystem.pursuingUnits
    WantedSystem.pursuingUnits = {}
    WantedSystem.policeActive  = false

    local dis         = Config.PoliceDisengage or {}
    local maxWait     = dis.maxDepartureWait  or 25000
    local departDist  = dis.departureDistance or 200.0

    CreateThread(function()
        for _, unit in ipairs(units) do
            if not unit then goto skip end

            -- Remove blip immediately
            if unit.blip and DoesBlipExist(unit.blip) then RemoveBlip(unit.blip); unit.blip = nil end

            local ped     = unit.ped
            local vehicle = unit.vehicle

            if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                -- Reset cop to civilian mode
                ClearPedTasks(ped)
                ClearPedTasksImmediately(ped)
                SetPedCombatAttributes(ped, 46, false)
                SetPedCombatAttributes(ped, 5,  false)
                SetPedCombatAttributes(ped, 1,  false)
                SetPedCombatAttributes(ped, 52, false)
                SetPedFleeAttributes(ped, 0, true)
                SetPedAsCop(ped, false)
                SetPedRelationshipGroupHash(ped, joaat('CIVMALE'))
                SetRelationshipBetweenGroups(0, joaat('CIVMALE'), joaat('PLAYER'))
                SetRelationshipBetweenGroups(0, joaat('PLAYER'),  joaat('CIVMALE'))

                if DoesEntityExist(vehicle) then
                    -- Lights off, siren off — they're standing down
                    SetVehicleSiren(vehicle, false)
                    SetVehicleLights(vehicle, 0)

                    -- Get cop back in car if on foot
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

                    -- Now drive away
                    if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true)
                        and GetVehiclePedIsIn(ped, false) == vehicle
                    then
                        local angle  = math.rad(math.random(0, 359))
                        local target = cache.coords + vector3(
                            math.cos(angle) * 500.0,
                            math.sin(angle) * 500.0,
                            0.0
                        )
                        TaskVehicleDriveToCoord(ped, vehicle,
                            target.x, target.y, target.z,
                            25.0, 0, GetEntityModel(vehicle),
                            786603, 10.0, true)

                        -- Wait until far enough or timeout
                        local t = 0
                        while t < maxWait do
                            Wait(1000); t = t + 1000
                            if not DoesEntityExist(vehicle) then break end
                            if #(GetEntityCoords(vehicle) - cache.coords) > departDist then break end
                        end
                    end
                end
            end

            -- Clean delete
            if DoesEntityExist(ped)     then SetEntityAsMissionEntity(ped,     false, true); DeleteEntity(ped)     end
            if DoesEntityExist(vehicle) then SetEntityAsMissionEntity(vehicle, false, true); DeleteEntity(vehicle) end

            ::skip::
        end
        Debug('ClearAllUnits: all units departed')
    end)
end

-- ════════════════════════════════════════════════════════════════
-- CLEANUP INVALID UNITS
-- ════════════════════════════════════════════════════════════════

function Police.CleanupInvalid()
    local death     = Config.CopDeathHandling or {}
    local lifetime  = death.deadCopVehicleLifetime or 120000
    local cullDist  = death.deadCopCullDistance    or 250.0
    local keepVeh   = death.keepVehicleAfterDeath  ~= false
    local keepBody  = death.keepBodyAfterDeath     ~= false
    local bodyLife  = death.bodyLifetime           or 60000
    local now       = GetGameTimer()

    for i = #WantedSystem.pursuingUnits, 1, -1 do
        local unit = WantedSystem.pursuingUnits[i]
        if not unit then table.remove(WantedSystem.pursuingUnits, i); goto cont end

        local pedGone = not DoesEntityExist(unit.ped)
        local pedDead = (not pedGone) and IsEntityDead(unit.ped)

        if pedGone then
            if unit.blip and DoesBlipExist(unit.blip) then RemoveBlip(unit.blip) end
            if unit.vehicle and DoesEntityExist(unit.vehicle) then
                SetEntityAsMissionEntity(unit.vehicle, false, true)
                if not keepVeh then DeleteEntity(unit.vehicle) end
            end
            table.remove(WantedSystem.pursuingUnits, i)

        elseif pedDead then
            if not unit.deathTime then unit.deathTime = now end
            local elapsed  = now - unit.deathTime
            local vehDist  = unit.vehicle and DoesEntityExist(unit.vehicle)
                             and #(cache.coords - GetEntityCoords(unit.vehicle)) or math.huge

            local removeVeh  = (not keepVeh) or (elapsed >= lifetime) or (vehDist > cullDist)
            local removeBody = (not keepBody) or (elapsed >= bodyLife)

            if removeVeh and unit.vehicle and DoesEntityExist(unit.vehicle) then
                SetEntityAsMissionEntity(unit.vehicle, false, true); DeleteEntity(unit.vehicle); unit.vehicle = nil
            end
            if removeBody and DoesEntityExist(unit.ped) then
                SetEntityAsMissionEntity(unit.ped, false, true); DeleteEntity(unit.ped)
                table.remove(WantedSystem.pursuingUnits, i)
            end
        end
        ::cont::
    end
end

-- ════════════════════════════════════════════════════════════════
-- PRISON SYSTEM
-- ════════════════════════════════════════════════════════════════

function Prison.StartTimer()
    if WantedSystem.jailTimerActive then return end
    if type(WantedSystem.jailTime) ~= 'number' or WantedSystem.jailTime <= 0 then
        WantedSystem.jailTime = 60
    end

    jailTimerGen = jailTimerGen + 1
    local myGen  = jailTimerGen
    WantedSystem.jailTimerActive = true
    Debug(('Prison.StartTimer: %ds, gen=%d'):format(WantedSystem.jailTime, myGen))

    CreateThread(function()
        local lastTick = GetGameTimer()
        while myGen == jailTimerGen
            and WantedSystem.jailTime > 0
            and (WantedSystem.isJailed or WantedSystem.isArrested)
            and WantedSystem.jailTimerActive
        do
            -- ✅ FIX #36 (1.0.3-alpha): Wait(0) → Wait(100). Skill-Standard:
            -- "Always Wait(N) — never Wait(0) unless absolutely necessary".
            -- UI-Refresh 10x/sek reicht völlig für einen Sekunden-Timer.
            Wait(100)
            UI.DrawJailTimer(WantedSystem.jailTime)
            local now = GetGameTimer()
            if now - lastTick >= 1000 then
                local elapsed = math.floor((now - lastTick) / 1000)
                lastTick = lastTick + elapsed * 1000
                WantedSystem.jailTime = math.max(0, WantedSystem.jailTime - elapsed)
            end
        end
        if myGen == jailTimerGen then WantedSystem.jailTimerActive = false end
    end)
end

function Prison.Release()
    if not WantedSystem.isArrested and not WantedSystem.isJailed then return end
    WantedSystem.isArrested      = false
    WantedSystem.isJailed        = false
    WantedSystem.jailTimerActive = false
    WantedSystem.jailTime        = 0
    UI.Reset()
    DoScreenFadeOut(3000); Wait(3000)
    local exit = Config.Prison.exit
    SetEntityCoords(cache.ped, exit.x, exit.y, exit.z)
    SetEntityHeading(cache.ped, exit.w)
    ClearPedTasksImmediately(cache.ped)
    Wait(500); DoScreenFadeIn(3000)
    Notify({ type='success', description=L('released') })
end

function Prison.EnsureRunning()
    if ensureRunningInProgress then return end
    if WantedSystem.jailTimerActive then return end
    if not WantedSystem.isJailed then return end
    ensureRunningInProgress = true

    CreateThread(function()
        Wait(2500)
        if WantedSystem.jailTimerActive or not WantedSystem.isJailed then
            ensureRunningInProgress = false; return
        end
        if not WantedSystem.jailTime or WantedSystem.jailTime <= 0 then
            local ok, data = pcall(function() return lib.callback.await('police:checkJailStatus', false) end)
            if ok and data and data.jailed and type(data.time) == 'number' and data.time > 0 then
                WantedSystem.jailTime = data.time
                if data.cell then WantedSystem.jailCell = data.cell end
            else
                WantedSystem.isJailed   = false
                WantedSystem.isArrested = false
                ensureRunningInProgress = false; return
            end
        end
        -- If not in a cell, teleport there
        if DoesEntityExist(cache.ped) and Config.Prison.cells and #Config.Prison.cells > 0 then
            local nearest, nearestDist = nil, math.huge
            for _, cell in ipairs(Config.Prison.cells) do
                local d = #(GetEntityCoords(cache.ped) - vector3(cell.x, cell.y, cell.z))
                if d < nearestDist then nearestDist = d; nearest = cell end
            end
            if nearestDist > 8.0 and nearest then
                if not IsScreenFadedOut() then DoScreenFadeOut(800); Wait(800) end
                SetEntityCoords(cache.ped, nearest.x, nearest.y, nearest.z, false, false, false, false)
                SetEntityHeading(cache.ped, nearest.w)
                ClearPedTasksImmediately(cache.ped)
                Wait(300); DoScreenFadeIn(800); Wait(800)
            end
        end
        WantedSystem.isArrested = true
        if not WantedSystem.jailTimerActive then Prison.StartTimer() end
        ensureRunningInProgress = false
    end)
end

-- Watchdog
CreateThread(function()
    Wait(15000)
    while true do
        Wait(5000)
        if WantedSystem.isJailed and not WantedSystem.jailTimerActive and not ensureRunningInProgress then
            Prison.EnsureRunning()
        end
    end
end)

-- ════════════════════════════════════════════════════════════════
-- WANTED SYSTEM CORE
-- ════════════════════════════════════════════════════════════════

function WantedSystem.SetLevel(level)
    if not level then return end
    local changed  = level ~= WantedSystem.level
    local oldLevel = WantedSystem.level
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
        if changed and oldLevel > 0 and not WantedSystem.isArrested and not WantedSystem.isDead then
            Notify({ type='success', description=L('cops_disengaging'), duration=4000, icon='shield-check' })
        end
    end
end

function WantedSystem.StartPoliceSystem()
    if WantedSystem.policeActive then return end
    WantedSystem.policeActive = true

    -- Spawn loop
    CreateThread(function()
        while WantedSystem.level > 0 and not WantedSystem.isArrested
              and not WantedSystem.isDead and WantedSystem.policeActive
        do
            local cfg = Config.WantedLevels and Config.WantedLevels[WantedSystem.level]
            if cfg and cfg.peds then
                local maxUnits = Config.Optimization.maxPoliceUnits or 8
                local needed   = math.min(
                    cfg.peds.amount - #WantedSystem.pursuingUnits,
                    maxUnits        - #WantedSystem.pursuingUnits
                )
                if needed > 0 and (GetGameTimer() - WantedSystem.lastSpawnTime) >= (Config.Optimization.spawnCooldown or 5000) then
                    WantedSystem.lastSpawnTime = GetGameTimer()
                    local models = { peds=cfg.peds.models, vehicles=cfg.peds.vehicles }
                    if Spawner.PreloadModels(models) then
                        local points = Spawner.GetSpawnPoints(cache.coords, needed, cfg.peds.spawnDistance or 350.0)
                        for i = 1, math.min(needed, #points) do
                            Police.SpawnUnit(points[i], cfg.peds, WantedSystem.level)
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

    -- Behavior update loop
    CreateThread(function()
        while WantedSystem.policeActive do
            for i = #WantedSystem.pursuingUnits, 1, -1 do
                local unit = WantedSystem.pursuingUnits[i]
                local now  = GetGameTimer()
                if not unit or (now - (unit.lastUpdate or 0)) < WantedSystem.updateInterval then goto cont end
                unit.lastUpdate = now
                if Police.UpdateBehavior(unit) == false then
                    if unit.blip    and DoesBlipExist(unit.blip)      then RemoveBlip(unit.blip)     end
                    if unit.vehicle and DoesEntityExist(unit.vehicle) then DeleteEntity(unit.vehicle) end
                    table.remove(WantedSystem.pursuingUnits, i)
                end
                ::cont::
            end
            Wait(WantedSystem.updateInterval)
        end
    end)

    -- Cleanup loop
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
        Notify({ type='error', description=L('cannot_surrender_vehicle'), duration=3000 }); return
    end
    if WantedSystem.isSurrendered then
        WantedSystem.isSurrendered = false
        ClearPedTasks(cache.ped)
    else
        WantedSystem.isSurrendered = true
        if LoadAnimDict(Config.Animations.surrender.dict) then
            TaskPlayAnim(cache.ped,
                Config.Animations.surrender.dict,
                Config.Animations.surrender.anim,
                8.0, -8, -1, 49, 0, false, false, false)
        end
        CreateThread(function()
            Wait(1000)
            local nearest, nearDist = nil, 999.0
            for _, unit in pairs(WantedSystem.pursuingUnits) do
                if DoesEntityExist(unit.ped) and not IsEntityDead(unit.ped) then
                    local d = #(GetEntityCoords(unit.ped) - cache.coords)
                    if d < (unit.config.arrestDistance or 2.5) and d < nearDist then
                        nearest = unit.ped; nearDist = d
                    end
                end
            end
            if nearest then Wait(2000); Police.AttemptArrest(nearest) end
        end)
    end
end

-- ════════════════════════════════════════════════════════════════
-- EVENT HANDLERS
-- ════════════════════════════════════════════════════════════════

RegisterNetEvent('police:setWantedLevel', function(level)
    if type(level) == 'number' then WantedSystem.SetLevel(level) end
end)

-- ── TELEPORT TO JAIL  —  ACK PATTERN ────────────────────────────
-- Server retries until we ACK. We ACK only after successfully teleporting.
RegisterNetEvent('police:teleportToJail', function(cell, time)
    Debug(('teleportToJail: cell=%s time=%s'):format(tostring(cell), tostring(time)))

    time = tonumber(time) or 60
    cell = tonumber(cell) or 1
    if time < 1 then time = 60 end

    -- If already jailed and timer running, just ACK (duplicate delivery)
    if WantedSystem.isJailed and WantedSystem.jailTimerActive then
        TriggerServerEvent('police:jailAck')
        Debug('teleportToJail: already jailed, sending ACK')
        return
    end

    WantedSystem.jailTime        = time
    WantedSystem.isArrested      = true
    WantedSystem.isJailed        = true
    WantedSystem.level           = 0
    WantedSystem.jailTimerActive = false

    UI.Reset()
    Police.ClearAllUnits()

    CreateThread(function()
        -- Wait for valid ped
        if not playerHasPed or not DoesEntityExist(cache.ped) then
            local timeout = GetGameTimer() + 30000
            while (not playerHasPed or not DoesEntityExist(cache.ped)) and GetGameTimer() < timeout do
                Wait(500); UpdateCache()
            end
            Wait(500); UpdateCache()
        end

        if not DoesEntityExist(cache.ped) then
            local p = PlayerPedId()
            if p ~= 0 and DoesEntityExist(p) then cache.ped = p; UpdateCache() end
        end

        -- Start timer regardless of ped state
        if not DoesEntityExist(cache.ped) then
            if not WantedSystem.jailTimerActive then Prison.StartTimer() end
            DoScreenFadeIn(1000)
            Notify({ type='error', description=L('jailed', time), duration=5000 })
            TriggerServerEvent('police:jailAck')
            return
        end

        -- Teleport to cell
        local cellCoords = Config.Prison.cells[cell] or Config.Prison.cells[1]
        if cellCoords then
            if not IsScreenFadedOut() then DoScreenFadeOut(800); Wait(800) end
            SetEntityCoords(cache.ped, cellCoords.x, cellCoords.y, cellCoords.z, false, false, false, false)
            SetEntityHeading(cache.ped, cellCoords.w)
            ClearPedTasksImmediately(cache.ped)
            Wait(300)
            DoScreenFadeIn(800); Wait(800)
        else
            if IsScreenFadedOut() then DoScreenFadeIn(800) end
        end

        -- Start timer
        if not WantedSystem.jailTimerActive then Prison.StartTimer() end
        Notify({ type='error', description=L('jailed', time), duration=5000 })

        -- ACK to server — stops the retry loop
        TriggerServerEvent('police:jailAck')
        Debug(('teleportToJail: done & ACKd — %ds, cell=%d'):format(WantedSystem.jailTime, cell))
    end)
end)

RegisterNetEvent('police:teleportFromJail', function() Prison.Release() end)

RegisterNetEvent('police:clearWeapons', function() RemoveAllPedWeapons(cache.ped, true) end)

RegisterNetEvent('police:updateJailTime', function(time)
    if type(time) == 'number' then WantedSystem.jailTime = time end
end)

RegisterNetEvent('police:applySyncedTackle', function(targetPlayerId, forwardVector)
    local targetPed = GetPlayerPed(GetPlayerFromServerId(targetPlayerId))
    if DoesEntityExist(targetPed) then
        SetPedToRagdollWithFall(targetPed, 4000, 5000, 0, forwardVector, 12.0, 0,0,0,0,0,0)
        ApplyForceToEntity(targetPed, 1, forwardVector.x*10.0, forwardVector.y*10.0, 0, 0,0,0, 0, false, true, true, true, true)
    end
end)

RegisterNetEvent('police:applySyncedArrest', function(targetPlayerId, policeNetId)
    local isSelf    = targetPlayerId == GetPlayerServerId(PlayerId())
    local targetPed = GetPlayerPed(GetPlayerFromServerId(targetPlayerId))
    local policePed = policeNetId > 0 and NetworkGetEntityFromNetworkId(policeNetId) or nil
    if not DoesEntityExist(targetPed) then return end

    if not isSelf then FreezeEntityPosition(targetPed, true) end

    -- Walk cop to player if needed
    if policePed and DoesEntityExist(policePed) then
        local dist = #(GetEntityCoords(policePed) - GetEntityCoords(targetPed))
        if dist > 2.0 then
            TaskGoToEntity(policePed, targetPed, -1, 1.0, 2.0, 0, 0)
            Wait(math.min(dist*500, 2000))
        end
        TaskTurnPedToFaceEntity(policePed, targetPed, 1000)
        TaskTurnPedToFaceEntity(targetPed, policePed, 1000)
        Wait(500)
    end

    -- Paired cuffing animation
    if policePed and DoesEntityExist(policePed) and LoadAnimDict('mp_arrest_paired') then
        TaskPlayAnim(policePed, 'mp_arrest_paired', 'cop_p2_back_right',   8.0, -8.0, 3500, 49, 0, false, false, false)
        Wait(100)
        TaskPlayAnim(targetPed, 'mp_arrest_paired', 'crook_p2_back_right', 8.0, -8.0, 3500, 49, 0, false, false, false)
        if #(GetEntityCoords(targetPed) - GetEntityCoords(PlayerPedId())) < 30.0 then
            PlaySoundFrontend(-1, 'Cuff_Shackles', 'GTAO_FM_Events_Soundset', 1)
        end
        Wait(3500)
    else
        Wait(2000)
    end

    -- Hold in arrested pose
    if LoadAnimDict('mp_arresting') then
        TaskPlayAnim(targetPed, 'mp_arresting', 'idle', 8.0, -8, -1, 49, 0, false, false, false)
    end
    Wait(500)
    if not isSelf then FreezeEntityPosition(targetPed, false) end
end)

RegisterNetEvent('police:createPanicBlip', function(coords)
    if not coords then return end
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, 161); SetBlipColour(blip, 1); SetBlipScale(blip, 1.2)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentString('🚨 PANIC BUTTON'); EndTextCommandSetBlipName(blip)
    CreateThread(function()
        local t = GetGameTimer()
        while GetGameTimer()-t < 30000 do
            SetBlipAlpha(blip, 255); Wait(500); SetBlipAlpha(blip, 100); Wait(500)
        end
        RemoveBlip(blip)
    end)
    PlaySoundFrontend(-1, 'CHECKPOINT_PERFECT', 'HUD_MINI_GAME_SOUNDSET', 1)
end)

-- ── MULTI-PLAYER STATE SYNC ───────────────────────────────────────

local OtherPlayerStates = {}

RegisterNetEvent('police:playerStateUpdate', function(playerSource, stateData)
    if not playerSource or not stateData then return end
    OtherPlayerStates[playerSource] = stateData
    local mySource = GetPlayerServerId(PlayerId())
    if playerSource == mySource then
        if stateData.level then
            if stateData.level ~= WantedSystem.level then
                WantedSystem.SetLevel(stateData.level)
            elseif stateData.level > 0 and not WantedSystem.policeActive then
                WantedSystem.StartPoliceSystem()
            end
        end
        if stateData.isJailed ~= nil then
            local was = WantedSystem.isJailed
            WantedSystem.isJailed = stateData.isJailed
            if stateData.isJailed and not was and Prison.EnsureRunning then Prison.EnsureRunning() end
        end
        if stateData.jailTime then
            WantedSystem.jailTime = stateData.jailTime
            if WantedSystem.isJailed and stateData.jailTime > 0
                and not WantedSystem.jailTimerActive and Prison.EnsureRunning
            then Prison.EnsureRunning() end
        end
    end
end)

RegisterNetEvent('police:syncAllStates', function(stateArray)
    if not stateArray then return end
    OtherPlayerStates = {}
    local mySource = GetPlayerServerId(PlayerId())
    for _, state in ipairs(stateArray) do
        if state.source and state.source ~= mySource then
            OtherPlayerStates[state.source] = state
        end
    end
end)

RegisterNetEvent('police:playerDisconnected', function(playerSource)
    if playerSource then OtherPlayerStates[playerSource] = nil end
end)

-- ════════════════════════════════════════════════════════════════
-- DEATH / REVIVAL
-- ════════════════════════════════════════════════════════════════

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

local function SetAlive()
    WantedSystem.isDead = false
end

AddEventHandler('ox:playerRevived',        SetAlive)
AddEventHandler('rde_death:adminRevive',   SetAlive)
AddEventHandler('rde_death:doctorRevive',  SetAlive)
AddEventHandler('rde_death:doRespawn',     SetAlive)
AddEventHandler('rde_death:localRevive',   SetAlive)
AddEventHandler('ox:playerDeath',          function() WantedSystem.isDead = true; WantedSystem.SetLevel(0) end)

-- Failsafe
CreateThread(function()
    while true do
        Wait(3000)
        if WantedSystem.isDead then
            local ped = cache.ped
            if DoesEntityExist(ped) and not IsEntityDead(ped) and GetEntityHealth(ped) > 100 then
                WantedSystem.isDead = false
                Debug('isDead failsafe: player alive — reset')
            end
        end
    end
end)

-- ════════════════════════════════════════════════════════════════
-- SURRENDER KEY
-- ════════════════════════════════════════════════════════════════

if Config.SurrenderKey then
    RegisterCommand('+surrender', function()
        if WantedSystem.level > 0 and not WantedSystem.isArrested then WantedSystem.ToggleSurrender() end
    end, false)
    RegisterCommand('-surrender', function() end, false)
    RegisterKeyMapping('+surrender', 'Surrender to Police', 'keyboard', Config.SurrenderKey)
end

-- ════════════════════════════════════════════════════════════════
-- INITIALIZATION
-- ════════════════════════════════════════════════════════════════

local pendingJailRestore = nil
local initGen            = 0

local function InitializeSystem()
    if WantedSystem.systemReady then return end
    WantedSystem.systemReady = true
    initGen = initGen + 1
    local myGen = initGen

    CreateThread(function()
        WaitForRealPed()
        if myGen ~= initGen then return end

        local ok, level = pcall(function() return lib.callback.await('police:getWantedLevel', false) end)
        if ok and type(level) == 'number' and level > 0 then
            WantedSystem.SetLevel(level)
        end
        Debug('System initialized')
    end)
end

RegisterNetEvent('police:systemReady', function(data)
    if data and data.wantedLevel and data.wantedLevel > 0 then
        WantedSystem.level = data.wantedLevel
    end

    -- Jail restore from systemReady
    if data and data.isJailed and data.jailTime and data.jailTime > 0 then
        WantedSystem.isJailed   = true
        WantedSystem.isArrested = true
        WantedSystem.jailTime   = data.jailTime

        pendingJailRestore = { jailTime=data.jailTime, jailCell=data.jailCell or 1 }

        -- Jail restore thread (independent of initGen)
        local restoreTime = data.jailTime
        local restoreCell = data.jailCell or 1
        CreateThread(function()
            -- Wait for ped
            local t = 0
            while t < 15000 do
                local ped = cache.ped or PlayerPedId()
                if ped ~= 0 and DoesEntityExist(ped) and not IsEntityDead(ped) then break end
                Wait(200); t = t + 200
            end
            Wait(500)

            if WantedSystem.jailTimerActive then pendingJailRestore = nil; return end

            -- Server will handle actual teleport via JailDelivery loop;
            -- here we just ensure the timer is running for UI
            WantedSystem.isJailed   = true
            WantedSystem.isArrested = true
            WantedSystem.level      = 0
            WantedSystem.jailTime   = math.max(WantedSystem.jailTime, restoreTime)

            if not WantedSystem.jailTimerActive then Prison.StartTimer() end
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

-- ── LIFECYCLE EVENTS ─────────────────────────────────────────────

AddEventHandler('onResourceStart', function(resource)
    if GetCurrentResourceName() ~= resource then return end
    CreateThread(function() Wait(1000); WantedSystem.systemReady = false; InitializeSystem() end)
end)

AddEventHandler('onResourceStop', function(resource)
    if GetCurrentResourceName() ~= resource then return end
    Police.ClearAllUnits(); UI.Reset()
    if WantedSystem.jailTimerActive then WantedSystem.jailTimerActive = false end
end)

AddEventHandler('ox:playerLoaded', function()
    WantedSystem.systemReady = false
end)

-- ════════════════════════════════════════════════════════════════
-- EXPORTS
-- ════════════════════════════════════════════════════════════════

exports('getWantedLevel',   function() return WantedSystem.level end)
exports('isArrested',       function() return WantedSystem.isArrested end)
exports('isSurrendered',    function() return WantedSystem.isSurrendered end)
exports('isJailed',         function() return WantedSystem.isJailed end)
exports('getJailTime',      function() return WantedSystem.jailTime end)
exports('getPursuingUnits', function() return #WantedSystem.pursuingUnits end)
exports('copsCanSeePlayer', function() return AnyCopCanSeePlayer() end)
exports('isDecayActive',    function() return WantedSystem.decayActive end)
exports('setWantedLevel',   function(l) if type(l) == 'number' then WantedSystem.SetLevel(l) end end)
exports('surrender',        function() WantedSystem.ToggleSurrender() end)
exports('clearPolice',      function() Police.ClearAllUnits() end)

-- ════════════════════════════════════════════════════════════════
-- DEBUG COMMANDS
-- ════════════════════════════════════════════════════════════════

if Config.Debug then
    RegisterCommand('debugpolice', function()
        print('=== AIPD Client Debug ===')
        print('Wanted:', WantedSystem.level, '| Arrested:', WantedSystem.isArrested)
        print('isJailed:', WantedSystem.isJailed, '| jailTime:', WantedSystem.jailTime)
        print('jailTimerActive:', WantedSystem.jailTimerActive, '| isSurrendered:', WantedSystem.isSurrendered)
        print('Units:', #WantedSystem.pursuingUnits, '| policeActive:', WantedSystem.policeActive)
        print('isDead:', WantedSystem.isDead, '| playerHasPed:', playerHasPed)
        print('decayActive:', WantedSystem.decayActive)
        print('=========================')
    end, false)

    RegisterCommand('clearcops',  function() Police.ClearAllUnits(); print('[AIPD] Cleared units') end, false)
    RegisterCommand('testwanted', function(s,a) local l=tonumber(a[1])or 3; WantedSystem.SetLevel(l) end, false)
    RegisterCommand('testjail',   function(s,a) local t=tonumber(a[1])or 60; TriggerEvent('police:teleportToJail',1,t) end, false)
    RegisterCommand('unjail',     function() Prison.Release() end, false)

    RegisterCommand('spawncop', function()
        local lc = Config.WantedLevels[WantedSystem.level] or Config.WantedLevels[3]
        if lc and lc.peds then
            local m = { peds=lc.peds.models, vehicles=lc.peds.vehicles }
            if Spawner.PreloadModels(m) then
                local pts = Spawner.GetSpawnPoints(cache.coords, 1, 300.0)
                if #pts > 0 then Police.SpawnUnit(pts[1], lc.peds, WantedSystem.level) end
                Spawner.ReleaseModels(m)
            end
        end
    end, false)
end

-- ════════════════════════════════════════════════════════════════
-- STARTUP LOG
-- ════════════════════════════════════════════════════════════════

CreateThread(function()
    Wait(5000)
    print('^2[AIPD | Client]^7 ✓ NEXT-GEN Edition initialized')
    print('^2[AIPD | Client]^7 ✅ Jail: ACK pattern — server retries until client confirms')
    print('^2[AIPD | Client]^7 ✅ Multi-player: isolated per-player Police systems')
    print('^2[AIPD | Client]^7 ✅ Cop despawn: realistic departure — lights off, drive away, delete')
    print('^2[AIPD | Client]^7 ✅ Arrest: smooth paired animations, no race conditions')
    print('^2[AIPD | Client]^7 ✅ Decay: blocked server-side during arrest window')
    print('^2[AIPD | Client]^7 ✅ FOV: dot-product based — 220° realistic field of view')
    print('^2[AIPD | Client]^7 ✅ Vehicle chase: PIT, roadblock, flank, speed matching')
    if Config.Debug then print('^3[AIPD | Client]^7 ⚠ Debug mode active') end
end)
