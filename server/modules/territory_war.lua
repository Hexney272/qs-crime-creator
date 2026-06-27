-- ============================================================
-- server/modules/territory_war.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- In-memory territory war engine.
-- Wars are purely runtime state (activeWars table) — not
-- persisted to DB except for territory ownership and stats.
-- ============================================================

-- ── State ───────────────────────────────────────────────────
local nextWarId   = 1                  -- auto-increment war IDs
local activeWars  = {}                 -- activeWars[warId] = warData
local protectedUntil = {}              -- protectedUntil[territoryId] = unixTimestamp

-- ──────────────────────────────────────────────────────────
-- local getOwnerOrgId(territoryId)
-- ──────────────────────────────────────────────────────────
local function getOwnerOrgId(territoryId)
    local territory = RecordManager:get("territories", territoryId)
    return territory and territory.organization_id or nil
end

-- ──────────────────────────────────────────────────────────
-- local countOnlineOrgMembers(orgId)
-- ──────────────────────────────────────────────────────────
local function countOnlineOrgMembers(orgId)
    local count = 0
    local org   = RecordManager:get("organizations", orgId)
    if org and org.members then
        for _, member in ipairs(org.members) do
            if sfr:getSourceFromIdentifier(member.identifier) then
                count = count + 1
            end
        end
    end
    return count
end

-- ──────────────────────────────────────────────────────────
-- local getActiveWarForTerritory(territoryId)
-- ──────────────────────────────────────────────────────────
local function getActiveWarForTerritory(territoryId)
    for _, war in pairs(activeWars) do
        if war.territory_id == territoryId then return war end
    end
    return nil
end

-- Global accessor used by taxing.lua — territory wars are runtime-only (not in DB)
function GetActiveWarForTerritory(territoryId)
    return getActiveWarForTerritory(territoryId)
end

-- ──────────────────────────────────────────────────────────
-- local isTerritoryProtected(territoryId)
-- ──────────────────────────────────────────────────────────
local function isTerritoryProtected(territoryId)
    local expires = protectedUntil[territoryId]
    if expires and expires > os.time() then return true end
    return false
end

-- ──────────────────────────────────────────────────────────
-- local setTerritoryProtection(territoryId, durationSeconds)
-- ──────────────────────────────────────────────────────────
local function setTerritoryProtection(territoryId, durationSeconds)
    protectedUntil[territoryId] = os.time() + durationSeconds
end

-- ──────────────────────────────────────────────────────────
-- local newWarId()
-- ──────────────────────────────────────────────────────────
local function newWarId()
    local id = nextWarId
    nextWarId = nextWarId + 1
    return id
end

-- ──────────────────────────────────────────────────────────
-- local getCallerOrgId(identifier)
--   Finds the org that has identifier as a member.
-- ──────────────────────────────────────────────────────────
local function getCallerOrgId(identifier)
    local orgs = RecordManager:getAll("organizations")
    for _, org in ipairs(orgs) do
        -- Check owner first (owner is NOT in org.members)
        if org.owner and org.owner.identifier == identifier then
            return org.id
        end
        if org.members then
            for _, m in ipairs(org.members) do
                if m.identifier == identifier then return org.id end
            end
        end
    end
    return nil
