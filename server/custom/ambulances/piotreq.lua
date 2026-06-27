if Config.Ambulance ~= 'piotreq' then return end

function RevivePlayer(src)
    TriggerClientEvent('p_ambulancejob:RevivePlayer', src)
end

function IsPlayerDead(src)
    return Player(src).state.isDead
end
