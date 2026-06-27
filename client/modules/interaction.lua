-- ============================================================
-- client/modules/interaction.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Client-side player interaction module.
-- Handles the radial interaction menu, handcuffs, arrest,
-- escort, put-in-vehicle, search (inventory), and headbag.
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- interaction  — radial action menu (React-based)
-- ──────────────────────────────────────────────────────────
_G.interaction = {}

-- interaction:open(actionList, onClose)
--   Opens the NUI action menu with icon + title entries.
--   While visible, movement and vehicle-entry controls remain
--   active; all other inputs are blocked.
function interaction:open(actionList, onClose)
    self.data = actionList

    -- Send only icon + title to NUI
    local nuiData = table.map(actionList, function(item)
        return { icon = item.icon, title = item.title }
    end)

    SendReactMessage("toggle_actions", { visible = true, data = nuiData })
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)

    self.visible = true
    self.onClose = onClose

    CreateThread(function()
        while self.visible do
            Wait(0)
            DisableAllControlActions(0)
            -- Keep movement / look controls enabled
            EnableControlAction(0, 30,  true)  -- move left/right
            EnableControlAction(0, 31,  true)  -- move forward/back
            EnableControlAction(0, 44,  true)  -- cover
            EnableControlAction(0, 21,  true)  -- sprint
            EnableControlAction(0, 22,  true)  -- jump
            EnableControlAction(0, 71,  true)  -- accelerate
            EnableControlAction(0, 72,  true)  -- brake
            EnableControlAction(0, 59,  true)  -- vehicle look left
            EnableControlAction(0, 78,  true)  -- vehicle look right
            EnableControlAction(0, 249, true)  -- cursor X
        end
    end)
end

-- interaction:close()
function interaction:close()
    if not self.visible then return end
    self.visible = false
    SetNuiFocusKeepInput(false)
    SendReactMessage("toggle_actions", { visible = false })
    if self.onClose then self.onClose() end
end

-- NUI callback: user clicked an action (0-indexed from NUI)
RegisterNUICallback("click_action", function(indexZero, cb)
    if not interaction.data then
        Warning("Interaction data not found")
        return
    end

    local index = indexZero + 1
    local item  = interaction.data[index]
    if not item then
        Warning("Interaction data not found")
        return
    end

    if item.onSelect then item.onSelect(index) end
    cb("ok")
end)

-- ──────────────────────────────────────────────────────────
-- Handcuff system
-- ──────────────────────────────────────────────────────────
local isHandcuffed       = false   -- local player handcuff state
local handcuffTimerEnd   = 0       -- game timer when cuffs auto-release (0 = no timer)

-- HandcuffPlayer() — find nearest handcuffable player and cuff them
function HandcuffPlayer()
    local myCoords = GetEntityCoords(cache.ped)
    local playerId, playerPed = lib.getClosestPlayer(myCoords, 3.0)

    if playerId and playerPed then
        local handsUp = IsEntityPlayingAnim(playerPed, "missminuteman_1ig_2", "handsup_base",           3)
                     or IsEntityPlayingAnim(playerPed, "random@mugging3",       "handsup_standing_base", 3)
                     or IsEntityPlayingAnim(playerPed, "mp_arresting",           "idle",                  3)

        if handsUp then
            TriggerServerEvent("crime:handcuff", GetPlayerServerId(playerId))
        else
            Notification(i18n.t("interaction.handcuff.no_handsup"), "error")
        end
    else
        Notification(i18n.t("interaction.handcuff.no_player_nearby"), "error")
    end
end

-- NetEvent: "crime:handcuff" — toggle cuffed state on local player
RegisterNetEvent("crime:handcuff", function(fromSource)
    if not isHandcuffed then Wait(3500) end  -- small delay when being cuffed
    isHandcuffed = not isHandcuffed

    local ped = cache.ped
    if isHandcuffed then
        lib.requestAnimDict("mp_arresting")
        TaskPlayAnim(ped, "mp_arresting", "idle", 8.0, -8, -1, 49, 0, 0, 0, 0)
        SetEnableHandcuffs(ped, true)
        DisablePlayerFiring(ped, true)
        SetCurrentPedWeapon(ped, -1569615261, true)  -- UNARMED
        SetPedCanPlayGestureAnims(ped, false)
        FreezeEntityPosition(ped, true)
        DisplayRadar(false)
        DisableActions(true)

        -- Set auto-release timer
        handcuffTimerEnd = GetGameTimer() + Config.RemoveHandcuffTimer
        HandcuffThread()
    else
        ClearPedSecondaryTask(ped)
        SetEnableHandcuffs(ped, false)
        DisablePlayerFiring(ped, false)
        SetPedCanPlayGestureAnims(ped, true)
        FreezeEntityPosition(ped, false)
        DisplayRadar(true)
        DisableActions(false)
    end
end)

