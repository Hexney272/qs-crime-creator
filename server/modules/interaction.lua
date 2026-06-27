-- ============================================================
-- server/modules/interaction.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Server-side interaction events: handcuffing, escorting,
-- and head-bag placement.
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:handcuff"
--   Relays handcuff/arrest events to both the arresting player
--   and the arrested player.  Requires the sender to be in an
--   organization (anti-exploit check).
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:handcuff", function(targetPlayerId)
    local arresterId = source
    local arresterOrg = Player(arresterId).state.organization

    if not arresterOrg then
        Error("Player is trying to exploit! ", arresterId)
        return
    end

    -- Tell the arrested player they are now arrested
    TriggerClientEvent("crime:arrested",  targetPlayerId, arresterId)
    -- Tell the arresting player to play the arrest animation
    TriggerClientEvent("crime:arrest",    arresterId)
    -- Tell the target to put on handcuffs
    TriggerClientEvent("crime:handcuff",  targetPlayerId)
end)

-- ──────────────────────────────────────────────────────────
-- Server event: "crime:setPlayerEscort"
--   Syncs an escorted player's state and optionally puts them
--   in a vehicle seat.
--   Parameters:
--     targetPlayerId  – player being escorted
--     isEscorting     – true = start escort, false/nil = stop
--     vehicleNetId    – network ID of the vehicle (optional)
--     vehicleSeat     – seat index to put target in (optional)
--     teleport        – true = teleport target to escorter first
-- ──────────────────────────────────────────────────────────
RegisterServerEvent("crime:setPlayerEscort",
    function(targetPlayerId, isEscorting, vehicleNetId, vehicleSeat, teleport)

    local escorterId = source
    local escorterOrg = Player(escorterId).state.organization

    if not escorterOrg then
        Error("Player is trying to exploit! ", escorterId)
        return
    end

    targetPlayerId = tonumber(targetPlayerId)
    if not targetPlayerId or targetPlayerId == 0 then return end

    local escorterPed = GetPlayerPed(escorterId)
    local targetPed   = GetPlayerPed(targetPlayerId)
    if not escorterPed or not targetPed then return end

    -- Anti-cheat: must be within 10 metres of each other
    local escorterPos = GetEntityCoords(escorterPed)
    local targetPos   = GetEntityCoords(targetPed)

    if escorterPos and targetPos then
        if #(escorterPos - targetPos) > 10 then
            return
        end
    end

    -- Optionally teleport the target to the escorter
    if teleport then
        SetEntityCoords(targetPed, escorterPos.x, escorterPos.y, escorterPos.z)
    end

    -- Update the target's "isEscorted" state bag
    local targetState = Player(targetPlayerId)
    if not targetState then return end

    targetState = targetState.state
    targetState:set("isEscorted", isEscorting and escorterId or nil, true)

    -- If a vehicle and seat were given, put the target in it
    if not vehicleNetId or not vehicleSeat then return end

    Wait(500)

    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    if not DoesEntityExist(vehicle) then return end

    SetPedIntoVehicle(targetPed, vehicle, vehicleSeat)
end)

-- ──────────────────────────────────────────────────────────
-- Head-bag state tracking (server-side)
-- headsbagged[playerId] = true | nil
-- ──────────────────────────────────────────────────────────
local headsbagged = {}

local function hasHeadbag(playerId)
    return headsbagged[playerId] == true
end

local function setHeadbag(playerId, state)
    headsbagged[playerId] = state and true or nil
end

-- Clean up on disconnect
AddEventHandler("playerDropped", function()
    local playerId = source
    if headsbagged[playerId] then
        headsbagged[playerId] = nil
    end
end)

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:putHeadbagOn"
--   Puts a head-bag on `targetPlayerId`.
--   Requires the sender to be in an organization.
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:putHeadbagOn", function(targetPlayerId)
    local senderId = source
    local senderOrg = Player(senderId).state.organization

    if not senderOrg then
        Error("Player is trying to exploit! ", senderId)
        return
    end

    if not Player(targetPlayerId) then return end

    -- Don't apply twice
    if hasHeadbag(targetPlayerId) then return end

    setHeadbag(targetPlayerId, true)
    TriggerClientEvent("crime:putHeadbagOn", targetPlayerId)
end)

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:takeHeadbagOff"
--   Removes the head-bag from `targetPlayerId`.
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:takeHeadbagOff", function(targetPlayerId)
    local senderId = source
    local senderOrg = Player(senderId).state.organization

    if not senderOrg then
        Error("Player is trying to exploit! ", senderId)
        return
    end

    if not Player(targetPlayerId) then return end

    -- Nothing to remove
    if not hasHeadbag(targetPlayerId) then return end

    setHeadbag(targetPlayerId, false)
    TriggerClientEvent("crime:takeHeadbagOff", targetPlayerId)
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:hasHeadbag"
--   Returns true if the given player has a head-bag on.
--   If `targetId` is omitted the caller themselves is checked.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:hasHeadbag", function(callerId, targetId)
    local checkId = targetId or callerId
    return hasHeadbag(checkId)
end)
