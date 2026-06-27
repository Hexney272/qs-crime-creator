if Config.Wardrobe ~= 'rcore_clothes' then
    return
end

function OpenWardrobe()
    TriggerEvent('rcore_clothes:openOutfits')
end
