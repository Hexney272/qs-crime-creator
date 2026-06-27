if Config.Ambulance ~= 'esx' then return end

function RevivePlayer(src)
    TriggerClientEvent('esx_ambulancejob:revive', src)
end

function IsPlayerDead(src)
    return Player(src).state.isDead == 1
end