end

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:startTerritoryWar"
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:startTerritoryWar", function(playerId, territoryId)
    if not Config.CrimeTablet.EnableTerritoryWar then
        return false, i18n.t("tablet.map.territory_war_disabled")
    end
    if not territoryId then
        return false, i18n.t("tablet.map.invalid_territory")
    end

    local identifier = sfr:getIdentifier(playerId)
    local attackerOrgId = getCallerOrgId(identifier)

    if not attackerOrgId then
        return false, i18n.t("tablet.map.not_in_organization")
    end
    if getActiveWarForTerritory(territoryId) then
        return false, i18n.t("tablet.map.war_already_active")
    end
    if isTerritoryProtected(territoryId) then
        return false, i18n.t("tablet.map.territory_protected")
    end

    local onlineCount = countOnlineOrgMembers(attackerOrgId)
    if onlineCount < Config.CrimeTablet.WarMinPlayers then
        return false, i18n.t("tablet.map.not_enough_players", {
            current  = onlineCount,
            required = Config.CrimeTablet.WarMinPlayers,
        })
    end

    -- Check org finance balance
    local finance = OrganizationFinanceDB:getFinance(attackerOrgId)
    local balance = (finance and finance.clean_money) or 0
    if balance < Config.CrimeTablet.WarStartCost then
        return false, i18n.t("boss_not_enough_money",
            { amount = Config.CrimeTablet.WarStartCost })
    end

    -- Deduct cost
    local first, last = sfr:getUserName(playerId)
    local playerName  = first .. " " .. last

    local txOk = OrganizationFinanceDB:createTransaction(attackerOrgId, {
        type        = "expense",
        amount      = -Config.CrimeTablet.WarStartCost,
        money_type  = "money",
        description = "Territory war start cost",
        identifier  = identifier,
        name        = playerName,
        status      = "completed",
    })
    if not txOk then
        return false, i18n.t("tablet.map.failed_to_create_transaction")
    end

    local deducted = OrganizationFinanceDB:updateMoney(
        attackerOrgId, Config.CrimeTablet.WarStartCost, "withdraw", "clean")
    if not deducted then
        return false, i18n.t("tablet.map.failed_to_deduct_cost")
    end

    -- Create war record
    local warId      = newWarId()
    local now        = os.time()
    local startedAt  = os.date("%Y-%m-%d %H:%M:%S", now)
    local endsAt     = os.date("%Y-%m-%d %H:%M:%S", now + Config.CrimeTablet.WarDuration)
    local defenderOrgId = getOwnerOrgId(territoryId)

    activeWars[warId] = {
        id              = warId,
        territory_id    = territoryId,
        status          = "active",
        started_by_org_id = attackerOrgId,
        started_at      = startedAt,
        ends_at         = endsAt,
        timer           = now + Config.CrimeTablet.WarDuration,
        start_cost      = Config.CrimeTablet.WarStartCost,
        attacker_org_id = attackerOrgId,
        defender_org_id = defenderOrgId,
        scores          = {},
    }

    -- Seed score entries
    activeWars[warId].scores[attackerOrgId] = {
        score = 0, tax_stolen = 0, drugs_sold = 0,
        graffiti_sprayed = 0, graffiti_removed = 0,
    }
    if defenderOrgId and defenderOrgId ~= attackerOrgId then
        activeWars[warId].scores[defenderOrgId] = {
            score = 0, tax_stolen = 0, drugs_sold = 0,
            graffiti_sprayed = 0, graffiti_removed = 0,
        }
    end

    Debug("TerritoryWar", "War started - ID:", warId, "Territory:", territoryId,
        "Attacker:", attackerOrgId, "Defender:", defenderOrgId)

    -- Resolve territory label and attacker label
    local territory     = RecordManager:get("territories", territoryId)
    local territoryLabel = (territory and territory.label) or "Unknown Territory"
    local attackerOrg    = RecordManager:get("organizations", attackerOrgId)

    -- Notify attacker org members
    if attackerOrg and attackerOrg.members then
        for _, member in ipairs(attackerOrg.members) do
            local src = sfr:getSourceFromIdentifier(member.identifier)
            if src then
                TriggerClientEvent("crime:territoryWarStarted", src, {
                    war_id            = warId,
                    territory_id      = territoryId,
                    territory_label   = territoryLabel,
                    started_by_org_id = attackerOrgId,
                    defender_org_id   = defenderOrgId,
                    ends_at           = endsAt,
                    is_attacker       = true,
                })
            end
        end
    end

    -- Notify defender org members
    if defenderOrgId and defenderOrgId ~= attackerOrgId then
        local defenderOrg = RecordManager:get("organizations", defenderOrgId)
        if defenderOrg and defenderOrg.members then
            for _, member in ipairs(defenderOrg.members) do
                local src = sfr:getSourceFromIdentifier(member.identifier)
                if src then
                    TriggerClientEvent("crime:territoryWarStarted", src, {
                        war_id             = warId,
                        territory_id       = territoryId,
                        territory_label    = territoryLabel,
                        started_by_org_id  = attackerOrgId,
                        attacker_org_label = (attackerOrg and attackerOrg.label) or "Unknown",
                        defender_org_id    = defenderOrgId,
                        ends_at            = endsAt,
                        is_attacker        = false,
                    })
                end
            end
        end
    end

    -- Broadcast map update to all clients
    TriggerClientEvent("crime:territoryWarMapUpdate", -1, {
        war_id       = warId,
        territory_id = territoryId,
        status       = "active",
    })

    return true, nil
