--[[
    QBox/QBCore Server Framework Adapter
    QBox uses the qb-core compat bridge - so exports['qb-core']:GetCoreObject() works.
    All player operations wrapped in pcall for safety.
]]

local framework = {}

-- QBox provides a qb-core compat bridge, so this works for both QB and QBox
local QBCore = exports['qb-core']:GetCoreObject()
local isQBX  = Config.QBX

-- ─── Safe player getter ───────────────────────────────────────────────────────
local function safeGetPlayer(source)
    local ok, player = pcall(function()
        return QBCore.Functions.GetPlayer(source)
    end)
    if not ok or not player then return nil end
    return player
end

-- ─── Jobs ────────────────────────────────────────────────────────────────────
function framework:getJobsData()
    local data = {}
    local jobs = QBCore.Shared.Jobs
    if not jobs then return data end
    for k, v in pairs(jobs) do
        data[#data + 1] = {
            name   = k,
            label  = v.label or k,
            grades = table.map(v.grades or {}, function(grade, index)
                return { label = grade.name or tostring(index), grade = tonumber(index) }
            end),
        }
    end
    return data
end

-- ─── Player loaded event ─────────────────────────────────────────────────────
RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    local src = source
    Wait(500)
    InitOrganization(src)
end)

-- QBox also fires qbx_core:server:playerLoaded
if isQBX then
    AddEventHandler('qbx_core:server:playerLoaded', function(src)
        Wait(500)
        InitOrganization(src)
    end)
end

-- ─── Usable items ────────────────────────────────────────────────────────────
function framework:registerUsableItem(name, cb)
    if isQBX then
        local ok = pcall(function() exports['qbx_core']:RegisterUsableItem(name, cb) end)
        if not ok then QBCore.Functions.CreateUseableItem(name, cb) end
    else
        QBCore.Functions.CreateUseableItem(name, cb)
    end
end

-- ─── Player lookup ───────────────────────────────────────────────────────────
function framework:getPlayerFromId(source)
    return safeGetPlayer(source)
end

function framework:getSourceFromIdentifier(identifier)
    local ok, result = pcall(function()
        local players = QBCore.Functions.GetPlayers()
        for _, src in ipairs(players) do
            local p = safeGetPlayer(src)
            if p and p.PlayerData.citizenid == identifier then
                return p.PlayerData.source
            end
        end
    end)
    return ok and result or nil
end

function framework:getIdentifier(source)
    local player = safeGetPlayer(source)
    if not player then return nil end
    return player.PlayerData.citizenid
end

-- ─── Money ───────────────────────────────────────────────────────────────────
local function accountName(account)
    if account == 'money' then return 'cash' end
    return account
end

function framework:getAccountMoney(source, account)
    local player = safeGetPlayer(source)
    if not player then return 0 end
    account = accountName(account)
    local ok, amount = pcall(function()
        return player.PlayerData.money[account] or 0
    end)
    return (ok and amount) or 0
end

function framework:removeAccountMoney(source, account, amount)
    if not amount or amount <= 0 then return true end
    local player = safeGetPlayer(source)
    if not player then return false end
    account = accountName(account)

    local balance = player.PlayerData.money[account] or 0
    if balance < amount then return false end

    local ok, err = pcall(function()
        player.Functions.RemoveMoney(account, amount)
    end)
    if not ok then
        Error("framework:removeAccountMoney", err)
        return false
    end
    return true
end

function framework:addAccountMoney(source, account, amount)
    if not amount or amount <= 0 then return end
    local player = safeGetPlayer(source)
    if not player then return end
    account = accountName(account)
    pcall(function() player.Functions.AddMoney(account, amount) end)
end

-- ─── Items ───────────────────────────────────────────────────────────────────
function framework:removeItem(source, item, count)
    local player = safeGetPlayer(source)
    if not player then return false end
    local ok = pcall(function() player.Functions.RemoveItem(item, count) end)
    return ok
