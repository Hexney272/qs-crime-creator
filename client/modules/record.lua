-- ============================================================
-- client/modules/record.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Client-side RecordHandler: receives server syncs and CRUD
-- events for all record types, keeping creator.* tables in sync
-- and delegating to type-specific managers (Organization,
-- Territory, PvpModule, GraffitiModule, etc.).
-- ============================================================

_G.RecordHandler = { configs = {} }

-- ──────────────────────────────────────────────────────────
-- Config: organizations
-- ──────────────────────────────────────────────────────────
RecordHandler.configs.organizations = {
    getStorage = function()
        return creator.organizations
    end,
    setStorage = function(data)
        creator.organizations = data
    end,
    format = function(data)
        return {
            id                = data.id,
            label             = data.label,
            category          = "organizations",
            organization_data = data,
        }
    end,
    onCreate = function(data)
        if OrganizationManager and Organization then
            local instance = Organization:new(data)
            OrganizationManager:add(data.id, instance)
        end
    end,
    onUpdate = function(data)
        if OrganizationManager and Organization then
            local instance = Organization:new(data)
            OrganizationManager:update(data.id, instance)
        end
    end,
    onRemove = function(id)
        if OrganizationManager then
            OrganizationManager:remove(id)
        end
    end,
}

-- ──────────────────────────────────────────────────────────
-- Config: territories
-- ──────────────────────────────────────────────────────────
RecordHandler.configs.territories = {
    getStorage = function()
        return creator.territories
    end,
    setStorage = function(data)
        creator.territories = data
    end,
    format = function(data)
        return {
            id             = data.id,
            label          = data.label,
            category       = "territories",
            territory_data = data,
        }
    end,
    onCreate = function(data)
        if TerritoryManager and Territory then
            local instance = Territory:new(data.id, data.label, data.organization_id,
                data.zone, data.color, data.creator)
            TerritoryManager:add(data.id, instance)
        end
    end,
    onUpdate = function(data)
        if TerritoryManager and Territory then
            local instance = Territory:new(data.id, data.label, data.organization_id,
                data.zone, data.color, data.creator)
            TerritoryManager:update(data.id, instance)
        end
    end,
    onRemove = function(id)
        if TerritoryManager then TerritoryManager:remove(id) end
    end,
}

-- ──────────────────────────────────────────────────────────
-- Config: taxing
-- ──────────────────────────────────────────────────────────
RecordHandler.configs.taxing = {
    getStorage = function() return creator.taxing end,
    setStorage = function(data) creator.taxing = data end,
    format = function(data)
        return { id = data.id, label = data.label, category = "taxing", taxing_data = data }
    end,
    onCreate  = function(_) end,
    onUpdate  = function(_) end,
    onRemove  = function(_) end,
}

-- ──────────────────────────────────────────────────────────
-- Config: vehicle_store
-- ──────────────────────────────────────────────────────────
RecordHandler.configs.vehicle_store = {
    getStorage = function() return creator.vehicleStore end,
    setStorage = function(data) creator.vehicleStore = data end,
    format = function(data)
        local label = data.vehicle_label or data.vehicle_model
                   or ("Vehicle #" .. tostring(data.id))
        return {
            id                 = data.id,
            label              = label,
            category           = "vehicle_store",
            vehicle_store_data = data,
        }
    end,
    onCreate  = function(_) end,
    onUpdate  = function(_) end,
    onRemove  = function(_) end,
}

-- ──────────────────────────────────────────────────────────
-- Config: season_pass (singleton)
-- ──────────────────────────────────────────────────────────
RecordHandler.configs.season_pass = {
    getStorage = function() return creator.seasonPass end,
    setStorage = function(data) creator.seasonPass = data end,
    format = function(data)
        -- Normalise end_date → endDate
        if not data.endDate and data.end_date then
            data.endDate  = data.end_date
            data.end_date = nil
        end
        if data.season_pass_data then
            if not data.season_pass_data.endDate and data.season_pass_data.end_date then
                data.season_pass_data.endDate   = data.season_pass_data.end_date
                data.season_pass_data.end_date  = nil
            end
        end
        return {
            id               = data.id or "season_pass",
            label            = "Season Pass",
            category         = "season_pass",
            season_pass_data = data,
        }
    end,
    onCreate  = function(_) end,
    onUpdate  = function(_) end,
    onRemove  = function(_) end,
}

