if Config.Wardrobe ~= 'default' then
    return
end

local ESX = cfr:getObject()

function OpenWardrobe()
    if Config.Framework == 'qb' then
        return TriggerEvent('qb-clothing:client:openOutfitMenu')
    end

    ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'room', {
        title    = i18n.t('esx_wardrobe.title'),
        align    = 'right',
        elements = {
            { label = i18n.t('esx_wardrobe.clothes'),        value = 'player_dressing' },
            { label = i18n.t('esx_wardrobe.delete_clothes'), value = 'remove_cloth' }
        }
    }, function(data, menu)
        if data.current.value == 'player_dressing' then
            menu.close()
            ESX.TriggerServerCallback('crime:getPlayerDressing', function(dressing)
                elements = {}

                for i = 1, #dressing, 1 do
                    table.insert(elements, {
                        label = dressing[i],
                        value = i
                    })
                end

                ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'player_dressing',
                    {
                        title    = i18n.t('esx_wardrobe.title'),
                        align    = 'right',
                        elements = elements
                    }, function(data2, menu2)
                        TriggerEvent('skinchanger:getSkin', function(skin)
                            ESX.TriggerServerCallback('crime:getPlayerOutfit', function(clothes)
                                TriggerEvent('skinchanger:loadClothes', skin, clothes)
                                TriggerEvent('esx_skin:setLastSkin', skin)

                                TriggerEvent('skinchanger:getSkin', function(skin)
                                    TriggerServerEvent('esx_skin:save', skin)
                                end)
                            end, data2.current.value)
                        end)
                    end, function(data2, menu2)
                        menu2.close()
                    end)
            end)
        elseif data.current.value == 'remove_cloth' then
            menu.close()
            ESX.TriggerServerCallback('crime:getPlayerDressing', function(dressing)
                elements = {}

                for i = 1, #dressing, 1 do
                    table.insert(elements, {
                        label = dressing[i],
                        value = i
                    })
                end

                ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'remove_cloth', {
                    title    = i18n.t('esx_wardrobe.delete_clothes'),
                    align    = 'right',
                    elements = elements
                }, function(data2, menu2)
                    menu2.close()
                    TriggerServerEvent('crime:removeOutfit', data2.current.value)
                    Notification(i18n.t('esx_wardrobe.outfit_delete'), 'info')
                end, function(data2, menu2)
                    menu2.close()
                end)
            end)
        end
    end, function(data, menu)
        menu.close()
    end)
end
