-- ============================================================
-- client/modules/organization/house/junk/main.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Junk (cleaning) system for org houses.
-- A lib.class-based Junk object manages spawning, tracking,
-- fade-out removal and pickup interactions for junk items.
-- ============================================================

local MAX_SPAWN_ATTEMPTS = 15

local Junk = lib.class("Junk")

-- ──────────────────────────────────────────────────────────
-- constructor
-- ──────────────────────────────────────────────────────────
function Junk:constructor()
    self.objects             = {}
    self.active              = false
    self.isLoopRunning       = false
    self.pendingCoordUpdates = {}
    return self
end

-- ──────────────────────────────────────────────────────────
-- Junk:spawnObject(modelName, coords) → handle | nil
--   Spawns a frozen world object at coords (ground-snapped).
-- ──────────────────────────────────────────────────────────
function Junk:spawnObject(modelName, coords)
    local hash = joaat(modelName)
    lib.requestModel(hash, Config.DefaultRequestModelTimeout)

    if not HasModelLoaded(hash) then
        Debug("Junk:spawnObject - Model not loaded:", modelName)
        return nil
    end

    local groundZ = self:getGroundZ(coords)
    local spawnPos = vec3(coords.x, coords.y, groundZ)

    local handle = CreateObject(hash,
        spawnPos.x, spawnPos.y, spawnPos.z, false, false, false)

    if not DoesEntityExist(handle) then
        Debug("Junk:spawnObject - Failed to create object:", modelName)
        SetModelAsNoLongerNeeded(hash)
        return nil
    end

    PlaceObjectOnGroundProperly(handle)
    FreezeEntityPosition(handle, true)
    SetEntityAsMissionEntity(handle, false, true)
    SetModelAsNoLongerNeeded(hash)
    SetEntityHeading(handle, math.random(0, 360) + 0.0)

    Debug("Junk:spawnObject - Spawned:", modelName, "at", spawnPos, "handle:", handle)
    return handle
end

-- ──────────────────────────────────────────────────────────
-- Junk:getGroundZ(coords) → z
-- ──────────────────────────────────────────────────────────
function Junk:getGroundZ(coords)
    local z = coords.z
    local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 5.0, false)
    if found and groundZ then z = groundZ end
    return z
end

-- ──────────────────────────────────────────────────────────
-- Junk:getHouseTypeInfo(houseId) → isShell, origin, dimMin, dimMax
--   Returns shell bounding-box data for coordinate generation.
-- ──────────────────────────────────────────────────────────
function Junk:getHouseTypeInfo(houseId)
    local org = OrganizationManager:get(houseId)
    if not org then return false, nil, nil, nil end

    if org.type == "shell" then
        local shellData = Config.Shells[org.interior_data.tier]
        if shellData and shellData.model then
            local hash = joaat(shellData.model)
            lib.requestModel(hash, Config.DefaultRequestModelTimeout)
            if HasModelLoaded(hash) then
                local dimMin, dimMax = GetModelDimensions(hash)
                local origin = vec3(
                    org.interior_data.coords.x,
                    org.interior_data.coords.y,
                    org.interior_data.coords.z)
                SetModelAsNoLongerNeeded(hash)
                Debug("Junk:getHouseTypeInfo - Shell dimensions:", dimMin, dimMax)
                return true, origin, dimMin, dimMax
            end
        end
    end

    return false, nil, nil, nil
end

