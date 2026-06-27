-- ============================================================
-- client/modules/territory/main.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Territory class + TerritoryManager singleton.
-- Each Territory owns a polygon zone and area blip.
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- Territory class (ox_lib based)
-- ──────────────────────────────────────────────────────────
Territory = lib.class("Territory")

-- ──────────────────────────────────────────────────────────
-- Territory constructor
--   id            – unique territory record ID
--   label         – display name
--   organization_id – owning org (or nil if unclaimed)
--   zone          – { topPoint, bottomPoint, width }
--   color         – hex colour string for the blip
--   creator       – identifier of who created this territory
--   callbacks     – { onEnter, onExit, inside } function table
-- ──────────────────────────────────────────────────────────
function Territory:constructor(id, label, organizationId, zone, color, creator, callbacks)
    self.id             = id
    self.label          = label
    self.organization_id = organizationId
    self.zone           = zone
    self.color          = color
    self.creator        = creator
    self.callbacks      = callbacks or {}
    self.polyzone       = nil

    self:createPolyzone()
    self:createBlip()
end

-- ──────────────────────────────────────────────────────────
-- Territory:createPolyzone()
--   Calculates the 4-corner rectangle from the zone data and
--   creates an ox_lib poly zone.
--   Fires callbacks.onEnter / onExit / inside.
-- ──────────────────────────────────────────────────────────
function Territory:createPolyzone()
    if not (self.zone and self.zone.topPoint and self.zone.bottomPoint) then
        Debug("Territory:createPolyzone",
              "Invalid zone data for territory:", self.id)
        return
    end

    local corners = TerritoryHelper.calculateCorners(
        self.zone.topPoint,
        self.zone.bottomPoint,
        self.zone.width or 50.0
    )

    if not corners then
        Debug("Territory:createPolyzone",
              "Failed to calculate corners for territory:", self.id)
        return
    end

    -- Capture self in the upvalue for the callbacks
    local territory = self

    self.polyzone = lib.zones.poly({
        points    = corners,
        thickness = 500.0,
        debug     = Config.ZoneDebug,

        onEnter = function()
            TerritoryManager.currentTerritory = territory

            if territory.callbacks.onEnter then
                territory.callbacks.onEnter(territory)
            end

            Debug("Territory:onEnter", "Entered territory:", territory.id, territory.label)
        end,

        onExit = function()
            if TerritoryManager.currentTerritory then
                if TerritoryManager.currentTerritory:getID() == territory.id then
                    TerritoryManager.currentTerritory = nil
                end
            end

            if territory.callbacks.onExit then
                territory.callbacks.onExit(territory)
            end

            Debug("Territory:onExit", "Exited territory:", territory.id, territory.label)
        end,

        inside = function()
            if territory.callbacks.inside then
                territory.callbacks.inside(territory)
            end
        end,
    })

    Debug("Territory:createPolyzone",
          "Created polyzone for territory:", self.id, self.label)
end

-- ──────────────────────────────────────────────────────────
-- Territory:createBlip()
--   Draws an area blip on the minimap for this territory.
--   Colour comes from the owning organisation (if any) or
--   from self.color directly.
-- ──────────────────────────────────────────────────────────
function Territory:createBlip()
    -- Remove old blip if it exists
    if self.blip then
        RemoveBlip(self.blip)
    end

    local centre, width, length, heading = TerritoryHelper.calculateRectangleBounds(self.zone)

    if width <= 0 or length <= 0 then
        Error("Territory", "Invalid zone dimensions for zone:", self.id,
              "width:", width, "length:", length)
        return
    end

    -- Create an area blip
    local blip = AddBlipForArea(centre.x, centre.y, centre.z, width, length)

    -- Rotate the blip to match the zone orientation
    Citizen.InvokeNative(0x0F49EB27726DB67D, blip, heading)

    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(self.label or "Zone")
    EndTextCommandSetBlipName(blip)

    -- Determine blip colour: prefer org colour, then zone colour
    local blipColor = self.color
    if self.organization_id then
        local org = OrganizationManager:get(self.organization_id)
        if org then
            local orgColor = org:getColor()
            if orgColor and orgColor ~= "" then
                blipColor = orgColor
            end
        end
    end

    if blipColor then
        SetBlipColour(blip, TerritoryHelper.hexToBlipColor(blipColor))
    else
        SetBlipColour(blip, 0)
    end

    SetBlipAlpha(blip, 150)
    SetBlipAsShortRange(blip, true)
    SetBlipHighDetail(blip, true)
    SetBlipDisplay(blip, 3)

    self.blip = blip
