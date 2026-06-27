-- ============================================================
-- server/modules/db/pvp.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- PvP battle CRUD, participant management, and score queries.
-- ============================================================

-- local: convert Unix-ms timestamp or string → "YYYY-MM-DD HH:MM:SS"
local function toDatetimeString(value)
    if not value then return nil end
    if type(value) == "string" then return value end
    return os.date("%Y-%m-%d %H:%M:%S", math.floor(value / 1000))
end

-- ──────────────────────────────────────────────────────────
-- local: decode JSON fields on a battle row
-- ──────────────────────────────────────────────────────────
local function decodeBattleRow(row)
    if row.zone_points           then row.zone_points           = json.decode(row.zone_points)           end
    if row.center_coords         then row.center_coords         = json.decode(row.center_coords)         end
    if row.rewards               then row.rewards               = json.decode(row.rewards)               end
    if row.allowed_organizations then row.allowed_organizations = json.decode(row.allowed_organizations) end
    return row
end

-- ──────────────────────────────────────────────────────────
-- local: compute centroid of zone points
-- ──────────────────────────────────────────────────────────
local function calcCentroid(points)
    if not points or #points < 3 then return nil end
    local sx, sy, sz = 0, 0, 0
    for _, p in ipairs(points) do
        sx = sx + (p.x or 0)
        sy = sy + (p.y or 0)
        sz = sz + (p.z or 0)
    end
    local n = #points
    return { x = sx / n, y = sy / n, z = sz / n }
end

