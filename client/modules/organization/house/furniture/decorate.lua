-- ============================================================
-- client/modules/organization/house/furniture/decorate.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- In-world furniture placement/decoration system.
-- Manages spawning, selecting, moving, saving, and removing
-- furniture objects inside org houses.
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- Local hot-path natives
-- ──────────────────────────────────────────────────────────
local DisablePlayerFiring            = DisablePlayerFiring
local IsControlJustPressed           = IsControlJustPressed
local IsDisabledControlJustPressed   = IsDisabledControlJustPressed
local IsControlJustReleased          = IsControlJustReleased
local IsDisabledControlJustReleased  = IsDisabledControlJustReleased
local getCursorHitCoords             = Utils.getCursorHitCoords

-- ──────────────────────────────────────────────────────────
-- decorate state object (exposed via setmetatable proxy so
-- that setting currentObject auto-calls selectEntity /
-- deselectEntity and handles stash-page highlighting).
-- ──────────────────────────────────────────────────────────
local decorateState = {
    active        = false,
    currentObject = nil,    -- { handle, modelName, stashId? }
    hide          = false,
    focus         = false,
    keepInput     = false,
    objects       = {},
    currentPage   = "dynamic",
    mode          = "mgizmo",
    freeCamera    = false,
    cameraFocus   = false,
}

-- Proxy with a __newindex interceptor for currentObject
local decorateMeta = {}
decorateMeta.__index = function(_, key)
    return decorateState[key]
end
decorateMeta.__newindex = function(_, key, value)
    decorateState[key] = value

    if key == "currentObject" then
        if value then
            -- Highlight stash item if on stash page
            if decorateState.currentPage == "stash" then
                SendReactMessage("select_stash_item", value.stashId)
            end
            -- Select entity in gizmo
            if DoesEntityExist(value.handle) then
                decorate:selectEntity(value.handle)
            else
                decorate:deselectEntity()
            end
        else
            decorate:deselectEntity()
        end
    end
end

_G.decorate = setmetatable({}, decorateMeta)

