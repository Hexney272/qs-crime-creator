-- ============================================================
-- server/modules/pvp/pvp.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Active PvP battle management: GivePvpReward, start/finish/
-- destroy helpers, background poll thread, and all net events
-- and callbacks for the PvP zone system.
-- ============================================================

-- ActivePvpBattles[battleId] = PvpBattle instance
local ActivePvpBattles = {}

-- ──────────────────────────────────────────────────────────
-- local toUnixSec(val)
--   Converts a start_date value to a Unix timestamp (seconds).
--   Handles both integer millisecond timestamps and MySQL
--   datetime strings ("YYYY-MM-DD HH:MM:SS").
-- ──────────────────────────────────────────────────────────
local function toUnixSec(val)
    if type(val) == "string" then
        local y, mo, d, h, m, s = val:match("(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
        if y then
            return os.time({
                year  = tonumber(y),
                month = tonumber(mo),
                day   = tonumber(d),
                hour  = tonumber(h) or 0,
                min   = tonumber(m) or 0,
                sec   = tonumber(s) or 0,
            })
        end
        return tonumber(val) or 0
    end
    return math.floor((tonumber(val) or 0) / 1000)
end

-- ──────────────────────────────────────────────────────────
-- GivePvpReward(orgId, reward)
--   Dispatches a single reward to an organisation.
--   reward: { type, value?, moneyType?, vehicleModel?,
--             label?, itemName?, itemAmount?, id? }
-- ──────────────────────────────────────────────────────────
function GivePvpReward(orgId, reward)
    if not (reward and reward.type) then
        Error("givePvpReward", "Invalid reward data")
        return false
    end

    local org = RecordManager:get("organizations", orgId)
    if not org then
        Error("givePvpReward", "Organization not found:", orgId)
        return false
    end

    -- Build list of online member player ids
    local onlinePlayers = {}
    for _, member in ipairs(org.members or {}) do
        local src = sfr:getSourceFromIdentifier(member.identifier)
        if src then onlinePlayers[#onlinePlayers + 1] = src end
    end

    if reward.type == "xp" then
        local xp = reward.value or 0
        if xp > 0 then
            local stats = db.getOrganizationStats(orgId)
            if stats then
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
                for _, src in ipairs(onlinePlayers) do
                    local ident = sfr:getIdentifier(src)
                    db.updateOrganizationMemberStats(orgId, ident, xp, 0, 0)
                end
            end
            return true
        end

    elseif reward.type == "money" then
        local moneyType = reward.moneyType or "money"
        local value     = reward.value     or 0
        if value > 0 then
            local ok = OrganizationFinanceDB:updateMoney(orgId, value, "deposit", "clean")
            if ok then
                OrganizationFinanceDB:createTransaction(orgId, {
                    type        = "deposit",
                    amount      = value,
                    money_type  = moneyType,
                    description = "PvP Battle Reward",
                    identifier  = "system",
                    name        = "PvP Battle Reward",
                    status      = "completed",
                })
                return true
            end
        end

    elseif reward.type == "vehicle" then
        local model = reward.vehicleModel
        if model then
            local label = reward.label or model
            local plate = string.upper(string.sub(model, 1, 3) .. math.random(1000, 9999))
            local meta  = { source = "pvp_battle", reward_id = reward.id }
            local newId = db.addOrganizationVehicle(orgId, model, label, plate, nil, meta)
            return newId ~= nil
        end

    elseif reward.type == "item" then
        local itemName   = reward.itemName
        local itemAmount = reward.itemAmount or 1
        if itemName and itemAmount > 0 then
            if #onlinePlayers > 0 then
                local ok = sfr:addItem(onlinePlayers[1], itemName, itemAmount)
                return ok or false
            end
        end
    end

    return false
end

-- ──────────────────────────────────────────────────────────
-- finishPvpBattle(battleId, _unused)
--   Ends a battle: determines winner, gives rewards, notifies
--   all participants, marks status as "finished".
-- ──────────────────────────────────────────────────────────
local function finishPvpBattle(battleId, _)
    local battle = db.getPvpBattle(battleId)
    if not battle then return end

    if battle.status == "finished" then
        Debug("finishPvpBattle", "Battle already finished, skipping:", battleId)
        return
    end

    -- If we have an in-memory PvpBattle instance, use it to finish
    local instance = ActivePvpBattles[battleId]
    if instance then
        instance:finish()
        ActivePvpBattles[battleId] = nil
        return
    end

    -- Fallback: do it manually from DB scores
    local scores = db.getPvpScores(battleId)
    if not scores or #scores == 0 then
        db.updatePvpBattleStatus(battleId, "finished")
        return
    end

    -- Find the winning org (highest score)
    local winner = scores[1]
    for _, s in ipairs(scores) do
        if s.score > winner.score then winner = s end
    end

    -- Distribute rewards to winner
    if battle.rewards and winner.organization_id then
        for _, reward in ipairs(battle.rewards) do
            GivePvpReward(winner.organization_id, reward)
        end
    end

    db.updatePvpBattleStatus(battleId, "finished")

    -- Notify online members of all accepted participants
    local participants = db.getPvpParticipants(battleId) or {}
    for _, participant in ipairs(participants) do
        if participant.status == "accepted" then
            local org = RecordManager:get("organizations", participant.organization_id)
            if org and org.members then
                for _, member in ipairs(org.members) do
                    local src = sfr:getSourceFromIdentifier(member.identifier)
                    if src then
                        TriggerClientEvent("crime:pvpBattleFinished", src, {
                            pvp_battle_id = battleId,
                            winner_org_id = winner.organization_id,
                            scores        = scores,
                        })
                    end
                end
            end
        end
    end

    -- After 6 s, tell all clients to clean up their local state
    CreateThread(function()
        Wait(6000)
        TriggerClientEvent("crime:pvpBattleDestroyed", -1, battleId)
    end)
end

-- ──────────────────────────────────────────────────────────
-- destroyActivePvpBattle(battleId)
--   Destroys the in-memory PvpBattle instance (without
--   re-finishing it — used when a battle is reset).
-- ──────────────────────────────────────────────────────────
local function destroyActivePvpBattle(battleId)
    local instance = ActivePvpBattles[battleId]
    if instance and instance.isActive then
        instance:destroy()
        ActivePvpBattles[battleId] = nil
        Debug("destroyActivePvpBattle", "Destroyed active PvP battle instance:", battleId)
        return true
    end
    return false
end

RegisterNetEvent("crime:destroyActivePvpBattle", function(battleId)
    destroyActivePvpBattle(battleId)
end)

-- ──────────────────────────────────────────────────────────
-- startPvpBattle(battleId)
--   Creates a PvpBattle instance and marks the battle active.
-- ──────────────────────────────────────────────────────────
local function startPvpBattle(battleId)
    local battleData = db.getPvpBattle(battleId)
    if not battleData then return end

    if ActivePvpBattles[battleId] then
        Debug("startPvpBattle", "Battle instance already exists:", battleId)
        return
    end

    db.updatePvpBattleStatus(battleId, "active")

    local freshBattle = db.getPvpBattle(battleId)
    if freshBattle then
        Debug("startPvpBattle", "Notifying clients about battle activation:", battleId)
        TriggerClientEvent("crime:pvpBattleUpdated", -1, freshBattle)
    end

    ActivePvpBattles[battleId] = PvpBattle:new(battleData)
    Debug("startPvpBattle", "Started PvP battle:", battleId)
end

-- ──────────────────────────────────────────────────────────
-- Background thread — polls RecordManager pvp records every
-- 5 s and starts/finishes battles based on their schedule.
-- ──────────────────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(5000)
        local now     = os.time()
        local battles = RecordManager:getAll("pvp")

        for _, battle in ipairs(battles) do
            -- Convert start_date to Unix seconds (handles ms int and datetime string)
            local startSec  = toUnixSec(battle.start_date)
            local endSec    = startSec + battle.duration
            local sinceStart = os.difftime(startSec, now)
            local sinceEnd   = os.difftime(endSec,   now)

            if battle.status == "pending" then
                -- Start time has arrived
                if sinceStart <= 0 then
                    if not ActivePvpBattles[battle.id] then
                        startPvpBattle(battle.id)
                    end
                end

            elseif battle.status == "active" then
                -- End time has passed
                if sinceEnd <= 0 then
                    finishPvpBattle(battle.id, nil)
                else
                    -- Restore in-memory instance if server restarted mid-battle
                    if not ActivePvpBattles[battle.id] then
                        ActivePvpBattles[battle.id] = PvpBattle:new(battle)
                        Debug("PvP Battle", "Restored active battle to ActivePvpBattles:",
                            battle.id)
                    end
                end

            elseif battle.status == "finished" then
                -- Nothing to do
            end
        end
    end
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getPvpBattles"
--   Returns battles that are pending or active (not finished).
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getPvpBattles", function(_)
    local battles = RecordManager:getAll("pvp") or {}
    local now     = os.time()
    local result  = {}

    for _, battle in ipairs(battles) do
        local startSec = toUnixSec(battle.start_date)
        local endSec   = startSec + battle.duration

        local sinceStart = os.difftime(startSec, now)
        local sinceEnd   = os.difftime(endSec,   now)

        if sinceStart > 0 then
            -- Not started yet — include pending battles
            if battle.status == "pending" then
                result[#result + 1] = battle
            end
        else
            if battle.status == "active" then
                if sinceEnd <= 0 then
                    -- Past end time; finish it inline
                    finishPvpBattle(battle.id, nil)
                else
                    result[#result + 1] = battle
                end
            elseif battle.status == "pending" then
                result[#result + 1] = battle
            elseif battle.status ~= "finished" then
                result[#result + 1] = battle
            end
        end
    end

    return result
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getPvpBattle"
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getPvpBattle", function(_, battleId)
    return db.getPvpBattle(battleId)
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getPvpParticipants"
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getPvpParticipants", function(_, battleId)
    if not battleId then return {} end
    return db.getPvpParticipants(battleId)
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getPvpInvitations"
--   Returns all pending battle invitations for the caller's org.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getPvpInvitations", function(playerId)
    local identifier = sfr:getIdentifier(playerId)
    if not identifier then return {} end

    local orgId = Player(playerId).state.organization
    if not orgId then
        Debug("crime:getPvpInvitations", "No organization found for player", playerId)
        return {}
    end

    local allBattles = RecordManager:getAll("pvp")
    local invitations = {}

    for _, battle in ipairs(allBattles) do
        if battle.status == "pending" then
            local participants = db.getPvpParticipants(battle.id)
            for _, p in ipairs(participants) do
                if p.organization_id == orgId and p.status == "invited" then
                    invitations[#invitations + 1] = {
                        battle      = battle,
                        participant = p,
                    }
                end
            end
        end
    end

    return invitations
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:acceptPvpInvitation"
--   Validates and accepts a battle invitation on behalf of an org.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:acceptPvpInvitation", function(playerId, battleId)
    local identifier = sfr:getIdentifier(playerId)
    if not identifier then return false, "invalid_player" end

    local orgId = Player(playerId).state.organization
    if not orgId then return false, "not_in_organization" end

    local org = RecordManager:get("organizations", orgId)
    if not org then return false, "organization_not_found" end

    -- Check permission: owner, boss, or rank with canAcceptPvp
    local hasPermission = false

    if org.owner and org.owner.identifier == identifier then
        hasPermission = true
    else
        local memberRecord = nil
        for _, m in ipairs(org.members or {}) do
            if m.identifier == identifier then memberRecord = m break end
        end

        if memberRecord then
            if memberRecord.is_boss then
                hasPermission = true
            elseif memberRecord.rank_id and org.ranks then
                for _, rank in ipairs(org.ranks) do
                    if rank.id == memberRecord.rank_id and rank.permissions then
                        if rank.permissions.canAcceptPvp then
                            hasPermission = true
                            break
                        end
                    end
                end
            end
        end
    end

    if not hasPermission then return false, "no_permission" end

    -- Make sure the org isn't already in an active battle
    local activeBattles = db.getActivePvpBattles()
    for _, activeBattle in ipairs(activeBattles) do
        local participants = db.getPvpParticipants(activeBattle.id)
        for _, p in ipairs(participants) do
            if p.organization_id == orgId and p.status == "accepted" then
                return false, "already_in_battle"
            end
        end
    end

    -- Find the participant row for this org
    local participants = db.getPvpParticipants(battleId)
    local participantRow = nil
    for _, p in ipairs(participants) do
        if p.organization_id == orgId then participantRow = p break end
    end

    if not (participantRow and participantRow.status == "invited") then
        return false, "not_invited"
    end

    local ok = db.updatePvpParticipantStatus(battleId, orgId, "accepted", identifier)

    if ok then
        -- Notify all online org members
        for _, member in ipairs(org.members or {}) do
            local src = sfr:getSourceFromIdentifier(member.identifier)
            if src then
                TriggerClientEvent("crime:pvpInvitationAccepted", src, {
                    pvp_battle_id   = battleId,
                    organization_id = orgId,
                })
            end
        end
        RecordManager:clearCache("pvp")
    end

    return ok, nil
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:cancelPvpParticipation"
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:cancelPvpParticipation", function(playerId, battleId)
    local identifier = sfr:getIdentifier(playerId)
    if not identifier then return false end

    local orgId = Player(playerId).state.organization
    if not orgId then return false end

    -- Cannot cancel once battle is active
    local battle = db.getPvpBattle(battleId)
    if battle and battle.status == "active" then return false end

    local ok = db.updatePvpParticipantStatus(battleId, orgId, "cancelled", identifier)
    if ok then RecordManager:clearCache("pvp") end
    return ok
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getPvpScores"
--   Returns live in-memory scores if battle is active,
--   otherwise falls back to DB.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getPvpScores", function(_, battleId)
    local instance = ActivePvpBattles[battleId]
    if instance and instance.isActive then
        return instance:getScores()
    end
    return db.getPvpScores(battleId)
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getOrganizations"
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getOrganizations", function(_)
    return RecordManager:getAll("organizations")
end)

-- ──────────────────────────────────────────────────────────
-- NetEvent: "crime:pvpPlayerEnteredZone"
--   Client fires this when a player enters a PvP battle zone.
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:pvpPlayerEnteredZone", function(battleId, orgId)
    local playerId = source

    if not battleId or not orgId then
        Debug("crime:pvpPlayerEnteredZone", "Missing parameters:", battleId, orgId)
        return
    end

    -- Restore in-memory instance if needed
    local instance = ActivePvpBattles[battleId]
    if not instance then
        local battleData = db.getPvpBattle(battleId)
        if battleData and battleData.status == "active" then
            ActivePvpBattles[battleId] = PvpBattle:new(battleData)
            instance = ActivePvpBattles[battleId]
            Debug("crime:pvpPlayerEnteredZone", "Restored active battle to ActivePvpBattles:",
                battleId)
        else
            Debug("crime:pvpPlayerEnteredZone", "Battle not found or not active:", battleId)
            return
        end
    end

    -- Verify the org is an accepted participant
    local participants = db.getPvpParticipants(battleId)
    local isParticipant = false
    for _, p in ipairs(participants or {}) do
        if p.organization_id == orgId and p.status == "accepted" then
            isParticipant = true
            break
        end
    end

    if not isParticipant then
        Debug("crime:pvpPlayerEnteredZone", "Organization is not a participant:",
            orgId, "battle:", battleId)
        return
    end

    -- Verify the player's state org matches
    local playerOrg = Player(playerId).state.organization
    if playerOrg ~= orgId then
        Debug("crime:pvpPlayerEnteredZone", "Organization mismatch:", playerOrg,
            "expected:", orgId)
        return
    end

    instance:addPlayer(playerId, orgId)
end)

-- ──────────────────────────────────────────────────────────
-- NetEvent: "crime:pvpPlayerExitedZone"
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:pvpPlayerExitedZone", function(battleId, orgId)
    local playerId = source

    if not battleId or not orgId then
        Debug("crime:pvpPlayerExitedZone", "Missing parameters:", battleId, orgId)
        return
    end

    local instance = ActivePvpBattles[battleId]
    if not instance then return end

    instance:removePlayer(playerId)
end)

-- ──────────────────────────────────────────────────────────
-- NetEvent: "crime:pvpPlayerHeartbeat"
--   Client sends this periodically to confirm it's still in zone.
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:pvpPlayerHeartbeat", function(battleId)
    local playerId = source
    if not battleId then return end

    local instance = ActivePvpBattles[battleId]
    if not instance then return end

    if instance.players_in_zone and instance.players_in_zone[playerId] then
        instance.players_in_zone[playerId].last_heartbeat = os.time()
    end
end)

-- ──────────────────────────────────────────────────────────
-- NetEvent: "crime:updatePvpScore"
--   Client submits a score delta for an organisation.
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:updatePvpScore", function(battleId, orgId, scoreDelta)
    local playerId = source

    if not battleId or not orgId then
        Debug("crime:updatePvpScore", "Missing parameters:", battleId, orgId)
        return
    end

    local battle = db.getPvpBattle(battleId)
    if not battle then
        Debug("crime:updatePvpScore", "Battle not found in database:", battleId)
        return
    end
    if battle.status ~= "active" then
        Debug("crime:updatePvpScore", "Battle is not active:", battleId, "status:", battle.status)
        return
    end

    -- Verify org is accepted participant
    local participants   = db.getPvpParticipants(battleId)
    local isParticipant  = false
    for _, p in ipairs(participants or {}) do
        if p.organization_id == orgId and p.status == "accepted" then
            isParticipant = true break
        end
    end
    if not isParticipant then
        Debug("crime:updatePvpScore", "Organization is not a participant:", orgId,
            "battle:", battleId)
        return
    end

    Debug("crime:updatePvpScore", "Updating score:", battleId, orgId, scoreDelta)

    local instance = ActivePvpBattles[battleId]
    if instance and instance.isActive then
        -- Update in-memory cache
        if not instance.scores_cache[orgId] then
            instance.scores_cache[orgId] = 0
        end
        instance.scores_cache[orgId] = instance.scores_cache[orgId] + scoreDelta

        instance:triggerEvent("crime:pvpScoreUpdated", {
            pvp_battle_id   = battleId,
            organization_id = orgId,
            score           = instance.scores_cache[orgId],
        })
    else
        -- No in-memory instance — persist directly to DB
        local ok = db.updatePvpScore(battleId, orgId, scoreDelta)
        if ok then
            local scores   = db.getPvpScores(battleId) or {}
            local newScore = 0
            for _, s in ipairs(scores) do
                if s.organization_id == orgId then newScore = s.score break end
            end

            -- Notify all online members of this org
            for _, p in ipairs(participants) do
                if p.status == "accepted" and p.organization_id == orgId then
                    local org = RecordManager:get("organizations", orgId)
                    if org and org.members then
                        for _, member in ipairs(org.members) do
                            local src = sfr:getSourceFromIdentifier(member.identifier)
                            if src then
                                TriggerClientEvent("crime:pvpScoreUpdated", src, {
                                    pvp_battle_id   = battleId,
                                    organization_id = orgId,
                                    score           = newScore,
                                })
                            end
                        end
                    end
                    break
                end
            end
        end
    end
end)

-- ──────────────────────────────────────────────────────────
-- NetEvent: "crime:pvpPlayerDeath"
--   Applies death-penalty score deduction for an org.
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:pvpPlayerDeath", function(battleId)
    local playerId = source

    local identifier = sfr:getIdentifier(playerId)
    if not identifier then return end

    local orgId = Player(playerId).state.organization
    if not orgId then
        Debug("crime:pvpPlayerDeath", "No organization found for player", playerId)
        return
    end

    local instance = ActivePvpBattles[battleId]
    if not instance then
        Debug("crime:pvpPlayerDeath", "No battle found for player", playerId)
        return
    end

    local penalty = Config.PvpSystem and Config.PvpSystem.DeathPenalty or 10

    if not instance.scores_cache[orgId] then
        instance.scores_cache[orgId] = 0
    end
    instance.scores_cache[orgId] = instance.scores_cache[orgId] - penalty

    instance:triggerEvent("crime:pvpScoreUpdated", {
        pvp_battle_id   = battleId,
        organization_id = orgId,
        score           = instance.scores_cache[orgId],
    })
end)

-- ──────────────────────────────────────────────────────────
-- playerDropped — remove disconnected player from all battles
-- ──────────────────────────────────────────────────────────
AddEventHandler("playerDropped", function()
    local playerId = source
    for _, instance in pairs(ActivePvpBattles) do
        if instance and instance.isActive then
            instance:removePlayer(playerId)
        end
    end
end)
