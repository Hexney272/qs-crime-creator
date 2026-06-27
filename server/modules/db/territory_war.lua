-- ============================================================
-- server/modules/db/territory_war.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Territory war protection DB update.
-- ============================================================

-- db.updateTerritoryProtection(territoryId, protectionUntil)
--   Sets war_protection_until (if supplied) and last_war_at.
--   Falls back to updating only last_war_at if the column
--   doesn't exist.
function db.updateTerritoryProtection(territoryId, protectionUntil)
    if not territoryId then
        Error("db.updateTerritoryProtection", "territoryId must be provided")
        return false
    end

    local ok = nil

    if protectionUntil then
        ok = MySQL.update.await([[
            UPDATE qs_crime_territories SET
                war_protection_until = ?,
                last_war_at = NOW()
            WHERE id = ?
        ]], { protectionUntil, territoryId })
    end

    if not ok then
        ok = MySQL.update.await([[
            UPDATE qs_crime_territories SET
                last_war_at = NOW()
            WHERE id = ?
        ]], { territoryId })

        if ok and protectionUntil then
            Debug("db.updateTerritoryProtection",
                "war_protection_until column may not exist, only updated last_war_at")
        end
    end

    return ok ~= nil
end
