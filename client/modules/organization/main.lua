-- ============================================================
-- client/modules/organization/main.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Organization and OrganizationManager classes.
-- Handles org zones (polyzones), blips, MLO doors, shell/IPL
-- house entry/exit, interior interactions (stash, wardrobe,
-- dynamic furniture), and the global OrganizationManager.
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- Organization class
-- ──────────────────────────────────────────────────────────
Organization = lib.class("Organization")

-- ──────────────────────────────────────────────────────────
-- Organization:constructor(data)
-- ──────────────────────────────────────────────────────────
function Organization:constructor(data)
    self.id              = data.id
    self.label           = data.label or "Unknown Organization"
    self.owner           = data.owner
    self.color           = data.color or "#000000"

    -- entry_coords as vec4 (w defaults to 0)
    if data.entry_coords and data.entry_coords.x then
        self.entry_coords = vec4(
            data.entry_coords.x,
            data.entry_coords.y,
            data.entry_coords.z,
            data.entry_coords.w or 0.0)
    else
        self.entry_coords = vec4(0.0, 0.0, 0.0, 0.0)
        Warning("Organization:constructor :: entry_coords missing for org " .. tostring(data.id) .. " -- entry prompt will not appear")
    end

    -- garage_coords as vec4 if present
    if data.garage_coords then
        self.garage_coords = vec4(
            data.garage_coords.x,
            data.garage_coords.y,
            data.garage_coords.z,
            data.garage_coords.w or 0.0)
    else
        self.garage_coords = nil
    end

    self.locations_coords = data.locations_coords or {}
    self.zone_points      = data.zone_points
    self.type             = data.type or "shell"
    self.interior_data    = data.interior_data
    self.mlo_data         = data.mlo_data
    self.ipl_data         = data.ipl_data
    self.blip_data        = data.blip or nil
    self.creator          = data.creator
    self.created_at       = data.created_at
    self.updated_at       = data.updated_at
    self.members          = data.members  or {}
    self.ranks            = data.ranks    or {}
    self.inside           = false
    self.upgrades         = data.upgrades or {}
    self.blip             = nil
    self.doorsData        = {}

    -- Create garage sub-object if coords exist
    if self.garage_coords then
        self.garage = Garage:new(self)
    else
        self.garage = nil
    end

    -- Create missions sub-object
    self.missions  = Missions:new(self)
    CurrentMissions = self.missions

    self:createPolyzone()
    self:createBlip()
    self:initMLO()
end

-- ──────────────────────────────────────────────────────────
-- Simple field getters
-- ──────────────────────────────────────────────────────────
function Organization:getID()     return self.id      end
function Organization:getLabel()  return self.label   end
function Organization:getOwner()  return self.owner   end
function Organization:getColor()  return self.color   end
function Organization:getMembers() return self.members end

-- ──────────────────────────────────────────────────────────
-- Organization:getMember(identifier) → member | nil
-- ──────────────────────────────────────────────────────────
function Organization:getMember(identifier)
    for _, member in ipairs(self.members) do
        if member.identifier == identifier then return member end
    end
    return nil
end

function Organization:getMemberCount() return #self.members end
function Organization:getRanks()        return self.ranks    end

-- ──────────────────────────────────────────────────────────
-- Organization:getRank(rankId) → rank | nil
-- ──────────────────────────────────────────────────────────
function Organization:getRank(rankId)
    for _, rank in ipairs(self.ranks) do
        if rank.id == rankId then return rank end
    end
    return nil
end

-- ──────────────────────────────────────────────────────────
-- Organization:getMemberRank(identifier) → rank | nil
-- ──────────────────────────────────────────────────────────
function Organization:getMemberRank(identifier)
    local member = self:getMember(identifier)
    if not member then return nil end
    if member.rank    then return member.rank end
    if member.rank_id then return self:getRank(member.rank_id) end
    return nil
end

