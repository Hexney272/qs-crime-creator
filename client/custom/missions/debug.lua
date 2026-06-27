---@class MissionDebug
MissionDebug = {}

function MissionDebug:printMissions()
    print('^3[Mission Debug]^7 Available Missions:')
    for missionId, mission in pairs(Config.Missions) do
        print(string.format('^2  [%s]^7 %s - Type: %s, Target: %s',
            missionId,
            mission.label,
            mission.type,
            mission.target_type
        ))
        if mission.rewards then
            print('^5    Rewards:^7')
            for _, reward in ipairs(mission.rewards) do
                print(string.format('^5      - %s: %s^7', reward.type, reward.value or reward.item))
            end
        end
    end
end

function MissionDebug:printActiveMissions()
    local orgId = LocalPlayer.state.organization
    if not orgId then
        print('^1[Mission Debug]^7 No organization found')
        return
    end

    local organization = OrganizationManager:get(orgId)
    if not organization or not organization.missions then
        print('^1[Mission Debug]^7 Organization missions not initialized')
        return
    end

    local activeMissions = organization.missions:getActiveMissions()

    if #activeMissions == 0 then
        print('^3[Mission Debug]^7 No active missions')
        return
    end

    print(string.format('^3[Mission Debug]^7 Active Missions for Org #%d:', orgId))
    for _, mission in ipairs(activeMissions) do
        local progressPercent = (mission.progress / mission.targetValue) * 100
        print(string.format('^2  [%s]^7 %s', mission.missionId, mission.mission.label))
        print(string.format('^5    Progress:^7 %d/%d (%.1f%%)', mission.progress, mission.targetValue, progressPercent))
        print(string.format('^5    Org Mission ID:^7 %d', mission.id))
    end
end

function MissionDebug:printModules()
    local orgId = LocalPlayer.state.organization
    if not orgId then
        print('^1[Mission Debug]^7 No organization found')
        return
    end

    local organization = OrganizationManager:get(orgId)
    if not organization or not organization.missions then
        print('^1[Mission Debug]^7 Organization missions not initialized')
        return
    end

    print('^3[Mission Debug]^7 Loaded Mission Modules:')
    for missionId, module in pairs(organization.missions.missionModules) do
        local trackingCount = 0
        if module.trackingOrgMissionIds then
            for _ in pairs(module.trackingOrgMissionIds) do
                trackingCount = trackingCount + 1
            end
        end

        print(string.format('^2  [%s]^7', missionId))
        print(string.format('^5    Target:^7 %s', module.targetCount or module.targetAmount or 'N/A'))
        print(string.format('^5    Tracking:^7 %d mission(s)', trackingCount))
        print(string.format('^5    Has Listener:^7 %s',
            (module.sprayListener or module.warWinListener or module.drugSaleListener or module.graffitiRemoveListener) and 'Yes' or 'No'
        ))
    end
end

---@param missionId string
function MissionDebug:testStart(missionId)
    if not missionId then
        print('^1[Mission Debug]^7 Usage: /missiondebug start <missionId>')
        print('^3Available mission IDs:^7')
        for id, _ in pairs(Config.Missions) do
            print(string.format('^5  - %s^7', id))
        end
        return
    end

    local orgId = LocalPlayer.state.organization
    if not orgId then
        print('^1[Mission Debug]^7 You must be in an organization')
        return
    end

    local mission = Config.GetMission(missionId)
    if not mission then
        print(string.format('^1[Mission Debug]^7 Mission not found: %s', missionId))
        return
    end

    -- Try to take mission
    lib.callback('crime:takeMission', false, function(success, reason)
        if success then
            print(string.format('^2[Mission Debug]^7 Successfully started mission: %s', missionId))

            -- Wait a bit for client to receive the event
            Wait(500)
            self:printActiveMissions()
        else
            print(string.format('^1[Mission Debug]^7 Failed to start mission: %s', reason or 'unknown'))
        end
    end, orgId, missionId)
end

---@param missionId string
function MissionDebug:testComplete(missionId)
    if not missionId then
        print('^1[Mission Debug]^7 Usage: /missiondebug complete <missionId>')
        return
    end

    local orgId = LocalPlayer.state.organization
    if not orgId then
        print('^1[Mission Debug]^7 You must be in an organization')
        return
    end

    local organization = OrganizationManager:get(orgId)
    if not organization or not organization.missions then
        print('^1[Mission Debug]^7 Organization missions not initialized')
        return
    end

    local activeMission = organization.missions:getActiveMission(missionId)
    if not activeMission then
        print(string.format('^1[Mission Debug]^7 Mission not active: %s', missionId))
        return
    end

    -- Force complete by setting progress to target
    local mission = activeMission.mission
    organization.missions:updateProgress(missionId, activeMission.targetValue, true)

    print(string.format('^2[Mission Debug]^7 Force completed mission: %s', missionId))
end

---@param missionId string
---@param amount number
function MissionDebug:testProgress(missionId, amount)
    if not missionId or not amount then
        print('^1[Mission Debug]^7 Usage: /missiondebug progress <missionId> <amount>')
        return
    end

    amount = tonumber(amount)
    if not amount then
        print('^1[Mission Debug]^7 Amount must be a number')
        return
    end

    local orgId = LocalPlayer.state.organization
    if not orgId then
        print('^1[Mission Debug]^7 You must be in an organization')
        return
    end

    local organization = OrganizationManager:get(orgId)
    if not organization or not organization.missions then
        print('^1[Mission Debug]^7 Organization missions not initialized')
        return
    end

    local activeMission = organization.missions:getActiveMission(missionId)
    if not activeMission then
        print(string.format('^1[Mission Debug]^7 Mission not active: %s', missionId))
        return
    end

    local newProgress = activeMission.progress + amount
    local completed = newProgress >= activeMission.targetValue

    organization.missions:updateProgress(missionId, newProgress, completed)

    print(string.format('^2[Mission Debug]^7 Progressed mission %s by %d (new: %d/%d)',
        missionId, amount, newProgress, activeMission.targetValue))