-- ──────────────────────────────────────────────────────────
-- decorate:instructional(extraControls)
--   Draws the on-screen control hint bar for decorate mode.
-- ──────────────────────────────────────────────────────────
function decorate:instructional(extraControls)
    if not self.active then return end

    if DrawingInstructional then DrawingInstructional = false end

    local controls = {
        { key = "place_object_on_ground", label = "Place Object on Ground" },
        { key = "toggle_cursor",          label = "Toggle Cursor"          },
        { key = "toggle_free_mode",       label = "Toggle Free Mode"       },
        { key = "toggle_editor_mode",     label = "Toggle Editor Mode"     },
        { key = "toggle_gizmo_mode",      label = "Toggle Gizmo Mode"      },
        { key = "toggle_free_camera",     label = "Toggle Free Camera"     },
    }

    -- Buy button only shown when not a stash item
    if not (self.currentObject and self.currentObject.stashId) then
        controls[#controls + 1] = { key = "done", label = "Buy Object" }
    end

    -- Append any extra controls passed in
    if extraControls then
        for _, ctrl in pairs(extraControls) do
            controls[#controls + 1] = ctrl
        end
    end

    Utils.DrawInstructional(controls)
end

-- ──────────────────────────────────────────────────────────
-- decorate:open()
-- ──────────────────────────────────────────────────────────
function decorate:open()
    if self.active then
        Debug("decorate:open ::: decorate is already active")
        return
    end

    local orgId = OrganizationManager:getCurrentOrganization()
    if not orgId then
        Notification(i18n.t("decorate.not_in_garage"), "error")
        return
    end

    -- Block if a cleaner robot is currently running
    if cleanerRobot and cleanerRobot.hasActiveCleaningRobot then
        if cleanerRobot:hasActiveCleaningRobot() then
            Notification(i18n.t("decorate.robot_not_docked"), "error")
            return
        end
    end

    -- Check decoration availability on server
    local available = lib.callback.await("crime:decorate:getDecorationAvailable", false, orgId)
    if not available then
        Notification(i18n.t("decorate.decoration_not_available"), "error")
        return
    end

    TriggerServerEvent("crime:decorate:updateDecorationUsedBy", orgId, true)

    self.active = true
    self:toggleFreeCamera(true)
    self:setFocus(true)
    DisableIdleCamera(true)
    self:getObjects(orgId)

    SendReactMessage("toggle_decorate_menu", {
        visible     = true,
        navigation  = Config.FurnitureNavigation,
        furniture   = Config.Furniture,
        enableShop  = Config.EnableF3Shop,
    })

    ToggleHud(false)
    TriggerServerEvent("crime:fiveguard:freecam", true)
    self:instructional()
    gizmo:handleCameraUpdate()
    mgizmo:loop()
    self:handleControls()
    self:checkDistance()
end

-- ──────────────────────────────────────────────────────────
-- decorate:close()
-- ──────────────────────────────────────────────────────────
function decorate:close()
    if not self.active then return end
    self.active = false

    ToggleHud(true)
    DisableIdleCamera(false)
    self:removeCurrentObject()
    Utils.RemoveInstructional()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendReactMessage("toggle_decorate_menu", { visible = false })

    self.focus    = false
    self.keepInput = false
    DrawingInstructional = false

    TriggerServerEvent("crime:fiveguard:freecam", false)
    TriggerServerEvent("crime:decorate:updateDecorationUsedBy",
        OrganizationManager:getCurrentOrganization(), false)
end

-- ──────────────────────────────────────────────────────────
-- decorate:checkDistance()
--   Closes decorate mode if the camera drifts too far from
--   the player's original position.
-- ──────────────────────────────────────────────────────────
function decorate:checkDistance()
    if not Config.MaximumDistanceForDecorate then return end

    local startPos = GetEntityCoords(cache.ped)

    CreateThread(function()
        while self.active do
            local orgId = OrganizationManager:getCurrentOrganization()
            if not orgId then break end

            local camPos = GetFinalRenderedCamCoord()
            if #(camPos - startPos) > Config.MaximumDistanceForDecorate then
                Notification(i18n.t("decorate.too_far"), "error")
                self:close()
            end

            Wait(500)
        end
    end)
end

-- ──────────────────────────────────────────────────────────
-- decorate:selectEntity(handle)
--   Passes the entity to gizmo/mgizmo and refreshes the
--   instructional bar.
-- ──────────────────────────────────────────────────────────
function decorate:selectEntity(handle)
    local gizmoTarget = (self.mode == "gizmo") and gizmo or mgizmo

    if handle then
        if not DoesEntityExist(handle) then
            gizmoTarget.entity       = nil
            gizmoTarget.decorateData = nil
            return
        end
    end

    -- Determine entity from cursor or explicit handle
    local entity = handle
    if not entity then
        local hit, hitEntity = getCursorHitCoords()
        if hit and hitEntity and hitEntity ~= 0 then
            entity = hitEntity
        end
    end

    if not entity then return end

    -- On non-stash pages, only the current object can be selected
    if decorate.currentPage ~= "stash" and not handle then
        local curHandle = decorate.currentObject and decorate.currentObject.handle
        if curHandle ~= entity then
            Notification(i18n.t("decorate.you_cant_select_entity"), "error")
            return
        end
    end

    local objData = self:getObjectData(entity)
    if not handle and not objData then return end

    gizmoTarget.entity       = entity
    gizmoTarget.decorateData = objData

    -- Update currentObject if not already set to this handle
    local curHandle = decorate.currentObject and decorate.currentObject.handle
    if curHandle ~= entity then
        decorate.currentObject = {
            handle    = entity,
            modelName = objData.modelName,
            stashId   = objData.id,
        }
    end

    gizmoTarget:selectEntity()
    self:instructional()
end

-- ──────────────────────────────────────────────────────────
-- decorate:deselectEntity()
-- ──────────────────────────────────────────────────────────
function decorate:deselectEntity()
    gizmo:deselectEntity()
    self:instructional()
end

-- ──────────────────────────────────────────────────────────
-- decorate:getCamCoords() → vec3
-- ──────────────────────────────────────────────────────────
function decorate:getCamCoords()
    return GetFinalRenderedCamCoord()
end

-- ──────────────────────────────────────────────────────────
-- decorate:getCamRot() → vec3
-- ──────────────────────────────────────────────────────────
function decorate:getCamRot()
    return GetFinalRenderedCamRot(2)
end

-- ──────────────────────────────────────────────────────────
-- decorate:toggleHideDecorate()
-- ──────────────────────────────────────────────────────────
function decorate:toggleHideDecorate()
    self.hide = not self.hide
    SendReactMessage("toggle_hide_decorate", self.hide)
    self:setFocus(true, not self.hide)
end

-- ──────────────────────────────────────────────────────────
-- decorate:setFocus(focusOn, keepInput)
-- ──────────────────────────────────────────────────────────
function decorate:setFocus(focusOn, keepInput)
    -- Default: toggle if no explicit argument
    if focusOn == nil then
        self.focus = not self.focus
    else
        self.focus = focusOn
    end

    SetNuiFocus(self.focus, self.focus)

    if keepInput ~= nil then
        self.keepInput = keepInput
    else
        self.keepInput = keepInput
    end
    self.keepInput = keepInput
    SetNuiFocusKeepInput(self.keepInput)

    -- When losing NUI input, switch to gizmo mode so entity is movable
    if not self.keepInput then
        if self.mode == "mgizmo" then
            self:toggleGizmoMode("gizmo")
            Debug("setFocus ::: toggleGizmoMode to gizmo because keepInput is false")
        end
    end
end

-- ──────────────────────────────────────────────────────────
-- decorate:placeObjectOnGround()
-- ──────────────────────────────────────────────────────────
function decorate:placeObjectOnGround()
    local handle = decorate.currentObject and decorate.currentObject.handle
    if not handle then return end
    PlaceObjectOnGroundProperly(handle)
    gizmo:updateGizmoEntity()
end

-- ──────────────────────────────────────────────────────────
-- decorate:toggleGizmoMode(forcedMode)
-- ──────────────────────────────────────────────────────────
function decorate:toggleGizmoMode(forcedMode)
    if self.mode == "gizmo" then
        if not self.keepInput then
            Debug("toggleGizmoMode ::: mgizmo mode is enabled and keepInput is true, so we do not toggle mode")
            return
        end
    end

    if forcedMode then
        if forcedMode == self.mode then
            Debug("toggleGizmoMode ::: mode is already same", "mode", forcedMode)
            return
        end
        self.mode = forcedMode
    else
        self.mode = (self.mode == "gizmo") and "mgizmo" or "gizmo"
    end

    SendReactMessage("toggle_gizmo_mode", self.mode)
    Notification(i18n.t("decorate.gizmo_mode_toggled", { mode = self.mode }), "info")

    gizmo:deselectEntity()
    mgizmo:deselectEntity()

    if self.mode == "gizmo" then
        gizmo:handleCameraUpdate()
    else
        mgizmo:loop()
    end
end

-- ──────────────────────────────────────────────────────────
-- InitializeFurnitures()
--   Builds Config.DynamicFurnitures, Config.DoorModels, and
--   the onlyInside lookup table from Config.Furniture.
-- ──────────────────────────────────────────────────────────
LIGHT_ITEMS = Config.Furniture.light.items

-- Keep original DynamicFurnitures for reset on each call
local _originalDynamicFurnitures = table.deepclone(Config.DynamicFurnitures)
local _onlyInsideModels          = {}

function InitializeFurnitures()
    Config.DynamicFurnitures = table.deepclone(_originalDynamicFurnitures)
    Config.DoorModels        = {}
    _onlyInsideModels        = {}

    for category, catData in pairs(Config.Furniture) do
        if category ~= "navigation" then
            for _, item in pairs(catData.items) do
                -- Dynamic furniture type
                if item.type then
                    Config.DynamicFurnitures[item.object] = item
                end
                -- Door models
                if item.isDoor then
                    Config.DoorModels[item.object] = item
                end
                -- Only-inside models
                if item.onlyInside then
                    _onlyInsideModels[item.object] = true
                end

                -- Process color variants
                if item.colors then
                    for _, colorItem in pairs(item.colors) do
                        if colorItem.type then
                            Config.DynamicFurnitures[colorItem.object] = colorItem
                        end
                        if item.isDoor then
                            Config.DoorModels[colorItem.object] = colorItem
                        end
                        if item.onlyInside then
                            _onlyInsideModels[colorItem.object] = true
                        end
                    end
                end
            end
        end
    end
end

-- IsOnlyInsideModel(modelName) → bool
function IsOnlyInsideModel(modelName)
    return _onlyInsideModels[modelName] == true
end

CreateThread(InitializeFurnitures)

-- ──────────────────────────────────────────────────────────
-- handleControls thread
-- ──────────────────────────────────────────────────────────
function decorate:handleControls()
    CreateThread(function()
        local prevHandle = 0

        while self.active do
            -- Disable shooting while in decorate
            DisablePlayerFiring(cache.playerId, true)

            -- Track outline changes when currentObject changes
            local curHandle = self.currentObject and self.currentObject.handle
            if prevHandle ~= curHandle then
                SetEntityDrawOutline(prevHandle, false)
                SetEntityDrawOutline(curHandle, true)
                SetEntityDrawOutlineColor(0, 180, 255, 255)
            end
            prevHandle = curHandle or 0

            -- F5: toggle cursor / focus
            if IsControlJustPressed(0, Keys.F5)
               or IsDisabledControlJustPressed(0, Keys.F5) then
                self:setFocus(true)
            end

            -- F3: toggle free camera
            if IsControlJustPressed(0, Keys.F3)
               or IsDisabledControlJustPressed(0, Keys.F3) then
                self:toggleFreeCamera()
            end

            -- Enter: open buy-object modal (only for non-stash items)
            if IsControlJustPressed(0, Keys.Enter)
               or IsDisabledControlJustPressed(0, Keys.Enter) then
                if not (self.currentObject and self.currentObject.stashId) then
                    self:openBuyObjectModal()
                end
            end

            -- G: place on ground (only when object is selected)
            if prevHandle ~= 0 then
                if IsControlJustReleased(0, Keys.G)
                   or IsDisabledControlJustReleased(0, Keys.G) then
                    self:placeObjectOnGround()
                end
            end

            Wait(0)
        end
    end)
end

-- Camera lerp speed constant
local CAM_LERP = 0.01

-- ──────────────────────────────────────────────────────────
-- toggleFreeCamera(forceOn)
--   Launches a fly-cam loop with optional orbit-focus mode.
-- ──────────────────────────────────────────────────────────
function decorate:toggleFreeCamera(forceOn)
    if forceOn ~= nil then
        self.freeCamera = forceOn
    else
        self.freeCamera = not self.freeCamera
    end

    if not self.freeCamera then return end

    -- Disable player control
    SetPlayerControl(cache.playerId, false, 0)

    -- Create scripted camera at current ped position + forward
    local right, forward, _, origin = GetEntityMatrix(cache.ped)
    local camOrigin = origin + forward
    local pedRot    = GetEntityRotation(cache.ped)

    local cam = Utils.CreateCamera("DEFAULT_SCRIPTED_CAMERA",
        camOrigin, pedRot, true, nil, 1000)

    self:instructional({
        { key = "focus_free_camera", label = "Focus Object" },
    })
    self.cameraFocus = false

    local camCoords = camOrigin
    local camRot    = pedRot

    CreateThread(function()
        while self.active and self.freeCamera do
            -- Fly-cam movement
            camCoords, camRot = Utils.HandleFlyCam(cam, {
                mouse = not self.cameraFocus,
            })

            DisableAllControlActions(0)

            -- F: toggle focus (only in gizmo mode)
            if IsDisabledControlJustPressed(0, Keys.F) then
                if self.mode == "gizmo" then
                    self.cameraFocus = not self.cameraFocus
                else
                    Notification(i18n.t("decorate.focus_object_not_supported"), "error")
                end
            end

            -- mgizmo doesn't support focus
            if self.cameraFocus and self.mode == "mgizmo" then
                self.cameraFocus = false
            end

            -- Orbit-focus camera around selected object
            if self.cameraFocus then
                local handle = self.currentObject and self.currentObject.handle
                if handle and DoesEntityExist(handle) then
                    local objPos     = GetEntityCoords(handle)
                    local objHash    = GetEntityModel(handle)
                    local dimMin, dimMax = GetModelDimensions(objHash)
                    local objSize    = #(dimMax - dimMin)
                    local orbitDist  = math.max(objSize * 2.0, 3.0)
                    local objHeight  = dimMax.z - dimMin.z

                    local toObj     = objPos - camCoords
                    local dist      = #toObj
                    local normTo    = toObj / dist

                    -- Compute desired rotation looking at object
                    local pitchRad = math.asin(normTo.z)
                    local yawRad   = math.atan(-normTo.x, normTo.y)
                    local targetRot = vec3(
                        math.deg(pitchRad),
                        0.0,
                        math.deg(yawRad))

                    -- Lerp camera rotation
                    local newRot = vec3(
                        camRot.x + (targetRot.x - camRot.x) * CAM_LERP,
                        camRot.y + (targetRot.y - camRot.y) * CAM_LERP,
                        camRot.z + (targetRot.z - camRot.z) * CAM_LERP)
                    SetCamRot(cam, newRot.x, newRot.y, newRot.z, 2)

                    -- Adjust camera distance
                    if dist > orbitDist * 1.5 or dist < orbitDist * 0.5 then
                        local targetPos = objPos - (normTo * orbitDist)
                        local newCamPos = vec3(
                            camCoords.x + (targetPos.x - camCoords.x) * CAM_LERP * 0.5,
                            camCoords.y + (targetPos.y - camCoords.y) * CAM_LERP * 0.5,
                            camCoords.z + (targetPos.z - camCoords.z) * CAM_LERP * 0.5)
                        SetCamCoord(cam, newCamPos.x, newCamPos.y, newCamPos.z)
                        camCoords = newCamPos
                    end

                    -- Orbit close-in animation
                    if dist < orbitDist * 0.7 then
                        local t       = GetGameTimer() / 1000.0 * 0.3
                        local radius  = orbitDist * 0.8
                        local orbitTarget = vec3(
                            objPos.x + math.cos(t) * radius,
                            objPos.y + math.sin(t) * radius,
                            objPos.z + objHeight)
                        local newPos = vec3(
                            camCoords.x + (orbitTarget.x - camCoords.x) * 0.05,
                            camCoords.y + (orbitTarget.y - camCoords.y) * 0.05,
                            camCoords.z + (orbitTarget.z - camCoords.z) * 0.05)
                        SetCamCoord(cam, newPos.x, newPos.y, newPos.z)
                    end
                end
            end

            Wait(0)
        end

        -- Cleanup
        Utils.DestroyFlyCam(cam, 1000)
        SetPlayerControl(cache.playerId, true, 0)
        self:instructional()
    end)
end

-- ──────────────────────────────────────────────────────────
-- removeCurrentObject()
--   Deletes the ghost of the currently selected new object
--   (unless it came from the stash).
-- ──────────────────────────────────────────────────────────
function decorate:removeCurrentObject()
    if not decorate.currentObject then return end

    local handle = decorate.currentObject.handle
    if handle and not decorate.currentObject.stashId then
        DeleteObject(handle)
    end

    gizmo:deselectEntity()
    decorate.currentObject = nil
    SendReactMessage("remove_current_object")
    Debug("Removed current object", decorate.currentObject)
end

-- Export: isInDecorate
exports("inDecorate", function()
    return decorate.active
end)

-- ──────────────────────────────────────────────────────────
-- getObjectData(handle) → object | false
--   Returns the decorate.objects entry whose entity handle
--   matches, or the currentObject if it matches, or false.
-- ──────────────────────────────────────────────────────────
function decorate:getObjectData(handle)
    local cur = decorate.currentObject
    if cur and cur.handle == handle then return cur end

    for _, obj in pairs(decorate.objects) do
        if obj.handle and DoesEntityExist(obj.handle) then
            if obj.handle == handle then return obj end
        end
    end
    return false
end

-- ──────────────────────────────────────────────────────────
-- saveCurrentObject()
--   Saves the currently held object to the server.
-- ──────────────────────────────────────────────────────────
function decorate:saveCurrentObject()
    Debug("saveCurrentObject", "Current object", decorate.currentObject)
    if not self.currentObject then return end

    local data = {
        modelName = self.currentObject.modelName,
        coords    = GetEntityCoords(self.currentObject.handle),
        rotation  = GetEntityRotation(self.currentObject.handle),
        handle    = self.currentObject.handle,
        inStash   = false,
        inHouse   = (EnteredHouse ~= nil),
        house     = OrganizationManager:getCurrentOrganization(),
    }

    self:removeCurrentObject()
    return lib.callback.await("crime:saveObject", false,
        OrganizationManager:getCurrentOrganization(), data)
end

-- ──────────────────────────────────────────────────────────
-- destroyObjects()
--   Despawns all tracked decoration entities.
-- ──────────────────────────────────────────────────────────
function decorate:destroyObjects()
    local snapshot = table.deepclone(decorate.objects)
    decorate.objects = {}

    for _, obj in pairs(snapshot) do
        RemoveSpawnedObject(obj)
    end

    if cleanerRobot then
        cleanerRobot:stopInteractionLoop()
        cleanerRobot:cleanAll()
    end
end

-- ──────────────────────────────────────────────────────────
-- refreshObjects()
--   Despawns all entities without clearing the object list.
-- ──────────────────────────────────────────────────────────
function decorate:refreshObjects()
    for _, obj in pairs(decorate.objects) do
        RemoveSpawnedObject(obj)
    end
end

-- ──────────────────────────────────────────────────────────
-- saveObjects()
--   Fires crime:updateObject for any decoration that has
--   moved or rotated since the last sync.
-- ──────────────────────────────────────────────────────────
function decorate:saveObjects()
    local orgId = OrganizationManager:getCurrentOrganization()

    for _, obj in pairs(decorate.objects) do
        if obj.spawned and DoesEntityExist(obj.handle) then
            local newCoords = GetEntityCoords(obj.handle)
            local newRot    = GetEntityRotation(obj.handle)
            local oldCoords = vec3(newCoords.x, newCoords.y, newCoords.z)
            local oldRot    = vec3(newRot.x,    newRot.y,    newRot.z)

            local coordChanged = (oldCoords.x ~= obj.coords.x) or (oldRot.x ~= obj.rotation.x)
            if coordChanged then
                obj.coords   = newCoords
                obj.rotation = newRot
                TriggerServerEvent("crime:updateObject", orgId, obj.id, {
                    coords   = json.encode(newCoords),
                    rotation = json.encode(newRot),
                })
            end
        end
    end
end

-- ──────────────────────────────────────────────────────────
-- openBuyObjectModal()
-- ──────────────────────────────────────────────────────────
function decorate:openBuyObjectModal()
    if not self.currentObject then return end
    SendReactMessage("open_buy_object_modal")
end

-- ──────────────────────────────────────────────────────────
-- Net event: crime:updateObject (from another client or server)
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:updateObject", function(house, objectId, updates)
    local orgId = OrganizationManager:getCurrentOrganization()
    if orgId ~= house then
        Debug("crime:updateObject ::: house is not same",
            "currentHouse", orgId, "house", house)
        return
    end

    local obj = table.find(decorate.objects, function(o) return o.id == objectId end)
    if not obj then
        Error("crime:updateObject :: Object not found", "id", objectId)
        return
    end

    for key, value in pairs(updates) do
        if key == "coords" and obj.spawned then
            Debug("crime:updateObject ::: SetEntityCoords",
                "object", obj.handle, "coords", value)
            SetEntityCoords(obj.handle,
                value.x, value.y, value.z,
                false, false, false, false)

        elseif key == "rotation" and obj.spawned then
            Debug("crime:updateObject ::: SetEntityRotation",
                "object", obj.handle, "rotation", value)
            SetEntityRotation(obj.handle,
                value.x, value.y, value.z, 0, false)
        end

        obj[key] = value
        Debug("Updated object", "object", obj.id, "key", key, "value", value)
    end
end)

-- ──────────────────────────────────────────────────────────
-- RemoveSpawnedObject(objData)
--   Deletes entity, despawns cleaner robot if applicable.
-- ──────────────────────────────────────────────────────────
function RemoveSpawnedObject(objData)
    if not objData.spawned then return false end

    -- Despawn associated cleaner robot
    if cleanerRobot and objData.id then
        if cleanerRobot:isCleanerModel(objData.modelName) then
            cleanerRobot:despawn(objData.id)
        end
    end

    DeleteObject(objData.handle)
    objData.spawned = false
end

-- ──────────────────────────────────────────────────────────
-- Net event: crime:decorate:sellFurniture
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:decorate:sellFurniture", function(house, objectId)
    local orgId = OrganizationManager:getCurrentOrganization()
    if orgId ~= house then
        Debug("crime:decorate:sellFurniture ::: house is not same",
            "currentHouse", orgId, "house", house)
        return
    end

    local obj = table.find(decorate.objects, function(o) return o.id == objectId end)
    if not obj then
        Error("crime:decorate:sellFurniture ::: Object not found", "id", objectId)
        return
    end

    RemoveSpawnedObject(obj)
    decorate.objects = table.filter(decorate.objects,
        function(o) return o.id ~= objectId end)
    Debug("crime:decorate:sellFurniture", "object is deleted from cache", obj.id)
end)

