-- ============================================================
-- client/modules/organization/house/furniture/gizmo.lua
-- (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- 3-D gizmo system for furniture placement.
-- Sends camera data to the React NUI so it can render a
-- 3-D transformation handle, then applies position/rotation
-- changes from the NUI back to the world entity.
-- ============================================================

_G.gizmo = { utils = {} }

-- ──────────────────────────────────────────────────────────
-- gizmo.handleCameraUpdate(self)
--   Spawns a thread that continuously sends the final
--   rendered camera position + rotation to the React UI
--   while the decorate mode is "gizmo".
-- ──────────────────────────────────────────────────────────
function gizmo.handleCameraUpdate(self)
    CreateThread(function()
        while true do
            if not decorate.active            then break end
            if decorate.mode ~= "gizmo"       then break end

            SendNUIMessage({
                action = "set_camera_position",
                data   = {
                    position = GetFinalRenderedCamCoord(),
                    rotation = GetFinalRenderedCamRot(2),
                },
            })

            Wait(0)
        end
    end)
end

-- ──────────────────────────────────────────────────────────
-- gizmo.selectEntity(self)
--   Selects an entity for gizmo manipulation.
--   Sends its current position + rotation to the NUI and
--   starts a watcher thread that deselects it if it disappears.
-- ──────────────────────────────────────────────────────────
function gizmo.selectEntity(self)
    local entityPos = GetEntityCoords(self.entity)
    local entityRot = GetEntityRotation(self.entity)

    SendReactMessage("set_gizmo_entity", {
        handle   = self.entity,
        position = entityPos,
        rotation = entityRot,
    })

    -- Cap Z movement to 10 m above the current position
    self.maxZ = entityPos.z + 10.0

    -- Watch for entity deletion
    CreateThread(function()
        while true do
            if not self.entity then break end
            if not DoesEntityExist(self.entity) then break end
            Wait(0)
        end
        -- Entity gone — clear the NUI selection
        SendReactMessage("set_gizmo_entity", nil)
    end)
end

-- ──────────────────────────────────────────────────────────
-- gizmo.deselectEntity(self)
--   Clears the currently selected entity.
-- ──────────────────────────────────────────────────────────
function gizmo.deselectEntity(self)
    self.entity = nil
end

-- ──────────────────────────────────────────────────────────
-- NUI callback: "select_decorate_entity"
--   Fired by the React UI when the user clicks on an entity
--   to select it for gizmo editing.
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("select_decorate_entity", function(_, cb)
    cb(1)

    if decorate.mode ~= "gizmo" then
        return Debug("gizmo:selectEntity gizmo mode is not enabled, so we do not select entity")
    end

    decorate:selectEntity()
end)

-- ──────────────────────────────────────────────────────────
-- gizmo.setEditorMode(self, modeData)
--   Tells the React NUI which gizmo editing mode is active
--   (translate / rotate / scale).
-- ──────────────────────────────────────────────────────────
function gizmo.setEditorMode(self, modeData)
    SendReactMessage("set_gizmo_editor_mode", modeData)
end

-- NUI callback: "set_gizmo_editor_mode"
RegisterNUICallback("set_gizmo_editor_mode", function(payload, cb)
    cb(1)
    gizmo:setEditorMode(payload)
end)

-- ──────────────────────────────────────────────────────────
-- gizmo.updateGizmoEntity(self)
--   Re-syncs the selected entity's current world transform
--   to the NUI.
-- ──────────────────────────────────────────────────────────
function gizmo.updateGizmoEntity(self)
    if not (self.entity and DoesEntityExist(self.entity)) then
        return Error("updateGizmoEntity", "Entity does not exist", self.entity)
    end

    SendReactMessage("set_gizmo_entity", {
        handle   = self.entity,
        position = GetEntityCoords(self.entity),
        rotation = GetEntityRotation(self.entity),
    })
end

-- ──────────────────────────────────────────────────────────
-- NUI callback: "move_entity"
--   The React UI sends updated position/rotation; apply them
--   to the entity in the world.
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("move_entity", function(payload, cb)
    cb(1)

    if not (payload.handle and DoesEntityExist(payload.handle)) then
        return Error("move_entity", "Entity does not exist", payload.handle)
    end

    -- Apply position (clamped to maxZ)
    if payload.position then
        payload.position.z = math.min(payload.position.z, gizmo.maxZ)
        SetEntityCoordsNoOffset(
            payload.handle,
            payload.position.x, payload.position.y, payload.position.z,
            false, false, false
        )
    end

    -- Apply rotation
    if payload.rotation then
        SetEntityRotation(
            payload.handle,
            payload.rotation.x, payload.rotation.y, payload.rotation.z,
            0, false
        )
    end

    SendReactMessage("set_gizmo_entity", payload)
end)