-- ──────────────────────────────────────────────────────────
-- Organization:hasPermission(permission) → bool
--   Returns true if the local player is an owner, boss, or
--   has the specified permission in their rank.
-- ──────────────────────────────────────────────────────────
function Organization:hasPermission(permission)
    local identifier = cfr:getIdentifier()

    if self:isOwner(identifier) then return true end

    local member = self:getMember(identifier)
    if not member then return false end
    if member.is_boss then return true end
    if not permission then return true end

    local rank = self:getMemberRank(identifier)
    if rank and rank.permissions then
        return rank.permissions[permission] == true
    end
    return false
end

-- ──────────────────────────────────────────────────────────
-- Organization:isMember(identifier) → bool
-- ──────────────────────────────────────────────────────────
function Organization:isMember(identifier)
    return self:getMember(identifier) ~= nil or self:isOwner(identifier)
end

-- ──────────────────────────────────────────────────────────
-- Organization:isOwner(identifier) → bool
-- ──────────────────────────────────────────────────────────
function Organization:isOwner(identifier)
    return self.owner and self.owner.identifier == identifier
end

-- ──────────────────────────────────────────────────────────
-- Organization:initMLO()
--   Registers each MLO door with the door system.
-- ──────────────────────────────────────────────────────────
function Organization:initMLO()
    if not (self.mlo_data and self.mlo_data.doors) then return end

    for i, door in ipairs(self.mlo_data.doors) do
        if door.hash then
            local doorKey = joaat(self.id .. "_" .. i)
            AddDoorToSystem(doorKey, door.hash,
                door.coords.x, door.coords.y, door.coords.z,
                false, false, false)
            DoorSystemSetDoorState(doorKey,
                door.locked and 1 or 0, false, false)
            SetStateOfClosestDoorOfType(door.hash,
                door.coords.x, door.coords.y, door.coords.z,
                door.locked, 0.0, true)
        end
    end
end

-- ──────────────────────────────────────────────────────────
-- Organization:initMLODoors()
--   Groups nearby door pairs by proximity (DoorDuplicateDistance)
--   and builds self.doorsData for interaction prompts.
-- ──────────────────────────────────────────────────────────
function Organization:initMLODoors()
    if not (self.mlo_data and self.mlo_data.doors) then return end

    self.doorsData = {}
    local processed = {}

    for i, door in ipairs(self.mlo_data.doors) do
        if not processed[i] then
            local pos       = vec3(door.coords.x, door.coords.y, door.coords.z)
            local indices   = { i }
            local lockedArr = { door.locked }

            -- Check for duplicates (doors close together)
            for j, other in ipairs(self.mlo_data.doors) do
                if j ~= i and not processed[j] then
                    local otherPos = vec3(other.coords.x, other.coords.y, other.coords.z)
                    if #(pos - otherPos) < Config.DoorDuplicateDistance then
                        table.insert(indices, j)
                        table.insert(lockedArr, other.locked)
                        processed[j] = true
                        pos = Utils.getCentreOfTwoVector3D(pos, otherPos)
                    end
                end
            end

            -- Offset the interaction prompt slightly forward
            local interactPos = GetCoordsWithOffset(
                vec4(pos.x, pos.y, pos.z, 0),
                vec3(0.0, -0.7, 0.0))

            self.doorsData[#self.doorsData + 1] = {
                coords      = interactPos.xyz,
                doorIndices = indices,
                locked      = door.locked,
            }
            processed[i] = true
        end
    end
end

-- ──────────────────────────────────────────────────────────
-- Organization:destroy()
-- ──────────────────────────────────────────────────────────
function Organization:destroy()
    if self.missions then
        self.missions:destroy()
        self.missions = nil
    end
    self.garage = nil
    self:destroyPolyzone()
    self:destroyBlip()
    self:destroyMLODoors()
end

-- ──────────────────────────────────────────────────────────
-- Organization:destroyMLODoors()
-- ──────────────────────────────────────────────────────────
function Organization:destroyMLODoors()
    if not (self.mlo_data and self.mlo_data.doors) then return end
    Debug("Organization:destroyMLODoors", "Organization", self.id, "MLO Data", self.mlo_data)

    for i in ipairs(self.mlo_data.doors) do
        local doorKey = joaat(self.id .. "_" .. i)
        RemoveDoorFromSystem(doorKey)
    end
end

