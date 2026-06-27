---@class DrugSellingMission : MissionModule
---@field missionsInstance Missions
---@field targetAmount number
---@field trackingOrgMissionIds table<number, boolean>
---@field drugSaleListener? function
DrugSellingMission = {}

---@param missionsInstance Missions
---@param targetAmount number
function DrugSellingMission:initialize(missionsInstance, targetAmount)
    self.missionsInstance = missionsInstance
    self.targetAmount = targetAmount or 10000
    self.trackingOrgMissionIds = {}
    self.eventListeners = {}
end

---@param orgMissionId number
function DrugSellingMission:startTracking(orgMissionId)
    if not orgMissionId then
        return
    end

    self.trackingOrgMissionIds[orgMissionId] = true

    if not self.drugSaleListener then
        self.drugSaleListener = function(data)
            self:onDrugSale(data)
        end

        self.eventListeners.drugSale = AddEventHandler('crime:territoryWarDrugSale', self.drugSaleListener)
    end

    Debug('DrugSellingMission:startTracking', 'Started tracking orgMissionId:', orgMissionId, 'target:', self.targetAmount)
end

---@param orgMissionId number
function DrugSellingMission:stopTracking(orgMissionId)
    if not orgMissionId then
        return
    end

    self.trackingOrgMissionIds[orgMissionId] = nil

    if self.drugSaleListener and not next(self.trackingOrgMissionIds) then
        RemoveEventHandler(self.eventListeners.drugSale)
        self.drugSaleListener = nil
    end
end

---@param data {orgId: number, amount: number, territoryId?: number}
function DrugSellingMission:onDrugSale(data)
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

        local saleAmount = data.amount or 0
        local newProgress = (activeMission.progress or 0) + saleAmount
        local completed = newProgress >= self.targetAmount

        self.missionsInstance:updateProgress(missionId, newProgress, completed)
    end
end

---@param orgMissionId number
---@return string|nil
function DrugSellingMission:getMissionIdByOrgMissionId(orgMissionId)
    local activeMissions = self.missionsInstance:getActiveMissions()
    for _, mission in ipairs(activeMissions) do
        if mission.id == orgMissionId then
            return mission.missionId
        end
    end
    return nil
end

function DrugSellingMission:destroy()
    for _, eventListener in pairs(self.eventListeners) do
        RemoveEventHandler(eventListener)
    end
    self.eventListeners = {}

    self.trackingOrgMissionIds = {}
end

MissionModuleRegistry = MissionModuleRegistry or {}
MissionModuleRegistry.drug_selling = DrugSellingMission
