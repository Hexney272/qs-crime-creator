-- ============================================================
-- server/modules/pvp/battle.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- PvpBattle class (ox_lib based).
-- Manages one active PvP battle: timers, score accumulation,
-- player-zone tracking, countdown notifications, and finish.
-- ============================================================

PvpBattle = lib.class("PvpBattle")

-- ──────────────────────────────────────────────────────────
-- local toUnixSec(val)
--   Converts a start_date value to a Unix timestamp (seconds).
--   Handles both integer millisecond timestamps and MySQL
--   datetime strings ("YYYY-MM-DD HH:MM:SS"), since the DB
--   may return either depending on the code path that wrote it.
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
-- PvpBattle:triggerEvent(eventName, ...)
--   Fires a client event on every player currently in the zone.
-- ──────────────────────────────────────────────────────────
function PvpBattle:triggerEvent(eventName, ...)
    for playerId in pairs(self.players_in_zone or {}) do
        TriggerClientEvent(eventName, playerId, ...)
    end
end

-- ──────────────────────────────────────────────────────────
-- PvpBattle:constructor(battleData)
--   battleData must contain: id, start_date (Unix ms), duration
-- ──────────────────────────────────────────────────────────
function PvpBattle:constructor(battleData)
    self.id = battleData.id

    -- Convert start_date to Lua Unix timestamp (handles both ms int and datetime string)
    local startTs = toUnixSec(battleData.start_date)
    self.start_time    = startTs
    self.end_time      = startTs + battleData.duration
    self.duration      = battleData.duration
    self.players_in_zone  = {}
    self.scoreLoopStarted = false
    self.notificationTimers = {}
    self.isActive      = true
    self.scores_cache  = {}

    -- Seed scores from DB
    local participants = db.getPvpParticipants(self.id)
    for _, p in ipairs(participants) do
        if p.status == "accepted" then
            local scoreRow = db.getPvpScore(self.id, p.organization_id)
            self.scores_cache[p.organization_id] = scoreRow and scoreRow.score or 0
        end
    end

    -- Schedule countdown notifications
    local notifTimes = (Config.PvpSystem and Config.PvpSystem.NotificationTimes)
                    or { 600, 300, 60 }

    for _, secsBeforeEnd in ipairs(notifTimes) do
        local waitSecs = self.end_time - secsBeforeEnd - os.time()
        if waitSecs > 0 then
            CreateThread(function()
                Wait(waitSecs * 1000)
                if not self.isActive then return end

                local parts = db.getPvpParticipants(self.id)
                for _, part in ipairs(parts) do
                    if part.status == "accepted" then
                        local org = RecordManager:get("organizations", part.organization_id)
                        if org and org.members then
                            for _, member in ipairs(org.members) do
                                local playerId = sfr:getSourceFromIdentifier(member.identifier)
                                if playerId then
                                    Notification(playerId,
                                        i18n.t("pvp.battle.starts_in", {
                                            minutes = math.floor(secsBeforeEnd / 60)
                                        }), "info")
                                end
                            end
                        end
                    end
                end
            end)
        end
    end

    -- End-timer thread
    CreateThread(function()
        while true do
            if not self.isActive then break end
            Wait(1000)
            if os.time() - self.end_time >= 0 then
                if self.isActive then self:finish() end
                break
            end
        end
    end)

    self:startScoreLoop()
    Debug("PvpBattle:constructor", "Created PvpBattle instance:", self.id)
end

-- ──────────────────────────────────────────────────────────
-- PvpBattle:startScoreLoop()
--   Per-second accumulation loop: awards 1 point per second
--   per living, in-zone player to their org.
-- ──────────────────────────────────────────────────────────
function PvpBattle:startScoreLoop()
    if self.scoreLoopStarted then return end
    self.scoreLoopStarted = true

    CreateThread(function()
        while true do
            if not self.isActive then break end
            Wait(1000)

            if os.time() >= self.end_time then
                if self.isActive then self:finish() end
                break
            end

            if not self.players_in_zone then goto continue end

            -- Count living in-zone players per org
            local orgCounts = {}
            for playerId, entry in pairs(self.players_in_zone) do
                local pState = Player(playerId) and Player(playerId).state
                if not pState then
                    self.players_in_zone[playerId] = nil
                else
                    local sinceHeartbeat = os.time() - (entry.last_heartbeat or 0)
                    if sinceHeartbeat > 3 then
                        self.players_in_zone[playerId] = nil
                    elseif not IsPlayerDead(playerId) then
                        local orgId = entry.orgId
                        if orgId then
                            orgCounts[orgId] = (orgCounts[orgId] or 0) + 1
                        end
                    end
                end
            end

            -- Award score and broadcast
            for orgId, count in pairs(orgCounts) do
                if count > 0 then
                    self.scores_cache[orgId] = (self.scores_cache[orgId] or 0) + count

                    self:triggerEvent("crime:pvpScoreUpdated", {
                        pvp_battle_id   = self.id,
                        organization_id = orgId,
                        score           = self.scores_cache[orgId],
                    })
                end
            end

            ::continue::
        end
    end)
