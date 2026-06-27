-- ============================================================
-- client/modules/creator/helper.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Creator tool helpers:
--   RayCastSelector  — interactive fly-cam point/shell/exit picker
--   RayCastGetMLO    — interactive fly-cam MLO door selector
--   spawnShellPreview    (local)
--   spawnHouseObjPreview (local)
--   isInsideShell        (local, checks entity bbox)
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- local isInsideShell(shellEntity, testPoint) → bool
--   Returns true when testPoint.x is within the X AABB of
--   the shell entity.  (Simple cheap check used for "exit".)
-- ──────────────────────────────────────────────────────────
local function isInsideShell(shellEntity, testPoint)
    local model  = GetEntityModel(shellEntity)
    local lo, hi = GetModelDimensions(model)
    local origin = GetEntityCoords(shellEntity)

    local halfX = hi.x - lo.x
    local halfY = hi.y - lo.y
    local halfZ = hi.z - lo.z

    local bboxMin = vec3(origin.x - halfX, origin.y - halfY, origin.z - halfZ)
    -- Simple X-axis check (the original code only tested X)
    return testPoint.x >= bboxMin.x
end

-- ──────────────────────────────────────────────────────────
-- Draw-text labels (resolved at load)
-- ──────────────────────────────────────────────────────────
local POINT_LABELS = {
    entry       = i18n.t("drawtext.entry_point"),
    shell       = i18n.t("drawtext.shell_point"),
    exit        = i18n.t("drawtext.exit_point"),
    customHouse = i18n.t("drawtext.house_point"),
}

-- ──────────────────────────────────────────────────────────
-- local spawnShellPreview(coords, tier, heading) → entity
--   Creates a ghost shell object for the creator fly-cam.
-- ──────────────────────────────────────────────────────────
local function spawnShellPreview(coords, tier, heading)
    local shellData = Config.Shells[tier] or Config.Shells[1]
    local hash      = joaat(shellData.model)
    lib.requestModel(hash, Config.DefaultRequestModelTimeout)

    local obj = CreateObject(hash,
        coords.x, coords.y, coords.z, false, true, true)

    SetEntityCollision(obj, false, false)
    SetEntityCompletelyDisableCollision(obj, true, false)
    FreezeEntityPosition(obj, true)
    SetEntityInvincible(obj, true)
    SetEntityDrawOutline(obj, true)
    SetModelAsNoLongerNeeded(hash)
    SetEntityDrawOutlineColor(0, 255, 0, 255)

    if heading then SetEntityHeading(obj, heading) end
    return obj
end

-- ──────────────────────────────────────────────────────────
-- local spawnHouseObjPreview(coords, tier, heading, isIsland) → entity
-- ──────────────────────────────────────────────────────────
local function spawnHouseObjPreview(coords, tier, heading, isIsland)
    local pool    = (isIsland and Config.Islands) or Config.HouseObjects
    local objData = pool[tier] or pool[1]
    local hash    = joaat(objData.model)
    lib.requestModel(hash, Config.DefaultRequestModelTimeout)

    local obj = CreateObject(hash,
        coords.x, coords.y, coords.z, false, true, true)

    SetEntityCollision(obj, false, false)
    SetEntityCompletelyDisableCollision(obj, true, false)
    FreezeEntityPosition(obj, true)
    SetEntityInvincible(obj, true)
    SetEntityDrawOutline(obj, true)
    SetModelAsNoLongerNeeded(hash)
    SetEntityDrawOutlineColor(0, 255, 0, 255)

    if heading then SetEntityHeading(obj, heading) end
    return obj
end

