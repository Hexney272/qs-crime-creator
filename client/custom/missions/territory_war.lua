---@class TerritoryWarMission : MissionModule
---@field missionsInstance Missions
---@field trackingOrgMissionIds table<number, boolean>
---@field warWinListener? function
TerritoryWarMission = {}

RegisterNetEvent('crime:territoryWarWon')

---@param missionsInstance Missions
function TerritoryWarMission:initialize(missionsInstance)
    self.missionsInstance = missionsInstance
    self.trackingOrgMissionIds = {}
    self.eventListeners = {}
end

---@param orgMissionId number
function TerritoryWarMission:startTracking(orgMissionId)
    if not orgMissionId then
        return
    end

    self.trackingOrgMissionIds[orgMissionId] = true

    if not self.warWinListener then
        self.warWinListener = function(data)
            self:onTerritoryWarWon(data)
        end

        self.eventListeners.warWin = AddEventHandler('crime:territoryWarWon', self.warWinListener)
    end

    Debug('TerritoryWarMission:startTracking', 'Started tracking orgMissionId:', orgMissionId)
end

---@param orgMissionId number
function TerritoryWarMission:stopTracking(orgMissionId)
    if not orgMissionId then
        return
    end

    self.trackingOrgMissionIds[orgMissionId] = nil

    if self.warWinListener and not next(self.trackingOrgMissionIds) then
        RemoveEventHandler(self.eventListeners.warWin)
        self.warWinListener = nil
    end
end

---@param data {orgId: number, territoryId: number}
function TerritoryWarMission:onTerritoryWarWon(data)
    if data.orgId ~= self.missionsInstance.organization.id then
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

        self.missionsInstance:updateProgress(missionId, activeMission.targetValue, true)
    end
end

---@param orgMissionId number
---@return string|nil
function TerritoryWarMission:getMissionIdByOrgMissionId(orgMissionId)
    local activeMissions = self.missionsInstance:getActiveMissions()
    for _, mission in ipairs(activeMissions) do
        if mission.id == orgMissionId then
            return mission.missionId
        end
    end
    return nil
end

function TerritoryWarMission:destroy()
    for _, eventListener in pairs(self.eventListeners) do
        RemoveEventHandler(eventListener)
    end
    self.eventListeners = {}

    self.trackingOrgMissionIds = {}
end

MissionModuleRegistry = MissionModuleRegistry or {}
MissionModuleRegistry.territory_war = TerritoryWarMission