end)

-- ──────────────────────────────────────────────────────────
-- UpdateTerritoryWarScore(warId, orgId, delta)
--   Increments score fields for one org in a war and notifies
--   all participating org members.
-- ──────────────────────────────────────────────────────────
function UpdateTerritoryWarScore(warId, orgId, delta)
    if not (warId and orgId) or not delta then return false end

    local war = activeWars[warId]
    if not war then return false end

    if not war.scores[orgId] then
        war.scores[orgId] = {
            score = 0, tax_stolen = 0, drugs_sold = 0,
            graffiti_sprayed = 0, graffiti_removed = 0,
        }
    end

    local entry = war.scores[orgId]

    if delta.score           ~= nil then entry.score           = (entry.score           or 0) + delta.score           end
    if delta.tax_stolen      ~= nil then entry.tax_stolen      = (entry.tax_stolen      or 0) + delta.tax_stolen      end
    if delta.drugs_sold      ~= nil then entry.drugs_sold      = (entry.drugs_sold      or 0) + delta.drugs_sold      end
    if delta.graffiti_sprayed ~= nil then entry.graffiti_sprayed = (entry.graffiti_sprayed or 0) + delta.graffiti_sprayed end
    if delta.graffiti_removed ~= nil then entry.graffiti_removed = (entry.graffiti_removed or 0) + delta.graffiti_removed end

    -- Build score list for broadcast
    local scoreList = {}
    for oid, s in pairs(war.scores) do
        scoreList[#scoreList + 1] = {
            organization_id  = oid,
            score            = s.score,
            tax_stolen       = s.tax_stolen,
            drugs_sold       = s.drugs_sold,
            graffiti_sprayed = s.graffiti_sprayed,
            graffiti_removed = s.graffiti_removed,
        }
    end

    -- Notify all online members of all participating orgs
    for participantOrgId in pairs(war.scores) do
        local org = RecordManager:get("organizations", participantOrgId)
        if org and org.members then
            for _, member in ipairs(org.members) do
                local src = sfr:getSourceFromIdentifier(member.identifier)
                if src then
                    TriggerClientEvent("crime:territoryWarScoreUpdated", src, {
                        war_id          = warId,
                        territory_id    = war.territory_id,
                        organization_id = orgId,
                        scores          = scoreList,
                    })
                end
            end
        end
    end

    return true
end

