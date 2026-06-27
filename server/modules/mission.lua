-- ============================================================
-- server/modules/mission.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Mission system server callbacks: listing, taking, progress
-- updates, reward claiming, cancellation, and XP management.
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- local giveReward(playerId, reward)
--   Dispatches a reward to a player.
--   reward: { type, value, moneyType?, item? }
-- ──────────────────────────────────────────────────────────
local function giveReward(playerId, reward)
    if not (reward and reward.type) then
        Error("giveReward", "Invalid reward data")
        return false
    end

    if reward.type == "money" then
        local moneyType = reward.moneyType or "money"
        local value     = reward.value     or 0
        if value > 0 then
            sfr:addAccountMoney(playerId, moneyType, value)
            return true
        end

    elseif reward.type == "xp" then
        return true   -- XP is handled separately via addOrganizationXP

    elseif reward.type == "item" then
        local item  = reward.item
        local value = reward.value or 1
        if item and value > 0 then
            return sfr:addItem(playerId, item, value) or false
        end

    elseif reward.type == "vehicle" then
        return true   -- Vehicle delivery is handled client-side
    end

    return false
end

-- ──────────────────────────────────────────────────────────
-- local addOrganizationXP(orgId, xp)
--   Awards XP to an organization and recalculates its level.
-- ──────────────────────────────────────────────────────────
local function addOrganizationXP(orgId, xp)
    if not (orgId and xp and xp > 0) then return false end

    local stats = db.getOrganizationStats(orgId)
    if not stats then
        db.createOrUpdateOrganizationStats(orgId, {
            level = 1, xp = xp, total_missions = 0, total_territory_wars_won = 0,
        })
        return true
    end

    local newXp    = stats.xp + xp
    local newLevel = stats.level or 1
    local xpToNext = Config.MissionSystem.XPFormula.LevelUpXP(newLevel)

    while newXp >= xpToNext do
        newLevel = newLevel + 1
        xpToNext = Config.MissionSystem.XPFormula.LevelUpXP(newLevel)
    end

    db.createOrUpdateOrganizationStats(orgId, {
        level                   = newLevel,
        xp                      = newXp,
        total_missions          = stats.total_missions          or 0,
        total_territory_wars_won = stats.total_territory_wars_won or 0,
    })
    return true
end

-- Export for use by other modules (e.g. moneylaundering)
exports("addOrganizationXP", addOrganizationXP)

-- ──────────────────────────────────────────────────────────
-- local canTakeMission(orgId, missionId)
--   Validates preconditions for starting a mission.
--   Returns (ok, errorCode).
-- ──────────────────────────────────────────────────────────
local function canTakeMission(orgId, missionId)
    local missionConfig = Config.GetMission(missionId)
    if not (missionConfig and missionConfig.active) then
        return false, "mission_not_found"
    end

    local existingMission = db.getActiveOrPendingMission(orgId, missionId)
    if existingMission then
        if existingMission.status == "active" then
            return false, "mission_already_active"
        elseif existingMission.status == "completed" then
            if existingMission.pending_rewards and #existingMission.pending_rewards > 0 then
                return false, "mission_rewards_unclaimed"
            end
        end
    end

    local today         = os.date("%Y-%m-%d")
    local completedToday = db.getMissionHistoryCount(orgId, missionId, today)
    local dailyLimit    = missionConfig.daily_limit or 999
    if completedToday >= dailyLimit then
        return false, "daily_limit_reached"
    end

    local activeMissions = db.getOrganizationMissions(orgId)
    if #activeMissions >= Config.MissionSystem.DailyMissionLimit then
        return false, "max_active_missions_reached"
    end

    return true
