-- ============================================================
-- server/main.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Server-side entry point.  Handles startup, player tracking,
-- organization management callbacks, illegal medic, season pass,
-- and item/usable-item registration.
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- Startup: wait until `db` and sv_inventory are ready
-- ──────────────────────────────────────────────────────────
while true do
    if db and sv_inventory.formatItemList then
        break
    end
    Wait(1000)
    Info("Waiting for db and sv_inventory.formatItemList", "your inventory", Config.Inventory)
end

-- ──────────────────────────────────────────────────────────
-- Global state
-- ──────────────────────────────────────────────────────────
ActivePlayers = {}   -- Set of server IDs currently connected: { [src] = true }

-- Pre-format the full item list from the inventory system
ItemList = sv_inventory:formatItemList()

-- ──────────────────────────────────────────────────────────
-- On startup: reset any vehicles that were marked "out" to
-- "impound" (handles server restarts mid-session)
-- ──────────────────────────────────────────────────────────
CreateThread(function()
    MySQL.update('UPDATE qs_crime_organization_vehicles SET state = "impound" WHERE state = "out"')
end)

-- ──────────────────────────────────────────────────────────
-- InitOrganization(playerId)
--   Looks up which organization the player belongs to and
--   writes the organization ID into their player state bag.
--   Called on every connection.
-- ──────────────────────────────────────────────────────────
function InitOrganization(playerId)
    local playerIdentifier = sfr:getIdentifier(playerId)
    if not playerIdentifier then return end

    -- Search all organizations for one that includes this player
    local org = RecordManager:get("organizations", function(orgData)
        if orgData.members then
            return table.find(orgData.members, function(member)
                return member.identifier == playerIdentifier
            end)
        end
    end)

    -- Write the org ID (or nil) into the player state bag
    local playerState = Player(playerId).state
    playerState:set("organization", org and org.id or nil, true)
end

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:playerConnected"
--   Fired by the client immediately after the UI initialises.
--   Syncs all record data to the new player and registers them.
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:playerConnected", function()
    local playerId = source
    RecordManager:syncToPlayer(playerId)
    ActivePlayers[playerId] = true
    InitOrganization(playerId)
end)

-- ──────────────────────────────────────────────────────────
-- GetItemList()
--   Converts the cached ItemList into a minimal UI-friendly
--   array: { name, label, image }.
-- ──────────────────────────────────────────────────────────
function GetItemList()
    local items = {}

    for _, item in pairs(ItemList) do
        items[#items + 1] = {
            name  = item.name,
            label = item.label or item.name,
            image = item.image,
        }
    end

    return items
