-- ── Perf: build model lookup sets once at module load ───────────────────────
-- lightModelSet: hash set of light model names → O(1) lookup in GetLightsData
-- cameraModels:  hash map of camera model name → label → O(1) lookup in GetCamerasData
-- Both are derived from Config.Furniture which never changes at runtime.
local lightModelSet = {}
local cameraModels  = {}

CreateThread(function()
    -- Wait one frame so Config.Furniture and LIGHT_ITEMS are guaranteed loaded
    Wait(0)

    -- Build light model hash set from LIGHT_ITEMS (replaces table.find O(n) per object)
    if LIGHT_ITEMS then
        for _, item in pairs(LIGHT_ITEMS) do
            if item.object then
                lightModelSet[item.object] = true
            end
        end
    end

    -- Build camera model hash map from Config.Furniture.camera
    local camCategory = Config.Furniture and Config.Furniture.camera
    if camCategory and camCategory.items then
        for _, item in pairs(camCategory.items) do
            if item.object then
                cameraModels[item.object] = item.label or "Security Camera"
            end
            if item.colors then
                for _, variant in pairs(item.colors) do
                    if variant.object then
                        cameraModels[variant.object] = variant.label or item.label or "Security Camera"
                    end
                end
            end
        end
    end
end)
-- ─────────────────────────────────────────────────────────────────────────────

function GetLightsData()
    local lights = {}
    if not (decorate and decorate.objects) then return lights end

    for objectId, objectData in pairs(decorate.objects) do
        -- O(1) hash lookup replaces O(n) table.find() across LIGHT_ITEMS
        if lightModelSet[objectData.modelName] then
            local lightData = objectData.lightData

            local isActive = true
            if lightData and lightData.active ~= nil then
                isActive = lightData.active
            end

            table.insert(lights, {
                id        = objectId,
                name      = (lightData and lightData.name) or i18n.t("management.light_name", { id = objectId }),
                color     = (lightData and lightData.color) or "white",
                intensity = (lightData and lightData.intensity) or Config.DefaultLightIntensity,
                active    = isActive,
            })
        end
    end

    return lights
end

-- GetCamerasData()
--   cameraModels is now built once at module load (above) instead of on every call.
function GetCamerasData()
    local cameras = {}
    if not (decorate and decorate.objects) then return cameras end

    for objectId, objectData in pairs(decorate.objects) do
        -- O(1) hash lookup — cameraModels built once at load, not rebuilt here
        local cameraLabel = cameraModels[objectData.modelName]
        if cameraLabel then
            table.insert(cameras, {
                id    = objectId,
                name  = i18n.t("management.camera_name", { id = objectId }) or (cameraLabel .. " " .. objectId),
                model = objectData.modelName,
            })
        end
    end

    return cameras
end

-- ⚠️ Defined but never referenced in this file. Possibly dead code.
local locationActionMap = {
    wardrobe = "setoutfit",
    stash = "setstash",
    charge = "setCharge",
}

local setLocationDrawText = i18n.t("drawtext.set_location")

function SetLocation(locationType)
    CreateThread(function()
        local orgId = OrganizationManager:getCurrentOrganization()
        if not orgId then
            Notification(i18n.t("bossmenu.organization_not_found"), "error")
            return
        end

        while true do
            if not OrganizationManager:getCurrentOrganization() then
                break
            end

            Wait(0)

            local playerCoords = GetEntityCoords(cache.ped)
            local playerHeading = GetEntityHeading(cache.ped)

            DrawGenericText(setLocationDrawText)

            if IsControlJustPressed(0, 47) then
                local coords = {
                    x = playerCoords.x,
                    y = playerCoords.y,
                    z = playerCoords.z,
                    w = playerHeading,
                }

                local result = lib.callback.await("crime:setOrganizationLocation", false, orgId, locationType, coords)

                if result and result.success then
                    Notification(i18n.t("management.location_set", { type = locationType }), "success")
                else
                    Notification((result and result.message) or i18n.t("management.location_set_failed"), "error")
                end
                break
            end
        end
    end)
end

-- ============================================================
-- Members
-- ============================================================

RegisterNUICallback("bossmenu_get_members", function(data, cb)
    local members = lib.callback.await("crime:getOrganizationMembers", false)
    cb(members or false)
end)

RegisterNUICallback("bossmenu_update_member", function(data, cb)
    if not data or not data.organizationId or not data.memberId then
        return cb(false)
    end
    local result = lib.callback.await("crime:updateOrganizationMember", false, data.organizationId, data.memberId, data.rankId)
    cb(result)
end)

RegisterNUICallback("bossmenu_remove_member", function(data, cb)
    if not data or not data.organizationId or not data.memberId then
        return cb(false)
    end
    local result = lib.callback.await("crime:removeOrganizationMember", false, data.organizationId, data.memberId)
    cb(result)
end)

