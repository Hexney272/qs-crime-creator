-- ============================================================
-- server/modules/garage.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Organization garage server callbacks: listing vehicles,
-- spawning, storing, impound retrieval, vehicle store,
-- vehicle purchasing, selling, and activity logs.
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getOrganizationVehicles"
--   Returns org vehicles, marking any that are currently
--   spawned in the world as state = "out".
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getOrganizationVehicles", function(playerId, orgId)
    if not orgId then return {} end

    if not sv_bossmenu:hasPermission(playerId, orgId, "canAccessGarage") then
        Error("crime:getOrganizationVehicles", "Permission denied for garage",
            playerId, orgId)
        return {}
    end

    local vehicles = db.getOrganizationVehicles(orgId)
    if not vehicles or #vehicles == 0 then return {} end

    -- Build a set of plates currently present in the world
    local worldPlates = {}
    for _, entity in ipairs(GetAllVehicles()) do
        if DoesEntityExist(entity) then
            local plate = GetVehicleNumberPlateText(entity)
            if plate then
                plate = plate:gsub("^%s*(.-)%s*$", "%1")
                worldPlates[plate] = true
            end
        end
    end

    for _, veh in ipairs(vehicles) do
        if worldPlates[veh.plate] then
            veh.state  = "out"
            veh.stored = false
        end
    end

    return vehicles
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:spawnOrganizationVehicle"
--   Marks a vehicle as "out" and fires the client spawn event.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:spawnOrganizationVehicle", function(playerId, orgId, vehicleId)
    if not orgId or not vehicleId then return false end

    if not sv_bossmenu:hasPermission(playerId, orgId, "canAccessGarage") then
        Error("crime:spawnOrganizationVehicle", "Permission denied for garage",
            playerId, orgId)
        return false
    end

    local vehicle = db.getOrganizationVehicle(orgId, vehicleId)
    if not vehicle then
        Error("crime:spawnOrganizationVehicle", "Vehicle not found", vehicleId)
        return false
    end
    if vehicle.state == "out" then
        Debug("crime:spawnOrganizationVehicle", "Vehicle is already out", vehicleId)
        return false
    end

    local identifier = sfr:getIdentifier(playerId)
    local first, last = sfr:getUserName(playerId)
    local playerName  = first .. " " .. last

    -- Update metadata with spawn info
    local meta = vehicle.metadata or {}
    if type(meta) == "string" then meta = json.decode(meta) or {} end
    meta.last_spawned_by         = playerName
    meta.last_spawned_at         = os.date("%Y-%m-%d %H:%M:%S")
    meta.last_spawned_identifier = identifier

    db.updateOrganizationVehicleState(orgId, vehicleId, "out", nil, meta)

    db.createVehicleActivity(orgId, vehicleId, vehicle.vehicle_label, vehicle.plate,
        "spawn", playerName, identifier)

    TriggerClientEvent("crime:spawnOrganizationVehicle", playerId, orgId, vehicleId, vehicle)
    return true
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:storeOrganizationVehicle"
--   Captures vehicle props client-side then marks it garage.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:storeOrganizationVehicle", function(playerId, orgId, plate)
    if not orgId or not plate then return false end

    if not sv_bossmenu:hasPermission(playerId, orgId, "canAccessGarage") then
        Error("crime:storeOrganizationVehicle", "Permission denied for garage",
            playerId, orgId)
        return false
    end

    local vehicle = db.getOrganizationVehicleByPlate(orgId, plate)
    if not vehicle then
        Error("crime:storeOrganizationVehicle", "Vehicle not found", plate)
        return false
    end
    if vehicle.state == "garage" then return false end

    -- Check garage capacity
    local slots     = db.getOrganizationGarageSlotCount(orgId)
    local allVehs   = db.getOrganizationVehicles(orgId)
    local storedCnt = 0
    for _, v in ipairs(allVehs) do
        if v.state == "garage" then storedCnt = storedCnt + 1 end
    end
    if slots <= storedCnt then return false end

    -- Fetch props from the client
    local props = lib.callback.await("crime:getVehicleProps", playerId, plate)

    db.updateOrganizationVehicleStateByPlate(orgId, plate, "garage", props)

    local identifier = sfr:getIdentifier(playerId)
    local first, last = sfr:getUserName(playerId)
    local playerName = first .. " " .. last

    db.createVehicleActivity(orgId, vehicle.id, vehicle.vehicle_label, plate,
        "store", playerName, identifier)

    return true
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:retrieveVehicleFromImpound"
--   Pays the impound fee and moves the vehicle to garage.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:retrieveVehicleFromImpound", function(playerId, orgId, vehicleId)
    if not orgId or not vehicleId then return false end

    if not sv_bossmenu:hasPermission(playerId, orgId, "canAccessGarage") then
        Error("crime:retrieveVehicleFromImpound", "Permission denied for garage",
            playerId, orgId)
        return false
    end

    local vehicle = db.getOrganizationVehicle(orgId, vehicleId)
    if not vehicle then
        Error("crime:retrieveVehicleFromImpound", "Vehicle not found", vehicleId)
        return false
    end
    if vehicle.state ~= "impound" then return false end

    local impoundPrice = Config.OrganizationGarage.ImpoundPrice
    local balance      = sfr:getAccountMoney(playerId, "money")

    if impoundPrice > balance then
        Notification(playerId, i18n.t("not_enough_money", { amount = impoundPrice }), "error")
        return false
    end

    -- Check garage capacity
    local slots     = db.getOrganizationGarageSlotCount(orgId)
    local allVehs   = db.getOrganizationVehicles(orgId)
    local storedCnt = 0
    for _, v in ipairs(allVehs) do
        if v.state == "garage" then storedCnt = storedCnt + 1 end
    end
    if slots <= storedCnt then
        Notification(playerId, i18n.t("garage_full"), "error")
        return false
    end

    sfr:removeAccountMoney(playerId, "money", impoundPrice)

    local identifier = sfr:getIdentifier(playerId)
    local first, last = sfr:getUserName(playerId)
    local playerName = first .. " " .. last

    db.updateOrganizationVehicleState(orgId, vehicleId, "garage")
    db.createVehicleActivity(orgId, vehicleId, vehicle.vehicle_label, vehicle.plate,
        "retrieve_impound", playerName, identifier)

    Notification(playerId, i18n.t("vehicle_retrieved_from_impound"), "success")
    return true
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getOrganizationVehicleByPlate"
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getOrganizationVehicleByPlate", function(playerId, orgId, plate)
    if not orgId or not plate then return nil end
    if not sv_bossmenu:hasPermission(playerId, orgId, "canAccessGarage") then return nil end
    return db.getOrganizationVehicleByPlate(orgId, plate)
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getOrganizationGarageSlotCount"
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getOrganizationGarageSlotCount", function(_, orgId)
    if not orgId then return Config.OrganizationGarage.DefaultSlots end
    return db.getOrganizationGarageSlotCount(orgId)
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getVehicleStore"
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getVehicleStore", function(playerId, orgId)
    if not orgId then return {} end

    if not sv_bossmenu:hasPermission(playerId, orgId, "canAccessVehicleStore") then
        Error("crime:getVehicleStore", "Permission denied for vehicle store",
            playerId, orgId)
        return {}
    end

    return db.getVehicleStore()
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:purchaseVehicle"
--   Validates availability / budget, generates a plate,
--   inserts the vehicle record, and deducts org clean money.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:purchaseVehicle", function(playerId, orgId, storeItemId, extraProps)
    if not orgId or not storeItemId then return false end

    if not sv_bossmenu:hasPermission(playerId, orgId, "canAccessVehicleStore") then
        Error("crime:purchaseVehicle", "Permission denied for vehicle store",
            playerId, orgId)
        return false
    end

    -- Find the store item
    local storeItems = db.getVehicleStore()
    local storeItem  = table.find(storeItems, function(i) return i.id == storeItemId end)
    if not storeItem then
        Error("crime:purchaseVehicle", "Vehicle not found in store", storeItemId)
        return false
    end

    -- Check if limited item is expired
    if storeItem.limited and storeItem.limited_end_date then
        local endDate    = storeItem.limited_end_date
        local endTimeSec = nil

        if type(endDate) == "string" then
            local yr, mo, dy, hr, mn =
                endDate:sub(1,4), endDate:sub(6,7), endDate:sub(9,10),
                endDate:sub(12,13), endDate:sub(15,16)
            if yr and mo and dy then
                endTimeSec = os.time({
                    year  = tonumber(yr), month = tonumber(mo), day = tonumber(dy),
                    hour  = tonumber(hr) or 0, min = tonumber(mn) or 0, sec = 0,
                })
            end
        end

        if endTimeSec and endTimeSec < os.time() then
            Notification(playerId, i18n.t("bossmenu.vehicle_store.expired"), "error")
            return false
        end

        if storeItem.limited_quantity ~= -1 then
            if not storeItem.limited_quantity or storeItem.limited_quantity <= 0 then
                Notification(playerId, i18n.t("bossmenu.vehicle_store.out_of_stock"), "error")
                return false
            end
        end
    end

    -- Check garage capacity
    local slots     = db.getOrganizationGarageSlotCount(orgId)
    local allVehs   = db.getOrganizationVehicles(orgId)
    local storedCnt = 0
    for _, v in ipairs(allVehs) do
        if v.state == "garage" then storedCnt = storedCnt + 1 end
    end
    if slots <= storedCnt then
        Notification(playerId, i18n.t("garage_full"), "error")
        return false
    end

    -- Check org balance
    local finance    = OrganizationFinanceDB:getFinanceOverview(orgId)
    local cleanMoney = (finance and finance.clean_money) or 0
    Debug("clean_money", cleanMoney, storeItem.price)

    if cleanMoney < storeItem.price then
        Notification(playerId,
            i18n.t("boss_not_enough_money", { amount = storeItem.price }), "error")
        return false
    end

    -- Generate unique plate
    local plate = string.upper(
        string.sub(storeItem.vehicle_model, 1, 3) .. math.random(1000, 9999))

    local meta = { image = storeItem.image, original_price = storeItem.price }

    local newVehId = db.addOrganizationVehicle(
        orgId, storeItem.vehicle_model, storeItem.vehicle_label, plate, extraProps, meta)

    if not newVehId then
        Error("crime:purchaseVehicle", "Failed to add vehicle to garage", orgId, storeItemId)
        return false
    end

    -- Deduct from org finance
    local deducted = OrganizationFinanceDB:updateMoney(orgId, storeItem.price, "withdraw", "clean")
    if not deducted then
        db.removeOrganizationVehicle(orgId, newVehId)
        Error("crime:purchaseVehicle", "Failed to deduct money from organization finance",
            orgId, storeItem.price)
        return false
    end

    -- Finance transaction log
    local identifier = sfr:getIdentifier(playerId)
    local first, last = sfr:getUserName(playerId)
    local playerName = first .. " " .. last

    OrganizationFinanceDB:createTransaction(orgId, {
        type        = "expense",
        amount      = -storeItem.price,
        money_type  = "money",
        description = "Vehicle purchase: " .. storeItem.vehicle_label,
        reference   = "vehicle_store_" .. storeItemId,
        identifier  = identifier,
        name        = playerName,
        status      = "completed",
    })

    -- Decrement limited quantity if applicable
    if storeItem.limited and storeItem.limited_quantity ~= -1
       and storeItem.limited_quantity and storeItem.limited_quantity > 0 then
        MySQL.update.await([[
            UPDATE qs_crime_vehicle_store SET limited_quantity = limited_quantity - 1 WHERE id = ?
        ]], { storeItemId })
    end

    Notification(playerId, i18n.t("bossmenu.vehicle_store.purchase_success"), "success")
    return true
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getVehicleActivities"
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getVehicleActivities", function(playerId, orgId)
    if not orgId then return {} end

    if not sv_bossmenu:hasPermission(playerId, orgId, "canAccessGarage") then
        Error("crime:getVehicleActivities", "Permission denied for garage", playerId, orgId)
        return {}
    end

    return db.getVehicleActivities(orgId, 50)
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getVehicleSellPrice"
--   Returns the sell-back price for a stored vehicle.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getVehicleSellPrice", function(playerId, orgId, vehicleId)
    if not orgId or not vehicleId then return nil end

    if not sv_bossmenu:hasPermission(playerId, orgId, "canAccessGarage") then
        Error("crime:getVehicleSellPrice", "Permission denied for garage", playerId, orgId)
        return nil
    end

    local vehicle = db.getOrganizationVehicle(orgId, vehicleId)
    if not vehicle then
        Error("crime:getVehicleSellPrice", "Vehicle not found", vehicleId)
        return nil
    end

    local sellPercent = Config.OrganizationGarage.SellPricePercent or 30
    local origPrice   = 10000

    local meta = vehicle.metadata
    if meta then
        if type(meta) == "string" then meta = json.decode(meta) or meta end
        if type(meta) == "table" and meta.original_price then
            origPrice = tonumber(meta.original_price) or origPrice
        end
    end

    return math.floor(origPrice * (sellPercent / 100))
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:sellOrganizationVehicle"
--   Adds sale proceeds to org finance, removes the vehicle.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:sellOrganizationVehicle", function(playerId, orgId, vehicleId)
    if not orgId or not vehicleId then return false end

    if not sv_bossmenu:hasPermission(playerId, orgId, "canAccessGarage") then
        Error("crime:sellOrganizationVehicle", "Permission denied for garage",
            playerId, orgId)
        return false
    end

    local vehicle = db.getOrganizationVehicle(orgId, vehicleId)
    if not vehicle then
        Error("crime:sellOrganizationVehicle", "Vehicle not found", vehicleId)
        return false
    end
    if vehicle.state == "out" then
        Notification(playerId, i18n.t("bossmenu.garage.cannot_sell_vehicle_out"), "error")
        return false
    end

    local sellPercent = Config.OrganizationGarage.SellPricePercent or 30
    local origPrice   = 10000

    local meta = vehicle.metadata
    if meta then
        if type(meta) == "string" then meta = json.decode(meta) or meta end
        if type(meta) == "table" and meta.original_price then
            origPrice = tonumber(meta.original_price) or origPrice
        end
    end

    local sellPrice = math.floor(origPrice * (sellPercent / 100))

    -- Credit org
    local credited = OrganizationFinanceDB:updateMoney(orgId, sellPrice, "deposit", "clean")
    if not credited then
        Error("crime:sellOrganizationVehicle",
            "Failed to add money to organization finance", orgId, sellPrice)
        return false
    end

    local identifier = sfr:getIdentifier(playerId)
    local first, last = sfr:getUserName(playerId)
    local playerName = first .. " " .. last

    OrganizationFinanceDB:createTransaction(orgId, {
        type        = "deposit",
        amount      = sellPrice,
        money_type  = "money",
        description = "Vehicle sold: " .. vehicle.vehicle_label,
        reference   = "vehicle_sold_" .. vehicleId,
        identifier  = identifier,
        name        = playerName,
        status      = "completed",
    })

    db.createVehicleActivity(orgId, vehicleId, vehicle.vehicle_label, vehicle.plate,
        "sell", playerName, identifier)

    local removed = db.removeOrganizationVehicle(orgId, vehicleId)
    if not removed then
        -- Rollback the credit
        OrganizationFinanceDB:updateMoney(orgId, sellPrice, "withdraw", "clean")
        Error("crime:sellOrganizationVehicle", "Failed to remove vehicle", vehicleId)
        return false
    end

    sv_bossmenu:triggerEvent(orgId, "crime:updateBossMenuGarage")
    Notification(playerId, i18n.t("bossmenu.garage.vehicle_sold", {
        vehicle = vehicle.vehicle_label, price = sellPrice,
    }), "success")

    return true
end)
