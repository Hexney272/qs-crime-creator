-- ============================================================
-- server/modules/moneylaundering.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Server-side money-laundering session manager.
-- Tracks per-player sessions, validates deliveries,
-- awards XP/clean money, and enforces daily limits.
-- ============================================================

-- activeSessions[playerId] = sessionData
local activeSessions = {}

-- ──────────────────────────────────────────────────────────
-- local getDailyRecord(orgId, identifier)
--   Returns today's daily-stats row for the player/org, or nil.
-- ──────────────────────────────────────────────────────────
local function getDailyRecord(orgId, identifier)
    local today = os.date("%Y-%m-%d")
    return MySQL.single.await([[
        SELECT * FROM qs_crime_money_laundering_daily
        WHERE organization_id = ? AND identifier = ? AND last_reset_date = ?
    ]], { orgId, identifier, today })
end

-- ──────────────────────────────────────────────────────────
-- local getDailyCount(orgId, identifier)
--   Returns how many laundering runs the player completed today.
-- ──────────────────────────────────────────────────────────
local function getDailyCount(orgId, identifier)
    local row = getDailyRecord(orgId, identifier)
    return (row and row.completed_count) or 0
end

-- ──────────────────────────────────────────────────────────
-- local incrementDailyCount(orgId, identifier, amount)
--   Upserts the daily tracking row (completed_count + 1).
-- ──────────────────────────────────────────────────────────
local function incrementDailyCount(orgId, identifier, amount)
    local today = os.date("%Y-%m-%d")
    local row   = getDailyRecord(orgId, identifier)

    if row then
        local ok = MySQL.update.await([[
            UPDATE qs_crime_money_laundering_daily
            SET completed_count = completed_count + 1,
                total_laundered = total_laundered + ?
            WHERE id = ?
        ]], { amount, row.id })
        return ok > 0
    else
        local newId = MySQL.insert.await([[
            INSERT INTO qs_crime_money_laundering_daily
            (organization_id, identifier, completed_count, total_laundered, last_reset_date)
            VALUES (?, ?, 1, ?, ?)
        ]], { orgId, identifier, amount, today })
        return newId ~= nil
    end
end

-- ──────────────────────────────────────────────────────────
-- local hasMoneyLaunderingUpgrade(playerId, orgId)
--   Returns true if the org has the money_laundering upgrade.
-- ──────────────────────────────────────────────────────────
local function hasMoneyLaunderingUpgrade(playerId, orgId)
    local org = RecordManager:get("organizations", orgId)
    if not (org and org.upgrades) then return false end

    for _, upg in ipairs(org.upgrades) do
        if upg.name == "money_laundering" then
            if (tonumber(upg.level) or 0) >= 1 then
                return true
            end
        end
    end
    return false
end

-- ──────────────────────────────────────────────────────────
-- local hasPermission(playerId, orgId)
-- ──────────────────────────────────────────────────────────
local function hasPermission(playerId, orgId)
    return sv_bossmenu:hasPermission(playerId, orgId, "canAccessMoneyLaundering")
end

