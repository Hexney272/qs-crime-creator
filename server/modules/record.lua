-- ============================================================
-- server/modules/record.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- RecordManager global — generic CRUD manager for creator-tool
-- record types (organizations, territories, taxing, vehicle_store,
-- season_pass, pvp).  Handles caching, permission checks,
-- client syncing, and Discord logging.
-- ============================================================

_G.RecordManager = {
    types = {},
    cache = {},
}

-- ──────────────────────────────────────────────────────────
-- RecordManager:register(config)
--   Registers a new record type.
--   config: { type, db = { get, create, update, remove }, log = { event, prefix } }
-- ──────────────────────────────────────────────────────────
function RecordManager:register(config)
    assert(config.type,       "RecordManager:register :: type is required")
    assert(config.db,         "RecordManager:register :: db is required")
    assert(config.db.get,     "RecordManager:register :: db.get is required")
    assert(config.db.create,  "RecordManager:register :: db.create is required")
    assert(config.db.update,  "RecordManager:register :: db.update is required")
    assert(config.db.remove,  "RecordManager:register :: db.remove is required")

    self.types[config.type] = config
    self.cache[config.type] = nil
end

-- ──────────────────────────────────────────────────────────
-- RecordManager:getAll(recordType)
--   Returns the full cached list for a type (loads from DB on miss).
-- ──────────────────────────────────────────────────────────
function RecordManager:getAll(recordType)
    local typeConfig = self.types[recordType]
    if not typeConfig then
        Error("RecordManager:getAll", "Unknown record type:", recordType)
        return {}
    end

    if not self.cache[recordType] then
        local data = typeConfig.db.get()
        self.cache[recordType] = data or {}
        Debug("RecordManager:getAll", "Loaded", #self.cache[recordType],
            recordType, "from database")
    end

    return self.cache[recordType]
end

-- ──────────────────────────────────────────────────────────
-- RecordManager:get(recordType, filter)
--   Returns a single record.
--   filter may be: an id (number/string) or a predicate function.
-- ──────────────────────────────────────────────────────────
function RecordManager:get(recordType, filter)
    local all = self:getAll(recordType)

    if type(filter) == "function" then
        return table.find(all, filter)
    elseif type(filter) == "string" or type(filter) == "number" then
        return table.find(all, function(record)
            return record.id == filter
        end)
    else
        Error("RecordManager:get", "Invalid filter type:", type(filter))
    end
end

-- ──────────────────────────────────────────────────────────
-- RecordManager:create(playerId, recordType, data)
--   Creates a new record after checking permission.
--   Returns (success, newId).
-- ──────────────────────────────────────────────────────────
function RecordManager:create(playerId, recordType, data)
    if not HasPermission(playerId) then
        Error("RecordManager:create", "Player does not have permission")
        return false, nil
    end

    local typeConfig = self.types[recordType]
    if not typeConfig then
        Error("RecordManager:create", "Unknown record type:", recordType)
        return false, nil
    end

    -- Special case: season_pass is a singleton — update if it already exists
    if recordType == "season_pass" then
        Debug("RecordManager:create",
            "Season pass create requested, using upsert behavior")
        local existing = db.getSeasonPass()
        if existing then
            local ok = typeConfig.db.update(playerId, existing.id, data)
            if ok then
                data.id      = existing.id
                data.creator = sfr:getIdentifier(playerId)
                if self.cache[recordType] then
                    self.cache[recordType][1] = data
                end
                TriggerClientEvent("crime:recordUpdated", -1, recordType, data)
                self:logAction(playerId, recordType, "update", data)
                Notification(playerId, i18n.t("creator." .. typeConfig.log.prefix .. "_updated"), "success")
                return true, existing.id
            else
                Error("RecordManager:create", "Failed to update season pass")
                return false, nil
            end
        end
        Debug("RecordManager:create", "Creating new season pass with data:",
            json.encode(data))
    end

    -- Create the record
    local newId = typeConfig.db.create(playerId, data)
    if not newId then
        Error("RecordManager:create", "Failed to create record for type:", recordType)
        if recordType == "organizations" and data.owner and data.owner.identifier then
            Notification(playerId, i18n.t("owner_already_in_organization"), "error")
        else
            Notification(playerId,
                i18n.t("creator." .. typeConfig.log.prefix .. "_create_failed"), "error")
        end
        return false, nil
    end

    data.id      = newId
    data.creator = sfr:getIdentifier(playerId)

    self:clearCache(recordType)

    -- Re-fetch the full record from DB before broadcasting so clients receive complete data.
    -- pvp battles need `status` (set to "pending" by the DB, not present in the NUI payload).
    -- organizations need `members`, `ranks`, and `upgrades` (populated by the DB after insert).
    if recordType == "pvp" then
        local fresh = db.getPvpBattle(newId)
        if fresh then data = fresh end
    elseif recordType == "organizations" then
        local fresh = RecordManager:get("organizations", newId)
        if fresh then data = fresh end
    end

    TriggerClientEvent("crime:recordCreated", -1, recordType, data)
    self:logAction(playerId, recordType, "create", data)
    Notification(playerId, i18n.t("creator." .. typeConfig.log.prefix .. "_created"), "success")

    -- For organizations: set the owner's player state
    if recordType == "organizations" and data.owner and data.owner.identifier then
        local ownerSrc = sfr:getSourceFromIdentifier(data.owner.identifier)
        if ownerSrc then
            Player(ownerSrc).state:set("organization", newId, true)
            Debug("RecordManager:create", "Set organization state for owner:",
                ownerSrc, "organization:", newId)
        end
    end

    return true, newId
