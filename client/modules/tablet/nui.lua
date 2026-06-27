-- ============================================================
-- client/modules/tablet/nui.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- NUI callbacks for the crime tablet UI.
-- Bridges tablet NUI (React) ↔ server callbacks and net events.
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- Helper: wrap a callback call with a fallback empty table/value
-- ──────────────────────────────────────────────────────────
local function cbAwait(callbackName, ...)
    local ok, result = pcall(lib.callback.await, callbackName, false, ...)
    if not ok then
        Error("cbAwait ::: " .. tostring(callbackName), result)
        return nil
    end
    return result
end

-- ──────────────────────────────────────────────────────────
-- Territories
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("crime_tablet:get_territories", function(_, cb)
    cb(cbAwait("crime:getTerritories") or {})
end)

-- ──────────────────────────────────────────────────────────
-- Rankings
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("crime_tablet:get_rankings", function(_, cb)
    cb(cbAwait("crime:getOrganizationRankings") or {})
end)

-- ──────────────────────────────────────────────────────────
-- Organization stats
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("crime_tablet:get_organization_stats", function(data, cb)
    if not (data and data.organizationId) then return cb(nil) end
    cb(cbAwait("crime:getOrganizationStats", data.organizationId))
end)

-- ──────────────────────────────────────────────────────────
-- Available missions for an org
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("crime_tablet:get_missions", function(data, cb)
    if not (data and data.organizationId) then return cb({}) end
    cb(cbAwait("crime:getMissions", data.organizationId) or {})
end)

-- ──────────────────────────────────────────────────────────
-- Active/completed missions for an org
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("crime_tablet:get_organization_missions", function(data, cb)
    if not (data and data.organizationId) then return cb({}) end
    cb(cbAwait("crime:getOrganizationMissions", data.organizationId) or {})
end)

-- ──────────────────────────────────────────────────────────
-- Take (start) a mission
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("crime_tablet:take_mission", function(data, cb)
    if not (data and data.organizationId and data.missionId) then
        return cb({ success = false, message = "invalid_params" })
    end
    local ok, msg = cbAwait("crime:takeMission", data.organizationId, data.missionId)
    cb({ success = ok, message = msg })
end)

-- ──────────────────────────────────────────────────────────
-- Season Pass
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("crime_tablet:get_season_pass", function(data, cb)
    if not (data and data.organizationId) then return cb(nil) end
    cb(cbAwait("crime:getSeasonPass", data.organizationId))
end)

RegisterNUICallback("crime_tablet:get_organization_seasonpass_data", function(data, cb)
    if not (data and data.organizationId) then return cb(nil) end
    cb(cbAwait("crime:getOrganizationSeasonPassData", data.organizationId))
end)

RegisterNUICallback("crime_tablet:claim_seasonpass_reward", function(data, cb)
    if not (data and data.organizationId and data.level and data.tier) then
        return cb(false)
    end
    cb(cbAwait("crime:claimSeasonPassReward", data.organizationId, data.level, data.tier))
end)

RegisterNUICallback("crime_tablet:purchase_seasonpass_premium", function(data, cb)
    if not (data and data.organizationId) then return cb(false) end
    cb(cbAwait("crime:purchaseSeasonPassPremium", data.organizationId))
end)

-- ──────────────────────────────────────────────────────────
-- Territory war
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("crime_tablet:get_active_territory_war", function(data, cb)
    if not (data and data.territoryId) then return cb(nil) end
    cb(cbAwait("crime:getActiveTerritoryWar", data.territoryId))
end)

RegisterNUICallback("crime_tablet:get_territory_war_scores", function(data, cb)
    if not (data and data.warId) then return cb({}) end
    cb(cbAwait("crime:getTerritoryWarScores", data.warId) or {})
end)

RegisterNUICallback("crime_tablet:start_territory_war", function(data, cb)
    if not (data and data.territoryId) then
        return cb({ success = false, message = i18n.t("tablet.map.invalid_territory") })
    end
    local ok, msg = cbAwait("crime:startTerritoryWar", data.territoryId)
    cb({ success = ok, message = msg })
end)

-- ──────────────────────────────────────────────────────────
-- Member stats
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("crime_tablet:get_organization_member_stats", function(data, cb)
    if not (data and data.organizationId) then return cb({}) end
    cb(cbAwait("crime:getOrganizationMemberStats", data.organizationId) or {})
end)

-- ──────────────────────────────────────────────────────────
-- Mission rewards
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("crime_tablet:get_completed_missions_with_rewards", function(data, cb)
    if not (data and data.organizationId) then return cb({}) end
    cb(cbAwait("crime:getCompletedMissionsWithRewards", data.organizationId) or {})
end)

RegisterNUICallback("crime_tablet:claim_mission_rewards", function(data, cb)
    if not (data and data.orgMissionId) then
        return cb({ success = false, message = "invalid_params" })
    end
    local ok, msg = cbAwait("crime:claimMissionRewards", data.orgMissionId)
    cb({ success = ok, message = msg })
end)

