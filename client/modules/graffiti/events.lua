-- ============================================================
-- client/modules/graffiti/events.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Graffiti module event handlers:  sync, CRUD, item-use,
-- spray animation, dialog, and nearby-remove flow.
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:graffiti:sync"
--   Full graffiti list sync on connect / reload.
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:graffiti:sync", function(graffitiList)
    GraffitiModule:initialize(graffitiList)
end)

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:graffiti:created"
--   A new graffiti was created by any player — add it.
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:graffiti:created", function(graffitiData)
    GraffitiModule:add(graffitiData)
end)

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:graffiti:updated"
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:graffiti:updated", function(graffitiData)
    GraffitiModule:update(graffitiData)
end)

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:graffiti:removed"
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:graffiti:removed", function(graffitiId)
    GraffitiModule:remove(graffitiId)
end)

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:graffiti:useItem"
--   Server tells this client to open the graffiti dialog.
--   Validates org membership, resolves font/color from org,
--   opens the React dialog.
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:graffiti:useItem", function(itemName, textureName, options)
    if not options then options = {} end

    -- Require an organization
    local orgId = LocalPlayer.state.organization
    if not orgId then
        Notification(i18n.t("no_organization"), "error")
        return
    end

    local org = OrganizationManager:get(orgId)
    if not org then
        Notification(i18n.t("no_organization"), "error")
        return
    end

    local orgLabel = org:getLabel()
    local orgColor = org:getColor() or "#FFFFFF"

    options.organizationColor = orgColor
    options.organization_id   = orgId

    -- Resolve font from config
    local fonts = Config.Graffiti and Config.Graffiti.fonts or {}
    if #fonts > 0 then
        options.font = options.font or fonts[1]
    else
        options.font = options.font or (Config.Graffiti and Config.Graffiti.font)
    end

    -- Stash pending item data globally for use after the dialog
    _G.graffitiItemData = {
        itemName          = itemName,
        textureName       = textureName,
        options           = options,
        organizationLabel = orgLabel,
    }

    SendReactMessage("graffiti:open_dialog", { organizationLabel = orgLabel })
    SetNuiFocus(true, true)
end)

-- ──────────────────────────────────────────────────────────
-- local startGraffitiPlacement(customLabel)
--   Internal: consumes graffitiItemData, runs the placement
--   flow, plays animation, fires the creation server event.
-- ──────────────────────────────────────────────────────────
local function startGraffitiPlacement(customLabel)
    local itemData = _G.graffitiItemData
    if not itemData then return end

    _G.graffitiItemData = nil

    local itemName    = itemData.itemName
    local textureName = itemData.textureName
    local options     = itemData.options

    -- Apply the custom label from the dialog (or fall back to org label)
    options.label = customLabel or itemData.organizationLabel

    -- Run the GraffitiModule placement routine
    local success, placedGraffiti = GraffitiModule:startPlacement(textureName, options)

    if success and placedGraffiti then
        local animDict    = "anim@scripted@freemode@postertag@graffiti_spray@male@"
        local sprayCanHash = 1749718958

        lib.requestAnimDict(animDict, 5000)
        lib.requestModel(sprayCanHash, 5000)

        -- Spawn a spray-can prop and attach it to the player's right hand
        local sprayCanProp = CreateObject(sprayCanHash, 0, 0, 0, true, true, false)
        local handBone     = GetPedBoneIndex(cache.ped, 28422)

        AttachEntityToEntity(
            sprayCanProp, cache.ped, handBone,
            0.0, 0.0, 0.0,
            0.0, 0.0, 0.0,
            true, true, false, true, 1, true
        )

        local sprayDuration = (Config.Graffiti and Config.Graffiti.SprayDuration) or 5000

        -- Face toward the graffiti surface
        TaskLookAtCoord(
            cache.ped,
            placedGraffiti.coords.x, placedGraffiti.coords.y, placedGraffiti.coords.z,
            sprayDuration, 2048, 2
        )

        -- Play spray animation in a background thread
        CreateThread(function()
            lib.playAnim(cache.ped, animDict, "shake_can_male")
            Wait(1000)
            lib.playAnim(cache.ped, animDict, "spray_can_var_01_male")
            GraffitiModule:startSpraying(placedGraffiti, sprayDuration - 1000)
        end)

        -- Progress bar for the spray duration
        local completed = ProgressBar({
            duration     = sprayDuration,
            label        = i18n.t("graffiti.spraying"),
            useWhileDead = false,
            canCancel    = true,
            disable      = { car = true, move = true, combat = true },
        })

        GraffitiModule:stopSpraying()

        -- Clean up prop and animations
        DeleteObject(sprayCanProp)
        SetModelAsNoLongerNeeded(sprayCanHash)
        RemoveAnimDict(animDict)
        ClearPedTasks(cache.ped)

        if completed then
            -- Determine territory context
            local currentTerritory = TerritoryManager:getCurrent()
            local territoryId      = currentTerritory and currentTerritory.id or nil
            local myOrgId          = LocalPlayer.state.organization

            -- isOwn = we own the territory OR it's unclaimed
            local isOwn = currentTerritory
                and (currentTerritory.organization_id == myOrgId)
                or  currentTerritory == nil

            TriggerServerEvent("crime:graffiti:create", {
                itemName        = itemName,
                coords          = placedGraffiti.coords,
                rotation        = placedGraffiti.rotation,
                scale           = placedGraffiti.scale,
                font            = placedGraffiti.font,
                color           = placedGraffiti.color,
                alpha           = placedGraffiti.alpha,
                label           = placedGraffiti.label,
                organization_id = placedGraffiti.organization_id,
                territoryId     = territoryId,
                isOwn           = isOwn,
            })
        else
            Notification(i18n.t("graffiti.cancelled"), "info")
        end
    end