end

-- ──────────────────────────────────────────────────────────
-- Territory:destroy()
--   Removes the poly zone (blip is kept intentionally).
-- ──────────────────────────────────────────────────────────
function Territory:destroy()
    if self.polyzone then
        self.polyzone:remove()
        self.polyzone = nil
        Debug("Territory:destroy", "Destroyed polyzone for territory:", self.id)
    end
end

-- ──────────────────────────────────────────────────────────
-- Accessor methods
-- ──────────────────────────────────────────────────────────
function Territory:getID()             return self.id end
function Territory:getLabel()          return self.label end
function Territory:getOrganizationID() return self.organization_id end
function Territory:getZone()           return self.zone end
function Territory:getColor()          return self.color end

-- ──────────────────────────────────────────────────────────
-- Territory:isInside(point)
--   Returns true if `point` (vec3) is inside this territory.
--   Delegates to the polyzone if available; otherwise falls
--   back to a manual ray-casting point-in-polygon test.
-- ──────────────────────────────────────────────────────────
function Territory:isInside(point)
    -- Use ox_lib zone if available
    if self.polyzone then
        return self.polyzone:contains(point)
    end

    if not (self.zone and self.zone.topPoint and self.zone.bottomPoint) then
        return false
    end

    local corners = TerritoryHelper.calculateCorners(
        self.zone.topPoint,
        self.zone.bottomPoint,
        self.zone.width or 50.0
    )

    if not corners or #corners < 3 then return false end

    -- Ray-casting point-in-polygon test (2-D, X/Y plane)
    local px = point.x
    local py = point.y
    local inside = false
    local n = #corners

    for i = 1, n do
        local j = i + 1
        if j > n then j = 1 end

        local xi, yi = corners[i].x, corners[i].y
        local xj, yj = corners[j].x, corners[j].y

        local isCross = (py < yi) ~= (py < yj)
        if isCross then
            local intersectX = (xj - xi) * (py - yi) / (yj - yi) + xi
            if px < intersectX then
                inside = not inside
            end
        end
    end

    return inside
end

-- ──────────────────────────────────────────────────────────
-- TerritoryManager
--   Singleton that tracks all active Territory instances.
-- ──────────────────────────────────────────────────────────
TerritoryManager = {
    territories      = {},
    currentTerritory = nil,
}

-- TerritoryManager.add(self, id, territory)
function TerritoryManager.add(self, id, territory)
    self.territories[id] = territory
    Debug("TerritoryManager", "Added territory:", id, territory:getLabel())
end

-- TerritoryManager.remove(self, id)
function TerritoryManager.remove(self, id)
    local existing = self.territories[id]
    if existing then
        existing:destroy()

        if self.currentTerritory and self.currentTerritory:getID() == id then
            self.currentTerritory = nil
        end
    end

    self.territories[id] = nil
    Debug("TerritoryManager", "Removed territory:", id)
end

-- TerritoryManager.update(self, id, newTerritory)
function TerritoryManager.update(self, id, newTerritory)
    local existing = self.territories[id]
    if existing then
        existing:destroy()
    end

    self.territories[id] = newTerritory
    Debug("TerritoryManager", "Updated territory:", id, newTerritory:getLabel())
end

-- TerritoryManager.getCurrent(self)  →  Territory | nil
function TerritoryManager.getCurrent(self)
    return self.currentTerritory
end

-- TerritoryManager.get(self, id)  →  Territory | nil
function TerritoryManager.get(self, id)
    return self.territories[id]
end

-- TerritoryManager.getAll(self)  →  table
function TerritoryManager.getAll(self)
    return self.territories
end

-- TerritoryManager.clear(self)
--   Destroys all territories and resets state.
function TerritoryManager.clear(self)
    for _, territory in pairs(self.territories) do
        if territory then territory:destroy() end
    end
    self.territories      = {}
    self.currentTerritory = nil
    Debug("TerritoryManager", "Cleared all territories")
end
