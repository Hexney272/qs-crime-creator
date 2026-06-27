---@class VehicleTheftMission : MissionModule
---@field missionsInstance Missions
---@field trackingOrgMissionIds table<number, boolean>
---@field currentVehicle number
---@field currentVehicleNetId number?
---@field vehicleBlip number?
---@field deliveryBlip number?
---@field returnToVehicleBlip number?
---@field spawnLocation vector4?
---@field deliveryLocation vector4?
---@field hasEnteredVehicle boolean
---@field missionThreadActive boolean
---@field currentOrgMissionId number?
---@field currentMissionId string?
VehicleTheftMission = {}

local textEnterVehicle = i18n.t('vehicle_theft.enter_vehicle')
local textDeliveryPoint = i18n.t('vehicle_theft.delivery_point')

---@param model string
---@param coords vector4
---@return number|nil, number|nil
local function spawnVehicle(model, coords)
    model = joaat(model)
    lib.requestModel(model)
    local vehicle = CreateVehicle(model, coords.x, coords.y, coords.z, coords.w, true, true)

    SetModelAsNoLongerNeeded(model)
    SetVehicleOnGroundProperly(vehicle)
    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleDoorsLocked(vehicle, 1)
    SetVehicleEngineOn(vehicle, true, true, false)

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    return vehicle, netId
end

---@param vehicle number
local function deleteVehicle(vehicle)
    if vehicle and DoesEntityExist(vehicle) then
        SetEntityAsMissionEntity(vehicle, false, true)
        DeleteVehicle(vehicle)
    end
end

---@param missionsInstance Missions
---@param targetValue? number
function VehicleTheftMission:initialize(missionsInstance, targetValue)
    self.missionsInstance = missionsInstance
    self.trackingOrgMissionIds = {}
    self.eventListeners = {}
    self.currentVehicle = nil
    self.currentVehicleNetId = nil
    self.vehicleBlip = nil
    self.deliveryBlip = nil
    self.returnToVehicleBlip = nil
    self.spawnLocation = nil
    self.deliveryLocation = nil
    self.hasEnteredVehicle = false
    self.missionThreadActive = false
    self.currentOrgMissionId = nil
    self.currentMissionId = nil
end

---@param orgMissionId number
---@param missionId string
function VehicleTheftMission:startTracking(orgMissionId, missionId)
    if not orgMissionId then
        return
    end

    self.trackingOrgMissionIds[orgMissionId] = true
    self.currentOrgMissionId = orgMissionId
    self.currentMissionId = missionId or self:getMissionIdByOrgMissionId(orgMissionId)

    self:startMission()

    Debug('VehicleTheftMission:startTracking', 'Started tracking orgMissionId:', orgMissionId, 'missionId:', self.currentMissionId)
end

---@param orgMissionId number
function VehicleTheftMission:stopTracking(orgMissionId)
    if not orgMissionId then
        return
    end

    self.trackingOrgMissionIds[orgMissionId] = nil

    if not next(self.trackingOrgMissionIds) then
        self:cleanup()
    end
end

function VehicleTheftMission:startMission()
    local orgId = LocalPlayer.state.organization
    if not orgId then
        Notification(i18n.t('vehicle_theft.no_organization'), 'error')
        return
    end

    local result = lib.callback.await('crime:vehicletheft:start', false, orgId, self.currentOrgMissionId)
    if not result or not result.success then
        Notification(result and result.message, 'error')
        return
    end

    self.spawnLocation = result.spawnLocation
    self.deliveryLocation = result.deliveryLocation
    local vehicleModel = result.vehicleModel

    self.currentVehicle, self.currentVehicleNetId = spawnVehicle(vehicleModel, self.spawnLocation)

    if not self.currentVehicle then
        Notification(i18n.t('vehicle_theft.vehicle_spawn_failed'), 'error')
        lib.callback.await('crime:vehicletheft:cancel', false, orgId, self.currentOrgMissionId)
        return
    end

    local blipConfig = Config.VehicleTheft.vehicleBlip
    self.vehicleBlip = Utils.CreateBlip({
        location = self.spawnLocation,
        sprite = blipConfig.sprite,
        color = blipConfig.color,
        scale = blipConfig.scale,
        text = i18n.t('vehicle_theft.vehicle_blip')
    })
    SetBlipRoute(self.vehicleBlip, true)
    SetBlipRouteColour(self.vehicleBlip, blipConfig.color)

    self:startMissionThread()

    Notification(i18n.t('vehicle_theft.started'), 'success')
