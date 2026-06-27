local framework = {}
local QBCore = exports['qb-core']:GetCoreObject()

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    PlayerData = framework:getPlayerData()
    Wait(2500)
    local insideId = lib.callback.await('crime:getHouseInside', false)
    if insideId and insideId ~= 'nil' and insideId ~= '' then
        local organization = OrganizationManager:get(insideId)
        if not organization then return end
        organization:enterHouse()
    end
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(jobData)
    PlayerData.job = jobData
end)

RegisterNetEvent('QBCore:Client:SetDuty', function(duty)
    PlayerData.job.onduty = duty
end)

CreateThread(function()
    PlayerData = framework:getPlayerData()
end)

function framework:getPlayerData()
    return QBCore.Functions.GetPlayerData()
end

function framework:getObject()
    return QBCore
end

function framework:getIdentifier()
    return PlayerData.citizenid
end

function framework:getJobName()
    return (PlayerData and PlayerData.job and PlayerData.job.name) or 'unemployed'
end

function framework:getJobGrade()
    return (PlayerData and PlayerData.job and PlayerData.job.grade and PlayerData.job.grade.level) or 0
end

function framework:getPlayers()
    return QBCore.Functions.GetPlayers()
end

RegisterNetEvent('QBCore:Client:OnGangUpdate', function(gangData)
    PlayerData.gang = gangData
end)

return framework
