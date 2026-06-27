if Config.Inventory ~= 'qb' then
    return
end

sv_inventory.imagePath = 'nui://qb-inventory/html/images/'

-- PURPOSE: Format original item list to include `image`, `isWeapon`, and `objectModel` properties.
-- `objectModel` can be nil if your inventory doesn't support it or if its a weapon.
---@diagnostic disable-next-line: duplicate-set-field
function sv_inventory:formatItemList()
    local itemList = sfr:getItemList()
    while not itemList or not next(itemList) do
        Wait(500)
        itemList = sfr:getItemList()
        Debug('Waiting for item list to be populated...')
    end
    for _, v in pairs(itemList) do
        local image = v.image or 'default.png'
        v.image = self.imagePath .. image
    end
    return itemList
end

---@param source number
---@param items table
---@diagnostic disable-next-line: duplicate-set-field
function sv_inventory:setInventory(source, items)
    exports['qb-inventory']:SetInventory(source, items)
end
