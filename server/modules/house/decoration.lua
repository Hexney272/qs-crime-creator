-- ============================================================
-- server/modules/house/decoration.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- In-memory house decoration state (per-house object lists),
-- server callbacks, and update / sell / buy events.
-- ============================================================

-- houseObjects[houseId] = { objectData, ... }
local houseObjects = {}

-- usedByMap[objectUniq] = playerId | nil
--   Tracks which player is currently editing a decoration.
local usedByMap = {}

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:saveObject"
--   Saves a new decoration to the DB, registers it in the
--   in-memory list, and broadcasts to all clients.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:saveObject", function(playerId, houseId, objectData)
    local creatorId   = sfr:getIdentifier(playerId)
    objectData.created = os.time()

    local newDbId     = db.saveObject(creatorId, objectData)
    objectData.id     = newDbId

    if not houseObjects[houseId] then
        houseObjects[houseId] = {}
    end
    houseObjects[houseId][#houseObjects[houseId] + 1] = objectData

    objectData.uniq = tostring("organization_house_" .. newDbId)

    TriggerClientEvent("crime:addObject", -1, houseId, objectData)

    Debug("crime:saveObject", "Saved", houseId, "Id", newDbId, "Data", objectData)
    return true
end)

-- Whitelist of fields that clients are allowed to update
local ALLOWED_UPDATE_FIELDS = {
    coords    = true,
    rotation  = true,
    inStash   = true,
    lightData = true,
}

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:updateObject"
--   Updates a decoration's transform / stash state in DB and
--   broadcasts the change to all clients.
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:updateObject", function(houseId, objectId, updateData)
    local playerId = source

    if not updateData then
        return Notification(playerId, i18n.t("decorate.invalid_data"), "error")
    end

    -- Security: reject any key not in the whitelist
    local unsecuredKey = table.find(updateData, function(_, key)
        return not ALLOWED_UPDATE_FIELDS[key]
    end)

    if unsecuredKey then
        Notification(playerId, i18n.t("decorate.invalid_data"), "error")
        Debug("unsecured", unsecuredKey)
        Debug("crime:updateObject", "User trying to exploit update profile event",
              playerId, updateData)
        return
    end

    -- Verify the object exists in this house
    local objectRecord = table.find(houseObjects[houseId] or {}, function(obj)
        return obj.id == objectId
    end)

    if not objectRecord then
        return Notification(playerId, i18n.t("decorate.invalid_object"), "error")
    end

    -- Write to DB
    local ok = db.updateObject(objectId, updateData)
    if not ok then
        Notification(playerId, i18n.t("decorate.failed_update"), "error")
        return
    end

    -- Update in-memory record; decode JSON strings for spatial fields
    for key, value in pairs(updateData) do
        if value and (key == "coords" or key == "rotation" or key == "lightData") then
            Debug("crime:updateObject", "Decoding", key, value)
            updateData[key] = json.decode(value)
        end
        objectRecord[key] = updateData[key]
    end

    TriggerClientEvent("crime:updateObject", -1, houseId, objectId, updateData)
    Debug("crime:updateObject", "Updated", houseId, "Id", objectId, "data", updateData)
end)

-- ──────────────────────────────────────────────────────────
-- local getFurniturePrice(modelName)
--   Looks up the price of a furniture item in Config.Furniture.
-- ──────────────────────────────────────────────────────────
local function getFurniturePrice(modelName)
    for categoryKey, category in pairs(Config.Furniture) do
        if categoryKey ~= "navigation" then
            for _, item in pairs(category.items) do
                if item.object == modelName then
                    return item.price
                end
                if item.colors then
                    for _, colorVariant in pairs(item.colors) do
                        if colorVariant.object == modelName then
                            return colorVariant.price
                        end
                    end
                end
            end
        end
    end