-- ──────────────────────────────────────────────────────────
-- Junk:generateRandomCoords(houseId) → vec3 | nil
--   Generates a random interior-valid position near the house.
-- ──────────────────────────────────────────────────────────
function Junk:generateRandomCoords(houseId)
    local org = OrganizationManager:get(houseId)
    if not org then
        Debug("Junk:generateRandomCoords - No house data for:", houseId)
        return nil
    end

    local exitCoords = org.interior_data and org.interior_data.exit
    if not exitCoords then
        Debug("Junk:generateRandomCoords - No exit coords for:", houseId)
        return nil
    end

    local playerPos     = GetEntityCoords(cache.ped)
    local playerInterior = GetInteriorAtCoords(playerPos.x, playerPos.y, playerPos.z)

    local isShell, origin, dimMin, dimMax = self:getHouseTypeInfo(houseId)

    for attempt = 1, MAX_SPAWN_ATTEMPTS do
        local candidate

        if isShell and origin and dimMin and dimMax then
            -- Shell-based: scatter within 70% of the half-extents
            local factor = 0.7
            local halfX  = ((dimMax.x - dimMin.x) / 2) * factor
            local halfY  = ((dimMax.y - dimMin.y) / 2) * factor
            local minR   = 1.5

            local angle  = math.random() * 2 * math.pi
            local radius = minR + math.random() * (math.min(halfX, halfY) - minR)

            candidate = vec3(
                origin.x + math.cos(angle) * radius,
                origin.y + math.sin(angle) * radius,
                exitCoords.z)
        else
            -- Fallback: scatter within 6 m of exit coords
            local maxR, minR = 6.0, 1.5
            local angle  = math.random() * 2 * math.pi
            local radius = minR + math.random() * (maxR - minR)

            candidate = vec3(
                exitCoords.x + math.cos(angle) * radius,
                exitCoords.y + math.sin(angle) * radius,
                exitCoords.z)

            -- Verify same interior
            local candidateInterior = GetInteriorAtCoords(candidate.x, candidate.y, candidate.z)
            if candidateInterior ~= playerInterior then
                Debug("Junk:generateRandomCoords - Interior mismatch, attempt:", attempt)
                goto continue
            end
        end

        -- Ground-snap candidate
        do
            local found, gz = GetGroundZFor_3dCoord(
                candidate.x, candidate.y, candidate.z + 5.0, false)
            if found and gz then
                candidate = vec3(candidate.x, candidate.y, gz)
            end
        end

        -- Must not be too close to exit (within 20 m is accepted)
        do
            local exitVec = vec3(exitCoords.x, exitCoords.y, exitCoords.z)
            if #(candidate - exitVec) < 20.0 then
                Debug("Junk:generateRandomCoords - Generated coords:", candidate,
                    "for house:", houseId, "attempt:", attempt)
                return candidate
            end
        end

        ::continue::
    end

    Debug("Junk:generateRandomCoords - Failed to generate valid coords after",
        MAX_SPAWN_ATTEMPTS, "attempts")
    return nil
end

-- ──────────────────────────────────────────────────────────
-- Junk:spawnSingle(junkData, skipCoordSave)
--   Spawns one junk item. If coords not yet assigned,
--   generates them and (unless skipCoordSave) persists them.
-- ──────────────────────────────────────────────────────────
function Junk:spawnSingle(junkData, skipCoordSave)
    -- Already spawned?
    if junkData.spawned and junkData.handle and DoesEntityExist(junkData.handle) then
        Debug("Junk:spawnSingle - Already spawned:", junkData.id)
        return
    end

    local coords       = junkData.coords
    local needsSave    = false

    if not coords then
        coords = self:generateRandomCoords(junkData.house)
        if not coords then
            Debug("Junk:spawnSingle - Failed to generate coords for:", junkData.id)
            return
        end
        needsSave = true
    end

    local handle = self:spawnObject(junkData.model, coords)
    if handle then
        junkData.coords  = coords
        junkData.handle  = handle
        junkData.spawned = true
        self.objects[junkData.id] = junkData
        Debug("Junk:spawnSingle - Spawned junk:", junkData.id, junkData.model)

        -- Persist coords to server if freshly generated
        if needsSave and not skipCoordSave then
            if not self.pendingCoordUpdates[junkData.id] then
                self.pendingCoordUpdates[junkData.id] = true
                lib.callback("crime:junk:updateCoords", false,
                    function(ok)
                        self.pendingCoordUpdates[junkData.id] = nil
                        if ok then
                            Debug("Junk:spawnSingle - Saved coords to server:", junkData.id)
                        else
                            Debug("Junk:spawnSingle - Failed to save coords to server:", junkData.id)
                        end
                    end,
                    junkData.id,
                    { x = coords.x, y = coords.y, z = coords.z })
            end
        end
    end
