if Config.Inventory ~= 'ox' then
    return
end

local IMAGE_PATH = GetConvar('inventory:imagepath', 'nui://ox_inventory/html/images')

local function setImagePath(path)
    if path then
        return path:match('^[%w]+://') and path or ('%s/%s'):format(IMAGE_PATH, path)
    end
end

-- ════════════════════════════════════════════════════════════
-- FIX: A lib.load('@ox_inventory.data.items') nil-t ad vissza,
-- mert a data/items.lua-ban az Items globális változó nem elérhető
-- izolált lib.load kontextusban.
--
-- Megoldás: exports['ox_inventory']:Items() használata, ami a
-- ox_bridge.lua-ban van definiálva és a teljes item listát adja.
-- Valamint: nincs külön data/weapons.lua, a fegyverek is az Items
-- táblában vannak (metadata.weapon = true jelöléssel).
-- ════════════════════════════════════════════════════════════

---@diagnostic disable-next-line: duplicate-set-field
function sv_inventory:formatItemList()
    local itemList = {}

    -- Az összes item lekérése az exports-on keresztül (ox_bridge.lua: Items export)
    -- Ha paraméter nélkül hívjuk, az összes item definíciót adja vissza
    local allItems = exports['ox_inventory']:Items()

    -- Fallback: ha az export nil-t ad, próbáljuk meg közvetlenül a globális Items táblát
    if not allItems or not next(allItems) then
        allItems = Items
    end

    if not allItems then
        print('^1[qs-crime-creator]^0 ERROR: Could not load items from ox_inventory. Make sure ox_inventory is started before qs-crime-creator.')
        return itemList
    end

    for k, v in pairs(allItems) do
        local defaultImage = k .. '.png'
        local isWeapon = false

        -- Fegyver detektálás: metadata.weapon flag VAGY WEAPON_ prefix
        if (v.metadata and v.metadata.weapon) or (type(k) == 'string' and k:match('^WEAPON_')) then
            isWeapon = true
        end

        itemList[k] = {
            name = k,
            label = v.label or k,
            image = setImagePath(v.image or (v.client and v.client.image) or defaultImage),
            isWeapon = isWeapon,
            client = v.client or {},
        }

        -- Lőszer/ammo jelölés
        if v.metadata and v.metadata.ammo then
            itemList[k].ammo = true
        end
    end

    return itemList
end