-- ──────────────────────────────────────────────────────────
-- Organization:enterIplHouse()
-- ──────────────────────────────────────────────────────────
function Organization:enterIplHouse()
    if not (self.ipl_data and self.ipl_data.tier and self.ipl_data.themeId) then
        Error("Organization:enterIplHouse", "Invalid IPL data for organization:", self.id)
        return
    end

    local tier    = self.ipl_data.tier
    local themeId = self.ipl_data.themeId
    local exit    = self.ipl_data.exit
    local iplData = Config.IplData[tier]

    if not iplData then
        Error("Organization:enterIplHouse", "Invalid IPL tier:", tier)
        return
    end

    -- Play door sound
    if not Config.DisableInteractSound then
        TriggerServerEvent("InteractSound_SV:PlayOnSource", "houses_door_open", 0.25)
    end

    EnteredHouse = self.id
    TriggerServerEvent("crime:enableAntiTeleport")
    DoorAnim()
    DoScreenFadeOut(250)
    Wait(400)

    -- Apply IPL theme
    local iplExport = iplData.export and iplData.export()
    if iplExport then
        if iplExport.Style and iplExport.Style.Theme then
            if iplExport.Style.Theme[themeId] then
                iplExport.Style.Set(iplExport.Style.Theme[themeId], true)
            end
        elseif iplData.defaultTheme then
            iplExport.Style.Set(iplExport.Style.Theme[iplData.defaultTheme], true)
        end
    end

    SetEntityCoords(cache.ped, exit.x, exit.y, exit.z)
    self.inside = true
    DoScreenFadeIn(500)
    Wait(100)

    self:initHouseInteractions()
    decorate:getObjects(self.id)
    self:tick()
    TriggerEvent("crime:onInsideHouse", self.id, true)
end

-- ──────────────────────────────────────────────────────────
-- Organization:leaveIplHouse()
-- ──────────────────────────────────────────────────────────
function Organization:leaveIplHouse()
    if not self.entry_coords then
        Error("Organization:leaveIplHouse", "No entry coords for organization:", self.id)
        return
    end

    if not Config.DisableInteractSound then
        TriggerServerEvent("InteractSound_SV:PlayOnSource", "houses_door_open", 0.25)
    end

    DoorAnim()
    Wait(250)
    DoScreenFadeOut(250)
    Wait(500)

    self.inside = false
    DoScreenFadeIn(250)
    SetEntityCoords(cache.ped,
        self.entry_coords.x,
        self.entry_coords.y,
        self.entry_coords.z)
    if self.entry_coords.w then
        SetEntityHeading(cache.ped, self.entry_coords.w)
    end

    TriggerServerEvent("crime:disableAntiTeleport")
    decorate:destroyObjects()
    TriggerEvent("crime:onInsideHouse", self.id, false)
end

-- ──────────────────────────────────────────────────────────
-- Organization:enterHouse()
-- ──────────────────────────────────────────────────────────
function Organization:enterHouse()
    local playerPos = GetEntityCoords(cache.ped)
    if self:hasPermission() then
        if self.type == "ipl" then
            self:enterIplHouse()
        else
            EnterHouse(self.id)
        end
    else
        Notification(i18n.t("house_not_permission"), "error")
    end
end

-- ──────────────────────────────────────────────────────────
-- Organization:leaveHouse()
-- ──────────────────────────────────────────────────────────
function Organization:leaveHouse()
    if self.type == "ipl" then
        self:leaveIplHouse()
    else
        LeaveHouse()
    end
end

-- ──────────────────────────────────────────────────────────
-- Resolved i18n labels (at load time)
-- ──────────────────────────────────────────────────────────
local LABEL_ENTER_HOUSE    = i18n.t("drawtext.enter_house")
local LABEL_STASH          = i18n.t("drawtext.stash")
local LABEL_VAULT_ACCESS   = i18n.t("drawtext.vault_access")
local LABEL_EXIT_HOUSE     = i18n.t("drawtext.exit_house")
local LABEL_WARDROBE       = i18n.t("drawtext.wardrobe")
local LABEL_FURNITURE_EVENT = i18n.t("drawtext.furniture_data_event")