-- ──────────────────────────────────────────────────────────
-- db.createPvpBattle(playerId, data)
--   data: { label, start_date (ms), duration, zone_points,
--           rewards, allowed_organizations }
-- ──────────────────────────────────────────────────────────
function db.createPvpBattle(playerId, data)
    if not (data and data.label) then
        Error("db.createPvpBattle", "data and data.label must be provided")
        return nil
    end
    if not data.start_date then
        Error("db.createPvpBattle", "start_date must be provided")
        return nil
    end
    if not data.duration or data.duration <= 0 then
        Error("db.createPvpBattle", "duration must be provided and greater than 0")
        return nil
    end
    if not (data.zone_points and data.zone_points.points and #data.zone_points.points >= 3) then
        Error("db.createPvpBattle", "zone_points with at least 3 points must be provided")
        return nil
    end

    local creatorId = sfr:getIdentifier(playerId)
    local centroid  = calcCentroid(data.zone_points.points)
    local startStr  = toDatetimeString(data.start_date)

    local newId = MySQL.insert.await([[
        INSERT INTO qs_crime_pvp_battles (
            label, start_date, duration, zone_points, center_coords,
            rewards, allowed_organizations, creator
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.label,
        startStr,
        data.duration,
        data.zone_points           and json.encode(data.zone_points)           or nil,
        centroid                   and json.encode(centroid)                   or nil,
        data.rewards               and json.encode(data.rewards)               or nil,
        data.allowed_organizations and json.encode(data.allowed_organizations) or nil,
        creatorId,
    })

    if newId then
        Debug("db.createPvpBattle", "Created PvP battle:", newId)

        -- Seed participants
        if data.allowed_organizations and #data.allowed_organizations > 0 then
            db.createPvpParticipants(newId, data.allowed_organizations)
        else
            -- Invite all organizations
            local orgs = MySQL.query.await("SELECT id FROM qs_crime_organizations", {})
            if orgs and #orgs > 0 then
                local ids = {}
                for _, org in ipairs(orgs) do ids[#ids + 1] = org.id end
                if #ids > 0 then db.createPvpParticipants(newId, ids) end
            end
        end

        return newId
    end

    Error("db.createPvpBattle", "Failed to create PvP battle")
    return nil
end

-- ──────────────────────────────────────────────────────────
-- db.updatePvpBattle(self, pvpBattleId, data)
-- ──────────────────────────────────────────────────────────
function db.updatePvpBattle(self, pvpBattleId, data)
    if not pvpBattleId or not data then
        Error("db.updatePvpBattle", "pvpBattleId and data must be provided")
        return false
    end

    local setClauses = {}
    local params     = {}

    if data.label then
        setClauses[#setClauses + 1] = "label = ?"
        params[#params + 1]         = data.label
    end
    if data.start_date then
        setClauses[#setClauses + 1] = "start_date = ?"
        params[#params + 1]         = toDatetimeString(data.start_date)
    end
    if data.duration then
        setClauses[#setClauses + 1] = "duration = ?"
        params[#params + 1]         = data.duration
    end
    if data.zone_points then
        setClauses[#setClauses + 1] = "zone_points = ?"
        params[#params + 1]         = json.encode(data.zone_points)

        -- Recalculate centroid
        if data.zone_points.points and #data.zone_points.points >= 3 then
            local centroid = calcCentroid(data.zone_points.points)
            if centroid then
                setClauses[#setClauses + 1] = "center_coords = ?"
                params[#params + 1]         = json.encode(centroid)
            end
        end
    end
    if data.rewards ~= nil then
        setClauses[#setClauses + 1] = "rewards = ?"
        params[#params + 1]         = data.rewards and json.encode(data.rewards) or nil
    end
    if data.allowed_organizations ~= nil then
        setClauses[#setClauses + 1] = "allowed_organizations = ?"
        params[#params + 1]         = data.allowed_organizations
                                     and json.encode(data.allowed_organizations) or nil
    end

    if #setClauses == 0 then
        Error("db.updatePvpBattle", "No fields to update")
        return false
    end

    params[#params + 1] = pvpBattleId

    local ok = MySQL.update.await(
        "UPDATE qs_crime_pvp_battles SET " .. table.concat(setClauses, ", ") .. " WHERE id = ?",
        params
    )

    if ok then
        Debug("db.updatePvpBattle", "Updated PvP battle:", pvpBattleId)
        return true
    end

    Error("db.updatePvpBattle", "Failed to update PvP battle:", pvpBattleId)
    return false
end

-- ──────────────────────────────────────────────────────────
-- db.removePvpBattle(pvpBattleId)
-- ──────────────────────────────────────────────────────────
function db.removePvpBattle(pvpBattleId)
    if not pvpBattleId then
        Error("db.removePvpBattle", "pvpBattleId must be provided")
        return false
    end

    local ok = MySQL.query.await(
        "DELETE FROM qs_crime_pvp_battles WHERE id = ?", { pvpBattleId })

    if ok then
        Debug("db.removePvpBattle", "Removed PvP battle:", pvpBattleId)
        return true
    end

    Error("db.removePvpBattle", "Failed to remove PvP battle:", pvpBattleId)
    return false
end

-- ──────────────────────────────────────────────────────────
-- db.getPvpBattles()
-- ──────────────────────────────────────────────────────────
function db.getPvpBattles()
    local rows = MySQL.query.await([[
        SELECT * FROM qs_crime_pvp_battles ORDER BY created_at DESC
    ]])

    if not rows or #rows == 0 then
        Debug("db.getPvpBattles", "No PvP battles found")
        return {}
    end

    for _, row in ipairs(rows) do decodeBattleRow(row) end
    return rows
end

-- ──────────────────────────────────────────────────────────
-- db.getPvpBattle(pvpBattleId)
-- ──────────────────────────────────────────────────────────
function db.getPvpBattle(pvpBattleId)
    if not pvpBattleId then return nil end

    local row = MySQL.single.await([[
        SELECT * FROM qs_crime_pvp_battles WHERE id = ?
    ]], { pvpBattleId })

    if not row then return nil end
    return decodeBattleRow(row)
end

-- ──────────────────────────────────────────────────────────
-- db.getActivePvpBattles()
-- ──────────────────────────────────────────────────────────
function db.getActivePvpBattles()
    local rows = MySQL.query.await([[
        SELECT * FROM qs_crime_pvp_battles
        WHERE status = 'active'
        ORDER BY start_date ASC
    ]])

    if not rows or #rows == 0 then return {} end

    for _, row in ipairs(rows) do decodeBattleRow(row) end
    return rows
end

-- ──────────────────────────────────────────────────────────
-- db.getPvpParticipants(pvpBattleId)
-- ──────────────────────────────────────────────────────────
function db.getPvpParticipants(pvpBattleId)
    if not pvpBattleId then return {} end

    return MySQL.query.await([[
        SELECT * FROM qs_crime_pvp_participants
        WHERE pvp_battle_id = ?
        ORDER BY created_at ASC
    ]], { pvpBattleId }) or {}
end

-- ──────────────────────────────────────────────────────────
-- db.updatePvpParticipantStatus(battleId, orgId, status, acceptedBy)
-- ──────────────────────────────────────────────────────────
function db.updatePvpParticipantStatus(battleId, orgId, status, acceptedBy)
    if not (battleId and orgId) or not status then
        Error("db.updatePvpParticipantStatus",
              "pvpBattleId, organizationId and status must be provided")
        return false
    end

    local acceptedAt = (status == "accepted") and os.date("%Y-%m-%d %H:%M:%S") or nil

    local ok = MySQL.update.await([[
        UPDATE qs_crime_pvp_participants
        SET status = ?, accepted_by = ?, accepted_at = ?
        WHERE pvp_battle_id = ? AND organization_id = ?
    ]], { status, acceptedBy, acceptedAt, battleId, orgId })

    if ok then
        Debug("db.updatePvpParticipantStatus", "Updated participant status:",
            battleId, orgId, status)
        return true
    end
    return false
end

-- ──────────────────────────────────────────────────────────
-- db.createPvpParticipants(pvpBattleId, orgIdList)
-- ──────────────────────────────────────────────────────────
function db.createPvpParticipants(pvpBattleId, orgIdList)
    if not pvpBattleId or not orgIdList or #orgIdList == 0 then
        Error("db.createPvpParticipants", "pvpBattleId and organizationIds must be provided")
        return false
    end

    local placeholders = {}
    local params       = {}
    for _, orgId in ipairs(orgIdList) do
        placeholders[#placeholders + 1] = "(?, ?)"
        params[#params + 1] = pvpBattleId
        params[#params + 1] = orgId
    end

    local sql = string.format([[
        INSERT INTO qs_crime_pvp_participants (pvp_battle_id, organization_id)
        VALUES %s
    ]], table.concat(placeholders, ", "))

    local ok = MySQL.insert.await(sql, params)
    if ok then
        Debug("db.createPvpParticipants", "Created", #orgIdList,
            "participants for PvP battle:", pvpBattleId)
        return true
    end

    Error("db.createPvpParticipants", "Failed to create participants for PvP battle:", pvpBattleId)
    return false
end

-- ──────────────────────────────────────────────────────────
-- db.getPvpScore(pvpBattleId, orgId)
-- ──────────────────────────────────────────────────────────
function db.getPvpScore(pvpBattleId, orgId)
    if not pvpBattleId or not orgId then return nil end

    return MySQL.single.await([[
        SELECT * FROM qs_crime_pvp_scores
        WHERE pvp_battle_id = ? AND organization_id = ?
    ]], { pvpBattleId, orgId })
end

-- ──────────────────────────────────────────────────────────
-- db.getPvpScores(pvpBattleId)
--   Returns all scores for a battle with org label/color.
-- ──────────────────────────────────────────────────────────
function db.getPvpScores(pvpBattleId)
    if not pvpBattleId then return {} end

    return MySQL.query.await([[
        SELECT
            ps.*,
            o.label as organization_label,
            o.color as organization_color
        FROM qs_crime_pvp_scores ps
        LEFT JOIN qs_crime_organizations o ON ps.organization_id = o.id
        WHERE ps.pvp_battle_id = ?
        ORDER BY ps.score DESC
    ]], { pvpBattleId }) or {}
end

-- ──────────────────────────────────────────────────────────
-- db.getTerritoryWarScores(warId)  (alias used by taxing.lua)
-- ──────────────────────────────────────────────────────────
function db.getTerritoryWarScores(warId)
    return db.getPvpScores(warId)
end

-- ──────────────────────────────────────────────────────────
-- db.updatePvpScore(pvpBattleId, orgId, scoreDelta)
--   Upserts a score row (increments on duplicate).
-- ──────────────────────────────────────────────────────────
function db.updatePvpScore(pvpBattleId, orgId, scoreDelta)
    if not pvpBattleId or not orgId then
        Error("db.updatePvpScore", "pvpBattleId and organizationId must be provided")
        return false
    end

    local ok = MySQL.insert.await([[
        INSERT INTO qs_crime_pvp_scores (pvp_battle_id, organization_id, score)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE score = score + ?
    ]], { pvpBattleId, orgId, scoreDelta, scoreDelta })

    if ok then
        Debug("db.updatePvpScore", "Updated PvP score:", pvpBattleId, orgId, scoreDelta)
        return true
    end
    return false
end

-- ──────────────────────────────────────────────────────────
-- db.updatePvpBattleStatus(pvpBattleId, status)
-- ──────────────────────────────────────────────────────────
function db.updatePvpBattleStatus(pvpBattleId, status)
    if not pvpBattleId or not status then
        Error("db.updatePvpBattleStatus", "pvpBattleId and status must be provided")
        return false
    end

    -- No-op if already at target status
    local battle = db.getPvpBattle(pvpBattleId)
    if battle and battle.status == status then return true end

    local ok = MySQL.update.await([[
        UPDATE qs_crime_pvp_battles SET status = ? WHERE id = ?
    ]], { status, pvpBattleId })

    if ok then
        Debug("db.updatePvpBattleStatus", "Updated PvP battle status:", pvpBattleId, status)
        if RecordManager and RecordManager.clearCache then
            RecordManager:clearCache("pvp")
        end
        return true
    end
    return false
end

-- ──────────────────────────────────────────────────────────
-- db.getActiveTerritoryWar(territoryId)
--   Used by taxing system — finds an active PvP battle whose
--   zone contains the given territory (by ID match).
--   Simple implementation: returns first active battle found
--   in the RecordManager pvp records whose territory_id matches.
-- ──────────────────────────────────────────────────────────
function db.getActiveTerritoryWar(territoryId)
    if not territoryId then return nil end

    -- Look in active battles for one tied to this territory
    local rows = MySQL.query.await([[
        SELECT * FROM qs_crime_pvp_battles
        WHERE status = 'active' AND territory_id = ?
        ORDER BY start_date ASC LIMIT 1
    ]], { territoryId })

    if rows and #rows > 0 then
        return decodeBattleRow(rows[1])
    end
    return nil
end

-- ──────────────────────────────────────────────────────────
-- db.resetPvpParticipants(pvpBattleId)
-- ──────────────────────────────────────────────────────────
function db.resetPvpParticipants(pvpBattleId)
    if not pvpBattleId then
        Error("db.resetPvpParticipants", "pvpBattleId must be provided")
        return false
    end

    local ok = MySQL.update.await([[
        UPDATE qs_crime_pvp_participants
        SET status = 'invited', accepted_by = NULL, accepted_at = NULL
        WHERE pvp_battle_id = ? AND status = 'accepted'
    ]], { pvpBattleId })

    if ok then
        Debug("db.resetPvpParticipants", "Reset participants for battle:", pvpBattleId)
        return true
    end
    return false
end

-- ──────────────────────────────────────────────────────────
-- db.deletePvpScores(pvpBattleId)
-- ──────────────────────────────────────────────────────────
function db.deletePvpScores(pvpBattleId)
    if not pvpBattleId then
        Error("db.deletePvpScores", "pvpBattleId must be provided")
        return false
    end

    local ok = MySQL.update.await([[
        DELETE FROM qs_crime_pvp_scores WHERE pvp_battle_id = ?
    ]], { pvpBattleId })

    if ok then
        Debug("db.deletePvpScores", "Deleted scores for battle:", pvpBattleId)
        return true
    end
    return false
end
