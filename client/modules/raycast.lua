-- ============================================================
-- client/modules/raycast.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Raycast module.  Provides a gameplay-camera crosshair probe
-- and a free-camera probe used by the furniture/gizmo system.
-- Both modes expose coords / entity / hit on a shared state
-- table and call a per-frame callback.
-- ============================================================

-- GLM helpers (FiveM native math library)
local glmSinCos  = require("glm").sincos
local glmRad     = require("glm").rad
local mathAbs    = math.abs

-- Cached native references for speed
local getFinalCamCoord  = GetFinalRenderedCamCoord
local getFinalCamRot    = GetFinalRenderedCamRot
local getEntityCoords   = GetEntityCoords
local disableAllControls = DisableAllControlActions
local drawLine          = DrawLine
local getCamMatrix      = GetCamMatrix
local createCamera      = Utils.CreateCamera
local handleFlyCam      = Utils.HandleFlyCam
local drawScaleform     = Utils.DrawScaleform

-- ──────────────────────────────────────────────────────────
-- Global raycast namespace
-- ──────────────────────────────────────────────────────────
_G.raycast = {
    cameraOptions = {
        controls = { "up", "right", "forward" },
    },
}

-- ──────────────────────────────────────────────────────────
-- raycast.getForwardVector(self)
--   Computes the camera's forward direction vector using GLM
--   sincos on the final rendered camera rotation.
--   Returns a vec3 pointing in the camera's forward direction.
-- ──────────────────────────────────────────────────────────
function raycast.getForwardVector(self)
    local camRot = getFinalCamRot(2)

    -- Convert rotation to radians with GLM
    local sinZ, cosZ = glmSinCos(glmRad(camRot))
    local absCosCamX = mathAbs(cosZ.x)

    return vec3(
        -sinZ.z * absCosCamX,
         cosZ.z * absCosCamX,
         sinZ.x
    )
end

-- ──────────────────────────────────────────────────────────
-- raycast.gameplayCamera(self, fn, controls, entityFilter)
--   Runs a per-frame raycast loop using the gameplay camera.
--   Fires an expensive synchronous LOS probe from the camera
--   50 m ahead, draws a marker and line at the hit point, then
--   calls `fn(self)` each frame until self.active = false.
--
--   self      – the raycast state table
--   fn        – per-frame callback(self)
--   controls  – optional array of extra control name strings
--   entityFilter – shape-test entity filter flags (default 17)
-- ──────────────────────────────────────────────────────────
function raycast.gameplayCamera(self, fn, controls, entityFilter)
    assert(type(fn) == "function",
           "raycast:gameplayCamera ::: fn must be a function")

    if not controls then controls = {} end
    entityFilter = entityFilter or 17

    -- Resolve controls and build instructional scaleform
    self.controls  = Utils.GetControls(controls)
    self.scaleform = Utils.CreateInstructional(self.controls)
    self.active    = true

    while true do
        if not self.active then break end

        -- Disable player firing while in raycast mode
        DisablePlayerFiring(cache.playerId, true)

        -- Get camera origin and forward point
        local camPos    = getFinalCamCoord()
        local fwdVec    = self:getForwardVector()
        local farPoint  = camPos + fwdVec * 50.0

        -- Probe the scene
        local rayHandle = StartExpensiveSynchronousShapeTestLosProbe(
            camPos.x,   camPos.y,   camPos.z,
            farPoint.x, farPoint.y, farPoint.z,
            entityFilter, cache.ped, 4
        )

        local pedPos = getEntityCoords(cache.ped)
        local _, hitType, hitCoords, _, hitMaterial, hitEntity =
            GetShapeTestResultIncludingMaterial(rayHandle)

        self.coords = hitCoords
        self.entity = (hitMaterial ~= 0 and hitMaterial) and hitEntity or nil
        self.hit    = (hitType == 1)

        -- Draw a marker + line at the hit point
        if self.hit then
            DrawMarker(
                28,
                hitCoords.x, hitCoords.y, hitCoords.z,
                0.0, 0.0, 0.0,
                0.0, 0.0, 0.0,
                0.2, 0.2, 0.2,
                255, 42, 24, 100,
                false, false, 0, true, false, false, false
            )
            DrawLine(
                pedPos.x, pedPos.y, pedPos.z,
                hitCoords.x, hitCoords.y, hitCoords.z,
                255, 42, 24, 100
            )
        end

        fn(self)
        drawScaleform(self.scaleform)
        self.lastCoords = self.coords
        Wait(0)
    end
