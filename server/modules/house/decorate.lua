-- ============================================================
-- server/modules/house/decorate.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- SQL helpers for house decoration objects:
-- save, get, update, delete (single + all for a house).
-- ============================================================

local SQL = {
    INSERT_OBJECT = [[
        INSERT INTO qs_crime_house_decorations (creator, house, modelName, coords, rotation, inStash, inHouse, created, uniq, lightData)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]],
    DELETE_OBJECT  = [[ DELETE FROM qs_crime_house_decorations WHERE id = ? ]],
    SELECT_OBJECTS = [[ SELECT * FROM qs_crime_house_decorations WHERE house = ? ]],
}

-- db.saveObject(creatorId, data)
--   Inserts a new decoration record and returns its DB id.
function db.saveObject(creatorId, data)
    local lightDataJson = nil
    if data.lightData then
        lightDataJson = json.encode(data.lightData)
    end

    local newId = MySQL.insert.await(SQL.INSERT_OBJECT, {
        creatorId,
        data.house,
        data.modelName,
        json.encode(data.coords),
        json.encode(data.rotation),
        data.inStash,
        data.inHouse,
        os.date("%Y-%m-%d %H:%M:%S"),
        data.uniq,
        lightDataJson,
    })

    Debug("db.saveObject", "Saved", data.insideId, "Id", newId, "Data", data)
    return newId
end

-- db.getObjects(houseId)
--   Returns all decoration records for a house with coords and
--   rotation decoded from JSON, and timestamps normalised.
function db.getObjects(houseId)
    local rows = MySQL.query.await(SQL.SELECT_OBJECTS, { houseId })

    for i = 1, #rows do
        local row = rows[i]

        row.coords   = json.decode(row.coords)
        row.rotation = json.decode(row.rotation)

        -- Convert created timestamp (ms) to Lua time table
        local ts = os.date("*t", math.floor(row.created / 1000))
        row.created = os.time(ts)

        -- Fallback uniq key if not stored
        if not row.uniq then
            row.uniq = tostring("house_" .. row.id)
        end

        -- Decode optional light data
        if row.lightData then
            row.lightData = json.decode(row.lightData)
        end
    end

    return rows
end

-- db.updateObject(objectId, data)
--   Dynamically builds an UPDATE statement for the supplied
--   key/value pairs and executes it.
function db.updateObject(objectId, data)
    if not data then
        Debug("db.updateObject", "No data to update")
        return false
    end

    Debug("db.updateObject", data)

    local sql    = "UPDATE qs_crime_house_decorations SET"
    local params = {}

    for key, value in pairs(data) do
        sql = sql .. string.format(" `%s` = :%s,", key, key)

        -- Treat false as NULL except for boolean columns
        if value == false and key ~= "inStash" and key ~= "inHouse" then
            value = nil
            Debug("db.updateObject", "Set", key, "to nil because of false")
        end
        params[key] = value
    end

    -- Strip trailing comma
    sql = sql:sub(1, -2) .. " WHERE id = :id"
    params.id = objectId

    Debug("params", params)
    return MySQL.update.await(sql, params)
end

-- db.deleteObject(objectId)
function db.deleteObject(objectId)
    MySQL.prepare(SQL.DELETE_OBJECT, { objectId })
    return true
end

-- db.deleteAllObjects(houseId)
--   Removes all decorations for a house from the DB and
--   clears the server-side decoration cache.
function db.deleteAllObjects(houseId)
    Debug("db.deleteAllObjects", houseId)
    ClearHouseDecoration(houseId)
    MySQL.prepare.await(
        "DELETE FROM qs_crime_house_decorations WHERE house = ?",
        { houseId }
    )
    return true
end