end

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getPoliceCount"
--   Returns the number of online players currently employed
--   in a police job (as defined in Config.PoliceJobs).
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getPoliceCount", function(playerId)
    local allPlayers = GetPlayers()
    local policeCount = 0

    for _, playerIdStr in pairs(allPlayers) do
        local jobName = sfr:getJobName(tonumber(playerIdStr))
        if table.contains(Config.PoliceJobs, jobName) then
            policeCount = policeCount + 1
        end
    end

    return policeCount
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getItemList"
--   Returns the formatted item list for the UI item picker.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getItemList", function()
    return GetItemList()
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:hasMoney"
--   Returns true if the requesting player has at least
--   `requiredAmount` in their money account.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:hasMoney", function(playerId, requiredAmount)
    local balance = sfr:getAccountMoney(playerId, "money")
    return requiredAmount <= balance
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:hasItem"
--   Returns true if the requesting player has at least one
--   of `itemName` in their inventory.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:hasItem", function(playerId, itemName)
    local item = sfr:getItem(playerId, itemName)
    return item.count > 0
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getOrganizationMembers"
--   Returns the member list for the requesting player's org,
--   enriched with an `isOnline` boolean for each member.
--   Returns {} if the player is not in the organization.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getOrganizationMembers", function(playerId, orgId)
    -- Resolve the organisation ID via the boss-menu module
    local resolvedOrgId = sv_bossmenu:getOrganizationId(playerId)
    if not resolvedOrgId then
        Error("crime:getOrganizationMembers", "Organization ID is required")
        return {}
    end

    local requesterIdentifier = sfr:getIdentifier(playerId)
    local org = RecordManager:get("organizations", resolvedOrgId)

    if not org then return {} end

    -- Verify the requester is actually a member (owner counts)
    local isMember = (org.owner and org.owner.identifier == requesterIdentifier)
    if not isMember and org.members then
        for _, member in ipairs(org.members) do
            if member.identifier == requesterIdentifier then
                isMember = true
                break
            end
        end
    end

    if not isMember then return {} end

    -- Build the response array with online status
    local members = org.members or {}
    local result   = {}

    for _, member in ipairs(members) do
        -- Check if this member is currently online
        local isOnline = false
        for _, onlinePlayerIdStr in ipairs(GetPlayers()) do
            local onlinePlayerId = tonumber(onlinePlayerIdStr)
            if onlinePlayerId then
                local onlineIdentifier = sfr:getIdentifier(onlinePlayerId)
                if onlineIdentifier == member.identifier then
                    isOnline = true
                    break
                end
            end
        end

        -- Copy member data and add the isOnline flag
        local memberEntry = {}
        for k, v in pairs(member) do
            memberEntry[k] = v
        end
        memberEntry.isOnline = isOnline
        result[#result + 1] = memberEntry
    end

    return result
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:addOrganizationMember"
--   Adds a player to an organization.
--   Parameters: playerId (requester), orgId, targetPlayerId,
--               rank, additionalData
--   Returns (success, errorCode)
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:addOrganizationMember",
    function(playerId, orgId, targetPlayerId, rank, additionalData)

    -- Validate required parameters
    if not (orgId and targetPlayerId) or not rank then
        return false, "invalid_data"
    end

    local targetIdentifier = sfr:getIdentifier(targetPlayerId)
    if not targetIdentifier then
        return false, "invalid_player"
    end

    local requesterIdentifier = sfr:getIdentifier(playerId)
    local org = RecordManager:get("organizations", orgId)

    if not org then
        return false, "organization_not_found"
    end

    -- Find the requester's member entry (owner may not be in members list)
    local isOwner = org.owner and org.owner.identifier == requesterIdentifier
    local requesterMember = nil
    if org.members then
        for _, member in ipairs(org.members) do
            if member.identifier == requesterIdentifier then
                requesterMember = member
                break
            end
        end
    end

    if not isOwner and not requesterMember then
        return false, "not_member"
    end

    -- Permission check: owner/boss always allowed, otherwise check canManageMembers
    if not isOwner and requesterMember and not requesterMember.is_boss then
        local hasPerm = sv_bossmenu:hasPermission(playerId, orgId, "canManageMembers")
        if not hasPerm then
            return false, "no_permission"
        end
    end

    -- Check target is not already in any organization
    if db.isPlayerInAnyOrganization(targetIdentifier, orgId) then
        Notification(playerId, i18n.t("player_already_in_organization"), "error")
        return false, "player_already_in_organization"
    end

    -- Write to DB
    local success = db.addOrganizationMember(playerId, orgId, targetIdentifier, rank, additionalData)

    if success ~= nil then
        -- Bust cache and push updated member list to all clients
        RecordManager:clearCache("organizations")
        local updatedOrg = RecordManager:get("organizations", orgId)
        if updatedOrg then
            TriggerClientEvent("crime:updateOrganization", -1, orgId, { members = updatedOrg.members })
        end

        -- Update the joined player's state bag if they are online
        if ActivePlayers[targetPlayerId] then
            Player(targetPlayerId).state:set("organization", orgId, true)
            Debug("crime:addOrganizationMember", "Player", targetPlayerId, "added to organization", orgId)
        end

        return true, nil
    end

    return false, "failed_to_add"
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:updateOrganizationMember"
--   Updates an existing member's data (e.g. rank, permissions).
--   Returns success boolean.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:updateOrganizationMember",
    function(playerId, orgId, targetIdentifier, newData)

    if not orgId or not targetIdentifier then return false end

    local requesterIdentifier = sfr:getIdentifier(playerId)
    local org = RecordManager:get("organizations", orgId)
    if not org then return false end

    -- Find requester's member record (owner may not be in members list)
    local isOwner = org.owner and org.owner.identifier == requesterIdentifier
    local requesterMember = nil
    if org.members then
        for _, member in ipairs(org.members) do
            if member.identifier == requesterIdentifier then
                requesterMember = member
                break
            end
        end
    end

    if not isOwner and not requesterMember then return false end

    -- Owners can always manage; non-owners need is_boss or canManageMembers
    if not isOwner then
        if not requesterMember.is_boss then
            local hasPerm = sv_bossmenu:hasPermission(playerId, orgId, "canManageMembers")
            if not hasPerm then return false end
        end
    end

    local success = db.updateOrganizationMember(playerId, orgId, targetIdentifier, newData)

    if success then
        RecordManager:clearCache("organizations")
        local updatedOrg = RecordManager:get("organizations", orgId)
        if updatedOrg then
            TriggerClientEvent("crime:updateOrganization", -1, orgId, { members = updatedOrg.members })
        end
    end

    return success
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:removeOrganizationMember"
--   Removes a member (by identifier) from an organization.
--   Clears the removed player's state bag if they are online.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:removeOrganizationMember",
    function(playerId, orgId, targetIdentifier)

    if not orgId or not targetIdentifier then return false end

    local requesterIdentifier = sfr:getIdentifier(playerId)
    local org = RecordManager:get("organizations", orgId)
    if not org then return false end

    -- Find requester's member record (owner may not be in members list)
    local isOwner = org.owner and org.owner.identifier == requesterIdentifier
    local requesterMember = nil
    if org.members then
        for _, member in ipairs(org.members) do
            if member.identifier == requesterIdentifier then
                requesterMember = member
                break
            end
        end
    end

    if not isOwner and not requesterMember then return false end

    -- Permission check
    if not isOwner then
        if not requesterMember.is_boss then
            local hasPerm = sv_bossmenu:hasPermission(playerId, orgId, "canManageMembers")
            if not hasPerm then return false end
        end
    end

    local success = db.removeOrganizationMember(orgId, targetIdentifier)

    if success then
        RecordManager:clearCache("organizations")
        local updatedOrg = RecordManager:get("organizations", orgId)
        if updatedOrg then
            TriggerClientEvent("crime:updateOrganization", -1, orgId, { members = updatedOrg.members })
        end

        -- Clear the removed player's state bag if online
        local targetPlayerId = sfr:getSourceFromIdentifier(targetIdentifier)
        if targetPlayerId and ActivePlayers[targetPlayerId] then
            Player(targetPlayerId).state:set("organization", nil, true)
            Debug("crime:removeOrganizationMember", "Player", targetPlayerId, "removed from organization", orgId)
        end
    end

    return success
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getOrganizationRanks"
--   Returns the rank list for an organization, but only if
--   the requesting player is a member.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getOrganizationRanks", function(playerId, orgId)
    if not orgId then return {} end

    local requesterIdentifier = sfr:getIdentifier(playerId)
    local org = RecordManager:get("organizations", orgId)
    if not org then return {} end

    -- Verify membership (owner counts as member)
    local isMember = (org.owner and org.owner.identifier == requesterIdentifier)
    if not isMember and org.members then
        for _, member in ipairs(org.members) do
            if member.identifier == requesterIdentifier then
                isMember = true
                break
            end
        end
    end

    if not isMember then return {} end

    return org.ranks or {}
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:addOrganizationRank"
--   Adds a new rank to the organization.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:addOrganizationRank",
    function(playerId, orgId, rankName, rankData)

    if not orgId then orgId = sv_bossmenu:getOrganizationId(playerId) end
    if not orgId or not rankName then return false end

    local requesterIdentifier = sfr:getIdentifier(playerId)
    local org = RecordManager:get("organizations", orgId)
    if not org then return false end

    -- Owner always has permission
    local isOwner = org.owner and org.owner.identifier == requesterIdentifier

    -- Find requester's member record
    local requesterMember = nil
    if org.members then
        for _, member in ipairs(org.members) do
            if member.identifier == requesterIdentifier then
                requesterMember = member
                break
            end
        end
    end

    if not isOwner and not requesterMember then return false end

    if not isOwner and requesterMember and not requesterMember.is_boss then
        local hasPerm = sv_bossmenu:hasPermission(playerId, orgId, "canManageRanks")
        if not hasPerm then return false end
    end

    local success = db.addOrganizationRank(playerId, orgId, rankName, rankData)

    if success ~= nil then
        RecordManager:clearCache("organizations")
        local updatedOrg = RecordManager:get("organizations", orgId)
        if updatedOrg then
            TriggerClientEvent("crime:updateOrganization", -1, orgId, { ranks = updatedOrg.ranks })
        end
    end

    return success ~= nil
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:updateOrganizationRank"
--   Updates an existing rank's definition.
--   Finds the organization by locating the rank ID first.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:updateOrganizationRank",
    function(playerId, rankId, rankName, rankData)

    if not rankId then return false end

    local requesterIdentifier = sfr:getIdentifier(playerId)

    -- Find the organization that contains this rank
    local org = RecordManager:get("organizations", function(orgData)
        if orgData.ranks then
            return table.find(orgData.ranks, function(rank)
                return rank.id == rankId
            end)
        end
    end)

    if not org then return false end

    -- Find requester's member record
    local requesterMember = nil
    if org.members then
        for _, member in ipairs(org.members) do
            if member.identifier == requesterIdentifier then
                requesterMember = member
                break
            end
        end
    end

    local isOwner = org.owner and org.owner.identifier == requesterIdentifier

    if not isOwner and not requesterMember then return false end

    if not isOwner and requesterMember and not requesterMember.is_boss then
        local hasPerm = sv_bossmenu:hasPermission(playerId, org.id, "canManageRanks")
        if not hasPerm then return false end
    end

    local success = db.updateOrganizationRank(playerId, rankId, rankName, rankData)

    if success then
        RecordManager:clearCache("organizations")
        local updatedOrg = RecordManager:get("organizations", org.id)
        if updatedOrg then
            TriggerClientEvent("crime:updateOrganization", -1, org.id, { ranks = updatedOrg.ranks })
        end
    end

    return success
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:removeOrganizationRank"
--   Removes a rank by ID.  Organization is found via the rank.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:removeOrganizationRank", function(playerId, rankId)
    if not rankId then return false end

    local requesterIdentifier = sfr:getIdentifier(playerId)

    -- Find the organization that contains this rank
    local org = RecordManager:get("organizations", function(orgData)
        if orgData.ranks then
            return table.find(orgData.ranks, function(rank)
                return rank.id == rankId
            end)
        end
    end)

    if not org then return false end

    -- Find requester's member record
    local requesterMember = nil
    if org.members then
        for _, member in ipairs(org.members) do
            if member.identifier == requesterIdentifier then
                requesterMember = member
                break
            end
        end
    end

    local isOwner = org.owner and org.owner.identifier == requesterIdentifier

    if not isOwner and not requesterMember then return false end

    if not isOwner and requesterMember and not requesterMember.is_boss then
        local hasPerm = sv_bossmenu:hasPermission(playerId, org.id, "canManageRanks")
        if not hasPerm then return false end
    end

    local success = db.removeOrganizationRank(rankId)

    if success then
        RecordManager:clearCache("organizations")
        local updatedOrg = RecordManager:get("organizations", org.id)
        if updatedOrg then
            TriggerClientEvent("crime:updateOrganization", -1, org.id, { ranks = updatedOrg.ranks })
        end
    end

    return success
end)

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:useIllegalMedic"
--   Server-side validation + healing for the illegal medic
--   interaction.  Verifies the player is within range and has
--   enough money, then charges them and revives them.
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:useIllegalMedic", function(medicIndex)
    local playerId  = source
    local medicData = Config.IllegalMedic[medicIndex]

    if not medicData then
        Error("crime:useIllegalMedic", "Invalid medic ID:", medicIndex)
        return
    end

    -- Anti-cheat: ensure the player is close enough to the NPC
    local playerPos  = GetEntityCoords(GetPlayerPed(playerId))
    local distToMedic = #(playerPos - medicData.coords.xyz)

    if distToMedic > 5.0 then
        Error("crime:useIllegalMedic", "Player is too far from the medic. He is CHEATER!", playerId)
        return
    end

    -- Verify the player has enough money
    local balance = sfr:getAccountMoney(playerId, "money")
    if balance < medicData.price then
        Notification(playerId, i18n.t("not_enough_money", { amount = medicData.price }), "error")
        return
    end

    -- Charge the player and revive them
    sfr:removeAccountMoney(playerId, "money", medicData.price)
    RevivePlayer(playerId)
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getSeasonPass"
--   Returns the active season pass data for the requesting
--   player's organization.  Returns nil if expired or not found.
--   If `orgId` is provided, uses that org; otherwise finds the
--   org the player belongs to.
-- ──────────────────────────────────────────────────────────

