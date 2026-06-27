-- ============================================================
-- server/modules/db/garage.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Organization vehicle / garage database queries.
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- local helper: decode vehicle row fields (props, metadata)
-- ──────────────────────────────────────────────────────────
local function decodeVehicleRow(row, storeImageMap)
    if row.vehicle_props then
        row.vehicle_props = json.decode(row.vehicle_props)
    end
    if row.metadata then
        local meta = json.decode(row.metadata)
        row.metadata = meta
        if meta then
            row.last_spawned_by = meta.last_spawned_by
            row.last_spawned_at = meta.last_spawned_at
            row.image           = row.image or meta.image
        end
    end
    -- Fallback image from vehicle-store catalogue
    if not row.image and storeImageMap then
        row.image = storeImageMap[row.vehicle_model]
    end
    row.stored = (row.stored == 1)
    return row
end

-- ──────────────────────────────────────────────────────────
-- db.getOrganizationVehicles(orgId)
-- ──────────────────────────────────────────────────────────
function db.getOrganizationVehicles(orgId)
    if not orgId then
        Error("db.getOrganizationVehicles", "orgId must be provided")
        return {}
    end

    local cached = db:getCache("organization_vehicles", orgId)
    if cached then return cached end

    local rows = MySQL.query.await([[
        SELECT * FROM qs_crime_organization_vehicles
        WHERE organization_id = ?
        ORDER BY created_at DESC
    ]], { orgId })

    if not rows then return {} end

    -- Build model→image map from vehicle store
    local storeImageMap = {}
    for _, entry in ipairs(db.getVehicleStore()) do
        if entry.image then
            storeImageMap[entry.vehicle_model] = entry.image
        end
    end

    for _, row in ipairs(rows) do
        decodeVehicleRow(row, storeImageMap)
    end

    db:saveCache("organization_vehicles", rows, orgId)
    return rows
end

-- ──────────────────────────────────────────────────────────
-- db.getOrganizationVehicle(orgId, vehicleId)
-- ──────────────────────────────────────────────────────────
function db.getOrganizationVehicle(orgId, vehicleId)
    if not orgId or not vehicleId then
        Error("db.getOrganizationVehicle", "orgId and vehicleId must be provided")
        return nil
    end

    local cacheKey = orgId .. "_" .. vehicleId
    local cached   = db:getCache("organization_vehicle", cacheKey)
    if cached then return cached end

    local row = MySQL.single.await([[
        SELECT * FROM qs_crime_organization_vehicles
        WHERE organization_id = ? AND id = ?
    ]], { orgId, vehicleId })

    if row then
        decodeVehicleRow(row, nil)
        db:saveCache("organization_vehicle", row, cacheKey)
    end

    return row
end

-- ──────────────────────────────────────────────────────────
-- db.getOrganizationVehicleByPlate(orgId, plate)
-- ──────────────────────────────────────────────────────────
function db.getOrganizationVehicleByPlate(orgId, plate)
    if not orgId or not plate then
        Error("db.getOrganizationVehicleByPlate", "orgId and plate must be provided")
        return nil
    end

    local cacheKey = orgId .. "_" .. plate
    local cached   = db:getCache("organization_vehicle_plate", cacheKey)
    if cached then return cached end

    local row = MySQL.single.await([[
        SELECT * FROM qs_crime_organization_vehicles
        WHERE organization_id = ? AND plate = ?
    ]], { orgId, plate })

    if row then
        -- Try to get image from vehicle store if not in metadata
        if not row.image then
            for _, entry in ipairs(db.getVehicleStore()) do
                if entry.vehicle_model == row.vehicle_model and entry.image then
                    row.image = entry.image
                    break
                end
            end
        end
        decodeVehicleRow(row, nil)
        db:saveCache("organization_vehicle_plate", row, cacheKey)
    end

    return row
end