-- ──────────────────────────────────────────────────────────
-- RayCastSelector(pointType, options) → result
--
--   Interactive fly-cam used by the creator to place:
--     "entry"       — entry point (ped ghost, vec4)
--     "board"       — mission board position (board object, vec4)
--     "shell"       — shell interior (shell preview, tier + vec4)
--     "exit"        — exit point inside a shell (ped ghost, vec4)
--     "customHouse" — custom house object (house preview, tier + vec4)
--
--   Returns:
--     - For "shell" / "customHouse": tier, vec4
--     - For all others: vec4 (or false on cancel)
-- ──────────────────────────────────────────────────────────
function RayCastSelector(pointType, options)
    local pedHandle   = cache.ped
    local _, fwd, up, pos = GetEntityMatrix(pedHandle)
    local heading     = GetEntityHeading(pedHandle)

    -- Position camera above / in front of player
    local camPos = pos + (up * 2)

    if options and options.camOffset then
        camPos = pos + options.camOffset
    end
    if pointType == "shell" then
        camPos = pos - Config.MinZOffset
    elseif pointType == "exit" then
        local exitCoords = options.coords
        camPos = vec3(exitCoords.x, exitCoords.y, exitCoords.z) + (up * 2)
    end

    local camRot  = vector3(-35.0, 0.0, 0.0)
    local cam     = Utils.CreateCamera("DEFAULT_SCRIPTED_CAMERA", camPos, camRot, true)

    -- Build control list
    local controlKeys = { "done", "cancel", "up", "right", "forward", "rotate_z" }
    if pointType == "shell" then
        table.insert(controlKeys, "increase_z")
        table.insert(controlKeys, "change_shell")
        table.insert(controlKeys, "decrease_z")
    end

    local controlDefs  = Utils.GetControls(controlKeys)
    local instructional = Utils.CreateInstructional(controlDefs)
    EnabledMouseMovement = true

    local confirmedResult = nil    -- final vec4 result
    local previewEntity   = nil    -- ghost object
    local exitShellEntity = nil    -- shell used for "exit" containment check
    local currentHeading  = heading
    local zOverride       = nil
    local currentTier     = 1
    local houseObjectPool = Config.HouseObjects

    -- Spawn appropriate ghost entity
    if pointType == "entry" then
        confirmedResult = vec4(pos.x, pos.y, pos.z, heading)
        previewEntity   = ClonePed(pedHandle, false, false, true)
        SetEntityAlpha(previewEntity, Config.CreatorAlpha, false)

    elseif pointType == "board" then
        local hash = joaat(Config.BoardObject)
        lib.requestModel(hash, Config.DefaultRequestModelTimeout)
        previewEntity = CreateObject(
            joaat(Config.BoardObject), pos.x, pos.y, pos.z, false, true, true)
        SetEntityAlpha(previewEntity, Config.CreatorAlpha, false)
        SetModelAsNoLongerNeeded(hash)

    elseif pointType == "shell" then
        previewEntity = spawnShellPreview(pos, currentTier, heading)

    elseif pointType == "exit" then
        previewEntity = ClonePed(pedHandle, false, false, true)
        SetEntityAlpha(previewEntity, Config.CreatorAlpha, false)
        exitShellEntity = spawnShellPreview(options.coords, options.tier, options.coords.w)
        currentHeading = options.coords.w

    elseif pointType == "customHouse" then
        local isIsland = options and options.isIsland
        if isIsland and Config.Islands then
            houseObjectPool = Config.Islands
        end
        previewEntity = spawnHouseObjPreview(pos, currentTier, heading, isIsland)
    end

    -- ── Done / cancel helpers ──────────────────────────────
    local function captureResult()
        lib.hideMenu()
        local isObjectType = (pointType == "entry" or pointType == "board"
            or pointType == "shell" or pointType == "customHouse")

        if isObjectType then
            local objCoords = GetEntityCoords(previewEntity)
            confirmedResult = vec4(objCoords.x, objCoords.y, objCoords.z,
                GetEntityHeading(previewEntity))
            DeleteEntity(previewEntity)
        elseif pointType == "exit" then
            local objCoords = GetEntityCoords(previewEntity)
            confirmedResult = vec4(objCoords.x, objCoords.y, objCoords.z,
                GetEntityHeading(previewEntity))
            DeleteEntity(exitShellEntity)
            DeleteEntity(previewEntity)
        end
    end

    local function finish()
        captureResult()
        EnableAllControlActions(0)
        Utils.DestroyFlyCam(cam)

        if pointType == "shell" or pointType == "customHouse" then
            return currentTier, confirmedResult
        end
        return confirmedResult
    end

    -- ── Main loop ─────────────────────────────────────────
    local hitCoords   -- raycast hit position
    while true do
        Wait(0)
        DisableAllControlActions(0)
        Utils.HandleFlyCam(cam)

        local _, camRight, camUp, camPos2 = GetCamMatrix(cam)

        -- Compute raycast hit or shell position
        if pointType == "shell" then
            hitCoords = camPos2 + (camRight * 25.0)
        else
            local rayEnd = {
                x = camPos2.x + camRight.x * 100.0,
                y = camPos2.y + camRight.y * 100.0,
                z = camPos2.z + camRight.z * 100.0,
            }
            local rayHandle = StartExpensiveSynchronousShapeTestLosProbe(
                camPos2.x, camPos2.y, camPos2.z,
                rayEnd.x, rayEnd.y, rayEnd.z,
                4294967295, previewEntity, 7)
            local _, hit, hitPos, _, _ = GetShapeTestResult(rayHandle)
            hitCoords = hitPos
        end

        -- ── Confirm (done key) ───────────────────────────
        if IsDisabledControlJustPressed(0, ActionControls.done.codes[1]) then
            if pointType == "exit" then
                -- Must be inside the shell
                if isInsideShell(exitShellEntity, hitCoords) then
                    return finish()
                else
                    Notification(i18n.t("coords_not_in_shell"), "error")
                end
            else
                local needsInside = Config.NeedToBeInsidePoints and
                    Config.NeedToBeInsidePoints[pointType]
                if not needsInside then
                    return finish()
                else
                    if creator:isInPoints(hitCoords) then
                        return finish()
                    else
                        Notification(i18n.t("polyzone_nearby"), "error")
                    end
                end
            end
        end

        -- ── Cancel ──────────────────────────────────────
        if IsDisabledControlJustPressed(0, ActionControls.cancel.codes[1])
           or IsDisabledControlJustPressed(0, 322) then
            captureResult()
            EnableAllControlActions(0)
            Utils.DestroyFlyCam(cam)
            return false
        end

        -- ── Shell / customHouse extra controls ───────────
        local isShellOrHouse = (pointType == "shell" or pointType == "customHouse")
        if isShellOrHouse then
            -- Decrease Z
            if IsDisabledControlPressed(0, ActionControls.increase_z.codes[1]) then
                zOverride = (zOverride or hitCoords.z) - 0.1
            end
            -- Increase Z
            if IsDisabledControlPressed(0, ActionControls.increase_z.codes[2]) then
                zOverride = (zOverride or hitCoords.z) + 0.1
            end

            -- Cycle tier forward
            local maxTier = (pointType == "shell")
                and #Config.Shells or #houseObjectPool
            if IsDisabledControlJustPressed(0, ActionControls.change_shell.codes[1]) then
                local currentCoords = GetEntityCoords(previewEntity)
                DeleteEntity(previewEntity)
                currentTier = (currentTier + 1 <= maxTier) and (currentTier + 1) or 1
                previewEntity = (pointType == "shell")
                    and spawnShellPreview(currentCoords, currentTier, currentHeading)
                    or  spawnHouseObjPreview(currentCoords, currentTier, currentHeading,
                            options and options.isIsland)
            end

            -- Cycle tier backward
            if IsDisabledControlJustPressed(0, ActionControls.change_shell.codes[2]) then
                local currentCoords = GetEntityCoords(previewEntity)
                DeleteEntity(previewEntity)
                currentTier = (currentTier - 1 > 0) and (currentTier - 1) or maxTier
                previewEntity = (pointType == "shell")
                    and spawnShellPreview(currentCoords, currentTier, currentHeading)
                    or  spawnHouseObjPreview(currentCoords, currentTier, currentHeading,
                            options and options.isIsland)
            end
        end

        -- ── Rotate Z ────────────────────────────────────
        local rotatable = (pointType == "entry" or pointType == "board"
            or pointType == "shell" or pointType == "exit"
            or pointType == "customHouse")
        if rotatable then
            if IsDisabledControlPressed(0, ActionControls.rotate_z.codes[1]) then
                currentHeading = currentHeading + 1.0
            end
            if IsDisabledControlPressed(0, ActionControls.rotate_z.codes[2]) then
                currentHeading = currentHeading - 1.0
            end
        end

        -- ── Update ghost entity position / heading ───────
        if previewEntity then
            SetEntityCoords(previewEntity,
                hitCoords.x, hitCoords.y,
                zOverride or hitCoords.z,
                false, false, false, false)
            SetEntityHeading(previewEntity, currentHeading)
        end

        -- ── Visual aids ─────────────────────────────────
        if pointType ~= "shell" and hitCoords then
            DrawLine(hitCoords.x, hitCoords.y, hitCoords.z,
                hitCoords.x, hitCoords.y, hitCoords.z + 10.0,
                255, 0, 0, 255)
            DrawText3Ds(hitCoords.x, hitCoords.y, hitCoords.z + 1.0,
                POINT_LABELS[pointType] or "")
        end

        Utils.DrawScaleform(instructional)
    end
