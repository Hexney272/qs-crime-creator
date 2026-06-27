-- ============================================================
-- client/modules/tablet/main.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Crime tablet controller.  Opens/closes the React UI panel
-- after verifying org membership and (optionally) item possession.
-- ============================================================

_G.tablet = { isOpen = false }

-- ──────────────────────────────────────────────────────────
-- tablet.open(self)
--   Opens the crime tablet for the local player.
--   Checks: not already open, in an org, is member,
--   optionally holds the tablet item.
-- ──────────────────────────────────────────────────────────
function tablet.open(self)
    if self.isOpen then return end

    local playerIdentifier = cfr:getIdentifier()
    local orgId            = LocalPlayer.state.organization

    if not orgId then
        return Notification(i18n.t("tablet.not_in_organization"), "error")
    end

    local org = OrganizationManager:get(orgId)
    if not org then
        return Notification(i18n.t("tablet.not_in_organization"), "error")
    end

    if not org:isMember(playerIdentifier) then
        return Notification(i18n.t("tablet.not_in_organization"), "error")
    end

    -- Item check (optional — only if Config.CrimeTablet.Item is set)
    if Config.CrimeTablet.Item then
        local hasItem = lib.callback.await("crime:hasItem", false, Config.CrimeTablet.Item)
        if not hasItem then
            return Notification(i18n.t("tablet.item_not_found"), "error")
        end
    end

    self.isOpen = true

    -- Fetch org stats before opening
    local stats = lib.callback.await("crime:getOrganizationStats", false, orgId)

    SendReactMessage("crime_tablet:open", {
        organizationId = orgId,
        organization   = org:serialize(),
        stats          = stats,
    })

    SetNuiFocus(true, true)
end

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:tablet:open"  (server → client)
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:tablet:open", function()
    tablet:open()
end)

-- ──────────────────────────────────────────────────────────
-- tablet.close(self)
-- ──────────────────────────────────────────────────────────
function tablet.close(self)
    if not self.isOpen then return end
    self.isOpen = false
    SendReactMessage("crime_tablet:close")
    SetNuiFocus(false, false)
end

-- NUI callback: close button
RegisterNUICallback("crime_tablet:close", function(_, cb)
    tablet:close()
    cb("ok")
end)
