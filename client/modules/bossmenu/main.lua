_G.bossmenu = {
    visible = false,
    organizationId = nil,
    organization = nil,
    data = nil,
}

function bossmenu.open(self, orgId)
    if self.visible then return end

    if not orgId then
        orgId = OrganizationManager:getCurrentOrganization()
    end

    if not orgId then
        Notification(i18n.t("bossmenu.organization_not_found"), "error")
        return
    end

    if not OrganizationManager then
        Error("bossmenu:open", "OrganizationManager not found")
        return
    end

    local orgInstance = OrganizationManager:get(orgId)
    if not orgInstance then
        Notification(i18n.t("bossmenu.organization_not_found"), "error")
        return
    end

    local identifier = cfr:getIdentifier()

    if not orgInstance:isMember(identifier) then
        Notification(i18n.t("bossmenu.not_member"), "error")
        return
    end

    if not orgInstance:hasPermission("canAccessBossMenu") then
        Notification(i18n.t("not_have_permission"), "error")
        return
    end

    self.organizationId = orgId
    self.organization = orgInstance

    local menuData = lib.callback.await("crime:getBossMenuData", false, orgId)
    if not menuData then
        Error("bossmenu:open", "Failed to load boss menu data")
        return
    end

    self.data = menuData

    ToggleHud(false)
    self.visible = true
    SetNuiFocus(true, true)
    TriggerServerEvent("crime:openBossMenu", orgId)
    self:updateUI()

    Debug("BossMenu opened for organization:", orgId)
end

function bossmenu.close(self)
    if not self.visible then return end

    local previousOrgId = self.organizationId

    self.visible = false
    self.organizationId = nil
    self.organization = nil
    self.data = nil

    if previousOrgId then
        TriggerServerEvent("crime:closeBossMenu", previousOrgId)
    end

    SendReactMessage("toggle_bossmenu", { visible = false })
    SetNuiFocus(false, false)
    ToggleHud(true)

    Debug("BossMenu closed")
end

function bossmenu.updateUI(self)
    if not self.organization or not self.data then return end

    local permissions = self.data.permissions or {}
    local isOwner = self.data.isOwner or false

    SendReactMessage("toggle_bossmenu", {
        visible = true,
        organization = self.organization:serialize(),
        shopData = {
            money_types = { "money", "bank" },
        },
        data = {
            organization = self.organization:serialize(),
            permissions  = permissions,
            isOwner      = isOwner,
            member       = self.data.member,
            finance      = self.data.finance,
            vehicles     = self.data.vehicles,
            upgrades     = self.data.upgrades,
            stats        = self.data.stats,
        },
    })
end

function bossmenu.refreshFinance(self)
    if not self.organizationId then return end

    local menuData = lib.callback.await("crime:getBossMenuData", false, self.organizationId)
    if menuData and menuData.finance then
        self.data.finance = menuData.finance
        self:updateUI()
    end
end

-- ============================================================
-- NUI Callbacks
-- ============================================================

RegisterNUICallback("close_bossmenu", function(data, cb)
    bossmenu:close()
    cb("ok")
end)

-- ============================================================
-- Net Events
-- ============================================================

RegisterNetEvent("crime:updateBossMenuFinance", function()
    if bossmenu.visible and bossmenu.organizationId then
        bossmenu:refreshFinance()
    end
end)

RegisterNetEvent("crime:updateBossMenuUpgrades", function()
    if not bossmenu.visible or not bossmenu.organizationId then return end

    local menuData = lib.callback.await("crime:getBossMenuData", false, bossmenu.organizationId)
    if menuData and menuData.upgrades then
        bossmenu.data.upgrades = menuData.upgrades
        bossmenu:updateUI()
    end
end)

RegisterNetEvent("crime:updateBossMenuGarage", function()
    SendReactMessage("bossmenu_garage_update", {})
end)