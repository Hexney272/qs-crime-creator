-- ============================================================
-- client/modules/pvp/main.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Client-side PvP battle system.  Manages zone creation,
-- map blips, player death detection, and React UI integration.
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- Module-private state tables
-- ──────────────────────────────────────────────────────────
local activeBattles   = {}   -- [battleId] = battleData
local activeZones     = {}   -- [battleId] = ox_lib poly-zone
local activeBlips     = {}   -- [battleId] = blip handle
local inZone          = {}   -- [battleId] = bool (player inside zone)
local deathReported   = {}   -- [battleId] = bool (death already sent)

_G.PvpModule = {}

-- ──────────────────────────────────────────────────────────
-- local createPvpZone(battleId, battleData)
--   Creates an ox_lib polygon zone for `battleData`.
--   The zone must have at least 3 points.
--   Hooks onEnter / onExit / inside to drive server events.
-- ──────────────────────────────────────────────────────────
local function createPvpZone(battleId, battleData)
    if not (battleData.zone_points
        and battleData.zone_points.points
        and #battleData.zone_points.points >= 3) then
        return
    end

    -- Remove any existing zone for this battle
    if activeZones[battleId] then
        activeZones[battleId]:remove()
        activeZones[battleId] = nil
    end

    -- Convert config point tables to vec3 values
    local points = table.map(battleData.zone_points.points, function(pt)
        return vec3(pt.x, pt.y, pt.z)
    end)

    local thickness = battleData.zone_points.thickness or 25.0

    -- Create the poly zone
    activeZones[battleId] = lib.zones.poly({
        name      = "pvp_zone_" .. battleId,
        points    = points,
        thickness = thickness,
        debug     = true,

        -- ── onEnter ───────────────────────────────────────
        onEnter = function()
            inZone[battleId]        = true
            deathReported[battleId] = false

            Debug("PvP Zone", "Entered zone:", battleId)

            local orgId = LocalPlayer.state.organization
            if not orgId then return end

            local battle = activeBattles[battleId]
            if not battle then return end

            -- Fetch participants if not cached yet
            if not battle.participants then
                battle.participants = lib.callback.await(
                    "crime:getPvpParticipants", false, battleId
                )
            end

            -- Check if this player's org is an accepted participant
            local isParticipant = false
            for _, participant in ipairs(battle.participants or {}) do
                if participant.organization_id == orgId
                and participant.status == "accepted" then
                    isParticipant = true
                    break
                end
            end

            if isParticipant then
                TriggerServerEvent("crime:pvpPlayerEnteredZone", battleId, orgId)
                Debug("PvP Zone",
                    "Sending pvp_zone_entered to NUI, battleId:", battleId,
                    "orgId:", orgId, "battle:", battle)
                SendReactMessage("pvp_zone_entered", {
                    pvp_battle_id  = battleId,
                    organization_id = orgId,
                    battle_data    = battle,
                })
            else
                Debug("PvP Zone",
                    "Player is not a participant, orgId:", orgId, "battleId:", battleId)
            end
        end,

        -- ── onExit ────────────────────────────────────────
        onExit = function()
            inZone[battleId]        = false
            deathReported[battleId] = false

            Debug("PvP Zone", "Exited zone:", battleId)

            local orgId = LocalPlayer.state.organization
            if not orgId then return end

            TriggerServerEvent("crime:pvpPlayerExitedZone", battleId, orgId)
            SendReactMessage("pvp_zone_exited", {
                pvp_battle_id   = battleId,
                organization_id = orgId,
            })
        end,

        -- ── inside (per-frame) ────────────────────────────
        inside = function()
            if not inZone[battleId] then return end

            local orgId = LocalPlayer.state.organization
            if not orgId then return end

            local battle = activeBattles[battleId]
            if not battle then return end

            -- Check participant status
            local isParticipant = false
            for _, participant in ipairs(battle.participants or {}) do
                if participant.organization_id == orgId
                and participant.status == "accepted" then
                    isParticipant = true
                    break
                end
            end

            if isParticipant then
                -- Send a heartbeat every 2 seconds
                if not battle.lastHeartbeatTime then
                    battle.lastHeartbeatTime = 0
                end

                local now = GetGameTimer()
                if (now - battle.lastHeartbeatTime) > 2000 then
                    battle.lastHeartbeatTime = now
                    TriggerServerEvent("crime:pvpPlayerHeartbeat", battleId)
                end
            end
        end,
    })

    Debug("PvP Zone", "Created zone for battle:", battleId)
end

-- ──────────────────────────────────────────────────────────
-- local removeZone(battleId)
--   Removes the poly zone for a battle and clears flags.
-- ──────────────────────────────────────────────────────────
local function removeZone(battleId)
    if activeZones[battleId] then
        activeZones[battleId]:remove()
        activeZones[battleId] = nil
    end
    inZone[battleId]        = nil
    deathReported[battleId] = nil
end

-- ──────────────────────────────────────────────────────────
-- local createPvpBlip(battleId, battleData)
--   Creates a map blip at the battle's centre coords.
-- ──────────────────────────────────────────────────────────
local function createPvpBlip(battleId, battleData)
    if not battleData.center_coords then return end

    -- Remove existing blip
    if activeBlips[battleId] then
        Utils.RemoveBlip(activeBlips[battleId])
        activeBlips[battleId] = nil
    end

    local centre = vec3(
        battleData.center_coords.x,
        battleData.center_coords.y,
        battleData.center_coords.z
    )

    activeBlips[battleId] = Utils.CreateBlip({
        location   = centre,
        sprite     = 84,
        color      = 1,
        scale      = 0.8,
        display    = 4,
        shortRange = false,
        highDetail = true,
        text       = battleData.label or "PvP Battle",
    })

    Debug("PvP Blip", "Created blip for battle:", battleId)
end

-- ──────────────────────────────────────────────────────────
-- local removeBlip(battleId)
--   Removes the blip for a battle.
-- ──────────────────────────────────────────────────────────
local function removeBlip(battleId)
    if activeBlips[battleId] then
        Utils.RemoveBlip(activeBlips[battleId])
        activeBlips[battleId] = nil
    end
end

-- ──────────────────────────────────────────────────────────
-- local setupActiveBattle(battleId, battleData)
--   Fetches participants, registers the battle in the active
--   table, creates the zone and blip, then notifies the UI
--   if the local player's org is a participant already inside.
-- ──────────────────────────────────────────────────────────
local function setupActiveBattle(battleId, battleData)
    local participants = lib.callback.await(
        "crime:getPvpParticipants", false, battleId
    )
    battleData.participants = participants

    activeBattles[battleId] = battleData

    createPvpZone(battleId, battleData)
    createPvpBlip(battleId, battleData)

    local orgId = LocalPlayer.state.organization
    if orgId and inZone[battleId] then
        local isParticipant = false
        for _, participant in ipairs(battleData.participants or {}) do
            if participant.organization_id == orgId
            and participant.status == "accepted" then
                isParticipant = true
                break
            end
        end

        if isParticipant then
            SendReactMessage("pvp_zone_entered", {
                pvp_battle_id   = battleId,
                organization_id = orgId,
                battle_data     = battleData,
            })
        end
    end
end

-- ──────────────────────────────────────────────────────────
-- local finishBattle(battleId)
--   Tears down zone/blip, clears state, notifies UI.
-- ──────────────────────────────────────────────────────────
local function finishBattle(battleId)
    local orgId = LocalPlayer.state.organization

    removeZone(battleId)
    removeBlip(battleId)
    activeBattles[battleId] = nil

    if orgId and inZone[battleId] then
        SendReactMessage("pvp_zone_exited", {
            pvp_battle_id   = battleId,
            organization_id = orgId,
        })
    end

    SendReactMessage("pvp_battle_winner", { pvp_battle_id = battleId })
end

-- ──────────────────────────────────────────────────────────
-- Game event: CEventNetworkEntityDamage
--   Detects when the local ped dies while inside an active
--   PvP zone and sends a single death report to the server.
-- ──────────────────────────────────────────────────────────
AddEventHandler("gameEventTriggered", function(eventName, eventData)
    if eventName ~= "CEventNetworkEntityDamage" then return end

    local victim     = eventData[1]
    local attacker   = eventData[2]
    local wasFatal   = (eventData[6] == 1)

    if victim ~= cache.ped then return end
    if not IsPlayerDead() then return end

    -- Check every active battle
    for battleId, battleData in pairs(activeBattles) do
        if battleData.status == "active" then
            if inZone[battleId] and not deathReported[battleId] then
                deathReported[battleId] = true

                local orgId = LocalPlayer.state.organization
                if orgId then
                    TriggerServerEvent("crime:pvpPlayerDeath", battleId)
                end
            end
        end
    end
end)

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:pvpBattleStarted"
--   Server signals that a battle has become active.
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:pvpBattleStarted", function(payload)
    local battleId = payload.pvp_battle_id
    if not battleId then return end

    local battleData = lib.callback.await("crime:getPvpBattle", false, battleId)
    if battleData then
        setupActiveBattle(battleId, battleData)
    end
end)

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:pvpBattleFinished"
--   Server signals the battle has ended; push winner info to UI.
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:pvpBattleFinished", function(payload)
    local battleId = payload.pvp_battle_id
    if not battleId then return end

    SendReactMessage("pvp_battle_winner", {
        pvp_battle_id  = battleId,
        winner_org_id  = payload.winner_org_id,
        scores         = payload.scores,
    })
