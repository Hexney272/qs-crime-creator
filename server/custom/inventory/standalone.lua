if Config.Inventory ~= 'standalone' then
    return
end

LoopError('Using standalone inventory, this is not recommended for production servers. Please use a supported inventory. If you know what you are doing, you can delete this message.')

---@diagnostic disable-next-line: duplicate-set-field
function sv_inventory:formatItemList()
    return {}
end
