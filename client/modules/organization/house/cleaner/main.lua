-- ============================================================
-- client/modules/organization/house/cleaner/main.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- CleanerRobot: Roomba-style robot that autonomously navigates
-- a house, avoids walls (wall-following algorithm), and cleans
-- nearby junk items.
-- ============================================================

local sincos = require("glm").sincos
local rad    = require("glm").rad

-- ──────────────────────────────────────────────────────────
-- Config helper: reads CleanerRobot config with defaults
-- ──────────────────────────────────────────────────────────
local function buildConfig()
    local cfg = Config.CleanerRobot or {}
    return {
        moveSpeed         = cfg.moveSpeed         or 0.012,
        maxSpeed          = cfg.maxSpeed          or 0.018,
        acceleration      = cfg.acceleration      or 0.0003,
        deceleration      = cfg.deceleration      or 0.0008,
        raycastDistance   = cfg.raycastDistance   or 0.8,
        junkDetectRadius  = cfg.junkDetectRadius  or 15.0,
        maxDistanceFromDock = cfg.maxDistanceFromDock or 15.0,
        cleaningTimeout   = cfg.cleaningTimeout   or 300000,
        randomDirectionTime = cfg.randomDirectionTime or 8000,
        maxStuckTime      = cfg.maxStuckTime      or 3000,
        wobbleEnabled     = (cfg.wobbleEnabled ~= false),
        wobbleAmount      = cfg.wobbleAmount      or 0.15,
        wobbleSpeed       = cfg.wobbleSpeed       or 0.08,
    }
end

-- ──────────────────────────────────────────────────────────
-- Threshold constants
-- ──────────────────────────────────────────────────────────
local UPDATE_INTERVAL_MS = 16   -- ~60 fps
local WALL_THRESHOLD     = 0.4  -- minimum clear distance ahead
local CLOSE_JUNK_RADIUS  = 1.5  -- very close junk (clean immediately)
local RIGHT_WALL_DIST    = 0.4  -- target distance from right wall
local OPENING_JUMP_DIST  = 2.0  -- right-wall jump that signals opening
local HEADING_THRESHOLD  = 15   -- degrees: counts as "turned"
local TURN_COMPLETE_MOVE = 0.3  -- metres past turn position

-- ──────────────────────────────────────────────────────────
-- CleanerRobot class
-- ──────────────────────────────────────────────────────────
local CleanerRobot = lib.class("CleanerRobot")

function CleanerRobot:constructor()
    local cfg = buildConfig()
    self.robots           = {}
    self.activeThread     = false
    self.interactionThread = false
    self.moveSpeed        = cfg.moveSpeed
    self.maxSpeed         = cfg.maxSpeed
    self.acceleration     = cfg.acceleration
    self.deceleration     = cfg.deceleration
    self.raycastDistance  = cfg.raycastDistance
    self.junkDetectRadius = cfg.junkDetectRadius
    self.maxDistanceFromDock = cfg.maxDistanceFromDock
    self.cleaningTimeout  = cfg.cleaningTimeout
    self.randomDirectionTime = cfg.randomDirectionTime
    self.maxStuckTime     = cfg.maxStuckTime
    self.wobbleEnabled    = cfg.wobbleEnabled
    self.wobbleAmount     = cfg.wobbleAmount
    self.wobbleSpeed      = cfg.wobbleSpeed
    self.cleanerModels    = {}
    return self
end

-- ──────────────────────────────────────────────────────────
-- buildModelList()
--   Scans Config.Furniture for cleaner-robot items and
--   populates self.cleanerModels[modelName] = { model, dockerModel }.
-- ──────────────────────────────────────────────────────────
function CleanerRobot:buildModelList()
    self.cleanerModels = {}
    for _, category in pairs(Config.Furniture) do
        if category.items then
            for _, item in ipairs(category.items) do
                if item.isCleanerRobot then
                    self.cleanerModels[item.object] = {
                        model       = item.object,
                        dockerModel = item.isCleanerRobot.dockerModel,
                    }
                end
                if item.colors then
                    for _, colorItem in pairs(item.colors) do
                        if colorItem.isCleanerRobot then
                            self.cleanerModels[colorItem.object] = {
                                model       = colorItem.object,
                                dockerModel = colorItem.isCleanerRobot.dockerModel,
                            }
                        end
                    end
                end
            end
        end
    end
end

-- ──────────────────────────────────────────────────────────
-- isCleanerModel(modelName) → bool, modelData
-- ──────────────────────────────────────────────────────────
function CleanerRobot:isCleanerModel(modelName)
    local data = self.cleanerModels[modelName]
    return (data ~= nil), data
end

-- ──────────────────────────────────────────────────────────
-- performRaycast(origin, dir, distance, ignoreEntities)
--   → hit, hitPos, hitEntity
-- ──────────────────────────────────────────────────────────
function CleanerRobot:performRaycast(origin, dir, distance, ignoreEntities)
    local endPos    = origin + (dir * distance)
    local ignoreEnt = (ignoreEntities and ignoreEntities[1]) or 0

    local handle = StartExpensiveSynchronousShapeTestLosProbe(
        origin.x, origin.y, origin.z,
        endPos.x, endPos.y, endPos.z,
        17, ignoreEnt, 4)

    local _, hit, hitPos, _, hitEntity = GetShapeTestResultIncludingMaterial(handle)

    if hit == 1 then
        return true, vec3(hitPos.x, hitPos.y, hitPos.z), hitEntity
    end
    return false, nil, nil
end

-- ──────────────────────────────────────────────────────────
-- headingToDirection(heading) → vec3 (XY only)
--   Converts a GTA heading (degrees, 0=North/+Y, 90=West/-X)
--   to a flat direction vector using glm sincos.
-- ──────────────────────────────────────────────────────────
function CleanerRobot:headingToDirection(heading)
    local r         = vec3(0, 0, heading)
    local s, c      = rad(r), rad(r)
    sincos(r)
    -- The original code extracts .z components of the two returns
    -- (sin→x component, cos→y component for the heading)
    local s2, c2    = sincos(rad(vec3(0, 0, heading)))
    return vec3(s2.z, c2.z, 0.0)
end

-- ──────────────────────────────────────────────────────────
-- canMoveInDirection(robotData, heading) → bool
-- ──────────────────────────────────────────────────────────
function CleanerRobot:canMoveInDirection(robotData, heading)
    if not DoesEntityExist(robotData.robotHandle) then return false end

    local pos     = GetEntityCoords(robotData.robotHandle)
    local normH   = self:normalizeAngle(heading)
    local dir     = self:headingToDirection(normH)
    local origin  = vec3(pos.x, pos.y, pos.z + 0.15)

    local hit, hitPos, hitEnt = self:performRaycast(
        origin, dir, self.raycastDistance,
        { robotData.dockHandle })

    if hit and hitEnt ~= robotData.dockHandle then
        if hitPos then
            local dist = #(pos - hitPos)
            Debug("CleanerRobot: Hit obstacle in direction:", normH, "distance", dist)
            return dist >= self.raycastDistance
        end
        return false
    end
    return true
end

-- ──────────────────────────────────────────────────────────
-- isForwardClear(robotData) → bool
-- ──────────────────────────────────────────────────────────
function CleanerRobot:isForwardClear(robotData)
    if not DoesEntityExist(robotData.robotHandle) then return false end
    local h = robotData.currentHeading or GetEntityHeading(robotData.robotHandle)
    return self:canMoveInDirection(robotData, h)
end

