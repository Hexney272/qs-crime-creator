if Config.Ambulance ~= 'ak47' then return end

function RevivePlayer(source)
    TriggerClientEvent('ak47_ambulancejob:revive', source)
    TriggerClientEvent('ak47_ambulancejob:skellyfix', source)
end

function IsPlayerDead(source)
    Error('IsPlayerDead', 'Not implemented your ambulance system. Please implement it in your custom/ambulances/ak47.lua file.', source)
    return false
end