end

-- ──────────────────────────────────────────────────────────
-- RecordManager:update(playerId, recordType, recordId, data)
--   Updates an existing record after checking permission.
-- ──────────────────────────────────────────────────────────
function RecordManager:update(playerId, recordType, recordId, data)
    if not HasPermission(playerId) then
        Error("RecordManager:update", "Player does not have permission")
        return false
    end

    local typeConfig = self.types[recordType]
    if not typeConfig then
        Error("RecordManager:update", "Unknown record type:", recordType)
        return false
    end

    -- Season-pass: resolve the real ID
    if recordType == "season_pass" then
        local sp = db.getSeasonPass()
        if sp then
            recordId  = sp.id
            data.id   = sp.id
        elseif not recordId or recordId == "season_pass" then
            recordId = nil
        end
        Debug("RecordManager:update", "Updating season pass with data:", json.encode({
            price         = data.price,
            endDate       = data.endDate,
            rewards_count = data.rewards and #data.rewards or 0,
        }))
    elseif recordId then
        data.id = recordId
    end

    -- PvP: detect if start_date or duration changed (requires reset)
    local needsPvpReset = false
    if recordType == "pvp" and recordId then
        local existing = db.getPvpBattle(recordId)
        if existing then
            if data.start_date then
                -- Parse existing start_date to ms
                local existingMs = nil
                if type(existing.start_date) == "string" then
                    local y, mo, d, h, m, s = existing.start_date:match(
                        "^(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)$")
                    if y then
                        existingMs = os.time({
                            year = tonumber(y), month = tonumber(mo), day = tonumber(d),
                            hour = tonumber(h) or 0, min = tonumber(m) or 0, sec = tonumber(s) or 0,
                        }) * 1000
                    end
                elseif type(existing.start_date) == "number" then
                    existingMs = existing.start_date
                end
                if existingMs and math.abs((data.start_date or 0) - existingMs) > 1000 then
                    needsPvpReset = true
                    Debug("RecordManager:update",
                        "PvP battle start_date changed, will reset status and participants")
                end
            end
            if data.duration and data.duration ~= existing.duration then
                needsPvpReset = true
                Debug("RecordManager:update",
                    "PvP battle duration changed, will reset status and participants")
            end
        end
    end

    -- Track old org owner for transfer logic
    local oldOwnerIdentifier = nil
    if recordType == "organizations" and recordId and data.owner then
        local existingOrg = RecordManager:get("organizations", recordId)
        if existingOrg and existingOrg.owner and existingOrg.owner.identifier then
            oldOwnerIdentifier = existingOrg.owner.identifier
        end
    end

    -- Perform the DB update
    local ok = typeConfig.db.update(playerId, recordId, data)
    if not ok then
        Error("RecordManager:update", "Failed to update record for type:", recordType)
        if recordType == "organizations" and data.owner and data.owner.identifier then
            Notification(playerId, i18n.t("owner_already_in_organization"), "error")
        else
            Notification(playerId,
                i18n.t("creator." .. typeConfig.log.prefix .. "_update_failed"), "error")
        end
        return false
    end

    -- Season-pass: re-fetch and normalise endDate
    if recordType == "season_pass" then
        local sp = db.getSeasonPass()
        if sp then
            data.id = sp.id
            recordId = sp.id
            if not data.endDate and data.end_date then
                data.endDate  = data.end_date
                data.end_date = nil
            end
        end
    end

    -- PvP: reset status / participants if timing changed
    if recordType == "pvp" and needsPvpReset and recordId then
        TriggerEvent("crime:destroyActivePvpBattle", recordId)
        db.updatePvpBattleStatus(recordId, "pending")
        db.resetPvpParticipants(recordId)
        db.deletePvpScores(recordId)
        Debug("RecordManager:update", "Reset PvP battle due to time change:", recordId)
    end

    self:clearCache(recordType)

    -- PvP: re-read fresh row before broadcasting
    if recordType == "pvp" and recordId then
        local fresh = db.getPvpBattle(recordId)
        if fresh then
            Debug("RecordManager:update", "Sending fresh PvP data to clients:",
                recordId, "status:", fresh.status)
            data = fresh
        end
    end

    TriggerClientEvent("crime:recordUpdated", -1, recordType, data)
    self:logAction(playerId, recordType, "update", data)
    Notification(playerId, i18n.t("creator." .. typeConfig.log.prefix .. "_updated"), "success")

    -- Organization owner transfer
    if recordType == "organizations" and recordId and data.owner then
        local newOwnerIdentifier = nil
        if type(data.owner) == "table" and data.owner.identifier then
            newOwnerIdentifier = data.owner.identifier
        end

        -- Clear old owner's state if owner changed
        if oldOwnerIdentifier and newOwnerIdentifier and newOwnerIdentifier ~= oldOwnerIdentifier then
            local oldSrc = sfr:getSourceFromIdentifier(oldOwnerIdentifier)
            if oldSrc then
                Player(oldSrc).state:set("organization", nil, true)
                Debug("RecordManager:update", "Cleared organization state for old owner:", oldSrc)
            end
        end

        -- Set new owner's state
        if newOwnerIdentifier then
            local newSrc = sfr:getSourceFromIdentifier(newOwnerIdentifier)
            if newSrc then
                Player(newSrc).state:set("organization", recordId, true)
                Debug("RecordManager:update", "Set organization state for new owner:",
                    newSrc, "organization:", recordId)
            end
        elseif data.owner == false and oldOwnerIdentifier then
            -- Owner explicitly removed
            local oldSrc = sfr:getSourceFromIdentifier(oldOwnerIdentifier)
            if oldSrc then
                Player(oldSrc).state:set("organization", nil, true)
                Debug("RecordManager:update", "Cleared organization state for removed owner:", oldSrc)
            end
        end
    end

    return true