-- ──────────────────────────────────────────────────────────
-- Organization:outsideCheck()
--   Draw "Enter house" prompt when near the entry coords.
-- ──────────────────────────────────────────────────────────
function Organization:outsideCheck()
    -- Skip if entry_coords was never configured (still at default 0,0,0)
    if not self.entry_coords or
       (self.entry_coords.x == 0.0 and self.entry_coords.y == 0.0 and self.entry_coords.z == 0.0) then
        return
    end

    local entryPos  = vec3(self.entry_coords.x, self.entry_coords.y, self.entry_coords.z)
    local playerPos = GetEntityCoords(cache.ped)
    local dist      = #(playerPos - entryPos)

    if dist < 1.5 then
        self.sleep = 0
        DrawText3D(entryPos.x, entryPos.y, entryPos.z,
            LABEL_ENTER_HOUSE, "enter_this_house", "E")

        if IsControlJustPressed(0, Keys.E) then
            self:enterHouse()
        end
    end
end

-- ──────────────────────────────────────────────────────────
-- Organization:checkNearObject()
--   Draws prompts for dynamic furniture (stash, wardrobe,
--   events) when the player is close enough.
-- ──────────────────────────────────────────────────────────
function Organization:checkNearObject()
    local playerPos = GetEntityCoords(cache.ped)

    if not (self.id and decorate and decorate.objects) then return end

    for _, obj in pairs(decorate.objects) do
        local objPos = vec3(obj.coords.x, obj.coords.y, obj.coords.z)
        if #(objPos - playerPos) <= 2.0 then
            local dynData    = Config.DynamicFurnitures[obj.modelName]
            local illegalData = Config.IllegalFurnitures and Config.IllegalFurnitures[obj.modelName]

            if dynData then
                local interactPos = GetOffsetFromEntityInWorldCoords(
                    obj.handle, dynData.offset.x, dynData.offset.y, dynData.offset.z)

                if dynData.event then
                    -- Custom event trigger
                    self.sleep = 0
                    DrawText3D(interactPos.x, interactPos.y, interactPos.z,
                        LABEL_FURNITURE_EVENT, "interactorid", "E")

                    if IsControlJustPressed(0, Keys.E) then
                        TriggerEvent(dynData.event, obj.uniq)
                    end

                elseif dynData.type == "stash" then
                    -- Stash access
                    self.sleep = 0
                    DrawText3D(interactPos.x, interactPos.y, interactPos.z,
                        LABEL_STASH, "stash_access", "E")

                    -- Vault access (owner only + vault upgrade)
                    local hasVault = false
                    if self.upgrades then
                        for _, upg in ipairs(self.upgrades) do
                            if upg.name == "vault" and (tonumber(upg.level) or 0) >= 1 then
                                hasVault = true
                                break
                            end
                        end
                    end
                    if hasVault and self:isOwner(cfr:getIdentifier()) then
                        DrawText3D(interactPos.x, interactPos.y, interactPos.z + 0.4,
                            LABEL_VAULT_ACCESS, "bault_access", "G")

                        if IsControlJustPressed(0, Keys.G) then
                            OpenVaultCodeMenu(obj.uniq)
                        end
                    end

                    if IsControlJustPressed(0, Keys.E) then
                        Debug("uniq", obj.uniq)
                        if CanAccessStash(obj.uniq) then
                            OpenStash(dynData.stash, obj.uniq)
                        end
                    end

                elseif dynData.type == "gardrobe" then
                    -- Wardrobe
                    self.sleep = 0
                    DrawText3D(interactPos.x, interactPos.y, interactPos.z,
                        LABEL_WARDROBE, "open_wardrobe", "E")

                    if IsControlJustPressed(0, Keys.E) then
                        OpenWardrobe()
                    end
                end
            end
        end
    end
end

