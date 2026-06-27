if not Config.UseTarget then
    return
end

---@class Target
---@field export string
---@field zones table<string, string[]>
_G['target'] = {
    export = GetResourceState('ox_target'):find('started') and 'ox_target' or 'qb-target',
    zones = {}
}

---@param key string
function target:destroyZones(key)
    if not self.zones[key] then return end
    for k, v in pairs(self.zones[key]) do
        exports[self.export]:RemoveZone(v)
    end
    self.zones[key] = {}
    Debug('destroyed target zones')
end

---@param key string
---@param id string | number
---@param coords vector3
---@param options {icon: string, label: string, action: function, canInteract?: function}[]
---@param distance? number
function target:addBoxZone(key, id, coords, options, distance)
    if not coords then return Error('target:addBoxZone :: coords is nil, probably bad configuration. Please check /hospital_creator', 'key', key, 'id', id) end
    local _id = key .. id
    exports[self.export]:AddBoxZone(_id, coords, Config.TargetWidth, Config.TargetHeight, {
        name = _id,
        heading = 90.0,
        debugPoly = Config.ZoneDebug,
        minZ = coords.z - 5,
        maxZ = coords.z + 1,
    }, {
        options = options,
        distance = distance or 2.5
    })
    if not self.zones[key] then self.zones[key] = {} end
    self.zones[key][id] = _id
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        for k, v in pairs(target.zones) do
            for _, zone in pairs(v) do
                exports[target.export]:RemoveZone(zone)
            end
        end
        target.zones = {}
    end
end)

function target:destroyExit()
    exports[target.export]:RemoveZone('house_exit')
end

function target:initExit()
    local house = OrganizationManager:getCurrentOrganization()
    if not house then
        Error('target:initExit ::: No house data', house)
        return
    end
    local organization = OrganizationManager:get(house)
    if not organization then
        Error('target:initExit ::: No organization data', house)
        return
    end
    self:destroyExit()
    local exitCoords
    if organization.type == 'mlo' then return end
    if organization.type == 'ipl' then
        exitCoords = vec3(organization.ipl_data.exit.x, organization.ipl_data.exit.y, organization.ipl_data.exit.z)
    else
        if not organization.interior_data.exit then return end
        exitCoords = vec3(organization.interior_data.exit.x, organization.interior_data.exit.y, organization.interior_data.exit.z)
    end
    exports[target.export]:AddBoxZone('house_exit', exitCoords, Config.TargetWidth, Config.TargetWidth, {
        name = 'house_exit',
        heading = 90.0,
        debugPoly = Config.ZoneDebug,
        minZ = exitCoords.z - 15.0,
        maxZ = exitCoords.z + 5.0,
    }, {
        options = {
            {
                icon = 'fa-solid fa-door-open',
                label = i18n.t('target.exit_house'),
                action = function()
                    organization:leaveHouse()
                end,
                canInteract = function(entity, distance, data)
                    return true
                end,
            },
            {
                icon = 'fa-solid fa-bell',
                label = i18n.t('target.ring_doorbell'),
                action = function()
                    TriggerServerEvent('qb-houses:server:OpenDoor', CurrentDoorBell, OrganizationManager:getCurrentOrganization())
                    CurrentDoorBell = 0
                end,
                canInteract = function(entity, distance, data)
                    return CurrentDoorBell ~= 0
                end,
            },
            {
                icon = 'fa-solid fa-video',
                label = i18n.t('target.access_camera'),
                action = function()
                    FrontDoorCam(vec3(organization.entry_coords.x, organization.entry_coords.y, organization.entry_coords.z + 1.0))
                end,
                canInteract = function(entity, distance, data)
                    if organization.type == 'ipl' then return false end
                    return not inOwned
                end,
            },
        },
        distance = 2.5
    })
    table.insert(self.zones, 'house_exit')
end