-- ──────────────────────────────────────────────────────────
-- getDistanceInDirection(robotData, heading, defaultDist)
-- ──────────────────────────────────────────────────────────
function CleanerRobot:getDistanceInDirection(robotData, heading, defaultDist)
    if not DoesEntityExist(robotData.robotHandle) then return defaultDist end

    local pos    = GetEntityCoords(robotData.robotHandle)
    local dir    = self:headingToDirection(heading)
    local origin = vec3(pos.x, pos.y, pos.z + 0.15)

    local hit, hitPos, hitEnt = self:performRaycast(
        origin, dir, defaultDist,
        { robotData.robotHandle, robotData.dockHandle })

    if hit and hitEnt ~= robotData.dockHandle and hitPos then
        return #(pos - hitPos)
    end
    return defaultDist
end

-- ──────────────────────────────────────────────────────────
-- initRoombaState(robotData)
--   Resets wall-following nav state to "moving".
-- ──────────────────────────────────────────────────────────
function CleanerRobot:initRoombaState(robotData)
    local h = robotData.currentHeading
        or GetEntityHeading(robotData.robotHandle)
        or 0

    robotData.navState              = "moving"
    robotData.moveDirection         = h
    robotData.lastWallDistance      = nil
    robotData.wallFollowStartTime   = nil
    robotData.openingDetected       = false
    robotData.openingDirection      = nil
    robotData.turnCompletePosition  = nil
    robotData.isInitialized         = true
    Debug("CleanerRobot: Wall-following initialized, direction:", h)
end

-- ──────────────────────────────────────────────────────────
-- getWallDistance(robotData, heading, defaultDist)
-- ──────────────────────────────────────────────────────────
function CleanerRobot:getWallDistance(robotData, heading, defaultDist)
    return self:getDistanceInDirection(robotData, heading, defaultDist)
end

-- ──────────────────────────────────────────────────────────
-- isFrontBlocked(robotData) → blocked, dist
-- ──────────────────────────────────────────────────────────
function CleanerRobot:isFrontBlocked(robotData)
    local dist = self:getWallDistance(robotData, robotData.moveDirection, WALL_THRESHOLD)
    return dist < WALL_THRESHOLD, dist
end

-- ──────────────────────────────────────────────────────────
-- getRightWallDistance(robotData) → dist
-- ──────────────────────────────────────────────────────────
function CleanerRobot:getRightWallDistance(robotData)
    local rightHeading = self:normalizeAngle(robotData.moveDirection - 90)
    return self:getWallDistance(robotData, rightHeading, RIGHT_WALL_DIST)
end

-- ──────────────────────────────────────────────────────────
-- checkRightOpening(robotData) → detected, turnHeading
-- ──────────────────────────────────────────────────────────
function CleanerRobot:checkRightOpening(robotData)
    local rightDist = self:getRightWallDistance(robotData)
    local lastDist  = robotData.lastWallDistance or rightDist
    local jump      = rightDist - lastDist

    if jump > OPENING_JUMP_DIST then
        local turnH = self:normalizeAngle(robotData.moveDirection - 90)
        Debug("CleanerRobot: Opening detected! Distance jump from", lastDist, "to", rightDist)
        return true, turnH
    end
    return false, 0
end

-- ──────────────────────────────────────────────────────────
-- findAllJunkInRange(robotData, maxDist) → sorted list
-- ──────────────────────────────────────────────────────────
function CleanerRobot:findAllJunkInRange(robotData, maxDist)
    if not maxDist then maxDist = self.maxDistanceFromDock end
    local result  = {}
    local robotPos = GetEntityCoords(robotData.robotHandle)
    local allJunk = junk:getAll()
    if not allJunk then return result end

    for id, junkData in pairs(allJunk) do
        -- Skip already-cleaned
        local alreadyCleaned = false
        for _, cleanedId in ipairs(robotData.cleanedJunk) do
            if cleanedId == id then alreadyCleaned = true break end
        end

        if not alreadyCleaned and junkData.handle and DoesEntityExist(junkData.handle) then
            local junkPos = GetEntityCoords(junkData.handle)
            local dist    = #(robotPos - junkPos)
            if dist <= maxDist then
                table.insert(result, {
                    id       = id,
                    coords   = junkPos,
                    distance = dist,
                    handle   = junkData.handle,
                })
            end
        end
    end

    table.sort(result, function(a, b) return a.distance < b.distance end)
    return result
end

-- ──────────────────────────────────────────────────────────
-- findNearbyJunk(robotData) → id, coords
-- ──────────────────────────────────────────────────────────
function CleanerRobot:findNearbyJunk(robotData)
    local all = self:findAllJunkInRange(robotData, self.maxDistanceFromDock)
    if #all > 0 then
        local first = all[1]
        if first.handle and DoesEntityExist(first.handle) then
            return first.id, first.coords
        end
    end
    return nil, nil
end

-- ──────────────────────────────────────────────────────────
-- findVeryCloseJunk(robotData, radius) → id, coords, dist
-- ──────────────────────────────────────────────────────────
function CleanerRobot:findVeryCloseJunk(robotData, radius)
    radius = radius or CLOSE_JUNK_RADIUS
    local robotPos = GetEntityCoords(robotData.robotHandle)
    local allJunk  = junk:getAll()
    if not allJunk then return nil, nil, nil end

    local best, bestDist = nil, math.huge

    for id, junkData in pairs(allJunk) do
        local already = false
        for _, cid in ipairs(robotData.cleanedJunk) do
            if cid == id then already = true break end
        end

        if not already and junkData.handle and DoesEntityExist(junkData.handle) then
            local junkPos = GetEntityCoords(junkData.handle)
            local dist    = #(robotPos - junkPos)
            if dist <= radius and dist < bestDist
               and self:isJunkVisible(robotData, junkData.handle) then
                best     = { id = id, coords = junkPos, distance = dist }
                bestDist = dist
            end
        end
    end

    if not best then return nil, nil, nil end

    -- Sort all visible within radius
    local visible = {}
    for id, junkData in pairs(allJunk) do
        local already = false
        for _, cid in ipairs(robotData.cleanedJunk) do
            if cid == id then already = true break end
        end
        if not already and junkData.handle and DoesEntityExist(junkData.handle) then
            local junkPos = GetEntityCoords(junkData.handle)
            local dist    = #(robotPos - junkPos)
            if self:isJunkVisible(robotData, junkData.handle) then
                table.insert(visible, { id = id, coords = junkPos, distance = dist })
            end
        end
    end

    if #visible == 0 then return nil, nil, nil end
    table.sort(visible, function(a, b) return a.distance < b.distance end)
    local first = visible[1]
    return first.id, first.coords, first.distance
end

-- ──────────────────────────────────────────────────────────
-- findVisibleJunk(robotData) → id, coords, dist
--   Returns the closest junk the robot has line-of-sight to.
-- ──────────────────────────────────────────────────────────
function CleanerRobot:findVisibleJunk(robotData)
    local robotPos = GetEntityCoords(robotData.robotHandle)
    local allJunk  = junk:getAll()
    if not allJunk then return nil, nil, nil end

    local visible = {}
    for id, junkData in pairs(allJunk) do
        local already = false
        for _, cid in ipairs(robotData.cleanedJunk) do
            if cid == id then already = true break end
        end
        if not already and junkData.handle and DoesEntityExist(junkData.handle) then
            local junkPos = GetEntityCoords(junkData.handle)
            local dist    = #(robotPos - junkPos)
            if self:isJunkVisible(robotData, junkData.handle) then
                table.insert(visible, { id = id, coords = junkPos, distance = dist })
            end
        end
    end

    if #visible == 0 then return nil, nil, nil end
    table.sort(visible, function(a, b) return a.distance < b.distance end)
    local first = visible[1]
    return first.id, first.coords, first.distance
end