end

-- ──────────────────────────────────────────────────────────
-- RecordManager:remove(playerId, recordType, recordId)
-- ──────────────────────────────────────────────────────────
function RecordManager:remove(playerId, recordType, recordId)
    if not HasPermission(playerId) then
        Error("RecordManager:remove", "Player does not have permission")
        return false
    end

    local typeConfig = self.types[recordType]
    if not typeConfig then
        Error("RecordManager:remove", "Unknown record type:", recordType)
        return false
    end

    local ok = typeConfig.db.remove(recordId)
    if not ok then
        Error("RecordManager:remove", "Failed to remove record")
        return false
    end

    self:clearCache(recordType)
    TriggerClientEvent("crime:recordRemoved", -1, recordType, recordId)
    self:logAction(playerId, recordType, "remove", { id = recordId })
    Notification(playerId, i18n.t("creator." .. typeConfig.log.prefix .. "_removed"), "success")
    return true
end

-- ──────────────────────────────────────────────────────────
-- RecordManager:getAllData()
--   Returns all record types as a map { type → list }.
-- ──────────────────────────────────────────────────────────
function RecordManager:getAllData()
    local result = {}
    for typeName in pairs(self.types) do
        result[typeName] = self:getAll(typeName)
    end
    return result
end

-- ──────────────────────────────────────────────────────────
-- RecordManager:syncToPlayer(playerId)
--   Sends all data to a specific player via latent event.
-- ──────────────────────────────────────────────────────────
function RecordManager:syncToPlayer(playerId)
    local allData = self:getAllData()
    TriggerLatentClientEvent("crime:syncData", playerId, 10485760, allData)
    Debug("RecordManager:syncToPlayer", "Synced all data to player:", playerId)
