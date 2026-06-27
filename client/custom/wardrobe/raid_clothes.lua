if Config.Wardrobe ~= 'raid_clothes' then
    return
end

function OpenWardrobe()
    TriggerEvent('raid_clothes:openmenu')
end