-- ──────────────────────────────────────────────────────────
-- cleanJunk(robotData, junkId)
--   Marks junk as cleaned, removes entity outline,
--   calls server to delete it, plays pickup sound.
-- ──────────────────────────────────────────────────────────
function CleanerRobot:cleanJunk(robotData, junkId)
    -- Already cleaned?
    for _, cid in ipairs(robotData.cleanedJunk) do
        if cid == junkId then
            Debug("CleanerRobot: Junk already cleaned:", junkId)
            return
        end
    end

    table.insert(robotData.cleanedJunk, junkId)

    -- Remove outline from entity if it exists
    local allJunk = junk:getAll()
    if allJunk and allJunk[junkId] and allJunk[junkId].handle
       and DoesEntityExist(allJunk[junkId].handle) then
        SetEntityDrawOutline(allJunk[junkId].handle, false)
    end

    local ok = lib.callback.await("crime:junk:remove", false, junkId, robotData.house)
    if ok then
        junk:remove(junkId)
        Debug("CleanerRobot: Cleaned and removed junk", junkId)
        PlaySoundFrontend(-1, "PICK_UP", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
    else
        -- Revert: remove from cleanedJunk list
        for i, cid in ipairs(robotData.cleanedJunk) do
            if cid == junkId then
                table.remove(robotData.cleanedJunk, i)
                break
            end
        end
        Debug("CleanerRobot: Failed to remove junk on server:", junkId)
    end
end

-- ──────────────────────────────────────────────────────────
-- lerp(a, b, t) → value
-- ──────────────────────────────────────────────────────────
function CleanerRobot:lerp(a, b, t)
    return a + (b - a) * math.min(t, 1.0)
end

-- ──────────────────────────────────────────────────────────
-- normalizeAngle(angle) → [0, 360)
-- ──────────────────────────────────────────────────────────
function CleanerRobot:normalizeAngle(angle)
    while angle < 0   do angle = angle + 360 end
    while angle >= 360 do angle = angle - 360 end
    return angle
end

-- ──────────────────────────────────────────────────────────
-- getAngleDifference(a, b) → signed diff in (-180, 180]
-- ──────────────────────────────────────────────────────────
function CleanerRobot:getAngleDifference(a, b)
    local diff = b - a
    while diff >  180 do diff = diff - 360 end
    while diff < -180 do diff = diff + 360 end
    return diff
end

-- ──────────────────────────────────────────────────────────
-- hasReachedTargetHeading(robotData, tolerance) → bool
-- ──────────────────────────────────────────────────────────
function CleanerRobot:hasReachedTargetHeading(robotData, tolerance)
    tolerance = tolerance or 5
    local cur = robotData.currentHeading or 0
    local tgt = robotData.targetHeading  or 0
    return math.abs(self:getAngleDifference(cur, tgt)) <= tolerance
end

-- ──────────────────────────────────────────────────────────
-- canUpdateTargetHeading(robotData) → bool
-- ──────────────────────────────────────────────────────────
function CleanerRobot:canUpdateTargetHeading(robotData)
    if not robotData.headingLockTime then return true end
    local elapsed = GetGameTimer() - robotData.headingLockTime
    if elapsed > 500 then return true end
    return self:hasReachedTargetHeading(robotData, 10)
end

-- ──────────────────────────────────────────────────────────
-- updateRotation(robotData, targetHeading, forceUpdate)
--   Smoothly interpolates current heading toward target.
--   Applies wobble if enabled.
-- ──────────────────────────────────────────────────────────
function CleanerRobot:updateRotation(robotData, targetHeading, forceUpdate)
    if not DoesEntityExist(robotData.robotHandle) then return end

    local normTarget = self:normalizeAngle(targetHeading)

    if not forceUpdate then
        if robotData.targetHeading then
            local diff = math.abs(self:getAngleDifference(robotData.targetHeading, normTarget))
            if diff > 30 then
                if not self:canUpdateTargetHeading(robotData) then
                    normTarget = robotData.targetHeading
                end
            else
                robotData.headingLockTime = GetGameTimer()
            end
        end
    else
        robotData.headingLockTime = GetGameTimer()
    end

    robotData.targetHeading = normTarget

    local cur  = robotData.currentHeading or GetEntityHeading(robotData.robotHandle)
    local diff = self:getAngleDifference(cur, normTarget)
    local step = math.min(math.abs(diff), 8.0)
    local newH

    if math.abs(diff) < 1 then
        newH = normTarget
    else
        local sign = (diff > 0) and 1 or -1
        newH = self:normalizeAngle(cur + sign * step)
    end

    -- Optional wobble
    if self.wobbleEnabled and robotData.velocity > 0.001 then
        if math.abs(diff) < 10 then
            robotData.wobblePhase = (robotData.wobblePhase or 0) + self.wobbleSpeed
            local wobble = math.sin(robotData.wobblePhase) * self.wobbleAmount
                           * (robotData.velocity / self.maxSpeed)
            newH = newH + wobble
        end
    end

    robotData.currentHeading = newH
    -- GTA heading is the inverse of the robot's internal heading
    SetEntityHeading(robotData.robotHandle, self:normalizeAngle(newH + 180))
end

-- ──────────────────────────────────────────────────────────
-- updateVelocity(robotData, shouldAccelerate)
-- ──────────────────────────────────────────────────────────
function CleanerRobot:updateVelocity(robotData, shouldAccelerate)
    local vel = robotData.velocity or 0

    if shouldAccelerate then
        local newVel = self:lerp(vel, self.moveSpeed, self.acceleration * 10)
        robotData.velocity = newVel
        if robotData.velocity > self.maxSpeed then
            robotData.velocity = self.maxSpeed
        end
    else
        local newVel = self:lerp(vel, 0, self.deceleration * 10)
        robotData.velocity = newVel
        if robotData.velocity < 1e-4 then
            robotData.velocity = 0
        end
    end
end

-- ──────────────────────────────────────────────────────────
-- applyMovement(robotData) → bool (moved)
-- ──────────────────────────────────────────────────────────
function CleanerRobot:applyMovement(robotData)
    if not DoesEntityExist(robotData.robotHandle) then return false end
    if (robotData.velocity or 0) < 1e-4 then return false end

    local pos     = GetEntityCoords(robotData.robotHandle)
    local heading = robotData.currentHeading or GetEntityHeading(robotData.robotHandle)
    local dir     = self:headingToDirection(heading)
    local vel     = robotData.velocity

    local newX = pos.x + dir.x * vel
    local newY = pos.y + dir.y * vel
    local newZ = (robotData.baseZ or pos.z) + (robotData.robotHeightOffset or 0)

    SetEntityCoords(robotData.robotHandle, newX, newY, newZ,
        false, false, false, false)
    robotData.lastMoveTime = GetGameTimer()
    return true
end

-- ──────────────────────────────────────────────────────────
-- isJunkVisible(robotData, junkHandle) → bool
-- ──────────────────────────────────────────────────────────
function CleanerRobot:isJunkVisible(robotData, junkHandle)
    if not DoesEntityExist(robotData.robotHandle) then return false end
    if not DoesEntityExist(junkHandle) then return false end

    local robotZ = GetEntityCoords(robotData.robotHandle).z
    local junkZ  = GetEntityCoords(junkHandle).z
    if math.abs(robotZ - junkZ) > 3.0 then return false end

    return HasEntityClearLosToEntity(robotData.robotHandle, junkHandle, 17)
end

-- ──────────────────────────────────────────────────────────
-- updateCleaningState(robotData) → newHeading, canMove
--   The heart of the Roomba navigation algorithm.
--   Returns the heading to use this tick and whether forward
--   movement is permitted.
-- ──────────────────────────────────────────────────────────
function CleanerRobot:updateCleaningState(robotData)
    if not DoesEntityExist(robotData.robotHandle) then return 0, false end

    local pos        = GetEntityCoords(robotData.robotHandle)
    local curHeading = robotData.currentHeading
        or GetEntityHeading(robotData.robotHandle)

    -- Initialise nav state if first tick
    if not robotData.isInitialized then
        self:initRoombaState(robotData)
    end
    if not robotData.navState then robotData.navState = "moving" end
    if not (robotData.moveDirection and type(robotData.moveDirection) == "number") then
        robotData.moveDirection = curHeading
    end

    local headingDiff = math.abs(self:getAngleDifference(curHeading, robotData.moveDirection))

    -- ── Helper: angle from robot to coords ───────────────
    local function angleToCoords(targetCoords)
        local dx = targetCoords.x - pos.x
        local dy = targetCoords.y - pos.y
        return self:normalizeAngle(math.deg(math.atan(dx, dy)))
    end

    -- ── Check visible junk ───────────────────────────────
    local visJunkId, visJunkCoords, visJunkDist = self:findVisibleJunk(robotData)

    -- Very close junk → clean immediately
    local closeId, closeCoords, closeDist = self:findVeryCloseJunk(robotData, CLOSE_JUNK_RADIUS)
    if closeId and closeCoords then
        self:cleanJunk(robotData, closeId)
        robotData.currentTarget      = nil
        robotData.turnCompletePosition = nil
        robotData.navState           = "moving"
        robotData.lastWallDistance   = nil
        robotData.moveDirection      = curHeading
        Debug("CleanerRobot: Cleaned very close junk (1.5m), back to normal movement. Distance:", closeDist)
        return curHeading, true
    end

    -- Visible junk within cleaning range → clean
    if visJunkId and visJunkCoords and visJunkDist and visJunkDist < 1.2 then
        self:cleanJunk(robotData, visJunkId)
        robotData.currentTarget      = nil
        robotData.turnCompletePosition = nil
        robotData.navState           = "moving"
        robotData.lastWallDistance   = nil
        robotData.moveDirection      = curHeading
        Debug("CleanerRobot: Cleaned visible junk, back to normal movement")
        return curHeading, true
    end

    -- Visible junk further away → steer toward it
    if visJunkId and visJunkCoords then
        local junkAngle = angleToCoords(visJunkCoords)
        local angleDiff = math.abs(self:getAngleDifference(curHeading, junkAngle))

        if angleDiff > HEADING_THRESHOLD then
            robotData.moveDirection = junkAngle
            robotData.navState      = "turning_to_junk"
            robotData.currentTarget = visJunkCoords
            Debug("CleanerRobot: Visible junk found! OVERRIDING current state, turning to face it. Distance:", visJunkDist)
            return junkAngle, false
        else
            robotData.navState          = "moving"
            robotData.lastWallDistance  = nil
            robotData.moveDirection     = junkAngle
            robotData.currentTarget     = visJunkCoords
            Debug("CleanerRobot: Visible junk found! OVERRIDING current state, going straight to it. Distance:", visJunkDist)
            return junkAngle, true
        end
    end

    -- ── State machine ────────────────────────────────────
    local navState = robotData.navState

    if navState == "turning_to_junk" then
        if visJunkId and visJunkCoords then
            local junkAngle = angleToCoords(visJunkCoords)
            local angleDiff = math.abs(self:getAngleDifference(curHeading, junkAngle))
            if angleDiff > HEADING_THRESHOLD then
                robotData.moveDirection = junkAngle
                robotData.currentTarget = visJunkCoords
                return junkAngle, false
            else
                robotData.navState          = "moving"
                robotData.lastWallDistance  = nil
                robotData.moveDirection     = junkAngle
                robotData.currentTarget     = visJunkCoords
                return junkAngle, true
            end
        end
        if headingDiff < HEADING_THRESHOLD then
            robotData.navState            = "moving"
            robotData.moveDirection       = curHeading
            robotData.turnCompletePosition = vec3(pos.x, pos.y, pos.z)
            Debug("CleanerRobot: Turned to junk, moving towards it")
            return curHeading, true
        end
        return robotData.moveDirection, false
    end

    if navState == "turning" then
        if visJunkId and visJunkCoords then
            local junkAngle = angleToCoords(visJunkCoords)
            robotData.moveDirection = junkAngle
            robotData.navState      = "turning_to_junk"
            robotData.currentTarget = visJunkCoords
            Debug("CleanerRobot: Visible junk found while turning, switching to junk!")
            return junkAngle, false
        end
        if headingDiff < HEADING_THRESHOLD then
            robotData.turnCompletePosition = vec3(pos.x, pos.y, pos.z)
            robotData.moveDirection        = curHeading
            if robotData.openingDetected then
                robotData.navState       = "passing_opening"
                robotData.openingDetected = false
                Debug("CleanerRobot: Now passing through opening")
            else
                robotData.navState         = "following_wall"
                robotData.lastWallDistance = self:getRightWallDistance(robotData)
                robotData.wallFollowStartTime = GetGameTimer()
                Debug("CleanerRobot: Turn complete, now following wall. Right wall dist:",
                    robotData.lastWallDistance)
            end
            return curHeading, true
        end
        return robotData.moveDirection, false
    end

    if navState == "passing_opening" then
        if visJunkId and visJunkCoords then
            local junkAngle = angleToCoords(visJunkCoords)
            local angleDiff = math.abs(self:getAngleDifference(curHeading, junkAngle))
            if angleDiff > HEADING_THRESHOLD then
                robotData.moveDirection = junkAngle
                robotData.navState      = "turning_to_junk"
                robotData.currentTarget = visJunkCoords
                Debug("CleanerRobot: Visible junk found while passing opening, switching to junk!")
                return junkAngle, false
            else
                robotData.navState         = "moving"
                robotData.lastWallDistance = nil
                robotData.moveDirection    = junkAngle
                robotData.currentTarget    = visJunkCoords
                Debug("CleanerRobot: Visible junk found while passing opening, going straight!")
                return junkAngle, true
            end
        end
        -- Check if we've cleared the opening
        if robotData.turnCompletePosition then
            local dx   = pos.x - robotData.turnCompletePosition.x
            local dy   = pos.y - robotData.turnCompletePosition.y
            local dist = math.sqrt(dx*dx + dy*dy)
            if dist > (TURN_COMPLETE_MOVE + 0.5) then
                robotData.navState            = "moving"
                robotData.turnCompletePosition = nil
                robotData.lastWallDistance    = nil
                Debug("CleanerRobot: Passed through opening, RESET to normal movement")
            end
        else
            robotData.navState         = "moving"
            robotData.lastWallDistance = nil
        end

        -- Check if wall is now ahead again
        local frontDist = self:getWallDistance(robotData, curHeading, WALL_THRESHOLD)
        if frontDist < WALL_THRESHOLD then
            Debug("CleanerRobot: Passing opening, frontDist:", frontDist, "WALL_DETECT_FRONT:", WALL_THRESHOLD)
            local turnH = self:normalizeAngle(curHeading + 90)
            robotData.moveDirection   = turnH
            robotData.navState        = "turning"
            robotData.openingDetected = false
            return turnH, false
        end
        return curHeading, true
    end

    if navState == "following_wall" then
        if visJunkId and visJunkCoords then
            local junkAngle = angleToCoords(visJunkCoords)
            local angleDiff = math.abs(self:getAngleDifference(curHeading, junkAngle))
            if angleDiff > HEADING_THRESHOLD then
                robotData.moveDirection = junkAngle
                robotData.navState      = "turning_to_junk"
                robotData.currentTarget = visJunkCoords
                Debug("CleanerRobot: Visible junk found while following wall, switching to junk!")
                return junkAngle, false
            else
                robotData.navState         = "moving"
                robotData.lastWallDistance = nil
                robotData.moveDirection    = junkAngle
                robotData.currentTarget    = visJunkCoords
                Debug("CleanerRobot: Visible junk found while following wall, going straight!")
                return junkAngle, true
            end
        end

        -- Wall ahead while following?
        local frontDist = self:getWallDistance(robotData, curHeading, WALL_THRESHOLD)
        if frontDist < WALL_THRESHOLD then
            Debug("838 CleanerRobot: Wall ahead while following, frontDist:", frontDist,
                "WALL_DETECT_FRONT:", WALL_THRESHOLD)
            local turnH = self:normalizeAngle(curHeading + 90)
            robotData.moveDirection   = turnH
            robotData.navState        = "turning"
            robotData.openingDetected = false
            Debug("CleanerRobot: Wall ahead while following, turning left")
            return turnH, false
        end

        -- Check for opening to the right
        local rightDist = self:getRightWallDistance(robotData)
        local lastDist  = robotData.lastWallDistance or rightDist
        local jump      = rightDist - lastDist

        if jump > OPENING_JUMP_DIST then
            local turnH = self:normalizeAngle(curHeading - 90)
            local altDist = self:getWallDistance(robotData, turnH, WALL_THRESHOLD)
            if altDist >= WALL_THRESHOLD then
                Debug("859 CleanerRobot: Opening detected! Dist jumped from", lastDist, "to", rightDist)
                robotData.moveDirection   = turnH
                robotData.navState        = "turning"
                robotData.openingDetected = true
                robotData.openingDirection = turnH
                Debug("CleanerRobot: Opening detected! Dist jumped from", lastDist, "to", rightDist)
                return turnH, false
            end
        end

        robotData.lastWallDistance = rightDist
        return curHeading, true
    end

    -- Default "moving" state
    if robotData.turnCompletePosition then
        local dx   = pos.x - robotData.turnCompletePosition.x
        local dy   = pos.y - robotData.turnCompletePosition.y
        local dist = math.sqrt(dx*dx + dy*dy)
        if dist < TURN_COMPLETE_MOVE then
            return curHeading, true
        else
            robotData.turnCompletePosition = nil
        end
    end

    local frontDist = self:getWallDistance(robotData, curHeading, WALL_THRESHOLD)
    if frontDist < WALL_THRESHOLD then
        local turnH = self:normalizeAngle(curHeading + 90)
        robotData.moveDirection   = turnH
        robotData.navState        = "turning"
        robotData.openingDetected = false
        return turnH, false
    end

    robotData.moveDirection = curHeading
    return curHeading, true
end

-- ──────────────────────────────────────────────────────────
-- isPathBlocked(robotData, heading) → blocked, dist
-- ──────────────────────────────────────────────────────────
function CleanerRobot:isPathBlocked(robotData, heading)
    local dist = self:getWallDistance(robotData, heading, WALL_THRESHOLD)
    return dist < WALL_THRESHOLD, dist
end

-- ──────────────────────────────────────────────────────────
-- updateReturningState(robotData) → reached
--   Moves robot toward dock at 1.5× speed.
--   Returns true when docked.
-- ──────────────────────────────────────────────────────────
function CleanerRobot:updateReturningState(robotData)
    if not DoesEntityExist(robotData.robotHandle) then return true end

    local pos       = GetEntityCoords(robotData.robotHandle)
    local dockCoords = robotData.dockCoords
    local dx = pos.x - dockCoords.x
    local dy = pos.y - dockCoords.y
    local distToDock = math.sqrt(dx*dx + dy*dy)

    if distToDock < CLOSE_JUNK_RADIUS then
        -- Arrived at dock
        robotData.velocity = 0
        robotData.state    = "docked"

        if robotData.isOwner then
            if robotData.networkedRobotHandle then
                if DoesEntityExist(robotData.networkedRobotHandle) then
                    DeleteEntity(robotData.networkedRobotHandle)
                end
                robotData.networkedRobotHandle = nil

                -- Restore decoration handle as robot handle
                if robotData.decorationHandle and DoesEntityExist(robotData.decorationHandle) then
                    robotData.robotHandle = robotData.decorationHandle
                    SetEntityCoords(robotData.robotHandle,
                        dockCoords.x, dockCoords.y, dockCoords.z,
                        false, false, false, false)
                    SetEntityHeading(robotData.robotHandle, robotData.dockRotation.z)
                end

                TriggerServerEvent("crime:cleaner:stopped", robotData.house, robotData.id)
                robotData.isOwner = false
            end
        end

        robotData.currentHeading = robotData.dockRotation.z
        Debug("CleanerRobot: Returned to dock")
        PlaySoundFrontend(-1, "Beep_Green", "DLC_HEIST_HACKING_SNAKE_SOUNDS", true)
        SendReactMessage("cleaner_sound", { action = "stop" })
        return true
    end

    -- Navigate toward dock
    local len = math.sqrt(dx*dx + dy*dy)
    if len > 0 then dx = dx / len; dy = dy / len end

    -- Compute angle toward dock
    local angleToDoc = self:normalizeAngle(math.deg(math.atan(dx, dy)))
    robotData.currentHeading = angleToDoc
    SetEntityHeading(robotData.robotHandle, angleToDoc)

    local speed  = self.moveSpeed * 1.5
    local newX   = pos.x + dx * speed
    local newY   = pos.y + dy * speed
    local newZ   = (robotData.baseZ or pos.z) + (robotData.robotHeightOffset or 0)
    SetEntityCoords(robotData.robotHandle, newX, newY, newZ, false, false, false, false)
    robotData.lastMoveTime = GetGameTimer()
    return false
end

-- ──────────────────────────────────────────────────────────
-- startUpdateLoop()
--   Per-frame loop that ticks all active robots.
-- ──────────────────────────────────────────────────────────
function CleanerRobot:startUpdateLoop()
    if self.activeThread then return end
    self.activeThread = true

    CreateThread(function()
        while self.activeThread do
            local anyActive = false

            for _, robotData in pairs(self.robots) do
                if robotData.state == "cleaning" or robotData.state == "returning" then
                    anyActive = true

                    robotData.velocity    = robotData.velocity    or 0
                    robotData.wobblePhase = robotData.wobblePhase or 0
                    if not robotData.currentHeading then
                        robotData.currentHeading = GetEntityHeading(robotData.robotHandle)
                    end
                    if not robotData.isInitialized then
                        self:initRoombaState(robotData)
                    end

                    if robotData.state == "cleaning" then
                        -- Check timeout
                        if robotData.cleaningStartTime then
                            local elapsed = GetGameTimer() - robotData.cleaningStartTime
                            if elapsed >= self.cleaningTimeout then
                                robotData.state            = "returning"
                                robotData.cleaningStartTime = nil
                                Notification(i18n.t("cleaner.returning"), "info")
                                Debug("CleanerRobot: Cleaning timeout, returning to dock", robotData.id)
                            end
                        else
                            local newH, canMove = self:updateCleaningState(robotData)
                            self:updateRotation(robotData, newH, false)
                            self:updateVelocity(robotData, canMove)
                            if canMove then self:applyMovement(robotData) end
                        end

                    elseif robotData.state == "returning" then
                        self:updateReturningState(robotData)
                    end
                end
            end

            if not anyActive then
                self.activeThread = false
                break
            end

            Wait(UPDATE_INTERVAL_MS)
        end
    end)
end

-- ──────────────────────────────────────────────────────────
-- spawnForDecoration(decorationObj, houseId) → bool
--   Creates the dock object and initialises a robot entry
--   for a placed decoration item.
-- ──────────────────────────────────────────────────────────
function CleanerRobot:spawnForDecoration(decorationObj, houseId)
    if not (decorationObj and decorationObj.id) then return false end

    local isCleaner, modelData = self:isCleanerModel(decorationObj.modelName)
    if not isCleaner or not modelData then return false end

    if self.robots[decorationObj.id] then
        Debug("CleanerRobot: Robot already exists for decoration", decorationObj.id)
        return true
    end

    local decorHandle = decorationObj.handle
    if not (decorHandle and DoesEntityExist(decorHandle)) then
        Debug("CleanerRobot: Decoration object handle not found")
        return false
    end

    local coords   = decorationObj.coords
    local rotation = decorationObj.rotation or vec3(0, 0, 0)

    -- Spawn dock object (slightly below the placement coords)
    local dockHash = joaat(modelData.dockerModel)
    lib.requestModel(dockHash, Config.DefaultRequestModelTimeout or 5000)

    local dockHandle = CreateObject(dockHash,
        coords.x, coords.y, coords.z - 0.07, false, false, false)

    if not DoesEntityExist(dockHandle) then
        Debug("CleanerRobot: Failed to spawn dock")
        SetModelAsNoLongerNeeded(dockHash)
        return false
    end

    SetEntityRotation(dockHandle, rotation.x, rotation.y, rotation.z, 0, false)
    FreezeEntityPosition(dockHandle, true)
    SetEntityCompletelyDisableCollision(dockHandle, true, false)
    SetModelAsNoLongerNeeded(dockHash)

    -- Calculate robot Z offset (half-height of robot model)
    local robotHash       = joaat(modelData.model)
    local dockDimMin, dockDimMax = GetModelDimensions(dockHash)
    local dockHeight      = dockDimMax.z - dockDimMin.z

    local roboDimMin, roboDimMax = GetModelDimensions(robotHash)
    local robotHalfHeight = (roboDimMax.z - roboDimMin.z) * 0.5

    local dockCoords  = vec3(coords.x, coords.y, coords.z + robotHalfHeight)

    -- Build robot entry
    local robotData = {
        id                    = decorationObj.id,
        decorationObj         = decorationObj,
        robotHandle           = decorHandle,
        dockHandle            = dockHandle,
        robotModel            = modelData.model,
        dockModel             = modelData.dockerModel,
        dockCoords            = dockCoords,
        dockRotation          = rotation,
        baseZ                 = coords.z,
        robotHeightOffset     = robotHalfHeight,
        state                 = "docked",
        currentTarget         = nil,
        cleanedJunk           = {},
        house                 = houseId,
        velocity              = 0,
        targetHeading         = rotation.z,
        currentHeading        = rotation.z,
        wobblePhase           = 0,
        lastMoveTime          = 0,
        lastKnownCoords       = vec3(coords.x, coords.y, coords.z),
        isInitialized         = false,
        navState              = "moving",
        moveDirection         = nil,
        lastWallDistance      = nil,
        wallFollowStartTime   = nil,
        openingDetected       = false,
        openingDirection      = nil,
        turnCompletePosition  = nil,
    }

    self.robots[decorationObj.id] = robotData
    Debug("CleanerRobot: Initialized cleaner for decoration", decorationObj.id)
    return true
end

-- ──────────────────────────────────────────────────────────
-- despawn(robotId)
-- ──────────────────────────────────────────────────────────
function CleanerRobot:despawn(robotId)
    local robotData = self.robots[robotId]
    if not robotData then return end

    -- Stop cleaning if owner
    if robotData.isOwner then
        if robotData.state == "cleaning" or robotData.state == "returning" then
            TriggerServerEvent("crime:cleaner:stopped", robotData.house, robotId)
            SendReactMessage("cleaner_sound", { action = "stop" })
        end
    end

    -- Delete networked robot
    if robotData.networkedRobotHandle and DoesEntityExist(robotData.networkedRobotHandle) then
        DeleteEntity(robotData.networkedRobotHandle)
        robotData.networkedRobotHandle = nil
    end

    -- Delete dock
    if DoesEntityExist(robotData.dockHandle) then
        DeleteEntity(robotData.dockHandle)
    end

    -- Reset decoration handle to dock position
    if DoesEntityExist(robotData.robotHandle) then
        SetEntityCoords(robotData.robotHandle,
            robotData.dockCoords.x, robotData.dockCoords.y, robotData.dockCoords.z,
            false, false, false, false)
        SetEntityHeading(robotData.robotHandle, robotData.dockRotation.z)
    end

    self.robots[robotId] = nil
    Debug("CleanerRobot: Despawned cleaner", robotId)
end

-- ──────────────────────────────────────────────────────────
-- startCleaning(robotId)
--   Requests server permission, spawns networked robot,
--   starts the update loop.
-- ──────────────────────────────────────────────────────────
function CleanerRobot:startCleaning(robotId)
    local robotData = self.robots[robotId]
    if not robotData then
        Debug("CleanerRobot: Robot not found", robotId)
        return
    end

    if robotData.state ~= "docked" and robotData.state ~= "idle" then
        Debug("CleanerRobot: Robot is not ready to clean", robotData.state)
        return
    end

    local ok, reason = lib.callback.await("crime:cleaner:start", false,
        robotData.house, robotId, robotData.robotModel)

    if not ok then
        if reason == "already_active" then
            Notification(i18n.t("cleaner.already_active"), "error")
        end
        Debug("CleanerRobot: Server rejected start", reason)
        return
    end

    -- Save decoration handle; we'll spawn a new networked entity
    robotData.decorationHandle = robotData.robotHandle
    robotData.isOwner          = true

    -- Spawn networked robot at dock coords
    local robotHash = joaat(robotData.robotModel)
    lib.requestModel(robotHash, Config.DefaultRequestModelTimeout or 5000)

    local newRobot = CreateObject(robotHash,
        robotData.dockCoords.x, robotData.dockCoords.y, robotData.dockCoords.z,
        true, true, true)

    if not DoesEntityExist(newRobot) then
        Debug("CleanerRobot: Failed to spawn networked robot")
        TriggerServerEvent("crime:cleaner:stopped", robotData.house, robotId)
        SetModelAsNoLongerNeeded(robotHash)
        return
    end

    SetEntityInvincible(newRobot, true)
    SetEntityRotation(newRobot, 0.0, 0.0, robotData.dockRotation.z, 0, false)
    SetEntityCompletelyDisableCollision(newRobot, true, false)
    SetModelAsNoLongerNeeded(robotHash)

    robotData.networkedRobotHandle = newRobot
    robotData.robotHandle          = newRobot

    local netId = NetworkGetNetworkIdFromEntity(newRobot)
    TriggerServerEvent("crime:cleaner:updateNetworkId", robotData.house, robotId, netId)

    -- Initialise state
    robotData.state             = "cleaning"
    robotData.cleanedJunk       = {}
    robotData.velocity          = 0
    robotData.wobblePhase       = 0
    robotData.currentHeading    = GetEntityHeading(newRobot)
    robotData.targetHeading     = robotData.currentHeading
    robotData.lastMoveTime      = GetGameTimer()
    robotData.cleaningStartTime = GetGameTimer()
    self:initRoombaState(robotData)
    robotData.currentTarget     = nil

    Debug("CleanerRobot: Started cleaning with networked robot", robotId, "networkId", netId)
    Notification(i18n.t("cleaner.cleaning"), "info")
    self:startUpdateLoop()
    PlaySoundFrontend(-1, "Beep_Green", "DLC_HEIST_HACKING_SNAKE_SOUNDS", true)
    SendReactMessage("cleaner_sound", { action = "start" })
end

-- ──────────────────────────────────────────────────────────
-- stopCleaning(robotId) — transition to returning
-- ──────────────────────────────────────────────────────────
function CleanerRobot:stopCleaning(robotId)
    local robotData = self.robots[robotId]
    if not robotData then return end

    if robotData.state == "cleaning" then
        robotData.state             = "returning"
        robotData.cleaningStartTime = nil
        Notification(i18n.t("cleaner.returning"), "info")
        Debug("CleanerRobot: Returning to dock", robotId)
        self:startUpdateLoop()
    end
end

-- ──────────────────────────────────────────────────────────
-- returnToDock(robotId) — force return at any time
-- ──────────────────────────────────────────────────────────
function CleanerRobot:returnToDock(robotId)
    local robotData = self.robots[robotId]
    if not robotData then return end

    robotData.state = "returning"
    Notification(i18n.t("cleaner.returning"), "info")
    self:startUpdateLoop()
    Debug("CleanerRobot: Manually returning to dock", robotId)
end

-- ──────────────────────────────────────────────────────────
-- Simple accessors
-- ──────────────────────────────────────────────────────────
function CleanerRobot:get(robotId)     return self.robots[robotId] end
function CleanerRobot:getAll()          return self.robots end
function CleanerRobot:getState(robotId)
    local r = self.robots[robotId]
    return r and r.state or "unknown"
end
function CleanerRobot:isActive(robotId)
    local r = self.robots[robotId]
    return r and r.state == "cleaning" or false
end
function CleanerRobot:hasRobots()
    return next(self.robots) ~= nil
end
function CleanerRobot:hasActiveCleaningRobot()
    for id, r in pairs(self.robots) do
        if r.state == "cleaning" or r.state == "returning" then
            return true, id
        end
    end
    return false, nil
end

-- ──────────────────────────────────────────────────────────
-- reinitializeAtPosition(robotId, newCoords, newRotation)
-- ──────────────────────────────────────────────────────────
function CleanerRobot:reinitializeAtPosition(robotId, newCoords, newRotation)
    local robotData = self.robots[robotId]
    if not robotData then return end

    if robotData.state ~= "docked" then
        Debug("CleanerRobot: Cannot reinitialize - robot not docked")
        return
    end

    local modelData = self.cleanerModels[robotData.robotModel]
    if not modelData then return end

    -- Recreate dock at new position
    if DoesEntityExist(robotData.dockHandle) then DeleteEntity(robotData.dockHandle) end

    local dockHash = joaat(modelData.dockerModel)
    lib.requestModel(dockHash, Config.DefaultRequestModelTimeout or 5000)

    local newDock = CreateObject(dockHash,
        newCoords.x, newCoords.y, newCoords.z, false, false, false)

    if not DoesEntityExist(newDock) then
        Debug("CleanerRobot: Failed to respawn dock")
        SetModelAsNoLongerNeeded(dockHash)
        return
    end

    SetEntityRotation(newDock, newRotation.x, newRotation.y, newRotation.z, 0, false)
    FreezeEntityPosition(newDock, true)
    SetEntityCompletelyDisableCollision(newDock, true, false)
    SetEntityInvincible(newDock, true)
    SetModelAsNoLongerNeeded(dockHash)

    local dockDimMin, dockDimMax = GetModelDimensions(dockHash)
    local dockHeight = dockDimMax.z - dockDimMin.z

    -- Also reposition the robot handle
    if DoesEntityExist(robotData.robotHandle) then
        SetEntityCoords(robotData.robotHandle,
            newCoords.x, newCoords.y, newCoords.z + dockHeight + 0.02,
            false, false, false, false)
        SetEntityRotation(robotData.robotHandle,
            0.0, 0.0, newRotation.z, 0, false)
    end

    local robotHash            = joaat(robotData.robotModel)
    local rDimMin, rDimMax     = GetModelDimensions(robotHash)
    local robotHalfH           = (rDimMax.z - rDimMin.z) * 0.5

    robotData.dockHandle       = newDock
    robotData.dockCoords       = vec3(newCoords.x, newCoords.y, newCoords.z + robotHalfH)
    robotData.dockRotation     = newRotation
    robotData.baseZ            = newCoords.z
    robotData.lastKnownCoords  = vec3(newCoords.x, newCoords.y, newCoords.z)
    robotData.currentHeading   = newRotation.z
    robotData.targetHeading    = newRotation.z
    Debug("CleanerRobot: Reinitialized at new position", robotId)
end

function CleanerRobot:getCleanerModels() return self.cleanerModels end

-- ──────────────────────────────────────────────────────────
-- cleanAll() — despawn every robot, stop threads
-- ──────────────────────────────────────────────────────────
function CleanerRobot:cleanAll()
    for id, r in pairs(self.robots) do
        if r.isOwner then
            if r.state == "cleaning" or r.state == "returning" then
                TriggerServerEvent("crime:cleaner:stopped", r.house, id)
            end
        end
        if r.networkedRobotHandle and DoesEntityExist(r.networkedRobotHandle) then
            DeleteEntity(r.networkedRobotHandle)
        end
        if DoesEntityExist(r.dockHandle) then DeleteEntity(r.dockHandle) end
    end
    SendReactMessage("cleaner_sound", { action = "stop" })
    self.activeThread      = false
    self.interactionThread = false
    self.robots            = {}
end

-- ──────────────────────────────────────────────────────────
-- scanAndSpawnFromDecorations(houseId)
--   Iterates decorate.objects and spawns a robot for any
--   cleaner-model item.
-- ──────────────────────────────────────────────────────────
function CleanerRobot:scanAndSpawnFromDecorations(houseId)
    if not (decorate and decorate.objects) then return end
    for _, obj in pairs(decorate.objects) do
        if obj.spawned and obj.coords and obj.handle then
            if self:isCleanerModel(obj.modelName) then
                self:spawnForDecoration(obj, houseId)
            end
        end
    end
end

-- ──────────────────────────────────────────────────────────
-- startInteractionLoop() — DrawText3D prompts (non-target mode)
-- ──────────────────────────────────────────────────────────
function CleanerRobot:startInteractionLoop()
    if self.interactionThread then return end
    if Config.UseTarget then return end

    self.interactionThread = true

    CreateThread(function()
        while self.interactionThread and EnteredHouse do
            local playerPos = GetEntityCoords(cache.ped)
            local nearest, nearDist = nil, 2.5

            -- Find nearest dock
            for id, r in pairs(self.robots) do
                if DoesEntityExist(r.dockHandle) then
                    local dist = #(playerPos - GetEntityCoords(r.dockHandle))
                    if dist < nearDist then
                        nearest  = { id = id, data = r }
                        nearDist = dist
                    end
                end
            end

            if nearest and CurrentHouseData and CurrentHouseData.haskey then
                local dockPos = GetEntityCoords(nearest.data.dockHandle)
                local state   = nearest.data.state
                local label   = ""

                if state == "docked" or state == "idle" then
                    label = i18n.t("cleaner.press_start")
                elseif state == "cleaning" then
                    label = i18n.t("cleaner.press_stop")
                elseif state == "returning" then
                    label = i18n.t("cleaner.returning")
                end

                DrawText3D(dockPos.x, dockPos.y, dockPos.z + 0.3,
                    label, "cleaner_robot", "E")

                if IsControlJustPressed(0, 38) then
                    if state == "docked" or state == "idle" then
                        self:startCleaning(nearest.id)
                    elseif state == "cleaning" then
                        self:stopCleaning(nearest.id)
                    end
                end
            end

            Wait(0)
        end

        self.interactionThread = false
    end)
end

function CleanerRobot:stopInteractionLoop()
    self.interactionThread = false
end

-- ──────────────────────────────────────────────────────────
-- Singleton
-- ──────────────────────────────────────────────────────────
_G.cleanerRobot = CleanerRobot:new()

-- Build model list after a short delay (Config fully loaded)
CreateThread(function()
    Wait(1000)
    cleanerRobot:buildModelList()
end)

-- ──────────────────────────────────────────────────────────
-- Decoration tracking table (decorId → { coords, rotation })
-- ──────────────────────────────────────────────────────────
local trackedDecorations = {}

-- Decoration watcher thread: spawns / reinitialises / despawns
-- robots as house furniture is placed/moved/removed.
CreateThread(function()
    while true do
        Wait(500)

        local orgId    = OrganizationManager:getCurrentOrganization()
        local inHouse  = EnteredHouse

        if not inHouse or not orgId then
            trackedDecorations = {}
        elseif decorate and decorate.objects then
            -- Spawn / reinitialise
            for _, obj in pairs(decorate.objects) do
                if obj.id and obj.spawned and obj.coords and obj.handle then
                    local isCleaner = cleanerRobot:isCleanerModel(obj.modelName)
                    if isCleaner then
                        local existing = cleanerRobot:get(obj.id)
                        local coords   = vec3(obj.coords.x, obj.coords.y, obj.coords.z)
                        local rotation = obj.rotation
                            and vec3(obj.rotation.x, obj.rotation.y, obj.rotation.z)
                            or  vec3(0, 0, 0)

                        if not existing then
                            trackedDecorations[obj.id] = { coords = coords, rotation = rotation }
                            cleanerRobot:spawnForDecoration(obj, orgId)
                        else
                            local tracked = trackedDecorations[obj.id]
                            if tracked then
                                local moved    = #(coords - tracked.coords) > 0.1
                                local rotated  = math.abs(rotation.z - tracked.rotation.z) > 1.0
                                if moved or rotated then
                                    existing.robotHandle = obj.handle
                                    cleanerRobot:reinitializeAtPosition(obj.id, coords, rotation)
                                    trackedDecorations[obj.id] = { coords = coords, rotation = rotation }
                                end
                            end
                        end
                    end
                end
            end

            -- Despawn robots whose decoration was removed
            for trackedId in pairs(trackedDecorations) do
                local found = false
                for _, obj in pairs(decorate.objects) do
                    if obj.id == trackedId then found = true break end
                end
                if not found then
                    trackedDecorations[trackedId] = nil
                    cleanerRobot:despawn(trackedId)
                end
            end
        end
    end
end)

-- ──────────────────────────────────────────────────────────
-- ox_target / qb-target registration (when UseTarget = true)
-- ──────────────────────────────────────────────────────────
if Config.UseTarget then
    CreateThread(function()
        Wait(2000)
        -- Wait until models are loaded
        local models = cleanerRobot:getCleanerModels()
        while not next(models) do
            Wait(500)
            models = cleanerRobot:getCleanerModels()
        end

        -- Build hash list
        local modelHashes = {}
        for modelName in pairs(models) do
            table.insert(modelHashes, joaat(modelName))
        end
        if #modelHashes == 0 then return end

        -- ── Shared canInteract guards ──────────────────────
        local function canInteract(entity)
            if not EnteredHouse then return false end
            if not (CurrentHouseData and CurrentHouseData.haskey) then return false end
            for _, r in pairs(cleanerRobot:getAll()) do
                if r.robotHandle == entity then return r.state == "docked" end
            end
            return false
        end

        local function canInteractCleaning(entity)
            if not EnteredHouse then return false end
            if not (CurrentHouseData and CurrentHouseData.haskey) then return false end
            for _, r in pairs(cleanerRobot:getAll()) do
                if r.robotHandle == entity then return r.state == "cleaning" end
            end
            return false
        end

        -- ── ox_target ─────────────────────────────────────
        if GetResourceState("ox_target") == "started" then
            exports.ox_target:addModel(modelHashes, {
                {
                    icon       = "fas fa-play",
                    label      = i18n.t("cleaner.start"),
                    distance   = 2.5,
                    onSelect   = function(data)
                        for id, r in pairs(cleanerRobot:getAll()) do
                            if r.robotHandle == data.entity then
                                if r.state == "docked" or r.state == "idle" then
                                    cleanerRobot:startCleaning(id)
                                end
                                break
                            end
                        end
                    end,
                    canInteract = canInteract,
                },
                {
                    icon       = "fas fa-stop",
                    label      = i18n.t("cleaner.stop"),
                    distance   = 2.5,
                    onSelect   = function(data)
                        for id, r in pairs(cleanerRobot:getAll()) do
                            if r.robotHandle == data.entity and r.state == "cleaning" then
                                cleanerRobot:stopCleaning(id)
                                break
                            end
                        end
                    end,
                    canInteract = canInteractCleaning,
                },
                {
                    icon       = "fas fa-home",
                    label      = i18n.t("cleaner.return_dock"),
                    distance   = 2.5,
                    onSelect   = function(data)
                        for id, r in pairs(cleanerRobot:getAll()) do
                            if r.robotHandle == data.entity then
                                cleanerRobot:returnToDock(id)
                                break
                            end
                        end
                    end,
                    canInteract = canInteractCleaning,
                },
            })
            Debug("CleanerRobot: Registered ox_target models")

        elseif GetResourceState("qb-target") == "started" then
            exports["qb-target"]:AddTargetModel(modelHashes, {
                options = {
                    {
                        icon       = "fas fa-play",
                        label      = i18n.t("cleaner.start"),
                        action     = function(entity)
                            for id, r in pairs(cleanerRobot:getAll()) do
                                if r.robotHandle == entity then
                                    if r.state == "docked" or r.state == "idle" then
                                        cleanerRobot:startCleaning(id)
                                    end
                                    break
                                end
                            end
                        end,
                        canInteract = function(entity) return canInteract(entity) end,
                    },
                    {
                        icon       = "fas fa-stop",
                        label      = i18n.t("cleaner.stop"),
                        action     = function(entity)
                            for id, r in pairs(cleanerRobot:getAll()) do
                                if r.robotHandle == entity and r.state == "cleaning" then
                                    cleanerRobot:stopCleaning(id)
                                    break
                                end
                            end
                        end,
                        canInteract = function(entity) return canInteractCleaning(entity) end,
                    },
                    {
                        icon       = "fas fa-home",
                        label      = i18n.t("cleaner.return_dock"),
                        action     = function(entity)
                            for id, r in pairs(cleanerRobot:getAll()) do
                                if r.robotHandle == entity then
                                    cleanerRobot:returnToDock(id)
                                    break
                                end
                            end
                        end,
                        canInteract = function(entity) return canInteractCleaning(entity) end,
                    },
                },
                distance = 2.5,
            })
            Debug("CleanerRobot: Registered qb-target models")
        end
    end)
end

-- ──────────────────────────────────────────────────────────
-- Resource stop
-- ──────────────────────────────────────────────────────────
AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        cleanerRobot:cleanAll()
    end
end)

