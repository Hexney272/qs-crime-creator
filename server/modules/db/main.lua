-- ============================================================
-- server/modules/db/main.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Core `db` global: in-memory cache system, season-pass CRUD,
-- graffiti CRUD, and season-pass-progress helpers.
-- All MySQL calls use oxmysql async/await (.await).
-- ============================================================

_G.db = { cache = {} }

-- ──────────────────────────────────────────────────────────
-- db.saveCache(self, name, data, id, ttlSeconds)
--   Stores `data` under `name` (+ optional `id` sub-key).
--   Default TTL is 1,000,000 seconds if not supplied.
-- ──────────────────────────────────────────────────────────
function db.saveCache(self, name, data, id, ttlSeconds)
    if not data then
        Debug("No data to save to cache", name, id)
        return
    end

    local expireAt = os.time() + (ttlSeconds or 3600000)

    self.cache[#self.cache + 1] = {
        name   = name,
        id     = id,
        time   = os.time(),
        expire = expireAt,
        data   = data,
    }

    Debug("db:saveCache", name, id)
end

-- ──────────────────────────────────────────────────────────
-- db.clearCache(self, name, id)
--   Removes all cache entries matching `name` (and optional `id`).
-- ──────────────────────────────────────────────────────────
function db.clearCache(self, name, id)
    local keepPredicate
    if not id then
        keepPredicate = function(entry) return entry.name ~= name end
    else
        keepPredicate = function(entry) return not (entry.name == name and entry.id == id) end
    end

    self.cache = table.filter(self.cache, keepPredicate)
    Debug("db:clearCache", name, id)
end

-- ──────────────────────────────────────────────────────────
-- db.getCache(self, name, id)
--   Looks up a cache entry by name (and optional id).
--   Returns the cached data, or nil if not found.
-- ──────────────────────────────────────────────────────────
function db.getCache(self, name, id)
    local matchPredicate
    if not id then
        matchPredicate = function(entry) return entry.name == name end
    else
        matchPredicate = function(entry) return entry.name == name and entry.id == id end
    end

    local entry = table.find(self.cache, matchPredicate)
    if entry then
        Debug("db:getCache", name, id)
        return entry.data
    end
    return nil
end

-- ──────────────────────────────────────────────────────────
-- local normalizeCoords(value)
--   Recursively converts plain {x,y,z,w} tables returned by
--   MySQL back into FiveM vector types.
-- ──────────────────────────────────────────────────────────
local function normalizeCoords(value)
    if type(value) ~= "table" then return value end

    -- vec4 detection
    if value.w and value.x and value.y and value.z then
        return vec4(value.x, value.y, value.z, value.w)
    end

    -- Recurse into nested tables
    for k, v in pairs(value) do
        if type(v) == "table" then
            value[k] = normalizeCoords(v)
        end
    end
    return value
end

-- ──────────────────────────────────────────────────────────
-- Season Pass CRUD
-- ──────────────────────────────────────────────────────────

-- db.createSeasonPass(self, data)
--   Creates a new season pass. If one already exists, updates it.
--   data: { endDate, price, rewards[] }
function db.createSeasonPass(self, data)
    if not data then
        Error("db.createSeasonPass", "data must be provided")
        return nil
    end
    if not data.endDate then
        Error("db.createSeasonPass", "endDate is required")
        return nil
    end

    -- If a season pass already exists, update it
    local existing = db.getSeasonPass()
    if existing then
        Debug("db.createSeasonPass", "Season pass already exists, updating instead of creating")
        local ok = db.updateSeasonPass(self, data)
        if ok then return existing.id end
        Error("db.createSeasonPass", "Failed to update existing season pass")
        return nil
    end

    local creatorIdentifier = sfr:getIdentifier(self)
    local rewards = data.rewards or {}
    if type(rewards) ~= "table" then rewards = {} end

    local newId = MySQL.insert.await([[
        INSERT INTO qs_crime_season_pass (
            price, end_date, rewards, creator
        ) VALUES (?, ?, ?, ?)
    ]], {
        data.price or 0,
        data.endDate,
        json.encode(rewards),
        creatorIdentifier,
    })

    if newId then
        db:clearCache("season_pass")
        Debug("db.createSeasonPass", "Created season pass:", newId)
        return newId
    end

    Error("db.createSeasonPass", "Failed to create season pass")
    return nil