RegisterNUICallback("bossmenu_add_member", function(data, cb)
    if not data or not data.organizationId or not data.targetSource or not data.name then
        return cb({ success = false, message = "invalid_data" })
    end

    local success, message = lib.callback.await("crime:addOrganizationMember", false, data.organizationId, data.targetSource, data.name, data.rankId)

    local result = { success = (success == true) }
    if type(message) == "string" then
        result.message = message
    end
    cb(result)
end)

RegisterNUICallback("bossmenu_get_member_details", function(data, cb)
    if not data or not data.organizationId or not data.identifier then
        return cb(nil)
    end
    local details = lib.callback.await("crime:getMemberDetails", false, data.organizationId, data.identifier)
    cb(details or nil)
end)

RegisterNUICallback("get_closest_players", function(data, cb)
    local players = lib.callback.await("crime:getClosestPlayers", false)
    cb(players)
end)

-- ============================================================
-- Ranks
-- ============================================================

RegisterNUICallback("bossmenu_get_ranks", function(data, cb)
    if not data or not data.organizationId then
        return cb({})
    end
    local ranks = lib.callback.await("crime:getOrganizationRanks", false, data.organizationId)
    cb(ranks or {})
end)

RegisterNUICallback("bossmenu_add_rank", function(data, cb)
    if not data or not data.organizationId or not data.label then
        return cb(false)
    end
    local result = lib.callback.await("crime:addOrganizationRank", false, data.organizationId, data.label, data.permissions)
    cb(result)
end)

RegisterNUICallback("bossmenu_update_rank", function(data, cb)
    if not data or not data.rankId then
        return cb(false)
    end
    local result = lib.callback.await("crime:updateOrganizationRank", false, data.rankId, data.label, data.permissions)
    cb(result)
end)

RegisterNUICallback("bossmenu_remove_rank", function(data, cb)
    if not data or not data.rankId then
        return cb(false)
    end
    local result = lib.callback.await("crime:removeOrganizationRank", false, data.rankId)
    cb(result)
end)

-- ============================================================
-- Finance
-- ============================================================

RegisterNUICallback("get_financial_overview", function(data, cb)
    local orgId = (data and data.organizationId) or bossmenu.organizationId
    if not orgId then
        return cb({})
    end
    local overview = lib.callback.await("crime:getOrganizationFinanceOverview", false, orgId)
    cb(overview or {})
end)

RegisterNUICallback("get_transactions", function(data, cb)
    if not data or not data.organizationId then
        return cb({})
    end
    local transactions = lib.callback.await("crime:getOrganizationTransactions", false, data.organizationId, data.limit, data.offset)
    cb(transactions or {})
end)

RegisterNUICallback("get_finance_analytics", function(data, cb)
    if not data or not data.organizationId then
        return cb({})
    end
    local analytics = lib.callback.await("crime:getOrganizationFinanceAnalytics", false, data.organizationId)
    cb(analytics or {})
end)

RegisterNUICallback("bossmenu_deposit_money", function(data, cb)
    if not data or not data.organizationId or not data.amount then
        return cb(false)
    end
    local result = lib.callback.await("crime:depositOrganizationMoney", false, data.organizationId, data.amount, data.type)
    cb(result)
end)

RegisterNUICallback("bossmenu_withdraw_money", function(data, cb)
    if not data or not data.organizationId or not data.amount then
        return cb(false)
    end
    local result = lib.callback.await("crime:withdrawOrganizationMoney", false, data.organizationId, data.amount, data.type)
    cb(result)
end)

RegisterNUICallback("deposit_money", function(data, cb)
    if not data or not data.organizationId or not data.amount or not data.method or not data.description then
        return cb({ success = false, message = "Missing required fields" })
    end

    local result = lib.callback.await("crime:depositOrganizationMoney", false,
        data.organizationId, data.amount, data.method, data.description, data.reference)

    if result and result.success then
        bossmenu:refreshFinance()
    end

    cb(result or { success = false, message = "Deposit failed" })
end)

RegisterNUICallback("withdraw_money", function(data, cb)
    if not data or not data.organizationId or not data.amount or not data.method or not data.description then
        return cb({ success = false, message = "Missing required fields" })
    end

    local result = lib.callback.await("crime:withdrawOrganizationMoney", false,
        data.organizationId, data.amount, data.method, data.description, data.reference)

    if result and result.success then
        bossmenu:refreshFinance()
    end

    cb(result or { success = false, message = "Withdrawal failed" })
end)

-- ============================================================
-- Vehicles & Garage
-- ============================================================

