if Config.Wardrobe ~= 'rcore_clothing' then
    return
end

function OpenWardrobe()
    TriggerEvent('rcore_clothing:openChangingRoom')
end