-- ──────────────────────────────────────────────────────────
-- Net event: crime:addObject — server confirms a new object
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:addObject", function(house, objData)
    local orgId = OrganizationManager:getCurrentOrganization()
    if orgId ~= house then
        Debug("crime:addObject ::: house is not same",
            "currentHouse", orgId, "house", house)
        return
    end

    local n = #decorate.objects + 1
    decorate.objects[n] = objData
    Debug("Added object to data", "data", objData)
end)

-- ──────────────────────────────────────────────────────────
-- Net event: crime:removeFurniture
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:removeFurniture", function(house, objectId)
    local orgId = OrganizationManager:getCurrentOrganization()
    if orgId ~= house then return end

    local objs = decorate.objects
    if not objs then return end

    for i, obj in pairs(objs) do
        if obj.id == objectId then
            -- Despawn cleaner robot if applicable
            if cleanerRobot then
                if cleanerRobot:isCleanerModel(obj.modelName) then
                    cleanerRobot:despawn(objectId)
                end
            end

            if obj.handle and DoesEntityExist(obj.handle) then
                DeleteObject(obj.handle)
            end

            objs[i] = nil
            Debug("Removed furniture:", objectId)
            break
        end
    end
end)

-- ──────────────────────────────────────────────────────────
-- SpawnObject(modelName, coords, rotation) → handle | 0
--   Creates a world object with a fade-in animation.
--   If Config.DynamicDoors is true and the model is a door,
--   collisions are NOT disabled.
-- ──────────────────────────────────────────────────────────
function SpawnObject(modelName, coords, rotation)
    local hash = joaat(modelName)
    lib.requestModel(hash, Config.DefaultRequestModelTimeout)

    local handle = CreateObject(hash,
        coords.x, coords.y, coords.z, false, false, false)

    -- Start invisible and fade in
    SetEntityAlpha(handle, 0, false)
    CreateThread(function()
        for alpha = 0, 255, 51 do
            Wait(50)
            SetEntityAlpha(handle, alpha, false)
        end
    end)

    if rotation then
        SetEntityRotation(handle,
            rotation.x, rotation.y, rotation.z, 0, false)
    end

    SetEntityAsMissionEntity(handle, true, true)
    SetEntityInvincible(handle, true)
    SetEntityCompletelyDisableCollision(handle, true, false)

    -- If DynamicDoors enabled and this is a door model: freeze instead
    if Config.DynamicDoors and Config.DoorModels and Config.DoorModels[modelName] then
        FreezeEntityPosition(handle, true)
    end

    SetModelAsNoLongerNeeded(hash)
    Wait(0)
    SetEntityCoords(handle,
        coords.x, coords.y, coords.z,
        false, false, false, false)
    return handle