end

function VehicleTheftMission:startMissionThread()
    if self.missionThreadActive then return end

    self.missionThreadActive = true
    local lastNotificationTime = 0

    if PoliceDispatch and math.random(1, 100) <= Config.VehicleTheftPoliceCallChance then
        PoliceDispatch(i18n.t('vehicle_theft.police_call'))
    end

    CreateThread(function()
        local deliveryRadius = Config.VehicleTheft.deliveryRadius or 5.0

        while self.missionThreadActive do
            local sleep = 500
            local playerCoords = GetEntityCoords(cache.ped)
            local playerVehicle = GetVehiclePedIsIn(cache.ped, false)

            if self.currentVehicle and not DoesEntityExist(self.currentVehicle) then
                Notification(i18n.t('vehicle_theft.vehicle_lost'), 'error')
                self:cancelMission()
                break
            end

            local vehicleCoords = self.currentVehicle and GetEntityCoords(self.currentVehicle) or nil

            local isCurrentlyInMissionVehicle = playerVehicle == self.currentVehicle

            if not self.hasEnteredVehicle and isCurrentlyInMissionVehicle then
                self.hasEnteredVehicle = true

                RemoveBlip(self.vehicleBlip)
                self.vehicleBlip = nil

                local blipConfig = Config.VehicleTheft.deliveryBlip
                self.deliveryBlip = Utils.CreateBlip({
                    location = self.deliveryLocation,
                    sprite = blipConfig.sprite,
                    color = blipConfig.color,
                    scale = blipConfig.scale,
                    text = i18n.t('vehicle_theft.delivery_blip')
                })
                SetBlipRoute(self.deliveryBlip, true)
                SetBlipRouteColour(self.deliveryBlip, blipConfig.color)

                Notification(i18n.t('vehicle_theft.vehicle_stolen'), 'info')
            end

            if self.hasEnteredVehicle and not isCurrentlyInMissionVehicle then
                if not self.returnToVehicleBlip and vehicleCoords then
                    if self.deliveryBlip then
                        SetBlipRoute(self.deliveryBlip, false)
                    end

                    local blipConfig = Config.VehicleTheft.vehicleBlip
                    self.returnToVehicleBlip = Utils.CreateBlip({
                        location = vehicleCoords,
                        sprite = blipConfig.sprite,
                        color = blipConfig.color,
                        scale = blipConfig.scale,
                        text = i18n.t('vehicle_theft.return_to_vehicle_blip')
                    })
                    SetBlipRoute(self.returnToVehicleBlip, true)
                    SetBlipRouteColour(self.returnToVehicleBlip, blipConfig.color)

                    local currentTime = GetGameTimer()
                    if currentTime - lastNotificationTime > 5000 then
                        Notification(i18n.t('vehicle_theft.return_to_vehicle'), 'error')
                        lastNotificationTime = currentTime
                    end
                end

                if self.returnToVehicleBlip and vehicleCoords then
                    SetBlipCoords(self.returnToVehicleBlip, vehicleCoords.x, vehicleCoords.y, vehicleCoords.z)
                end

                if vehicleCoords then
                    local distToVehicle = #(playerCoords - vehicleCoords)
                    if distToVehicle <= 50.0 then
                        sleep = 0
                        DrawMarker(
                            1,                                                       -- Marker type: cylinder
                            vehicleCoords.x, vehicleCoords.y, vehicleCoords.z - 1.0, -- Position
                            0.0, 0.0, 0.0,                                           -- Direction
                            0.0, 0.0, 0.0,                                           -- Rotation
                            3.0, 3.0, 1.5,                                           -- Scale
                            255, 165, 0, 200,                                        -- Color (orange)
                            false, true, 2, false, nil, nil, false
                        )
                    end
                end
            end

            if self.hasEnteredVehicle and isCurrentlyInMissionVehicle and self.returnToVehicleBlip then
                RemoveBlip(self.returnToVehicleBlip)
                self.returnToVehicleBlip = nil

                if self.deliveryBlip then
                    SetBlipRoute(self.deliveryBlip, true)
                    SetBlipRouteColour(self.deliveryBlip, Config.VehicleTheft.deliveryBlip.color)
                end
            end

            if self.hasEnteredVehicle and isCurrentlyInMissionVehicle and self.deliveryLocation then
                local deliveryPos = vec3(self.deliveryLocation.x, self.deliveryLocation.y, self.deliveryLocation.z)
                local distToDelivery = #(playerCoords - deliveryPos)

                if distToDelivery <= 50.0 then
                    sleep = 0
                    DrawMarker(
                        1,                                                 -- Marker type: cylinder
                        deliveryPos.x, deliveryPos.y, deliveryPos.z - 1.0, -- Position
                        0.0, 0.0, 0.0,                                     -- Direction
                        0.0, 0.0, 0.0,                                     -- Rotation
                        3.0, 3.0, 1.5,                                     -- Scale
                        34, 197, 94, 200,                                  -- Color (green)
                        false, true, 2, false, nil, nil, false
                    )

                    DrawMarker(
                        2,                                           -- Marker type: ring
                        deliveryPos.x, deliveryPos.y, deliveryPos.z, -- Position
                        0.0, 0.0, 0.0,                               -- Direction
                        0.0, 0.0, 0.0,                               -- Rotation
                        4.0, 4.0, 0.3,                               -- Scale
                        34, 197, 94, 150,                            -- Color (green)
                        false, true, 2, false, nil, nil, false
                    )
                end

                if distToDelivery <= deliveryRadius then
                    sleep = 0
                    DrawText3D(deliveryPos.x, deliveryPos.y, deliveryPos.z + 1.0, textDeliveryPoint, 'deliver_vehicle', 'E')

                    if IsControlJustPressed(0, 38) then -- E key
                        self:deliverVehicle()
                        break
                    end
                end
            end

            if not self.hasEnteredVehicle and self.spawnLocation then
                local vehiclePos = vec3(self.spawnLocation.x, self.spawnLocation.y, self.spawnLocation.z)
                local distToVehicle = #(playerCoords - vehiclePos)

                if distToVehicle <= 50.0 then
                    sleep = 0
                    DrawMarker(
                        1,                                              -- Marker type: cylinder
                        vehiclePos.x, vehiclePos.y, vehiclePos.z - 1.0, -- Position
                        0.0, 0.0, 0.0,                                  -- Direction
                        0.0, 0.0, 0.0,                                  -- Rotation
                        3.0, 3.0, 1.5,                                  -- Scale
                        255, 0, 0, 200,                                 -- Color (red)
                        false, true, 2, false, nil, nil, false
                    )

                    DrawMarker(
                        2,                                        -- Marker type: ring
                        vehiclePos.x, vehiclePos.y, vehiclePos.z, -- Position
                        0.0, 0.0, 0.0,                            -- Direction
                        0.0, 0.0, 0.0,                            -- Rotation
                        4.0, 4.0, 0.3,                            -- Scale
                        255, 0, 0, 150,                           -- Color (red)
                        false, true, 2, false, nil, nil, false
                    )
                end

                if distToVehicle <= 5.0 then
                    sleep = 0
                    DrawText3D(vehiclePos.x, vehiclePos.y, vehiclePos.z + 1.0, textEnterVehicle, 'enter_vehicle', 'E')
                end
            end

            Wait(sleep)
        end

        self.missionThreadActive = false
    end)
