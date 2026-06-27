-- ============================================================
-- client/modules/organization/house/furniture/nui.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- NUI callbacks for the house furniture / decoration UI.
-- Bridges the NUI (Vue/React front-end) to the `decorate`
-- Lua module.
-- ============================================================

local function cbAwait(name, ...)
    local ok, result = pcall(lib.callback.await, name, ...)
    if not ok then
        Error("cbAwait ::: " .. tostring(name), result)
        return nil
    end
    return result
end

-- ──────────────────────────────────────────────────────────
-- toggle_hide_decorate  — show/hide the decorate HUD
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("toggle_hide_decorate", function(_, cb)
    decorate:toggleHideDecorate()
    cb("ok")
end)

-- ──────────────────────────────────────────────────────────
-- spawn_object  — spawn a catalogue object in front of cam
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("spawn_object", function(data, cb)
    if not decorate.active then return cb("ok") end

    decorate:removeCurrentObject()

    -- Check interior-only restriction
    if IsOnlyInsideModel(data.modelName) then
        if not EnteredHouse then
            Notification(i18n.t("decorate.only_inside_purchase"), "error")
            return cb("ok")
        end
    end

    -- Check if this is a light item (needs spotlight loop)
    local isLightItem = table.find(LIGHT_ITEMS, function(e)
        return e.object == data.modelName
    end)

    -- Spawn 5 units in front of the camera
    local camPos     = decorate:getCamCoords()
    local camRot     = decorate:getCamRot()
    local forward    = Utils.GetForwardVector(camRot)
    local spawnCoord = camPos + (forward * 5.0)

    local handle = SpawnObject(data.modelName, spawnCoord, vec3(0.0, 0.0, 0.0))
    cb(handle)

    if not handle then
        Notification("Object is not spawned", "error")
        return
    end

    decorate.currentObject = {
        modelName = data.modelName,
        handle    = handle,
        price     = data.price,
    }

    Debug("Spawned object", "decorate.currentObject", decorate.currentObject)

    -- If it's a light item, render the spotlight while it's the current object
    if isLightItem then
        CreateThread(function()
            while decorate.currentObject and decorate.currentObject.handle do
                Wait(0)
                local rot     = GetEntityRotation(decorate.currentObject.handle)
                local coords  = GetEntityCoords(decorate.currentObject.handle)
                local dir     = RotationToDirection(rot)
                DrawSpotLight(
                    coords.x, coords.y, coords.z,
                    dir.x, dir.y, dir.z,
                    255, 255, 255,
                    100.0, 20.0, 1.0,
                    Config.DefaultLightIntensity, 0.0
                )
            end
        end)
    end
end)

-- ──────────────────────────────────────────────────────────
-- place_object_on_ground  — snap current object to ground
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("place_object_on_ground", function(_, cb)
    if not (decorate.currentObject and decorate.currentObject.handle) then
        return cb("ok")
    end
    decorate:placeObjectOnGround()
    cb("ok")
end)

-- ──────────────────────────────────────────────────────────
-- set_current_page  — track which catalogue page is open
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("set_current_page", function(data, cb)
    decorate.currentPage = data
    cb("ok")
end)

-- ──────────────────────────────────────────────────────────
-- toggle_cursor  — toggle NUI focus / cursor visibility
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("toggle_cursor", function(_, cb)
    decorate:setFocus()
    cb("ok")
end)

-- ──────────────────────────────────────────────────────────
-- save_locations  — persist all placed objects to server
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("save_locations", function(_, cb)
    decorate:saveObjects()
    cb("ok")
end)

-- ──────────────────────────────────────────────────────────
-- sell_current_object  — sell the currently selected object
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("sell_current_object", function(_, cb)
    local stashId = decorate.currentObject and decorate.currentObject.stashId

    if not stashId then
        Error("sell_current_object", "Selected object id is nil",
            decorate.currentObject and decorate.currentObject.stashId)
        return
    end

    local obj = table.find(decorate.objects, function(o)
        return o.id == decorate.currentObject.stashId
    end)

    if not obj then
        Error("sell_current_object", "Object not found",
            decorate.currentObject.stashId)
        return
    end

    TriggerServerEvent("crime:decorate:sellFurniture",
        OrganizationManager:getCurrentOrganization(),
        decorate.currentObject.stashId)

    decorate:removeCurrentObject()
    cb("ok")
end)

