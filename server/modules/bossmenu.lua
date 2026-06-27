if not _G.sv_bossmenu then
    _G.sv_bossmenu = {
        players = {}
    }
end

function GetFullPermissions()
    return {
        canAccessWardrobe = true,
        canAccessStash = true,
        canAccessCharge = true,
        canManageMembers = true,
        canManageFinance = true,
        canManageRanks = true,
        canSetLocations = true,
        canBuyUpgrades = true,
        canAccessBossMenu = true,
        canAccessMembers = true,
        canAccessRanks = true,
        canAccessFinance = true,
        canAccessGarage = true,
        canAccessVehicleStore = true,
        canAccessUpgradeInterior = true,
        canAccessManagement = true,
        canAccessMoneyLaundering = true,
    }
end

function sv_bossmenu.triggerEvent(self, orgId, eventName, ...)
    local playerList = sv_bossmenu.players[orgId]
    if not playerList then return end
    for _, playerId in pairs(playerList) do
        TriggerClientEvent(eventName, playerId, ...)
    end
end

function sv_bossmenu.isPlayerInBossMenu(self, orgId, playerId)
    if not orgId or not playerId then return false end
    local playerList = self.players[orgId]
    if not playerList then return false end
    for _, id in ipairs(playerList) do
        if id == playerId then return true end
    end
    return false
end

function sv_bossmenu.getOrganizationId(self, playerId)
    for orgId, playerList in pairs(self.players) do
        if playerList and type(playerList) == "table" then
            for _, id in ipairs(playerList) do
                if id == playerId then return orgId end
            end
        end
    end
    return nil
end

function sv_bossmenu.hasAccess(self, playerId, orgId)
    local identifier = sfr:getIdentifier(playerId)
    local orgData = RecordManager:get("organizations", orgId)
    if not orgData then return false end
    -- Owner always has access
    if orgData.owner and orgData.owner.identifier == identifier then
        return true
    end
    if orgData.members then
        for _, member in ipairs(orgData.members) do
            if member.identifier == identifier then
                return true
            end
        end
    end
    return false
end

function sv_bossmenu.hasPermission(self, playerId, orgId, permissionName)
    local identifier = sfr:getIdentifier(playerId)
    local orgData = RecordManager:get("organizations", orgId)
    if not orgData then return false end

    if orgData.owner and orgData.owner.identifier == identifier then
        return true
    end

    local member = nil
    if orgData.members then
        for _, m in ipairs(orgData.members) do
            if m.identifier == identifier then
                member = m
                break
            end
        end
    end

    if not member then return false end
    if member.is_boss then return true end

    if member.rank_id and orgData.ranks then
        for _, rank in ipairs(orgData.ranks) do
            if rank.id == member.rank_id and rank.permissions then
                return rank.permissions[permissionName] == true
            end
        end
    end

    return false
end

-- ⚠️ Returns true for ANY member of the organization once found.
-- The is_boss and hasPermission("canManageFinance") checks are redundant
-- because the function unconditionally returns true after them for any matched member.
function sv_bossmenu.hasFinanceAccess(self, playerId, orgId)
    local identifier = sfr:getIdentifier(playerId)
    local orgData = RecordManager:get("organizations", orgId)
    if not orgData then
        Error("sv_bossmenu:hasFinanceAccess", "Organization not found", orgId)
        return false
    end
    if orgData.owner and orgData.owner.identifier == identifier then
        return true
    end
    if orgData.members then
        for _, member in ipairs(orgData.members) do
            if member.identifier == identifier then
                if member.is_boss then return true end
                if sv_bossmenu:hasPermission(playerId, orgId, "canManageFinance") then return true end
                return false
            end
        end
    end
    return false
end

-- ============================================================
-- Callbacks
-- ============================================================