end

-- ──────────────────────────────────────────────────────────
-- getObjects(orgId)
--   Fetches the decoration list from server and triggers
--   cleaner robot initialization if needed.
-- ──────────────────────────────────────────────────────────
function decorate:getObjects(orgId)
    self:destroyObjects()
    local objects    = lib.callback.await("crime:getDecorations", 0, orgId)
    decorate.objects = objects

    local curOrg = OrganizationManager:getCurrentOrganization()
    if cleanerRobot and curOrg and EnteredHouse then
        CreateThread(function()
            Wait(500)
            if not decorate.objects then return end

            for _, obj in pairs(decorate.objects) do
                if obj.spawned and obj.handle and DoesEntityExist(obj.handle) then
                    if cleanerRobot:isCleanerModel(obj.modelName) then
                        cleanerRobot:spawnForDecoration(obj, curOrg)
                    end
                end
            end

            if cleanerRobot:hasRobots() and not Config.UseTarget then
                cleanerRobot:startInteractionLoop()
            end
        end)
    end
end

-- ──────────────────────────────────────────────────────────
-- Light system: tracks active light items and their positions
-- ──────────────────────────────────────────────────────────
local activeLightObjects = {}
local lightModelNames    = {}

CreateThread(function()
    -- Build list of light model names
    for _, item in pairs(LIGHT_ITEMS) do
        table.insert(lightModelNames, item.object)
    end

    -- Poll decorate.objects and extract position/direction for lights
    while true do
        if not decorate.objects then
            activeLightObjects = {}
            Wait(500)
        else
            -- Filter to just light items
            local lightObjs = table.deepclone(
                table.filter(decorate.objects, function(o)
                    return table.includes(lightModelNames, o.modelName)
                end))

            activeLightObjects = lightObjs

            local orgId = OrganizationManager:getCurrentOrganization()

            for i, obj in pairs(activeLightObjects) do
                if obj.handle and DoesEntityExist(obj.handle) then
                    if not (obj.inside and not orgId) then
                        local rot     = GetEntityRotation(obj.handle)
                        local pos     = GetEntityCoords(obj.handle)
                        local dir     = RotationToDirection(rot)

                        activeLightObjects[i].position  = pos
                        activeLightObjects[i].direction = dir
                    end
                end
            end

            Wait(500)
        end
    end
end)

