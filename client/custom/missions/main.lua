---@class OrganizationMission
---@field id number
---@field missionId string
---@field mission Mission
---@field progress number
---@field targetValue number
---@field dailyCount? number
---@field lastResetDate string?
---@field status? 'active' | 'completed' | 'expired'
---@field createdAt string?
---@field updatedAt string?
---@field organization Organization?

---@class MissionModule
---@field missionsInstance Missions
---@field targetCount? number
---@field targetAmount? number
---@field trackingOrgMissionIds table<number, boolean>
---@field initialize function
---@field startTracking function
---@field stopTracking function
---@field destroy function

---@class Mission
---@field id number
---@field label string
---@field description string
---@field type string
---@field targetType string
---@field targetValue number
---@field dailyLimit number
---@field dailyResetLimit number

---@class Missions : OxClass
---@field organization Organization
---@field activeMissions table<string, OrganizationMission>
---@field missionModules table<string, MissionModule>
Missions = lib.class('Missions')

CurrentMissions = nil

MissionModuleRegistry = MissionModuleRegistry or {}

---@param organization Organization
function Missions:constructor(organization)
    self.organization = organization
    self.activeMissions = {}
    self.missionModules = {}

    self:loadMissionModules()
end

MissionModuleRegistry = MissionModuleRegistry or {}

function Missions:loadMissionModules()
    for missionId, mission in pairs(Config.Missions) do
        local moduleName = nil

        if mission.type == 'graffiti' and mission.target_type == 'spray_count' then
            moduleName = 'spray'
        elseif mission.type == 'territory_war' and mission.target_type == 'war_win' then
            moduleName = 'territory_war'
        elseif mission.type == 'drug_selling' and mission.target_type == 'drug_sale_amount' then
            moduleName = 'drug_selling'
        elseif mission.type == 'graffiti' and mission.target_type == 'remove_count' then
            moduleName = 'graffiti_remove'
        elseif mission.type == 'vehicle_theft' and mission.target_type == 'vehicle_delivery' then
            moduleName = 'vehicle_theft'
        end

        if moduleName and MissionModuleRegistry[moduleName] then
            local moduleTemplate = MissionModuleRegistry[moduleName]

            local missionModule = {}
            setmetatable(missionModule, { __index = moduleTemplate })

            if mission.type == 'territory_war' and mission.target_type == 'war_win' then
                missionModule:initialize(self)
            else
                missionModule:initialize(self, mission.target_value)
            end

            self.missionModules[missionId] = missionModule
        end
    end
end

---@param missionId string
---@param orgMissionId number
function Missions:startMission(missionId, orgMissionId)
    if not missionId or not orgMissionId then
        Error('Missions:startMission', 'missionId and orgMissionId must be provided')
        return
    end

    local mission = Config.GetMission(missionId)
    if not mission then
        Error('Missions:startMission', 'Mission not found: ', tostring(missionId))
        return
    end

    self.activeMissions[missionId] = {
        id = orgMissionId,
        missionId = missionId,
        mission = mission,
        progress = 0,
        targetValue = mission.target_value
    }

    local module = self.missionModules[missionId]
    if module and module.startTracking then
        module:startTracking(orgMissionId, missionId)
    end

    Notification(i18n.t('mission.started', { mission = mission.label }), 'info')

    Debug('Missions:startMission', 'Started tracking mission:', missionId, 'orgMissionId:', orgMissionId)
end

---@param missionId string
---@param progress number
---@param completed? boolean
function Missions:updateProgress(missionId, progress, completed)
    Debug('Missions:updateProgress', 'Updating progress for mission:', missionId, 'progress:', progress, 'completed:', completed)
    if not self.activeMissions[missionId] then
        return Error('Missions:updateProgress', 'Active mission not found:', missionId)
    end

    local activeMission = self.activeMissions[missionId]
    activeMission.progress = progress

    -- Notify player about progress update
    local mission = activeMission.mission
    Notification(i18n.t('mission.progress_updated', {
        mission = mission.label,
        progress = progress,
        target = activeMission.targetValue
    }), 'info')

    -- Send progress update to NUI for real-time UI updates
    SendReactMessage('crime:missionProgressUpdated', {
        missionId = missionId,
        orgMissionId = activeMission.id,
        progress = progress,
        targetValue = activeMission.targetValue,
        completed = completed or false
    })

    lib.callback('crime:updateMissionProgress', false, function(success)
        if success and completed then
            self:completeMission(missionId)
        end
    end, self.organization.id, activeMission.id, progress, completed or false)
end

---@param missionId string
function Missions:completeMission(missionId)
    if not self.activeMissions[missionId] then
        return
    end

    local activeMission = self.activeMissions[missionId]
    local mission = activeMission.mission

    local module = self.missionModules[missionId]
    if module and module.stopTracking then
        module:stopTracking(activeMission.id)
    end

    Notification(i18n.t('mission.completed', { mission = mission.label }), 'success')

    -- Send completion update to NUI for real-time UI updates
    SendReactMessage('crime:missionCompleted', {
        missionId = missionId,
        orgMissionId = activeMission.id
    })

    self.activeMissions[missionId] = nil

    Debug('Missions:completeMission', 'Completed mission:', missionId)
end

---Stop tracking a mission
---@param missionId string
function Missions:stopMission(missionId)
    if not self.activeMissions[missionId] then
        return
    end

    local activeMission = self.activeMissions[missionId]
    local mission = activeMission.mission

    local module = self.missionModules[missionId]
    if module and module.stopTracking then
        module:stopTracking(activeMission.id)
    end

    Notification(i18n.t('mission.cancelled', { mission = mission.label }), 'error')

    self.activeMissions[missionId] = nil
end

---@param missionId string
---@return table?
function Missions:getActiveMission(missionId)
    return self.activeMissions[missionId]
end

---@return table[]
function Missions:getActiveMissions()
    Debug('Missions:getActiveMissions', 'Getting active missions', self.activeMissions)
    local missions = {}
    for _, mission in pairs(self.activeMissions) do
        missions[#missions + 1] = mission
    end
    return missions
end

function Missions:destroy()
    for missionId, _ in pairs(self.activeMissions) do
        self:stopMission(missionId)
    end

    for _, module in pairs(self.missionModules) do
        if module and module.destroy then
            module:destroy()
        end
    end

    self.activeMissions = {}
    self.missionModules = {}
end
