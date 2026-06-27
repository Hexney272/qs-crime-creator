if not Config.Debug then return end

RegisterCommand('testgraffiti', function(_, args)
    local font = ''
    if args and #args > 0 then
        font = table.concat(args, ' ')
    end
    TriggerEvent('crime:graffiti:useItem', 'spray_paint', 'PLAYER_NAME_01', {
        label = 'Test Graffiti',
        font = font
    })
end, false)

RegisterCommand('removegraffiti', function()
    TriggerEvent('crime:graffiti:removeNearby')
end, false)

RegisterCommand('listgraffitis', function()
    print('=== Active Graffitis ===')
    for id, graffiti in pairs(GraffitiModule.graffitis) do
        print(string.format('ID: %d | Label: %s | Owner: %s | Gang: %s',
            id, graffiti.label, graffiti.owner_name or 'Unknown', graffiti.gang or 'None'))
    end
end, false)