-- ──────────────────────────────────────────────────────────
-- local endTerritoryWar(warId)
--   Closes a war: determines winner, updates territory
--   ownership, applies protection timer, and notifies clients.
-- ──────────────────────────────────────────────────────────
local function endTerritoryWar(warId)
    local war = activeWars[warId]
    if not war then return false end

    local territoryId = war.territory_id

    -- Build sorted score list
    local scoreList = {}
    for oid, s in pairs(war.scores) do
        scoreList[#scoreList + 1] = {
            organization_id  = oid,
            score            = s.score            or 0,
            tax_stolen       = s.tax_stolen       or 0,
            drugs_sold       = s.drugs_sold       or 0,
            graffiti_sprayed = s.graffiti_sprayed or 0,
            graffiti_removed = s.graffiti_removed or 0,
        }
    end

    local territory     = RecordManager:get("territories", territoryId)
    local territoryLabel = (territory and territory.label) or "Unknown Territory"

    if #scoreList == 0 then
        Debug("TerritoryWar", "War ended with no participants - ID:", warId)
        activeWars[warId] = nil
        TriggerClientEvent("crime:territoryWarEnded", -1, {
            war_id       = warId,
            territory_id = territoryId,
        })
        return true
    end

    -- Sort by score descending
    table.sort(scoreList, function(a, b) return a.score > b.score end)
    local winner = scoreList[1]

    Debug("TerritoryWar", "War ended - ID:", warId, "Winner:", winner.organization_id,
        "Score:", winner.score)

    -- Apply protection timer
    setTerritoryProtection(territoryId, Config.CrimeTablet.WarProtectionDuration)

    -- Update protection expiry in DB
    local protectionExpiry = os.date("%Y-%m-%d %H:%M:%S",
        os.time() + Config.CrimeTablet.WarProtectionDuration)
    db.updateTerritoryProtection(territoryId, protectionExpiry)

    -- Update territory ownership
    if territory then
        db.updateTerritory(0, territoryId, {
            organization_id = winner.organization_id,
            label           = territory.label,
            zone            = territory.zone,
            color           = territory.color,
        })
        RecordManager:clearCache("territories")
        local fresh = RecordManager:get("territories", territoryId)
        if fresh then
            TriggerClientEvent("crime:recordUpdated", -1, "territories", fresh)
            Debug("TerritoryWar", "Territory ownership updated and synced - ID:",
                territoryId, "New owner:", winner.organization_id)
        end
    end

    -- Update winner's wars-won counter
    local stats = db.getOrganizationStats(winner.organization_id)
    if stats then
        db.createOrUpdateOrganizationStats(winner.organization_id, {
            level                   = stats.level,
            xp                      = stats.xp,
            total_missions          = stats.total_missions,
            total_territory_wars_won = (stats.total_territory_wars_won or 0) + 1,
        })
    end

    -- Resolve winner label
    local winnerOrg   = RecordManager:get("organizations", winner.organization_id)
    local winnerLabel = (winnerOrg and winnerOrg.label) or "Unknown"

    activeWars[warId] = nil

    -- Build participant org set
    local participantOrgs = {}
    for _, s in ipairs(scoreList) do participantOrgs[s.organization_id] = true end

    -- Notify all online members of all participating orgs
    for orgId in pairs(participantOrgs) do
        local org = RecordManager:get("organizations", orgId)
        if org and org.members then
            local isWinner = (orgId == winner.organization_id)
            for _, member in ipairs(org.members) do
                local src = sfr:getSourceFromIdentifier(member.identifier)
                if src then
                    TriggerClientEvent("crime:territoryWarEnded", src, {
                        war_id         = warId,
                        territory_id   = territoryId,
                        territory_label = territoryLabel,
                        winner_org_id  = winner.organization_id,
                        winner_label   = winnerLabel,
                        scores         = scoreList,
                        is_winner      = isWinner,
                    })
                end
            end
        end
    end

    TriggerClientEvent("crime:territoryWarMapUpdate", -1, {
        war_id       = warId,
        territory_id = territoryId,
        status       = "finished",
    })
    TriggerClientEvent("crime:territoryWarWon", -1, {
        orgId       = winner.organization_id,
        territoryId = territoryId,
    })

    return true
end

-- ──────────────────────────────────────────────────────────
-- Score update handlers — called via net events and local events
-- ──────────────────────────────────────────────────────────

-- Tax stolen by a player
RegisterNetEvent("crime:territoryWarTaxStolen", function(territoryId, amount)
    local playerId   = source
    local identifier = sfr:getIdentifier(playerId)
    local orgId      = getCallerOrgId(identifier)
    if not orgId then return end

    local war = getActiveWarForTerritory(territoryId)
    if not war then return end

    UpdateTerritoryWarScore(war.id, orgId, {
        score      = Config.CrimeTablet.WarScore.TaxStolen,
        tax_stolen = 1,
    })
end)

-- ── Drug sale handler (server event + local event) ──────────
local function onDrugSale(playerId, territoryId, amount)
    if not playerId then playerId = source end
    if not playerId then return end

    local identifier = sfr:getIdentifier(playerId)
    local orgId      = getCallerOrgId(identifier)
    if not orgId then return end

    local war = getActiveWarForTerritory(territoryId)
    if not war then return end

    local scorePoints = math.floor(amount * Config.CrimeTablet.WarScore.DrugSaleMultiplier)
    UpdateTerritoryWarScore(war.id, orgId, { score = scorePoints, drugs_sold = amount })
end

