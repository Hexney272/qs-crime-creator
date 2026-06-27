-- ============================================================
-- server/modules/house/junk.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- House junk system.  Periodically spawns debris inside
-- org houses; tracks which players are inside each house so
-- spawn events reach the right clients.
-- ============================================================

-- junkTimers[houseId]  = SetTimeout handle (nil when no timer active)
-- playersInHouse[houseId] = { playerId, ... }
local junkTimers     = {}
local playersInHouse = {}

-- ──────────────────────────────────────────────────────────
-- local pickRandomJunk()
--   Returns a random junk object model from Config.JunkObjects.
-- ──────────────────────────────────────────────────────────
local function pickRandomJunk()
    local objects = Config.JunkObjects
    return objects[math.random(1, #objects)]
end

-- ──────────────────────────────────────────────────────────
-- local hasJunk(houseId)
-- ──────────────────────────────────────────────────────────
local function hasJunk(houseId)
    return playersInHouse[houseId] and #playersInHouse[houseId] > 0
end

-- ──────────────────────────────────────────────────────────
-- DB helpers
-- ──────────────────────────────────────────────────────────

local function dbCreateJunk(houseId)
    local model = pickRandomJunk()
    local newId = MySQL.insert.await(
        "INSERT INTO qs_crime_house_junks (house, model, coords) VALUES (?, ?, NULL)",
        { houseId, model }
    )
    return newId or nil
end

local function dbDeleteJunk(junkId)
    local affected = MySQL.update.await(
        "DELETE FROM qs_crime_house_junks WHERE id = ?", { junkId })
    return affected > 0
end

local function dbSetJunkCoords(junkId, coords)
    if not (coords and coords.x and coords.y and coords.z) then return false end
    local coordsJson = json.encode({ x = coords.x, y = coords.y, z = coords.z })
    local affected   = MySQL.update.await(
        "UPDATE qs_crime_house_junks SET coords = ? WHERE id = ?",
        { coordsJson, junkId }
    )
    return affected > 0
end

local function dbGetJunkForHouse(houseId)
    local rows = MySQL.query.await(
        "SELECT * FROM qs_crime_house_junks WHERE house = ?", { houseId })

    local result = {}
    for _, row in ipairs(rows or {}) do
        local coords = row.coords and json.decode(row.coords) or nil
        table.insert(result, {
            id         = row.id,
            house      = row.house,
            model      = row.model,
            coords     = coords,
            created_at = row.created_at,
        })
    end
    return result
end

local function dbCountJunk(houseId)
    return MySQL.scalar.await(
        "SELECT COUNT(*) FROM qs_crime_house_junks WHERE house = ?", { houseId }
    ) or 0
end

-- ──────────────────────────────────────────────────────────
-- local spawnJunkForHouse(houseId)
--   Creates one junk record and notifies clients inside.
-- ──────────────────────────────────────────────────────────
local function spawnJunkForHouse(houseId)
    if not Config.Cleaning then return end

    local maxJunk    = Config.MaxJunkPerHouse or 10
    local currentCount = dbCountJunk(houseId)

    if currentCount >= maxJunk then
        Debug("spawnJunkForHouse - Max junk reached for:",
            houseId, currentCount, "/", maxJunk)
        return
    end

    local newJunkId = dbCreateJunk(houseId)
    if not newJunkId then return end

    local junkData = {
        id     = newJunkId,
        house  = houseId,
        model  = pickRandomJunk(),
        coords = nil,
    }

    if hasJunk(houseId) then
        for _, playerId in ipairs(playersInHouse[houseId]) do
            TriggerClientEvent("crime:junk:spawn", playerId, junkData)
        end
    end
end

-- ──────────────────────────────────────────────────────────
-- local startJunkTimer(houseId)
--   Schedules periodic junk spawning for a house if not
--   already scheduled.
-- ──────────────────────────────────────────────────────────
local function startJunkTimer(houseId)
    if junkTimers[houseId] then return end
    if not Config.Cleaning then return end

    local interval = Config.JunkObjectTime

    junkTimers[houseId] = SetTimeout(interval, function()
        if not junkTimers[houseId] then return end

        junkTimers[houseId] = nil
        spawnJunkForHouse(houseId)
        startJunkTimer(houseId)
    end)
end

local function stopJunkTimer(houseId)
    if junkTimers[houseId] then
        junkTimers[houseId] = nil
    end
end

-- ──────────────────────────────────────────────────────────
-- Player tracking
-- ──────────────────────────────────────────────────────────

local function playerEnterHouse(playerId, houseId)
    if not playersInHouse[houseId] then
        playersInHouse[houseId] = {}
    end

    for _, pid in ipairs(playersInHouse[houseId]) do
        if pid == playerId then return end
    end

    table.insert(playersInHouse[houseId], playerId)

    -- Start the junk timer on first player entering
    if #playersInHouse[houseId] == 1 then
        startJunkTimer(houseId)
    end

    Debug("Player", playerId, "entered house:", houseId,
        "total players:", #playersInHouse[houseId])
end

local function playerLeaveHouse(playerId, houseId)
    if not playersInHouse[houseId] then return end

    for i, pid in ipairs(playersInHouse[houseId]) do
        if pid == playerId then
            table.remove(playersInHouse[houseId], i)
            break
        end
    end

    if #playersInHouse[houseId] == 0 then
        stopJunkTimer(houseId)
        playersInHouse[houseId] = nil
    end

    local remaining = (playersInHouse[houseId] and #playersInHouse[houseId]) or 0
    Debug("Player", playerId, "left house:", houseId, "remaining:", remaining)
end

-- ──────────────────────────────────────────────────────────
-- Callbacks
-- ──────────────────────────────────────────────────────────

lib.callback.register("crime:junk:getForHouse", function(_, houseId)
    return dbGetJunkForHouse(houseId)
end)

lib.callback.register("crime:junk:updateCoords", function(_, junkId, coords)
    if not junkId or not coords then return false end

    if type(coords) ~= "table" or not (coords.x and coords.y and coords.z) then
        Debug("crime:junk:updateCoords - Invalid coords structure:", coords)
        return false
    end

    return dbSetJunkCoords(junkId, coords)
end)

lib.callback.register("crime:junk:remove", function(playerId, junkId, houseId)
    if not junkId then return false end

    local ok = dbDeleteJunk(junkId)

    if ok and playersInHouse[houseId] then
        -- Tell all other players in the house to remove this junk
        for _, pid in ipairs(playersInHouse[houseId]) do
            if pid ~= playerId then
                TriggerClientEvent("crime:junk:remove", pid, junkId)
            end
        end
    end

    return ok
end)

-- ──────────────────────────────────────────────────────────
-- Events
-- ──────────────────────────────────────────────────────────

AddEventHandler("crime:onInsideHouse", function(houseData, isInside)
    if not Config.Cleaning then return end

    local playerId = source

    -- houseData may be a table with .house / .name or just the ID
    local houseId = houseData
    if type(houseData) == "table" then
        houseId = houseData.house or houseData.name
    end
    if not houseId then return end

    if isInside then
        playerEnterHouse(playerId, houseId)
    else
        playerLeaveHouse(playerId, houseId)
    end
end)

AddEventHandler("playerDropped", function()
    local playerId = source

    for houseId, players in pairs(playersInHouse) do
        for i, pid in ipairs(players) do
            if pid == playerId then
                table.remove(players, i)

                if #players == 0 then
                    stopJunkTimer(houseId)
                    playersInHouse[houseId] = nil
                end
                break
            end
        end
    end
end)

-- ──────────────────────────────────────────────────────────
-- Startup: if cleaning is enabled, purge junk older than 7 days
-- ──────────────────────────────────────────────────────────
if Config.Cleaning then
    CreateThread(function()
        while true do
            local affected = MySQL.update.await(
                "DELETE FROM qs_crime_house_junks "
                .. "WHERE created_at < DATE_SUB(NOW(), INTERVAL 7 DAY)"
            )
            if affected and affected > 0 then
                Debug("Cleaned up", affected, "old junk entries")
            end
            Wait(86400000)   -- run once a day
        end
    end)
end