-- ──────────────────────────────────────────────────────────
-- db.addOrganizationVehicle(orgId, model, label, plate, props, metadata)
-- ──────────────────────────────────────────────────────────
function db.addOrganizationVehicle(orgId, vehicleModel, vehicleLabel, plate, extraProps, metadata)
    if not (orgId and vehicleModel and vehicleLabel) or not plate then
        Error("db.addOrganizationVehicle",
              "orgId, vehicleModel, vehicleLabel and plate must be provided")
        return nil
    end

    -- Build default props and merge extras
    local defaultProps = { model = vehicleModel, plate = plate,
                           fuel = 100, engine = 1000, body = 1000 }
    local props = {}
    for k, v in pairs(defaultProps) do props[k] = v end
    if extraProps then
        for k, v in pairs(extraProps) do props[k] = v end
    end

    local metaJson = metadata and json.encode(metadata) or nil

    local newId = MySQL.insert.await([[
        INSERT INTO qs_crime_organization_vehicles (
            organization_id, vehicle_model, vehicle_label, plate, vehicle_props, metadata, state
        ) VALUES (?, ?, ?, ?, ?, ?, 'garage')
    ]], {
        orgId, vehicleModel, vehicleLabel, plate,
        json.encode(props), metaJson,
    })

    if newId then
        db:clearCache("organization_vehicles", orgId)
        Debug("db.addOrganizationVehicle", "Added vehicle:", plate, "to organization:", orgId)
        return newId
    end

    Error("db.addOrganizationVehicle", "Failed to add vehicle:", plate, "to organization:", orgId)
    return nil
end

