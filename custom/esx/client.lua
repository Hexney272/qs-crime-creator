local framework = {}
local ESX = exports['es_extended']:getSharedObject()

RegisterNetEvent('esx:playerLoaded', function(playerData)
    PlayerData = playerData
    Wait(2500)
    local insideId = lib.callback.await('crime:getHouseInside', false)
    if insideId and insideId ~= 'nil' and insideId ~= '' then
        local organization = OrganizationManager:get(insideId)
        if not organization then return end
        organization:enterHouse()
    end
end)

function framework:getPlayerData()
    return ESX.GetPlayerData()
end

function framework:getObject()
    return ESX
end

CreateThread(function()
    PlayerData = framework:getPlayerData()
end)

RegisterNetEvent('esx:setJob', function(jobData)
    PlayerData.job = jobData
end)

function framework:getIdentifier()
    return PlayerData?.identifier
end

function framework:getJobName()
    return PlayerData?.job?.name or 'unemployed'
end

function framework:getJobGrade()
    return PlayerData?.job?.grade or 0
end

function framework:getPlayers()
    return ESX.Game.GetPlayers()
end

return framework