lib.callback.register("crime:getBossMenuData", function(playerId, orgId)
    if not orgId then
        Error("crime:getBossMenuData", "orgId is required")
        return nil
    end

    local identifier = sfr:getIdentifier(playerId)
    local orgData = RecordManager:get("organizations", orgId)

    if not sv_bossmenu:hasAccess(playerId, orgId) then
        Error("crime:getBossMenuData", "Player does not have access to organization:", orgId)
        return nil
    end

    if not sv_bossmenu:hasPermission(playerId, orgId, "canAccessBossMenu") then
        Error("crime:getBossMenuData", "Player does not have permission to access boss menu:", orgId)
        return nil
    end

    local isOwner = orgData.owner and (orgData.owner.identifier == identifier)

    local member = table.find(orgData.members, function(m)
        return m.identifier == identifier
    end)

    if not isOwner and not member then
        Error("crime:getBossMenuData", "Player is not a member of organization:", orgId)
        return nil
    end

    local permissions = {}

    if isOwner then
        permissions = GetFullPermissions()
    elseif member and member.is_boss then
        permissions = GetFullPermissions()
    elseif member and member.rank_id and orgData.ranks then
        for _, rank in ipairs(orgData.ranks) do
            if rank.id == member.rank_id and rank.permissions then
                permissions = rank.permissions
                break
            end
        end
    end

    local financeOverview = OrganizationFinanceDB:getFinanceOverview(orgId)
    local userCash = sfr:getAccountMoney(playerId, "money")
    local userBank = sfr:getAccountMoney(playerId, "bank")
    local userBlackMoney = sfr:getAccountMoney(playerId, "black_money")

    local finance = {
        clean_money = (financeOverview and financeOverview.clean_money) or 0,
        dirty_money = (financeOverview and financeOverview.dirty_money) or 0,
        transactions = OrganizationFinanceDB:getTransactions(orgId, 50, 0),
        userCash = userCash,
        userBank = userBank,
        userBlackMoney = userBlackMoney,
        money_types = Config.FinanceMoneyTypes or { "money", "bank" },
    }

    if financeOverview then
        financeOverview.userCash = userCash
        financeOverview.userBank = userBank
        financeOverview.userBlackMoney = userBlackMoney
        finance.overview = financeOverview
    end

    -- Fetch org level/XP stats for dashboard display
    local orgStats = db.getOrganizationLevelData(orgId) or {
        level            = 1,
        experience       = 0,
        experienceToNext = Config.MissionSystem.XPFormula.LevelUpXP(1),
    }

    return {
        finance     = finance,
        vehicles    = {},
        upgrades    = orgData.upgrades or {},
        permissions = permissions,
        isOwner     = isOwner,
        member      = member or (isOwner and {
            identifier = identifier,
            name       = orgData.owner.name or "",
            is_boss    = true,
        }) or nil,
        stats       = orgStats,
    }
end)

lib.callback.register("crime:getOrganizationFinanceOverview", function(playerId, orgId)
    if not orgId then
        orgId = sv_bossmenu:getOrganizationId(playerId)
    end

    Debug("crime:getOrganizationFinanceOverview", playerId, orgId)

    if not orgId then
        Error("crime:getOrganizationFinanceOverview", "Organization ID is required")
        return {}
    end

    local overview = OrganizationFinanceDB:getFinanceOverview(orgId)
    if not overview then return {} end

    overview.userCash = sfr:getAccountMoney(playerId, "money")
    overview.userBank = sfr:getAccountMoney(playerId, "bank")
    overview.userBlackMoney = sfr:getAccountMoney(playerId, "black_money")

    return overview
end)

lib.callback.register("crime:getOrganizationTransactions", function(playerId, orgId, limit, offset)
    Debug("crime:getOrganizationTransactions", playerId, orgId, limit, offset)

    if not orgId then
        Error("crime:getOrganizationTransactions", "Organization ID is required")
        return {}
    end

    if not sv_bossmenu:hasFinanceAccess(playerId, orgId) then
        Error("crime:getOrganizationTransactions", "Access denied for organization:", orgId)
        return {}
    end

    if not sv_bossmenu:hasPermission(playerId, orgId, "canAccessFinance") then
        Error("crime:getOrganizationTransactions", "Permission denied for finance category")
        return {}
    end

    return OrganizationFinanceDB:getTransactions(orgId, limit, offset)
end)