-- ──────────────────────────────────────────────────────────
-- db.updateOrganizationVehicleState(orgId, vehicleId, state, props, metadata)
--   state: "garage" (stored) | "world" (spawned)
-- ──────────────────────────────────────────────────────────
function db.updateOrganizationVehicleState(orgId, vehicleId, state, props, metadata)
    if not (orgId and vehicleId) or not state then
        Error("db.updateOrganizationVehicleState",
              "orgId, vehicleId and state must be provided")
        return false
    end

    local isStored  = (state == "garage")
    local setClauses = { "state = ?", "stored = ?" }
    local params     = { state, isStored and 1 or 0 }

    if props then
        setClauses[#setClauses + 1] = "vehicle_props = ?"
        params[#params + 1]         = json.encode(props)
    end
    if metadata then
        setClauses[#setClauses + 1] = "metadata = ?"
        params[#params + 1]         = json.encode(metadata)
    end

    params[#params + 1] = orgId
    params[#params + 1] = vehicleId

    local ok = MySQL.update.await(
        "UPDATE qs_crime_organization_vehicles SET "
        .. table.concat(setClauses, ", ")
        .. " WHERE organization_id = ? AND id = ?",
        params
    )

    if ok then
        db:clearCache("organization_vehicles", orgId)
        local cacheKey = orgId .. "_" .. vehicleId
        db:clearCache("organization_vehicle", cacheKey)
        -- Also clear plate cache
        local veh = db.getOrganizationVehicle(orgId, vehicleId)
        if veh and veh.plate then
            db:clearCache("organization_vehicle_plate", orgId .. "_" .. veh.plate)
        end
        Debug("db.updateOrganizationVehicleState", "Updated vehicle:", vehicleId, "state:", state)
        return true
    end

    Error("db.updateOrganizationVehicleState", "Failed to update vehicle:", vehicleId)
    return false
end

-- ──────────────────────────────────────────────────────────
-- db.updateOrganizationVehicleStateByPlate(orgId, plate, state, props)
-- ──────────────────────────────────────────────────────────
function db.updateOrganizationVehicleStateByPlate(orgId, plate, state, props)
    if not (orgId and plate) or not state then
        Error("db.updateOrganizationVehicleStateByPlate",
              "orgId, plate and state must be provided")
        return false
    end

    local isStored   = (state == "garage")
    local setClauses = { "state = ?", "stored = ?" }
    local params     = { state, isStored and 1 or 0 }

    if props then
        setClauses[#setClauses + 1] = "vehicle_props = ?"
        params[#params + 1]         = json.encode(props)
    end

    params[#params + 1] = orgId
    params[#params + 1] = plate

    local ok = MySQL.update.await(
        "UPDATE qs_crime_organization_vehicles SET "
        .. table.concat(setClauses, ", ")
        .. " WHERE organization_id = ? AND plate = ?",
        params
    )

    if ok then
        db:clearCache("organization_vehicles",       orgId)
        db:clearCache("organization_vehicle_plate",  orgId .. "_" .. plate)
        local veh = db.getOrganizationVehicleByPlate(orgId, plate)
        if veh and veh.id then
            db:clearCache("organization_vehicle", orgId .. "_" .. veh.id)
        end
        Debug("db.updateOrganizationVehicleStateByPlate", "Updated vehicle:", plate, "state:", state)
        return true
    end

    Error("db.updateOrganizationVehicleStateByPlate", "Failed to update vehicle:", plate)
    return false
end

-- ──────────────────────────────────────────────────────────
-- db.getOrganizationGarageSlotCount(orgId)
--   Returns the number of garage slots for the org based on
--   its current garage upgrade level.
-- ──────────────────────────────────────────────────────────
function db.getOrganizationGarageSlotCount(orgId)
    if not orgId then
        return Config.OrganizationGarage.DefaultSlots
    end

    local cached = db:getCache("garage_slots", orgId)
    if cached then return cached end

    local org = RecordManager:get("organizations", orgId)
    if not (org and org.upgrades) then
        local slots = Config.OrganizationGarage.DefaultSlots
        db:saveCache("garage_slots", slots, orgId)
        return slots
    end

    -- Find the garage upgrade record
    local garageUpgrade = nil
    for _, upg in ipairs(org.upgrades) do
        if upg.name == "garage" then
            garageUpgrade = upg
            break
        end
    end

    if not garageUpgrade then
        local slots = Config.OrganizationGarage.DefaultSlots
        db:saveCache("garage_slots", slots, orgId)
        return slots
    end

    -- Sum slot bonuses up to the current level
    local slots = Config.OrganizationGarage.DefaultSlots
    local upgradeConfig = nil
    for _, upg in ipairs(Config.Upgrades) do
        if upg.name == "garage" then upgradeConfig = upg break end
    end

    if upgradeConfig then
        for level = 1, garageUpgrade.level, 1 do
            local levelData = upgradeConfig.levels[level]
            if levelData then
                slots = slots + levelData.value
            end
        end
    end

    slots = math.min(slots, Config.OrganizationGarage.MaxSlots)
    db:saveCache("garage_slots", slots, orgId)
    return slots
end

-- ──────────────────────────────────────────────────────────
-- db.removeOrganizationVehicle(orgId, vehicleId)
-- ──────────────────────────────────────────────────────────
function db.removeOrganizationVehicle(orgId, vehicleId)
    if not orgId or not vehicleId then
        Error("db.removeOrganizationVehicle", "orgId and vehicleId must be provided")
        return false
    end

    -- Grab vehicle before deletion (for cache clearing)
    local veh = db.getOrganizationVehicle(orgId, vehicleId)

    local ok = MySQL.query.await([[
        DELETE FROM qs_crime_organization_vehicles
        WHERE organization_id = ? AND id = ?
    ]], { orgId, vehicleId })

    if ok then
        db:clearCache("organization_vehicles",  orgId)
        db:clearCache("organization_vehicle",   orgId .. "_" .. vehicleId)
        if veh and veh.plate then
            db:clearCache("organization_vehicle_plate", orgId .. "_" .. veh.plate)
        end
        Debug("db.removeOrganizationVehicle", "Removed vehicle:", vehicleId, "from organization:", orgId)
        return true
    end

    Error("db.removeOrganizationVehicle", "Failed to remove vehicle:", vehicleId)
    return false
end

-- ──────────────────────────────────────────────────────────
-- db.createVehicleActivity(orgId, vehicleId, label, plate, action, playerName, identifier)
-- ──────────────────────────────────────────────────────────
function db.createVehicleActivity(orgId, vehicleId, vehicleLabel, plate, action, playerName, identifier)
    if not (orgId and vehicleId and vehicleLabel and plate and action) or not playerName then
        Error("db.createVehicleActivity",
              "orgId, vehicleId, vehicleLabel, plate, action, and playerName must be provided")
        return false
    end

    local ok = MySQL.insert.await([[
        INSERT INTO qs_crime_vehicle_activities (
            organization_id, vehicle_id, vehicle_label, plate, action, player_name, identifier
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], { orgId, vehicleId, vehicleLabel, plate, action, playerName, identifier or nil })

    if ok then
        db:clearCache("vehicle_activities", orgId)
        Debug("db.createVehicleActivity", "Created activity:", action, "for vehicle:", plate)
        return true
    end

    Error("db.createVehicleActivity", "Failed to create activity")
    return false
end

-- ──────────────────────────────────────────────────────────
-- db.getVehicleActivities(orgId, limit)
-- ──────────────────────────────────────────────────────────
function db.getVehicleActivities(orgId, limit)
    if not orgId then
        Error("db.getVehicleActivities", "orgId must be provided")
        return {}
    end
    limit = limit or 50

    local cacheKey = orgId .. "_" .. limit
    local cached   = db:getCache("vehicle_activities", cacheKey)
    if cached then return cached end

    local sql = [[
        SELECT * FROM qs_crime_vehicle_activities
        WHERE organization_id = ?
        ORDER BY created_at DESC
    ]]
    if limit then
        sql = sql .. " LIMIT " .. tonumber(limit)
    end

    local rows = MySQL.query.await(sql, { orgId })
    if not rows then return {} end

    db:saveCache("vehicle_activities", rows, cacheKey)
    return rows
end
