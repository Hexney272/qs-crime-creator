-- ============================================================
-- server/modules/creator.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Creator tool server callbacks: permission check, fetching
-- config data for the creator UI, player search, record
-- CRUD proxies, and season-pass reset.
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- HasPermission(playerId)
--   Returns true if the player is an admin or holds a
--   job grade listed in Config.CreatorJobs.
-- ──────────────────────────────────────────────────────────
function HasPermission(playerId)
    local jobName  = sfr:getJobName(playerId)
    local jobGrade = sfr:getJobGrade(playerId)

    if sfr:playerIsAdmin(playerId) then return true end

    for _, entry in pairs(Config.CreatorJobs) do
        if entry.job == jobName then
            if entry.grade then
                if table.contains(entry.grade, jobGrade) then
                    return true
                end
            else
                return true
            end
        end
    end

    return false
end

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:hasPermission"
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:hasPermission", function(playerId)
    return HasPermission(playerId)
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getCreatorData"
--   Returns the full creator-tool config bundle.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getCreatorData", function(playerId)
    if not HasPermission(playerId) then
        Error("crime:getCreatorData",
              "Player does not have permission to get creator data")
        return nil
    end

    -- Build money types list
    local moneyTypes = {}
    if Config.MoneyTypes then
        for _, mt in ipairs(Config.MoneyTypes) do
            moneyTypes[#moneyTypes + 1] = {
                label = mt.label,
                value = mt.value,
                image = mt.image,
            }
        end
    end

    -- Reward type / rarity defaults
    local rewardTypes    = Config.RewardTypes    or { "money", "vehicle", "item" }
    local rewardRarities = Config.RewardRarities or { "common", "rare", "epic", "legendary" }

    return {
        items         = GetItemList(),
        jobs          = sfr:getJobsData(),
        moneyTypes    = moneyTypes,
        rewardTypes   = rewardTypes,
        rewardRarities = rewardRarities,
    }
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:searchPlayers"
--   Returns players matching a name/identifier search.
--   Normalises QB/ESX identifier field names.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:searchPlayers", function(playerId, query)
    if not HasPermission(playerId) then
        Error("crime:searchPlayers",
              "Player does not have permission to search players")
        return {}
    end

    if not query or #query < 2 then return {} end

    local results     = {}
    local rawPlayers  = sfr:searchPlayers(query)

    for _, p in ipairs(rawPlayers) do
        local name, identifier = nil, nil

        if p.citizenid then
            -- QB-Core format
            if p.charinfo then
                local info = json.decode(p.charinfo)
                local first = info.firstname or ""
                local last  = info.lastname  or ""
                name        = first .. " " .. last
            end
            identifier = p.citizenid

        elseif p.identifier then
            -- ESX format
            if p.firstname then
                local first = p.firstname or ""
                local last  = p.lastname  or ""
                name        = first .. " " .. last
            end
            identifier = p.identifier
        end

        if name and name ~= " " and identifier then
            results[#results + 1] = { identifier = identifier, name = name }
        end
    end

    return results
end)

-- ──────────────────────────────────────────────────────────
-- Record CRUD proxies (delegate to RecordManager)
-- ──────────────────────────────────────────────────────────

lib.callback.register("crime:createRecord", function(playerId, recordType, data)
    return RecordManager:create(playerId, recordType, data)
end)

lib.callback.register("crime:updateRecord", function(playerId, recordType, recordId, data)
    return RecordManager:update(playerId, recordType, recordId, data)
end)

lib.callback.register("crime:removeRecord", function(playerId, recordType, recordId)
    return RecordManager:remove(playerId, recordType, recordId)
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:resetSeasonPass"
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:resetSeasonPass", function(playerId)
    if not HasPermission(playerId) then
        Error("crime:resetSeasonPass", "Player does not have permission")
        return false
    end

    local ok = db.resetSeasonPass()
    if ok then
        Notification(playerId, i18n.t("creator.season_pass_reset"), "success")
        RecordManager:clearCache("season_pass")
        TriggerClientEvent("crime:recordRemoved", -1, "season_pass", "season_pass")
    end
    return ok
end)