-- HandcuffThread() — blocks controls while cuffed; auto-releases on timer or death
function HandcuffThread()
    CreateThread(function()
        local disableCtrl    = DisableControlAction
        local isPlayingAnim  = IsEntityPlayingAnim

        while isHandcuffed do
            -- Block all movement / action controls
            for _, ctrl in ipairs({ 1, 2, 24, 257, 25, 263, 32, 34, 31, 30, 45,
                22, 44, 37, 23, 288, 289, 170, 167, 0, 26, 73, 59, 71, 72,
                47, 264, 257, 140, 141, 142, 143, 75 }) do
                disableCtrl(0, ctrl, true)
            end
            disableCtrl(2, 199, true)
            disableCtrl(2, 36,  true)
            disableCtrl(27, 75, true)

            -- Ensure arrest anim keeps playing
            if not isPlayingAnim(cache.ped, "mp_arresting", "idle", 3) then
                TaskPlayAnim(cache.ped, "mp_arresting", "idle",
                    8.0, -8, -1, 49, 0.0, false, false, false)
            end

            -- Auto-release on timer or death
            local timerExpired = (handcuffTimerEnd > 0 and GetGameTimer() > handcuffTimerEnd)
            local isDead       = IsPedDeadOrDying(cache.ped, false)
                              or (LocalPlayer.state.dead == true)

            if timerExpired or isDead then
                isHandcuffed = false
                ClearPedSecondaryTask(cache.ped)
                SetEnableHandcuffs(cache.ped, false)
                DisablePlayerFiring(cache.ped, false)
                SetPedCanPlayGestureAnims(cache.ped, true)
                FreezeEntityPosition(cache.ped, false)
                DisplayRadar(true)
                DisableActions(false)
                handcuffTimerEnd = 0
            end

            Wait(0)
        end
    end)
end

-- ──────────────────────────────────────────────────────────
-- Arrest animations
-- ──────────────────────────────────────────────────────────

-- NetEvent "crime:arrested" — play crook arrest anim (attach to arrester)
RegisterNetEvent("crime:arrested", function(arrestingPlayerId)
    local myPed      = cache.ped
    local arresterPed = GetPlayerPed(arrestingPlayerId)

    if not isHandcuffed then
        lib.requestAnimDict("mp_arrest_paired")
        AttachEntityToEntity(myPed, arresterPed, 11816,
            -0.1, 0.45, 0.0,  0.0, 0.0, 20.0,
            false, false, false, false, 20, false)
        TaskPlayAnim(myPed, "mp_arrest_paired", "crook_p2_back_left",
            8.0, -8.0, 5500, 33, 0, false, false, false)
        Wait(950)
        DetachEntity(myPed, true, false)
    end
end)

-- NetEvent "crime:arrest" — play cop arrest anim
RegisterNetEvent("crime:arrest", function()
    local myPed = cache.ped
    local myCoords = GetEntityCoords(myPed)
    local closestId, closestPed = lib.getClosestPlayer(myCoords, 3.0)

    if closestId and closestPed then
        local targetCuffed = IsEntityPlayingAnim(closestPed, "mp_arresting", "idle", 3)
        if targetCuffed then
            lib.requestAnimDict("veh@van@ps@enter_exit")
            TaskPlayAnim(myPed, "veh@van@ps@enter_exit", "d_close_out_no_door",
                8.0, 1.0, -1, 16, 0, 0, 0, 0)
            Wait(500)
            ClearPedTasks(myPed)
        else
            lib.requestAnimDict("mp_arrest_paired")
            TaskPlayAnim(myPed, "mp_arrest_paired", "cop_p2_back_left",
                8.0, -8.0, 5500, 33, 0, false, false, false)
            Wait(3000)
        end
    end
end)