end)

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:pvpBattleDestroyed"
--   Fully removes a battle from the client.
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:pvpBattleDestroyed", function(battleId)
    if not battleId then return end

    removeZone(battleId)
    removeBlip(battleId)
    activeBattles[battleId] = nil

    SendReactMessage("pvp_battle_destroyed", { pvp_battle_id = battleId })
end)

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:pvpInvitationAccepted"
--   An org accepted the PvP invite — set up zone if active.
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:pvpInvitationAccepted", function(payload)
    local battleId = payload.pvp_battle_id
    if not battleId then return end

    local battleData = lib.callback.await("crime:getPvpBattle", false, battleId)
    if battleData and battleData.status == "active" then
        setupActiveBattle(battleId, battleData)
    end
end)

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:pvpScoreUpdated"
--   Relay score update to the React UI.
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:pvpScoreUpdated", function(payload)
    SendReactMessage("pvp_score_updated", {
        pvp_battle_id   = payload.pvp_battle_id,
        organization_id = payload.organization_id,
        score           = payload.score,
    })
end)

-- ──────────────────────────────────────────────────────────
-- PvpModule.handleBattleCreated(battleData)
--   Called when the RecordManager syncs a newly created battle.
-- ──────────────────────────────────────────────────────────
function PvpModule.handleBattleCreated(battleData)
    if not (battleData and battleData.id) then
        Error("PvpModule.handleBattleCreated", "Invalid battle data", battleData)
        return false
    end

    Debug("PvpModule.handleBattleCreated",
        "Creating battle:", battleData.id, "status:", battleData.status)

    local battleId = battleData.id

    if battleData.status == "active" then
        setupActiveBattle(battleId, battleData)
    elseif battleData.status == "pending" and battleData.center_coords then
        createPvpBlip(battleId, battleData)
    end

    SendReactMessage("pvp_battle_created", { battle = battleData })
    return true
