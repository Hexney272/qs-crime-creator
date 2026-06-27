if Config.Inventory ~= 'codem' then
    return
end

---@param customData table|nil
---@param uniq string|nil
function OpenStash(customData, uniq)
    -- Always start with DefaultStashData
    local data = {
        maxweight = Config.DefaultStashData.maxweight,
        slots = Config.DefaultStashData.slots
    }

    local house = OrganizationManager:getCurrentOrganization()
    local organization = OrganizationManager:get(house)

    -- Apply upgrades
    if organization and organization.upgrades then
        for _, upgrade in ipairs(organization.upgrades) do
            if upgrade.level and upgrade.level > 0 then
                local upgradeConfig = nil
                for _, cfg in ipairs(Config.Upgrades) do
                    if cfg.name == upgrade.name then
                        upgradeConfig = cfg
                        break
                    end
                end

                if upgradeConfig and upgradeConfig.levels[upgrade.level] then
                    local upgradeValue = upgradeConfig.levels[upgrade.level].value

                    if upgrade.name == 'stash' then
                        -- Capacity upgrade - add to maxweight (kg -> gram)
                        data.maxweight = data.maxweight + (upgradeValue * 1000)
                    elseif upgrade.name == 'stash_slots' then
                        -- Slots upgrade - add to slots
                        data.slots = data.slots + upgradeValue
                    end
                end
            end
        end
    end

    uniq = uniq or house
    uniq = tostring(uniq or 'house'):gsub('-', '_')
    local name = 'stash_' .. uniq
    local maxweight = data.maxweight or 10000
    local slots = data.slots or 30

    print('[INFO] Open stash CodeM:', name, 'MaxWeight:', maxweight, 'Slots:', slots)
    TriggerServerEvent('codem-inventory:server:openstash', name, slots, maxweight, name)
end

function OpenInventory(target)
    TriggerServerEvent('core_inventory:server:openInventory', GetPlayerServerId(target), 'otherplayer', nil, nil, false)
end

function DisableActions(bool)
    -- Add your block events here
end
