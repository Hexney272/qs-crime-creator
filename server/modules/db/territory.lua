-- ============================================================
-- server/modules/db/territory.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Territory CRUD database queries.
-- ============================================================

-- db.createTerritory(self/playerId, data)
--   data: { label, organization_id, zone, color }
function db.createTerritory(playerId, data)
    if not (data and data.label) then
        Error("db.createTerritory", "data and data.label must be provided")
        return nil
    end

    local creatorId = sfr:getIdentifier(playerId)

    local newId = MySQL.insert.await([[
        INSERT INTO qs_crime_territories (
            label, organization_id, zone_data, color, creator
        ) VALUES (?, ?, ?, ?, ?)
    ]], {
        data.label,
        data.organization_id or nil,
        json.encode(data.zone),
        data.color or nil,
        creatorId,
    })

    if newId then
        Debug("db.createTerritory", "Created territory:", newId)
        return newId
    end

    Error("db.createTerritory", "Failed to create territory")
    return nil
end

-- db.updateTerritory(self, zoneId, data)
function db.updateTerritory(self, zoneId, data)
    if not zoneId or not data then
        Error("db.updateTerritory", "zoneId and data must be provided")
        return false
    end

    local ok = MySQL.update.await([[
        UPDATE qs_crime_territories SET
            label = ?,
            organization_id = ?,
            zone_data = ?,
            color = ?
        WHERE id = ?
    ]], {
        data.label,
        data.organization_id or nil,
        json.encode(data.zone),
        data.color or "#eab308",
        zoneId,
    })

    if ok then
        Debug("db.updateTerritory", "Updated territory:", zoneId)
        return true
    end

    Error("db.updateTerritory", "Failed to update territory:", zoneId)
    return false
end

-- db.removeTerritory(zoneId)
function db.removeTerritory(zoneId)
    if not zoneId then
        Error("db.removeTerritory", "zoneId must be provided")
        return false
    end

    local ok = MySQL.query.await(
        "DELETE FROM qs_crime_territories WHERE id = ?", { zoneId })

    if ok then
        Debug("db.removeTerritory", "Removed territory:", zoneId)
        return true
    end

    Error("db.removeTerritory", "Failed to remove territory:", zoneId)
    return false
end

-- db.getTerritories()
--   Returns all territories joined with their owning
--   organization and boss member data.
function db.getTerritories()
    local rows = MySQL.query.await([[
        SELECT
            tz.*,
            o.id     as org_id,
            o.label  as org_label,
            o.color  as org_color,
            m.identifier as org_owner_identifier,
            m.name       as org_owner_name
        FROM qs_crime_territories tz
        LEFT JOIN qs_crime_organizations o
            ON tz.organization_id = o.id
        LEFT JOIN qs_crime_organization_members m
            ON o.id = m.organization_id AND m.is_boss = 1
        ORDER BY tz.created_at DESC
    ]])

    if not rows or #rows == 0 then
        Debug("db.getTerritories", "No territories found")
        return {}
    end

    for _, row in pairs(rows) do
        -- Decode zone_data JSON → .zone
        if row.zone_data then
            row.zone      = json.decode(row.zone_data)
            row.zone_data = nil
        end

        -- Fold org columns into a nested .organization table
        if row.org_id then
            row.organization = {
                id    = row.org_id,
                label = row.org_label,
                color = row.org_color,
                owner = row.org_owner_identifier and {
                    identifier = row.org_owner_identifier,
                    name       = row.org_owner_name,
                } or nil,
            }
        end

        row.org_id               = nil
        row.org_label            = nil
        row.org_color            = nil
        row.org_owner_identifier = nil
        row.org_owner_name       = nil
    end

    Debug("db.getTerritories", "Found territories:", #rows)
    return rows
end