-- ──────────────────────────────────────────────────────────
-- Robbery / inventory search
-- ──────────────────────────────────────────────────────────

-- local monitorRobberyDistance(robbedPlayerId)
--   Closes inventory and notifies if robber moves too far.
local function monitorRobberyDistance(robbedPlayerId)
    CreateThread(function()
        while true do
            Wait(100)
            local robbedPed = GetPlayerPed(robbedPlayerId)
            if not (DoesEntityExist(robbedPed) and NetworkIsPlayerActive(robbedPlayerId)) then
                TriggerEvent("inventory:client:closeinv")
                Notification(i18n.t("interaction.robbery_away"), "info")
                break
            end

            local dist = #(GetEntityCoords(cache.ped) - GetEntityCoords(robbedPed))
            if dist > 5 then
                Wait(500)
                TriggerEvent("inventory:client:closeinv")
                Notification(i18n.t("interaction.robbery_away"), "info")
                break
            end
        end
    end)
end

-- SearchPlayer() — search the nearest handcuffed / hands-up player
function SearchPlayer()
    local myCoords = GetEntityCoords(cache.ped)
    local closestId, closestPed = lib.getClosestPlayer(myCoords, 3.0)

    if not (closestId and closestPed) then
        Notification(i18n.t("interaction.no_player_nearby"), "error")
        return
    end

    local serverId = GetPlayerServerId(closestId)

    -- If target is dead/downed, open inventory immediately
    if IsPedDeadOrDying(closestPed, false) or Player(serverId).state.dead then
        return OpenInventory(closestId)
    end

    -- Must be hands-up or cuffed
    local targetHandsUp = IsEntityPlayingAnim(closestPed, "missminuteman_1ig_2", "handsup_base",           3)
                       or IsEntityPlayingAnim(closestPed, "random@mugging3",       "handsup_standing_base", 3)
                       or IsEntityPlayingAnim(closestPed, "mp_arresting",           "idle",                  3)

    if not targetHandsUp then
        Notification(i18n.t("interaction.no_handsup_or_handcuff"), "error")
        return
    end

    -- Play steal animation sequence
    lib.requestAnimDict("missminuteman_1ig_2")
    lib.requestAnimDict("missbigscore2aig_7@driver")
    lib.requestAnimDict("mini@yoga")
    lib.requestAnimDict("anim@heists@box_carry@")

    CreateThread(function()
        ProgressBar({ duration = 4350, label = i18n.t("interaction.steal_player"),
            disable = { move = true, combat = true, mouse = true, look = true } })
    end)

    AttachEntityToEntity(cache.ped, closestPed, 11816,
        0.0, -0.85, 0.0,  0.0, 0.0, 0.0,
        false, false, false, false, 20, false)

    TaskPlayAnim(cache.ped, "missbigscore2aig_7@driver", "boot_r_loop",
        8.0, -8.0, -1, 1, 0, false, false, false)
    Wait(1000)
    TaskPlayAnim(cache.ped, "missbigscore2aig_7@driver", "boot_l_loop",
        8.0, -8.0, -1, 1, 0, false, false, false)
    Wait(1000)
    TaskPlayAnim(cache.ped, "mini@yoga", "outro_2",
        8.0, -8.0, -1, 1, 0, false, false, false)
    Wait(1000)

    AttachEntityToEntity(cache.ped, closestPed, 11816,
        0.0, -0.45, 0.0,  0.0, 0.0, 0.0,
        false, false, false, false, 20, false)
    TaskPlayAnim(cache.ped, "anim@heists@box_carry@", "idle",
        8.0, -8.0, -1, 1, 0, false, false, false)
    Wait(1250)

    ClearPedTasks(cache.ped)
    DetachEntity(cache.ped, true, false)

    OpenInventory(closestId)
    monitorRobberyDistance(closestId)

    RemoveAnimDict("missminuteman_1ig_2")
    RemoveAnimDict("missbigscore2aig_7@driver")
    RemoveAnimDict("mini@yoga")
    RemoveAnimDict("anim@heists@box_carry@")
end

-- Cleanup on resource stop
AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        ClearPedTasks(cache.ped)
        FreezeEntityPosition(cache.ped, false)
        DetachEntity(cache.ped, true, false)
    end
end)

