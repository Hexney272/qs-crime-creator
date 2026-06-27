if Config.Inventory ~= 'ox' then
    return
end

local ox_inventory = exports.ox_inventory

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
    local maxweight = data.maxweight or 10000
    local slot = data.slots or 30
    if ox_inventory:openInventory('stash', uniq) == false then
        TriggerServerEvent('crime:registerOXStash', uniq, slot, maxweight)
        ox_inventory:openInventory('stash', uniq)
        Debug('Ox Stash', 'Registering new stash', uniq)
    end
end

function OpenInventory(target)
    exports.ox_inventory:openInventory('player', GetPlayerServerId(target))
end

function DisableActions(bool)
    -- Add your block events here
end