RegisterNUICallback("bossmenu_get_vehicles", function(data, cb)
    if not data or not data.organizationId then
        return cb({})
    end
    local vehicles = lib.callback.await("crime:getOrganizationVehicles", false, data.organizationId)
    cb(vehicles or {})
end)

RegisterNUICallback("bossmenu_spawn_vehicle", function(data, cb)
    if not data or not data.organizationId or not data.vehicleId then
        return cb(false)
    end
    local result = lib.callback.await("crime:spawnOrganizationVehicle", false, data.organizationId, data.vehicleId)
    cb(result)
end)

RegisterNUICallback("bossmenu_retrieve_impound", function(data, cb)
    if not data or not data.organizationId or not data.vehicleId then
        return cb(false)
    end
    local result = lib.callback.await("crime:retrieveVehicleFromImpound", false, data.organizationId, data.vehicleId)
    cb(result)
end)

RegisterNUICallback("bossmenu_get_garage_slots", function(data, cb)
    if not data or not data.organizationId then
        return cb(1)
    end
    local slotCount = lib.callback.await("crime:getOrganizationGarageSlotCount", false, data.organizationId)
    cb(slotCount or 1)
end)

RegisterNUICallback("bossmenu_get_garage_activities", function(data, cb)
    if not data or not data.organizationId then
        return cb({})
    end
    local activities = lib.callback.await("crime:getVehicleActivities", false, data.organizationId)
    cb(activities or {})
end)

RegisterNUICallback("bossmenu_get_vehicle_sell_price", function(data, cb)
    if not data or not data.organizationId or not data.vehicleId then
        return cb(nil)
    end
    local price = lib.callback.await("crime:getVehicleSellPrice", false, data.organizationId, data.vehicleId)
    cb(price)
end)

RegisterNUICallback("bossmenu_sell_vehicle", function(data, cb)
    if not data or not data.organizationId or not data.vehicleId then
        return cb(false)
    end
    local result = lib.callback.await("crime:sellOrganizationVehicle", false, data.organizationId, data.vehicleId)
    cb(result)
end)

RegisterNUICallback("get_vehicle_store", function(data, cb)
    local orgId = (data and data.organizationId) or bossmenu.organizationId
    if not orgId then
        return cb({})
    end
    local store = lib.callback.await("crime:getVehicleStore", false, orgId)
    cb(store or {})
end)

RegisterNUICallback("purchase_vehicle", function(data, cb)
    if not data or not data.organizationId or not data.vehicleId then
        return cb(false)
    end

    local vehicleColors = nil
    local currentVehicle = GetVehiclePedIsIn(cache.ped, false)

    if currentVehicle ~= 0 then
        local vehicleProps = lib.getVehicleProperties(currentVehicle)
        if vehicleProps then
            vehicleColors = {
                color1 = vehicleProps.color1,
                color2 = vehicleProps.color2,
                pearlescentColor = vehicleProps.pearlescentColor,
            }
        end
    end

    local result = lib.callback.await("crime:purchaseVehicle", false, data.organizationId, data.vehicleId, vehicleColors)
    cb(result)
end)

-- ============================================================
-- Season Pass
-- ============================================================

RegisterNUICallback("get_season_pass", function(data, cb)
    local seasonPass = lib.callback.await("crime:getSeasonPass", false)
    cb(seasonPass or nil)
end)

RegisterNUICallback("bossmenu_claim_reward", function(data, cb)
    if not data or not data.organizationId or not data.level or not data.tier then
        return cb(false)
    end
    local result = lib.callback.await("crime:claimSeasonPassReward", false, data.organizationId, data.level, data.tier)
    cb(result)
end)

RegisterNUICallback("bossmenu_purchase_premium", function(data, cb)
    if not data or not data.organizationId then
        return cb(false)
    end
    local result = lib.callback.await("crime:purchaseSeasonPassPremium", false, data.organizationId)
    cb(result)
end)

RegisterNUICallback("bossmenu_get_organization_seasonpass_data", function(data, cb)
    if not data or not data.organizationId then
        return cb(nil)
    end
    local seasonPassData = lib.callback.await("crime:getOrganizationSeasonPassData", false, data.organizationId)
    cb(seasonPassData or nil)
end)

-- ============================================================
-- Management & Upgrades
-- ============================================================

RegisterNUICallback("bossmenu_get_management", function(data, cb)
    local defaultManagement = { lights = {}, cameras = {}, upgrades = {} }

    if not bossmenu.organizationId then
        return cb(defaultManagement)
    end

    local management = lib.callback.await("crime:getOrganizationManagement", false, bossmenu.organizationId)
    management = management or defaultManagement

    -- Populate lights from client-side decorate objects (server cannot know these)
    management.lights   = GetLightsData()
    -- Populate cameras from client-side decorate objects (server cannot know these)
    management.cameras  = GetCamerasData()

    cb(management)
end)