end

RegisterNetEvent("crime:pvpBattleCreated", function(battleData)
    PvpModule.handleBattleCreated(battleData)
end)

-- ──────────────────────────────────────────────────────────
-- PvpModule.handleBattleUpdated(battleData)
--   Called when an existing battle changes status.
-- ──────────────────────────────────────────────────────────
function PvpModule.handleBattleUpdated(battleData)
    if not (battleData and battleData.id) then
        Error("PvpModule.handleBattleUpdated", "Invalid battle data", battleData)
        return false
    end

    Debug("PvpModule.handleBattleUpdated",
        "Updating battle:", battleData.id, "status:", battleData.status)

    local battleId = battleData.id

    -- Tear down existing zone/blip before re-creating
    removeZone(battleId)
    removeBlip(battleId)
    activeBattles[battleId] = nil

    if battleData.status == "active" then
        Debug("PvpModule.handleBattleUpdated", "Battle is active, setting up:", battleId)
        setupActiveBattle(battleId, battleData)

    elseif battleData.status == "pending" then
        Debug("PvpModule.handleBattleUpdated", "Battle is pending, creating blip only:", battleId)
        if battleData.center_coords then
            createPvpBlip(battleId, battleData)
        end

    elseif battleData.status == "finished" then
        Debug("PvpModule.handleBattleUpdated", "Battle is finished, no zone/blip needed:", battleId)
    end

    SendReactMessage("pvp_battle_updated", { battle = battleData })
    return true
end

RegisterNetEvent("crime:pvpBattleUpdated", function(battleData)
    PvpModule.handleBattleUpdated(battleData)
end)

-- ──────────────────────────────────────────────────────────
-- PvpModule.handleBattleRemoved(battleId)
--   Called when a battle is deleted from the records.
-- ──────────────────────────────────────────────────────────
function PvpModule.handleBattleRemoved(battleId)
    if not battleId then
        Error("PvpModule.handleBattleRemoved", "Invalid battleId")
        return false
    end

    Debug("PvpModule.handleBattleRemoved", "Removing battle:", battleId)

    if activeBattles[battleId] then
        finishBattle(battleId)
    else
        removeBlip(battleId)
    end

    return true
end

RegisterNetEvent("crime:pvpBattleRemoved", function(battleId)
    PvpModule.handleBattleRemoved(battleId)
end)

-- ──────────────────────────────────────────────────────────
-- onResourceStop — clean up all PvP zones and blips
-- ──────────────────────────────────────────────────────────
AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        for battleId in pairs(activeBattles) do
            finishBattle(battleId)
        end
    end
end)
