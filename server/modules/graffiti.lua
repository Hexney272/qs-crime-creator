-- ============================================================
-- server/modules/graffiti.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Server-side graffiti system.  Manages an in-memory cache of
-- graffiti records, handles creation / removal net events,
-- syncs to connecting players, and registers usable items.
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- GraffitiCache — in-memory store keyed by graffiti ID
-- ──────────────────────────────────────────────────────────
local GraffitiCache = { graffitis = {} }

-- GraffitiCache.load(self)
--   Loads all graffiti records from the DB into the cache.
function GraffitiCache.load(self)
    self.graffitis = {}
    local all = db.getGraffitis()
    for _, g in ipairs(all) do
        self.graffitis[g.id] = g
    end
    Debug("GraffitiCache:load", "Loaded", Utils.TableCount(self.graffitis), "graffitis")
end

-- GraffitiCache.getAll(self) → array
function GraffitiCache.getAll(self)
    local list = {}
    for _, g in pairs(self.graffitis) do
        list[#list + 1] = g
    end
    return list
end

-- GraffitiCache.get(self, id)
function GraffitiCache.get(self, id)
    return self.graffitis[id]
end

-- GraffitiCache.add(self, graffiti)
function GraffitiCache.add(self, graffiti)
    self.graffitis[graffiti.id] = graffiti
end

-- GraffitiCache.remove(self, id)
function GraffitiCache.remove(self, id)
    self.graffitis[id] = nil
end

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:graffiti:create"
--   Player submits a graffiti placement request.
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:graffiti:create", function(payload)
    local playerId = source

    if not (payload and payload.coords) then
        Error("crime:graffiti:create", "Invalid data from source:", playerId)
        return
    end

    local territoryId = payload.territoryId
    local isOwn       = payload.isOwn or false

    -- Resolve item name (fall back to config default)
    local itemName = payload.itemName
                  or (Config.Graffiti and Config.Graffiti.DefaultItem)

    -- Verify the player has the spray-can item
    local heldItem = sfr:getItem(playerId, itemName)
    if heldItem.count <= 0 then
        Notification(playerId, i18n.t("graffiti.no_item"), "error")
        return
    end

    -- Config limits
    local checkDist    = (Config.Graffiti and Config.Graffiti.CheckDistance)  or 50.0
    local maxNearby    = (Config.Graffiti and Config.Graffiti.MaxSprayCount)  or 15

    -- Normalise coords to vec3 if supplied as a plain table
    local coords = payload.coords
    if type(coords) == "table" and not coords.x then
        coords = vec3(
            coords[1] or coords.x or 0,
            coords[2] or coords.y or 0,
            coords[3] or coords.z or 0
        )
    end

    -- Check nearby graffiti density limit
    local nearbyCount = db.countNearbyGraffitis(coords, checkDist)
    if nearbyCount >= maxNearby then
        Notification(playerId,
            i18n.t("graffiti.too_many_nearby", { count = maxNearby }), "error")
        return
    end

    -- Consume one spray-can
    sfr:removeItem(playerId, itemName, 1)

    -- Write to DB
    local newId = db.createGraffiti(playerId, {
        label           = payload.label   or "Graffiti",
        font            = payload.font    or (Config.Graffiti and Config.Graffiti.font),
        coords          = payload.coords,
        rotation        = payload.rotation,
        scale           = payload.scale   or 1.0,
        color           = payload.color   or "FFFFFFFF",
        organization_id = payload.organization_id,
    })

    if not newId then
        -- Refund the item on failure
        sfr:addItem(playerId, itemName, 1)
        Notification(playerId, i18n.t("graffiti.creation_failed"), "error")
        return
    end

    local newGraffiti = db.getGraffiti(newId)
    if not newGraffiti then
        Error("crime:graffiti:create", "Failed to get created graffiti:", newId)
        return
    end

    -- Update cache and broadcast to all clients
    GraffitiCache:add(newGraffiti)
    TriggerClientEvent("crime:graffiti:created", -1, newGraffiti)

    -- Territory-war score event
    if territoryId then
        TriggerEvent("crime:territoryWarGraffitiSpray", playerId, territoryId, isOwn)
    end

    -- Discord log
    local playerInfo = logger:getPlayerInfo(playerId)
    logger:log({
        source  = playerInfo.identifier,
        event   = "Graffiti Created",
        message = i18n.t("logs.graffiti.created", {
            playerName = playerInfo.name,
            playerId   = playerId,
            graffitiId = newId,
            label      = newGraffiti.label,
            gang       = newGraffiti.gang or "N/A",
        }) or ("Graffiti created: " .. newGraffiti.label),
        webhook = webhook.creator,
    })

    Notification(playerId, i18n.t("graffiti.created_success"), "success")
    Debug("crime:graffiti:create", "Graffiti created by", playerId, "id:", newId)
end)

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:graffiti:remove"
--   Player removes a nearby graffiti using the cleaner item.
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:graffiti:remove", function(graffitiId, territoryId, removerOrgId)
    local playerId = source

    if not graffitiId then
        Error("crime:graffiti:remove", "Invalid graffitiId from source:", playerId)
        return
    end

    local graffiti = GraffitiCache:get(graffitiId)
    if not graffiti then
        Notification(playerId, i18n.t("graffiti.not_found"), "error")
        return
    end

    if not CanRemoveGraffiti(playerId, graffiti) then
        Notification(playerId, i18n.t("graffiti.no_permission"), "error")
        return
    end

    local success = db.removeGraffiti(graffitiId)
    if not success then
        Notification(playerId, i18n.t("graffiti.remove_failed"), "error")
        return
    end

    GraffitiCache:remove(graffitiId)

    -- Determine remover's org ID and owner's org ID for territory-war scoring
    local removerIdentifier = sfr:getIdentifier(playerId)
    local removerOrgFromDB  = nil
    local ownerOrgId        = nil

    if graffiti.owner_identifier then
        local allOrgs = RecordManager:getAll("organizations")
        for _, org in ipairs(allOrgs) do
            if org.members then
                for _, member in ipairs(org.members) do
                    if member.identifier == removerIdentifier then
                        removerOrgFromDB = org.id
                    end
                    if member.identifier == graffiti.owner_identifier then
                        ownerOrgId = org.id
                    end
                    if removerOrgFromDB and ownerOrgId then break end
                end
                if removerOrgFromDB and ownerOrgId then break end
            end
        end
    end

    -- isOwn = remover belongs to the same org as the graffiti owner
    local isOwn = graffiti.gang and ownerOrgId and (removerOrgFromDB == ownerOrgId)
               or graffiti.gang

    TriggerClientEvent("crime:graffiti:removed", -1, graffitiId, {
        territoryId  = territoryId,
        removerOrgId = removerOrgFromDB,
        isOwn        = isOwn,
    })

    -- Territory-war scoring (rival org removed it)
    if territoryId and removerOrgFromDB and ownerOrgId and removerOrgFromDB ~= ownerOrgId then
        TriggerEvent("crime:territoryWarGraffitiRemove",
            playerId, territoryId, ownerOrgId)
    end

    -- Discord log
    local playerInfo = logger:getPlayerInfo(playerId)
    logger:log({
        source  = playerInfo.identifier,
        event   = "Graffiti Removed",
        message = i18n.t("logs.graffiti.removed", {
            playerName = playerInfo.name,
            playerId   = playerId,
            graffitiId = graffitiId,
            label      = graffiti.label,
        }) or ("Graffiti removed: " .. graffiti.label),
        webhook = webhook.creator,
    })

    Notification(playerId, i18n.t("graffiti.removed_success"), "success")
    Debug("crime:graffiti:remove", "Graffiti removed by", playerId, "id:", graffitiId)

    -- Consume the cleaner item
    sfr:removeItem(playerId, Config.Graffiti.CleanerItem, 1)
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:graffiti:hasItem"
--   Returns true if the player has at least one of `itemName`.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:graffiti:hasItem", function(playerId, itemName)
    return sfr:getItem(playerId, itemName).count > 0
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:graffiti:canRemove"
--   Returns whether the player is permitted to remove a
--   specific graffiti.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:graffiti:canRemove", function(playerId, graffitiId)
    local graffiti = GraffitiCache:get(graffitiId)
    if not graffiti then return false end
    return CanRemoveGraffiti(playerId, graffiti)
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:graffiti:getAll"
--   Returns the full graffiti list.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:graffiti:getAll", function()
    return GraffitiCache:getAll()
