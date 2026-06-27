-- ============================================================
-- server/modules/house/main.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- House entry/exit tracking, anti-teleport (FiveGuard) hooks,
-- MLO door sync, vault-code management, and stash registration.
-- ============================================================

PlayerDefaultRoutings = {}
HouseRoutings         = {}

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:onInsideHouse"
--   Fires when a player enters or leaves a house interior.
--   Updates the sfr "houseInside" state.
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:onInsideHouse", function(houseId, isInside)
    local playerId = source
    sfr:setHouseInside(playerId, isInside and houseId or nil)
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getHouseInside"
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getHouseInside", function(playerId)
    return sfr:getHouseInside(playerId)
end)

-- ──────────────────────────────────────────────────────────
-- FiveGuard anti-teleport / freecam bypass events
-- ──────────────────────────────────────────────────────────

RegisterNetEvent("crime:enableAntiTeleport", function()
    local playerId = source
    if not Config.FiveGuard then return end

    exports[Config.FiveGuard].SetTempPermission(
        playerId, "Client", "BypassTeleport", true, false)
end)

RegisterNetEvent("crime:fiveguard:freecam", function(enabled)
    local playerId = source
    if not Config.FiveGuard then return end

    exports[Config.FiveGuard].SetTempPermission(
        playerId, "Client", "BypassFreecam", enabled, enabled, false)
    exports[Config.FiveGuard].SetTempPermission(
        playerId, "Client", "BypassNoclip",  enabled, enabled, false)
end)

RegisterNetEvent("crime:disableAntiTeleport", function()
    local playerId = source
    if not Config.FiveGuard then return end

    exports[Config.FiveGuard].SetTempPermission(
        playerId, "Client", "BypassTeleport", false, false)
end)

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:syncDoor"
--   Updates door locked state in the org's MLO data and
--   broadcasts the change to all clients.
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:syncDoor", function(orgId, doorIndexes, locked)
    local playerId = source

    -- Normalise doorIndexes to a table
    if type(doorIndexes) ~= "table" then
        doorIndexes = { doorIndexes }
    end

    local org = RecordManager:get("organizations", orgId)
    if not org then
        return Error("crime:syncDoor", "Organization not found", orgId)
    end

    if not (org.mlo_data and org.mlo_data.doors) then
        return Error("crime:syncDoor", "Organization has no MLO data", orgId)
    end

    for _, doorIndex in ipairs(doorIndexes) do
        if org.mlo_data.doors[doorIndex] then
            org.mlo_data.doors[doorIndex].locked = locked
        end
    end

    TriggerClientEvent("crime:updateMLODoors", -1, org.id, org.mlo_data.doors)
end)

-- ──────────────────────────────────────────────────────────
-- local getVaultCodesForOrg(orgId)
--   Returns the vault_codes array for an org from the DB.
-- ──────────────────────────────────────────────────────────
local function getVaultCodesForOrg(orgId)
    local rows = MySQL.query.await(
        "SELECT vault_codes FROM qs_crime_organizations WHERE id = ?",
        { orgId }
    )
    if rows[1] and rows[1].vault_codes then
        return json.decode(rows[1].vault_codes) or {}
    end
    return {}
end

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getVaultCodes"
--   Returns vault codes for org members only.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getVaultCodes", function(playerId, orgId)
    local playerIdentifier = sfr:getIdentifier(playerId)

    if not orgId then return {} end

    local org = RecordManager:get("organizations", orgId)
    if not org then return {} end

    -- Verify membership
    local isMember = false
    if org.members then
        for _, member in ipairs(org.members) do
            if member.identifier == playerIdentifier then
                isMember = true
                break
            end
        end
    end

    if not isMember then return {} end

    return getVaultCodesForOrg(orgId)