-- ──────────────────────────────────────────────────────────
-- local awardXP(orgId, xp)
--   Adds XP to the org and recalculates level.
-- ──────────────────────────────────────────────────────────
local function awardXP(orgId, xp)
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

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:moneylaundering:canStart"
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:moneylaundering:canStart", function(playerId, orgId)
    if not orgId then
        return { canStart = false, reason = "no_organization" }
    end

    local identifier = sfr:getIdentifier(playerId)
    if not identifier then
        return { canStart = false, reason = "invalid_player" }
    end

    if activeSessions[playerId] then
        return { canStart = false, reason = "already_active" }
    end

    if not hasMoneyLaunderingUpgrade(playerId, orgId) then
        return { canStart = false, reason = "need_upgrade" }
    end

    if not hasPermission(playerId, orgId) then
        return { canStart = false, reason = "no_permission" }
    end

    local dailyCount = getDailyCount(orgId, identifier)
    if dailyCount >= Config.MoneyLaundering.limitPerDay then
        return { canStart = false, reason = "daily_limit_reached" }
    end

    local blackMoney = sfr:getAccountMoney(playerId, "black_money")
    if blackMoney < Config.MoneyLaundering.minBlackMoney then
        return {
            canStart = false,
            reason   = "not_enough_black_money",
            data     = { required = Config.MoneyLaundering.minBlackMoney, current = blackMoney },
        }
    end

    local totalCost = Config.MoneyLaundering.price + Config.MoneyLaundering.vehiclePrice
    local money     = sfr:getAccountMoney(playerId, "money")
    if totalCost > money then
        return {
            canStart = false,
            reason   = "not_enough_money",
            data     = { required = totalCost, current = money },
        }
    end

    return {
        canStart = true,
        data     = {
            price           = Config.MoneyLaundering.price,
            vehiclePrice    = Config.MoneyLaundering.vehiclePrice,
            minBlackMoney   = Config.MoneyLaundering.minBlackMoney,
            blackMoney      = blackMoney,
            locations       = Config.MoneyLaundering.locations,
            dailyRemaining  = Config.MoneyLaundering.limitPerDay - dailyCount,
        },
    }
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:moneylaundering:start"
--   Charges the player and creates a session.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:moneylaundering:start", function(playerId, orgId)
    if not orgId then
        return { success = false, message = "no_organization" }
    end

    local identifier = sfr:getIdentifier(playerId)
    if not identifier then
        return { success = false, message = "invalid_player" }
    end

    local totalCost = Config.MoneyLaundering.price + Config.MoneyLaundering.vehiclePrice
    local ok = sfr:removeAccountMoney(playerId, "money", totalCost)
    if not ok then
        return { success = false, message = "failed_to_deduct_money" }
    end

    local firstName, lastName = sfr:getUserName(playerId)
    local playerName = firstName .. " " .. lastName

    -- Log the service fee
    OrganizationFinanceDB:createTransaction(orgId, {
        type        = "deposit",
        amount      = Config.MoneyLaundering.price,
        money_type  = "money",
        description = "Money laundering service fee",
        identifier  = identifier,
        name        = playerName,
        status      = "completed",
    })

    activeSessions[playerId] = {
        orgId           = orgId,
        identifier      = identifier,
        playerName      = playerName,
        startTime       = os.time(),
        currentLocation = 1,
        totalLocations  = #Config.MoneyLaundering.locations,
        totalLaundered  = 0,
        vehiclePrice    = Config.MoneyLaundering.vehiclePrice,
        deliveries      = {},
    }

    Debug("crime:moneylaundering:start", "Session started for player:", playerId,
        "org:", orgId)

    return {
        success            = true,
        vehicleModel       = Config.MoneyLaundering.ped.vehicle.model,
        vehicleSpawnCoords = Config.MoneyLaundering.ped.vehicle.spawnCoords,
        locations          = Config.MoneyLaundering.locations,
    }
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:moneylaundering:delivery"
--   Processes one delivery stop.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:moneylaundering:delivery", function(playerId, orgId, locationIndex)
    local session = activeSessions[playerId]
    if not session then return { success = false, message = "no_active_session" } end
    if session.orgId ~= orgId then return { success = false, message = "wrong_organization" } end
    if locationIndex ~= session.currentLocation then return { success = false, message = "wrong_location" } end

    local blackMoney = sfr:getAccountMoney(playerId, "black_money")
    if blackMoney <= 0 then return { success = false, message = "no_black_money" } end

    -- Calculate laundering amount
    local minLaunder = Config.MoneyLaundering.launder.min
    local maxLaunder = Config.MoneyLaundering.launder.max
    local laundered  = math.min(math.random(minLaunder, maxLaunder), blackMoney)

    local removedOk = sfr:removeAccountMoney(playerId, "black_money", laundered)
    if not removedOk then return { success = false, message = "failed_to_remove_black_money" } end

    sfr:addAccountMoney(playerId, "money", laundered)

    session.totalLaundered               = session.totalLaundered + laundered
    session.deliveries[locationIndex]    = { amount = laundered, time = os.time() }
    session.currentLocation              = session.currentLocation + 1

    -- Finance log
    OrganizationFinanceDB:createTransaction(orgId, {
        type        = "deposit",
        amount      = laundered,
        money_type  = "money",
        description = "Money laundering delivery #" .. locationIndex .. "/" .. session.totalLocations,
        identifier  = session.identifier,
        name        = session.playerName,
        status      = "completed",
        metadata    = json.encode({
            type             = "money_laundering",
            delivery         = locationIndex,
            total_deliveries = session.totalLocations,
        }),
    })

    -- XP reward per delivery
    local xpPerDelivery = Config.MoneyLaundering.xpReward or 150
    awardXP(orgId, xpPerDelivery)
    db.updateOrganizationMemberStats(orgId, session.identifier, xpPerDelivery, 0, 0)

    local remainingBlack = sfr:getAccountMoney(playerId, "black_money")
    Debug("crime:moneylaundering:delivery", "Delivery completed:", locationIndex,
        "Amount:", laundered)

    return {
        success               = true,
        cleanMoney            = laundered,
        remainingBlackMoney   = remainingBlack,
        xpEarned              = xpPerDelivery,
        isLastDelivery        = session.currentLocation > session.totalLocations,
    }
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:moneylaundering:finish"
--   Completes the full run, awards bonus XP.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:moneylaundering:finish", function(playerId, orgId)
    local session = activeSessions[playerId]
    if not session then return { success = false, message = "no_active_session" } end
    if session.orgId ~= orgId then return { success = false, message = "wrong_organization" } end
    if session.currentLocation <= session.totalLocations then
        return { success = false, message = "deliveries_not_complete" }
    end

    local bonusXP = Config.MoneyLaundering.xpBonusComplete or 300
    awardXP(orgId, bonusXP)
    db.updateOrganizationMemberStats(orgId, session.identifier, bonusXP, 1, 0)

    -- Log the completed run
    incrementDailyCount(orgId, session.identifier, session.totalLaundered)

    db:clearCache("member_details", orgId .. "_" .. session.identifier)

    -- Final summary finance log
    OrganizationFinanceDB:createTransaction(orgId, {
        type        = "deposit",
        amount      = 0,
        money_type  = "money",
        description = "Money laundering mission completed - Total: $" .. session.totalLaundered,
        identifier  = session.identifier,
        name        = session.playerName,
        status      = "completed",
        metadata    = json.encode({
            type           = "money_laundering_complete",
            total_laundered = session.totalLaundered,
            deliveries     = session.deliveries,
        }),
    })

    local totalLaundered = session.totalLaundered
    activeSessions[playerId] = nil

    Debug("crime:moneylaundering:finish", "Mission completed for player:", playerId,
        "Total laundered:", totalLaundered)
    Notification(playerId, i18n.t("money_laundering.all_complete"), "success")

    return { success = true, totalLaundered = totalLaundered, bonusXP = bonusXP }
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:moneylaundering:stop"
--   Cancels the run.  Refunds vehicle deposit if requested.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:moneylaundering:stop", function(playerId, orgId, refundVehicle)
    local session = activeSessions[playerId]
    if not session then return { success = false, message = "no_active_session" } end
    if session.orgId ~= orgId then return { success = false, message = "wrong_organization" } end

    local refund = 0
    if refundVehicle then
        refund = session.vehiclePrice
        sfr:addAccountMoney(playerId, "money", refund)
        OrganizationFinanceDB:createTransaction(orgId, {
            type        = "withdraw",
            amount      = -refund,
            money_type  = "money",
            description = "Money laundering vehicle deposit refund",
            identifier  = session.identifier,
            name        = session.playerName,
            status      = "completed",
        })
    end

    if session.totalLaundered > 0 then
        incrementDailyCount(orgId, session.identifier, session.totalLaundered)
    end

    local totalLaundered = session.totalLaundered
    activeSessions[playerId] = nil

    Debug("crime:moneylaundering:stop", "Mission stopped for player:", playerId,
        "Refund:", refund)

    return { success = true, refund = refund, totalLaundered = totalLaundered }
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:moneylaundering:isActive"
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:moneylaundering:isActive", function(playerId)
    return activeSessions[playerId] ~= nil
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:moneylaundering:getSession"
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:moneylaundering:getSession", function(playerId)
    return activeSessions[playerId]
end)

-- ──────────────────────────────────────────────────────────
-- Cleanup hooks
-- ──────────────────────────────────────────────────────────
AddEventHandler("playerDropped", function()
    local playerId = source
    if activeSessions[playerId] then
        Debug("crime:moneylaundering", "Player disconnected, clearing session:", playerId)
        activeSessions[playerId] = nil
    end
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        activeSessions = {}
    end
end)

Debug("Money Laundering module loaded")