-- ──────────────────────────────────────────────────────────
-- Escort system
-- ──────────────────────────────────────────────────────────
local playerState     = LocalPlayer.state
local openDoorBlocking = false   -- prevents rapid door-open spam during escort
local isEscortedState  = playerState.isEscorted
local isPedCuffed      = IsPedCuffed
local isAttachedTo     = IsEntityAttachedToEntity

-- local isPedHandcuffedOrArrested(ped) → bool
local function isPedHandcuffedOrArrested(ped)
    return IsEntityPlayingAnim(ped, "mp_arresting", "idle", 3)
        or isPedCuffed(ped)
end

-- StopEscortPlayer(targetServerId, netVehicle, seat)
function StopEscortPlayer(targetServerId, netVehicle, seat)
    TriggerServerEvent("crime:setPlayerEscort", targetServerId, false, netVehicle, seat)
    LocalPlayer.state.blockHandsUp = false
    StopAnimTask(cache.ped, "amb@world_human_drinking@coffee@female@base", "base", 2.0)
end

-- local playEscortAnim() — plays hands-on-shoulders escort idle anim
local function playEscortAnim()
    lib.requestAnimDict("amb@world_human_drinking@coffee@female@base")
    TaskPlayAnim(cache.ped, "amb@world_human_drinking@coffee@female@base", "base",
        8.0, 8.0, -1, 50, 0, false, false, false)
end

-- EscortPlayer() — toggle escort on/off for the nearest cuffed/hands-up player
function EscortPlayer()
    local myCoords = GetEntityCoords(cache.ped)
    local closestId, closestPed = lib.getClosestPlayer(myCoords, 3.0)

    if not (closestId and closestPed) then
        Notification(i18n.t("interaction.no_player_nearby"), "error")
        return
    end

    if not isPedHandcuffedOrArrested(closestPed) then
        Notification(i18n.t("interaction.no_handsup_or_handcuff"), "error")
        return
    end

    local serverId = GetPlayerServerId(closestId)

    if isAttachedTo(closestPed, cache.ped) then
        -- Stop escorting
        StopEscortPlayer(serverId)
    else
        -- Start escorting
        playEscortAnim()
        LocalPlayer.state.blockHandsUp = true
        TriggerServerEvent("crime:setPlayerEscort", serverId, true)
    end
end

-- PutInVehicle() — escort the nearest cuffed player into the closest vehicle seat
function PutInVehicle()
    local myCoords = GetEntityCoords(cache.ped)
    local closestId, closestPed = lib.getClosestPlayer(myCoords, 3.0)

    if not (closestId and closestPed) then
        Notification(i18n.t("interaction.no_player_nearby"), "error")
        return
    end

    if not isPedHandcuffedOrArrested(closestPed) then
        Notification(i18n.t("interaction.no_handsup_or_handcuff"), "error")
        return
    end

    if not isAttachedTo(closestPed, cache.ped) then
        Notification(i18n.t("interaction.no_handsup_or_handcuff"), "error")
        return
    end

    local veh = lib.getClosestVehicle(myCoords, 4.0, true)
    if not (DoesEntityExist(veh) and AreAnyVehicleSeatsFree(veh)) then
        Notification(i18n.t("interaction.no_vehicle_nearby"), "error")
        return
    end

    if GetVehicleDoorLockStatus(veh) == 2 then
        Notification(i18n.t("interaction.vehicle_locked"), "error")
        return
    end

    -- Find the best rear seat
    local boneSides  = { "seat_dside_r", "seat_pside_r" }
    local bestSeat   = nil
    local bestDist   = nil

    for i, boneName in ipairs(boneSides) do
        local boneIdx   = GetEntityBoneIndexByName(veh, boneName)
        local bonePos   = GetEntityBonePosition_2(veh, boneIdx)
        local dist      = #(myCoords - bonePos)
        if (not bestDist or bestDist > dist) and IsVehicleSeatFree(veh, i) then
            bestSeat = i
            bestDist = dist
        end
    end

    -- Fall back to driver-side rear (0) if needed
    if not bestSeat and IsVehicleSeatFree(veh, 0) then
        bestSeat = 0
    end

    if not bestSeat then
        Notification(i18n.t("interaction.no_free_seat"), "error")
        return
    end

    StopEscortPlayer(GetPlayerServerId(closestId), VehToNet(veh), bestSeat)