end)

-- ──────────────────────────────────────────────────────────
-- CanRemoveGraffiti(playerId, graffitiData)
--   Permission check hook.  Default: always returns true.
--   Override in a separate file to add org / role checks.
-- ──────────────────────────────────────────────────────────
function CanRemoveGraffiti(playerId, graffitiData)
    return true
end

-- ──────────────────────────────────────────────────────────
-- SyncGraffitisToPlayer(playerId)
--   Sends the full graffiti list to a single player.
-- ──────────────────────────────────────────────────────────
function SyncGraffitisToPlayer(playerId)
    local all = GraffitiCache:getAll()
    TriggerClientEvent("crime:graffiti:sync", playerId, all)
    Debug("SyncGraffitisToPlayer", "Synced", #all, "graffitis to player:", playerId)
end

-- Sync graffiti to each newly connected player
AddEventHandler("crime:playerConnected", function()
    SyncGraffitisToPlayer(source)
end)

-- ──────────────────────────────────────────────────────────
-- Startup: load graffiti cache once the DB is ready
-- ──────────────────────────────────────────────────────────
CreateThread(function()
    while not db do Wait(100) end
    GraffitiCache:load()
end)

-- ──────────────────────────────────────────────────────────
-- Register usable items once sfr is available
-- ──────────────────────────────────────────────────────────
CreateThread(function()
    while not sfr do Wait(100) end

    local sprayItemName   = Config.Graffiti.DefaultItem
    local defaultTexture  = "PLAYER_NAME_01"

    -- Spray-can item → open graffiti dialog
    sfr:registerUsableItem(sprayItemName, function(playerId)
        TriggerClientEvent("crime:graffiti:useItem", playerId,
            sprayItemName, defaultTexture)
        Debug("Graffiti", "Player", playerId, "used item:", sprayItemName)
    end)

    -- Cleaner item → remove nearby graffiti
    sfr:registerUsableItem(Config.Graffiti.CleanerItem, function(playerId)
        TriggerClientEvent("crime:graffiti:removeNearby", playerId)
    end)
end)