end

-- db.updateSeasonPass(self, data)
--   Updates the existing season pass. Creates one if none exists.
function db.updateSeasonPass(self, data)
    if not data then
        Error("db.updateSeasonPass", "data must be provided")
        return false
    end
    if not data.endDate then
        Error("db.updateSeasonPass", "endDate is required")
        return false
    end

    local existing = db.getSeasonPass()
    if not existing then
        Debug("db.updateSeasonPass", "No season pass exists, creating new one")
        return db.createSeasonPass(self, data) ~= nil
    end

    local rewards = data.rewards or {}
    if type(rewards) ~= "table" then rewards = {} end

    if not data.endDate or data.endDate == "" then
        Error("db.updateSeasonPass", "endDate is required and cannot be empty")
        return false
    end

    Debug("db.updateSeasonPass", "Updating season pass:", existing.id, "with endDate:", data.endDate)

    local ok = MySQL.update.await([[
        UPDATE qs_crime_season_pass SET
            price = ?,
            end_date = ?,
            rewards = ?
        WHERE id = ?
    ]], {
        data.price or 0,
        data.endDate,
        json.encode(rewards),
        existing.id,
    })

    if ok then
        db:clearCache("season_pass")
        Debug("db.updateSeasonPass", "Updated season pass:", existing.id, "endDate:", data.endDate)
        return true
    end

    Error("db.updateSeasonPass", "Failed to update season pass")
    return false
end

-- db.getSeasonPass()
--   Returns the active season pass record or nil.
function db.getSeasonPass()
    local cached = db:getCache("season_pass")
    if cached then return cached end

    local rows = MySQL.query.await([[
        SELECT * FROM qs_crime_season_pass ORDER BY created_at DESC LIMIT 1
    ]])

    if not rows or #rows == 0 then
        Debug("db.getSeasonPass", "No season pass found")
        return nil
    end

    local sp = rows[1]

    -- Normalise end_date → endDate
    if sp.end_date and sp.end_date ~= "" then
        sp.endDate  = sp.end_date
        sp.end_date = nil
    else
        sp.endDate = nil
    end

    -- Decode rewards JSON
    if sp.rewards then
        local decoded = json.decode(sp.rewards)
        sp.rewards = (type(decoded) == "table") and decoded or {}
    else
        sp.rewards = {}
    end

    db:saveCache("season_pass", sp)
    return sp
end

-- db.removeSeasonPass()
function db.removeSeasonPass()
    local ok = MySQL.query.await("DELETE FROM qs_crime_season_pass")
    if ok then
        db:clearCache("season_pass")
        return true
    end
    Error("db.removeSeasonPass", "Failed to remove season pass")
    return false
end

-- db.resetSeasonPass()
function db.resetSeasonPass()
    Debug("db.resetSeasonPass", "Season pass reset requested")
    return true
end

-- ──────────────────────────────────────────────────────────
-- Graffiti CRUD
-- ──────────────────────────────────────────────────────────

