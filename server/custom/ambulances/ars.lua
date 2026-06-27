if Config.Ambulance ~= 'ars' then return end

function RevivePlayer(src)
    for i = 1, 5 do
        TriggerClientEvent('ars_ambulancejob:healPlayer', src, {
            revive = true
        })
        Wait(500)
    end
end

function IsPlayerDead(src)
    Error('IsPlayerDead', 'Not implemented your ambulance system. Please implement it in your custom/ambulances/ars.lua file.', src)
    return false
end
