if not Config.Debug then
    return
end

Debug('`randomsellitems` command loaded')
RegisterCommand('randomsellitems', function(source, args, rawCommand)
    if not args[1] then
        return Error('randomsellitems', 'Store ID is required')
    end
    local store = tonumber(args[1])
    local store = table.find(shared.shops, function(t)
        return t.id == store
    end)
    if not store then
        return Error('randomsellitems', 'Store not found', store)
    end
    for _ = 1, 10 do
        local item = store.sellable_items[math.random(#store.sellable_items)]
        local quantity = math.random(1, 10)
        sfr:addItem(source, item.name, quantity)
    end
end)
TriggerClientEvent('chat:addSuggestion', -1, '/randomsellitems', 'Randomly add items to your inventory', {
    { name = 'store_id', help = 'The ID of the store to add items to' }
})
