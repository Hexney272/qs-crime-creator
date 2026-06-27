-- ============================================================
-- server/modules/house/cleaner.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Server-side cleaner (junk removal) session manager.
-- Tracks which players are actively cleaning which decoration,
-- broadcasts alpha changes so all clients see the ghost effect.
-- ============================================================

-- activeSessions[houseId][decorationId] = sessionData
local activeSessions = {}

-- ──────────────────────────────────────────────────────────
-- local isActive(houseId, decorationId)
--   Returns (isActive, ownerId) for a given session.
-- ──────────────────────────────────────────────────────────
local function isActive(houseId, decorationId)
    if activeSessions[houseId] and activeSessions[houseId][decorationId] then
        return true, activeSessions[houseId][decorationId].ownerId
    end
    return false, nil
end

-- ──────────────────────────────────────────────────────────
-- local startCleaner(playerId, houseId, decorationId, modelName)
--   Starts a cleaning session.  Returns (success, errorCode).
-- ──────────────────────────────────────────────────────────
local function startCleaner(playerId, houseId, decorationId, modelName)
    local already, _ = isActive(houseId, decorationId)
    if already then
        return false, "already_active"
    end

    if not activeSessions[houseId] then
        activeSessions[houseId] = {}
    end

    activeSessions[houseId][decorationId] = {
        decorationId = decorationId,
        house        = houseId,
        ownerId      = playerId,
        networkId    = 0,
        modelName    = modelName,
    }

    -- Tell all clients to ghost-out (alpha = 0) the decoration
    TriggerClientEvent("crime:cleaner:setDecorationAlpha", -1, houseId, decorationId, 0)

    Debug("Cleaner started",
        "house", houseId, "decorationId", decorationId, "owner", playerId)

    return true, nil
end

-- ──────────────────────────────────────────────────────────
-- local updateNetworkId(playerId, houseId, decorationId, netId)
--   Updates the networked entity ID for a cleaning session.
-- ──────────────────────────────────────────────────────────
local function updateNetworkId(playerId, houseId, decorationId, netId)
    if activeSessions[houseId] and activeSessions[houseId][decorationId] then
        local session = activeSessions[houseId][decorationId]
        if session.ownerId == playerId then
            session.networkId = netId
            Debug("Cleaner network ID updated",
                "house", houseId, "decorationId", decorationId, "networkId", netId)
        end
    end
end

-- ──────────────────────────────────────────────────────────
-- local stopCleaner(playerId, houseId, decorationId)
--   Ends a cleaning session, restores alpha, and tells the
--   owner to delete their networked robot prop.
--   playerId = 0 means force-stop (e.g. on disconnect).
-- ──────────────────────────────────────────────────────────
local function stopCleaner(playerId, houseId, decorationId)
    if not (activeSessions[houseId] and activeSessions[houseId][decorationId]) then
        return false
    end

    local session = activeSessions[houseId][decorationId]

    -- Enforce ownership (unless forced via playerId = 0)
    if playerId > 0 and session.ownerId ~= playerId then
        return false
    end

    -- Restore decoration visibility for all clients
    TriggerClientEvent("crime:cleaner:setDecorationAlpha", -1, houseId, decorationId, 255)

    -- Ask the owner's client to delete the networked robot entity
    if session.ownerId > 0 then
        TriggerClientEvent("crime:cleaner:deleteNetworkedRobot",
            session.ownerId, houseId, decorationId)
    end

    activeSessions[houseId][decorationId] = nil

    -- If the house has no more active sessions, remove it
    if not next(activeSessions[houseId]) then
        activeSessions[houseId] = nil
    end

    Debug("Cleaner stopped", "house", houseId, "decorationId", decorationId)
    return true
end

-- ──────────────────────────────────────────────────────────
-- local stopAllForPlayer(playerId)
--   Stops every cleaning session owned by `playerId`.
-- ──────────────────────────────────────────────────────────
local function stopAllForPlayer(playerId)
    for houseId, house in pairs(activeSessions) do
        for decorationId, session in pairs(house) do
            if session.ownerId == playerId then
                stopCleaner(0, houseId, decorationId)
            end
        end
    end
end

-- ──────────────────────────────────────────────────────────
-- Callbacks
-- ──────────────────────────────────────────────────────────

lib.callback.register("crime:cleaner:start", function(playerId, houseId, decorationId, modelName)
    return startCleaner(playerId, houseId, decorationId, modelName)
end)

lib.callback.register("crime:cleaner:stop", function(playerId, houseId, decorationId)
    return stopCleaner(playerId, houseId, decorationId)
end)

lib.callback.register("crime:cleaner:isActive", function(_, houseId, decorationId)
    return isActive(houseId, decorationId)
end)

-- ──────────────────────────────────────────────────────────
-- Net events
-- ──────────────────────────────────────────────────────────

RegisterNetEvent("crime:cleaner:updateNetworkId", function(houseId, decorationId, netId)
    updateNetworkId(source, houseId, decorationId, netId)
end)

RegisterNetEvent("crime:cleaner:stopped", function(houseId, decorationId)
    stopCleaner(source, houseId, decorationId)
end)

-- ──────────────────────────────────────────────────────────
-- Cleanup hooks
-- ──────────────────────────────────────────────────────────

AddEventHandler("crime:onInsideHouse", function(_, isInside)
    if not isInside then
        stopAllForPlayer(source)
    end
end)

AddEventHandler("playerDropped", function()
    stopAllForPlayer(source)
end)