-- ──────────────────────────────────────────────────────────
-- Organization:insideChecks()
--   Draws stash, vault, wardrobe, and exit prompts while
--   inside a shell/IPL house.
-- ──────────────────────────────────────────────────────────
function Organization:insideChecks()
    if EnteringHouse then return end

    local playerPos = GetEntityCoords(cache.ped)

    -- Stash prompt
    if self.locations_coords and self.locations_coords.stash then
        local stashPos = vec3(
            self.locations_coords.stash.x,
            self.locations_coords.stash.y,
            self.locations_coords.stash.z)

        if #(playerPos - stashPos) < 2.5 then
            self.sleep = 0
            DrawText3D(stashPos.x, stashPos.y, stashPos.z,
                LABEL_STASH, "stash_access_" .. self.id, "E")

            -- Check vault upgrade level
            local hasVaultUpgrade = false
            if self.upgrades then
                for _, upg in ipairs(self.upgrades) do
                    if upg.name == "vault" and upg.level > 0 then
                        hasVaultUpgrade = true
                        break
                    end
                end
            end

            local isOwner = self:isOwner(cfr:getIdentifier())
            if hasVaultUpgrade and isOwner then
                DrawText3D(stashPos.x, stashPos.y, stashPos.z + 0.4,
                    LABEL_VAULT_ACCESS, "vault_access_" .. self.id, "G")

                if IsControlJustPressed(0, Keys.G) then
                    OpenVaultCodeMenu(self.id)
                end
            end

            if IsControlJustPressed(0, Keys.E) then
                if self:hasPermission("canAccessStash") then
                    if CanAccessStash(self.id) then
                        OpenStash(nil, self.id)
                    end
                else
                    Notification(i18n.t("not_have_permission"), "error")
                end
            end
        end
    end

    -- Wardrobe prompt
    if self.locations_coords and self.locations_coords.wardrobe then
        local wardrobePos = vec3(
            self.locations_coords.wardrobe.x,
            self.locations_coords.wardrobe.y,
            self.locations_coords.wardrobe.z)

        if #(playerPos - wardrobePos) < 1.5 then
            self.sleep = 0
            DrawText3D(wardrobePos.x, wardrobePos.y, wardrobePos.z,
                LABEL_WARDROBE, "wardrobe_open_" .. self.id, "E")

            if IsControlJustPressed(0, Keys.E) then
                if self:hasPermission("canAccessWardrobe") then
                    OpenWardrobe()
                else
                    Notification(i18n.t("not_have_permission"), "error")
                end
            end
        end
    end

    -- Skip exit prompt for MLO houses (handled by checkMLODoors)
    if self.type == "mlo" then return end

    -- Resolve exit coords (IPL or shell/interior_data)
    local exitPos = nil
    if self.type == "ipl" then
        if self.ipl_data and self.ipl_data.exit then
            exitPos = vec3(self.ipl_data.exit.x, self.ipl_data.exit.y, self.ipl_data.exit.z)
        else
            return
        end
    else
        if self.interior_data and self.interior_data.exit then
            exitPos = vec3(self.interior_data.exit.x, self.interior_data.exit.y, self.interior_data.exit.z)
        else
            return
        end
    end

    if exitPos and #(playerPos - exitPos) <= 2 then
        self.sleep = 0
        DrawText3D(exitPos.x, exitPos.y, exitPos.z, LABEL_EXIT_HOUSE, "exit_house", "E")

        if IsControlJustPressed(0, Keys.E) then
            if self.type == "ipl" then
                self:leaveIplHouse()
            else
                LeaveHouse()
            end
        end
    end
end

-- ──────────────────────────────────────────────────────────
-- Organization:checkMLODoors()
--   Draws door lock/unlock prompt for MLO doors.
-- ──────────────────────────────────────────────────────────
function Organization:checkMLODoors()
    local playerPos = GetEntityCoords(cache.ped)

    for _, doorData in ipairs(self.doorsData) do
        local dist = #(playerPos - doorData.coords)
        if dist <= Config.DoorDistance then
            self.sleep = 0

            local statusLabel = i18n.t(doorData.locked
                and "drawtext.door_unlock"
                or  "drawtext.door_lock")

            DrawText3D(
                doorData.coords.x, doorData.coords.y, doorData.coords.z,
                i18n.t("drawtext.door", { status = statusLabel }),
                "open_mlo_door", "E")

            if IsControlJustPressed(0, 38) then
                DoorAnim()
                local newLocked = not doorData.locked
                TriggerServerEvent("crime:syncDoor", self.id, doorData.doorIndices, newLocked)
            end
        end
    end