end

function VehicleTheftMission:deliverVehicle()
    local orgId = LocalPlayer.state.organization
    if not orgId then return end

    local playerVehicle = GetVehiclePedIsIn(cache.ped, false)
    if playerVehicle ~= self.currentVehicle then
        Notification(i18n.t('vehicle_theft.wrong_vehicle_delivery'), 'error')
        return
    end

    local vehicleToDelete = self.currentVehicle

    if vehicleToDelete and DoesEntityExist(vehicleToDelete) then
        FreezeEntityPosition(vehicleToDelete, true)
    end

    local success = ProgressBar({
        duration = Config.VehicleTheft.progressBarDuration or 3000,
        label = i18n.t('vehicle_theft.delivering'),
        disable = { move = true, combat = true }
    })

    if not success then
        if vehicleToDelete and DoesEntityExist(vehicleToDelete) then
            FreezeEntityPosition(vehicleToDelete, false)
        end
        return
    end

    self.missionThreadActive = false

    if vehicleToDelete and DoesEntityExist(vehicleToDelete) then
        TaskLeaveVehicle(cache.ped, vehicleToDelete, 0)
        Wait(1500)
    end

    if vehicleToDelete and DoesEntityExist(vehicleToDelete) then
        SetEntityAsMissionEntity(vehicleToDelete, false, true)
        DeleteVehicle(vehicleToDelete)
    end

    self.currentVehicle = nil

    RemoveBlip(self.vehicleBlip)
    RemoveBlip(self.deliveryBlip)
    RemoveBlip(self.returnToVehicleBlip)
    self.vehicleBlip = nil
    self.deliveryBlip = nil
    self.returnToVehicleBlip = nil

    local result = lib.callback.await('crime:vehicletheft:deliver', false, orgId, self.currentOrgMissionId)

    if result and result.success then
        -- Call server directly to ensure pending_rewards is saved
        local missionId = self.currentMissionId
        local orgMissionId = self.currentOrgMissionId

        if orgId and orgMissionId then
            local updateSuccess = lib.callback.await('crime:updateMissionProgress', false, orgId, orgMissionId, 1, true)
            if updateSuccess and missionId and self.missionsInstance then
                self.missionsInstance:completeMission(missionId)
            end
        end

        Notification(i18n.t('vehicle_theft.success_claim'), 'success')
    else
        Notification(result and result.message, 'error')
    end

    self.spawnLocation = nil
    self.deliveryLocation = nil
    self.hasEnteredVehicle = false
    self.currentOrgMissionId = nil
    self.currentMissionId = nil
