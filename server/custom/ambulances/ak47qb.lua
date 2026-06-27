if Config.Ambulance ~= 'ak47qb' then return end

function RevivePlayer(source)
    TriggerClientEvent('ak47_qb_ambulancejob:revive', source)
    TriggerClientEvent('ak47_qb_ambulancejob:skellyfix', source)
end

function IsPlayerDead(source)
    Error('IsPlayerDead', 'Not implemented your ambulance system. Please implement it in your custom/ambulances/ak47qb.lua file.', source)
    return false
end