end

function MissionDebug:printRegistry()
    print('^3[Mission Debug]^7 Mission Module Registry:')
    if not MissionModuleRegistry or not next(MissionModuleRegistry) then
        print('^1  No modules registered^7')
        return
    end

    for moduleName, module in pairs(MissionModuleRegistry) do
        print(string.format('^2  [%s]^7 Module registered', moduleName))
    end
end

function MissionDebug:simulateSpray()
    local orgId = LocalPlayer.state.organization
    if not orgId then
        print('^1[Mission Debug]^7 You must be in an organization')
        return
    end

    TriggerEvent('crime:graffiti:created', {
        id = 999999,
        label = 'Debug Graffiti',
        texture = 'debug',
        text = 'Debug',
        coords = GetEntityCoords(cache.ped),
        rotation = vec3(0.0, 0.0, 0.0),
        scale = 1.0
    })

    print('^2[Mission Debug]^7 Simulated graffiti spray event')
end

function MissionDebug:simulateRemove()
    local orgId = LocalPlayer.state.organization
    if not orgId then
        print('^1[Mission Debug]^7 You must be in an organization')
        return
    end

    TriggerEvent('crime:graffiti:removed', 999999, {
        territoryId = nil,
        removerOrgId = orgId,
        isOwn = false
    })

    print('^2[Mission Debug]^7 Simulated graffiti remove event')
end

function MissionDebug:simulateWarWin()
    local orgId = LocalPlayer.state.organization
    if not orgId then
        print('^1[Mission Debug]^7 You must be in an organization')
        return
    end

    TriggerEvent('crime:territoryWarWon', {
        orgId = orgId,
        territoryId = 1
    })

    print('^2[Mission Debug]^7 Simulated territory war won event')
end

---@param amount number
function MissionDebug:simulateDrugSale(amount)
    if not amount then
        amount = 5000
    else
        amount = tonumber(amount)
    end

    local orgId = LocalPlayer.state.organization
    if not orgId then
        print('^1[Mission Debug]^7 You must be in an organization')
        return
    end

    TriggerEvent('crime:territoryWarDrugSale', {
        orgId = orgId,
        amount = amount,
        territoryId = nil
    })

    print(string.format('^2[Mission Debug]^7 Simulated drug sale event: $%d', amount))
end

function MissionDebug:help()
    print('^3[Mission Debug]^7 Available Commands:')
    print('^5  /missiondebug list^7 - List all available missions')
    print('^5  /missiondebug active^7 - List active missions')
    print('^5  /missiondebug modules^7 - Show loaded mission modules')
    print('^5  /missiondebug registry^7 - Show module registry')
    print('^5  /missiondebug start <missionId>^7 - Start a mission')
    print('^5  /missiondebug complete <missionId>^7 - Force complete a mission')
    print('^5  /missiondebug progress <missionId> <amount>^7 - Add progress to mission')
    print('^5  /missiondebug spray^7 - Simulate graffiti spray')
    print('^5  /missiondebug remove^7 - Simulate graffiti remove')
    print('^5  /missiondebug war^7 - Simulate territory war win')
    print('^5  /missiondebug drug <amount>^7 - Simulate drug sale')
    print('^5  /missiondebug help^7 - Show this help')
end

-- Register commands
RegisterCommand('missiondebug', function(source, args)
    local command = args[1] or 'help'

    if command == 'list' then
        MissionDebug:printMissions()
    elseif command == 'active' then
        MissionDebug:printActiveMissions()
    elseif command == 'modules' then
        MissionDebug:printModules()
    elseif command == 'registry' then
        MissionDebug:printRegistry()
    elseif command == 'start' then
        MissionDebug:testStart(args[2])
    elseif command == 'complete' then
        MissionDebug:testComplete(args[2])
    elseif command == 'progress' then
        MissionDebug:testProgress(args[2], args[3])
    elseif command == 'spray' then
        MissionDebug:simulateSpray()
    elseif command == 'remove' then
        MissionDebug:simulateRemove()
    elseif command == 'war' then
        MissionDebug:simulateWarWin()
    elseif command == 'drug' then
        MissionDebug:simulateDrugSale(args[2])
    else
        MissionDebug:help()
    end
end, false)

RegisterCommand('md', function(source, args)
    local newArgs = { args[1] or 'help' }
    for i = 2, #args do
        newArgs[i] = args[i]
    end

    local command = newArgs[1] or 'help'

    if command == 'list' then
        MissionDebug:printMissions()
    elseif command == 'active' then
        MissionDebug:printActiveMissions()
    elseif command == 'modules' then
        MissionDebug:printModules()
    elseif command == 'registry' then
        MissionDebug:printRegistry()
    elseif command == 'start' then
        MissionDebug:testStart(newArgs[2])
    elseif command == 'complete' then
        MissionDebug:testComplete(newArgs[2])
    elseif command == 'progress' then
        MissionDebug:testProgress(newArgs[2], newArgs[3])
    elseif command == 'spray' then
        MissionDebug:simulateSpray()
    elseif command == 'remove' then
        MissionDebug:simulateRemove()
    elseif command == 'war' then
        MissionDebug:simulateWarWin()
    elseif command == 'drug' then
        MissionDebug:simulateDrugSale(newArgs[2])
    else
        MissionDebug:help()
    end
end, false)