-- Light rendering thread
CreateThread(function()
    while true do
        local waitMs = 1250

        for _, obj in pairs(activeLightObjects) do
            if obj.handle and DoesEntityExist(obj.handle) then
                -- Skip if light is explicitly disabled
                if obj.lightData and not obj.lightData.active then
                    goto continueLightLoop
                end

                if obj.position then
                    waitMs = 0
                    local rgb = (obj.lightData and obj.lightData.rgb)
                        or { r = 255, g = 255, b = 255 }
                    local intensity = ((obj.lightData and obj.lightData.intensity)
                        or Config.DefaultLightIntensity) + 0.0

                    DrawSpotLight(
                        obj.position.x, obj.position.y, obj.position.z,
                        obj.direction.x, obj.direction.y, obj.direction.z,
                        rgb.r, rgb.g, rgb.b,
                        100.0, 20.0, 1.0, intensity, 0.0)
                end
            end
            ::continueLightLoop::
        end

        Wait(waitMs)
    end
end)

-- ──────────────────────────────────────────────────────────
-- Main object streaming thread
--   Spawns objects when the player enters SpawnDistance,
--   despawns when they leave. Also handles stash items and
--   onlyInside models.
-- ──────────────────────────────────────────────────────────
CreateThread(function()
    while true do
        local waitMs    = decorate.active and 300 or 1250
        local playerPos = GetEntityCoords(cache.ped)
        local objects   = decorate.objects

        if not objects then
            Wait(waitMs)
        else
            local orgId = OrganizationManager:getCurrentOrganization()

            for _, obj in pairs(objects) do
                -- Remove stash items that are still spawned
                if obj.inStash then
                    if obj.spawned then
                        DeleteObject(obj.handle)
                        obj.spawned = false
                        Debug("Deleted object because its setted to inStash",
                            "object", obj.handle)
                    end

                elseif not obj.coords then
                    Error("Object coords is nil we skipping it.", "object", obj)

                else
                    -- onlyInside items: remove when player leaves house
                    if IsOnlyInsideModel(obj.modelName) then
                        if not EnteredHouse and obj.spawned then
                            RemoveSpawnedObject(obj)
                            Debug("Deleted onlyInside object because player left the house",
                                "object", obj.handle)
                        end
                    else
                        -- Normalise coords
                        obj.coords = vec3(obj.coords.x, obj.coords.y, obj.coords.z)

                        -- Handle ikea/zero-coord objects: place at camera center
                        if obj.coords.x == 0.0 and obj.coords.y == 0.0 and obj.coords.z == 0.0 then
                            if decorate.active then
                                local cam     = Utils.GetCamera()
                                local forward = Utils.GetForwardVector(cam.rotation)
                                local newPos  = cam.coords + (forward * 5.0)
                                Debug("Load Decorations : Object is from ikea. We setted it to camera center",
                                    "v", obj)
                                obj.coords = vec3(newPos.x, newPos.y, newPos.z)
                                decorate:saveObjects()
                            end
                        end

                        local dist = #(playerPos - obj.coords)

                        if dist <= Config.SpawnDistance then
                            -- Spawn if not yet spawned
                            if not obj.spawned then
                                local handle = SpawnObject(obj.modelName, obj.coords, obj.rotation)
                                if handle then
                                    obj.handle  = handle
                                    obj.spawned = true

                                    -- Re-select if this was the pending stash object
                                    local cur = decorate.currentObject
                                    if cur and cur.stashId == obj.id then
                                        decorate.currentObject.handle = handle
                                        decorate:selectEntity(handle)
                                    end

                                    -- Spawn cleaner robot if applicable
                                    if cleanerRobot and orgId and EnteredHouse then
                                        if cleanerRobot:isCleanerModel(obj.modelName) then
                                            cleanerRobot:spawnForDecoration(obj, orgId)
                                            if cleanerRobot:hasRobots() and not Config.UseTarget then
                                                cleanerRobot:startInteractionLoop()
                                            end
                                        end
                                    end
                                else
                                    obj.handle  = 0
                                    obj.spawned = true
                                    Warning("This model is not loaded. Please check if the model is valid. if its not delete it from the list",
                                        obj.modelName)
                                end
                            end

                        else
                            -- Despawn if too far
                            if obj.spawned then
                                RemoveSpawnedObject(obj)
                                Debug("Deleted object", "object", obj.handle)
                            end
                        end
                    end
                end
            end

            Wait(waitMs)
        end
    end
end)

-- ──────────────────────────────────────────────────────────
-- Resource stop
-- ──────────────────────────────────────────────────────────
AddEventHandler("onResourceStop", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    decorate:destroyObjects()
    decorate:close()
end)
