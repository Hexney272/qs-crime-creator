-- ============================================================
-- server/modules/db/organization_stats.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Organization stats & XP queries (level, XP, missions,
-- territory wars won).  Uses INSERT … ON DUPLICATE KEY UPDATE
-- for atomic upserts.
-- ============================================================

-- db.getOrganizationStats(orgId)
function db.getOrganizationStats(orgId)
    if not orgId then
        Error("db.getOrganizationStats", "orgId must be provided")
        return nil
    end

    local cached = db:getCache("organization_stats", orgId)
    if cached then return cached end

    local row = MySQL.single.await([[
        SELECT * FROM qs_crime_organizations_stats
        WHERE organization_id = ?
    ]], { orgId })

    if row then
        row.level                   = tonumber(row.level)                   or 1
        row.xp                      = tonumber(row.xp)                      or 0
        row.total_missions          = tonumber(row.total_missions)          or 0
        row.total_territory_wars_won = tonumber(row.total_territory_wars_won) or 0

        db:saveCache("organization_stats", row, orgId)
    end

    return row
end

-- db.createOrUpdateOrganizationStats(orgId, data)
--   Upserts the stats row for `orgId`.
function db.createOrUpdateOrganizationStats(orgId, data)
    if not orgId then
        Error("db.createOrUpdateOrganizationStats", "orgId must be provided")
        return false
    end

    local ok = MySQL.update.await([[
        INSERT INTO qs_crime_organizations_stats (
            organization_id, level, xp, total_missions, total_territory_wars_won
        ) VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            level = VALUES(level),
            xp = VALUES(xp),
            total_missions = VALUES(total_missions),
            total_territory_wars_won = VALUES(total_territory_wars_won)
    ]], {
        orgId,
        data.level                   or 1,
        data.xp                      or 0,
        data.total_missions          or 0,
        data.total_territory_wars_won or 0,
    })

    if ok then
        db:clearCache("organization_stats",   orgId)
        db:clearCache("all_organization_stats")
        db:clearCache("organization_level",   orgId)
        db:clearCache("organization_rankings")
    end

    return ok ~= nil
end

-- db.addOrganizationXP(orgId, xp)
--   Atomically increments the XP for an organization.
function db.addOrganizationXP(orgId, xp)
    if not orgId or not xp then
        Error("db.addOrganizationXP", "orgId and xp must be provided")
        return false
    end

    local ok = MySQL.update.await([[
        INSERT INTO qs_crime_organizations_stats (
            organization_id, xp
        ) VALUES (?, ?)
        ON DUPLICATE KEY UPDATE
            xp = xp + ?
    ]], { orgId, xp, xp })

    if ok then
        db:clearCache("organization_stats",   orgId)
        db:clearCache("all_organization_stats")
        db:clearCache("organization_level",   orgId)
        db:clearCache("organization_rankings")
    end

    return ok ~= nil
end

-- db.getAllOrganizationStats()
--   Returns all org stats rows, sorted by XP descending.
function db.getAllOrganizationStats()
    local cached = db:getCache("all_organization_stats")
    if cached then return cached end

    local rows = MySQL.query.await([[
        SELECT * FROM qs_crime_organizations_stats
        ORDER BY xp DESC, level DESC
    ]]) or {}

    for _, row in ipairs(rows) do
        row.level                   = tonumber(row.level)                   or 1
        row.xp                      = tonumber(row.xp)                      or 0
        row.total_missions          = tonumber(row.total_missions)          or 0
        row.total_territory_wars_won = tonumber(row.total_territory_wars_won) or 0
    end

    db:saveCache("all_organization_stats", rows)
    return rows
end

-- db.getOrganizationLevelData(orgId)
--   Returns { level, experience, experienceToNext } for `orgId`.
--   Creates a default stats record if one doesn't exist yet.
function db.getOrganizationLevelData(orgId)
    if not orgId then
        Error("db.getOrganizationLevelData", "orgId must be provided")
        return nil
    end

    local cached = db:getCache("organization_level", orgId)
    if cached then return cached end

    local stats = db.getOrganizationStats(orgId)
    if not stats then
        -- Bootstrap with zeros
        db.createOrUpdateOrganizationStats(orgId, {
            level = 1, xp = 0,
            total_missions = 0, total_territory_wars_won = 0,
        })
        stats = db.getOrganizationStats(orgId)
    end

    if not stats then return nil end

    local level  = stats.level or 1
    local xp     = stats.xp   or 0
    local xpNext = Config.MissionSystem.XPFormula.LevelUpXP(level)

    local levelData = {
        level            = level,
        experience       = xp,
        experienceToNext = xpNext,
    }

    db:saveCache("organization_level", levelData, orgId)
    return levelData
end