end

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:decorate:sellFurniture"
--   Removes an object from the house, deletes it from DB,
--   refunds the player a percentage of its original price,
--   and broadcasts the removal to all clients.
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:decorate:sellFurniture", function(houseId, objectId)
    local playerId = source

    local objectRecord = table.find(houseObjects[houseId] or {}, function(obj)
        return obj.id == objectId
    end)

    if not objectRecord then
        return Notification(playerId, i18n.t("decorate.invalid_object"), "error")
    end

    local ok = db.deleteObject(objectId)
    if not ok then
        Notification(playerId, i18n.t("decorate.failed_sell"), "error")
        return
    end

    -- Calculate sell-back value
    local originalPrice = getFurniturePrice(objectRecord.modelName) or 0
    local sellPrice     = originalPrice * Config.SellObjectCommision

    AddAccountMoney(playerId, Config.MoneyType, sellPrice)

    -- Remove from in-memory list
    houseObjects[houseId] = table.filter(
        houseObjects[houseId] or {},
        function(obj) return obj.id ~= objectId end
    )

    TriggerClientEvent("crime:decorate:sellFurniture", -1, houseId, objectId)
    Notification(playerId, i18n.t("decorate.sold_furniture", { price = sellPrice }), "success")
end)

-- ──────────────────────────────────────────────────────────
-- local getDecorations(houseId)
--   Returns the decoration list for `houseId`, loading from
--   DB on first access.  Defensive JSON decoding included.
-- ──────────────────────────────────────────────────────────
local function getDecorations(houseId)
    if not houseObjects[houseId] then
        local rows = db.getObjects(houseId)
        houseObjects[houseId] = rows or {}
    end

    -- Defensive: decode any fields still stored as JSON strings
    for key, value in pairs(houseObjects[houseId]) do
        if key == "coords" or key == "rotation" or key == "lightData" then
            if type(value) == "string" then
                houseObjects[key] = json.decode(value)
                Error("If you see this error please report this ERROR TO THE QUASAR. "
                    .. "It will not affect the server but it will help us to improve the script. "
                    .. "Thank you!")
            end
        end
    end

    return houseObjects[houseId] or {}
end

-- ──────────────────────────────────────────────────────────
-- ClearHouseDecoration(houseId)
--   Removes the in-memory cache for a house.
-- ──────────────────────────────────────────────────────────
function ClearHouseDecoration(houseId)
    houseObjects[houseId] = nil
    Debug("ClearHouseDecoration", houseId)
end

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getDecorations"
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getDecorations", function(playerId, houseId)
    local decorations = getDecorations(houseId)
    Debug("crime:getDecorations", houseId, "Decorations", decorations)
    return decorations or {}
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:buyDecorationObject"
--   Charges the player and returns true/false.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:buyDecorationObject", function(playerId, price)
    local balance = sfr:getAccountMoney(playerId, Config.MoneyType)
    if price <= balance then
        sfr:removeAccountMoney(playerId, Config.MoneyType, price)
        return true
    end
    return false
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:decorate:getDecorationAvailable"
--   Returns true if no player is currently editing this
--   decoration uniq key.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:decorate:getDecorationAvailable", function(_, uniqKey)
    local usedBy = usedByMap[uniqKey]
    Debug("crime:decorate:getDecorationAvailable", uniqKey, "UsedBy", usedBy)
    return not usedBy or usedBy
end)

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:decorate:updateDecorationUsedBy"
--   Marks a decoration as being edited by the sender (or
--   clears the lock when editing stops).
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:decorate:updateDecorationUsedBy", function(uniqKey, isEditing)
    local playerId = source
    usedByMap[uniqKey] = (isEditing and playerId) and playerId or nil
    Debug("crime:decorate:updateDecorationUsedBy", uniqKey, "UsedBy", isEditing)
end)

-- ──────────────────────────────────────────────────────────
-- playerDropped — release any decoration locks held by the
-- disconnecting player.
-- ──────────────────────────────────────────────────────────
AddEventHandler("playerDropped", function()
    local playerId = source
    for uniqKey, ownerId in pairs(usedByMap) do
        if ownerId == playerId then
            usedByMap[uniqKey] = nil
        end
    end
end)
