local isFrozen = false
function FreezeWeather(isSyncEnabled)
    isFrozen = isSyncEnabled
    if isSyncEnabled then
        TriggerEvent('Renewed:client:DisableSync')
        TriggerEvent('qb-weathersync:client:DisableSync')
        TriggerEvent('cd_easytime:PauseSync', true)
        TriggerEvent('vSync:toggle', true)
        TriggerEvent('av_weather:freeze', true, Config.TimeInterior, 0, 'CLEAR', false, false, false)
        TriggerEvent('Renewed:client:ForceWeather', {
            weather = 'CLEAR',
            time = { hour = Config.TimeInterior, minute = 0 },
            dynamic = false
        })

        CreateThread(function()
            while isFrozen do
                Wait(0)
                SetWeatherTypePersist('EXTRASUNNY')
                SetWeatherTypeNow('EXTRASUNNY')
                SetWeatherTypeNowPersist('EXTRASUNNY')
                NetworkOverrideClockTime(Config.TimeInterior, 0, 0)
            end
        end)
        Debug('Weather synchronization disabled.')
    else
        TriggerEvent('Renewed:client:EnableSync')
        TriggerEvent('qb-weathersync:client:EnableSync')
        TriggerEvent('cd_easytime:PauseSync', false)
        TriggerEvent('vSync:toggle', false)
        TriggerEvent('av_weather:freeze', false)
        TriggerEvent('Renewed:client:ForceWeather', false)

        Debug('Weather synchronization enabled.')
    end
end