AddEventHandler("crime:territoryWarDrugSale", function(p, tid, amt)
    onDrugSale(p or source, tid, amt)
end)

-- ── Graffiti spray handler ──────────────────────────────────
local function onGraffitiSpray(playerId, territoryId)
    if not playerId then playerId = source end
    if not playerId then return end

    local identifier = sfr:getIdentifier(playerId)
    local orgId      = getCallerOrgId(identifier)
    if not orgId then return end

    local war = getActiveWarForTerritory(territoryId)
    if not war then return end

    UpdateTerritoryWarScore(war.id, orgId, {
        score            = Config.CrimeTablet.WarScore.GraffitiSpray,
        graffiti_sprayed = 1,
    })
end

RegisterNetEvent("crime:territoryWarGraffitiSpray",  function(tid)
    onGraffitiSpray(source, tid)
end)
AddEventHandler("crime:territoryWarGraffitiSpray", function(p, tid)
    onGraffitiSpray(p or source, tid)
end)

-- ── Graffiti remove handler ─────────────────────────────────
local function onGraffitiRemove(playerId, territoryId, enemyOrgId)
    if not playerId then playerId = source end
    if not playerId then return end

    local identifier = sfr:getIdentifier(playerId)
    local orgId      = getCallerOrgId(identifier)
    if not orgId or not enemyOrgId then return end

    local war = getActiveWarForTerritory(territoryId)
    if not war then return end

    local removeScore = Config.CrimeTablet.WarScore.GraffitiRemove

    -- Award points to the remover
    UpdateTerritoryWarScore(war.id, orgId, {
        score            = removeScore,
        graffiti_removed = 1,
    })
    -- Deduct points from the enemy
    UpdateTerritoryWarScore(war.id, enemyOrgId, {
        score = -removeScore,
    })
end

RegisterNetEvent("crime:territoryWarGraffitiRemove", function(tid, enemyOrgId)
    onGraffitiRemove(source, tid, enemyOrgId)
end)
AddEventHandler("crime:territoryWarGraffitiRemove", function(p, tid, enemyOrgId)
    onGraffitiRemove(p or source, tid, enemyOrgId)
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getActiveTerritoryWar"
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getActiveTerritoryWar", function(_, territoryId)
    if not territoryId then return nil end
    local war = getActiveWarForTerritory(territoryId)
    if not war then return nil end
    return {
        id                = war.id,
        territory_id      = war.territory_id,
        status            = war.status,
        started_by_org_id = war.started_by_org_id,
        started_at        = war.started_at,
        ends_at           = war.ends_at,
        start_cost        = war.start_cost,
    }
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getTerritoryWarScores"
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getTerritoryWarScores", function(_, warId)
    if not warId then return {} end
    local war = activeWars[warId]
    if not (war and war.scores) then return {} end

    local result = {}
    for orgId, s in pairs(war.scores) do
        local org = RecordManager:get("organizations", orgId)
        result[#result + 1] = {
            organization_id    = orgId,
            organization_label = org and org.label or nil,
            organization_color = org and org.color or nil,
            score              = s.score            or 0,
            tax_stolen         = s.tax_stolen       or 0,
            drugs_sold         = s.drugs_sold       or 0,
            graffiti_sprayed   = s.graffiti_sprayed or 0,
            graffiti_removed   = s.graffiti_removed or 0,
        }
    end

    table.sort(result, function(a, b) return a.score > b.score end)
    return result
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getAllActiveWars"
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getAllActiveWars", function(_)
    local result = {}
    for warId, war in pairs(activeWars) do
        result[#result + 1] = {
            id                = war.id,
            territory_id      = war.territory_id,
            status            = war.status,
            started_by_org_id = war.started_by_org_id,
            attacker_org_id   = war.attacker_org_id,
            defender_org_id   = war.defender_org_id,
            started_at        = war.started_at,
            ends_at           = war.ends_at,
        }
    end
    return result
end)

-- ──────────────────────────────────────────────────────────
-- Background thread — ends wars whose timers have expired
-- ──────────────────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(10000)
        local now = os.time()
        for warId, war in pairs(activeWars) do
            if now >= war.timer then
                endTerritoryWar(warId)
            end
        end
    end
end)
