if Config.Ambulance ~= 'qs' then return end

function RevivePlayer(src)
    TriggerClientEvent('ambulance:revivePlayer', src)
end

function IsPlayerDead(src)
    return Player(src).state.dead
end
