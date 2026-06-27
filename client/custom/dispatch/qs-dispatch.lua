if Config.Dispatch ~= 'qs-dispatch' then
    return
end

function PoliceDispatch(alert)
    local playerData = exports['qs-dispatch']:GetPlayerInfo()

    if (not playerData) then
        print('Error getting player data')
        return
    end

    exports['qs-dispatch']:getSSURL(function(image)
        TriggerServerEvent('qs-dispatch:server:CreateDispatchCall', {
            job = { 'police', 'sheriff', 'traffic', 'patrol' },
            callLocation = playerData.coords,
            callCode = { code = alert },
            message = 'A message',
            flashes = false,
            image = image or nil,
            blip = {
                sprite = 488,
                scale = 1.5,
                colour = 1,
                flashes = true,
                text = alert,
                time = (20 * 1000), --20 secs
            }
        })
    end)
end