end

-- ──────────────────────────────────────────────────────────
-- raycast.freeCamera(self, fn, extraControls)
--   Creates a scripted fly-cam and runs a per-frame raycast
--   loop from that camera.  Draws a 3-axis crosshair at the
--   hit point as three short red lines, then calls fn(self).
--
--   self         – the raycast state table
--   fn           – per-frame callback(self)
--   extraControls – optional array of extra control name strings
-- ──────────────────────────────────────────────────────────
function raycast.freeCamera(self, fn, extraControls)
    assert(type(fn) == "function",
           "raycast:camera ::: fn must be a function")

    -- Position the scripted camera 2 m in front of the ped
    local _, forwardVec, _, pedPos = GetEntityMatrix(cache.ped)
    local camStartPos = pedPos + forwardVec * 2

    local camRot = GetEntityRotation(cache.ped)
    self.camRot  = camRot
    self.camPos  = camStartPos

    self.camera = createCamera(
        "DEFAULT_SCRIPTED_CAMERA",
        self.camPos,
        self.camRot,
        true
    )

    self.active = true

    -- Disable player control while in free-camera mode
    SetPlayerControl(cache.playerId, false, 0)

    -- Build merged controls list (default + extras)
    local allControlNames = table.deepclone(self.cameraOptions.controls)
    if extraControls then
        for _, ctrl in pairs(extraControls) do
            allControlNames[#allControlNames + 1] = ctrl
        end
    end

    self.controls  = Utils.GetControls(allControlNames)
    self.scaleform = Utils.CreateInstructional(self.controls)

    while true do
        if not self.active then break end

        disableAllControls(0)

        -- Update camera position / rotation from fly-cam input
        self.camPos, self.camRot = handleFlyCam(self.camera)

        -- Cast a ray from cam forward 100 m using the cam's forward axis
        local _, forwardAxis, _, _ = getCamMatrix(self.camera)
        local farPoint = vec3(
            self.camPos.x + forwardAxis.x * 100.0,
            self.camPos.y + forwardAxis.y * 100.0,
            self.camPos.z + forwardAxis.z * 100.0
        )

        local rayHandle = StartExpensiveSynchronousShapeTestLosProbe(
            self.camPos.x, self.camPos.y, self.camPos.z,
            farPoint.x,    farPoint.y,    farPoint.z,
            17, cache.ped, 4
        )

        local _, hitType, hitCoords, _, _, hitEntity =
            GetShapeTestResultIncludingMaterial(rayHandle)

        self.coords = hitCoords
        self.entity = hitEntity
        self.hit    = (hitType == 1)

        -- Draw a 3-axis red crosshair at the hit point
        local hx, hy, hz = hitCoords.x, hitCoords.y, hitCoords.z
        DrawLine(hx - 0.3, hy,       hz, hx + 0.3, hy,       hz, 255, 0, 0, 255)
        DrawLine(hx,       hy,       hz, hx,        hy,       hz + 0.3, 255, 0, 0, 255)
        DrawLine(hx,       hy - 0.3, hz, hx,        hy + 0.3, hz, 255, 0, 0, 255)

        drawScaleform(self.scaleform)
        fn(self)
        Wait(0)
    end
end

-- ──────────────────────────────────────────────────────────
-- raycast.destroy(self)
--   Stops the active raycast loop and cleans up the scripted
--   camera (if any), then restores player control.
-- ──────────────────────────────────────────────────────────
function raycast.destroy(self)
    self.active = false

    if self.camera then
        Utils.DestroyFlyCam(self.camera)
        self.camera = nil
        SetPlayerControl(cache.playerId, true, 0)
    end
end

-- ──────────────────────────────────────────────────────────
-- onResourceStop — destroy any active raycast on restart
-- ──────────────────────────────────────────────────────────
AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        raycast:destroy()
    end
end)