-- ──────────────────────────────────────────────────────────
-- Config: pvp (PvP battles)
-- ──────────────────────────────────────────────────────────
RecordHandler.configs.pvp = {
    getStorage = function() return creator.pvpBattles end,
    setStorage = function(data) creator.pvpBattles = data end,
    format = function(data)
        local label = data.label or ("PvP Battle #" .. tostring(data.id))
        return {
            id       = data.id,
            label    = label,
            category = "pvp",
            pvp_data = data,
        }
    end,
    onCreate = function(data)
        Debug("RecordHandler", "PvP onCreate called with data:", data)
        PvpModule.handleBattleCreated(data)
    end,
    onUpdate = function(data)
        Debug("RecordHandler", "PvP onUpdate called with data:", data)
        PvpModule.handleBattleUpdated(data)
    end,
    onRemove = function(id)
        Debug("RecordHandler", "PvP onRemove called with id:", id)
        PvpModule.handleBattleRemoved(id)
    end,
}

-- ──────────────────────────────────────────────────────────
-- Config: graffiti
-- ──────────────────────────────────────────────────────────
RecordHandler.configs.graffiti = {
    getStorage = function() return creator.graffitis end,
    setStorage = function(data) creator.graffitis = data end,
    format = function(data)
        return { id = data.id, label = data.label, category = "graffiti", graffiti_data = data }
    end,
    onCreate = function(data)
        if GraffitiModule then GraffitiModule:add(data) end
    end,
    onUpdate = function(data)
        if GraffitiModule then GraffitiModule:update(data) end
    end,
    onRemove = function(id)
        if GraffitiModule then GraffitiModule:remove(id) end
    end,
}

-- ──────────────────────────────────────────────────────────
-- RecordHandler.findOrganization(_, orgId)
-- ──────────────────────────────────────────────────────────
function RecordHandler.findOrganization(_, orgId)
    if not (orgId and creator.organizations) then return nil end
    for _, item in ipairs(creator.organizations) do
        if item.id == orgId then
            return item.organization_data or item
        end
    end
    return nil
end

-- ──────────────────────────────────────────────────────────
-- RecordHandler.initializeStorage(self)
--   Ensures each config type has a non-nil storage table.
-- ──────────────────────────────────────────────────────────
function RecordHandler.initializeStorage(self)
    for _, cfg in pairs(self.configs) do
        if not cfg.getStorage() then
            cfg.setStorage({})
        end
    end
end

