if Config.Ambulance ~= 'wasabi' then return end

function RevivePlayer(src)
    TriggerClientEvent('wasabi_ambulance:revive', src)
end

function IsPlayerDead(src)
    return Player(src).state.dead
end