RegisterNUICallback("buy-upgrade", function(data, cb)
    if not data or not data.upgrade then
        return cb(false)
    end

    if not bossmenu.organizationId then
        Notification(i18n.t("bossmenu.organization_not_found"), "error")
        return cb(false)
    end

    local result = lib.callback.await("crime:buyOrganizationUpgrade", false, bossmenu.organizationId, data.upgrade)

    if result and result.success then
        Notification(result.message or i18n.t("management.upgrade_purchased"), "success")
        cb(true)
    else
        Notification((result and result.message) or i18n.t("management.upgrade_purchase_failed"), "error")
        cb(false)
    end
end)

RegisterNUICallback("fast-action", function(data, cb)
    local action = data.action
    Debug("fast-action", action)

    if action == "decorate" then
        decorate:open()
    elseif action == "wardrobe" then
        SetLocation("wardrobe")
    elseif action == "storage" then
        SetLocation("stash")
    end

    cb("ok")
end)

-- ──────────────────────────────────────────────────────────
-- RegisterNUICallback: "watch-camera"
--   Called by the UI when a security camera button is clicked.
--   Looks up the placed camera object from decorate.objects
--   using the numeric cameraId (array index from GetCamerasData),
--   then opens a scripted camera view at the object's position,
--   mirroring the FrontDoorCam pattern from client/main.lua.
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("watch-camera", function(data, cb)
    cb("ok")

    local cameraId = tonumber(data and data.cameraId)
    if not cameraId then return end

    local obj = decorate and decorate.objects and decorate.objects[cameraId]
    if not obj then
        Notification(i18n.t("management.camera_not_found"), "error")
        return
    end

    -- ch_prop_ch_cctv_cam_01a lens points along the entity -X axis (confirmed by diagnostic).
    -- GetEntityMatrix returns (right/+X, forward/+Y, up/+Z, origin).
    -- We negate right to get -X (lens direction), then offset camCoords along that
    -- direction to move the scripted camera out of the prop geometry to the lens tip.
    local camCoords, camRot
    if obj.handle and DoesEntityExist(obj.handle) then
        local right, _, _, _ = GetEntityMatrix(obj.handle)
        local dir    = vec3(-right.x, -right.y, -right.z)  -- -X = lens direction
        local origin = GetEntityCoords(obj.handle)

        -- Offset 0.25 units along lens direction to clear prop geometry
        camCoords = vec3(
            origin.x + dir.x * 0.25,
            origin.y + dir.y * 0.25,
            origin.z + dir.z * 0.25
        )

        local pitch = math.deg(math.asin(dir.z)) - 11.5  -- tilt 11.5° extra downward
        local yaw   = math.deg(math.atan(-dir.x, dir.y))
        camRot = vec3(pitch, 0.0, yaw)
    else
        camCoords = obj.coords and vec3(obj.coords.x, obj.coords.y, obj.coords.z)
        local r   = obj.rotation
        camRot    = (r and vec3(r.x, r.y, r.z)) or vec3(0.0, 0.0, 0.0)
    end

    if not camCoords then
        Notification(i18n.t("management.camera_not_found"), "error")
        return
    end

    bossmenu:close()

    CreateThread(function()
        DoScreenFadeOut(150)
        Wait(500)

        local cam = Utils.CreateCamera("DEFAULT_SCRIPTED_CAMERA", camCoords, camRot, true)

        TriggerServerEvent("housing:toggleInSecurityCam", true)
        FreezeEntityPosition(cache.ped, true)

        ToggleCameraUI(true, i18n.t("management.camera_name", { id = cameraId }), "modern")
        Utils.DrawInstructional({ { key = "cancel", label = "Exit" } })

        DoScreenFadeIn(150)

        CreateThread(function()
            while true do
                Wait(0)
                -- Must be called every frame — a single call is overridden by the engine
                SetFocusPosAndVel(camCoords.x, camCoords.y, camCoords.z, 0.0, 0.0, 0.0)
                SetTimecycleModifier("scanline_cam_cheap")
                SetTimecycleModifierStrength(1.0)
                SetEntityInvincible(cache.ped, true)

                if IsControlJustPressed(1, Keys.BACKSPACE) then
                    DoScreenFadeOut(150)
                    ToggleCameraUI(false)
                    Wait(500)

                    Utils.DestroyFlyCam(cam)
                    ClearTimecycleModifier()
                    SetEntityInvincible(cache.ped, false)
                    FreezeEntityPosition(cache.ped, false)
                    TriggerServerEvent("housing:toggleInSecurityCam", false)
                    Utils.RemoveInstructional()

                    Wait(200)
                    DoScreenFadeIn(150)
                    break
                end
            end
        end)
    end)
end)
