-- ============================================================
-- server/modules/ranking.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Organization leaderboard / ranking system.
-- Fetches all org stats, joins with org display data, sorts by
-- XP descending, caches for 60 s, and exposes via callback.
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- GetOrganizationRankings()
--   Returns a sorted array of organization ranking entries.
--   Each entry: { organization_id, organization, level, xp,
--                 total_missions, total_territory_wars_won }
--   Checks the DB cache first; on miss, rebuilds and saves.
-- ──────────────────────────────────────────────────────────
function GetOrganizationRankings()
    -- Try cache first (keyed as "organization_rankings")
    local cached = db:getCache("organization_rankings")
    if cached then return cached end

    -- Build fresh rankings from DB stats
    local allStats = db.getAllOrganizationStats()
    local rankings = {}

    for _, stats in ipairs(allStats) do
        local org = RecordManager:get("organizations", stats.organization_id)
        if org then
            rankings[#rankings + 1] = {
                organization_id = stats.organization_id,
                organization    = {
                    id    = org.id,
                    label = org.label,
                    color = org.color,
                },
                level                      = stats.level,
                xp                         = stats.xp,
                total_missions             = stats.total_missions,
                total_territory_wars_won   = stats.total_territory_wars_won,
            }
        end
    end

    -- Sort by XP descending (highest XP = rank 1)
    table.sort(rankings, function(a, b)
        return a.xp > b.xp
    end)

    -- Cache for 60 seconds
    db:saveCache("organization_rankings", rankings, nil, 60)

    return rankings
end

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getOrganizationRankings"
--   Returns the full rankings table to the requesting client.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getOrganizationRankings", function()
    return GetOrganizationRankings()
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getTerritories"
--   Returns all territory records from the database.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getTerritories", function()
    return db.getTerritories()
end)
