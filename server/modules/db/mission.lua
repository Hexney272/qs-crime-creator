-- ============================================================
-- server/modules/db/mission.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Mission & member-stats DB queries.
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- local helper: normalise a mission row's numeric fields and
-- decode pending_rewards JSON.
-- ──────────────────────────────────────────────────────────
local function normaliseMissionRow(row)
    row.progress     = tonumber(row.progress)     or 0
    row.target_value = tonumber(row.target_value) or 1

    if row.pending_rewards then
        row.pending_rewards = json.decode(row.pending_rewards) or {}
    else
        row.pending_rewards = {}
    end
    return row
end

-- ──────────────────────────────────────────────────────────
-- db.getOrganizationMission(orgId, missionId)
-- ──────────────────────────────────────────────────────────
function db.getOrganizationMission(orgId, missionId)
    if not orgId or not missionId then
        Error("db.getOrganizationMission", "orgId and missionId must be provided")
        return nil
    end

    local cacheKey = orgId .. "_" .. missionId
    local cached   = db:getCache("organization_mission", cacheKey)
    if cached then return cached end

    local row = MySQL.single.await([[
        SELECT * FROM qs_crime_organization_missions
        WHERE organization_id = ? AND mission_id = ?
        ORDER BY created_at DESC LIMIT 1
    ]], { orgId, missionId })

    if row then
        normaliseMissionRow(row)
        db:saveCache("organization_mission", row, cacheKey)
    end

    return row
end

-- ──────────────────────────────────────────────────────────
-- db.getOrganizationMissions(orgId)
--   Returns all active missions for an org.
-- ──────────────────────────────────────────────────────────
function db.getOrganizationMissions(orgId)
    if not orgId then
        Error("db.getOrganizationMissions", "orgId must be provided")
        return {}
    end

    local cached = db:getCache("organization_missions", orgId)
    if cached then return cached end

    local rows = MySQL.query.await([[
        SELECT * FROM qs_crime_organization_missions
        WHERE organization_id = ? AND status = 'active'
        ORDER BY created_at DESC
    ]], { orgId }) or {}

    for _, row in ipairs(rows) do normaliseMissionRow(row) end

    db:saveCache("organization_missions", rows, orgId)
    return rows
end

-- ──────────────────────────────────────────────────────────
-- db.createOrganizationMission(orgId, missionId, targetValue)
-- ──────────────────────────────────────────────────────────
function db.createOrganizationMission(orgId, missionId, targetValue)
    if not (orgId and missionId) or not targetValue then
        Error("db.createOrganizationMission",
              "orgId, missionId and targetValue must be provided")
        return nil
    end

    local newId = MySQL.insert.await([[
        INSERT INTO qs_crime_organization_missions (
            organization_id, mission_id, target_value, status
        ) VALUES (?, ?, ?, 'active')
    ]], { orgId, missionId, targetValue })

    if newId then
        db:clearCache("organization_missions",          orgId)
        db:clearCache("organization_mission",           orgId .. "_" .. missionId)
        Debug("db.createOrganizationMission", "Created organization mission:", newId)
        return newId
    end

    Error("db.createOrganizationMission", "Failed to create organization mission")
    return nil
end