-- Local helper: parse a MySQL datetime string → Unix timestamp
local function parseMySQLDateTime(dateStr)
    if type(dateStr) ~= "string" then return dateStr end

    return os.time({
        year  = tonumber(string.sub(dateStr, 1,  4)),
        month = tonumber(string.sub(dateStr, 6,  7)),
        day   = tonumber(string.sub(dateStr, 9,  10)),
        hour  = tonumber(string.sub(dateStr, 12, 13)) or 0,
        min   = tonumber(string.sub(dateStr, 15, 16)) or 0,
        sec   = tonumber(string.sub(dateStr, 18, 19)) or 0,
    })
end

lib.callback.register("crime:getSeasonPass", function(playerId, orgId)
    local playerIdentifier = sfr:getIdentifier(playerId)
    local org

    if orgId then
        org = RecordManager:get("organizations", orgId)
    else
        -- Find the organization that includes this player
        org = RecordManager:get("organizations", function(orgData)
            if orgData.members then
                return table.find(orgData.members, function(member)
                    return member.identifier == playerIdentifier
                end)
            end
        end)
    end

    if not org then return nil end

    local seasonPass = db.getSeasonPass()
    if not seasonPass then return nil end

    -- Check expiry
    if seasonPass.endDate then
        local endTimestamp = parseMySQLDateTime(seasonPass.endDate)
        if endTimestamp < os.time() then
            Debug("crime:getSeasonPass", "Season pass has expired")
            return nil
        end
    end

    return seasonPass
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:claimSeasonPassReward"
--   Claims a season-pass reward for the requesting player's
--   organization.  Handles money, vehicle, and item rewards.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:claimSeasonPassReward",
    function(playerId, orgId, rewardLevel, rewardTier)

    if not orgId then orgId = sv_bossmenu:getOrganizationId(playerId) end
    local playerIdentifier = sfr:getIdentifier(playerId)
    local org = RecordManager:get("organizations", orgId)

    if not org then
        Error("crime:claimSeasonPassReward", "Organization not found:", orgId)
        return false
    end

    -- Verify membership
    local isMember = false
    if org.owner and org.owner.identifier == playerIdentifier then
        isMember = true
    elseif org.members then
        for _, member in ipairs(org.members) do
            if member.identifier == playerIdentifier then
                isMember = true
                break
            end
        end
    end

    if not isMember then
        Error("crime:claimSeasonPassReward", "Player is not a member of organization:", orgId)
        return false
    end

    local seasonPass = db.getSeasonPass()
    if not seasonPass then
        Error("crime:claimSeasonPassReward", "Season pass not found")
        return false
    end

    -- Find the reward entry for this level + tier
    local rewardEntry = nil
    if seasonPass.rewards then
        for _, reward in ipairs(seasonPass.rewards) do
            if reward.level == rewardLevel and reward.tier == rewardTier then
                rewardEntry = reward
                break
            end
        end
    end

    if not rewardEntry then
        Error("crime:claimSeasonPassReward", "Reward not found:", rewardLevel, rewardTier)
        return false
    end

    -- Load current progress for this organization
    local progress = db.getOrganizationSeasonPassProgress(orgId, seasonPass.id)

    -- Check this reward hasn't already been claimed
    if progress then
        local rewardKey = tostring(rewardLevel) .. "-" .. rewardTier
        local claimed   = progress.claimed_rewards or {}
        for _, claimedKey in ipairs(claimed) do
            if claimedKey == rewardKey then
                Error("crime:claimSeasonPassReward", "Reward already claimed:", rewardKey)
                return false
            end
        end
    end

    -- Verify the organization's level is high enough
    local levelData = db.getOrganizationLevelData(orgId)
    if not levelData or rewardLevel > levelData.level then
        Error("crime:claimSeasonPassReward",
            "Organization level too low. Required:", rewardLevel,
            "Current:", levelData and levelData.level or 0)
        return false
    end

    -- Premium tier requires the org to have purchased premium
    if rewardTier == "premium" then
        if not (progress and progress.has_premium) then
            Error("crime:claimSeasonPassReward", "Premium required for this reward")
            return false
        end
    end

    -- ── Distribute the reward ──────────────────────────
    local rewardGiven = false
    local rewardType  = rewardEntry.type

    if rewardType == "money" then
        -- Money reward → deposit into org finance
        local moneyType   = rewardEntry.moneyType   or "money"
        local moneyAmount = rewardEntry.moneyAmount  or 0

        if moneyAmount > 0 then
            local deposited = OrganizationFinanceDB:updateMoney(orgId, moneyAmount, "deposit", "clean")
            if deposited then
                local firstName, lastName = sfr:getUserName(playerId)
                local playerFullName = firstName .. " " .. lastName
                OrganizationFinanceDB:createTransaction(orgId, {
                    type        = "deposit",
                    amount      = moneyAmount,
                    money_type  = moneyType,
                    description = "Season Pass Reward - Level " .. rewardLevel .. " (" .. rewardTier .. ")",
                    identifier  = playerIdentifier,
                    name        = playerFullName,
                    status      = "completed",
                })
                rewardGiven = true
            end
        end

    elseif rewardType == "vehicle" then
        -- Vehicle reward → add to org garage
        local vehicleModel = rewardEntry.vehicleModel
        if vehicleModel then
            local vehicleLabel = rewardEntry.label or vehicleModel

            -- Generate a random plate: first 3 chars of model + 4 random digits
            local plate = string.upper(
                string.sub(vehicleModel, 1, 3) .. math.random(1000, 9999)
            )

            local meta = {
                source    = "season_pass",
                level     = rewardLevel,
                tier      = rewardTier,
                reward_id = seasonPass.id,
            }

            local added = db.addOrganizationVehicle(orgId, vehicleModel, vehicleLabel, plate, nil, meta)
            if added then
                rewardGiven = true
            end
        end

    elseif rewardType == "item" then
        -- Item reward → add to player inventory
        local itemName   = rewardEntry.itemName
        local itemAmount = rewardEntry.itemAmount or 1

        if itemName and itemAmount > 0 then
            local added = sfr:addItem(playerId, itemName, itemAmount)
            rewardGiven  = added or false
        end
    end

    if not rewardGiven then
        Error("crime:claimSeasonPassReward", "Failed to give reward")
        return false
    end

    -- Mark the reward as claimed in the DB
    db.claimSeasonPassReward(orgId, seasonPass.id, rewardLevel, rewardTier)

    -- Notify all online members
    local spFirstName, spLastName = sfr:getUserName(playerId)
    local playerName  = spFirstName .. " " .. spLastName
    local rewardLabel = rewardEntry.label
                     or ("Level " .. rewardLevel .. " " .. rewardTier .. " reward")

    if org.members then
        for _, member in ipairs(org.members) do
            local memberPlayerId = sfr:getSourceFromIdentifier(member.identifier)
            if memberPlayerId then
                Notification(memberPlayerId,
                    i18n.t("bossmenu.seasonpass.reward_claimed", {
                        player = playerName,
                        reward = rewardLabel,
                    }),
                    "success"
                )
            end
        end
    end

    return true
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:purchaseSeasonPassPremium"
--   Deducts the premium cost from the organization's finances
--   and unlocks premium-tier season-pass rewards.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:purchaseSeasonPassPremium", function(playerId, orgId)
    if not orgId then orgId = sv_bossmenu:getOrganizationId(playerId) end
    local playerIdentifier = sfr:getIdentifier(playerId)
    local org = RecordManager:get("organizations", orgId)

    if not org then
        Error("crime:purchaseSeasonPassPremium", "Organization not found:", orgId)
        return false
    end

    -- Only the owner or a boss-rank member can purchase premium
    local isOwner = org.owner and org.owner.identifier == playerIdentifier
    local isBoss  = false

    if org.members then
        for _, member in ipairs(org.members) do
            if member.identifier == playerIdentifier and member.is_boss then
                isBoss = true
                break
            end
        end
    end

    if not isOwner and not isBoss then
        Error("crime:purchaseSeasonPassPremium", "Player does not have permission to purchase premium")
        return false
    end

    local seasonPass = db.getSeasonPass()
    if not seasonPass then
        Error("crime:purchaseSeasonPassPremium", "Season pass not found")
        return false
    end

    local progress = db.getOrganizationSeasonPassProgress(orgId, seasonPass.id)
    if progress and progress.has_premium then
        Error("crime:purchaseSeasonPassPremium", "Organization already has premium")
        return false
    end

    -- Check org has enough clean money
    local finances   = OrganizationFinanceDB:getFinanceOverview(orgId)
    local cleanMoney = (finances and finances.clean_money) or 0
    local price      = seasonPass.price or 0

    if cleanMoney < price then
        Error("crime:purchaseSeasonPassPremium",
            "Insufficient funds. Required:", price, "Available:", cleanMoney)
        Notification(playerId, i18n.t("boss_not_enough_money", { amount = price }), "error")
        return false
    end

    -- Deduct the cost
    local deducted = OrganizationFinanceDB:updateMoney(orgId, price, "withdraw", "clean")
    if not deducted then
        Error("crime:purchaseSeasonPassPremium", "Failed to deduct money from organization finance")
        return false
    end

    local ppFirstName, ppLastName = sfr:getUserName(playerId)
    local playerName = ppFirstName .. " " .. ppLastName

    -- Record the transaction
    OrganizationFinanceDB:createTransaction(orgId, {
        type        = "withdraw",
        amount      = -price,
        money_type  = "money",
        description = "Season Pass Premium Purchase",
        identifier  = playerIdentifier,
        name        = playerName,
        status      = "completed",
    })

    -- Activate premium
    local activated = db.setOrganizationSeasonPassPremium(orgId, seasonPass.id, true)
    if not activated then
        -- Refund on failure
        OrganizationFinanceDB:updateMoney(orgId, price, "deposit", "clean")
        Error("crime:purchaseSeasonPassPremium", "Failed to set premium status")
        return false
    end

    -- Notify all online members
    if org.members then
        for _, member in ipairs(org.members) do
            local memberPlayerId = sfr:getSourceFromIdentifier(member.identifier)
            if memberPlayerId then
                Notification(memberPlayerId,
                    i18n.t("bossmenu.seasonpass.premium_purchased", { player = playerName }),
                    "success"
                )
            end
        end
    end

    Notification(playerId, i18n.t("bossmenu.seasonpass.premium_purchase_success"), "success")
    return true
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getOrganizationSeasonPassData"
--   Returns a combined payload with the active season pass,
--   the organization's current level/XP, premium status, and
--   claimed rewards.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getOrganizationSeasonPassData", function(playerId, orgId)
    if not orgId then orgId = sv_bossmenu:getOrganizationId(playerId) end
    local playerIdentifier = sfr:getIdentifier(playerId)
    local org = RecordManager:get("organizations", orgId)
    if not org then return nil end

    -- Verify membership
    local isMember = false
    if org.owner and org.owner.identifier == playerIdentifier then
        isMember = true
    elseif org.members then
        for _, member in ipairs(org.members) do
            if member.identifier == playerIdentifier then
                isMember = true
                break
            end
        end
    end

    if not isMember then return nil end

    local seasonPass = db.getSeasonPass()
    if not seasonPass then return nil end

    -- Check expiry
    if seasonPass.endDate then
        local endTimestamp = parseMySQLDateTime(seasonPass.endDate)
        if endTimestamp < os.time() then
            return nil
        end
    end

    -- Level/XP data (default if no record exists yet)
    local levelData = db.getOrganizationLevelData(orgId)
    if not levelData then
        levelData = { level = 1, experience = 0, experienceToNext = 1000 }
    end

    -- Progress record
    local progress    = db.getOrganizationSeasonPassProgress(orgId, seasonPass.id)
    local hasPremium  = progress and progress.has_premium  or false
    local claimed     = progress and progress.claimed_rewards or {}

    return {
        seasonPass      = seasonPass,
        level           = levelData.level,
        experience      = levelData.experience,
        experienceToNext = levelData.experienceToNext,
        hasPremium      = hasPremium,
        claimedRewards  = claimed,
    }
end)

-- ──────────────────────────────────────────────────────────
-- playerDropped — remove from ActivePlayers on disconnect
-- ──────────────────────────────────────────────────────────
AddEventHandler("playerDropped", function()
    ActivePlayers[source] = nil
end)

-- ──────────────────────────────────────────────────────────
-- Register usable item: Crime Tablet
--   When a player uses the configured tablet item, trigger
--   the tablet UI open event on their client.
-- ──────────────────────────────────────────────────────────
sfr:registerUsableItem(Config.CrimeTablet.Item, function(playerId)
    TriggerClientEvent("crime:tablet:open", playerId)
end)
