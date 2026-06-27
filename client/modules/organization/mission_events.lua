-- ============================================================
-- client/modules/organization/mission_events.lua (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Receives mission start/cancel events from the server and
-- delegates to the org's mission manager.
-- Also runs a reconciliation loop every 35 s to restart
-- missions that were active but not tracked locally.
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:mission:start"
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:mission:start", function(missionId, orgMissionId)
    if not missionId or not orgMissionId then
        Error("crime:mission:start", "missionId and orgMissionId must be provided")
        return
    end

    local orgId = LocalPlayer.state.organization
    if not orgId then return end

    local org = OrganizationManager:get(orgId)
    if not (org and org.missions) then return end

    org.missions:startMission(missionId, orgMissionId)
    Debug("crime:mission:start", "Started mission:", missionId, "orgMissionId:", orgMissionId)
end)

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:mission:cancelled"
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:mission:cancelled", function(missionId, orgMissionId)
    if not missionId then
        Error("crime:mission:cancelled", "missionId must be provided")
        return
    end

    local orgId = LocalPlayer.state.organization
    if not orgId then return end

    local org = OrganizationManager:get(orgId)
    if not (org and org.missions) then return end

    org.missions:stopMission(missionId)
    Debug("crime:mission:cancelled", "Cancelled mission:", missionId,
        "orgMissionId:", orgMissionId)
end)

-- ──────────────────────────────────────────────────────────
-- Reconciliation loop
--   Every 35 s, fetches active org missions from the server
--   and restarts any that are active but not tracked locally.
-- ──────────────────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(5000)

        local orgId = LocalPlayer.state.organization
        if orgId then
            local org = OrganizationManager:get(orgId)

            if org and org.missions then
                local missions = lib.callback.await(
                    "crime:getOrganizationMissions", false, orgId
                ) or {}

                for _, mission in ipairs(missions) do
                    if mission.status == "active" and mission.mission_id then
                        local tracked = org.missions:getActiveMission(mission.mission_id)
                        if not tracked then
                            org.missions:startMission(mission.mission_id, mission.id)
                        end
                    end
                end
            end
        end

        Wait(30000)
    end
end)
