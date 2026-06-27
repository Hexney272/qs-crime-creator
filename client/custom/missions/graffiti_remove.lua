---@class GraffitiRemoveMission : MissionModule
---@field missionsInstance Missions
---@field targetCount number
---@field trackingOrgMissionIds table<number, boolean>
---@field graffitiRemoveListener? function
GraffitiRemoveMission = {}

---@param missionsInstance Missions
---@param targetCount number
function GraffitiRemoveMission:initialize(missionsInstance, targetCount)
    self.missionsInstance = missionsInstance
    self.targetCount = targetCount or 5
    self.trackingOrgMissionIds = {}
    self.eventListeners = {}
end

---@param orgMissionId number
function GraffitiRemoveMission:startTracking(orgMissionId)
    if not orgMissionId then
        return
    end

    self.trackingOrgMissionIds[orgMissionId] = true

    if not self.graffitiRemoveListener then
        self.graffitiRemoveListener = function(graffitiId, data)
            self:onGraffitiRemoved(graffitiId, data)
        end

        self.eventListeners.graffitiRemove = AddEventHandler('crime:graffiti:removed', self.graffitiRemoveListener)
    end

    Debug('GraffitiRemoveMission:startTracking', 'Started tracking orgMissionId:', orgMissionId, 'target:', self.targetCount)
end

---@param orgMissionId number
function GraffitiRemoveMission:stopTracking(orgMissionId)
    if not orgMissionId then
        return
    end

    self.trackingOrgMissionIds[orgMissionId] = nil

    if self.graffitiRemoveListener and not next(self.trackingOrgMissionIds) then
        RemoveEventHandler(self.eventListeners.graffitiRemove)
        self.graffitiRemoveListener = nil
    end
end

---@param graffitiId number
---@param data {territoryId?: number, isOwn?: boolean, removerOrgId?: number}
function GraffitiRemoveMission:onGraffitiRemoved(graffitiId, data)
    if not data then return end

    if not data.removerOrgId or data.removerOrgId ~= self.missionsInstance.organization.id then
        return
    end

    if data.isOwn then
        return
    end

    for orgMissionId, _ in pairs(self.trackingOrgMissionIds) do
        local missionId = self:getMissionIdByOrgMissionId(orgMissionId)
        if not missionId then
            return
        end

        local activeMission = self.missionsInstance:getActiveMission(missionId)
        if not activeMission then
            return
        end

        local newProgress = (activeMission.progress or 0) + 1
        local completed = newProgress >= self.targetCount

        self.missionsInstance:updateProgress(missionId, newProgress, completed)
    end
end

---@param orgMissionId number
---@return string|nil
function GraffitiRemoveMission:getMissionIdByOrgMissionId(orgMissionId)
    local activeMissions = self.missionsInstance:getActiveMissions()
    for _, mission in ipairs(activeMissions) do
        if mission.id == orgMissionId then
            return mission.missionId
        end
    end
    return nil
end

function GraffitiRemoveMission:destroy()
    for _, eventListener in pairs(self.eventListeners) do
        RemoveEventHandler(eventListener)
    end
    self.eventListeners = {}

    self.trackingOrgMissionIds = {}
end

MissionModuleRegistry = MissionModuleRegistry or {}
MissionModuleRegistry.graffiti_remove = GraffitiRemoveMission
