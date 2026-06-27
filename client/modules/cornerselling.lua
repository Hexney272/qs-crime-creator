-- ============================================================
-- client/modules/cornerselling.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Client-side corner-selling module.
-- Handles drug selling to ambient peds, robbery interactions,
-- territory ownership checks, and police-call chance.
-- ============================================================

_G.cornerselling = {
    hasTarget      = false,
    active         = false,
    lastPed        = {},
    stealData      = {},
    availableDrugs = {},
}

-- ──────────────────────────────────────────────────────────
-- cornerselling.tooFarAway(self)
--   Resets the session when the player moves too far.
-- ──────────────────────────────────────────────────────────
function cornerselling.tooFarAway(self)
    Notification(i18n.t("cornerselling.too_far_away"), "error")
    self.active         = false
    self.hasTarget      = false
    self.availableDrugs = {}
end

-- ──────────────────────────────────────────────────────────
-- cornerselling.policeCall(self)
--   Random chance to trigger a police dispatch alert.
-- ──────────────────────────────────────────────────────────
function cornerselling.policeCall(self)
    if not PoliceDispatch then return end
    if math.random(1, 100) <= Config.PoliceCallChance then
        PoliceDispatch(i18n.t("cornerselling.police_call"))
    end
end

-- ──────────────────────────────────────────────────────────
-- cornerselling.robberyPed(self)
--   Starts a thread watching a ped that stole drugs.
--   When the ped dies near the player, show a pickup prompt.
-- ──────────────────────────────────────────────────────────
function cornerselling.robberyPed(self)
    CreateThread(function()
        while true do
            if not self.stealingPed then break end

            if IsEntityDead(self.stealingPed) then
                local playerPos = GetEntityCoords(cache.ped)
                local pedPos    = GetEntityCoords(self.stealingPed)
                local dist      = #(playerPos - pedPos)

                if dist < 1.5 then
                    DrawText3D(pedPos.x, pedPos.y, pedPos.z,
                        i18n.t("drawtext.cornerselling"), "pickup", "E")

                    if IsControlJustReleased(0, 38) then
                        -- Load pickup anim
                        RequestAnimDict("pickup_object")
                        while not HasAnimDictLoaded("pickup_object") do Wait(0) end

                        TaskPlayAnim(cache.ped, "pickup_object", "pickup_low",
                            8.0, -8.0, -1, 1, 0, false, false, false)
                        Wait(2000)
                        ClearPedTasks(cache.ped)

                        TriggerServerEvent("crime:giveStealItems",
                            self.stealData.item, self.stealData.amount)
                        self.stealingPed = nil
                        self.stealData   = {}
                    end
                else
                    -- Ped ran too far — give up
                    local runDist = #(playerPos - pedPos)
                    if runDist > 100 then
                        self.stealingPed = nil
                        self.stealData   = {}
                        break
                    end
                end
            end

            Wait(0)
        end
    end)
end