lib.callback.register("crime:depositOrganizationMoney", function(playerId, orgId, amount, moneyType, description, reference)
    Debug("crime:depositOrganizationMoney", playerId, orgId, amount, moneyType, description, reference)

    if not orgId or not amount or not moneyType then
        Error("crime:depositOrganizationMoney", "Organization ID, amount and money type are required")
        return { success = false, message = "Invalid data" }
    end

    if amount <= 0 then
        Error("crime:depositOrganizationMoney", "Invalid amount")
        return { success = false, message = "Invalid amount" }
    end

    if not sv_bossmenu:hasFinanceAccess(playerId, orgId) then
        Error("crime:depositOrganizationMoney", "Access denied for organization:", orgId)
        return { success = false, message = "Access denied" }
    end

    if not sv_bossmenu:hasPermission(playerId, orgId, "canAccessFinance") then
        Error("crime:depositOrganizationMoney", "Permission denied for finance category")
        return { success = false, message = "Permission denied" }
    end

    local playerBalance = sfr:getAccountMoney(playerId, moneyType)
    if amount > playerBalance then
        Debug("crime:depositOrganizationMoney", "Insufficient funds")
        return { success = false, message = "Insufficient funds" }
    end

    local removeSuccess = sfr:removeAccountMoney(playerId, moneyType, amount)
    if not removeSuccess then
        Error("crime:depositOrganizationMoney", "Failed to remove money from player")
        return { success = false, message = "Failed to remove money" }
    end

    local identifier = sfr:getIdentifier(playerId)
    local firstName, lastName = sfr:getUserName(playerId)
    local fullName = firstName .. " " .. lastName
    local moneyCategory = (moneyType == "black_money") and "dirty" or "clean"

    local transactionSuccess, transactionId = OrganizationFinanceDB:createTransaction(orgId, {
        type = "deposit",
        amount = amount,
        money_type = moneyType,
        description = description or "Money deposit",
        identifier = identifier,
        name = fullName,
        reference = reference,
        status = "completed",
    })

    if not transactionSuccess then
        sfr:addAccountMoney(playerId, moneyType, amount)
        Error("crime:depositOrganizationMoney", "Failed to create transaction")
        return { success = false, message = "Failed to create transaction" }
    end

    local updateSuccess = OrganizationFinanceDB:updateMoney(orgId, amount, "deposit", moneyCategory)
    if not updateSuccess then
        sfr:addAccountMoney(playerId, moneyType, amount)
        Error("crime:depositOrganizationMoney", "Failed to update money")
        return { success = false, message = "Failed to update money" }
    end

    sv_bossmenu:triggerEvent(orgId, "crime:updateBossMenuFinance")
    Notification(playerId, "Money deposited successfully", "success")

    return { success = true, transactionId = transactionId }
end)

lib.callback.register("crime:withdrawOrganizationMoney", function(playerId, orgId, amount, moneyType, description, reference)
    Debug("crime:withdrawOrganizationMoney", playerId, orgId, amount, moneyType, description, reference)

    if not orgId or not amount or not moneyType then
        Error("crime:withdrawOrganizationMoney", "Organization ID, amount and money type are required")
        return { success = false, message = "Invalid data" }
    end

    if amount <= 0 then
        Error("crime:withdrawOrganizationMoney", "Invalid amount")
        return { success = false, message = "Invalid amount" }
    end

    local identifier = sfr:getIdentifier(playerId)
    local orgData = RecordManager:get("organizations", orgId)

    -- Owner always has access; otherwise check canManageFinance permission
    local hasWithdrawAccess = false
    if orgData.owner and orgData.owner.identifier == identifier then
        hasWithdrawAccess = true
    else
        hasWithdrawAccess = sv_bossmenu:hasPermission(playerId, orgId, "canManageFinance")
    end

    if not hasWithdrawAccess then
        Error("crime:withdrawOrganizationMoney", "Access denied for organization:", orgId)
        return { success = false, message = "Access denied. You need permission to withdraw money." }
    end

    if not sv_bossmenu:hasPermission(playerId, orgId, "canAccessFinance") then
        Error("crime:withdrawOrganizationMoney", "Permission denied for finance category")
        return { success = false, message = "Permission denied" }
    end

    local financeData = OrganizationFinanceDB:getFinance(orgId)
    local availableCleanMoney = financeData and (financeData.clean_money or 0) or 0

    if not financeData or amount > availableCleanMoney then
        Error("crime:withdrawOrganizationMoney", "Insufficient funds")
        return { success = false, message = "Insufficient funds" }
    end

    local firstName, lastName = sfr:getUserName(playerId)
    local fullName = firstName .. " " .. lastName

    local transactionSuccess, transactionId = OrganizationFinanceDB:createTransaction(orgId, {
        type = "withdraw",
        amount = -amount,
        money_type = moneyType,
        description = description or "Money withdrawal",
        identifier = identifier,
        name = fullName,
        reference = reference,
        status = "completed",
    })

    if not transactionSuccess then
        Error("crime:withdrawOrganizationMoney", "Failed to create transaction")
        return { success = false, message = "Failed to create transaction" }
    end

    local updateSuccess = OrganizationFinanceDB:updateMoney(orgId, amount, "withdraw", "clean")
    if not updateSuccess then
        Error("crime:withdrawOrganizationMoney", "Failed to update money")
        return { success = false, message = "Failed to update money" }
    end

    sfr:addAccountMoney(playerId, moneyType, amount)
    sv_bossmenu:triggerEvent(orgId, "crime:updateBossMenuFinance")
    Notification(playerId, "Money withdrawn successfully", "success")

    return { success = true, transactionId = transactionId }
end)