end

-- ──────────────────────────────────────────────────────────
-- RayCastGetMLO() → doors[] | false
--
--   Interactive fly-cam for selecting MLO door entities.
--   Returns a table of { hash, coords, h, locked, obj, tempHandle }
--   or false on cancel.
-- ──────────────────────────────────────────────────────────
function RayCastGetMLO()
    local pedHandle = cache.ped
    local _, fwd, up, pos = GetEntityMatrix(pedHandle)
    local camPos    = pos + (up * 2)
    local camRot    = vector3(-35.0, 0.0, 0.0)
    local cam       = Utils.CreateCamera("DEFAULT_SCRIPTED_CAMERA", camPos, camRot, true)

    local controls  = Utils.GetControls({ "done", "cancel", "add_point", "undo_point" })
    local scaleform = Utils.CreateInstructional(controls)
    EnabledMouseMovement = true

    local doors       = {}
    local lastAdded   = false   -- coords of the last added entity (dedup guard)

    while true do
        Wait(0)
        DisableAllControlActions(0)
        Utils.HandleFlyCam(cam)

        local _, camRight, _, camPos2 = GetCamMatrix(cam)

        -- Raycast
        local rayEnd = {
            x = camPos2.x + camRight.x * 100.0,
            y = camPos2.y + camRight.y * 100.0,
            z = camPos2.z + camRight.z * 100.0,
        }
        local rayHandle = StartShapeTestRay(
            camPos2.x, camPos2.y, camPos2.z,
            rayEnd.x, rayEnd.y, rayEnd.z,
            -1, pedHandle, 0)
        local _, hit, hitPos, _, hitEntity = GetShapeTestResult(rayHandle)

        -- ── Done ───────────────────────────────────────
        if IsDisabledControlJustPressed(0, ActionControls.done.codes[1]) then
            if #doors > 0 then
                EnableAllControlActions(0)
                Utils.DestroyFlyCam(cam)
                for _, d in pairs(doors) do SetEntityDrawOutline(d.tempHandle, false) end
                return doors
            else
                Notification(i18n.t("choose_door"), "error")
            end
        end

        -- ── Cancel ─────────────────────────────────────
        if IsDisabledControlJustPressed(0, ActionControls.cancel.codes[1])
           or IsDisabledControlJustPressed(0, 322) then
            EnableAllControlActions(0)
            Utils.DestroyFlyCam(cam)
            for _, d in pairs(doors) do SetEntityDrawOutline(d.tempHandle, false) end
            return false
        end

        -- ── Add door ───────────────────────────────────
        if IsDisabledControlJustPressed(0, ActionControls.add_point.codes[1]) then
            if hitEntity then
                if IsEntityAnObject(hitEntity) then
                    local coords = GetEntityCoords(hitEntity)
                    if lastAdded and coords == lastAdded then
                        Notification(i18n.t("door_already_added"), "info")
                    else
                        table.insert(doors, {
                            hash       = GetEntityModel(hitEntity),
                            coords     = coords,
                            h          = GetEntityHeading(hitEntity),
                            locked     = true,
                            obj        = nil,
                            tempHandle = hitEntity,
                        })
                        lastAdded = coords
                        Notification(i18n.t("new_door"), "success")
                        SetEntityDrawOutline(hitEntity, true)
                        SetEntityDrawOutlineColor(0, 255, 0, 255)
                    end
                end
            else
                Notification(i18n.t("choose_door"), "error")
            end
        end

        -- ── Undo last door ─────────────────────────────
        if IsDisabledControlJustPressed(0, ActionControls.undo_point.codes[1]) then
            if #doors > 0 then
                local last = doors[#doors]
                SetEntityDrawOutline(last.tempHandle, false)
                table.remove(doors, #doors)
                lastAdded = false
                Notification(i18n.t("door_removed"), "success")
            else
                Notification(i18n.t("no_doors"), "error")
            end
        end

        -- ── Highlight hovered entity ───────────────────
        if hitEntity and IsEntityAnObject(hitEntity) then
            local ec = GetEntityCoords(hitEntity)
            DrawMarker(21, ec.x, ec.y, ec.z + 1,
                0, 0, 0,   0, 180.0, 0,   1, 1, 1,
                255, 0, 0, 255,
                false, true, 2, nil, nil, false)
        end

        -- ── Aim line ───────────────────────────────────
        if hitPos then
            DrawLine(hitPos.x, hitPos.y, hitPos.z,
                hitPos.x, hitPos.y, hitPos.z + 1.0,
                255, 0, 0, 255)
        end

        Utils.DrawScaleform(scaleform)
    end
end
