-- ============================================================
-- server/modules/db/taxing.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Taxing CRUD, territory-by-location lookup,
-- and collection record management.
-- ============================================================

-- db.createTaxing(playerId, data)
--   data: { label, territory_id, payment_count_min,
--           payment_count_max, location, time_type, time_value }
function db.createTaxing(playerId, data)
    if not (data and data.label) then
        Error("db.createTaxing", "data and data.label must be provided")
        return nil
    end
    if not data.territory_id then
        Error("db.createTaxing", "territory_id is required")
        return nil
    end

    local creatorId = sfr:getIdentifier(playerId)

    -- Try to auto-resolve territory_id from location if missing
    local territoryId = data.territory_id
    if not territoryId then
        local loc = data.location
        if loc then
            if type(loc) == "string" then loc = json.decode(loc) end
            if loc and loc.x and loc.y then
                territoryId = db.findTerritoryByLocation(loc)
            end
        end
    end

    if not territoryId then
        Error("db.createTaxing", "territory_id is required")
        return nil
    end

    local locationJson = data.location and json.encode(data.location) or nil

    local newId = MySQL.insert.await([[
        INSERT INTO qs_crime_taxing (
            label, payment_count_min, payment_count_max, location,
            territory_id, time_type, time_value, creator
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.label,
        data.payment_count_min or 1,
        data.payment_count_max or 1,
        locationJson,
        territoryId,
        data.time_type  or "daily",
        data.time_value or 1,
        creatorId,
    })

    if newId then
        Debug("db.createTaxing", "Created taxing:", newId)
        return newId
    end

    Error("db.createTaxing", "Failed to create taxing")
    return nil
end

-- db.updateTaxing(self, taxingId, data)
function db.updateTaxing(self, taxingId, data)
    if not taxingId or not data then
        Error("db.updateTaxing", "taxingId and data must be provided")
        return false
    end
    if not data.territory_id then
        Error("db.updateTaxing", "territory_id is required")
        return false
    end

    local territoryId = data.territory_id
    if not territoryId then
        local loc = data.location
        if loc then
            if type(loc) == "string" then loc = json.decode(loc) end
            if loc and loc.x and loc.y then
                territoryId = db.findTerritoryByLocation(loc)
            end
        end
    end

    if not territoryId then
        Error("db.updateTaxing", "territory_id is required")
        return false
    end

    local locationJson = data.location and json.encode(data.location) or nil

    local ok = MySQL.update.await([[
        UPDATE qs_crime_taxing SET
            label             = ?,
            payment_count_min = ?,
            payment_count_max = ?,
            location          = ?,
            territory_id      = ?,
            time_type         = ?,
            time_value        = ?
        WHERE id = ?
    ]], {
        data.label,
        data.payment_count_min or 1,
        data.payment_count_max or 1,
        locationJson,
        territoryId,
        data.time_type  or "daily",
        data.time_value or 1,
        taxingId,
    })

    if ok then
        Debug("db.updateTaxing", "Updated taxing:", taxingId)
        return true
    end

    Error("db.updateTaxing", "Failed to update taxing:", taxingId)
    return false
end

-- db.removeTaxing(taxingId)
function db.removeTaxing(taxingId)
    if not taxingId then
        Error("db.removeTaxing", "taxingId must be provided")
        return false
    end

    local ok = MySQL.query.await(
        "DELETE FROM qs_crime_taxing WHERE id = ?", { taxingId })

    if ok then
        Debug("db.removeTaxing", "Removed taxing:", taxingId)
        return true
    end

    Error("db.removeTaxing", "Failed to remove taxing:", taxingId)
    return false
end

-- db.getTaxing()
--   Returns all taxing records with location decoded.
function db.getTaxing()
    local rows = MySQL.query.await([[
        SELECT * FROM qs_crime_taxing ORDER BY created_at DESC
    ]])

    if not rows or #rows == 0 then
        Debug("db.getTaxing", "No taxing found")
        return {}
    end

    for _, row in pairs(rows) do
        if row.location then
            row.location = json.decode(row.location)
        end
    end

    return rows
end

-- db.findTerritoryByLocation(coords)
--   Does a point-in-polygon test against all territory zones
--   and returns the matching territory ID, or nil.
function db.findTerritoryByLocation(coords)
    if not (coords and coords.x and coords.y) then return nil end

    local territories = RecordManager:getAll("territories") or {}

    for _, territory in ipairs(territories) do
        local zone = territory.zone_data or territory.zone
        if zone then
            if type(zone) == "string" then zone = json.decode(zone) end
        end

        if zone and zone.topPoint and zone.bottomPoint then
            local top    = zone.topPoint
            local bot    = zone.bottomPoint
            local width  = zone.width or 50.0

            local dx = bot.x - top.x
            local dy = bot.y - top.y
            local len = math.sqrt(dx * dx + dy * dy)

            if len ~= 0 then
                local perpX = (-dy / len) * (width / 2)
                local perpY = ( dx / len) * (width / 2)

                local corners = {
                    { x = top.x + perpX, y = top.y + perpY },
                    { x = top.x - perpX, y = top.y - perpY },
                    { x = bot.x - perpX, y = bot.y - perpY },
                    { x = bot.x + perpX, y = bot.y + perpY },
                }

                -- Ray-casting point-in-polygon
                local px, py  = coords.x, coords.y
                local inside  = false
                local n       = #corners

                for i = 1, n do
                    local j  = i + 1
                    if j > n then j = 1 end
                    local xi, yi = corners[i].x, corners[i].y
                    local xj, yj = corners[j].x, corners[j].y

                    if (py < yi) ~= (py < yj) then
                        local intersectX = (xj - xi) * (py - yi) / (yj - yi) + xi
                        if px < intersectX then
                            inside = not inside
                        end
                    end
                end

                if inside then return territory.id end
            end
        end
    end

    return nil
end

-- db.getTaxingCollectionStatus(taxingId)
--   Returns the most recent collection record for a taxing point.
function db.getTaxingCollectionStatus(taxingId)
    if not taxingId then return nil end

    return MySQL.single.await([[
        SELECT * FROM qs_crime_taxing_collections
        WHERE taxing_id = ?
        ORDER BY created_at DESC
        LIMIT 1
    ]], { taxingId })
end

-- db.getTaxingCollections(taxingId)
--   Returns all collection records for a taxing point.
function db.getTaxingCollections(taxingId)
    if not taxingId then return {} end

    return MySQL.query.await([[
        SELECT * FROM qs_crime_taxing_collections
        WHERE taxing_id = ?
        ORDER BY created_at DESC
    ]], { taxingId }) or {}
end

-- db.createTaxingCollection(data)
--   Logs a completed taxing collection.
function db.createTaxingCollection(data)
    if not (data and data.taxing_id and data.organization_id
            and data.collector_identifier) then
        Error("db.createTaxingCollection", "Required fields missing")
        return nil
    end

    local newId = MySQL.insert.await([[
        INSERT INTO qs_crime_taxing_collections (
            taxing_id, territory_id, organization_id,
            collector_identifier, collector_name, amount, next_collectable_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.taxing_id,
        data.territory_id,
        data.organization_id,
        data.collector_identifier,
        data.collector_name      or "",
        data.amount              or 0,
        data.next_collectable_at,
    })

    if newId then
        Debug("db.createTaxingCollection", "Created collection:", newId)
        return newId
    end

    Error("db.createTaxingCollection", "Failed to create collection")
    return nil
end

-- db.updateTaxingTerritoryMapping(taxingId)
--   Looks up the taxing point's stored location and tries to
--   find and save the matching territory ID.
function db.updateTaxingTerritoryMapping(taxingId)
    if not taxingId then
        Error("db.updateTaxingTerritoryMapping", "taxingId must be provided")
        return false
    end

    local row = MySQL.single.await(
        "SELECT location FROM qs_crime_taxing WHERE id = ?", { taxingId })

    if not (row and row.location) then
        Error("db.updateTaxingTerritoryMapping", "Taxing or location not found:", taxingId)
        return false
    end

    local coords = json.decode(row.location)
    if not (coords and coords.x and coords.y) then
        Error("db.updateTaxingTerritoryMapping", "Invalid location data:", taxingId)
        return false
    end

    local territoryId = db.findTerritoryByLocation(coords)

    local ok = MySQL.update.await(
        "UPDATE qs_crime_taxing SET territory_id = ? WHERE id = ?",
        { territoryId, taxingId }
    )

    if ok then
        Debug("db.updateTaxingTerritoryMapping",
            "Updated territory mapping for taxing:", taxingId, "territory:", territoryId)
        return true
    end

    return false
end