lib.callback.register("crime:getOrganizationFinanceAnalytics", function(playerId, orgId)
    Debug("crime:getOrganizationFinanceAnalytics", playerId, orgId)

    if not orgId then
        Error("crime:getOrganizationFinanceAnalytics", "Organization ID is required")
        return {}
    end

    if not sv_bossmenu:hasFinanceAccess(playerId, orgId) then
        Error("crime:getOrganizationFinanceAnalytics", "Access denied for organization:", orgId)
        return {}
    end

    if not sv_bossmenu:hasPermission(playerId, orgId, "canAccessFinance") then
        Error("crime:getOrganizationFinanceAnalytics", "Permission denied for finance category")
        return {}
    end

    return OrganizationFinanceDB:getFinanceAnalytics(orgId)
end)

lib.callback.register("crime:getClosestPlayers", function(playerId)
    local orgId = sv_bossmenu:getOrganizationId(playerId)
    if not orgId then return {} end

    local orgData = RecordManager:get("organizations", orgId)
    if not orgData then return {} end

    local closestPlayers = {}
    local playerPed = GetPlayerPed(playerId)

    for _, serverId in pairs(GetPlayers()) do
        if serverId == tostring(playerId) then
            goto continue
        end

        local targetId = tonumber(serverId)
        local targetPed = GetPlayerPed(targetId)
        local distance = #(GetEntityCoords(targetPed) - GetEntityCoords(playerPed))

        if distance > 10.0 then
            goto continue
        end

        local targetIdentifier = sfr:getIdentifier(targetId)

        local isAlreadyMember = table.find(orgData.members, function(m)
            return m.identifier == targetIdentifier
        end)

        if isAlreadyMember then
            goto continue
        end

        if db.isPlayerInAnyOrganization(targetIdentifier, orgId) then
            goto continue
        end

        local firstName, lastName = sfr:getUserName(targetId)
        if not firstName or not lastName then
            goto continue
        end

        table.insert(closestPlayers, {
            id = targetId,
            name = firstName .. " " .. lastName,
        })

        ::continue::
    end

    return closestPlayers
end)

lib.callback.register("crime:getOrganizationManagement", function(playerId, orgId)
    if not orgId then
        Error("crime:getOrganizationManagement", "orgId is required")
        return { lights = {}, cameras = {}, upgrades = {} }
    end

    if not sv_bossmenu:hasAccess(playerId, orgId) then
        Error("crime:getOrganizationManagement", "Access denied for organization:", orgId)
        return { lights = {}, cameras = {}, upgrades = {} }
    end

    if not sv_bossmenu:hasPermission(playerId, orgId, "canAccessManagement") then
        Error("crime:getOrganizationManagement", "Permission denied for management category")
        return { lights = {}, cameras = {}, upgrades = {} }
    end

    local orgData = RecordManager:get("organizations", orgId)
    local upgrades = (orgData and orgData.upgrades) or {}

    return {
        lights = {},
        cameras = {},
        upgrades = upgrades,
    }
end)

