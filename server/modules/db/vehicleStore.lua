-- ============================================================
-- server/modules/db/vehicleStore.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Vehicle store (shop) CRUD queries.
-- ============================================================

-- local: convert a MySQL timestamp / Unix-ms number to a
-- "YYYY-MM-DD HH:MM:SS" string for storage.
local function toDatetimeString(value)
    if not value then return nil end
    if type(value) == "string" then return value end
    -- Assume Unix milliseconds
    local seconds = math.floor(value / 1000)
    return os.date("%Y-%m-%d %H:%M:%S", seconds)
end

-- local: parse "YYYY-MM-DD HH:MM:SS" or a number into Unix ms.
local function parseDatetime(value)
    if not value then return nil end
    if type(value) == "number" then return value end

    local y, mo, d, h, m, s = value:match(
        "^(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)$"
    )
    if y and mo and d then
        local t = os.time({
            year  = tonumber(y),
            month = tonumber(mo),
            day   = tonumber(d),
            hour  = tonumber(h) or 0,
            min   = tonumber(m) or 0,
            sec   = tonumber(s) or 0,
        })
        return t * 1000
    end
    return nil
end

-- db.createVehicleStore(self/playerId, data)
--   data: { vehicle_model, vehicle_label, description, image,
--           price, limited, limited_end_date, limited_quantity }
function db.createVehicleStore(playerId, data)
    if not (data and data.vehicle_model and data.vehicle_label and data.price) then
        Error("db.createVehicleStore",
              "data, vehicle_model, vehicle_label, and price must be provided")
        return
    end

    local creatorId     = sfr:getIdentifier(playerId)
    local endDateStr    = toDatetimeString(data.limited_end_date)

    local newId = MySQL.insert.await([[
        INSERT INTO qs_crime_vehicle_store (
            vehicle_model, vehicle_label, description, image, price,
            limited, limited_end_date, limited_quantity, creator
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.vehicle_model,
        data.vehicle_label,
        data.description     or nil,
        data.image           or nil,
        data.price,
        data.limited and 1 or 0,
        endDateStr,
        data.limited_quantity or nil,
        creatorId,
    })

    if newId then
        Debug("db.createVehicleStore", "Created vehicle store:", newId)
        return newId
    end

    Error("db.createVehicleStore", "Failed to create vehicle store")
    return nil
end

-- db.updateVehicleStore(self, vehicleStoreId, data)
function db.updateVehicleStore(self, vehicleStoreId, data)
    if not vehicleStoreId or not data then
        Error("db.updateVehicleStore", "vehicleStoreId and data must be provided")
        return false
    end

    local endDateStr = toDatetimeString(data.limited_end_date)

    local ok = MySQL.update.await([[
        UPDATE qs_crime_vehicle_store SET
            vehicle_model    = ?,
            vehicle_label    = ?,
            description      = ?,
            image            = ?,
            price            = ?,
            limited          = ?,
            limited_end_date = ?,
            limited_quantity = ?
        WHERE id = ?
    ]], {
        data.vehicle_model,
        data.vehicle_label,
        data.description     or nil,
        data.image           or nil,
        data.price,
        data.limited and 1 or 0,
        endDateStr,
        data.limited_quantity or nil,
        vehicleStoreId,
    })

    if ok then
        Debug("db.updateVehicleStore", "Updated vehicle store:", vehicleStoreId)
        return true
    end

    Error("db.updateVehicleStore", "Failed to update vehicle store:", vehicleStoreId)
    return false
end

-- db.removeVehicleStore(vehicleStoreId)
function db.removeVehicleStore(vehicleStoreId)
    if not vehicleStoreId then
        Error("db.removeVehicleStore", "vehicleStoreId must be provided")
        return false
    end

    local ok = MySQL.query.await(
        "DELETE FROM qs_crime_vehicle_store WHERE id = ?",
        { vehicleStoreId }
    )

    if ok then
        Debug("db.removeVehicleStore", "Removed vehicle store:", vehicleStoreId)
        return true
    end

    Error("db.removeVehicleStore", "Failed to remove vehicle store:", vehicleStoreId)
    return false
end

-- db.getVehicleStore()
--   Returns all vehicle-store entries, normalising the
--   limited boolean and converting limited_end_date to ms.
function db.getVehicleStore()
    local rows = MySQL.query.await([[
        SELECT * FROM qs_crime_vehicle_store ORDER BY created_at DESC
    ]])

    if not rows or #rows == 0 then
        Debug("db.getVehicleStore", "No vehicle store found")
        return {}
    end

    for _, row in ipairs(rows) do
        row.limited = row.limited == 1

        if row.limited_end_date then
            row.limited_end_date = parseDatetime(row.limited_end_date)
        end
    end

    Debug("db.getVehicleStore", "Found vehicle store:", #rows)
    return rows
end