-- ──────────────────────────────────────────────────────────
-- db.updateOrganizationMissionProgress(orgMissionId, progress, isComplete)
-- ──────────────────────────────────────────────────────────
function db.updateOrganizationMissionProgress(orgMissionId, progress, isComplete)
    if not orgMissionId or progress == nil then
        Error("db.updateOrganizationMissionProgress",
              "orgMissionId and progress must be provided")
        return false
    end

    local setClauses = { "progress = ?" }
    local params     = { progress }

    if isComplete then
        setClauses[#setClauses + 1] = "status = ?"
        setClauses[#setClauses + 1] = "completed_at = NOW()"
        params[#params + 1]         = "completed"
    end

    params[#params + 1] = orgMissionId

    local ok = MySQL.update.await(
        "UPDATE qs_crime_organization_missions SET "
        .. table.concat(setClauses, ", ")
        .. " WHERE id = ?",
        params
    )

    if ok then
        -- Look up org/mission for cache invalidation
        local ref = MySQL.single.await([[
            SELECT organization_id, mission_id FROM qs_crime_organization_missions WHERE id = ?
        ]], { orgMissionId })

        if ref then
            db:clearCache("organization_missions", ref.organization_id)
            db:clearCache("organization_mission",
                ref.organization_id .. "_" .. ref.mission_id)
            if isComplete then
                db:clearCache("completed_missions", ref.organization_id)
            end
        end
    end

    return ok ~= nil
end

-- ──────────────────────────────────────────────────────────
-- db.addMissionHistory(orgId, missionId, identifier)
-- ──────────────────────────────────────────────────────────
function db.addMissionHistory(orgId, missionId, identifier)
    if not (orgId and missionId) or not identifier then
        Error("db.addMissionHistory",
              "orgId, missionId and identifier must be provided")
        return false
    end

    local newId = MySQL.insert.await([[
        INSERT INTO qs_crime_mission_history (
            organization_id, mission_id, identifier, completed_at
        ) VALUES (?, ?, ?, NOW())
    ]], { orgId, missionId, identifier })

    if newId then
        db:clearCache("mission_history", orgId .. "_" .. missionId)
    end

    return newId ~= nil
end

-- ──────────────────────────────────────────────────────────
-- db.getMissionHistoryCount(orgId, missionId, date)
--   Returns how many times the org completed this mission today.
-- ──────────────────────────────────────────────────────────
function db.getMissionHistoryCount(orgId, missionId, date)
    if not (orgId and missionId) or not date then
        Error("db.getMissionHistoryCount",
              "orgId, missionId and date must be provided")
        return 0
    end

    local row = MySQL.single.await([[
        SELECT COUNT(*) as count FROM qs_crime_mission_history
        WHERE organization_id = ? AND mission_id = ? AND DATE(completed_at) = ?
    ]], { orgId, missionId, date })

    return (row and tonumber(row.count)) or 0
end

-- ──────────────────────────────────────────────────────────
-- db.deleteOrganizationMission(orgMissionId)
-- ──────────────────────────────────────────────────────────
function db.deleteOrganizationMission(orgMissionId)
    if not orgMissionId then
        Error("db.deleteOrganizationMission", "orgMissionId must be provided")
        return false
    end

    local ref = MySQL.single.await([[
        SELECT organization_id, mission_id FROM qs_crime_organization_missions WHERE id = ?
    ]], { orgMissionId })

    local ok = MySQL.update.await([[
        DELETE FROM qs_crime_organization_missions WHERE id = ?
    ]], { orgMissionId })

    if ok and ref then
        db:clearCache("organization_missions", ref.organization_id)
        db:clearCache("organization_mission",
            ref.organization_id .. "_" .. ref.mission_id)
        db:clearCache("completed_missions", ref.organization_id)
    end

    return ok ~= nil
end

-- ──────────────────────────────────────────────────────────
-- db.getActiveOrPendingMission(orgId, missionId)
--   Returns the most recent active or reward-pending row.
-- ──────────────────────────────────────────────────────────
function db.getActiveOrPendingMission(orgId, missionId)
    if not orgId or not missionId then return nil end

    local row = MySQL.single.await([[
        SELECT * FROM qs_crime_organization_missions
        WHERE organization_id = ? AND mission_id = ?
        AND (status = 'active'
             OR (status = 'completed'
                 AND pending_rewards IS NOT NULL
                 AND pending_rewards != ''))
        ORDER BY created_at DESC LIMIT 1
    ]], { orgId, missionId })

    if row then normaliseMissionRow(row) end
    return row
end

-- ──────────────────────────────────────────────────────────
-- db.getCompletedMissionsWithRewards(orgId)
-- ──────────────────────────────────────────────────────────
function db.getCompletedMissionsWithRewards(orgId)
    if not orgId then
        Error("db.getCompletedMissionsWithRewards", "orgId must be provided")
        return {}
    end

    local cached = db:getCache("completed_missions", orgId)
    if cached then return cached end

    local rows = MySQL.query.await([[
        SELECT * FROM qs_crime_organization_missions
        WHERE organization_id = ? AND status = 'completed'
        AND pending_rewards IS NOT NULL AND pending_rewards != ''
        ORDER BY completed_at DESC
    ]], { orgId }) or {}

    for _, row in ipairs(rows) do normaliseMissionRow(row) end

    db:saveCache("completed_missions", rows, orgId)
    return rows
end

-- ──────────────────────────────────────────────────────────
-- db.setPendingRewards(orgMissionId, rewards)
-- ──────────────────────────────────────────────────────────
function db.setPendingRewards(orgMissionId, rewards)
    if not orgMissionId then
        Error("db.setPendingRewards", "orgMissionId must be provided")
        return false
    end

    local rewardsJson = json.encode(rewards or {})

    local ok = MySQL.update.await([[
        UPDATE qs_crime_organization_missions SET
            pending_rewards = ?
        WHERE id = ?
    ]], { rewardsJson, orgMissionId })

    if ok then
        local ref = MySQL.single.await([[
            SELECT organization_id, mission_id FROM qs_crime_organization_missions WHERE id = ?
        ]], { orgMissionId })

        if ref then
            db:clearCache("organization_missions", ref.organization_id)
            db:clearCache("organization_mission",
                ref.organization_id .. "_" .. ref.mission_id)
            db:clearCache("completed_missions", ref.organization_id)
        end
    end

    return ok ~= nil
end

-- ──────────────────────────────────────────────────────────
-- db.getOrganizationMemberStats(orgId, identifier)
-- ──────────────────────────────────────────────────────────
function db.getOrganizationMemberStats(orgId, identifier)
    if not orgId or not identifier then
        Error("db.getOrganizationMemberStats",
              "orgId and identifier must be provided")
        return nil
    end

    local row = MySQL.single.await([[
        SELECT * FROM qs_crime_organization_member_stats
        WHERE organization_id = ? AND identifier = ?
    ]], { orgId, identifier })

    if row then
        row.total_xp_earned                    = tonumber(row.total_xp_earned)                    or 0
        row.total_missions_completed           = tonumber(row.total_missions_completed)           or 0
        row.total_territory_wars_participated  = tonumber(row.total_territory_wars_participated)  or 0
    end

    return row
end

-- ──────────────────────────────────────────────────────────
-- db.getOrganizationMemberStatsList(orgId)
--   Returns all members' stats joined with member info and rank.
-- ──────────────────────────────────────────────────────────
function db.getOrganizationMemberStatsList(orgId)
    if not orgId then
        Error("db.getOrganizationMemberStatsList", "orgId must be provided")
        return {}
    end

    local cached = db:getCache("member_stats", orgId)
    if cached then return cached end

    local rows = MySQL.query.await([[
        SELECT
            stats.*,
            members.id   as member_id,
            members.name as member_name,
            members.rank_id,
            members.is_boss
        FROM qs_crime_organization_member_stats stats
        LEFT JOIN qs_crime_organization_members members
            ON stats.organization_id = members.organization_id
            AND stats.identifier = members.identifier
        WHERE stats.organization_id = ?
        ORDER BY stats.total_xp_earned DESC, stats.total_missions_completed DESC
    ]], { orgId }) or {}

    local org = RecordManager:get("organizations", orgId)

    for _, row in ipairs(rows) do
        row.total_xp_earned                   = tonumber(row.total_xp_earned)                   or 0
        row.total_missions_completed          = tonumber(row.total_missions_completed)          or 0
        row.total_territory_wars_participated = tonumber(row.total_territory_wars_participated) or 0

        if row.member_name then
            row.member = {
                id         = row.member_id,
                identifier = row.identifier,
                name       = row.member_name,
                rank_id    = row.rank_id,
                is_boss    = (row.is_boss == 1),
            }

            -- Attach rank data from org config
            if org and org.ranks and row.rank_id then
                for _, rank in ipairs(org.ranks) do
                    if rank.id == row.rank_id then
                        row.member.rank = rank
                        break
                    end
                end
            end
        end
    end

    db:saveCache("member_stats", rows, orgId)
    return rows
end

-- ──────────────────────────────────────────────────────────
-- db.updateOrganizationMemberStats(orgId, identifier, xp, missions, wars)
--   Upserts the stats row using INSERT … ON DUPLICATE KEY UPDATE.
-- ──────────────────────────────────────────────────────────
function db.updateOrganizationMemberStats(orgId, identifier, xp, missions, wars)
    if not (orgId and identifier) or xp == nil then
        Error("db.updateOrganizationMemberStats",
              "orgId, identifier and xp must be provided")
        return false
    end

    local xpVal      = xp       or 0
    local missVal    = missions  or 0
    local warsVal    = wars      or 0

    local ok = MySQL.update.await([[
        INSERT INTO qs_crime_organization_member_stats (
            organization_id, identifier,
            total_xp_earned, total_missions_completed, total_territory_wars_participated
        ) VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            total_xp_earned                   = total_xp_earned + ?,
            total_missions_completed          = total_missions_completed + ?,
            total_territory_wars_participated = total_territory_wars_participated + ?
    ]], {
        orgId, identifier,
        xpVal, missVal, warsVal,
        xpVal, missVal, warsVal,
    })

    if ok then
        db:clearCache("member_stats",    orgId)
        db:clearCache("member_details",  orgId .. "_" .. identifier)
    end

    return ok ~= nil
end

-- ──────────────────────────────────────────────────────────
-- db.getMemberDetails(orgId, identifier)
--   Returns a rich detail object:
--   { member, stats, money_laundering, transactions, active_missions }
-- ──────────────────────────────────────────────────────────
function db.getMemberDetails(orgId, identifier)
    if not orgId or not identifier then
        Error("db.getMemberDetails", "orgId and identifier must be provided")
        return nil
    end

    local cacheKey = orgId .. "_" .. identifier
    local cached   = db:getCache("member_details", cacheKey)
    if cached then return cached end

    -- Base member row with lifetime aggregates
    local memberRow = MySQL.single.await([[
        SELECT
            m.*,
            COALESCE(ms.total_xp_earned, 0)                   as total_xp_earned,
            COALESCE(ms.total_missions_completed, 0)           as total_missions_completed,
            COALESCE(ms.total_territory_wars_participated, 0)  as total_territory_wars_participated,
            COALESCE(SUM(ml.total_laundered), 0)               as total_money_laundered
        FROM qs_crime_organization_members m
        LEFT JOIN qs_crime_organization_member_stats ms
            ON m.organization_id = ms.organization_id
            AND m.identifier = ms.identifier
        LEFT JOIN qs_crime_money_laundering_daily ml
            ON m.organization_id = ml.organization_id
            AND m.identifier = ml.identifier
        WHERE m.organization_id = ? AND m.identifier = ?
        GROUP BY m.id
    ]], { orgId, identifier })

    if not memberRow then return nil end

    -- Recent transactions
    local transactions = MySQL.query.await([[
        SELECT * FROM qs_crime_organization_transactions
        WHERE organization_id = ? AND identifier = ?
        ORDER BY created_at DESC LIMIT 50
    ]], { orgId, identifier }) or {}

    for _, tx in ipairs(transactions) do
        tx.metadata = (tx.metadata and json.decode(tx.metadata)) or {}
        tx.amount   = tonumber(tx.amount) or 0
    end

    -- Active missions
    local activeMissions = MySQL.query.await([[
        SELECT * FROM qs_crime_organization_missions
        WHERE organization_id = ? AND status = 'active'
        ORDER BY created_at DESC
    ]], { orgId }) or {}

    for _, m in ipairs(activeMissions) do
        m.progress        = tonumber(m.progress)     or 0
        m.target_value    = tonumber(m.target_value) or 0
        m.pending_rewards = (m.pending_rewards and json.decode(m.pending_rewards)) or {}
    end

    -- Today's money-laundering stats
    local today      = os.date("%Y-%m-%d")
    local mlDaily    = MySQL.single.await([[
        SELECT * FROM qs_crime_money_laundering_daily
        WHERE organization_id = ? AND identifier = ? AND last_reset_date = ?
    ]], { orgId, identifier, today })

    -- Assemble result
    local result = {
        member = {
            id              = memberRow.id,
            organization_id = memberRow.organization_id,
            identifier      = memberRow.identifier,
            name            = memberRow.name,
            rank_id         = memberRow.rank_id,
            is_boss         = (memberRow.is_boss == 1),
            joined_at       = memberRow.joined_at,
            updated_at      = memberRow.updated_at,
        },
        stats = {
            total_xp_earned                   = tonumber(memberRow.total_xp_earned)                   or 0,
            total_missions_completed          = tonumber(memberRow.total_missions_completed)          or 0,
            total_territory_wars_participated = tonumber(memberRow.total_territory_wars_participated) or 0,
        },
        money_laundering = {
            total_laundered = tonumber(memberRow.total_money_laundered) or 0,
            daily_stats     = mlDaily and {
                completed_count = tonumber(mlDaily.completed_count) or 0,
                total_laundered = tonumber(mlDaily.total_laundered) or 0,
                last_reset_date = mlDaily.last_reset_date,
            } or nil,
        },
        transactions   = transactions,
        active_missions = activeMissions,
    }

    -- Attach rank from org config
    local org = RecordManager:get("organizations", orgId)
    if org and org.ranks and memberRow.rank_id then
        for _, rank in ipairs(org.ranks) do
            if rank.id == memberRow.rank_id then
                result.member.rank = rank
                break
            end
        end
    end

    db:saveCache("member_details", result, cacheKey)
    return result
end