-- ──────────────────────────────────────────────────────────
-- NetEvent: "crime:syncData"
--   Full data sync from server (sent on player connect).
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:syncData", function(allData)
    RecordHandler:initializeStorage()

    for recordType, items in pairs(allData) do
        local cfg = RecordHandler.configs[recordType]
        if cfg then
            local formatted = {}
            for _, item in ipairs(items) do
                -- Normalise season_pass end_date
                if recordType == "season_pass" then
                    if not item.endDate and item.end_date then
                        item.endDate  = item.end_date
                        item.end_date = nil
                    end
                end
                formatted[#formatted + 1] = cfg.format(item)
            end
            cfg.setStorage(formatted)
        end
    end

    -- Rebuild OrganizationManager
    if creator.organizations and OrganizationManager and Organization then
        OrganizationManager:clear()
        for _, item in ipairs(creator.organizations) do
            if item.organization_data then
                local instance = Organization:new(item.organization_data)
                OrganizationManager:add(item.organization_data.id, instance)
            end
        end
    end

    -- Rebuild TerritoryManager
    if creator.territories and creator.organizations and TerritoryManager and Territory then
        TerritoryManager:clear()
        for _, item in ipairs(creator.territories) do
            if item.territory_data then
                local d = item.territory_data
                local instance = Territory:new(d.id, d.label, d.organization_id,
                    d.zone, d.color, d.creator)
                TerritoryManager:add(d.id, instance)
            end
        end
    end

    RecordHandler.initialized = true
    Debug("RecordHandler", "Synced all data")

    -- Initialise PvP battle instances
    if creator.pvpBattles then
        Debug("RecordHandler", "Initializing PvP battles, count:", #creator.pvpBattles)
        for _, item in ipairs(creator.pvpBattles) do
            if item.pvp_data then
                PvpModule.handleBattleCreated(item.pvp_data)
            end
        end
    end
end)

-- ──────────────────────────────────────────────────────────
-- NetEvent: "crime:recordCreated"
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:recordCreated", function(recordType, data)
    local cfg = RecordHandler.configs[recordType]
    if not cfg then
        Error("RecordHandler", "Unknown record type:", recordType)
        return
    end

    local storage = cfg.getStorage()
    if not storage then
        cfg.setStorage({})
        storage = cfg.getStorage()
    end

    -- Normalise season_pass
    if recordType == "season_pass" then
        if not data.endDate and data.end_date then
            data.endDate  = data.end_date
            data.end_date = nil
        end
        storage[1] = cfg.format(data)
    else
        storage[#storage + 1] = cfg.format(data)
    end

    if cfg.onCreate then cfg.onCreate(data) end

    if creator.visible then creator:updateUI() end
    Debug("RecordHandler", "Created", recordType, "id:", data.id)
end)

-- ──────────────────────────────────────────────────────────
-- NetEvent: "crime:recordUpdated"
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:recordUpdated", function(recordType, data)
    local cfg = RecordHandler.configs[recordType]
    if not cfg then
        Error("RecordHandler", "Unknown record type:", recordType)
        return
    end

    local storage = cfg.getStorage()
    if not storage then
        cfg.setStorage({})
        storage = cfg.getStorage()
    end

    if recordType == "season_pass" then
        if not data.endDate and data.end_date then
            data.endDate  = data.end_date
            data.end_date = nil
        end
        storage[1] = cfg.format(data)
    else
        local found = false
        for i, item in ipairs(storage) do
            Debug("RecordHandler", "Updating record:", recordType, "id:", data.id,
                "item id:", item.id)
            if item.id == data.id then
                storage[i] = cfg.format(data)
                found = true
                break
            end
        end
        if not found then
            storage[#storage + 1] = cfg.format(data)
            Debug("RecordHandler", "Record not found in storage, added as new:",
                recordType, "id:", data.id)
        end
    end

    if cfg.onUpdate then cfg.onUpdate(data) end
    if creator.visible then creator:updateUI() end
    Debug("RecordHandler", "Updated", recordType, "id:", data.id)
end)

-- ──────────────────────────────────────────────────────────
-- NetEvent: "crime:recordRemoved"
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:recordRemoved", function(recordType, recordId)
    local cfg = RecordHandler.configs[recordType]
    if not cfg then
        Error("RecordHandler", "Unknown record type:", recordType)
        return
    end

    local storage = cfg.getStorage()
    if not storage then return end

    if recordType == "season_pass" then
        storage[1] = nil
        cfg.setStorage({})
    else
        for i, item in ipairs(storage) do
            if item.id == recordId then
                table.remove(storage, i)
                break
            end
        end
    end

    if cfg.onRemove then cfg.onRemove(recordId) end
    if creator.visible then creator:updateUI() end
    Debug("RecordHandler", "Removed", recordType, "id:", recordId)
end)

-- ──────────────────────────────────────────────────────────
-- NetEvent: "crime:updateOrganization"
--   Partial update — merges changed fields into the stored org.
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:updateOrganization", function(orgId, changedFields)
    if not orgId or not changedFields then return end

    local cfg = RecordHandler.configs.organizations
    if not cfg then return end

    local storage = cfg.getStorage()
    if not storage then return end

    for _, item in ipairs(storage) do
        if item.id == orgId and item.organization_data then
            -- Merge changed fields
            for k, v in pairs(changedFields) do
                item.organization_data[k] = v
            end
            -- Also update the OrganizationManager instance
            if OrganizationManager then
                local instance = OrganizationManager:get(orgId)
                if instance then
                    for k, v in pairs(changedFields) do
                        instance[k] = v
                    end
                end
            end
            break
        end
    end

    if creator and creator.visible then creator:updateUI() end
    Debug("RecordHandler", "Partial update for organization:", orgId)
end)
