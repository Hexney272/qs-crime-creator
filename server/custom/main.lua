---@param organizationId number
RegisterNetEvent('crime:routePlayer', function(organizationId)
    local src = source
    if HouseRoutings[organizationId] then
        local id = HouseRoutings[organizationId].id
        table.insert(HouseRoutings[organizationId].players, src)
        SetPlayerRoutingBucket(src, id)
        return
    end
    local id = math.random(1, 100000)
    PlayerDefaultRoutings[src] = GetPlayerRoutingBucket(src)
    HouseRoutings[organizationId] = {
        id = id,
        house = organizationId,
        players = { src }
    }
    Debug('crime:routePlayer', 'Setting player routing bucket', src, id)
    SetPlayerRoutingBucket(src, id)
end)

function RouteDefault(source, house)
    local src = source
    Debug('RouteDefault', 'Routing player to default', src, house)
    if not HouseRoutings[house] then return print('RouteDefault', 'houseRoutings[house] not exists') end
    local players = HouseRoutings[house].players
    SetPlayerRoutingBucket(src, PlayerDefaultRoutings[src])
    for k, v in pairs(players) do
        if v == src then
            table.remove(players, k)
        end
    end
    if #players == 0 then
        HouseRoutings[house] = nil
    end
    PlayerDefaultRoutings[src] = nil
end

local securedFileTypes = {
    'image',
    'audio',
    'video'
}

---@param source number
---@param fileType string
---@return string
lib.callback.register('crime:getPresignedUrl', function(source, fileType)
    if not table.includes(securedFileTypes, fileType) then
        Error('Invalid file type', fileType, 'source', source)
        return ''
    end
    local url = ('https://fmapi.net/api/v2/presigned-url?fileType=%s'):format(fileType)
    local promise = promise.new()
    PerformHttpRequest(url, function(err, text, headers)
        local data = json.decode(text)
        if not data then
            return promise:resolve('')
        end
        if data.status ~= 'ok' then
            Error('Failed to get presigned url', data)
            return promise:resolve('')
        end
        promise:resolve(data.data.presignedUrl)
    end, 'GET', nil, {
        Authorization = Config.FiveManageToken
    })
    return Citizen.Await(promise)
end)
