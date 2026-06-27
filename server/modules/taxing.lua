-- ============================================================
-- server/modules/taxing.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Server-side taxing collection system.
-- Validates that a player is authorized (owns or contests the
-- territory), enforces cooldowns, pays the collector, logs a
-- finance transaction, and updates territory-war scores.
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- local calculateNextCollectableAt(timeType, timeValue)
--   Returns a MySQL datetime string representing the next
--   time this taxing point can be collected.
--   timeType: "hourly" | "daily" | "monthly" (default daily)
--   timeValue: multiplier (e.g. 2 = 2 hours / 2 days / ...)
-- ──────────────────────────────────────────────────────────
local function calculateNextCollectableAt(timeType, timeValue)
    local now      = os.time()
    local nextTime = now

    if     timeType == "hourly"  then nextTime = now + timeValue * 3600
    elseif timeType == "daily"   then nextTime = now + timeValue * 86400
    elseif timeType == "monthly" then nextTime = now + timeValue * 2592000
    else                              nextTime = now + 86400
    end

    return tostring(os.date("%Y-%m-%d %H:%M:%S", nextTime))
end

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:collectTaxing"
--   Processes a taxing collection request.
--   Returns (success, errorCode, amountCollected)
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:collectTaxing", function(playerId, taxingId)
    if not taxingId then
        return false, "invalid_taxing"
    end

    local playerIdentifier = sfr:getIdentifier(playerId)
    if not playerIdentifier then
        return false, "invalid_player"
    end

    -- Fetch taxing record from RecordManager or DB
    local taxingRecord = RecordManager:get("taxing", taxingId)
    if not taxingRecord then
        local allTaxing = db.getTaxing()
        for _, entry in ipairs(allTaxing) do
            if entry.id == taxingId then
                taxingRecord = entry
                break
            end
        end
    end

    if not taxingRecord then return false, "taxing_not_found" end
    if not taxingRecord.location then return false, "no_location" end

    -- Decode location if stored as JSON string
    local location = taxingRecord.location
    if type(location) == "string" then
        location = json.decode(location)
    end

    -- Resolve the territory this taxing point belongs to
    local territoryId = taxingRecord.territory_id
    if not territoryId then
        local foundTerritory = db.findTerritoryByLocation(location)
        territoryId = foundTerritory

        if territoryId then
            -- Cache the territory link in the DB
            MySQL.update.await(
                "UPDATE qs_crime_taxing SET territory_id = ? WHERE id = ?",
                { territoryId, taxingId }
            )
        end
    end

    if not territoryId then return false, "no_territory" end

    -- Fetch the territory record
    local territory = RecordManager:get("territories", territoryId)
    if not territory then return false, "territory_not_found" end

    local owningOrgId = territory.organization_id

    -- Find which org the collector belongs to
    local collectorOrgId = nil
    local allOrgs = RecordManager:getAll("organizations")
    for _, org in ipairs(allOrgs) do
        if org.members then
            for _, member in ipairs(org.members) do
                if member.identifier == playerIdentifier then
                    collectorOrgId = org.id
                    break
                end
            end
            if collectorOrgId then break end
        end
    end

    if not collectorOrgId then return false, "not_in_organization" end

    -- Check for an active territory war on this territory
    -- Territory wars are pure runtime state — never in DB.
    -- GetActiveWarForTerritory is exposed as a global by territory_war.lua.
    local activeWar   = GetActiveWarForTerritory and GetActiveWarForTerritory(territoryId) or nil
    local warIsActive = activeWar ~= nil
    local isAuthorized = false

    if warIsActive then
        -- During a war, any participating org (one with a score entry) can collect
        if activeWar.scores and activeWar.scores[collectorOrgId] then
            isAuthorized = true
        end
    elseif owningOrgId and owningOrgId == collectorOrgId then
        -- No war — only the owning org can collect
        isAuthorized = true
    end

    if not isAuthorized then return false, "not_authorized" end

    -- Check cooldown
    local collectionStatus = db.getTaxingCollectionStatus(taxingId)
    if collectionStatus then
        local nextCollectAt = collectionStatus.next_collectable_at
        if nextCollectAt then
            -- Handle both Unix-timestamp (number) and datetime string formats.
            -- calculateNextCollectableAt() stores as a datetime string, so the
            -- string branch is the primary path that must be handled here.
            local nextTimestamp = nil

            if type(nextCollectAt) == "number" then
                nextTimestamp = nextCollectAt
                if nextTimestamp > 9999999999 then
                    nextTimestamp = nextTimestamp / 1000   -- convert ms → s
                end
            elseif type(nextCollectAt) == "string" then
                local y, mo, d, h, m, s = nextCollectAt:match(
                    "(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)"
                )
                if y then
                    nextTimestamp = os.time({
                        year  = tonumber(y),
                        month = tonumber(mo),
                        day   = tonumber(d),
                        hour  = tonumber(h) or 0,
                        min   = tonumber(m) or 0,
                        sec   = tonumber(s) or 0,
                    })
                end
            end

            if nextTimestamp and nextTimestamp > os.time() then
                return false, "cooldown_active"
            end
        end
    end

    -- Calculate a random payout
    local minPay = taxingRecord.payment_count_min or 1
    local maxPay = taxingRecord.payment_count_max or 1
    local amount = math.random(minPay, maxPay)

    -- Pay the collector
    sfr:addAccountMoney(playerId, "money", amount)

    -- Calculate next collection time
    local timeType  = taxingRecord.time_type  or "daily"
    local timeValue = taxingRecord.time_value or 1
    local nextCollectable = calculateNextCollectableAt(timeType, timeValue)

    -- Get collector display name
    local firstName, lastName = sfr:getUserName(playerId)
    local collectorName = firstName .. " " .. lastName

    -- Log a finance transaction for the organization
    if collectorOrgId then
        OrganizationFinanceDB:createTransaction(collectorOrgId, {
            type        = "deposit",
            amount      = amount,
            money_type  = "money",
            description = "Taxing collected: " .. (taxingRecord.label or "Unknown"),
            identifier  = playerIdentifier,
            name        = collectorName,
            status      = "completed",
            metadata    = json.encode({
                taxing_id      = taxingId,
                taxing_label   = taxingRecord.label,
                territory_id   = territoryId,
                collector_name = collectorName,
            }),
        })
    end

    -- Write the collection record to the DB
    db.createTaxingCollection({
        taxing_id             = taxingId,
        territory_id          = territoryId,
        organization_id       = collectorOrgId,
        collector_identifier  = playerIdentifier,
        collector_name        = collectorName,
        amount                = amount,
        next_collectable_at   = nextCollectable,
    })

    -- Award war score if there is an active territory war
    if warIsActive and activeWar and UpdateTerritoryWarScore then
        local warScore = (Config.CrimeTablet
            and Config.CrimeTablet.WarScore
            and Config.CrimeTablet.WarScore.TaxStolen)
            or 100

        UpdateTerritoryWarScore(activeWar.id, collectorOrgId, {
            score      = warScore,
            tax_stolen = 1,
        })
    end

    return true, nil, amount
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getTaxing"
--   Returns all taxing records enriched with their last
--   collection status (next_collectable_at, amount, collector).
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getTaxing", function()
    local allTaxing = db.getTaxing()

    for _, taxEntry in ipairs(allTaxing) do
        local status = db.getTaxingCollectionStatus(taxEntry.id)
        if status then
            taxEntry.last_collection = {
                next_collectable_at = status.next_collectable_at,
                amount              = status.amount,
                collector_name      = status.collector_name,
            }
        else
            taxEntry.last_collection = nil
        end
    end

    return allTaxing
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getTaxingCollectionStatus"
--   Returns the collection status for a taxing point,
--   converting the next_collectable_at field to a
--   human-readable "HH:MM:SS" string via `formatted_time`.
--   Returns nil if no status exists or cooldown has passed.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getTaxingCollectionStatus", function(_, taxingId)
    if not taxingId then return nil end

    local status = db.getTaxingCollectionStatus(taxingId)
    if not status then return nil end

    local nextCollectAt = status.next_collectable_at
    if nextCollectAt then
        local nextTimestamp = nil

        if type(nextCollectAt) == "number" then
            nextTimestamp = nextCollectAt
            if nextTimestamp > 9999999999 then
                nextTimestamp = nextTimestamp / 1000
            end

        elseif type(nextCollectAt) == "string" then
            -- Parse "YYYY-MM-DD HH:MM:SS" format
            local y, mo, d, h, m, s = nextCollectAt:match(
                "(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)"
            )
            if y and mo and d and h and m and s then
                nextTimestamp = os.time({
                    year  = tonumber(y)  or 0,
                    month = tonumber(mo) or 0,
                    day   = tonumber(d)  or 0,
                    hour  = tonumber(h)  or 0,
                    min   = tonumber(m)  or 0,
                    sec   = tonumber(s)  or 0,
                })
            end
        end

        if nextTimestamp then
            if nextTimestamp <= os.time() then
                -- Cooldown has expired
                return nil
            end

            -- Format the remaining time as HH:MM:SS
            status.formatted_time = os.date("%H:%M:%S", nextTimestamp)
        else
            status.formatted_time = "Unknown"
        end
    end

    return status
end)
