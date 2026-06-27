-- ============================================================
-- client/main.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Entry-point for the client side.  Handles NUI initialisation,
-- sound callbacks, illegal-medic NPCs, front-door camera,
-- and vault-code management.
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- SendReactMessage(action, data)
--   Wrapper that sends a structured NUI message to the React
--   front-end.  All UI communication goes through this.
-- ──────────────────────────────────────────────────────────
function SendReactMessage(action, data)
    SendNUIMessage({ action = action, data = data })
end

-- ──────────────────────────────────────────────────────────
-- NUI callback: "notification"
--   Triggered by the UI when it wants to show a notification
--   on-screen (e.g. toasts from the React layer).
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("notification", function(payload, cb)
    Notification(payload.message, payload.type)
    cb("ok")
end)

-- ──────────────────────────────────────────────────────────
-- Local: buildLocalePayload()
--   Assembles the locale name and translation resource table
--   that is sent to the UI during initialisation.
--   Returns (languageName, resourcesTable).
-- ──────────────────────────────────────────────────────────
local function buildLocalePayload()
    local languageName = Config.Locale
    local resources    = {}
    resources[languageName] = { translation = _T }
    return languageName, resources
end

-- ──────────────────────────────────────────────────────────
-- CloseUI()
--   Closes all open UI modules (decorate, creator, bossmenu,
--   interaction, tablet, garage, graffiti) and releases NUI
--   focus.
-- ──────────────────────────────────────────────────────────
function CloseUI()
    decorate:close()
    creator:close()
    bossmenu:close()
    interaction:close()
    tablet:close()

    if CurrentGarage then
        CurrentGarage:close()
    end

    CloseGraffitiDialog()
    SetNuiFocus(false, false)
end

-- ──────────────────────────────────────────────────────────
-- NUI callback: "close"
--   The React UI requests that all panels be closed.
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("close", function(_, cb)
    CloseUI()
    cb("ok")
end)

-- ──────────────────────────────────────────────────────────
-- NUI callback: "initialized"
--   Called once by the React app when it has mounted.
--   Sends the full config payload back so the UI can render
--   correctly, then notifies the server that the player has
--   connected.  Also checks if the player is currently
--   inside a house and re-enters if so.
-- ──────────────────────────────────────────────────────────
local uiInitialized = false   -- Prevents double-initialisation

RegisterNUICallback("initialized", function(_, cb)
    -- Wait until translations are loaded
    while not _T do
        Wait(200)
    end

    -- Guard: already initialised
    if uiInitialized then
        Debug("Already initialized")
        return cb("ok")
    end

    -- Build and send the full UI configuration
    local languageName, resources = buildLocalePayload()

    SendReactMessage("onUiReady", {
        languageName = languageName,
        resources    = resources,
        config       = {
            debug              = Config.Debug,
            version            = GetResourceMetadata(GetCurrentResourceName(), "version", 0),
            intl               = Config.Intl,
            soundPath          = Config.Path .. "sounds/",
            imagePath          = Config.ImagePath,
            managementButtons  = Config.ManagementButtons,
            upgrades           = Config.Upgrades,
            crimeTablet        = Config.CrimeTablet,
            missionRarity      = Config.MissionRarity,
            IllegalMedic       = Config.IllegalMedic,
            MoneyLaundering    = Config.MoneyLaundering,
            music              = Config.Music,
            musicVolume        = Config.MusicVolume,
            sellObjectCommision = Config.SellObjectCommision,
        },
    })

    uiInitialized = true

    -- Notify the server of the player connection
    TriggerServerEvent("crime:playerConnected")
    cb("ok")

    -- If there is no framework identifier, skip the house check
    if not cfr:getIdentifier() then return end

    -- Wait until the record handler is ready before checking house state
    while not RecordHandler.initialized do
        Wait(100)
    end

    -- Ask the server if the player was inside a house (e.g. after reconnect)
    local insideHouseId = lib.callback.await("crime:getHouseInside", false)

    if insideHouseId and insideHouseId ~= "nil" and insideHouseId ~= "" then
        local org = OrganizationManager:get(insideHouseId)
        if not org then
            return Error("organization not found", insideHouseId)
        end
        org:enterHouse()
    end
end)

