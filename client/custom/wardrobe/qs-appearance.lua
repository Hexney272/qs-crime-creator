if Config.Wardrobe ~= 'qs-appearance' then
    return
end

function OpenWardrobe()
    TriggerEvent('clothing:openOutfitMenu')
end
