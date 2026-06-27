--[[
    Configurable company system, you can create multiple files
    and adapt them to your company system, these are the ones we recommend
    that we bring by default, but you can integrate others.

    Enable Config.Debug to be able to see the log inside Debug.
]]

if Config.Framework ~= 'esx' then
    return
end

-- for societyName, _ in pairs(Config.CreatorJobs) do
--     local name = 'society_' .. societyName
--     TriggerEvent('esx_society:registerSociety', societyName, 'RealState', name, name, name, { type = 'public' })
-- end

---@param src number
---@param societyName string
---@param societyPaid number
---@return boolean
---@diagnostic disable-next-line: duplicate-set-field
function sv_society.addMoney(src, societyName, societyPaid)
    if GetResourceState('esx_society') ~= 'started' then
        Error('esx_society', 'addMoney', 'esx_society not started. Shop not will work properly.')
        return false
    end
    Debug('esx_society', 'addMoney', 'src: ' .. src .. ' societyName: ' .. societyName .. ' societyPaid: ' .. societyPaid)
    local name = 'society_' .. societyName
    TriggerEvent('esx_addonaccount:getSharedAccount', name, function(account)
        account.addMoney(societyPaid)
    end)
    return true
end

---@param societyName string
---@return number
---@diagnostic disable-next-line: duplicate-set-field
function sv_society.getMoney(societyName)
    if GetResourceState('esx_society') ~= 'started' then
        Error('esx_society', 'getMoney', 'esx_society not started. Shop not will work properly.')
        return 0
    end
    Debug('esx_society', 'getMoney', 'societyName: ' .. societyName)
    local name = 'society_' .. societyName
    local promise = promise.new()
    TriggerEvent('esx_addonaccount:getSharedAccount', name, function(account)
        promise:resolve(account.money)
    end)
    return Citizen.Await(promise)
end

---@param societyName string
---@param amount number
---@return boolean
---@diagnostic disable-next-line: duplicate-set-field
function sv_society.removeMoney(societyName, amount)
    if GetResourceState('esx_society') ~= 'started' then
        Error('esx_society', 'removeMoney', 'esx_society not started. Shop not will work properly.')
        return false
    end
    Debug('esx_society', 'removeMoney', 'societyName: ' .. societyName .. ' amount: ' .. amount)
    local name = 'society_' .. societyName
    TriggerEvent('esx_addonaccount:getSharedAccount', name, function(account)
        account.removeMoney(amount)
    end)
    return true
end
