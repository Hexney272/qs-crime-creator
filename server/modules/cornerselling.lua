-- ============================================================
-- server/modules/cornerselling.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Corner-selling drug system.  Handles fetching available drugs,
-- selling, robbery, and distributing items back to the seller.
-- ============================================================

-- Temporary storage for drugs stolen during a robbery
-- { item, amount } entries pending collection
local stolenDrugsQueue = {}

-- ──────────────────────────────────────────────────────────
-- local getAvailableDrugs(playerId)
--   Returns a table of drug items the player currently holds,
--   filtered to only items listed in Config.DrugsPrice.
--   Returns nil if the player has no relevant drugs.
-- ──────────────────────────────────────────────────────────
local function getAvailableDrugs(playerId)
    local drugs = {}

    for itemName in pairs(Config.DrugsPrice) do
        local itemData = sfr:getItem(playerId, itemName)
        if itemData.count > 0 then
            local itemLabel = (ItemList[itemName] and ItemList[itemName].label) or "Unknown"
            drugs[#drugs + 1] = {
                item   = itemName,
                amount = itemData.count,
                label  = itemLabel,
            }
        end
    end

    -- Return nil if the player has nothing to sell
    if #drugs > 0 then
        return drugs
    end
    return nil
end

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getAvailableDrugs"
--   Returns the player's sellable drug inventory.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getAvailableDrugs", function(playerId)
    return getAvailableDrugs(playerId)
end)

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:giveStealItems"
--   When a player collects stolen drugs (after being robbed),
--   this event restores the items from the stolen queue.
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:giveStealItems", function(itemName, amount)
    local playerId = source

    for i, entry in pairs(stolenDrugsQueue) do
        if entry.item == itemName and entry.amount == amount then
            sfr:addItem(playerId, itemName, amount)

            local itemLabel = (ItemList[itemName] and ItemList[itemName].label) or "Unknown"
            Notification(playerId,
                i18n.t("cornerselling.recovered_items", {
                    amount = amount,
                    item   = itemLabel,
                }),
                "success"
            )

            table.remove(stolenDrugsQueue, i)
            break
        end
    end
end)

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:sellCornerDrugs"
--   Processes a drug sale transaction.
--   Parameters:
--     drugIndex   – index into the player's available drug list
--     sellAmount  – number of units to sell
--     sellPrice   – total black_money to award
--     territoryId – (optional) territory ID for territory-war XP
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:sellCornerDrugs", function(drugIndex, sellAmount, sellPrice, territoryId)
    local playerId = source

    local availableDrugs = getAvailableDrugs(playerId)
    if not availableDrugs then return end

    local drugEntry = availableDrugs[drugIndex]
    if not drugEntry then return end

    local itemName = drugEntry.item

    -- Verify the player actually has enough of this drug
    local heldItem = sfr:getItem(playerId, itemName)
    if sellAmount > heldItem.count then return end

    -- Remove the items and pay the player
    sfr:removeItem(playerId, itemName, sellAmount)
    sfr:addAccountMoney(playerId, "black_money", sellPrice)

    -- Push refreshed drug list back to the client
    TriggerClientEvent("crime:refreshAvailableDrugs", playerId,
        getAvailableDrugs(playerId))

    -- Notify territory-war system if this sale counts toward a war
    if territoryId then
        TriggerEvent("crime:territoryWarDrugSale", playerId, territoryId, sellPrice)
    end
end)

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:robCornerDrugs"
--   Another player robs a seller's drugs during a corner-sell.
--   Removes the item from the victim and queues it for pickup.
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:robCornerDrugs", function(drugIndex, robAmount)
    local robberId = source

    local availableDrugs = getAvailableDrugs(robberId)
    if not availableDrugs then return end

    local drugEntry = availableDrugs[drugIndex]
    if not drugEntry then return end

    local itemName = drugEntry.item

    sfr:removeItem(robberId, itemName, robAmount)

    -- Queue the stolen drugs so the robber can collect them
    table.insert(stolenDrugsQueue, {
        item   = itemName,
        amount = robAmount,
    })

    -- Refresh the victim's drug list UI
    TriggerClientEvent("crime:refreshAvailableDrugs", robberId,
        getAvailableDrugs(robberId))
end)