-- ──────────────────────────────────────────────────────────
-- Cancel a mission
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("crime_tablet:cancel_mission", function(data, cb)
    if not (data and data.organizationId and data.orgMissionId) then
        return cb({ success = false, message = "invalid_params" })
    end

    local ok, msg = cbAwait("crime:cancelMission", data.organizationId, data.orgMissionId)

    -- If cancelled, also stop the local mission tracker
    if ok then
        local orgId = LocalPlayer.state.organization
        if orgId then
            local org = OrganizationManager:get(orgId)
            if org and org.missions then
                local currentMissions = cbAwait("crime:getOrganizationMissions", orgId) or {}
                for _, m in ipairs(currentMissions) do
                    if m.id == data.orgMissionId then
                        org.missions:stopMission(m.mission_id)
                        break
                    end
                end
            end
        end
    end

    cb({ success = ok, message = msg })
end)

-- ──────────────────────────────────────────────────────────
-- Territory war net events → forward to React
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:territoryWarStarted", function(data)
    SendReactMessage("crime_tablet:territory_war_started", data)
    SendReactMessage("territory_war_started", data)

    local territory = data.territory_label or "Territory"
    if data.is_attacker then
        Notification(i18n.t("tablet.territory_war.started_attacker",
            { territory = territory }), "warning")
    else
        local attacker = data.attacker_org_label or "Unknown"
        Notification(i18n.t("tablet.territory_war.started_defender",
            { territory = territory, attacker = attacker }), "error")
    end
end)

RegisterNetEvent("crime:territoryWarEnded", function(data)
    SendReactMessage("crime_tablet:territory_war_ended", data)
    SendReactMessage("territory_war_ended", data)

    local territory = data.territory_label or "Territory"
    if data.is_winner then
        Notification(i18n.t("tablet.territory_war.won",
            { territory = territory }), "success")
    else
        local winner = data.winner_label or "Unknown"
        Notification(i18n.t("tablet.territory_war.lost",
            { territory = territory, winner = winner }), "error")
    end
end)

RegisterNetEvent("crime:territoryWarScoreUpdated", function(data)
    SendReactMessage("territory_war_score_updated", data)
end)

RegisterNetEvent("crime:territoryWarMapUpdate", function(data)
    SendReactMessage("crime_tablet:territory_war_map_update", data)
end)

-- ──────────────────────────────────────────────────────────
-- Map utilities
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("crime_tablet:set_waypoint", function(data, cb)
    if not (data and data.x and data.y) then return cb(false) end
    SetNewWaypoint(data.x, data.y)
    Notification(i18n.t("tablet.map.waypoint_set"), "success")
    cb(true)
end)

RegisterNUICallback("crime_tablet:get_player_coords", function(_, cb)
    local coords = GetEntityCoords(cache.ped)
    cb({ x = coords.x, y = coords.y, z = coords.z })
end)

-- ──────────────────────────────────────────────────────────
-- Taxing
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("crime_tablet:get_taxing", function(_, cb)
    cb(cbAwait("crime:getTaxing") or {})
end)

-- ──────────────────────────────────────────────────────────
-- PvP — invitations
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("crime_tablet:get_pvp_invitations", function(_, cb)
    local invitations = cbAwait("crime:getPvpInvitations")
    Debug("invitations", invitations)
    cb(invitations or {})
end)

RegisterNUICallback("crime_tablet:accept_pvp_invitation", function(data, cb)
    if not (data and data.pvpBattleId) then return cb(false, "invalid_params") end
    local ok, msg = cbAwait("crime:acceptPvpInvitation", data.pvpBattleId)
    cb(ok, msg)
end)

RegisterNUICallback("crime_tablet:cancel_pvp_participation", function(data, cb)
    if not (data and data.pvpBattleId) then return cb(false) end
    cb(cbAwait("crime:cancelPvpParticipation", data.pvpBattleId))
end)

-- ──────────────────────────────────────────────────────────
-- PvP — battle data
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("crime_tablet:get_pvp_battles", function(_, cb)
    local battles = cbAwait("crime:getPvpBattles")
    Debug("battles", battles)
    cb(battles or {})
end)

RegisterNUICallback("crime_tablet:get_pvp_participants", function(data, cb)
    if not (data and data.pvpBattleId) then return cb({}) end
    cb(cbAwait("crime:getPvpParticipants", data.pvpBattleId) or {})
end)

RegisterNUICallback("crime_tablet:get_pvp_scores", function(data, cb)
    if not (data and data.pvpBattleId) then return cb({}) end
    cb(cbAwait("crime:getPvpScores", data.pvpBattleId) or {})
end)

-- ──────────────────────────────────────────────────────────
-- Organizations list
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("crime_tablet:get_organizations", function(_, cb)
    cb(cbAwait("crime:getOrganizations") or {})
end)
