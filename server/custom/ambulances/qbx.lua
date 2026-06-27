if Config.Ambulance ~= 'qbx' then return end

function RevivePlayer(src)
    local success = pcall(function()
        exports.qbx_medical:Revive(src)
    end)

    if not success then
        TriggerClientEvent('qbx_medical:client:playerRevived', src)
    end
end

function IsPlayerDead(src)
    return sfr:getMeta(src).isDead
end