end

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getMissions"
--   Returns all available missions not already active/pending.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getMissions", function(playerId, orgId)
    if not orgId then return {} end

    local allMissions      = Config.GetMissions(true)
    local activeMissions   = db.getOrganizationMissions(orgId)
    local completedWithRew = db.getCompletedMissionsWithRewards(orgId)

    -- Build a lookup of missions already in progress or awaiting claim
    local inProgress = {}
    for _, m in ipairs(activeMissions) do
        inProgress[m.mission_id] = true
    end
    for _, m in ipairs(completedWithRew) do
        inProgress[m.mission_id] = true
    end

    local today     = os.date("%Y-%m-%d")
    local available = {}

    for _, mission in ipairs(allMissions) do
        if not inProgress[mission.id] then
            local completedToday = db.getMissionHistoryCount(orgId, mission.id, today)
            local dailyLimit     = mission.daily_limit or 999
            if completedToday < dailyLimit then
                available[#available + 1] = mission
            end
        end
    end

    return available
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getOrganizationMissions"
--   Returns active/pending missions enriched with config data.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getOrganizationMissions", function(playerId, orgId)
    if not orgId then return {} end

    local rows  = db.getOrganizationMissions(orgId)
    local result = {}

    for _, row in ipairs(rows) do
        local missionConfig = Config.GetMission(row.mission_id)
        if missionConfig then
            result[#result + 1] = {
                id           = row.id,
                mission_id   = row.mission_id,
                progress     = row.progress,
                target_value = row.target_value,
                status       = row.status,
                completed_at = row.completed_at,
                mission      = missionConfig,
            }
        end
    end

    return result
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:takeMission"
--   Creates a new mission assignment for the org.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:takeMission", function(playerId, orgId, missionId)
    if not orgId or not missionId then return false, "invalid_params" end

    local ok, errorCode = canTakeMission(orgId, missionId)
    if not ok then return false, (errorCode or "cannot_take_mission") end

    local missionConfig = Config.GetMission(missionId)
    if not (missionConfig and missionConfig.active) then
        return false, "mission_not_found"
    end

    local newOrgMissionId = db.createOrganizationMission(orgId, missionId,
        missionConfig.target_value)
    if not newOrgMissionId then return false, "failed_to_create_mission" end

    TriggerClientEvent("crime:mission:start", playerId, missionId, newOrgMissionId)
    return true, nil
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:updateMissionProgress"
--   Updates progress on a mission, and handles completion:
--   awards XP, sets pending rewards, increments total_missions.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:updateMissionProgress",
    function(playerId, orgId, orgMissionId, progress, isComplete)
    if not (orgId and orgMissionId) or progress == nil then return false end

    local missionRow = MySQL.single.await([[
        SELECT * FROM qs_crime_organization_missions
        WHERE id = ? AND organization_id = ?
    ]], { orgMissionId, orgId })

    if not (missionRow and missionRow.status == "active") then return false end

    local clampedProgress = math.max(0, progress)
    local completed       = (isComplete == true)

    db.updateOrganizationMissionProgress(orgMissionId, clampedProgress, completed)

    if completed then
        local missionConfig = Config.GetMission(missionRow.mission_id)
        if missionConfig and missionConfig.rewards then
            local pendingRewards = {}

            -- Get online org members
            local org            = RecordManager:get("organizations", orgId)
            local members        = (org and org.members) or {}
            local onlinePlayerIds = {}

            for _, member in ipairs(members) do
                local src = sfr:getSourceFromIdentifier(member.identifier)
                if src then onlinePlayerIds[#onlinePlayerIds + 1] = src end
            end

            -- Process rewards
            for _, reward in ipairs(missionConfig.rewards) do
                if reward.type == "xp" then
                    -- Calculate XP with rarity multipliers
                    local xpBase = reward.value or Config.MissionSystem.XPFormula.BaseXPPerMission
                    local rarity = missionConfig.rare

                    if     rarity == "rare"      then xpBase = xpBase * 1.5
                    elseif rarity == "epic"      then xpBase = xpBase * 2.0
                    elseif rarity == "legendary" then xpBase = xpBase * 3.0 end

                    if missionConfig.type == "territory_war" then
                        local mult = Config.MissionSystem.XPFormula.TerritoryWarMultiplier / 100
                        xpBase = xpBase * mult
                    end

                    local finalXP = math.floor(xpBase)
                    addOrganizationXP(orgId, finalXP)

                    -- Award XP to each online member
                    for _, src in ipairs(onlinePlayerIds) do
                        local memberIdentifier = sfr:getIdentifier(src)
                        db.updateOrganizationMemberStats(orgId, memberIdentifier, finalXP, 1, 0)
                    end
                else
                    pendingRewards[#pendingRewards + 1] = reward
                end
            end

            -- Store non-XP rewards for later claiming
            if #pendingRewards > 0 then
                db.setPendingRewards(orgMissionId, pendingRewards)
            end

            -- Increment total_missions counter
            local stats = db.getOrganizationStats(orgId)
            if stats then
                db.createOrUpdateOrganizationStats(orgId, {
                    level                   = stats.level,
                    xp                      = stats.xp,
                    total_missions          = (stats.total_missions or 0) + 1,
                    total_territory_wars_won = stats.total_territory_wars_won or 0,
                })
            end

            -- Clear member-level mission counter caches
            for _, src in ipairs(onlinePlayerIds) do
                local memberIdentifier = sfr:getIdentifier(src)
                db.updateOrganizationMemberStats(orgId, memberIdentifier, 0, 0, 0)
            end
        end
    end

    return true
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:claimMissionRewards"
--   Delivers pending rewards to the player and closes the mission.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:claimMissionRewards", function(playerId, orgMissionId)
    if not orgMissionId then return false, "invalid_params" end

    local missionRow = MySQL.single.await([[
        SELECT * FROM qs_crime_organization_missions WHERE id = ?
    ]], { orgMissionId })

    if not missionRow then return false, "mission_not_found" end
    if missionRow.status == "active"   then return false, "mission_still_active" end
    if missionRow.status ~= "completed" then return false, "mission_not_completed" end
    if not missionRow.pending_rewards or missionRow.pending_rewards == "" then
        return false, "no_rewards"
    end

    local rewards = json.decode(missionRow.pending_rewards) or {}
    if #rewards == 0 then return false, "no_rewards" end

    local orgId     = missionRow.organization_id
    local identifier = sfr:getIdentifier(playerId)

    -- Verify membership
    local org = RecordManager:get("organizations", orgId)
    if not org then return false, "organization_not_found" end

    local isMember = false
    for _, m in ipairs(org.members or {}) do
        if m.identifier == identifier then isMember = true break end
    end
    if not isMember then return false, "not_member" end

    -- Give all rewards
    for _, reward in ipairs(rewards) do
        giveReward(playerId, reward)
    end

    -- Archive the mission
    db.addMissionHistory(orgId, missionRow.mission_id, identifier)
    db.deleteOrganizationMission(orgMissionId)

    return true, nil
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:cancelMission"
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:cancelMission", function(playerId, orgId, orgMissionId)
    if not orgId or not orgMissionId then return false, "invalid_params" end

    local missionRow = MySQL.single.await([[
        SELECT * FROM qs_crime_organization_missions
        WHERE id = ? AND organization_id = ?
    ]], { orgMissionId, orgId })

    if not missionRow then return false, "mission_not_found" end
    if missionRow.status ~= "active" then return false, "mission_not_active" end

    -- Verify membership
    local playerIdentifier = sfr:getIdentifier(playerId)
    local org = RecordManager:get("organizations", orgId)
    if not org then return false, "organization_not_found" end

    local isMember = false
    for _, m in ipairs(org.members or {}) do
        if m.identifier == playerIdentifier then isMember = true break end
    end
    if not isMember then return false, "not_member" end

    local ok = db.deleteOrganizationMission(orgMissionId)
    if ok then
        TriggerClientEvent("crime:mission:cancelled", playerId,
            missionRow.mission_id, orgMissionId)
        return true, nil
    end

    return false, "failed_to_cancel"
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getCompletedMissionsWithRewards"
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getCompletedMissionsWithRewards", function(_, orgId)
    if not orgId then return {} end

    local rows   = db.getCompletedMissionsWithRewards(orgId)
    local result = {}

    for _, row in ipairs(rows) do
        local missionConfig = Config.GetMission(row.mission_id)
        if missionConfig then
            result[#result + 1] = {
                id              = row.id,
                mission_id      = row.mission_id,
                progress        = row.progress,
                target_value    = row.target_value,
                status          = row.status,
                completed_at    = row.completed_at,
                pending_rewards = row.pending_rewards,
                mission         = missionConfig,
            }
        end
    end

    return result
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getOrganizationMemberStats"
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getOrganizationMemberStats", function(_, orgId)
    if not orgId then return {} end
    return db.getOrganizationMemberStatsList(orgId)
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getOrganizationStats"
--   Returns org stats, creating the row if absent.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getOrganizationStats", function(_, orgId)
    if not orgId then return nil end

    local stats = db.getOrganizationStats(orgId)
    if not stats then
        db.createOrUpdateOrganizationStats(orgId, {
            level = 1, xp = 0, total_missions = 0, total_territory_wars_won = 0,
        })
        stats = db.getOrganizationStats(orgId)
    end
    return stats
end)
