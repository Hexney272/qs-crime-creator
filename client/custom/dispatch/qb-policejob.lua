if Config.Dispatch ~= 'qb-policejob' then
    return
end

function PoliceDispatch(alert)
    TriggerServerEvent('police:server:policeAlert', alert)
end