-- db.createGraffiti(self/playerId, data)
function db.createGraffiti(playerId, data)
    if not data then
        Error("db.createGraffiti", "data must be provided")
        return nil
    end

    local identifier  = sfr:getIdentifier(playerId)
    local firstName, lastName = sfr:getUserName(playerId)
    local ownerName   = firstName .. " " .. lastName

    local newId = MySQL.insert.await([[
        INSERT INTO qs_crime_graffiti (
            label, font, coords, rotation, scale, color,
            owner_identifier, owner_name, organization_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.label   or "Graffiti",
        data.font    or (Config.Graffiti and Config.Graffiti.font),
        json.encode(data.coords),
        json.encode(data.rotation),
        data.scale   or 1.0,
        data.color   or "FFFFFFFF",
        identifier,
        ownerName,
        data.organization_id or nil,
    })

    if newId then
        Debug("db.createGraffiti", "Created graffiti:", newId)
        return newId
    end

    Error("db.createGraffiti", "Failed to create graffiti")
    return nil
end

-- db.updateGraffiti(self, graffitiId, data)
function db.updateGraffiti(self, graffitiId, data)
    if not graffitiId or not data then
        Error("db.updateGraffiti", "graffitiId and data must be provided")
        return false
    end

    local ok = MySQL.update.await([[
        UPDATE qs_crime_graffiti SET
            label = ?,
            font = ?,
            coords = ?,
            rotation = ?,
            scale = ?,
            color = ?,
            organization_id = ?
        WHERE id = ?
    ]], {
        data.label,
        data.font  or (Config.Graffiti and Config.Graffiti.font),
        json.encode(data.coords),
        json.encode(data.rotation),
        data.scale or 1.0,
        data.color or "FFFFFFFF",
        data.organization_id or nil,
        graffitiId,
    })

    if ok then
        Debug("db.updateGraffiti", "Updated graffiti:", graffitiId)
        return true
    end

    Error("db.updateGraffiti", "Failed to update graffiti:", graffitiId)
    return false
end

-- db.removeGraffiti(graffitiId)
function db.removeGraffiti(graffitiId)
    if not graffitiId then
        Error("db.removeGraffiti", "graffitiId must be provided")
        return false
    end

    local ok = MySQL.query.await("DELETE FROM qs_crime_graffiti WHERE id = ?", { graffitiId })
    if ok then
        Debug("db.removeGraffiti", "Removed graffiti:", graffitiId)
        return true
    end

    Error("db.removeGraffiti", "Failed to remove graffiti:", graffitiId)
    return false
end

-- db.getGraffitis()
--   Returns all graffiti records with coords/rotation decoded as vec3.
function db.getGraffitis()
    local rows = MySQL.query.await([[
        SELECT * FROM qs_crime_graffiti
        ORDER BY created_at DESC
    ]])

    if not rows or #rows == 0 then
        Debug("db.getGraffitis", "No graffitis found")
        return {}
    end

    for _, g in pairs(rows) do
        if g.coords then
            local c = json.decode(g.coords)
            g.coords = vec3(c.x, c.y, c.z)
        end
        if g.rotation then
            local r = json.decode(g.rotation)
            g.rotation = vec3(r.x, r.y, r.z)
        end
    end

    Debug("db.getGraffitis", "Found graffitis:", #rows)
    return rows
end

-- db.countNearbyGraffitis(coords, maxDistance)
--   Returns the number of graffiti within `maxDistance` of `coords`.
function db.countNearbyGraffitis(coords, maxDistance)
    if not coords or not maxDistance then
        Error("db.countNearbyGraffitis", "coords and maxDistance must be provided")
        return 0
    end

    local all   = db.getGraffitis()
    local count = 0
    for _, g in ipairs(all) do
        if g.coords and #(coords - g.coords) <= maxDistance then
            count = count + 1
        end
    end
    return count
end

-- db.getGraffiti(graffitiId)
--   Returns a single graffiti record or nil.
function db.getGraffiti(graffitiId)
    if not graffitiId then
        Error("db.getGraffiti", "graffitiId must be provided")
        return nil
    end

    local row = MySQL.prepare.await([[
        SELECT * FROM qs_crime_graffiti WHERE id = ?
    ]], { graffitiId })

    if not row then
        Debug("db.getGraffiti", "Graffiti not found:", graffitiId)
        return nil
    end

    if row.coords then
        local c = json.decode(row.coords)
        row.coords = vec3(c.x, c.y, c.z)
    end
    if row.rotation then
        local r = json.decode(row.rotation)
        row.rotation = vec3(r.x, r.y, r.z)
    end

    return row
end

-- ──────────────────────────────────────────────────────────
-- Season Pass Progress
-- ──────────────────────────────────────────────────────────

-- db.getOrganizationSeasonPassProgress(orgId, seasonPassId)
function db.getOrganizationSeasonPassProgress(orgId, seasonPassId)
    if not orgId or not seasonPassId then
        Error("db.getOrganizationSeasonPassProgress", "orgId and seasonPassId must be provided")
        return nil
    end

    local cacheKey = orgId .. "_" .. seasonPassId
    local cached   = db:getCache("season_pass_progress", cacheKey)
    if cached then return cached end

    local row = MySQL.single.await([[
        SELECT * FROM qs_crime_organization_seasonpass_progress
        WHERE organization_id = ? AND season_pass_id = ?
    ]], { orgId, seasonPassId })

    if row then
        row.level       = tonumber(row.level) or 1
        row.xp          = tonumber(row.xp)    or 0
        row.has_premium = row.has_premium == 1

        if row.claimed_rewards then
            local decoded = json.decode(row.claimed_rewards)
            row.claimed_rewards = (type(decoded) == "table") and decoded or {}
        else
            row.claimed_rewards = {}
        end

        db:saveCache("season_pass_progress", row, cacheKey)
    end

    return row
end

-- db.createOrUpdateOrganizationSeasonPassProgress(orgId, seasonPassId, data)
function db.createOrUpdateOrganizationSeasonPassProgress(orgId, seasonPassId, data)
    if not orgId or not seasonPassId then
        Error("db.createOrUpdateOrganizationSeasonPassProgress",
              "orgId and seasonPassId must be provided")
        return false
    end

    local claimedRewards = data.claimed_rewards or {}
    if type(claimedRewards) ~= "table" then claimedRewards = {} end

    local ok = MySQL.update.await([[
        INSERT INTO qs_crime_organization_seasonpass_progress (
            organization_id, season_pass_id, level, xp, has_premium, claimed_rewards
        ) VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            level = VALUES(level),
            xp = VALUES(xp),
            has_premium = VALUES(has_premium),
            claimed_rewards = VALUES(claimed_rewards)
    ]], {
        orgId,
        seasonPassId,
        data.level       or 1,
        data.xp          or 0,
        data.has_premium and 1 or 0,
        json.encode(claimedRewards),
    })

    if ok then
        local cacheKey = orgId .. "_" .. seasonPassId
        db:clearCache("season_pass_progress", cacheKey)
    end

    return ok ~= nil
end

-- db.claimSeasonPassReward(orgId, seasonPassId, level, tier)
function db.claimSeasonPassReward(orgId, seasonPassId, level, tier)
    if not (orgId and seasonPassId and level) or not tier then
        Error("db.claimSeasonPassReward", "orgId, seasonPassId, level and tier must be provided")
        return false
    end

    local progress = db.getOrganizationSeasonPassProgress(orgId, seasonPassId)
    if not progress then
        local created = db.createOrUpdateOrganizationSeasonPassProgress(
            orgId, seasonPassId,
            { level = 1, xp = 0, has_premium = false, claimed_rewards = {} }
        )
        if not created then return false end
        progress = db.getOrganizationSeasonPassProgress(orgId, seasonPassId)
    end

    local rewardKey = tostring(level) .. "-" .. tier
    local claimed   = progress.claimed_rewards or {}

    -- Already claimed?
    for _, k in ipairs(claimed) do
        if k == rewardKey then
            Debug("db.claimSeasonPassReward", "Reward already claimed:", rewardKey)
            return false
        end
    end

    table.insert(claimed, rewardKey)

    return db.createOrUpdateOrganizationSeasonPassProgress(orgId, seasonPassId, {
        level           = progress.level,
        xp              = progress.xp,
        has_premium     = progress.has_premium,
        claimed_rewards = claimed,
    })
end

-- db.setOrganizationSeasonPassPremium(orgId, seasonPassId, hasPremium)
function db.setOrganizationSeasonPassPremium(orgId, seasonPassId, hasPremium)
    if not orgId or not seasonPassId then
        Error("db.setOrganizationSeasonPassPremium", "orgId and seasonPassId must be provided")
        return false
    end

    local progress = db.getOrganizationSeasonPassProgress(orgId, seasonPassId)
    if not progress then
        return db.createOrUpdateOrganizationSeasonPassProgress(orgId, seasonPassId, {
            level = 1, xp = 0, has_premium = hasPremium, claimed_rewards = {},
        })
    end

    return db.createOrUpdateOrganizationSeasonPassProgress(orgId, seasonPassId, {
        level           = progress.level,
        xp              = progress.xp,
        has_premium     = hasPremium,
        claimed_rewards = progress.claimed_rewards,
    })
end