end

-- ──────────────────────────────────────────────────────────
-- Junk:despawn(junkId)
--   Instantly deletes the entity without fade-out.
-- ──────────────────────────────────────────────────────────
function Junk:despawn(junkId)
    local junkData = self.objects[junkId]
    if not junkData then return end

    if junkData.handle and DoesEntityExist(junkData.handle) then
        DeleteEntity(junkData.handle)
        Debug("Junk:despawn - Despawned:", junkId)
    end

    junkData.handle  = nil
    junkData.spawned = false
end

-- ──────────────────────────────────────────────────────────
-- Junk:fadeOutAndRemove(junkId, duration)
--   Linearly fades the entity alpha to 0 over `duration` ms,
--   then deletes it and removes from objects table.
-- ──────────────────────────────────────────────────────────
function Junk:fadeOutAndRemove(junkId, duration)
    local junkData = self.objects[junkId]
    if not junkData then return end

    local handle = junkData.handle
    if not (handle and DoesEntityExist(handle)) then
        self.objects[junkId]             = nil
        self.pendingCoordUpdates[junkId] = nil
        return
    end

    duration = duration or 500

    local startTime   = GetGameTimer()
    local startAlpha  = GetEntityAlpha(handle)
    SetEntityAlpha(handle, startAlpha, false)

    CreateThread(function()
        while DoesEntityExist(handle) do
            local elapsed  = GetGameTimer() - startTime
            local progress = math.min(elapsed / duration, 1.0)
            local newAlpha = math.floor(startAlpha * (1.0 - progress))
            SetEntityAlpha(handle, newAlpha, false)

            if progress >= 1.0 then
                Wait(50)
                if DoesEntityExist(handle) then DeleteEntity(handle) end
                break
            end

            Wait(0)
        end

        if junkData then
            junkData.handle  = nil
            junkData.spawned = false
        end
        self.objects[junkId]             = nil
        self.pendingCoordUpdates[junkId] = nil
        Debug("Junk:fadeOutAndRemove - Fade-out complete and removed:", junkId)
    end)
end

-- ──────────────────────────────────────────────────────────
-- Junk:remove(junkId, animate)
--   If animate=true (default), fades out; otherwise instant.
-- ──────────────────────────────────────────────────────────
function Junk:remove(junkId, animate)
    local junkData = self.objects[junkId]
    if not junkData then return end

    if animate == nil then animate = true end

    if animate then
        if junkData.handle and DoesEntityExist(junkData.handle) then
            self:fadeOutAndRemove(junkId, 500)
        end
    else
        self:despawn(junkId)
        self.objects[junkId]             = nil
        self.pendingCoordUpdates[junkId] = nil
        Debug("Junk:remove - Removed from local cache:", junkId)
    end
end

