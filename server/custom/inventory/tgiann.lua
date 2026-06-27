-- if Config.Inventory ~= 'tgiann' then
--     return
-- end

-- local export = exports['tgiann-inventory']
-- local IMAGE_PATH = 'inventory_images/images'

-- local function setImagePath(path)
--     if path then
--         return path:match('^[%w]+://') and path or ('%s/%s'):format(IMAGE_PATH, path)
--     end
-- end

-- --ox_inventory/modules/items/shared.lua
-- ---@diagnostic disable-next-line: duplicate-set-field
-- function sv_inventory:formatItemList()
--     local invItems = export:Items()
--     local itemList = {}
--     for k, v in pairs(invItems) do
--         local defaultImage = k .. '.webp'

--         itemList[k] = {
--             name = k,
--             label = v.label,
--             image = setImagePath(v.image or v.client?.image or defaultImage),
--             client = v.client or {},
--         }
--     end
--     return itemList
-- end

if Config.Inventory ~= 'tgiann' then
    return
end

local IMAGE_PATH = 'nui://inventory_images/images' -- ✅ Must start with nui:// so the UI can access it
local export = exports['tgiann-inventory']

local function setImagePath(path)
    if not path or path == '' then return IMAGE_PATH .. '/default.webp' end

    -- If the path is already a URL (like http:// or https://), keep it as is
    if path:match('^[%w]+://') then
        return path
    end

    -- Ensure the extension is correct (.webp or .png)
    if not path:match('%.webp$') and not path:match('%.png$') and not path:match('%.jpg$') then
        path = path .. '.webp'
    end

    -- Return the full path
    return ('%s/%s'):format(IMAGE_PATH, path)
end

---@diagnostic disable-next-line: duplicate-set-field
function sv_inventory:formatItemList()
    local success, invItems = pcall(function()
        return export:GetItemList() or export:Items()
    end)

    if not success or not invItems then
        print('⚠️ [TGIANN-INVENTORY] Failed to get item list.')
        return {}
    end

    local itemList = {}
    for k, v in pairs(invItems) do
        local defaultImage = k .. '.webp'
        local label = v.label or k:gsub('^%l', string.upper)

        itemList[k] = {
            name = k,
            label = label,
            image = setImagePath(v.image or v.client?.image or defaultImage),
            client = v.client or {},
        }
    end
    return itemList
end