end

-- OutVehicle() — force a nearby cuffed player out of their vehicle
function OutVehicle()
    local myCoords = GetEntityCoords(cache.ped)
    local closestId, closestPed = lib.getClosestPlayer(myCoords, 5.0)

    if not (closestId and closestPed) then
        Notification(i18n.t("interaction.no_player_nearby"), "error")
        return
    end

    if not IsPedSittingInAnyVehicle(closestPed) then
        Notification(i18n.t("interaction.player_not_in_vehicle"), "error")
        return
    end

    if not isPedHandcuffedOrArrested(closestPed) then
        Notification(i18n.t("interaction.no_handsup_or_handcuff"), "error")
        return
    end

    local serverId = GetPlayerServerId(closestId)
    TriggerServerEvent("crime:setPlayerEscort", serverId, true, false, false, true)
end

-- ──────────────────────────────────────────────────────────
-- Escort attachment / anim thread
-- ──────────────────────────────────────────────────────────

-- Called when isEscorted state bag changes with a valid escort target
local function runEscortThread(escortSourceId)
    CreateThread(function()
        local WALK_DICT = "anim@move_m@prisoner_cuffed"
        local RUN_DICT  = "anim@move_m@trash"

        while isEscortedState do
            local escortPlayerIdx = GetPlayerFromServerId(escortSourceId)
            if not (escortPlayerIdx > 0) then break end
            local escortPed = GetPlayerPed(escortPlayerIdx)
            if not (DoesEntityExist(escortPed) and GetPlayerPed) then break end

            -- Attach if not already
            if not isAttachedTo(cache.ped, escortPed) then
                AttachEntityToEntity(cache.ped, escortPed, 11816,
                    0.38, 0.4, 0.0,  0.0, 0.0, 0.0,
                    false, false, true, true, 2, true)
            end

            -- Match walk/run animation to escort ped
            if IsPedWalking(escortPed) then
                if not IsEntityPlayingAnim(cache.ped, WALK_DICT, "walk", 3) then
                    lib.requestAnimDict(WALK_DICT)
                    TaskPlayAnim(cache.ped, WALK_DICT, "walk",
                        8.0, -8, -1, 1, 0.0, false, false, false)
                end
            elseif IsPedRunning(escortPed) or IsPedSprinting(escortPed) then
                if not IsEntityPlayingAnim(cache.ped, RUN_DICT, "run", 3) then
                    lib.requestAnimDict(RUN_DICT)
                    TaskPlayAnim(cache.ped, RUN_DICT, "run",
                        8.0, -8, -1, 1, 0.0, false, false, false)
                end
            else
                StopAnimTask(cache.ped, WALK_DICT, "walk", -8.0)
                StopAnimTask(cache.ped, RUN_DICT,  "run",  -8.0)
            end

            Wait(0)
        end

        RemoveAnimDict(WALK_DICT)
        RemoveAnimDict(RUN_DICT)
        playerState:set("isEscorted", false, true)
    end)
end

-- CEventOpenDoor — re-apply escort anim after door-open interruption
AddEventHandler("CEventOpenDoor", function()
    if not LocalPlayer.state.blockHandsUp then return end
    if openDoorBlocking then return end

    openDoorBlocking = true
    while IsPedOpeningADoor(cache.ped) do Wait(100) end
    openDoorBlocking = false

    if LocalPlayer.state.blockHandsUp then playEscortAnim() end
end)

-- StateBag change handler for isEscorted
AddStateBagChangeHandler(
    "isEscorted",
    string.format("player:%s", cache.serverId),
    function(_, _, newValue)
        isEscortedState = newValue

        -- Detach if no longer escorted
        if IsEntityAttached(cache.ped) then
            DetachEntity(cache.ped, true, false)
            StopAnimTask(cache.ped, "anim@move_m@prisoner_cuffed", "walk", -8.0)
            StopAnimTask(cache.ped, "anim@move_m@trash", "run", -8.0)
        end

        if newValue then runEscortThread(newValue) end
    end
)

-- Resume escort thread if already escorted when resource starts
if isEscortedState then
    CreateThread(function() runEscortThread(isEscortedState) end)
end