end)

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:setVaultCode"
--   Boss or authorized member adds a new vault code.
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:setVaultCode", function(payload)
    local playerId         = source
    local playerIdentifier = sfr:getIdentifier(playerId)

    if not payload.organization_id then
        return Notification(playerId, i18n.t("vault_code.invalid_organization"), "error")
    end

    local org = RecordManager:get("organizations", payload.organization_id)
    if not org then
        return Notification(playerId, i18n.t("vault_code.organization_not_found"), "error")
    end

    -- Find member record
    local isMember, memberRecord = false, nil
    if org.members then
        for _, m in ipairs(org.members) do
            if m.identifier == playerIdentifier then
                isMember     = true
                memberRecord = m
                break
            end
        end
    end

    if not isMember then
        return Notification(playerId, i18n.t("vault_code.not_member"), "error")
    end

    -- Check permission if not boss
    if not memberRecord.is_boss then
        if not sv_bossmenu:hasPermission(playerId, payload.organization_id, "canSetLocations") then
            return Notification(playerId, i18n.t("vault_code.no_permission"), "error")
        end
    end

    local codes    = getVaultCodesForOrg(payload.organization_id)
    local maxCodes = Config.MaxVaultCodes or 10

    if #codes >= maxCodes then
        return Notification(playerId, i18n.t("vault_code.codes_full"), "error")
    end

    table.insert(codes, { code = payload.code, uniq = payload.uniq })

    MySQL.update.await(
        "UPDATE qs_crime_organizations SET vault_codes = ? WHERE id = ?",
        { json.encode(codes), payload.organization_id }
    )

    RecordManager:clearCache("organizations")
    local updatedOrg = RecordManager:get("organizations", payload.organization_id)
    if updatedOrg then
        TriggerClientEvent("crime:updateOrganization", -1, payload.organization_id, {
            vault_codes = updatedOrg.vault_codes,
        })
    end

    Notification(playerId, i18n.t("vault_code.added"), "success")
end)

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:removeVaultCode"
--   Removes a vault code by uniq key.
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:removeVaultCode", function(payload)
    local playerId         = source
    local playerIdentifier = sfr:getIdentifier(playerId)

    if not payload.organization_id then
        return Notification(playerId, i18n.t("vault_code.invalid_organization"), "error")
    end

    local org = RecordManager:get("organizations", payload.organization_id)
    if not org then
        return Notification(playerId, i18n.t("vault_code.organization_not_found"), "error")
    end

    local isMember, memberRecord = false, nil
    if org.members then
        for _, m in ipairs(org.members) do
            if m.identifier == playerIdentifier then
                isMember     = true
                memberRecord = m
                break
            end
        end
    end

    if not isMember then
        return Notification(playerId, i18n.t("vault_code.not_member"), "error")
    end

    if not memberRecord.is_boss then
        if not sv_bossmenu:hasPermission(playerId, payload.organization_id, "canSetLocations") then
            return Notification(playerId, i18n.t("vault_code.no_permission"), "error")
        end
    end

    local codes = getVaultCodesForOrg(payload.organization_id)

    for i = 1, #codes do
        if codes[i].uniq == payload.uniq then
            table.remove(codes, i)

            MySQL.update.await(
                "UPDATE qs_crime_organizations SET vault_codes = ? WHERE id = ?",
                { json.encode(codes), payload.organization_id }
            )

            RecordManager:clearCache("organizations")
            local updatedOrg = RecordManager:get("organizations", payload.organization_id)
            if updatedOrg then
                TriggerClientEvent("crime:updateOrganization", -1, payload.organization_id, {
                    vault_codes = updatedOrg.vault_codes,
                })
            end

            Notification(playerId, i18n.t("vault_code.removed"), "success")
            return
        end
    end

    Notification(playerId, i18n.t("vault_code.not_found"), "error")
end)

-- ──────────────────────────────────────────────────────────
-- Stash registration events (ox_inventory / qb-inventory)
-- ──────────────────────────────────────────────────────────

RegisterNetEvent("crime:registerOXStash", function(stashId, slots, weight)
    exports.ox_inventory:RegisterStash(tostring(stashId), "stash_" .. tostring(stashId), tonumber(slots) or 30, tonumber(weight) or 10000, false)
end)

RegisterNetEvent("crime:openQBStash", function(stashId, stashData)
    local playerId = source
    exports["qb-inventory"].OpenInventory(playerId, stashId, stashData)
end)