-- ──────────────────────────────────────────────────────────
-- Junk:loadForHouse(houseId)
--   Fetches all junk from server, spawns those with coords,
--   and generates coords for those without.
-- ──────────────────────────────────────────────────────────
function Junk:loadForHouse(houseId)
    if not Config.Cleaning then
        Debug("Junk:loadForHouse - Cleaning is disabled")
        return
    end

    local serverJunk = lib.callback.await("crime:junk:getForHouse", false, houseId)

    if not serverJunk or #serverJunk == 0 then
        Debug("Junk:loadForHouse - No junk for house:", houseId)
        return
    end

    local withCoords    = {}
    local withoutCoords = {}

    for _, item in ipairs(serverJunk) do
        local junkData = {
            id      = item.id,
            house   = item.house,
            model   = item.model,
            coords  = item.coords and vec3(item.coords.x, item.coords.y, item.coords.z) or nil,
            spawned = false,
        }
        if junkData.coords then
            table.insert(withCoords, junkData)
        else
            table.insert(withoutCoords, junkData)
        end
    end

    -- Spawn junk that already has saved coords immediately
    for _, junkData in ipairs(withCoords) do
        self:spawnSingle(junkData, true)
    end

    -- Generate coords for the rest asynchronously
    if #withoutCoords > 0 then
        CreateThread(function()
            for _, junkData in ipairs(withoutCoords) do
                -- Bail out if player left the house
                if not (EnteredHouse and EnteredHouse == houseId) then
                    Debug("Junk:loadForHouse - Left house during processing")
                    return
                end

                local coords = self:generateRandomCoords(junkData.house)
                if coords then
                    junkData.coords = coords
                    self.pendingCoordUpdates[junkData.id] = true

                    local saved = lib.callback.await("crime:junk:updateCoords", false,
                        junkData.id,
                        { x = coords.x, y = coords.y, z = coords.z })

                    self.pendingCoordUpdates[junkData.id] = nil

                    if saved then
                        self:spawnSingle(junkData, true)
                        Debug("Junk:loadForHouse - Processed junk:", junkData.id)
                    else
                        Debug("Junk:loadForHouse - Failed to update coords for:", junkData.id)
                    end
                end

                Wait(50)
            end
        end)
    end

    Debug("Junk:loadForHouse - Loaded", #serverJunk, "junk objects for house:", houseId)
end

-- ──────────────────────────────────────────────────────────
-- Junk:unloadForHouse(houseId)
-- ──────────────────────────────────────────────────────────
function Junk:unloadForHouse(houseId)
    for id, junkData in pairs(self.objects) do
        if junkData.house == houseId then
            self:despawn(id)
            self.objects[id] = nil
        end
    end
    self.pendingCoordUpdates = {}
    Debug("Junk:unloadForHouse - Unloaded all junk for house:", houseId)
end

-- ──────────────────────────────────────────────────────────
-- Junk:cleanAll()
-- ──────────────────────────────────────────────────────────
function Junk:cleanAll()
    for id in pairs(self.objects) do
        self:despawn(id)
    end
    self.objects             = {}
    self.pendingCoordUpdates = {}
    Debug("Junk:cleanAll - Cleaned all junk")
end

-- ──────────────────────────────────────────────────────────
-- Junk:pickup(junkId, houseId)
--   Play janitor cleaning animation, then call server to remove.
-- ──────────────────────────────────────────────────────────
function Junk:pickup(junkId, houseId)
    -- Must have key to the house
    if not (CurrentHouseData and CurrentHouseData.haskey) then
        Notification(i18n.t("junk.no_permission"), "error")
        return
    end

    if not self.objects[junkId] then
        Notification(i18n.t("junk.not_found"), "error")
        return
    end

    local animDict = "amb@world_human_janitor@male@idle_a"
    local animClip = "idle_a"
    local broomHash = joaat("prop_tool_broom")
    lib.requestModel(broomHash)

    -- Spawn broom slightly behind player (hidden below ground initially)
    local behindPos = GetOffsetFromEntityInWorldCoords(cache.ped, 0.0, 0.0, -5.0)
    local broomObj  = CreateObject(broomHash, behindPos.x, behindPos.y, behindPos.z,
        true, true, true)

    lib.requestAnimDict(animDict)
    TaskPlayAnim(cache.ped, animDict, animClip,
        8.0, -8.0, -1, 0, 0, false, false, false)

    -- Attach broom to right hand
    AttachEntityToEntity(broomObj, cache.ped,
        GetPedBoneIndex(cache.ped, 28422),
        -0.005, 0.0, 0.0,
        360.0, 360.0, 0.0,
        1, 1, 0, 1, 0, 1)

    local success = lib.progressCircle({
        duration     = 3000,
        label        = i18n.t("junk.cleaning"),
        position     = "bottom",
        useWhileDead = false,
        canCancel    = true,
        disable      = { car = true, move = true, combat = true },
    })

    if success then
        ClearPedTasks(cache.ped)
        DeleteEntity(broomObj)

        local ok = lib.callback.await("crime:junk:remove", false, junkId, houseId)
        if ok then
            self:remove(junkId)
            Notification(i18n.t("junk.cleaned"), "success")
        else
            Notification(i18n.t("junk.failed"), "error")
        end
    else
        ClearPedTasks(cache.ped)
        Notification(i18n.t("junk.cancelled"), "info")
    end
end

-- ──────────────────────────────────────────────────────────
-- Junk:get(junkId) → junkData | nil
-- ──────────────────────────────────────────────────────────
function Junk:get(junkId)
    return self.objects[junkId]
end

-- ──────────────────────────────────────────────────────────
-- Junk:getAll() → objects table
-- ──────────────────────────────────────────────────────────
function Junk:getAll()
    return self.objects
end

-- ──────────────────────────────────────────────────────────
-- Junk:findNearby() → junkId | nil
--   Returns the id of the nearest spawned junk within 2 m.
-- ──────────────────────────────────────────────────────────
function Junk:findNearby()
    local playerPos = GetEntityCoords(cache.ped)
    local nearest   = nil
    local nearDist  = 2.0

    for id, junkData in pairs(self.objects) do
        if junkData.spawned and junkData.handle and DoesEntityExist(junkData.handle) then
            local dist = #(playerPos - GetEntityCoords(junkData.handle))
            if dist < nearDist then
                nearDist = dist
                nearest  = id
            end
        end
    end

    return nearest
end

-- ──────────────────────────────────────────────────────────
-- Interaction prompt label (resolved at load)
-- ──────────────────────────────────────────────────────────
local LABEL_PRESS_CLEAN = i18n.t("junk.press_to_clean")

-- ──────────────────────────────────────────────────────────
-- Junk:startInteractionLoop()
--   Draws a DrawText3D prompt and fires pickup on E.
-- ──────────────────────────────────────────────────────────
function Junk:startInteractionLoop()
    if self.isLoopRunning then return end

    self.active        = true
    self.isLoopRunning = true

    CreateThread(function()
        while self.active and EnteredHouse do
            local nearbyId = self:findNearby()
            local waitMs   = 500

            if nearbyId then
                if not Config.UseTarget then
                    local junkData = self.objects[nearbyId]
                    if junkData and junkData.handle and DoesEntityExist(junkData.handle) then
                        waitMs = 0
                        local pos = GetEntityCoords(junkData.handle)
                        DrawText3D(pos.x, pos.y, pos.z + 0.3,
                            LABEL_PRESS_CLEAN, "clean_junk", "E")

                        if IsControlJustPressed(0, Keys.E) then
                            self:pickup(nearbyId, EnteredHouse)
                        end
                    end
                end
            end

            Wait(waitMs)
        end

        self.isLoopRunning = false
        self.active        = false
    end)
end

-- ──────────────────────────────────────────────────────────
-- Junk:stopInteractionLoop()
-- ──────────────────────────────────────────────────────────
function Junk:stopInteractionLoop()
    self.active = false
end

-- ──────────────────────────────────────────────────────────
-- Create the singleton instance
-- ──────────────────────────────────────────────────────────
_G.junk = Junk:new()

-- ──────────────────────────────────────────────────────────
-- Net / local events
-- ──────────────────────────────────────────────────────────

-- Server spawned a new junk item
RegisterNetEvent("crime:junk:spawn", function(data)
    if not (EnteredHouse and EnteredHouse == data.house) then return end

    local junkData = {
        id      = data.id,
        house   = data.house,
        model   = data.model,
        coords  = nil,
        spawned = false,
    }
    junk:spawnSingle(junkData)
    Debug("crime:junk:spawn - New junk spawned:", data.id)
end)

-- Server removed a junk item
RegisterNetEvent("crime:junk:remove", function(junkId)
    junk:remove(junkId)
    Debug("crime:junk:remove - Junk removed:", junkId)
end)

-- On entering a house
AddEventHandler("crime:onEnterHouse", function(houseId)
    if not Config.Cleaning then return end
    Wait(1000)
    junk:loadForHouse(houseId)
    junk:startInteractionLoop()
end)

-- On leaving a house
AddEventHandler("crime:onExitHouse", function(houseId)
    junk:stopInteractionLoop()
    junk:cleanAll()
end)

-- Resource stop cleanup
AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        junk:cleanAll()
    end
end)