end

-- ──────────────────────────────────────────────────────────
-- PvpBattle:addPlayer(playerId, orgId)
-- ──────────────────────────────────────────────────────────
function PvpBattle:addPlayer(playerId, orgId)
    if not self.isActive then return false end

    if not self.players_in_zone then self.players_in_zone = {} end

    local now = os.time()
    self.players_in_zone[playerId] = {
        orgId          = orgId,
        entered_at     = now,
        last_heartbeat = now,
    }

    Debug("PvpBattle:addPlayer", "Player added to zone:", playerId,
        "battle:", self.id, "org:", orgId)
    return true
end

-- ──────────────────────────────────────────────────────────
-- PvpBattle:removePlayer(playerId)
-- ──────────────────────────────────────────────────────────
function PvpBattle:removePlayer(playerId)
    if not self.players_in_zone then return end

    if self.players_in_zone[playerId] then
        self.players_in_zone[playerId] = nil
        Debug("PvpBattle:removePlayer", "Player removed from zone:", playerId,
            "battle:", self.id)
    end
end

-- ──────────────────────────────────────────────────────────
-- PvpBattle:finish()
--   Flushes score changes to DB, determines winner, distributes
--   rewards, broadcasts finish event, and destroys the instance.
-- ──────────────────────────────────────────────────────────
function PvpBattle:finish()
    if not self.isActive then return end
    self.isActive = false

    local battleRecord = db.getPvpBattle(self.id)
    if not battleRecord then
        self:destroy()
        return
    end

    -- Flush score cache increments to DB
    for orgId, cachedScore in pairs(self.scores_cache) do
        local dbScore = db.getPvpScore(self.id, orgId)
        local dbVal   = (dbScore and dbScore.score) or 0
        local diff    = cachedScore - dbVal
        if math.abs(diff) > 0.001 then
            db.updatePvpScore(self.id, orgId, diff)
        end
    end

    -- Determine winner (highest score)
    local scores = db.getPvpScores(self.id)
    if not scores or #scores == 0 then
        db.updatePvpBattleStatus(self.id, "finished")
        self:destroy()
        return
    end

    local winner = scores[1]
    for _, s in ipairs(scores) do
        if s.score > winner.score then winner = s end
    end

    -- Give rewards to winner org
    if battleRecord.rewards and winner.organization_id then
        for _, reward in ipairs(battleRecord.rewards) do
            GivePvpReward(winner.organization_id, reward)
        end
    end

    db.updatePvpBattleStatus(self.id, "finished")

    -- Notify players in accepted orgs
    local payload = {
        pvp_battle_id  = self.id,
        winner_org_id  = winner.organization_id,
        scores         = scores,
    }
    self:triggerEvent("crime:pvpBattleFinished", payload)

    local participants = db.getPvpParticipants(self.id)
    for _, part in ipairs(participants or {}) do
        if part.status == "accepted" then
            local org = RecordManager:get("organizations", part.organization_id)
            if org and org.members then
                for _, member in ipairs(org.members) do
                    local playerId = sfr:getSourceFromIdentifier(member.identifier)
                    if playerId then
                        TriggerClientEvent("crime:pvpBattleFinished", playerId, payload)
                    end
                end
            end
        end
    end

    -- Delay "battle destroyed" broadcast so clients can show winner screen
    CreateThread(function()
        Wait(6000)
        TriggerClientEvent("crime:pvpBattleDestroyed", -1, self.id)
    end)

    self:destroy()
end

-- ──────────────────────────────────────────────────────────
-- PvpBattle:getScore(orgId)
-- ──────────────────────────────────────────────────────────
function PvpBattle:getScore(orgId)
    return self.scores_cache[orgId] or 0
end

-- ──────────────────────────────────────────────────────────
-- PvpBattle:getScores()
--   Returns sorted score entries with org label/color, desc.
-- ──────────────────────────────────────────────────────────
function PvpBattle:getScores()
    local result = {}
    for orgId, score in pairs(self.scores_cache) do
        local org = RecordManager:get("organizations", orgId)
        result[#result + 1] = {
            id                 = 0,
            pvp_battle_id      = self.id,
            organization_id    = orgId,
            score              = score,
            organization_label = org and org.label or nil,
            organization_color = org and org.color or nil,
        }
    end

    table.sort(result, function(a, b) return a.score > b.score end)
    return result
end

-- ──────────────────────────────────────────────────────────
-- PvpBattle:destroy()
--   Cleans up instance state.
-- ──────────────────────────────────────────────────────────
function PvpBattle:destroy()
    self.isActive           = false
    self.players_in_zone    = nil
    self.notificationTimers = {}
    self.scoreLoopStarted   = false
    self.scores_cache       = nil
    Debug("PvpBattle:destroy", "Destroyed PvpBattle instance:", self.id)
end
