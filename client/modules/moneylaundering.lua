-- ============================================================
-- client/modules/moneylaundering.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Client-side money laundering module.
-- Manages the NPC, delivery vehicle, blips, markers, and
-- the main delivery loop.
-- ============================================================

_G.moneylaundering = {
    active                = false,
    currentVehicle        = nil,
    currentVehicleNetId   = nil,
    launderingPed         = nil,
    currentLocationIndex  = 1,
    totalLocations        = 0,
    totalLaundered        = 0,
    checkpointBlips       = {},
    returnBlip            = nil,
    isNearPed             = false,
    deliveryThreadActive  = false,
    pedZone               = nil,
}

-- Localised UI label strings (resolved once at load)
local LABEL_START    = i18n.t("money_laundering.start")
local LABEL_STOP     = i18n.t("money_laundering.stop")
local LABEL_DELIVERY = i18n.t("money_laundering.delivery")
local LABEL_RETURN   = i18n.t("money_laundering.return_vehicle")

-- ──────────────────────────────────────────────────────────
-- local createLaunderingPed(model, coords)
-- ──────────────────────────────────────────────────────────
local function createLaunderingPed(model, coords)
    local handle = Utils.CreatePed(model, coords, true)
    if not handle then return nil end

    FreezeEntityPosition(handle, true)
    SetEntityInvincible(handle, true)
    SetBlockingOfNonTemporaryEvents(handle, true)

    local anim = Config.MoneyLaundering.ped.anim
    if anim and anim.dict and anim.name then
        lib.requestAnimDict(anim.dict)
        TaskPlayAnim(handle, anim.dict, anim.name,
            8.0, -8.0, -1, 1, 0, false, false, false)
    end

    return handle
end

-- ──────────────────────────────────────────────────────────
-- local deletePed(handle)
-- ──────────────────────────────────────────────────────────
local function deletePed(handle)
    if handle and DoesEntityExist(handle) then DeletePed(handle) end
end

-- ──────────────────────────────────────────────────────────
-- local spawnVehicle(model, coords) → handle, netId
-- ──────────────────────────────────────────────────────────
local function spawnVehicle(model, coords)
    lib.requestModel(model)
    local handle = CreateVehicle(GetHashKey(model),
        coords.x, coords.y, coords.z, coords.w, true, false)

    if not handle or handle == 0 then return nil, nil end

    SetModelAsNoLongerNeeded(GetHashKey(model))
    SetVehicleOnGroundProperly(handle)
    SetEntityAsMissionEntity(handle, true, true)
    SetVehicleDoorsLocked(handle, 1)
    SetVehicleEngineOn(handle, true, true, false)

    local netId = NetworkGetNetworkIdFromEntity(handle)
    return handle, netId
end

-- ──────────────────────────────────────────────────────────
-- local deleteVehicle(handle)
-- ──────────────────────────────────────────────────────────
local function deleteVehicle(handle)
    if handle and DoesEntityExist(handle) then
        SetEntityAsMissionEntity(handle, false, true)
        DeleteVehicle(handle)
    end
end

-- ──────────────────────────────────────────────────────────
-- local createBlip(coords, sprite, color, scale, label) → blip
-- ──────────────────────────────────────────────────────────
local function createBlip(coords, sprite, color, scale, label)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, sprite)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, scale)
    SetBlipColour(blip, color)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(label)
    EndTextCommandSetBlipName(blip)
    return blip
end

-- ──────────────────────────────────────────────────────────
-- local removeBlip(blip)
-- ──────────────────────────────────────────────────────────
local function removeBlip(blip)
    if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
end

-- ──────────────────────────────────────────────────────────
-- moneylaundering.clearAllBlips(self)
-- ──────────────────────────────────────────────────────────
function moneylaundering.clearAllBlips(self)
    for _, blip in pairs(self.checkpointBlips) do removeBlip(blip) end
    self.checkpointBlips = {}
    if self.returnBlip then
        removeBlip(self.returnBlip)
        self.returnBlip = nil
    end
end

