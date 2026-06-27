--[[
    Configurable company system, you can create multiple files
    and adapt them to your company system, these are the ones we recommend
    that we bring by default, but you can integrate others.

    Enable Config.Debug to be able to see the log inside Debug.
]]

if Config.Framework ~= 'qb' then
    return
end

---@param src number
---@param job string
---@param amount number
---@return boolean
---@diagnostic disable-next-line: duplicate-set-field
function sv_society.addMoney(src, job, amount)
    Debug('qb', 'addMoney', 'src: ' .. src .. ' job: ' .. job .. ' amount: ' .. amount)
    local success = pcall(function()
        return exports['qb-management']:AddMoney(job, amount)
    end)

    if success then
        return true
    end
    if exports['qb-banking']:AddMoney(job, amount) then
        return true
    end

    return false
end

---@param job string
---@return number
---@diagnostic disable-next-line: duplicate-set-field
function sv_society.getMoney(job)
    Debug('qb', 'getMoney', 'job: ' .. job)
    local success, result = pcall(function()
        return exports['qb-management']:GetAccount(job)
    end)

    if success then
        return result
    end

    return exports['qb-banking']:GetAccountBalance(job)
end

---@param job string
---@param amount number
---@return boolean
---@diagnostic disable-next-line: duplicate-set-field
function sv_society.removeMoney(job, amount)
    Debug('qb', 'removeMoney', 'job: ' .. job .. ' amount: ' .. amount)

    local success = pcall(function()
        return exports['qb-management']:RemoveMoney(job, amount)
    end)

    if not success then
        return exports['qb-banking']:RemoveMoney(job, amount)
    end

    return false
end