end

function framework:addItem(source, item, count, slot, info)
    local player = safeGetPlayer(source)
    if not player then return false end
    local ok, result = pcall(function()
        return player.Functions.AddItem(item, count, slot, info)
    end)
    return ok and result or false
end

function framework:getInventory(source)
    local player = safeGetPlayer(source)
    if not player then return {} end
    return player.PlayerData.items or {}
end

function framework:getItem(source, item)
    local player = safeGetPlayer(source)
    if not player then return { count = 0 } end
    local ok, data = pcall(function()
        local d = player.Functions.GetItemByName(item)
        if d then d.count = d.amount end
        return d or { count = 0 }
    end)
    return (ok and data) or { count = 0 }
end

function framework:getItemList()
    return QBCore.Shared.Items or {}
end

-- ─── Permissions ─────────────────────────────────────────────────────────────
function framework:playerIsAdmin(source)
    local ok, result = pcall(function()
        return QBCore.Functions.HasPermission(source, 'god')
            or QBCore.Functions.HasPermission(source, 'admin')
            or IsPlayerAceAllowed(source, 'command')
    end)
    return ok and result or false
end

-- ─── Player info ─────────────────────────────────────────────────────────────
function framework:getUserName(source)
    local player = safeGetPlayer(source)
    if not player then return 'Unknown', 'Unknown' end
    local ok, first, last = pcall(function()
        local ci = player.PlayerData.charinfo
        return ci.firstname or 'Unknown', ci.lastname or 'Unknown'
    end)
    if not ok then return 'Unknown', 'Unknown' end
    return first, last
end

function framework:getUserNameFromIdentifier(identifier)
    local ok, first, last = pcall(function()
        local rows = MySQL.query.await(
            'SELECT charinfo FROM `players` WHERE citizenid = ?', { identifier }
        )
        if not rows or not rows[1] then return '', '' end
        local ci = json.decode(rows[1].charinfo)
        if not ci then return '', '' end
        return ci.firstname or '', ci.lastname or ''
    end)
    if not ok then return '', '' end
    return first, last
end

function framework:getJobName(source)
    local player = safeGetPlayer(source)
    if not player then return '' end
    local ok, name = pcall(function() return player.PlayerData.job.name end)
    return (ok and name) or ''
end

function framework:getJobGrade(source)
    local player = safeGetPlayer(source)
    if not player then return 0 end
    local ok, grade = pcall(function() return player.PlayerData.job.grade.level or 0 end)
    return (ok and grade) or 0
end

function framework:getPlayers()
    return QBCore.Functions.GetPlayers()
end

function framework:searchPlayers(query)
    local ok, result = pcall(function()
        return MySQL.query.await(
            'SELECT citizenid, charinfo FROM `players` WHERE LOWER(CONCAT(JSON_EXTRACT(charinfo, "$.firstname"), " ", JSON_EXTRACT(charinfo, "$.lastname"))) LIKE ? OR LOWER(citizenid) LIKE ? LIMIT ?',
            { '%'..query..'%', '%'..query..'%', Config.MaxSearchResults }
        )
    end)
    return (ok and result) or {}
end

function framework:setHouseInside(src, insideId)
    local identifier = self:getIdentifier(src)
    if not identifier then return end
    MySQL.update.await('UPDATE players SET crime_house_inside = ? WHERE citizenid = ?', { insideId, identifier })
end

function framework:getHouseInside(src)
    local identifier = self:getIdentifier(src)
    if not identifier then return nil end
    local ok, result = pcall(function()
        return MySQL.prepare.await('SELECT crime_house_inside FROM players WHERE citizenid = ?', { identifier })
    end)
    return (ok and result) or nil
end

function framework:getMeta(src)
    local player = safeGetPlayer(src or source)
    if not player then return {} end
    return player.PlayerData.metadata or {}
end

return framework