-- ──────────────────────────────────────────────────────────
-- moneylaundering.createCheckpointBlips(self)
--   Creates a blip for every pending delivery location.
-- ──────────────────────────────────────────────────────────
function moneylaundering.createCheckpointBlips(self)
    self:clearAllBlips()

    local blipCfg   = Config.MoneyLaundering.checkpointBlip
    local locations = Config.MoneyLaundering.locations

    for i, loc in ipairs(locations) do
        if i >= self.currentLocationIndex then
            local label = i18n.t("money_laundering.checkpoint",
                { index = i, total = #locations })
                       or ("Delivery " .. i .. "/" .. #locations)

            local blip = createBlip(loc, blipCfg.sprite, blipCfg.color, blipCfg.scale, label)

            if i == self.currentLocationIndex then
                SetBlipRoute(blip, true)
                SetBlipRouteColour(blip, blipCfg.color)
            else
                SetBlipAlpha(blip, 200)
                SetBlipRoute(blip, false)
            end

            self.checkpointBlips[i] = blip
        end
    end
end

-- ──────────────────────────────────────────────────────────
-- moneylaundering.updateCheckpointBlips(self)
--   Removes completed blips, highlights the current one.
-- ──────────────────────────────────────────────────────────
function moneylaundering.updateCheckpointBlips(self)
    for i, blip in pairs(self.checkpointBlips) do
        if DoesBlipExist(blip) then
            if i < self.currentLocationIndex then
                removeBlip(blip)
                self.checkpointBlips[i] = nil
            elseif i == self.currentLocationIndex then
                SetBlipAlpha(blip, 255)
                SetBlipRoute(blip, true)
                SetBlipRouteColour(blip, Config.MoneyLaundering.checkpointBlip.color)
            else
                SetBlipAlpha(blip, 200)
                SetBlipRoute(blip, false)
            end
        end
    end
end

-- ──────────────────────────────────────────────────────────
-- moneylaundering.createReturnBlip(self)
--   Creates a blip at the vehicle spawn / return point.
-- ──────────────────────────────────────────────────────────
function moneylaundering.createReturnBlip(self)
    local returnCoords = Config.MoneyLaundering.ped.vehicle.spawnCoords
    local blipCfg      = Config.MoneyLaundering.returnBlip
    local label        = i18n.t("money_laundering.return_point") or "Return Vehicle"

    local blip = createBlip(
        vec3(returnCoords.x, returnCoords.y, returnCoords.z),
        blipCfg.sprite, blipCfg.color, blipCfg.scale, label)

    self.returnBlip = blip
    SetBlipRoute(blip, true)
    SetBlipRouteColour(blip, blipCfg.color)
end

-- ──────────────────────────────────────────────────────────
-- moneylaundering.updateNUIProgress(self)
-- ──────────────────────────────────────────────────────────
function moneylaundering.updateNUIProgress(self)
    if not self.active then return end
    SendReactMessage("money_laundering_progress", {
        currentLocation = self.currentLocationIndex,
        totalLocations  = self.totalLocations,
        totalLaundered  = self.totalLaundered,
    })
end

-- ──────────────────────────────────────────────────────────
-- moneylaundering.start(self, orgId)
--   Validates preconditions, confirms with the player,
--   charges them, spawns the vehicle, and starts the thread.
-- ──────────────────────────────────────────────────────────
function moneylaundering.start(self, orgId)
    if self.active then
        Notification(i18n.t("money_laundering.already_active") or "Mission already active", "error")
        return
    end

    -- Pre-flight check
    local check = lib.callback.await("crime:moneylaundering:canStart", false, orgId)

    if not check.canStart then
        local msg = i18n.t("money_laundering." .. (check.reason or ""))

        -- Richer error for money/black money shortfalls
        if check.data then
            if check.reason == "not_enough_black_money" then
                msg = i18n.t("money_laundering.not_enough_black_money",
                    { amount = check.data.required })
                   or ("Need $" .. check.data.required .. " black money")
            elseif check.reason == "not_enough_money" then
                msg = i18n.t("money_laundering.not_enough_money",
                    { amount = check.data.required })
                   or ("Need $" .. check.data.required .. " cash")
            end
        end

        Notification(msg or check.reason, "error")
        return
    end

    -- Confirmation dialog
    local confirmMsg = i18n.t("money_laundering.confirm_start", {
        price        = check.data.price,
        vehiclePrice = check.data.vehiclePrice,
        locations    = #check.data.locations,
    }) or string.format([[
Start laundering mission?

Service Fee: $%d
Vehicle Deposit: $%d
Delivery Points: %d

Vehicle deposit is refunded when you return the vehicle.]],
        check.data.price, check.data.vehiclePrice, #check.data.locations)

    local result = lib.alertDialog({
        header  = i18n.t("money_laundering.title") or "Money Laundering",
        content = confirmMsg,
        centered = true,
        cancel  = true,
    })
    if result ~= "confirm" then return end

    -- Progress bar while starting
    ProgressBar({
        duration = Config.MoneyLaundering.progressBarDuration or 5000,
        label    = i18n.t("money_laundering.starting") or "Starting laundering operation...",
        disable  = { move = true, combat = true, mouse = false, look = false },
    })

    local startData = lib.callback.await("crime:moneylaundering:start", false, orgId)

    if not startData.success then
        Notification(i18n.t("money_laundering." .. (startData.message or ""))
            or startData.message, "error")
        return
    end

    -- Spawn the delivery vehicle
    local veh, netId = spawnVehicle(startData.vehicleModel, startData.vehicleSpawnCoords)
    self.currentVehicleNetId = netId
    self.currentVehicle      = veh

    if not veh then
        Notification(i18n.t("money_laundering.vehicle_spawn_failed") or "Failed to spawn vehicle", "error")
        lib.callback.await("crime:moneylaundering:stop", false, orgId, false)
        return
    end

    -- Set up state
    self.active               = true
    self.currentLocationIndex = 1
    self.totalLocations       = #startData.locations
    self.totalLaundered       = 0

    TaskWarpPedIntoVehicle(cache.ped, veh, -1)
    self:createCheckpointBlips()

    SendReactMessage("money_laundering_started", {
        currentLocation = self.currentLocationIndex,
        totalLocations  = self.totalLocations,
        totalLaundered  = self.totalLaundered,
    })

    self:startDeliveryThread(orgId, startData.locations)
    Notification(i18n.t("money_laundering.started") or "Money laundering mission started!", "success")
end

-- ──────────────────────────────────────────────────────────
-- moneylaundering.cleanup(self)
--   Removes vehicle/blips and resets state (does NOT stop server).
-- ──────────────────────────────────────────────────────────
function moneylaundering.cleanup(self)
    self.active              = false
    self.deliveryThreadActive = false

    SendReactMessage("money_laundering_stopped", {})

    if self.currentVehicle and DoesEntityExist(self.currentVehicle) then
        local vehInside = GetVehiclePedIsIn(cache.ped, false)
        if vehInside == self.currentVehicle then
            TaskLeaveVehicle(cache.ped, self.currentVehicle, 0)
            Wait(1500)
        end
        deleteVehicle(self.currentVehicle)
    end

    self.currentVehicle       = nil
    self.currentVehicleNetId  = nil
    self.currentLocationIndex = 1
    self.totalLocations       = 0
    self.totalLaundered       = 0

    self:clearAllBlips()
end

-- ──────────────────────────────────────────────────────────
-- moneylaundering.stop(self, orgId, refundVehicle)
--   Tells the server to stop, shows refund/partial messages,
--   then cleans up locally.
-- ──────────────────────────────────────────────────────────
function moneylaundering.stop(self, orgId, refundVehicle)
    if not self.active then return end

    local result = lib.callback.await("crime:moneylaundering:stop", false, orgId, refundVehicle)

    if result.success then
        if result.refund and result.refund > 0 then
            Notification(
                i18n.t("money_laundering.vehicle_price_refund", { amount = result.refund })
                or ("Vehicle deposit refunded: $" .. result.refund),
                "success")
        end
        if result.totalLaundered and result.totalLaundered > 0 then
            Notification(
                i18n.t("money_laundering.partial_complete", { amount = result.totalLaundered })
                or ("Partial completion: $" .. result.totalLaundered .. " laundered"),
                "info")
        end
    end

    self:cleanup()
end

-- ──────────────────────────────────────────────────────────
-- moneylaundering.startDeliveryThread(self, orgId, locations)
--   Main delivery loop: draws markers, handles E-key
--   deliveries, and the final vehicle return.
-- ──────────────────────────────────────────────────────────
function moneylaundering.startDeliveryThread(self, orgId, locations)
    if self.deliveryThreadActive then return end
    self.deliveryThreadActive = true

    CreateThread(function()
        local deliveryRadius  = Config.MoneyLaundering.deliveryRadius or 3.0
        local pedCoords       = Config.MoneyLaundering.ped.coords
        local returnCoords    = Config.MoneyLaundering.ped.vehicle.spawnCoords

        while self.active do
            local waitMs       = 500
            local playerCoords = GetEntityCoords(cache.ped)
            local inVehicle    = GetVehiclePedIsIn(cache.ped, false)

            if self.currentLocationIndex > self.totalLocations then
                -- === Return phase ===
                local returnVec  = vec3(returnCoords.x, returnCoords.y, returnCoords.z)
                local distReturn = #(playerCoords - returnVec)

                if distReturn <= 50.0 then
                    waitMs = 0
                    DrawMarker(1, returnVec.x, returnVec.y, returnVec.z - 1.0,
                        0,0,0, 0,0,0, 2.5,2.5,1.5,
                        60,165,255,200, false, true, 2, false, nil, nil, false)
                    DrawMarker(2, returnVec.x, returnVec.y, returnVec.z,
                        0,0,0, 0,0,0, 3.5,3.5,0.3,
                        60,165,255,150, false, true, 2, false, nil, nil, false)
                end

                if distReturn <= 5.0 and inVehicle == self.currentVehicle then
                    waitMs = 0
                    DrawText3D(returnVec.x, returnVec.y, returnVec.z + 1.0,
                        LABEL_RETURN, "return_vehicle", "E")

                    if IsControlJustPressed(0, 38) then
                        -- Freeze vehicle while progress bar plays
                        if self.currentVehicle and DoesEntityExist(self.currentVehicle) then
                            FreezeEntityPosition(self.currentVehicle, true)
                        end

                        ProgressBar({
                            duration = 3000,
                            label    = i18n.t("money_laundering.returning") or "Returning vehicle...",
                            disable  = { move = true, combat = true },
                        })

                        if self.currentVehicle and DoesEntityExist(self.currentVehicle) then
                            FreezeEntityPosition(self.currentVehicle, false)
                        end

                        local finishResult = lib.callback.await(
                            "crime:moneylaundering:finish", false, orgId)

                        if finishResult.success then
                            self.totalLaundered = finishResult.totalLaundered or self.totalLaundered

                            Notification(
                                i18n.t("money_laundering.all_complete", {
                                    total = finishResult.totalLaundered,
                                    xp    = finishResult.bonusXP,
                                }) or string.format(
                                    "Mission complete! Total: $%d, Bonus XP: %d",
                                    finishResult.totalLaundered, finishResult.bonusXP),
                                "success")
                        end

                        self:cleanup()
                        break
                    end
                end

            else
                -- === Delivery phase ===
                local loc     = locations[self.currentLocationIndex]
                local distLoc = #(playerCoords - loc)

                if distLoc <= 50.0 then
                    waitMs = 0
                    DrawMarker(1, loc.x, loc.y, loc.z - 1.0,
                        0,0,0, 0,0,0, 2.0,2.0,1.5,
                        34,197,94,200, false, true, 2, false, nil, nil, false)
                    DrawMarker(2, loc.x, loc.y, loc.z,
                        0,0,0, 0,0,0, 3.0,3.0,0.3,
                        34,197,94,150, false, true, 2, false, nil, nil, false)
                end

                if distLoc <= deliveryRadius then
                    waitMs = 0

                    if inVehicle == self.currentVehicle then
                        DrawText3D(loc.x, loc.y, loc.z + 1.0,
                            LABEL_DELIVERY, "delivery_" .. self.currentLocationIndex, "E")

                        if IsControlJustPressed(0, 38) then
                            if self.currentVehicle and DoesEntityExist(self.currentVehicle) then
                                FreezeEntityPosition(self.currentVehicle, true)
                            end

                            ProgressBar({
                                duration = 3000,
                                label    = i18n.t("money_laundering.delivering") or "Making delivery...",
                                disable  = { move = true, combat = true },
                            })

                            if self.currentVehicle and DoesEntityExist(self.currentVehicle) then
                                FreezeEntityPosition(self.currentVehicle, false)
                            end

                            local deliveryResult = lib.callback.await(
                                "crime:moneylaundering:delivery", false,
                                orgId, self.currentLocationIndex)

                            if deliveryResult.success then
                                Notification(
                                    i18n.t("money_laundering.delivery_complete", {
                                        index  = self.currentLocationIndex,
                                        total  = self.totalLocations,
                                        amount = deliveryResult.cleanMoney,
                                        xp     = deliveryResult.xpEarned,
                                    }) or string.format(
                                        "Delivery %d/%d complete! +$%d clean, +%d XP",
                                        self.currentLocationIndex, self.totalLocations,
                                        deliveryResult.cleanMoney, deliveryResult.xpEarned),
                                    "success")

                                self.totalLaundered       = self.totalLaundered + (deliveryResult.cleanMoney or 0)
                                self.currentLocationIndex = self.currentLocationIndex + 1

                                self:updateCheckpointBlips()
                                self:updateNUIProgress()

                                if self.currentLocationIndex > self.totalLocations then
                                    self:clearAllBlips()
                                    self:createReturnBlip()
                                    Notification(
                                        i18n.t("money_laundering.return_vehicle_prompt")
                                        or "All deliveries complete! Return the vehicle.",
                                        "info")
                                end
                            else
                                Notification(
                                    i18n.t("money_laundering." .. (deliveryResult.message or ""))
                                    or deliveryResult.message,
                                    "error")
                            end
                        end
                    else
                        -- Player is not in the mission vehicle
                        DrawText3D(loc.x, loc.y, loc.z + 1.0,
                            i18n.t("money_laundering.need_vehicle") or "Return to your vehicle",
                            "need_vehicle", nil)
                    end
                end
            end

            Wait(waitMs)
        end

        self.deliveryThreadActive = false
    end)
end

-- ──────────────────────────────────────────────────────────
-- moneylaundering.createPedZone(self)
--   Creates a sphere zone around the NPC. On enter: spawn ped.
--   On exit: despawn ped if mission is not active.
-- ──────────────────────────────────────────────────────────
function moneylaundering.createPedZone(self)
    if self.pedZone then return end

    local pedCoords = Config.MoneyLaundering.ped.coords
    local radius    = Config.MoneyLaundering.sphereRadius or 15.0

    self.pedZone = lib.zones.sphere({
        coords  = vec3(pedCoords.x, pedCoords.y, pedCoords.z),
        radius  = radius,
        debug   = Config.ZoneDebug,

        onEnter = function()
            self.isNearPed = true
            if not self.launderingPed then
                self.launderingPed = createLaunderingPed(
                    Config.MoneyLaundering.ped.model, pedCoords)
            end
        end,

        onExit = function()
            self.isNearPed = false
            if self.launderingPed and not self.active then
                deletePed(self.launderingPed)
                self.launderingPed = nil
            end
        end,
    })
end

-- ──────────────────────────────────────────────────────────
-- moneylaundering.destroy(self)
-- ──────────────────────────────────────────────────────────
function moneylaundering.destroy(self)
    self:cleanup()
    if self.pedZone then
        self.pedZone:remove()
        self.pedZone = nil
    end
    if self.launderingPed then
        deletePed(self.launderingPed)
        self.launderingPed = nil
    end
end

-- ──────────────────────────────────────────────────────────
-- Main zone / interaction thread
-- ──────────────────────────────────────────────────────────
CreateThread(function()
    moneylaundering:createPedZone()

    while true do
        local waitMs = 500

        if moneylaundering.isNearPed and moneylaundering.launderingPed then
            local pedLoc    = Config.MoneyLaundering.ped.coords
            local playerPos = GetEntityCoords(cache.ped)
            local dist      = #(playerPos - pedLoc.xyz)

            if dist <= 2.5 then
                waitMs     = 0
                local orgId = LocalPlayer.state.organization

                if orgId then
                    if moneylaundering.active then
                        -- Show stop option
                        DrawText3D(pedLoc.x, pedLoc.y, pedLoc.z + 1.0,
                            LABEL_STOP, "stop_mission", "E")

                        if IsControlJustPressed(0, 38) then
                            local inVehicle = GetVehiclePedIsIn(cache.ped, false)
                            local isInMissionVehicle = (inVehicle == moneylaundering.currentVehicle)

                            -- Stop confirmation
                            local stopMsg
                            if isInMissionVehicle then
                                stopMsg = i18n.t("money_laundering.stop_confirm_refund")
                                       or "You will receive your vehicle deposit back."
                            else
                                stopMsg = i18n.t("money_laundering.stop_confirm_no_refund")
                                       or "WARNING: You are not in the mission vehicle. You will NOT receive your deposit back."
                            end

                            local confirm = lib.alertDialog({
                                header   = i18n.t("money_laundering.stop_confirm_title") or "Stop Mission?",
                                content  = stopMsg,
                                centered = true,
                                cancel   = true,
                            })

                            if confirm == "confirm" then
                                moneylaundering:stop(orgId, isInMissionVehicle)
                            end
                        end
                    else
                        -- Show start option
                        DrawText3D(pedLoc.x, pedLoc.y, pedLoc.z + 1.0,
                            LABEL_START, "start_mission", "E")

                        if IsControlJustPressed(0, 38) then
                            moneylaundering:start(orgId)
                        end
                    end
                else
                    DrawText3D(pedLoc.x, pedLoc.y, pedLoc.z + 1.0,
                        i18n.t("money_laundering.need_organization") or "You need to be in an organization",
                        "no_org", nil)
                end
            end
        end

        Wait(waitMs)
    end
end)

-- ──────────────────────────────────────────────────────────
-- Cleanup on resource stop
-- ──────────────────────────────────────────────────────────
AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        moneylaundering:destroy()
    end
end)

-- ──────────────────────────────────────────────────────────
-- Exports
-- ──────────────────────────────────────────────────────────
exports("isMoneyLaunderingActive", function()
    return moneylaundering.active
end)

exports("getMoneyLaunderingVehicle", function()
    return moneylaundering.currentVehicle
end)

Debug("Money Laundering client module loaded")