lib.callback.register("crime:buyOrganizationUpgrade", function(playerId, orgId, upgradeName)
    if not orgId or not upgradeName then
        Error("crime:buyOrganizationUpgrade", "orgId and upgradeName are required")
        return { success = false, message = "Invalid data" }
    end

    if not sv_bossmenu:hasAccess(playerId, orgId) then
        Error("crime:buyOrganizationUpgrade", "Access denied for organization:", orgId)
        return { success = false, message = "Access denied" }
    end

    if not sv_bossmenu:hasPermission(playerId, orgId, "canBuyUpgrades") then
        Error("crime:buyOrganizationUpgrade", "Permission denied for buying upgrades:", orgId)
        return { success = false, message = "Permission denied" }
    end

    local upgradeConfig = nil
    for _, upgrade in ipairs(Config.Upgrades) do
        if upgrade.name == upgradeName then
            upgradeConfig = upgrade
            break
        end
    end

    if not upgradeConfig then
        Error("crime:buyOrganizationUpgrade", "Upgrade not found:", upgradeName)
        return { success = false, message = "Upgrade not found" }
    end

    local orgData = RecordManager:get("organizations", orgId)
    if not orgData then
        return { success = false, message = "Organization not found" }
    end

    local currentLevel = 0
    if orgData.upgrades then
        for _, upgrade in ipairs(orgData.upgrades) do
            if upgrade.name == upgradeName then
                currentLevel = tonumber(upgrade.level) or 0
                break
            end
        end
    end

    if currentLevel >= upgradeConfig.maxLevel then
        return { success = false, message = "Maximum level reached" }
    end

    local nextLevel = currentLevel + 1
    local nextLevelData = upgradeConfig.levels[nextLevel]

    if not nextLevelData then
        Error("crime:buyOrganizationUpgrade", "Next level data not found for upgrade:", upgradeName, "level:", nextLevel)
        return { success = false, message = "Invalid upgrade level" }
    end

    local financeData = OrganizationFinanceDB:getFinance(orgId)
    local availableMoney = financeData and tonumber(financeData.clean_money) or 0
    local upgradePrice = tonumber(nextLevelData.price) or 0

    if not financeData or availableMoney < upgradePrice then
        return { success = false, message = "Insufficient funds" }
    end

    local deductSuccess = OrganizationFinanceDB:updateMoney(orgId, upgradePrice, "withdraw", "clean")
    if not deductSuccess then
        Error("crime:buyOrganizationUpgrade", "Failed to deduct money")
        return { success = false, message = "Failed to process payment" }
    end

    local identifier = sfr:getIdentifier(playerId)
    local firstName, lastName = sfr:getUserName(playerId)
    local fullName = firstName .. " " .. lastName

    OrganizationFinanceDB:createTransaction(orgId, {
        type = "expense",
        amount = -upgradePrice,
        money_type = "money",
        description = "Upgrade purchase: " .. upgradeConfig.title .. " (Level " .. nextLevel .. ")",
        identifier = identifier,
        name = fullName,
        status = "completed",
    })

    local upgradeApplied = db.setOrganizationUpgrade(playerId, orgId, upgradeName, nextLevel)
    if not upgradeApplied then
        OrganizationFinanceDB:updateMoney(orgId, upgradePrice, "deposit", "clean")
        Error("crime:buyOrganizationUpgrade", "Failed to update upgrade")
        return { success = false, message = "Failed to apply upgrade" }
    end

    if not orgData.upgrades then
        orgData.upgrades = {}
    end

    local existingFound = false
    for _, upgrade in ipairs(orgData.upgrades) do
        if upgrade.name == upgradeName then
            upgrade.level = nextLevel
            existingFound = true
            break
        end
    end

    if not existingFound then
        orgData.upgrades[#orgData.upgrades + 1] = {
            name = upgradeName,
            level = nextLevel,
        }
    end

    RecordManager:clearCache("organizations")
    local refreshedOrgData = RecordManager:get("organizations", orgId)

    if refreshedOrgData then
        TriggerClientEvent("crime:updateOrganization", -1, orgId, {
            upgrades = refreshedOrgData.upgrades,
        })
    end

    sv_bossmenu:triggerEvent(orgId, "crime:updateBossMenuUpgrades")
    Notification(playerId, "Upgrade purchased successfully: " .. upgradeConfig.title .. " (Level " .. nextLevel .. ")", "success")

    return { success = true, message = "Upgrade purchased successfully" }
end)