end

function VehicleTheftMission:cancelMission()
    local orgId = LocalPlayer.state.organization
    if orgId and self.currentOrgMissionId then
        lib.callback.await('crime:vehicletheft:cancel', false, orgId, self.currentOrgMissionId)
    end

    if self.currentMissionId then
        self.missionsInstance:stopMission(self.currentMissionId)
    end

    self:cleanup()
end

function VehicleTheftMission:cleanup()
    self.missionThreadActive = false

    if self.currentVehicle and DoesEntityExist(self.currentVehicle) then
        if GetVehiclePedIsIn(cache.ped, false) == self.currentVehicle then
            TaskLeaveVehicle(cache.ped, self.currentVehicle, 0)
            Wait(1500)
        end
        deleteVehicle(self.currentVehicle)
    end

    RemoveBlip(self.vehicleBlip)
    RemoveBlip(self.deliveryBlip)
    RemoveBlip(self.returnToVehicleBlip)

    self.currentVehicle = nil
    self.currentVehicleNetId = nil
    self.vehicleBlip = nil
    self.deliveryBlip = nil
    self.returnToVehicleBlip = nil
    self.spawnLocation = nil
    self.deliveryLocation = nil
    self.hasEnteredVehicle = false
    self.currentOrgMissionId = nil
    self.currentMissionId = nil
end

---@param orgMissionId number
---@return string?
function VehicleTheftMission:getMissionIdByOrgMissionId(orgMissionId)
    local activeMissions = self.missionsInstance:getActiveMissions()
    local mission = table.find(activeMissions, function(mission)
        return mission.id == orgMissionId
    end)
    return mission and mission.missionId or nil
end

function VehicleTheftMission:destroy()
    self:cleanup()

    for _, eventListener in pairs(self.eventListeners) do
        RemoveEventHandler(eventListener)
    end
    self.eventListeners = {}
    self.trackingOrgMissionIds = {}
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        VehicleTheftMission:cleanup()
    end
end)

MissionModuleRegistry = MissionModuleRegistry or {}
MissionModuleRegistry.vehicle_theft = VehicleTheftMission
