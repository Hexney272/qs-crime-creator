--[[
    Hi dear customer or developer, here you can fully configure your server's
    framework or you could even duplicate this file to create your own framework.

    If you do not have much experience, we recommend you download the base version
    of the framework that you use in its latest version and it will work perfectly.
]]

local framework = {}
local ESX = exports['es_extended']:getSharedObject()

function framework:getJobsData()
    local jobs = ESX.GetJobs()
    local data = {}
    for k, v in pairs(jobs) do
        data[#data + 1] = {
            name = v.name,
            label = v.label,
            grades = table.map(v.grades, function(grade)
                return {
                    id = grade.id,
                    name = grade.name,
                    label = grade.label,
                    grade = grade.grade
                }
            end)
        }
    end
    return data
end

RegisterNetEvent('esx:playerLoaded', function(id, data)
    Debug('Loaded player:', id)
    InitOrganization(id)
end)

function framework:registerUsableItem(item, cb)
    ESX.RegisterUsableItem(item, cb)
end

function framework:getPlayerFromId(source)
    return ESX.GetPlayerFromId(source)
end

function framework:getSourceFromIdentifier(identifier)
    local player = ESX.GetPlayerFromIdentifier(identifier)
    if not player then return end
    return player.source
end

function framework:getIdentifier(source)
    local player = self:getPlayerFromId(source)
    if not player then return end
    return player.identifier
end

function framework:getAccountMoney(source, account)
    local player = self:getPlayerFromId(source)
    return player.getAccount(account).money
end

function framework:removeAccountMoney(source, account, amount)
    if amount <= 0 then return true end
    local player = self:getPlayerFromId(source)
    if self:getAccountMoney(source, account) < amount then
        return false
    end
    player.removeAccountMoney(account, amount)
    return true
end

function framework:addAccountMoney(source, account, amount)
    local player = self:getPlayerFromId(source)
    player.addAccountMoney(account, amount)
end

function framework:removeItem(source, item, count)
    local player = self:getPlayerFromId(source)
    if not player then return false end
    player.removeInventoryItem(item, count)
end

function framework:addItem(source, item, count, slot, info)
    local player = self:getPlayerFromId(source)
    if player.canCarryItem(item, count) then
        player.addInventoryItem(item, count, info, slot)
        return true
    end
    return false
end

function framework:getInventory(source)
    local player = self:getPlayerFromId(source)
    return player.getInventory()
end

function framework:getItem(source, item)
    local player = self:getPlayerFromId(source)
    local data = player.getInventoryItem(item)
    if not data then
        return {
            count = 0
        }
    end
    return data
end

-- This is a so much expensive function. Be careful with it !
function framework:getItemList()
    ESX = exports['es_extended']:getSharedObject()
    return ESX.Items
end

function framework:playerIsAdmin(source)
    local player = self:getPlayerFromId(source)
    return player.getGroup() == 'admin' or player.getGroup() == 'superadmin'
end

function framework:getUserName(source)
    local xPlayer = self:getPlayerFromId(source)
    if not xPlayer then
        Debug('framework:getUserName :: Player not found', source)
        return 'Unknown', 'Unknown'
    end
    local firstName, lastName
    if xPlayer.get and xPlayer.get('firstName') and xPlayer.get('lastName') then
        firstName = xPlayer.get('firstName')
        lastName = xPlayer.get('lastName')
    else
        local name = MySQL.query.await('SELECT firstname, lastname FROM users WHERE identifier = ?', { xPlayer.identifier })
        firstName = (name and name[1] and name[1].firstname) or ''
        lastName  = (name and name[1] and name[1].lastname)  or ''
    end

    return firstName, lastName
end

function framework:getUserNameFromIdentifier(identifier)
    local name = MySQL.query.await('SELECT `firstname`, `lastname` FROM `users` WHERE `identifier`=?', { identifier })
    local first = (name and name[1] and name[1].firstname) or ''
    local last  = (name and name[1] and name[1].lastname)  or ''
    return first, last
end

function framework:getJobName(source)
    local xPlayer = self:getPlayerFromId(source)
    return xPlayer.getJob().name
end

function framework:getJobGrade(source)
    local xPlayer = self:getPlayerFromId(source)
    return xPlayer.getJob().grade
end

function framework:getPlayers()
    return ESX.GetPlayers()
end

function framework:searchPlayers(query)
    return MySQL.query.await('SELECT identifier, firstname, lastname FROM `users` WHERE LOWER(CONCAT(firstname, " ", lastname)) LIKE ? OR LOWER(identifier) LIKE ? LIMIT ?', {
        '%' .. query .. '%',
        '%' .. query .. '%',
        Config.MaxSearchResults
    })
end

function framework:setHouseInside(src, insideId)
    local identifier = self:getIdentifier(src)
    MySQL.update.await('UPDATE users SET crime_house_inside = ? WHERE identifier = ?', { insideId, identifier })
end

function framework:getHouseInside(src)
    local identifier = self:getIdentifier(src)
    if not identifier then return end
    local result = MySQL.prepare.await('SELECT crime_house_inside FROM users WHERE identifier = ?', { identifier })
    return result
end

ESX.RegisterServerCallback('crime:getPlayerDressing', function(source, cb)
    local xPlayer = sfr:getPlayerFromId(source)

    if xPlayer then
        TriggerEvent('esx_datastore:getDataStore', 'crime_house', xPlayer.identifier, function(store)
            local count  = store.count('dressing')
            local labels = {}

            for i = 1, count, 1 do
                local entry = store.get('dressing', i)
                table.insert(labels, entry.label)
            end

            cb(labels)
        end)
    end
end)

ESX.RegisterServerCallback('crime:getPlayerOutfit', function(source, cb, num)
    local xPlayer = sfr:getPlayerFromId(source)
    if xPlayer then
        TriggerEvent('esx_datastore:getDataStore', 'crime_house', xPlayer.identifier, function(store)
            local outfit = store.get('dressing', num)
            cb(outfit.skin)
        end)
    end
end)

RegisterNetEvent('crime:removeOutfit', function(label)
    local xPlayer = sfr:getPlayerFromId(source)
    if xPlayer then
        TriggerEvent('esx_datastore:getDataStore', 'crime_house', xPlayer.identifier, function(store)
            local dressing = store.get('dressing')
            if dressing == nil then
                dressing = {}
            end
            label = label
            table.remove(dressing, label)
            store.set('dressing', dressing)
        end)
    end
end)

return framework