lib.callback.register("crime:setOrganizationLocation", function(playerId, orgId, locationType, coords)
    if not orgId or not locationType or not coords then
        Error("crime:setOrganizationLocation", "orgId, locationType and coords are required")
        return { success = false, message = "Invalid data" }
    end

    if locationType ~= "wardrobe" and locationType ~= "stash" and locationType ~= "charge" then
        Error("crime:setOrganizationLocation", "Invalid location type:", locationType)
        return { success = false, message = "Invalid location type" }
    end

    if not sv_bossmenu:hasAccess(playerId, orgId) then
        Error("crime:setOrganizationLocation", "Access denied for organization:", orgId)
        return { success = false, message = "Access denied" }
    end

    local orgData = RecordManager:get("organizations", orgId)
    if not orgData then
        Error("crime:setOrganizationLocation", "Organization not found:", orgId)
        return { success = false, message = "Organization not found" }
    end

    local identifier = sfr:getIdentifier(playerId)

    -- Owner always has access; otherwise check canSetLocations permission
    local hasLocationPermission = false
    if orgData.owner and orgData.owner.identifier == identifier then
        hasLocationPermission = true
    else
        hasLocationPermission = sv_bossmenu:hasPermission(playerId, orgId, "canSetLocations")
    end

    if not hasLocationPermission then
        Error("crime:setOrganizationLocation", "Permission denied. You need permission to set locations.")
        return { success = false, message = "Permission denied. You need permission to set locations." }
    end

    local locationsCoords = orgData.locations_coords or {}
    locationsCoords[locationType] = coords

    local updateSuccess = db.updateOrganization(playerId, orgId, { locations_coords = locationsCoords })
    if not updateSuccess then
        Error("crime:setOrganizationLocation", "Failed to update location in database")
        return { success = false, message = "Failed to update location" }
    end

    orgData.locations_coords = locationsCoords

    RecordManager:clearCache("organizations")
    local refreshedOrgData = RecordManager:get("organizations", orgId)

    if refreshedOrgData then
        TriggerClientEvent("crime:updateOrganization", -1, orgId, {
            locations_coords = refreshedOrgData.locations_coords,
        })
    end

    Notification(playerId, "Location set successfully: " .. locationType, "success")

    return { success = true, message = "Location set successfully" }
end)

lib.callback.register("crime:getMemberDetails", function(playerId, orgId, memberIdentifier)
    if not orgId or not memberIdentifier then
        Error("crime:getMemberDetails", "orgId and identifier are required")
        return nil
    end

    if not sv_bossmenu:hasAccess(playerId, orgId) then
        Error("crime:getMemberDetails", "Access denied for organization:", orgId)
        return nil
    end

    if not sv_bossmenu:hasPermission(playerId, orgId, "canAccessMembers") then
        if not sv_bossmenu:hasPermission(playerId, orgId, "canAccessBossMenu") then
            Error("crime:getMemberDetails", "Permission denied for accessing members")
            return nil
        end
    end

    local memberDetails = db.getMemberDetails(orgId, memberIdentifier)
    if not memberDetails then
        Error("crime:getMemberDetails", "Member not found:", memberIdentifier)
        return nil
    end

    return memberDetails
end)

-- ============================================================
-- Net Events
-- ============================================================

RegisterNetEvent("crime:openBossMenu", function(orgId)
    local playerId = source

    if sv_bossmenu:isPlayerInBossMenu(orgId, playerId) then
        return
    end

    if not sv_bossmenu.players[orgId] then
        sv_bossmenu.players[orgId] = {}
    end

    sv_bossmenu.players[orgId][#sv_bossmenu.players[orgId] + 1] = playerId
    Debug("crime:openBossMenu", orgId, playerId)
end)

RegisterNetEvent("crime:closeBossMenu", function(orgId)
    local playerId = source
    if sv_bossmenu.players[orgId] then
        sv_bossmenu.players[orgId] = table.filter(sv_bossmenu.players[orgId], function(id)
            return id ~= playerId
        end)
    end
end)