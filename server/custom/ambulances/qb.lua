if Config.Ambulance ~= 'qb' then return end

function RevivePlayer(src)
    TriggerClientEvent('hospital:client:Revive', src)
end

function IsPlayerDead(src)
    return sfr:getMeta(src).isDead
end
