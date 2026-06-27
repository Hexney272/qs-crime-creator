-- ============================================================
-- server/modules/db/organization.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Organization CRUD, member management, rank management,
-- upgrade management, and the big JOIN-based getOrganizations
-- query that builds the full in-memory org graph.
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- Field-name maps used by the dynamic UPDATE builder
-- ──────────────────────────────────────────────────────────

-- JSON-serialised spatial / config fields
local JSON_FIELDS = {
    entry_coords    = "entry_coords",
    garage_coords   = "garage_coords",
    locations_coords = "locations_coords",
    zone_points     = "zone_points",
    interior_data   = "interior_data",
    mlo_data        = "mlo_data",
    ipl_data        = "ipl_data",
    blip            = "blip_data",
}

-- Plain scalar fields
local SCALAR_FIELDS = {
    label = "label",
    color = "color",
    type  = "interior_type",
}

-- ──────────────────────────────────────────────────────────
-- db.createOrganization(playerId, data)
--   data: { label, color?, owner?, entry_coords?, garage_coords?,
--           zone_points?, interior_type?, interior_data?,
--           mlo_data?, ipl_data?, blip? }
-- ──────────────────────────────────────────────────────────
function db.createOrganization(playerId, data)
    if not (data and data.label) then
        Error("db.createOrganization", "data and data.label must be provided")
        return nil
    end

    -- Prevent duplicate org membership
    if data.owner and data.owner.identifier then
        if db.isPlayerInAnyOrganization(data.owner.identifier) then
            Error("db.createOrganization",
                "Owner is already in another organization:", data.owner.identifier)
            return nil
        end
    end

    local creatorId = sfr:getIdentifier(playerId)

    local function enc(v) return v and json.encode(v) or nil end

    local newId = MySQL.insert.await([[
        INSERT INTO qs_crime_organizations (
            label, color,
            entry_coords, garage_coords, zone_points,
            interior_type, interior_data, mlo_data, ipl_data, blip_data, creator
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.label,
        data.color         or "#000000",
        enc(data.entry_coords),
        enc(data.garage_coords),
        enc(data.zone_points),
        data.type          or "",
        enc(data.interior_data),
        enc(data.mlo_data),
        enc(data.ipl_data),
        enc(data.blip),
        creatorId,
    })

    if newId then
        -- Add the owner as a boss member
        if data.owner and data.owner.identifier and data.owner.name then
            db.addOrganizationMember(
                playerId, newId, data.owner.identifier, data.owner.name, nil, true)
        end

        Debug("db.createOrganization", "Created organization:", newId)
        return newId
    end

    Error("db.createOrganization", "Failed to create organization")
    return nil
end

-- ──────────────────────────────────────────────────────────
-- db.updateOrganization(playerId, orgId, data)
--   Supports updating any combination of scalar fields,
--   JSON-blob fields, and the special `owner` key.
-- ──────────────────────────────────────────────────────────
function db.updateOrganization(playerId, orgId, data)
    if not orgId or not data then
        Error("db.updateOrganization", "orgId and data must be provided")
        return false
    end

    local setClauses  = {}
    local params      = {}
    local hasOwner    = false

    for key, value in pairs(data) do
        if key == "owner" then
            hasOwner = true

        elseif JSON_FIELDS[key] then
            setClauses[#setClauses + 1] = JSON_FIELDS[key] .. " = ?"
            params[#params + 1]         = value and json.encode(value) or nil

        elseif SCALAR_FIELDS[key] then
            setClauses[#setClauses + 1] = SCALAR_FIELDS[key] .. " = ?"
            params[#params + 1]         = value
        end
    end

    -- Handle owner change
    if hasOwner then
        local newOwner = data.owner

        if type(newOwner) == "table" and newOwner.identifier and newOwner.name then
            -- Validate: new owner must not already be in another org
            if db.isPlayerInAnyOrganization(newOwner.identifier, orgId) then
                Error("db.updateOrganization",
                    "New owner is already in another organization:", newOwner.identifier)
                return false
            end

            -- Demote current boss
            MySQL.update.await(
                "UPDATE qs_crime_organization_members SET is_boss = FALSE WHERE organization_id = ?",
                { orgId })

            -- Upsert new boss member
            db.addOrganizationMember(
                playerId, orgId, newOwner.identifier, newOwner.name, nil, true)

        elseif newOwner == false then
            -- Remove owner
            MySQL.query(
                "DELETE FROM qs_crime_organization_members WHERE organization_id = ? AND is_boss = 1",
                { orgId })
        end
    end

    if #setClauses == 0 then
        if hasOwner then
            Debug("db.updateOrganization", "Updated organization owner:", orgId)
            return true
        end
        Error("db.updateOrganization", "No fields to update")
        return false
    end

    params[#params + 1] = orgId

    local ok = MySQL.update.await(
        "UPDATE qs_crime_organizations SET "
        .. table.concat(setClauses, ", ")
        .. " WHERE id = ?",
        params
    )

    if ok then
        Debug("db.updateOrganization", "Updated organization:", orgId,
            "Fields:", table.concat(setClauses, ", "))
        return true
    end

    Error("db.updateOrganization", "Failed to update organization:", orgId)
    return false
end

-- ──────────────────────────────────────────────────────────
-- db.removeOrganization(orgId)
-- ──────────────────────────────────────────────────────────
function db.removeOrganization(orgId)
    if not orgId then
        Error("db.removeOrganization", "orgId must be provided")
        return false
    end

    local ok = MySQL.query.await(
        "DELETE FROM qs_crime_organizations WHERE id = ?", { orgId })

    if ok then
        Debug("db.removeOrganization", "Removed organization:", orgId)
        return true
    end

    Error("db.removeOrganization", "Failed to remove organization:", orgId)
    return false
end

-- ──────────────────────────────────────────────────────────
-- db.getOrganizations()
--   Returns all orgs with nested members, ranks, and upgrades
--   assembled from a single JOIN query.
-- ──────────────────────────────────────────────────────────
function db.getOrganizations()
    local rows = MySQL.query.await([[
        SELECT
            o.*,

            m.id         as member_id,
            m.identifier as member_identifier,
            m.name       as member_name,
            m.rank_id    as member_rank_id,
            m.is_boss    as member_is_boss,
            m.joined_at  as member_joined_at,

            r.id          as rank_id,
            r.label       as rank_label,
            r.permissions as rank_permissions,

            rm.id          as member_rank_id_full,
            rm.label       as member_rank_label,
            rm.permissions as member_rank_permissions,

            u.upgrade_name,
            u.level as upgrade_level
        FROM qs_crime_organizations o
        LEFT JOIN qs_crime_organization_members m  ON o.id = m.organization_id
        LEFT JOIN qs_crime_organization_ranks r    ON o.id = r.organization_id
        LEFT JOIN qs_crime_organization_ranks rm   ON m.rank_id = rm.id
        LEFT JOIN qs_crime_organization_upgrades u ON o.id = u.organization_id
        ORDER BY o.created_at DESC, m.is_boss DESC, m.joined_at ASC
    ]])

    if not rows or #rows == 0 then
        Debug("db.getOrganizations", "No organizations found")
        return {}
    end

    local orgs    = {}   -- ordered list
    local orgMap  = {}   -- id → org table (for dedup during iteration)

    for _, row in pairs(rows) do
        local orgId = row.id

        -- Create org entry if not seen yet
        if not orgMap[orgId] then
            local org = {
                id           = orgId,
                label        = row.label,
                color        = row.color,
                creator      = row.creator,
                created_at   = row.created_at,
                updated_at   = row.updated_at,
                type         = row.interior_type,
                members      = {},
                ranks        = {},
                upgrades     = {},
                owner        = nil,
            }

            -- Decode JSON spatial blobs
            local function dec(v) return v and json.decode(v) or nil end
            org.entry_coords    = dec(row.entry_coords)
            org.garage_coords   = dec(row.garage_coords)
            org.locations_coords = dec(row.locations_coords)
            org.zone_points     = dec(row.zone_points)
            org.interior_data   = dec(row.interior_data)
            org.mlo_data        = dec(row.mlo_data)
            org.ipl_data        = dec(row.ipl_data)
            org.blip            = dec(row.blip_data)
            org.vault_codes     = dec(row.vault_codes)

            orgMap[orgId] = org
            orgs[#orgs + 1] = org
        end

        local org = orgMap[orgId]

        -- Append member (dedup by member_id)
        if row.member_id then
            local alreadyAdded = false
            for _, m in ipairs(org.members) do
                if m.id == row.member_id then alreadyAdded = true break end
            end

            if not alreadyAdded then
                local member = {
                    id              = row.member_id,
                    organization_id = orgId,
                    identifier      = row.member_identifier,
                    name            = row.member_name,
                    rank_id         = row.member_rank_id,
                    is_boss         = row.member_is_boss,
                    joined_at       = row.member_joined_at,
                }

                if member.is_boss then
                    org.owner = { identifier = member.identifier, name = member.name }
                end

                -- Attach member rank data
                if row.member_rank_id_full then
                    member.rank = {
                        id              = row.member_rank_id_full,
                        organization_id = orgId,
                        label           = row.member_rank_label,
                        permissions     = row.member_rank_permissions
                                          and json.decode(row.member_rank_permissions) or nil,
                    }
                end

                org.members[#org.members + 1] = member
            end
        end

        -- Append rank (dedup by rank_id)
        if row.rank_id then
            local alreadyAdded = false
            for _, r in ipairs(org.ranks) do
                if r.id == row.rank_id then alreadyAdded = true break end
            end

            if not alreadyAdded then
                org.ranks[#org.ranks + 1] = {
                    id              = row.rank_id,
                    organization_id = orgId,
                    label           = row.rank_label,
                    permissions     = row.rank_permissions
                                      and json.decode(row.rank_permissions) or nil,
                }
            end
        end

        -- Append upgrade (dedup by upgrade_name)
        if row.upgrade_name then
            local alreadyAdded = false
            for _, u in ipairs(org.upgrades) do
                if u.name == row.upgrade_name then alreadyAdded = true break end
            end

            if not alreadyAdded then
                org.upgrades[#org.upgrades + 1] = {
                    name  = row.upgrade_name,
                    level = tonumber(row.upgrade_level) or 0,
                }
            end
        end
    end

    Debug("db.getOrganizations", "Found organizations:", #orgs)
    return orgs
end

-- ──────────────────────────────────────────────────────────
-- db.isPlayerInAnyOrganization(identifier, excludeOrgId?)
--   Returns true if the player is a member of any org other
--   than excludeOrgId (nil = check all orgs).
-- ──────────────────────────────────────────────────────────
function db.isPlayerInAnyOrganization(identifier, excludeOrgId)
    if not identifier then return false end

    local row = MySQL.single.await([[
        SELECT COUNT(*) as count FROM qs_crime_organization_members
        WHERE identifier = ? AND (? IS NULL OR organization_id != ?)
    ]], { identifier, excludeOrgId, excludeOrgId })

    return row and (tonumber(row.count) or 0) > 0 or false
end

-- ──────────────────────────────────────────────────────────
-- db.addOrganizationMember(playerId, orgId, identifier, name, rankId, isBoss)
--   Uses INSERT … ON DUPLICATE KEY UPDATE so re-inviting a
--   player who already left (and is rejoining) is safe.
-- ──────────────────────────────────────────────────────────
function db.addOrganizationMember(playerId, orgId, identifier, name, rankId, isBoss)
    if not (orgId and identifier) or not name then
        Error("db.addOrganizationMember",
              "orgId, identifier and name must be provided")
        return nil
    end

    if db.isPlayerInAnyOrganization(identifier, orgId) then
        Error("db.addOrganizationMember",
              "Player is already in another organization:", identifier)
        return nil
    end

    rankId = rankId or nil
    isBoss = isBoss or false

    -- If adding a new boss, demote previous boss first
    if isBoss then
        MySQL.update.await(
            "UPDATE qs_crime_organization_members SET is_boss = FALSE WHERE organization_id = ?",
            { orgId })
    end

    local newId = MySQL.insert.await([[
        INSERT INTO qs_crime_organization_members (
            organization_id, identifier, name, rank_id, is_boss
        ) VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            name    = VALUES(name),
            rank_id = VALUES(rank_id),
            is_boss = VALUES(is_boss)
    ]], {
        orgId, identifier, name, rankId, isBoss and 1 or 0,
    })

    if newId then
        Debug("db.addOrganizationMember", "Added member:", identifier,
            "to organization:", orgId, "is_boss:", isBoss)
        return newId
    end

    Error("db.addOrganizationMember", "Failed to add member:", identifier,
        "to organization:", orgId)
    return nil
end

-- ──────────────────────────────────────────────────────────
-- db.updateOrganizationMember(playerId, orgId, identifier, rankId)
-- ──────────────────────────────────────────────────────────
function db.updateOrganizationMember(playerId, orgId, identifier, rankId)
    if not orgId or not identifier then
        Error("db.updateOrganizationMember", "orgId and identifier must be provided")
        return false
    end

    local setClauses = {}
    local params     = {}

    if rankId ~= nil then
        setClauses[#setClauses + 1] = "rank_id = ?"
        params[#params + 1]         = rankId
    end

    if #setClauses == 0 then
        Error("db.updateOrganizationMember", "No updates provided")
        return false
    end

    params[#params + 1] = orgId
    params[#params + 1] = identifier

    local ok = MySQL.update.await(
        "UPDATE qs_crime_organization_members SET "
        .. table.concat(setClauses, ", ")
        .. " WHERE organization_id = ? AND identifier = ?",
        params
    )

    if ok then
        Debug("db.updateOrganizationMember", "Updated member:", identifier,
            "in organization:", orgId)
        return true
    end

    Error("db.updateOrganizationMember", "Failed to update member:", identifier,
        "in organization:", orgId)
    return false
end

-- ──────────────────────────────────────────────────────────
-- db.removeOrganizationMember(orgId, identifier)
-- ──────────────────────────────────────────────────────────
function db.removeOrganizationMember(orgId, identifier)
    if not orgId or not identifier then
        Error("db.removeOrganizationMember",
              "orgId and identifier must be provided")
        return false
    end

    local ok = MySQL.query.await(
        "DELETE FROM qs_crime_organization_members "
        .. "WHERE organization_id = ? AND identifier = ?",
        { orgId, identifier }
    )

    if ok then
        Debug("db.removeOrganizationMember", "Removed member:", identifier,
            "from organization:", orgId)
        return true
    end

    Error("db.removeOrganizationMember", "Failed to remove member:", identifier,
        "from organization:", orgId)
    return false
end

-- ──────────────────────────────────────────────────────────
-- db.addOrganizationRank(playerId, orgId, label, permissions)
-- ──────────────────────────────────────────────────────────
function db.addOrganizationRank(playerId, orgId, label, permissions)
    if not orgId or not label then
        Error("db.addOrganizationRank", "orgId and label must be provided")
        return nil
    end

    local permsJson = permissions and json.encode(permissions) or nil

    local newId = MySQL.insert.await([[
        INSERT INTO qs_crime_organization_ranks (organization_id, label, permissions)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE
            label       = VALUES(label),
            permissions = VALUES(permissions)
    ]], { orgId, label, permsJson })

    if newId then
        Debug("db.addOrganizationRank", "Added rank:", label, "to organization:", orgId)
        return newId
    end

    Error("db.addOrganizationRank", "Failed to add rank:", label, "to organization:", orgId)
    return nil
end

-- ──────────────────────────────────────────────────────────
-- db.updateOrganizationRank(playerId, rankId, label, permissions)
-- ──────────────────────────────────────────────────────────
function db.updateOrganizationRank(playerId, rankId, label, permissions)
    if not rankId then
        Error("db.updateOrganizationRank", "rankId must be provided")
        return false
    end

    local setClauses = {}
    local params     = {}

    if label then
        setClauses[#setClauses + 1] = "label = ?"
        params[#params + 1]         = label
    end
    if permissions ~= nil then
        setClauses[#setClauses + 1] = "permissions = ?"
        params[#params + 1]         = permissions and json.encode(permissions) or nil
    end

    if #setClauses == 0 then
        Error("db.updateOrganizationRank", "No updates provided")
        return false
    end

    params[#params + 1] = rankId

    local ok = MySQL.update.await(
        "UPDATE qs_crime_organization_ranks SET "
        .. table.concat(setClauses, ", ")
        .. " WHERE id = ?",
        params
    )

    if ok then
        Debug("db.updateOrganizationRank", "Updated rank:", rankId)
        return true
    end

    Error("db.updateOrganizationRank", "Failed to update rank:", rankId)
    return false
end

-- ──────────────────────────────────────────────────────────
-- db.removeOrganizationRank(rankId)
-- ──────────────────────────────────────────────────────────
function db.removeOrganizationRank(rankId)
    if not rankId then
        Error("db.removeOrganizationRank", "rankId must be provided")
        return false
    end

    local ok = MySQL.query.await(
        "DELETE FROM qs_crime_organization_ranks WHERE id = ?", { rankId })

    if ok then
        Debug("db.removeOrganizationRank", "Removed rank:", rankId)
        return true
    end

    Error("db.removeOrganizationRank", "Failed to remove rank:", rankId)
    return false
end

-- ──────────────────────────────────────────────────────────
-- db.setOrganizationUpgrade(playerId, orgId, upgradeName, level)
-- ──────────────────────────────────────────────────────────
function db.setOrganizationUpgrade(playerId, orgId, upgradeName, level)
    if not (orgId and upgradeName) or not level then
        Error("db.setOrganizationUpgrade",
              "orgId, upgradeName and level must be provided")
        return false
    end

    local ok = MySQL.insert.await([[
        INSERT INTO qs_crime_organization_upgrades (organization_id, upgrade_name, level)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE level = VALUES(level)
    ]], { orgId, upgradeName, level })

    if ok then
        Debug("db.setOrganizationUpgrade", "Set upgrade:", upgradeName,
            "to level:", level, "for organization:", orgId)
        return true
    end

    Error("db.setOrganizationUpgrade", "Failed to set upgrade:", upgradeName,
        "for organization:", orgId)
    return false
end