-- ──────────────────────────────────────────────────────────
-- update_stash  — update server-side object data
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("update_stash", function(data, cb)
    TriggerServerEvent("crime:updateObject",
        OrganizationManager:getCurrentOrganization(),
        decorate.currentObject.stashId,
        data)
    cb("ok")
end)

-- ──────────────────────────────────────────────────────────
-- buy_object  — purchase the currently previewed object
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("buy_object", function(_, cb)
    if not decorate.currentObject then
        Error("buy_object", "Current object is nil", decorate.currentObject)
        return cb("ok")
    end

    -- Interior-only check
    if IsOnlyInsideModel(decorate.currentObject.modelName) then
        if not EnteredHouse then
            Notification(i18n.t("decorate.only_inside_purchase"), "error")
            return cb("ok")
        end
    end

    local orgId = OrganizationManager:getCurrentOrganization()
    local org   = OrganizationManager:get(orgId)

    if not org then
        Error("buy_object", "Organization not found", orgId)
        return cb("ok")
    end

    if not org.upgrades then
        Debug("buy_object", "House data not found", orgId)
        return cb("ok")
    end

    -- Check furniture slot limit based on upgrades
    local hasUpgrade = table.includes(org.upgrades.upgrades, "furniture")
    local limit = hasUpgrade
        and Config.FurnitureLimits.upgrade
        or  Config.FurnitureLimits.normal

    if #decorate.objects >= limit then
        cb("ok")
        local msg = hasUpgrade
            and "You have reached the maximum number of furniture items"
            or  "You have reached the maximum number of furniture items. You can upgrade your property to increase the limit."
        return Notification(msg, "error")
    end

    Debug("buy_object", "Current object", decorate.currentObject)

    -- Charge the player
    local success = cbAwait("crime:buyDecorationObject", false,
        decorate.currentObject.price)

    if not success then
        Notification(i18n.t("not_enough_money", {
            amount = decorate.currentObject.price,
        }), "error")
        decorate:removeCurrentObject()
        cb("ok")
        return
    end

    decorate:saveCurrentObject()
    cb("ok")
end)

-- ──────────────────────────────────────────────────────────
-- get_owned_objects  — return the list of placed objects
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("get_owned_objects", function(_, cb)
    cb(decorate.objects)
end)

-- ──────────────────────────────────────────────────────────
-- select_owned_object  — pick an already-placed object for editing
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("select_owned_object", function(data, cb)
    local obj = table.find(decorate.objects, function(o) return o.id == data end)

    if not obj then
        Error("select_owned_object", "Object not found", data)
        return
    end

    decorate.currentObject = {
        handle    = obj.handle,
        modelName = obj.modelName,
        stashId   = obj.id,
    }

    Debug("Selected object", "data", obj, "objectData", obj)
    cb(true)
end)

-- ──────────────────────────────────────────────────────────
-- deselect_owned_object  — deselect and refresh world objects
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("deselect_owned_object", function(_, cb)
    decorate:removeCurrentObject()
    decorate:refreshObjects()
    cb(true)
end)

-- ──────────────────────────────────────────────────────────
-- remove_current_object  — delete the current preview object
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("remove_current_object", function(_, cb)
    decorate:removeCurrentObject()
    cb("ok")
end)

-- ──────────────────────────────────────────────────────────
-- Camera speed setting map
-- ──────────────────────────────────────────────────────────
local CAMERA_SPEED_KEYS = {
    x     = "lookSpeedX",
    y     = "lookSpeedY",
    speed = "moveSpeed",
}

RegisterNUICallback("updateCameraSpeed", function(data, _)
    local key = CAMERA_SPEED_KEYS[data.type]
    if key then CameraOptions[key] = data.value end
end)

-- ──────────────────────────────────────────────────────────
-- toggle_gizmo_mode  — switch between move / rotate / scale
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("toggle_gizmo_mode", function(_, cb)
    decorate:toggleGizmoMode()
    cb("ok")
end)

-- ──────────────────────────────────────────────────────────
-- toggle_free_camera  — enable/disable fly camera
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("toggle_free_camera", function(_, cb)
    decorate:toggleFreeCamera()
    cb("ok")
end)

-- ──────────────────────────────────────────────────────────
-- open_buy_object_modal  — open the purchase confirmation modal
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("open_buy_object_modal", function(_, cb)
    decorate:openBuyObjectModal()
    cb("ok")
end)