-- ──────────────────────────────────────────────────────────
-- Net events
-- ──────────────────────────────────────────────────────────

-- Server: set alpha on a decoration entity (e.g. fade while robot is active)
RegisterNetEvent("crime:cleaner:setDecorationAlpha", function(houseId, decorId, alpha)
    if not (EnteredHouse and EnteredHouse == houseId) then return end
    if not (decorate and decorate.objects) then return end

    for _, obj in pairs(decorate.objects) do
        if obj.id == decorId then
            if obj.handle and DoesEntityExist(obj.handle) then
                SetEntityAlpha(obj.handle, alpha, false)
                Debug("CleanerRobot: Set decoration alpha", decorId, alpha)
            end
            break
        end
    end

    local r = cleanerRobot:get(decorId)
    if r and r.decorationHandle and DoesEntityExist(r.decorationHandle) then
        SetEntityAlpha(r.decorationHandle, alpha, false)
    end
end)

-- Server: another client finished; delete our networked copy
RegisterNetEvent("crime:cleaner:deleteNetworkedRobot", function(houseId, robotId)
    local r = cleanerRobot:get(robotId)
    if not r then return end

    if r.networkedRobotHandle and DoesEntityExist(r.networkedRobotHandle) then
        DeleteEntity(r.networkedRobotHandle)
        r.networkedRobotHandle = nil
        Debug("CleanerRobot: Deleted networked robot by server request", robotId)
    end

    -- Restore decoration handle as the robot handle
    if r.decorationHandle and DoesEntityExist(r.decorationHandle) then
        r.robotHandle = r.decorationHandle
        SetEntityCoords(r.robotHandle,
            r.dockCoords.x, r.dockCoords.y, r.dockCoords.z,
            false, false, false, false)
        SetEntityHeading(r.robotHandle, r.dockRotation.z)
    end

    r.state   = "docked"
    r.isOwner = false
end)