-- ──────────────────────────────────────────────────────────
-- NUI callback: "play_sound"
--   The React front-end requests a GTA frontend sound.
--   The payload is the sound identifier string.
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("play_sound", function(soundName, cb)
    -- Respect the global sound-disable config flag
    if Config.DisableInteractSound then
        return cb("ok")
    end

    -- Map sound names to GTA frontend sound sets
    if soundName == "category_down" then
        PlaySoundFrontend(-1, "NAV_UP_DOWN",        "HUD_FRONTEND_DEFAULT_SOUNDSET",          0, 0, 1)

    elseif soundName == "item_down" then
        PlaySoundFrontend(-1, "Object_Collect_Remote", "GTAO_FM_Events_Soundset",              0, 0, 1)

    elseif soundName == "finish" then
        PlaySoundFrontend(-1, "Menu_Accept",        "Phone_SoundSet_Default",                  0, 0, 1)

    elseif soundName == "cancel" then
        PlaySoundFrontend(-1, "MP_IDLE_KICK",       "HUD_FRONTEND_DEFAULT_SOUNDSET",           0, 0, 1)

    elseif soundName == "admin_active" then
        PlaySoundFrontend(-1, "Hack_Success",       "DLC_HEIST_BIOLAB_PREP_HACKING_SOUNDS",    0, 0, 1)

    elseif soundName == "admin_disable" then
        PlaySoundFrontend(-1, "Hack_Failed",        "DLC_HEIST_BIOLAB_PREP_HACKING_SOUNDS",    0, 0, 1)

    elseif soundName == "hover_down" then
        PlaySoundFrontend(-1, "Highlight_Accept",   "DLC_HEIST_PLANNING_BOARD_SOUNDS",         0, 0, 1)

    elseif soundName == "hover_up" then
        PlaySoundFrontend(-1, "Highlight_Error",    "DLC_HEIST_PLANNING_BOARD_SOUNDS",         0, 0, 1)

    else
        Error("Unknown sound:", soundName)
    end

    cb("ok")
end)

-- ──────────────────────────────────────────────────────────
-- Illegal Medic NPC thread
--   Spawns all configured illegal-medic peds, then runs a
--   loop that detects when the player stands within 2 m and
--   presses E to purchase a heal for $5,000.
-- ──────────────────────────────────────────────────────────
local illegalMedicDrawText = i18n.t("drawtext.illegal_medic")

CreateThread(function()
    -- Spawn peds for all configured medic locations
    for _, medicData in pairs(Config.IllegalMedic) do
        medicData.ped = Utils.CreatePed(medicData.pedModel, medicData.coords, true)
    end

    local loopWait = 500   -- ms between proximity checks (reduced to 0 when near)

    while true do
        local playerPos = GetEntityCoords(cache.ped)

        for medicIndex, medicData in ipairs(Config.IllegalMedic) do
            local distToMedic = #(playerPos - medicData.coords.xyz)

            if distToMedic <= 2.0 then
                loopWait = 0   -- Speed up loop while player is close

                -- Draw interaction hint
                DrawText3D(
                    medicData.coords.x,
                    medicData.coords.y,
                    medicData.coords.z,
                    illegalMedicDrawText,
                    "illegal_medic" .. medicIndex,
                    "E"
                )

                -- Detect E key press (normal + disabled context)
                local pressedE = IsControlJustPressed(0, 38)
                              or IsDisabledControlJustPressed(0, 38)

                if pressedE then
                    -- Check if the player has enough money ($5,000)
                    local hasMoney = lib.callback.await("crime:hasMoney", false, 5000)

                    if not hasMoney then
                        Notification(i18n.t("not_enough_money", { amount = 5000 }), "error")
                        return
                    end

                    -- Show progress bar while "receiving treatment"
                    ProgressBar({
                        duration = 5000,
                        label    = i18n.t("using_illegal_medic"),
                        disable  = { move = true, combat = true, mouse = true, look = true },
                    })

                    TriggerServerEvent("crime:useIllegalMedic", medicIndex)
                    Wait(100)
                end
            end
        end

        Wait(loopWait)
    end
end)

