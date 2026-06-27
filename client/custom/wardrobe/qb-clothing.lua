if Config.Wardrobe ~= 'qb-clothing' then
    return
end

function OpenWardrobe()
    TriggerEvent('qb-clothing:client:openOutfitMenu')
end