end

-- ──────────────────────────────────────────────────────────
-- Organization:tick()
--   Main per-frame loop while player is inside.
-- ──────────────────────────────────────────────────────────
function Organization:tick()
    CreateThread(function()
        while self.inside do
            self.sleep = 500
            self:checkNearObject()

            if self.type ~= "mlo" then
                self:outsideCheck()
                self:insideChecks()
            else
                self:checkMLODoors()
            end

            if self.garage then
                self.garage:checkInteraction()
            end

            Wait(self.sleep)
        end
    end)
end

-- ──────────────────────────────────────────────────────────
-- Organization:initHouseInteractions(optional newId)
--   Populates CurrentHouseData with stash/wardrobe/charge
--   coords and permission flags.
-- ──────────────────────────────────────────────────────────
function Organization:initHouseInteractions(newId)
    if self.locations_coords then
        if self.locations_coords.stash then
            CurrentHouseData.stash = vec3(
                self.locations_coords.stash.x,
                self.locations_coords.stash.y,
                self.locations_coords.stash.z)
        end
        if self.locations_coords.wardrobe then
            CurrentHouseData.wardrobe = vec3(
                self.locations_coords.wardrobe.x,
                self.locations_coords.wardrobe.y,
                self.locations_coords.wardrobe.z)
        end
        if self.locations_coords.charge then
            CurrentHouseData.charge = vec3(
                self.locations_coords.charge.x,
                self.locations_coords.charge.y,
                self.locations_coords.charge.z)
        end
    end

    CurrentHouseData.isOfficialOwner = self:isOwner(cfr:getIdentifier())
    CurrentHouseData.haskey          = self:hasPermission()
end

-- ──────────────────────────────────────────────────────────
-- Organization:handleEnterPoly()
--   Called when the player enters the org polyzone.
-- ──────────────────────────────────────────────────────────
function Organization:handleEnterPoly()
    self.inside      = true
    CurrentHouseData = { haskey = true }

    decorate:close()

    -- Override OrganizationManager.getCurrentOrganization with this org's ID
    if self.id then
        if not EnteredHouse then
            OrganizationManager:setCurrentOrganization(self.id)
            Debug("RefreshClosestHouse ::: Overwrited OrganizationManager:getCurrentOrganization()")
        end
    end
    if EnteredHouse then
        OrganizationManager:setCurrentOrganization(EnteredHouse)
        Debug("RefreshClosestHouse ::: Overwrited OrganizationManager:getCurrentOrganization() to EnteredHouse",
            EnteredHouse)
    end

    self:initMLODoors()
    self:tick()
    self:initHouseInteractions()
    decorate:getObjects(self.id)
end

