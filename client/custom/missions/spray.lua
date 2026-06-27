---@class SprayMission : MissionModule
---@field missionsInstance Missions
---@field targetCount number
---@field trackingOrgMissionIds table<number, boolean>
---@field sprayListener? function
SprayMission = {}

---@param missionsInstance Missions
---@param targetCount? number
function SprayMission:initialize(missionsInstance, targetCount)
    self.missionsInstance = missionsInstance
    self.targetCount = targetCount or 5
    self.trackingOrgMissionIds = {}
    self.eventListeners = {}
end

---@param orgMissionId number
function SprayMission:startTracking(orgMissionId)
    if not orgMissionId then
        return
    end

    self.trackingOrgMissionIds[orgMissionId] = true

    if not self.sprayListener then
        self.sprayListener = function(graffiti)
            self:onGraffitiSprayed(graffiti)
        end

        self.eventListeners.spray = AddEventHandler('crime:graffiti:created', self.sprayListener)
    end

    Debug('SprayMission:startTracking', 'Started tracking orgMissionId:', orgMissionId, 'target:', self.targetCount)
end

---@param orgMissionId number
function SprayMission:stopTracking(orgMissionId)
    if not orgMissionId then
        return
    end

    self.trackingOrgMissionIds[orgMissionId] = nil

    if self.sprayListener and not next(self.trackingOrgMissionIds) then
        RemoveEventHandler(self.eventListeners.spray)
        self.sprayListener = nil
    end
end

---@param graffiti table
function SprayMission:onGraffitiSprayed(graffiti)
    Debug('SprayMission:onGraffitiSprayed', 'Graffiti sprayed:', graffiti)
    local zone = TerritoryManager:getCurrent()
    if not zone then
        Notification(i18n.t('missions.graffiti.no_zone'), 'error')
        return
    end

    -- local orgId = LocalPlayer.state.organization
    -- if not orgId or zone.organization_id ~= orgId then
    --     return Debug('SprayMission:onGraffitiSprayed', 'Graffiti sprayed in enemy territory:', graffiti)
    -- end

    for orgMissionId, _ in pairs(self.trackingOrgMissionIds) do
        Debug('SprayMission:onGraffitiSprayed', 'Tracking orgMissionId:', orgMissionId)
        local missionId = self:getMissionIdByOrgMissionId(orgMissionId)
        if not missionId then
            return Error('SprayMission:onGraffitiSprayed', 'Mission ID not found:', orgMissionId)
        end

        local activeMission = self.missionsInstance:getActiveMission(missionId)
        if not activeMission then
            return Error('SprayMission:onGraffitiSprayed', 'Active mission not found:', missionId)
        end

        local newProgress = (activeMission.progress or 0) + 1
        local completed = newProgress >= self.targetCount

        self.missionsInstance:updateProgress(missionId, newProgress, completed)
    end
end

---@param orgMissionId number
---@return string?
function SprayMission:getMissionIdByOrgMissionId(orgMissionId)
    local activeMissions = self.missionsInstance:getActiveMissions()
    local mission = table.find(activeMissions, function(mission)
        return mission.id == orgMissionId
    end)
    return mission and mission.missionId or nil
end

function SprayMission:destroy()
    for _, eventListener in pairs(self.eventListeners) do
        RemoveEventHandler(eventListener)
    end
    self.eventListeners = {}

    self.trackingOrgMissionIds = {}
end

MissionModuleRegistry = MissionModuleRegistry or {}
MissionModuleRegistry.spray = SprayMission
