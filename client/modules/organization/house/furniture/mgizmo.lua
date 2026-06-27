-- ============================================================
-- client/modules/organization/house/furniture/mgizmo.lua
-- (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Mouse/cursor-based gizmo ("mgizmo") for furniture placement.
-- Follows the cursor hit position on LMB hold and supports
-- Z-axis rotation via configured control keys.
-- ============================================================

-- Cached native references
local isControlPressed         = IsControlPressed
local isDisabledControlPressed = IsDisabledControlPressed
local getCursorHitCoords       = Utils.getCursorHitCoords
local setEntityCoords          = SetEntityCoords
local setEntityHeading         = SetEntityHeading

_G.mgizmo = {}

-- Rotation control codes from ActionControls (rotate_z key)
local rotateZCodes = ActionControls.rotate_z.codes

-- ──────────────────────────────────────────────────────────
-- mgizmo.selectEntity(self)
--   Called when an entity is selected for mouse-gizmo editing.
--   Shows the rotate-Z instructional hint and saves the
--   entity's current position as lastCoords.
-- ──────────────────────────────────────────────────────────
function mgizmo.selectEntity(self)
    decorate:instructional({
        { key = "rotate_z", label = "Rotate Z +/-" },
    })
    self.lastCoords = GetEntityCoords(self.entity)
end

-- ──────────────────────────────────────────────────────────
-- mgizmo.deselectEntity(self)
--   Clears the selection and removes the instructional overlay.
-- ──────────────────────────────────────────────────────────
function mgizmo.deselectEntity(self)
    if not self.entity then return end

    self.entity      = nil
    self.decorateData = nil
    decorate:instructional()
end

-- ──────────────────────────────────────────────────────────
-- mgizmo.updateEntity(self)
--   Called every frame while LMB is held.
--   Checks rotate-Z keys, then moves the entity to the
--   cursor's world hit position if it changed.
-- ──────────────────────────────────────────────────────────
function mgizmo.updateEntity(self)
    if not self.entity then return end

    -- Disable rotation control actions to prevent camera movement
    for i = 1, #rotateZCodes, 1 do
        DisableControlAction(0, rotateZCodes[i], true)
    end

    -- Rotate Z+ (key[1])
    if isDisabledControlPressed(0, rotateZCodes[1]) then
        setEntityHeading(self.entity, GetEntityHeading(self.entity) + 0.3)
    elseif isDisabledControlPressed(0, rotateZCodes[2]) then
        -- Rotate Z- (key[2])
        setEntityHeading(self.entity, GetEntityHeading(self.entity) - 0.3)
    end

    -- Move the entity to where the cursor is pointing
    local hitCoords, hitEntity = getCursorHitCoords(self.entity)
    if not hitCoords or not hitEntity then
        return Debug("mgizmo:updateEntity hitCoords or hitEntity is nil")
    end

    if self.lastCoords ~= hitCoords then
        self.lastCoords = hitCoords
        setEntityCoords(self.entity, hitCoords.x, hitCoords.y, hitCoords.z)
    end
end

-- ──────────────────────────────────────────────────────────
-- mgizmo.loop(self)
--   Spawns the main mgizmo input loop.
--   LMB just pressed  → select entity under cursor
--   LMB held          → drag / rotate entity
--   LMB just released → deselect entity
-- ──────────────────────────────────────────────────────────
function mgizmo.loop(self)
    CreateThread(function()
        while true do
            if not decorate.active        then break end
            if decorate.mode ~= "mgizmo"  then break end

            Wait(0)

            -- Left mouse button (control 24 = INPUT_ATTACK)
            local lmbJustPressed =
                IsControlJustPressed(0, 24)
             or IsDisabledControlJustPressed(0, 24)

            local lmbHeld =
                isControlPressed(0, 24)
             or isDisabledControlPressed(0, 24)

            local lmbJustReleased =
                IsControlJustReleased(0, 24)
             or IsDisabledControlJustReleased(0, 24)

            if lmbJustPressed then
                -- Select entity at cursor
                decorate:selectEntity(self.entity)

            elseif lmbHeld then
                -- Drag entity with cursor
                self:updateEntity()

            elseif lmbJustReleased then
                -- Confirm and deselect
                self:deselectEntity()
            end
        end
    end)
end
