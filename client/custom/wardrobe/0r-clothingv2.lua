if Config.Wardrobe ~= '0r-clothingv2' then
    return
end

function OpenWardrobe()
    exports['0r-clothingv2']:openClothStore('clothing')
end
