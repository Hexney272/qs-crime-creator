-- ============================================================
-- client/modules/organization/garage/nui.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- NUI callback handlers for the organization garage panel.
-- ============================================================

local function cbAwait(name, ...)
    local ok, result = pcall(lib.callback.await, name, ...)
    if not ok then
        Error("cbAwait ::: " .. tostring(name), result)
        return nil
    end
    return result
end

-- ──────────────────────────────────────────────────────────
-- NUI callback: "organization_garage:spawn_vehicle"
--   Spawns an organization vehicle by vehicleId, then
--   refreshes the vehicle list in the UI and closes the garage.
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("organization_garage:spawn_vehicle", function(payload, cb)
    if not (payload and payload.organizationId and payload.vehicleId) then
        return cb(false)
    end

    local org = OrganizationManager:get(payload.organizationId)
    if not (org and org.garage) then
        return cb(false)
    end

    -- Ask the server to spawn the vehicle
    local success = cbAwait(
        "crime:spawnOrganizationVehicle", false,
        payload.organizationId, payload.vehicleId
    )

    cb(success)

    if success then
        -- Refresh the vehicle list after spawning
        local updatedVehicles = cbAwait(
            "crime:getOrganizationVehicles", false, payload.organizationId
        ) or {}

        org.garage.vehicles = updatedVehicles

        SendReactMessage("organization_garage:update_vehicles", {
            vehicles = updatedVehicles,
        })

        org.garage:close()
    end
end)

-- ──────────────────────────────────────────────────────────
-- NUI callback: "organization_garage:retrieve_from_impound"
--   Retrieves a vehicle from the impound lot, then refreshes
--   the vehicle list in the UI.
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("organization_garage:retrieve_from_impound", function(payload, cb)
    if not (payload and payload.organizationId and payload.vehicleId) then
        return cb(false)
    end

    local org = OrganizationManager:get(payload.organizationId)
    if not (org and org.garage) then
        return cb(false)
    end

    local success = cbAwait(
        "crime:retrieveVehicleFromImpound", false,
        payload.organizationId, payload.vehicleId
    )

    cb(success)

    if success then
        local updatedVehicles = cbAwait(
            "crime:getOrganizationVehicles", false, payload.organizationId
        ) or {}

        org.garage.vehicles = updatedVehicles

        SendReactMessage("organization_garage:update_vehicles", {
            vehicles = updatedVehicles,
        })
    end
end)

-- ──────────────────────────────────────────────────────────
-- NUI callback: "organization_garage:close"
--   Closes the garage UI for the given organization.
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("organization_garage:close", function(payload, cb)
    if payload and payload.organizationId then
        local org = OrganizationManager:get(payload.organizationId)
        if org and org.garage then
            org.garage:close()
        end
    end
    cb("ok")
end)

-- ──────────────────────────────────────────────────────────
-- NUI callback: "organization_garage:get_slot_count"
--   Returns the number of garage slots for the organization.
--   Falls back to Config.OrganizationGarage.DefaultSlots if
--   the server callback returns nothing.
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("organization_garage:get_slot_count", function(payload, cb)
    if not (payload and payload.organizationId) then
        return cb(Config.OrganizationGarage.DefaultSlots)
    end

    local slotCount = cbAwait(
        "crime:getOrganizationGarageSlotCount", false, payload.organizationId
    )

    cb(slotCount or Config.OrganizationGarage.DefaultSlots)
end)