-- ──────────────────────────────────────────────────────────
-- Headbag system
-- ──────────────────────────────────────────────────────────
local headbag = {
    hasBag    = false,
    bagObject = nil,
}

-- PutHeadbagOn() — put a headbag on the nearest player
function PutHeadbagOn()
    local myCoords = GetEntityCoords(cache.ped)
    local closestId, _ = lib.getClosestPlayer(myCoords, 2.0)
    if not closestId then
        Notification(i18n.t("interaction.no_player_nearby"), "error")
        return
    end

    local targetServerId = GetPlayerServerId(closestId)
    local alreadyHasBag  = lib.callback.await("crime:hasHeadbag", false, targetServerId)
    if alreadyHasBag then
        Notification(i18n.t("interaction.headbag.already_has_bag"), "error")
        return
    end

    local ok = ProgressBar({
        duration = math.random(3000, 4000),
        label    = i18n.t("interaction.headbag.putting_on"),
        disable  = { car = true, move = true, combat = true },
        anim     = { dict = "mp_arresting", clip = "a_uncuff" },
        prop     = { model = 289396019, pos = vec3(0.013, 0.03, 0.022),
                     rot = vec3(0.0, 0.0, -1.5) },
    })
    if not ok then return end

    TriggerServerEvent("crime:putHeadbagOn", targetServerId)
    Notification(i18n.t("interaction.headbag.put_on_success"), "success")
end

-- TakeHeadbagOff() — remove headbag from nearest player
function TakeHeadbagOff()
    local myCoords = GetEntityCoords(cache.ped)
    local closestId, _ = lib.getClosestPlayer(myCoords, 2.0)
    if not closestId then
        Notification(i18n.t("interaction.no_player_nearby"), "error")
        return
    end

    local targetServerId = GetPlayerServerId(closestId)
    local hasBag = lib.callback.await("crime:hasHeadbag", false, targetServerId)
    if not hasBag then
        Notification(i18n.t("interaction.headbag.no_bag"), "error")
        return
    end

    local ok = ProgressBar({
        duration = math.random(2000, 3000),
        label    = i18n.t("interaction.headbag.taking_off"),
        disable  = { car = true, move = true, combat = true },
        anim     = { dict = "mp_arresting", clip = "a_uncuff" },
    })
    if not ok then return end

    TriggerServerEvent("crime:takeHeadbagOff", targetServerId)
end

-- NetEvent: "crime:putHeadbagOn" — equip bag visually on local ped
RegisterNetEvent("crime:putHeadbagOn", function()
    if headbag.hasBag then return end
    headbag.hasBag = true

    local ped = cache.ped
    lib.requestModel(289396019)
    local obj = CreateObject(289396019, 0, 0, 0, true, true, true)
    headbag.bagObject = obj

    AttachEntityToEntity(obj, ped,
        GetPedBoneIndex(ped, 12844),
        0.22, 0.04, 0,  0, 270.0, 60.0,
        true, true, false, true, 1, true)

    SendReactMessage("headbag", { visible = true })
end)

-- NetEvent: "crime:takeHeadbagOff" — remove bag from local ped
RegisterNetEvent("crime:takeHeadbagOff", function()
    if not headbag.hasBag then return end
    headbag.hasBag = false

    if headbag.bagObject and DoesEntityExist(headbag.bagObject) then
        DeleteEntity(headbag.bagObject)
        SetEntityAsNoLongerNeeded(headbag.bagObject)
        headbag.bagObject = nil
    end

    SendReactMessage("headbag", { visible = false })
    Notification(i18n.t("interaction.headbag.took_off"), "info")
end)

-- Cleanup headbag on resource stop
AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        if headbag.bagObject and DoesEntityExist(headbag.bagObject) then
            DeleteEntity(headbag.bagObject)
            headbag.bagObject = nil
        end
        headbag.hasBag = false
        SendReactMessage("headbag", { visible = false })
    end
end)

-- Clear headbag on player spawn/respawn
AddEventHandler("playerSpawned", function()
    if headbag.hasBag then
        if headbag.bagObject and DoesEntityExist(headbag.bagObject) then
            DeleteEntity(headbag.bagObject)
            SetEntityAsNoLongerNeeded(headbag.bagObject)
            headbag.bagObject = nil
        end
        headbag.hasBag = false
        SendReactMessage("headbag", { visible = false })
    end
end)