-- ──────────────────────────────────────────────────────────
-- cornerselling.sellToPed(self, ped)
--   Approaches a nearby ped and handles the sell/rob outcome.
-- ──────────────────────────────────────────────────────────
function cornerselling.sellToPed(self, ped)
    self.hasTarget = true

    -- Don't reuse the same ped
    for i = 1, #self.lastPed do
        if self.lastPed[i] == ped then
            self.hasTarget = false
            return
        end
    end

    -- Roll three independent chances
    local rollSuccess  = math.random(1, 100)
    local rollScam     = math.random(1, 100)
    local rollRobbery  = math.random(1, 100)

    -- Chance the ped simply walks away
    if rollSuccess <= Config.SuccessChance then
        self.hasTarget = false
        return
    end

    -- Pick a random drug type and amount
    local drugIndex   = math.random(1, #self.availableDrugs)
    local drugAmount  = math.random(1, self.availableDrugs[drugIndex].amount)
    if drugAmount > 15 then drugAmount = math.random(9, 15) end

    self.currentOfferDrug = self.availableDrugs[drugIndex]

    local priceRange = Config.DrugsPrice[self.currentOfferDrug.item]
    local price      = math.random(priceRange.min, priceRange.max) * drugAmount

    -- Scam chance — ped offers very low price
    if rollScam <= Config.ScamChance then
        price = math.random(1, 5) * drugAmount
    end

    -- Move the ped toward the player
    SetEntityAsNoLongerNeeded(ped)
    ClearPedTasks(ped)

    local playerCoords = GetEntityCoords(cache.ped, true)
    local pedCoords    = GetEntityCoords(ped)
    local dist         = #(playerCoords - pedCoords)

    local moveSpeed = (rollRobbery <= Config.RobberyChance) and 15.0 or 1.2

    TaskGoStraightToCoord(ped, playerCoords.x, playerCoords.y, playerCoords.z,
        moveSpeed, -1, 0.0, 0.0)

    -- Wait until ped is close
    while dist > 1.5 do
        playerCoords = GetEntityCoords(cache.ped, true)
        pedCoords    = GetEntityCoords(ped)
        TaskGoStraightToCoord(ped, playerCoords.x, playerCoords.y, playerCoords.z,
            1.2, -1, 0.0, 0.0)
        dist = #(playerCoords - pedCoords)
        Wait(100)
    end

    -- Face each other
    TaskLookAtEntity(ped, cache.ped, 5500.0, 2048, 3)
    TaskTurnPedToFaceEntity(ped, cache.ped, 5500)
    TaskStartScenarioInPlace(ped, "WORLD_HUMAN_STAND_IMPATIENT_UPRIGHT", 0, false)

    if not self.hasTarget then
        Debug("No target", "cornerselling")
        return
    end

    -- Interaction loop
    while dist < 1.5 do
        if IsPedDeadOrDying(ped, false) then break end

        playerCoords = GetEntityCoords(cache.ped, true)
        pedCoords    = GetEntityCoords(ped)
        local curDist = #(playerCoords - pedCoords)

        -- Robbery branch
        if rollRobbery <= Config.RobberyChance then
            TriggerServerEvent("crime:robCornerDrugs", drugIndex, drugAmount)
            Notification(i18n.t("cornerselling.robbed", {
                amount = drugAmount,
                item   = self.availableDrugs[drugIndex].label,
            }), "error")

            self.stealingPed    = ped
            self.stealData      = {
                item     = self.availableDrugs[drugIndex].item,
                drugType = drugIndex,
                amount   = drugAmount,
            }
            self.hasTarget      = false
            self.active         = false
            self.availableDrugs = {}

            -- Send ped fleeing
            local fleeDest = GetEntityCoords(cache.ped)
            ClearPedTasksImmediately(ped)
            TaskGoStraightToCoord(ped, fleeDest.x + math.random(100, 500),
                fleeDest.y + math.random(100, 500), fleeDest.z, 15.0, -1, 0.0, 0.0)

            self.lastPed[#self.lastPed + 1] = ped
            self:robberyPed()
            break

        elseif curDist < 1.5 then
            -- Regular sell prompt
            DrawText3D(pedCoords.x, pedCoords.y, pedCoords.z,
                i18n.t("drawtext.deliver_offer", {
                    amount = drugAmount,
                    item   = self.currentOfferDrug.label,
                    price  = price,
                }), "cornerSelling", "E")

            -- E — accept deal
            if IsControlJustPressed(0, 38) then
                if IsPedInAnyVehicle(cache.ped, false) then
                    Notification(i18n.t("cornerselling.in_vehicle"), "error")
                    self.hasTarget = false
                    SetPedKeepTask(ped, false)
                    SetEntityAsNoLongerNeeded(ped)
                    ClearPedTasksImmediately(ped)
                    self.lastPed[#self.lastPed + 1] = ped
                    break
                else
                    -- Sell
                    ProgressBar({ duration = 5000, label = i18n.t("cornerselling.selling_to_ped"),
                        disable = { move = true, combat = true, mouse = true, look = true } })

                    local currentTerritory = TerritoryManager:getCurrent()
                    local territoryId = currentTerritory and currentTerritory.id or nil

                    TriggerServerEvent("crime:sellCornerDrugs", drugIndex, drugAmount, price, territoryId)
                    self.hasTarget = false

                    lib.playAnim(cache.ped, "gestures@f@standing@casual", "gesture_point")
                    self.active = false
                    Wait(650)
                    ClearPedTasks(cache.ped)
                    SetPedKeepTask(ped, false)
                    SetEntityAsNoLongerNeeded(ped)
                    RemoveAnimDict("gestures@f@standing@casual")
                    ClearPedTasksImmediately(ped)
                    self:policeCall()
                    self.lastPed[#self.lastPed + 1] = ped
                    Wait(5000)
                    self.active = true
                end
            end

            -- G — decline
            if IsControlJustPressed(0, 47) then
                Notification(i18n.t("cornerselling.offer_declined"), "error")
                self.hasTarget = false
                SetPedKeepTask(ped, false)
                SetEntityAsNoLongerNeeded(ped)
                ClearPedTasksImmediately(ped)
                self.lastPed[#self.lastPed + 1] = ped
                break
            end
        else
            -- Ped walked away
            self.hasTarget = false
            SetPedKeepTask(ped, false)
            SetEntityAsNoLongerNeeded(ped)
            ClearPedTasksImmediately(ped)
            cornerselling.lastPed[#cornerselling.lastPed + 1] = ped
            break
        end

        Wait(0)
    end

    Wait(math.random(4000, 7000))
end

-- ──────────────────────────────────────────────────────────
-- cornerselling.toggleSelling(self)
--   Starts or stops the corner-selling session.
-- ──────────────────────────────────────────────────────────
function cornerselling.toggleSelling(self)
    if not self.active then
        self.active = true
        Notification(i18n.t("cornerselling.started_selling"), "info")

        local startPos = GetEntityCoords(cache.ped)

        CreateThread(function()
            while self.active do
                local playerCoords = GetEntityCoords(cache.ped)

                if not self.hasTarget then
                    local nearPed = lib.getClosestPed(playerCoords)
                    if nearPed and not IsPedInAnyVehicle(nearPed, false) then
                        self:sellToPed(nearPed)
                    end
                end

                if #(startPos - playerCoords) > 10 then
                    self:tooFarAway()
                end

                Wait(100)
            end
        end)
    else
        self.stealingPed = nil
        self.stealData   = {}
        self.active      = false
        Notification(i18n.t("cornerselling.stopped_selling"), "info")
    end
end

-- ──────────────────────────────────────────────────────────
-- cornerselling.destroy(self)
-- ──────────────────────────────────────────────────────────
function cornerselling.destroy(self)
    self.stealingPed = nil
    self.stealData   = {}
    self.active      = false
end

-- ──────────────────────────────────────────────────────────
-- local canAccessTerritory(territory)
--   Returns (ok, errorMsg). True if player's org owns the
--   territory or is a participant in an active territory war.
-- ──────────────────────────────────────────────────────────
local function canAccessTerritory(territory)
    local orgId = LocalPlayer.state.organization
    if not orgId then
        return false, i18n.t("cornerselling.not_in_organization")
    end

    local orgTerritory = territory:getOrganizationID()
    if orgTerritory == orgId then
        return true, nil
    end

    -- Check if there is an active war for this territory
    local war = lib.callback.await("crime:getActiveTerritoryWar", false, territory.id)
    if war and war.status == "active" then
        local scores = lib.callback.await("crime:getTerritoryWarScores", false, war.id)
        if scores then
            for _, s in ipairs(scores) do
                if s.organization_id == orgId then return true, nil end
            end
        end
        if war.started_by_org_id == orgId then return true, nil end
        return false, i18n.t("cornerselling.not_participating_in_war")
    end

    return false, i18n.t("cornerselling.not_your_territory")
end

-- ──────────────────────────────────────────────────────────
-- cornerselling.start(self)
--   Entry point: validates territory, police, drugs, then begins.
-- ──────────────────────────────────────────────────────────
function cornerselling.start(self)
    local drugs = lib.callback.await("crime:getAvailableDrugs", false)

    local territory = TerritoryManager:getCurrent()
    if not territory then
        self:destroy()
        return Notification(i18n.t("cornerselling.no_territory"), "error")
    end

    local canAccess, errMsg = canAccessTerritory(territory)
    if not canAccess then
        self:destroy()
        return Notification(errMsg or i18n.t("cornerselling.not_your_territory"), "error")
    end

    local policeCount = lib.callback.await("crime:getPoliceCount", false)
    if policeCount >= Config.RequiredCops then
        if IsPedInAnyVehicle(cache.ped, false) then
            Notification(i18n.t("cornerselling.in_vehicle"), "error")
        elseif drugs and #drugs > 0 then
            self.availableDrugs = drugs
            self:toggleSelling()
        else
            Notification(i18n.t("cornerselling.no_drugs"), "error")
        end
    else
        Notification(i18n.t("cornerselling.not_enough_police", {
            count = Config.RequiredCops,
        }), "error")
    end
end

-- ──────────────────────────────────────────────────────────
-- NetEvent triggers
-- ──────────────────────────────────────────────────────────

RegisterNetEvent("crime:cornerselling", function()
    cornerselling:start()
end)

RegisterNetEvent("crime:refreshAvailableDrugs", function(newDrugs)
    cornerselling.availableDrugs = newDrugs
    if not cornerselling.availableDrugs or #cornerselling.availableDrugs <= 0 then
        Notification(i18n.t("cornerselling.no_drugs_left"), "error")
        cornerselling:destroy()
    end
end)