-- ──────────────────────────────────────────────────────────
-- Organization:createPolyzone()
-- ──────────────────────────────────────────────────────────
function Organization:createPolyzone()
    if not (self.zone_points and self.zone_points.points
            and #self.zone_points.points >= 3) then
        return
    end

    self:destroyPolyzone()

    local points = table.map(self.zone_points.points, function(p)
        return vec3(p.x, p.y, p.z)
    end)
    local thickness = self.zone_points.thickness or 25.0

    local org = self

    self.polyzone = lib.zones.poly({
        name      = "organization_zone_" .. self.id,
        points    = points,
        thickness = thickness,
        debug     = Config.ZoneDebug,

        onEnter = function()
            org:handleEnterPoly()
        end,

        onExit = function()
            -- Block exit if player is inside the house
            if EnteredHouse then
                Debug("handleExitPoly blocked, cause EnteredHouse")
                return
            end

            -- Close decorate mode if active
            if decorate.active then
                Notification(i18n.t("decorate.too_far"), "error")
                decorate:close()
                Debug("handleExitPoly ::: decorate", "decorate")
            end

            org.inside = false
            OrganizationManager:setCurrentOrganization()
            decorate:destroyObjects()
            Debug("Organization:onExit", "Exited organization zone:", org.id, org.label)
        end,

        inside = function() end,
    })

    Debug("Organization:createPolyzone", "Created polyzone for organization:", self.id, self.label)
end

-- ──────────────────────────────────────────────────────────
-- Organization:destroyPolyzone()
-- ──────────────────────────────────────────────────────────
function Organization:destroyPolyzone()
    if self.polyzone then
        self.polyzone:remove()
        self.polyzone = nil
        Debug("Organization:destroyPolyzone",
            "Destroyed polyzone for organization:", self.id, self.label)
    end
end

-- ──────────────────────────────────────────────────────────
-- Organization:createBlip()
-- ──────────────────────────────────────────────────────────
function Organization:createBlip()
    self:destroyBlip()

    if not (self.blip_data and self.blip_data.enable) then return end
    if not self.blip_data.coords then return end

    local pos = vec3(self.blip_data.coords.x, self.blip_data.coords.y, self.blip_data.coords.z)

    self.blip = Utils.CreateBlip({
        location  = pos,
        sprite    = self.blip_data.sprite    or 40,
        color     = self.blip_data.color     or 3,
        scale     = self.blip_data.scale     or 0.6,
        display   = 4,
        shortRange = true,
        highDetail = true,
        text      = self.blip_data.label or self.label,
    })

    Debug("Organization:createBlip", "Created blip for organization:", self.id, self.label)
end

-- ──────────────────────────────────────────────────────────
-- Organization:destroyBlip()
-- ──────────────────────────────────────────────────────────
function Organization:destroyBlip()
    if self.blip then
        Utils.RemoveBlip(self.blip)
        self.blip = nil
        Debug("Organization:destroyBlip",
            "Destroyed blip for organization:", self.id, self.label)
    end
end

-- ──────────────────────────────────────────────────────────
-- Organization:serialize() → plain table (for NUI / callbacks)
-- ──────────────────────────────────────────────────────────
function Organization:serialize()
    local entryCoords = nil
    if self.entry_coords then
        entryCoords = {
            x = self.entry_coords.x,
            y = self.entry_coords.y,
            z = self.entry_coords.z,
            w = self.entry_coords.w or 0.0,
        }
    end

    local garageCoords = nil
    if self.garage_coords then
        garageCoords = {
            x = self.garage_coords.x,
            y = self.garage_coords.y,
            z = self.garage_coords.z,
            w = self.garage_coords.w or 0.0,
        }
    end

    return {
        id              = self.id,
        label           = self.label,
        owner           = self.owner,
        color           = self.color,
        entry_coords    = entryCoords,
        garage_coords   = garageCoords,
        locations_coords = self.locations_coords,
        zone_points     = self.zone_points,
        type            = self.type,
        interior_data   = self.interior_data,
        mlo_data        = self.mlo_data,
        ipl_data        = self.ipl_data,
        blip            = self.blip_data,
        creator         = self.creator,
        created_at      = self.created_at,
        updated_at      = self.updated_at,
        members         = self.members,
        ranks           = self.ranks,
        upgrades        = self.upgrades,
    }
end

-- ──────────────────────────────────────────────────────────
-- OrganizationManager singleton
-- ──────────────────────────────────────────────────────────
OrganizationManager = {
    organizations      = {},
    playerOrganization = nil,
}

-- ──────────────────────────────────────────────────────────
-- OrganizationManager:add(id, orgObject)
-- ──────────────────────────────────────────────────────────
function OrganizationManager:add(id, orgObject)
    self.organizations[id] = orgObject
    Debug("OrganizationManager", "Added organization:", id, orgObject:getLabel())
end

-- ──────────────────────────────────────────────────────────
-- OrganizationManager:remove(id)
-- ──────────────────────────────────────────────────────────
function OrganizationManager:remove(id)
    local org = self.organizations[id]
    if org then
        org:destroy()
        self.organizations[id] = nil

        if self.playerOrganization and self.playerOrganization:getID() == id then
            self.playerOrganization = nil
        end

        Debug("OrganizationManager", "Removed organization:", id)
    end
end

-- ──────────────────────────────────────────────────────────
-- OrganizationManager:update(id, newOrgObject)
-- ──────────────────────────────────────────────────────────
function OrganizationManager:update(id, newOrgObject)
    local existing = self.organizations[id]
    if existing then existing:destroy() end

    self.organizations[id] = newOrgObject

    if self.playerOrganization and self.playerOrganization:getID() == id then
        self.playerOrganization = newOrgObject
    end

    Debug("OrganizationManager", "Updated organization:", id, newOrgObject:getLabel())
end

-- ──────────────────────────────────────────────────────────
-- OrganizationManager:get(id) → Organization | nil
-- ──────────────────────────────────────────────────────────
function OrganizationManager:get(id)
    return self.organizations[id]
end

-- ──────────────────────────────────────────────────────────
-- OrganizationManager:getAll() → table
-- ──────────────────────────────────────────────────────────
function OrganizationManager:getAll()
    return self.organizations
end

-- ──────────────────────────────────────────────────────────
-- OrganizationManager:getByMember(identifier) → Organization | nil
-- ──────────────────────────────────────────────────────────
function OrganizationManager:getByMember(identifier)
    for _, org in pairs(self.organizations) do
        if org:isMember(identifier) then return org end
    end
    return nil
end

-- ──────────────────────────────────────────────────────────
-- OrganizationManager:setPlayerOrganization(identifier) → Organization | nil
-- ──────────────────────────────────────────────────────────
function OrganizationManager:setPlayerOrganization(identifier)
    self.playerOrganization = self:getByMember(identifier)
    return self.playerOrganization
end

-- ──────────────────────────────────────────────────────────
-- OrganizationManager:setCurrentOrganization(id)
-- ──────────────────────────────────────────────────────────
function OrganizationManager:setCurrentOrganization(id)
    Debug("OrganizationManager:setCurrentOrganization", "Setting current organization to:", id)
    self.currentOrganization = id or nil
end

-- ──────────────────────────────────────────────────────────
-- OrganizationManager:getCurrentOrganization() → id | nil
-- ──────────────────────────────────────────────────────────
function OrganizationManager:getCurrentOrganization()
    return self.currentOrganization
end

-- ──────────────────────────────────────────────────────────
-- OrganizationManager:clear()
-- ──────────────────────────────────────────────────────────
function OrganizationManager:clear()
    for _, org in pairs(self.organizations) do
        if org then
            if org.destroyPolyzone then org:destroyPolyzone() end
            if org.destroyBlip     then org:destroyBlip()     end
        end
    end
    self.organizations      = {}
    self.playerOrganization = nil
    Debug("OrganizationManager", "Cleared all organizations")
end

-- ──────────────────────────────────────────────────────────
-- OrganizationManager:getPolyzones() → { polyzone, ... }
-- ──────────────────────────────────────────────────────────
function OrganizationManager:getPolyzones()
    local zones = {}
    for _, org in pairs(self.organizations) do
        if org and org.polyzone then
            zones[#zones + 1] = org.polyzone
        end
    end
    return zones
end

-- ──────────────────────────────────────────────────────────
-- Net event: crime:updateMLODoors
--   Server broadcasts updated door locked states.
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:updateMLODoors", function(orgId, updatedDoors)
    local org = OrganizationManager:get(orgId)
    if not org then return end

    if not (org.mlo_data and org.mlo_data.doors) then return end

    -- Update locked states in mlo_data
    for i, doorUpdate in ipairs(updatedDoors) do
        if org.mlo_data.doors[i] then
            org.mlo_data.doors[i].locked = doorUpdate.locked
        end
    end

    -- Reinitialise door system if currently inside
    if org.inside then
        org:initMLODoors()
    end

    -- Apply door system states
    for i, door in ipairs(org.mlo_data.doors) do
        if door.hash then
            local doorKey = joaat(orgId .. "_" .. i)
            DoorSystemSetDoorState(doorKey, door.locked and 1 or 0, false, false)
            SetStateOfClosestDoorOfType(door.hash,
                door.coords.x, door.coords.y, door.coords.z,
                door.locked, 0.0, true)
        end
    end
end)