end

-- ──────────────────────────────────────────────────────────
-- RecordManager:clearCache(recordType?)
--   Clears the cache for one type, or all types if nil.
-- ──────────────────────────────────────────────────────────
function RecordManager:clearCache(recordType)
    if recordType then
        self.cache[recordType] = nil
        Debug("RecordManager:clearCache", "Cleared cache for:", recordType)
    else
        for typeName in pairs(self.types) do
            self.cache[typeName] = nil
        end
        Debug("RecordManager:clearCache", "Cleared all cache")
    end
end

-- ──────────────────────────────────────────────────────────
-- RecordManager:logAction(playerId, recordType, action, data)
--   Sends a Discord log entry for creator-tool actions.
-- ──────────────────────────────────────────────────────────
function RecordManager:logAction(playerId, recordType, action, data)
    local typeConfig = self.types[recordType]
    if not (typeConfig and typeConfig.log) then return end

    local playerInfo  = logger:getPlayerInfo(playerId)
    local i18nKey     = "logs.creator." .. action .. "_" .. typeConfig.log.prefix
    local adminTitle  = i18n.t("logs.admin_title")
    local adminEmbed  = logger:getPlayerInfoEmbed(adminTitle, playerId, playerInfo)

    local message = i18n.t(i18nKey, {
        adminName   = playerInfo.name,
        adminSource = playerId,
        adminInfo   = adminEmbed,
        id          = data.id,
        label       = data.label or "N/A",
    })

    if not message then
        message = typeConfig.log.prefix .. " " .. action .. "d: "
               .. (data.label or tostring(data.id))
    end

    logger:log({
        source  = playerInfo.identifier,
        event   = typeConfig.log.event,
        message = message,
        webhook = webhook.creator,
    })
end

-- ──────────────────────────────────────────────────────────
-- Register all record types once db is available
-- ──────────────────────────────────────────────────────────
CreateThread(function()
    while not db do Wait(100) end

    -- organizations
    RecordManager:register({
        type = "organizations",
        db   = {
            get    = db.getOrganizations,
            create = db.createOrganization,
            update = db.updateOrganization,
            remove = db.removeOrganization,
        },
        log  = { event = "Organization Creator", prefix = "organization" },
    })

    -- territories
    RecordManager:register({
        type = "territories",
        db   = {
            get    = db.getTerritories,
            create = db.createTerritory,
            update = db.updateTerritory,
            remove = db.removeTerritory,
        },
        log  = { event = "Territory Creator", prefix = "territory" },
    })

    -- taxing
    RecordManager:register({
        type = "taxing",
        db   = {
            get    = db.getTaxing,
            create = db.createTaxing,
            update = db.updateTaxing,
            remove = db.removeTaxing,
        },
        log  = { event = "Taxing Creator", prefix = "taxing" },
    })

    -- vehicle_store
    RecordManager:register({
        type = "vehicle_store",
        db   = {
            get    = db.getVehicleStore,
            create = db.createVehicleStore,
            update = db.updateVehicleStore,
            remove = db.removeVehicleStore,
        },
        log  = { event = "Vehicle Store Creator", prefix = "vehicle_store" },
    })

    -- season_pass (singleton)
    RecordManager:register({
        type = "season_pass",
        db   = {
            get    = function()
                local sp = db.getSeasonPass()
                return sp and { sp } or {}
            end,
            create = db.createSeasonPass,
            update = function(playerId, id, data)
                return db.updateSeasonPass(playerId, data)
            end,
            remove = db.removeSeasonPass,
        },
        log  = { event = "Season Pass Creator", prefix = "season_pass" },
    })

    -- pvp
    RecordManager:register({
        type = "pvp",
        db   = {
            get    = db.getPvpBattles,
            create = db.createPvpBattle,
            update = db.updatePvpBattle,
            remove = db.removePvpBattle,
        },
        log  = { event = "PvP Battle Creator", prefix = "pvp_battle" },
    })
end)
