-- ============================================================
-- client/modules/organization/house/ipl.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- IPL (Interior Placement Layer) house showcase and door-anim
-- helpers.  Lets a player browse configured house IPL interiors
-- using a fly-cam, then confirm or cancel their selection.
-- ============================================================

CreatorStartedPosition = nil   -- Saved world position before entering showcase

-- ──────────────────────────────────────────────────────────
-- ShowcaseOfIplHouse(iplIndex)
--   Loads and showcases the IPL interior at Config.IplData[iplIndex].
--   The player uses mouse-look to inspect and arrow keys to
--   cycle through available IPL options.
--   Returns the callback from the "done" action on confirm,
--   or nil if the player cancels.
-- ──────────────────────────────────────────────────────────
function ShowcaseOfIplHouse(iplIndex)
    -- Default to the first IPL if no index given
    local idx    = iplIndex or 1
    local iplCfg = Config.IplData[idx]

    -- Apply the default theme if the IPL has one configured
    local iplExport = iplCfg.export
    if iplCfg.defaultTheme and iplExport then
        local exportObj = iplExport()
        exportObj.Style.Set(exportObj.Style.Theme[iplCfg.defaultTheme], true)
    end

    -- Fade out and wait
    DoScreenFadeOut(300)
    local playerPed = cache.ped
    Wait(500)

    local iplCoords = iplCfg.iplCoords
    if not iplCoords then return end

    Wait(300)

    -- Hide the player ped and move them to the IPL interior
    SetEntityVisible(playerPed, false)
    SetEntityCoords(playerPed, vec3(iplCoords.x, iplCoords.y, iplCoords.z + 1.0))
    ClearFocus()

    -- Create a fly-cam inside the IPL
    local cam = Utils.CreateCamera(
        "DEFAULT_SCRIPTED_CAMERA",
        vec3(iplCoords.x, iplCoords.y, iplCoords.z + 1.0),
        vector3(0.0, 0.0, 0.0),
        true,   -- activate
        false   -- no entity tracking
    )

    DoScreenFadeIn(200)

    -- ── Restore function (exit showcase) ──────────────────
    local function exitShowcase()
        DoScreenFadeOut(300)
        Wait(500)
        SetEntityCoords(playerPed, CreatorStartedPosition)
        SetEntityVisible(playerPed, true)
        EnableAllControlActions(0)
        Utils.DestroyFlyCam(cam)
        Wait(1000)
        DoScreenFadeIn(300)
        -- Returns control back to the caller via iplIndex being nil
        return iplIndex
    end

    -- ── Pre-compute next/previous IPL indices ──────────────
    local totalIpls = #Config.IplData

    local nextIdx = idx + 1
    if nextIdx > totalIpls then nextIdx = 1 end

    local prevIdx = idx - 1
    if prevIdx < 1 then prevIdx = totalIpls end

    -- ── Build instructional button scaleform ───────────────
    local controls  = Utils.GetControls({"rightApt", "done", "cancel", "leftApt"})
    local scaleform = Utils.CreateInstructional(controls)

    EnabledMouseMovement = true

    -- ── Main showcase loop ─────────────────────────────────
    while cam do
        Wait(0)

        -- Mouse-look only (no keyboard movement)
        Utils.HandleFlyCam(cam, { mouse = true, keyboard = false })

        -- "Done" key → confirm selection
        if IsDisabledControlJustPressed(0, ActionControls.done.codes[1]) then
            return exitShowcase()
        end

        -- "Cancel" key or ESC → abandon without selecting
        local cancelPressed = IsDisabledControlPressed(0, ActionControls.cancel.codes[1])
                           or IsDisabledControlJustPressed(0, 322)

        if cancelPressed then
            DoScreenFadeOut(300)
            Wait(1000)
            Utils.DestroyFlyCam(cam)
            SetEntityCoords(playerPed, CreatorStartedPosition)
            SetEntityVisible(playerPed, true, false)
            Wait(500)
            DoScreenFadeIn(300)
            return nil
        end

        -- Left arrow → previous IPL
        if IsDisabledControlPressed(0, Keys.LEFT) then
            DoScreenFadeOut(300)
            Wait(500)
            Utils.DestroyFlyCam(cam)
            return ShowcaseOfIplHouse(prevIdx)
        end

        -- Right arrow → next IPL
        if IsDisabledControlPressed(0, Keys.RIGHT) then
            DoScreenFadeOut(300)
            Wait(500)
            Utils.DestroyFlyCam(cam)
            return ShowcaseOfIplHouse(nextIdx)
        end

        Utils.DrawScaleform(scaleform)
    end
end

-- ──────────────────────────────────────────────────────────
-- DoorAnim()
--   Plays the keycard-exit animation on the local player ped.
--   Used for the house door-open effect.
-- ──────────────────────────────────────────────────────────
function DoorAnim()
    lib.playAnim(cache.ped, "anim@heists@keycard@", "exit")
    Wait(400)
    ClearPedTasks(cache.ped)
end
