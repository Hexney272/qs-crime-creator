if Config.Wardrobe ~= 'p_appearance' then
    return
end

function OpenWardrobe()
    exports['p_appearance']:openOutfits()
end