end

-- ──────────────────────────────────────────────────────────
-- NUI callback: "graffiti_dialog_result"
--   Player confirmed the text in the dialog.
--   Kicks off the placement flow with the chosen text.
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("graffiti_dialog_result", function(payload, cb)
    cb({})
    SetNuiFocus(false, false)

    if payload and payload.text then
        startGraffitiPlacement(payload.text)
    else
        Notification(i18n.t("graffiti.dialog.cancelled"), "info")
    end
end)

-- ──────────────────────────────────────────────────────────
-- CloseGraffitiDialog()
--   Closes the graffiti dialog and cancels any pending
--   placement.
-- ──────────────────────────────────────────────────────────
function CloseGraffitiDialog()
    SetNuiFocus(false, false)
    SendReactMessage("graffiti:close_dialog")

    if _G.graffitiItemData then
        _G.graffitiItemData = nil
        Notification(i18n.t("graffiti.dialog.cancelled"), "info")
    end
end

-- NUI callback: "graffiti_dialog_close" — ESC or X button
RegisterNUICallback("graffiti_dialog_close", function(_, cb)
    cb({})
    SetNuiFocus(false, false)
    SendReactMessage("graffiti:close_dialog")

    if _G.graffitiItemData then
        _G.graffitiItemData = nil
        Notification(i18n.t("graffiti.dialog.cancelled"), "info")
    end
end)

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:graffiti:removeNearby"
--   Player used the graffiti-remover item.
--   Finds the nearest graffiti within 3 m, checks permission,
--   shows a confirmation dialog, runs a progress bar with
--   cleaning animation, then fires the server remove event.
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:graffiti:removeNearby", function()
    local nearbyGraffiti = GraffitiModule:getNearby(3.0)

    if not nearbyGraffiti then
        Notification(i18n.t("graffiti.no_nearby"), "error")
        return
    end

    -- Permission check
    local canRemove = lib.callback.await(
        "crime:graffiti:canRemove", false, nearbyGraffiti.id
    )
    if not canRemove then
        Notification(i18n.t("graffiti.no_permission"), "error")
        return
    end

    -- Confirm dialog
    local result = lib.alertDialog({
        header   = i18n.t("graffiti.remove_title"),
        content  = i18n.t("graffiti.remove_confirm", { label = nearbyGraffiti.label }),
        centered = true,
        cancel   = true,
    })

    if result ~= "confirm" then return end

    -- Progress bar with cleaning animation + sponge prop
    local completed = ProgressBar({
        duration     = 3000,
        label        = i18n.t("graffiti.removing"),
        useWhileDead = false,
        canCancel    = true,
        disable      = { car = true, move = true, combat = true },
        anim         = { dict = "amb@world_human_maid_clean@", clip = "base", flag = 49 },
        prop         = {
            model = "prop_sponge_01",
            bone  = 28422,
            pos   = vec3(0.0, 0.0, -0.01),
            rot   = vec3(90.0, 0.0, 0.0),
        },
    })

    if completed then
        local currentTerritory = TerritoryManager:getCurrent()
        local territoryId      = currentTerritory and currentTerritory.id or nil
        local myOrgId          = LocalPlayer.state.organization

        -- Fire local event for immediate visual removal
        TriggerEvent("crime:graffiti:removed", nearbyGraffiti.id, {
            territoryId  = territoryId,
            removerOrgId = myOrgId,
            isOwn        = false,
        })

        -- Notify the server
        TriggerServerEvent(
            "crime:graffiti:remove",
            nearbyGraffiti.id,
            territoryId,
            myOrgId
        )
    end
end)
