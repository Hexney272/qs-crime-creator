-- ============================================================
-- server/modules/vehicletheft.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Server-side vehicle theft mission session manager.
-- Tracks per-player sessions, validates delivery, and cleans
-- up on disconnect / resource stop.
-- ============================================================

-- activeTheftSessions[playerId] = sessionData
local activeTheftSessions = {}

-- ──────────────────────────────────────────────────────────
-- local pickRandom(list)
--   Returns a random element from `list`, or nil if empty.
-- ──────────────────────────────────────────────────────────
local function pickRandom(list)
    if not list or #list == 0 then return nil end
    return list[math.random(1, #list)]
end

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:vehicletheft:start"
--   Creates a new vehicle-theft session for a player.
--   Randomly picks a spawn location, delivery location, and
--   vehicle model from Config.VehicleTheft.
--   Returns { success, spawnLocation, deliveryLocation, vehicleModel }
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:vehicletheft:start", function(playerId, orgId, orgMissionId)
    if not orgId then
        return { success = false, message = "no_organization" }
    end

    local playerIdentifier = sfr:getIdentifier(playerId)
    if not playerIdentifier then
        return { success = false, message = "invalid_player" }
    end

    -- Only one active session per player
    if activeTheftSessions[playerId] then
        return { success = false, message = "already_active" }
    end

    -- Pick random locations and vehicle from config
    local spawnLocation    = pickRandom(Config.VehicleTheft.spawnLocations)
    local deliveryLocation = pickRandom(Config.VehicleTheft.deliveryLocations)
    local vehicleModel     = pickRandom(Config.VehicleTheft.vehicles)

    if not (spawnLocation and deliveryLocation) or not vehicleModel then
        return { success = false, message = "config_error" }
    end

    local firstName, lastName = sfr:getUserName(playerId)
    local playerName = firstName .. " " .. lastName

    -- Register the session
    activeTheftSessions[playerId] = {
        orgId            = orgId,
        orgMissionId     = orgMissionId,
        identifier       = playerIdentifier,
        playerName       = playerName,
        startTime        = os.time(),
        spawnLocation    = spawnLocation,
        deliveryLocation = deliveryLocation,
        vehicleModel     = vehicleModel,
        delivered        = false,
    }

    Debug("crime:vehicletheft:start",
        "Session started for player:", playerId,
        "org:", orgId,
        "vehicle:", vehicleModel)

    return {
        success          = true,
        spawnLocation    = spawnLocation,
        deliveryLocation = deliveryLocation,
        vehicleModel     = vehicleModel,
    }
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:vehicletheft:deliver"
--   Marks the player's vehicle as delivered.
--   Returns { success } or { success=false, message }
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:vehicletheft:deliver", function(playerId, orgId, orgMissionId)
    local session = activeTheftSessions[playerId]

    if not session then
        return { success = false, message = "no_active_session" }
    end

    if session.orgId ~= orgId then
        return { success = false, message = "wrong_organization" }
    end

    if session.orgMissionId ~= orgMissionId then
        return { success = false, message = "wrong_mission" }
    end

    if session.delivered then
        return { success = false, message = "already_delivered" }
    end

    session.delivered = true

    Debug("crime:vehicletheft:deliver", "Vehicle delivered by player:", playerId)

    -- Clear the session after delivery
    activeTheftSessions[playerId] = nil

    return { success = true }
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:vehicletheft:cancel"
--   Cancels an active vehicle-theft session.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:vehicletheft:cancel", function(playerId, orgId)
    local session = activeTheftSessions[playerId]

    if not session then
        return { success = false, message = "no_active_session" }
    end

    if session.orgId ~= orgId then
        return { success = false, message = "wrong_organization" }
    end

    activeTheftSessions[playerId] = nil

    Debug("crime:vehicletheft:cancel", "Mission cancelled for player:", playerId)

    return { success = true }
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:vehicletheft:isActive"
--   Returns true if the player has an active session.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:vehicletheft:isActive", function(playerId)
    return activeTheftSessions[playerId] ~= nil
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:vehicletheft:getSession"
--   Returns the player's session data table (or nil).
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:vehicletheft:getSession", function(playerId)
    return activeTheftSessions[playerId]
end)

-- ──────────────────────────────────────────────────────────
-- playerDropped — clear session on disconnect
-- ──────────────────────────────────────────────────────────
AddEventHandler("playerDropped", function()
    local playerId = source
    if activeTheftSessions[playerId] then
        Debug("crime:vehicletheft", "Player disconnected, clearing session:", playerId)
        activeTheftSessions[playerId] = nil
    end
end)

-- ──────────────────────────────────────────────────────────
-- onResourceStop — wipe all sessions on restart
-- ──────────────────────────────────────────────────────────
AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        activeTheftSessions = {}
    end
end)

Debug("Vehicle Theft module loaded")