-- ──────────────────────────────────────────────────────────
-- ToggleCameraUI(visible, label, cameraType)
--   Shows or hides the front-door camera overlay UI.
-- ──────────────────────────────────────────────────────────
function ToggleCameraUI(visible, label, cameraType)
    SendReactMessage("toggle_camera", {
        visible = visible,
        label   = label,
        type    = cameraType,
    })
end

-- ──────────────────────────────────────────────────────────
-- FrontDoorCam(doorCoords, cameraInsideHouse)
--   Places a scripted camera just outside the door and lets
--   the player look around with the mouse.
--   `cameraInsideHouse` controls whether pressing BACKSPACE
--   takes the player inside or outside the organization house.
-- ──────────────────────────────────────────────────────────
FrontCam = false   -- Global flag: true while front-door cam is active

function FrontDoorCam(doorCoords, cameraInsideHouse)
    local currentOrgId = OrganizationManager:getCurrentOrganization()
    if not currentOrgId then return end

    local org = OrganizationManager:get(currentOrgId)
    if not org then return end

    -- Build a proper vector4 from the coords (defaulting heading to 0)
    doorCoords = vec4(doorCoords.x, doorCoords.y, doorCoords.z, doorCoords.h or 0.0)

    -- Fade out before activating the camera
    DoScreenFadeOut(150)
    Wait(500)

    Debug("FrontDoorCam", "coords", doorCoords, "cameraInHouse", cameraInsideHouse)

    -- Position the camera slightly behind the door (−0.4 on local X axis)
    local camCoords = GetCoordsWithOffset(doorCoords, vec3(-0.4, 0.0, 0.0))

    -- Create the scripted camera facing toward the door interior
    local cam = Utils.CreateCamera(
        "DEFAULT_SCRIPTED_CAMERA",
        camCoords,
        vec3(0.0, 0.0, doorCoords.w - 180.0),
        true   -- activate immediately
    )

    FrontCam = true

    -- Hide the player ped and freeze them
    SetEntityAlpha(cache.ped, 0, false)
    FreezeEntityPosition(cache.ped, true)
    TriggerServerEvent("housing:toggleInSecurityCam", true)

    -- Determine transition direction
    --   If cameraInsideHouse == true  and player is outside → enter house on exit
    --   If cameraInsideHouse == false and player is inside  → leave house on exit
    local shouldEnterOnExit = cameraInsideHouse and not EnteredHouse
    local shouldLeaveOnExit = not cameraInsideHouse

    -- Detect if the house has a modern camera upgrade
    local hasModernCamera = false
    if org.upgrades then
        for _, upg in ipairs(org.upgrades) do
            if upg.name == "camera" and (tonumber(upg.level) or 0) >= 1 then
                hasModernCamera = true
                break
            end
        end
    end

    -- Perform immediate transition if applicable
    if shouldEnterOnExit then
        SetEntityAlpha(cache.ped, 0, false)
        org:enterHouse()
    elseif shouldLeaveOnExit then
        org:leaveHouse()
    end

    Wait(500)
    DoScreenFadeIn(150)

    -- Show the camera overlay UI
    ToggleCameraUI(
        true,
        org.label,
        hasModernCamera and "modern" or "peephole"
    )

    -- Instructional buttons while in camera mode
    Utils.DrawInstructional({ { key = "cancel", label = "Exit" } })

    -- ── Camera loop ─────────────────────────────────────
    CreateThread(function()
        while true do
            if not FrontCam then break end

            Wait(0)

            -- Mouse-only look (no keyboard movement)
            Utils.HandleFlyCam(cam, { mouse = true, keyboard = false })

            -- Apply scanline post-process effect
            SetTimecycleModifier("scanline_cam_cheap")
            SetTimecycleModifierStrength(1.0)
            SetEntityInvincible(cache.ped, true)

            -- BACKSPACE exits the camera
            if IsControlJustPressed(1, Keys.BACKSPACE) then
                DoScreenFadeOut(150)
                ToggleCameraUI(false)
                Citizen.Wait(500)

                Utils.DestroyFlyCam(cam)
                ClearTimecycleModifier()
                FrontCam = false

                -- Restore ped visibility
                SetEntityAlpha(cache.ped, 255, false)

                -- Perform the reverse transition
                if shouldEnterOnExit then
                    org:leaveHouse()
                elseif shouldLeaveOnExit then
                    org:enterHouse()
                end

                FreezeEntityPosition(cache.ped, false)
                TriggerServerEvent("housing:toggleInSecurityCam", false)

                Citizen.Wait(500)
                DoScreenFadeIn(150)
            end
        end

        -- Clean up after loop exits
        Utils.RemoveInstructional()
        SetEntityInvincible(cache.ped, false)
    end)
