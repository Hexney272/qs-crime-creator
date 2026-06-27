-- ============================================================
-- client/modules/organization/house/shell.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Interior shell system.  Handles entering / leaving the
-- organization house interior (the "shell" prop-based system)
-- and teleporting the player to the interior spawn point.
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- EnterHouse(orgId)
--   Loads the shell interior for the given organization and
--   teleports the player inside.  Uses DoorAnim, creates the
--   shell prop, then fires the interior-init chain.
-- ──────────────────────────────────────────────────────────
function EnterHouse(orgId)
    Debug("EnterHouse", "House", orgId)

    local currentOrgId = OrganizationManager:getCurrentOrganization()

    -- Default to the player's current organization
    if not orgId then
        orgId = currentOrgId
        Debug("No House Passed, Using Current House",
              "OrganizationManager:getCurrentOrganization()", orgId)
    end

    if not orgId then
        return Notification(i18n.t("house_not_found"), "error")
    end

    EnteredHouse = orgId

    local org = OrganizationManager:get(orgId)
    if not org then
        return Notification(i18n.t("house_not_found"), "error")
    end

    -- If the player doesn't already own the current house, force-set it
    if not currentOrgId then
        Debug("EnterHouse ::: Forcing to set current house")
        org:handleEnterPoly()
    end

    -- Validate that the interior tier has a shell configuration
    local shellTier   = org.interior_data.tier
    local shellConfig = Config.Shells[shellTier]

    if not shellConfig then
        print("Tier is not valid")
        return
    end

    Wait(300)

    -- Play door-open sound
    if not Config.DisableInteractSound then
        TriggerServerEvent("InteractSound_SV:PlayOnSource", "houses_door_open", 0.25)
    end

    TriggerServerEvent("crime:enableAntiTeleport")
    DoorAnim()
    Wait(250)

    -- Spawn the shell prop and teleport inside
    SHELL_DATA = CreateShell(
        org.interior_data.coords,
        org.interior_data.exit,
        shellConfig.model
    )

    Citizen.Wait(100)

    HouseObj    = SHELL_DATA[1]
    POIOffsets  = SHELL_DATA[2]

    -- Initialise the exit target if the target system is loaded
    if target then
        target:initExit()
    end

    EnteringHouse = true

    TriggerServerEvent("crime:routePlayer", orgId)
    Wait(500)

    -- Freeze indoor weather
    SetRainFxIntensity(0.0)
    FreezeWeather(true)

    -- Load furniture decoration objects
    decorate:getObjects(orgId)

    -- Initialise interactive objects inside the house
    org:initHouseInteractions()

    EnteringHouse = false

    TriggerServerEvent("crime:onInsideHouse", orgId, true)
    TriggerEvent("crime:onInsideHouse",       orgId, true)
end

-- ──────────────────────────────────────────────────────────
-- LeaveHouse(orgId)
--   Despawns the shell interior and returns the player to the
--   house entry coordinates in the open world.
-- ──────────────────────────────────────────────────────────
function LeaveHouse(orgId)
    Debug("LeaveHouse", "House", orgId)

    if not orgId then
        orgId = EnteredHouse
        Debug("No House Passed, Using Current House", "EnteredHouse", EnteredHouse)
    end

    if not orgId then
        return Notification(i18n.t("house_not_found"), "error")
    end

    -- Play door-open sound
    if not Config.DisableInteractSound then
        TriggerServerEvent("InteractSound_SV:PlayOnSource", "houses_door_open", 0.25)
    end

    local org = OrganizationManager:get(orgId)
    if not org then
        return Notification(i18n.t("house_not_found"), "error")
    end

    DoorAnim()
    Citizen.Wait(250)
    DoScreenFadeOut(250)
    Citizen.Wait(500)

    -- Despawn the interior and run the post-despawn callback
    DespawnInterior(HouseObj, function()
        FreezeWeather(false)
        Citizen.Wait(250)
        DoScreenFadeIn(250)

        -- Place player at the house entry coordinates
        SetEntityCoords(
            cache.ped,
            org.entry_coords.x,
            org.entry_coords.y,
            org.entry_coords.z + 0.2
        )
        SetEntityHeading(cache.ped, org.entry_coords.w)

        TriggerServerEvent("crime:routePlayerToDefault", orgId)
        inOwned = false

        TriggerServerEvent("crime:onInsideHouse", orgId, false)
        EnteredHouse = nil

        if target then
            target:destroyExit()
        end

        Invited      = false
        ShowingHouse = false

        TriggerServerEvent("crime:disableAntiTeleport")
        Wait(300)
    end)
end

-- ──────────────────────────────────────────────────────────
-- TeleportToInterior(coords)
--   Immediately teleports the player ped to `coords`
--   (vector4 with heading) and fades the screen back in.
--   Runs in a new thread so it does not block the caller.
-- ──────────────────────────────────────────────────────────
function TeleportToInterior(coords)
    CreateThread(function()
        Debug("TeleportToInterior", "Coords", coords)

        SetEntityCoords(
            cache.ped,
            coords.x, coords.y, coords.z,
            false, false, false, false
        )
        SetEntityHeading(cache.ped, coords.w)

        Wait(100)
        DoScreenFadeIn(1000)
    end)
end

-- ──────────────────────────────────────────────────────────
-- CreateShell(spawnCoords, exitCoords, modelHash)
--   Spawns the shell object at `spawnCoords`, applies
--   optional heading from spawnCoords.w, freezes the entity,
--   then calls TeleportToInterior(exitCoords).
--   Returns { objectHandles, { exit = exitCoords } }
-- ──────────────────────────────────────────────────────────
function CreateShell(spawnCoords, exitCoords, modelHash)
    local objects   = {}
    local shellInfo = { exit = exitCoords }

    -- Fade out and wait until fully faded
    DoScreenFadeOut(500)
    repeat Wait(10) until IsScreenFadedOut()

    -- Request the model
    lib.requestModel(modelHash, Config.DefaultRequestModelTimeout)

    -- Spawn the shell prop
    local obj = CreateObject(
        modelHash,
        spawnCoords.x, spawnCoords.y, spawnCoords.z,
        false, false, false
    )

    -- Apply heading if provided
    if spawnCoords.w then
        SetEntityHeading(obj, spawnCoords.w)
    end

    SetModelAsNoLongerNeeded(modelHash)
    FreezeEntityPosition(obj, true)

    objects[#objects + 1] = obj

    Debug("CreateShell.exitCoords", exitCoords, "spawn coords", spawnCoords)

    -- Move the player into the interior
    TeleportToInterior(exitCoords)

    return { objects, shellInfo }
end

-- ──────────────────────────────────────────────────────────
-- DespawnInterior(objectHandles, callback)
--   Spawns a thread that deletes every object in
--   `objectHandles`, then calls `callback()`.
-- ──────────────────────────────────────────────────────────
function DespawnInterior(objectHandles, callback)
    CreateThread(function()
        for _, obj in pairs(objectHandles) do
            if obj and DoesEntityExist(obj) then
                DeleteEntity(obj)
            end
        end
        callback()
    end)
end
