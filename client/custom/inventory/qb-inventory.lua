if Config.Inventory ~= 'qb' then
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
    uniq = tostring(uniq):gsub('-', '_')
    -- if you use old qb-inventory version, uncomment here and remove 'housing:OpenStash' trigger.
    -- TriggerServerEvent('inventory:server:OpenInventory', 'stash', uniq, data)
    -- TriggerEvent('inventory:client:SetCurrentStash', uniq)
    TriggerServerEvent('crime:openQBStash', uniq, data)
end

function OpenInventory(target)
    TriggerServerEvent('inventory:server:OpenInventory', 'otherplayer', GetPlayerServerId(target))
end

function DisableActions(bool)
    -- Add your block events here
end