end

-- ──────────────────────────────────────────────────────────
-- GetVaultCode(uniqId)
--   Queries the server for all vault codes belonging to the
--   current organization and returns the code matching
--   `uniqId`.  Returns false if not found.
-- ──────────────────────────────────────────────────────────
function GetVaultCode(uniqId)
    local currentOrgId = OrganizationManager:getCurrentOrganization()
    if not currentOrgId then return false end

    -- Default to the current org ID if no specific uniq was passed
    if not uniqId then uniqId = currentOrgId end

    local vaultCodes = lib.callback.await("crime:getVaultCodes", false, currentOrgId)

    if vaultCodes then
        for _, entry in pairs(vaultCodes) do
            if entry.uniq == uniqId then
                return entry.code
            end
        end
    end

    return false
end

-- ──────────────────────────────────────────────────────────
-- ChangeVaultCode(uniqId)
--   Opens the keypad UI, and if the player confirms, sends
--   the new code to the server.
-- ──────────────────────────────────────────────────────────
function ChangeVaultCode(uniqId)
    local currentOrgId = OrganizationManager:getCurrentOrganization()
    if not currentOrgId then return end

    local newCode = keypad:open(i18n.t("vault_code.title"))
    if not newCode then return end

    TriggerServerEvent("crime:setVaultCode", {
        code            = newCode,
        uniq            = uniqId or currentOrgId,
        organization_id = currentOrgId,
    })
end

-- ──────────────────────────────────────────────────────────
-- OpenVaultCodeMenu(uniqId)
--   Opens an ox_lib context menu with options to set or
--   remove the vault code for the given stash/door uniqId.
-- ──────────────────────────────────────────────────────────
function OpenVaultCodeMenu(uniqId)
    local currentOrgId = OrganizationManager:getCurrentOrganization()
    if not currentOrgId then return end

    local existingCode = GetVaultCode(uniqId)

    lib.registerContext({
        id    = "vault_code_menu",
        title = i18n.t("vault_code.management_title"),
        options = {
            {
                title    = i18n.t("vault_code.set_code"),
                icon     = "fas fa-key",
                onSelect = function()
                    ChangeVaultCode(uniqId)
                end,
            },
            {
                title    = i18n.t("vault_code.remove_code"),
                icon     = "fas fa-key",
                disabled = not existingCode,    -- Greyed out if no code set
                onSelect = function()
                    TriggerServerEvent("crime:removeVaultCode", {
                        uniq            = uniqId or currentOrgId,
                        organization_id = currentOrgId,
                    })
                end,
            },
        },
    })

    lib.showContext("vault_code_menu")
end

-- ──────────────────────────────────────────────────────────
-- CanAccessStash(uniqId)
--   Checks whether the player is permitted to open a stash.
--   If a vault code has been set, prompts the player to enter
--   it and validates the input.
--   Returns true if access is granted, false otherwise.
-- ──────────────────────────────────────────────────────────
function CanAccessStash(uniqId)
    local requiredCode = GetVaultCode(uniqId)

    -- No code is set → always allow access
    if not requiredCode then
        return true
    end

    -- Prompt the player to enter the code
    local enteredCode = keypad:open(i18n.t("vault_code.access_title"))
    if not enteredCode then
        return false
    end

    -- Validate the entered code
    if enteredCode ~= requiredCode then
        Notification(i18n.t("vault_code.invalid_code"), "error")
        return false
    end

    return true
end

-- ──────────────────────────────────────────────────────────
-- onResourceStop — clean up illegal medic peds on restart
-- ──────────────────────────────────────────────────────────
AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        for _, medicData in pairs(Config.IllegalMedic) do
            if medicData.ped then
                DeletePed(medicData.ped)
            end
        end
    end
end)
