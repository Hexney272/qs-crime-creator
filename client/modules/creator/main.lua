-- ============================================================
-- client/modules/creator/main.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Admin creator tool — manages the in-game data-creator UI.
-- Exposes: creator.open/close, updateUI, getPointLength,
--   drawRectangle, drawLines, isPointInAnyZone,
--   raycastRectangle, isInPoints, selectPoint, selectEntity.
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- Locals for hot-path natives
-- ──────────────────────────────────────────────────────────
local IsDisabledControlJustPressed = IsDisabledControlJustPressed
local IsDisabledControlPressed     = IsDisabledControlPressed
local DrawLine                     = DrawLine
local DrawPoly                     = DrawPoly
local ActionControls               = ActionControls

-- ──────────────────────────────────────────────────────────
-- creator singleton
-- ──────────────────────────────────────────────────────────
_G.creator = {
    -- Raycast / zone tool state
    raycast = {
        flags = { ped = 17, vehicle = 17, object = 1 },
        defaults = {
            models = {
                ped     = "mp_m_freemode_01",
                vehicle = "t20",
                object  = "prop_paper_bag_01",
            },
        },
        entities       = { ped = 1, vehicle = 2, object = 3 },
        minPointLength = Config.MinPointLength,
        height         = 25.0,
        points         = {},
    },

    -- Record data caches (populated from server)
    organizations = {},
    territories   = {},
    taxing        = {},
    vehicleStore  = {},
    seasonPass    = nil,
    pvpBattles    = {},
}

-- ──────────────────────────────────────────────────────────
-- creator:updateUI()
--   Transforms raw server record lists into flat tables and
--   sends them to the React creator UI via SendReactMessage.
-- ──────────────────────────────────────────────────────────
function creator:updateUI()
    -- Territories
    local territories = {}
    if self.territories then
        for _, item in ipairs(self.territories) do
            if item.territory_data then
                territories[#territories + 1] = {
                    id              = item.id,
                    label           = item.label,
                    organization_id = item.territory_data.organization_id,
                    organization    = item.territory_data.organization,
                    zone            = item.territory_data.zone,
                    color           = item.territory_data.color,
                    creator         = item.territory_data.creator,
                    created_at      = item.territory_data.created_at,
                    updated_at      = item.territory_data.updated_at,
                }
            end
        end
    end

    -- Taxing
    local taxing = {}
    if self.taxing then
        for _, item in ipairs(self.taxing) do
            if item.taxing_data then
                taxing[#taxing + 1] = {
                    id                = item.id,
                    label             = item.label,
                    payment_count_min = item.taxing_data.payment_count_min,
                    payment_count_max = item.taxing_data.payment_count_max,
                    location          = item.taxing_data.location,
                    territory_id      = item.taxing_data.territory_id,
                    time_type         = item.taxing_data.time_type,
                    time_value        = item.taxing_data.time_value,
                    creator           = item.taxing_data.creator,
                    created_at        = item.taxing_data.created_at,
                    updated_at        = item.taxing_data.updated_at,
                }
            end
        end
    end

    -- Vehicle store
    local vehicleStore = {}
    if self.vehicleStore then
        for _, item in ipairs(self.vehicleStore) do
            if item.vehicle_store_data then
                vehicleStore[#vehicleStore + 1] = {
                    id               = item.id,
                    vehicle_model    = item.vehicle_store_data.vehicle_model,
                    vehicle_label    = item.vehicle_store_data.vehicle_label,
                    description      = item.vehicle_store_data.description,
                    image            = item.vehicle_store_data.image,
                    price            = item.vehicle_store_data.price,
                    limited          = item.vehicle_store_data.limited,
                    limited_end_date = item.vehicle_store_data.limited_end_date,
                    limited_quantity = item.vehicle_store_data.limited_quantity,
                    creator          = item.vehicle_store_data.creator,
                    created_at       = item.vehicle_store_data.created_at,
                    updated_at       = item.vehicle_store_data.updated_at,
                }
            end
        end
    end

    -- Season pass (only the first record is used)
    local seasonPass = nil
    if self.seasonPass and #self.seasonPass > 0 then
        local sp = self.seasonPass[1]
        if sp.season_pass_data then
            local endDate = sp.season_pass_data.endDate or sp.season_pass_data.end_date
            seasonPass = {
                id         = sp.id,
                price      = sp.season_pass_data.price,
                endDate    = endDate,
                rewards    = sp.season_pass_data.rewards or {},
                creator    = sp.season_pass_data.creator,
                created_at = sp.season_pass_data.created_at,
                updated_at = sp.season_pass_data.updated_at,
            }
        end
    end

    -- PvP battles
    local pvpBattles = {}
    if self.pvpBattles then
        for _, item in ipairs(self.pvpBattles) do
            if item.pvp_data then
                pvpBattles[#pvpBattles + 1] = {
                    id                   = item.id,
                    label                = item.label,
                    start_date           = item.pvp_data.start_date,
                    duration             = item.pvp_data.duration,
                    zone_points          = item.pvp_data.zone_points,
                    center_coords        = item.pvp_data.center_coords,
                    rewards              = item.pvp_data.rewards,
                    allowed_organizations = item.pvp_data.allowed_organizations,
                    status               = item.pvp_data.status or "pending",
                    creator              = item.pvp_data.creator,
                    created_at           = item.pvp_data.created_at,
                    updated_at           = item.pvp_data.updated_at,
                }
            end
        end
    end

    -- Organizations (supports both record-wrapped and flat formats)
    local organizations = {}
    if self.organizations then
        for _, item in ipairs(self.organizations) do
            if item.organization_data then
                organizations[#organizations + 1] = item.organization_data
            elseif item.id then
                organizations[#organizations + 1] = {
                    id            = item.id,
                    label         = item.label or "",
                    owner         = item.owner,
                    color         = item.color or "#000000",
                    entry_coords  = item.entry_coords,
                    garage_coords = item.garage_coords,
                    zone_points   = item.zone_points,
                    type          = item.type or "shell",
                    interior_data = item.interior_data,
                    mlo_data      = item.mlo_data,
                    ipl_data      = item.ipl_data,
                    creator       = item.creator,
                    created_at    = item.created_at,
                    updated_at    = item.updated_at,
                }
            end
        end
    end

    SendReactMessage("toggle_creator", {
        visible = true,
        data    = {
            items         = self.items,
            jobs          = self.jobs,
            job           = cfr:getJobName(),
            organizations = organizations,
            territories   = territories,
            taxing        = taxing,
            vehicleStore  = vehicleStore,
            seasonPass    = seasonPass,
            pvpBattles    = pvpBattles,
        },
    })
end

-- ──────────────────────────────────────────────────────────
-- creator:open()
--   Fetches creator data from server (once), opens NUI.
-- ──────────────────────────────────────────────────────────
function creator:open()
    if raycast.active then
        Notification(i18n.t("raycast.must_be_completed"), "error")
        return
    end

    -- Fetch server data on first open
    if not (self.items and self.jobs) then
        local data = lib.callback.await("crime:getCreatorData", false)
        if not data then
            Error("creator:open", "No data returned from server. Did you follow the docs?", data)
            return
        end
        self.items = data.items
        self.jobs  = data.jobs
    end

    ToggleHud(false)
    self.visible = true
    SetNuiFocus(true, true)
    self:updateUI()
    Debug("Creator opened")
end

-- ──────────────────────────────────────────────────────────
-- creator:close()
-- ──────────────────────────────────────────────────────────
function creator:close()
    if not self.visible then return end
    self.visible = false
    SendReactMessage("toggle_creator", { visible = false })
    Debug("Creator closed")
end

-- ──────────────────────────────────────────────────────────
-- /crimecreator command — checks permission then opens
-- ──────────────────────────────────────────────────────────
RegisterCommand("crimecreator", function(source, args, raw)
    local hasPermission = lib.callback.await("crime:hasPermission", 0)
    if not hasPermission then
        Notification(i18n.t("no_permission"), "error")
        return
    end
    creator:open()
end)

-- ──────────────────────────────────────────────────────────
-- creator:getPointLength(points) → float
--   Sum of segment lengths for a closed polygon.
-- ──────────────────────────────────────────────────────────
function creator:getPointLength(points)
    local total = 0.0
    for i = 1, #points do
        local next = points[i + 1] or points[1]
        total = total + #(points[i] - next)
    end
    return total
end

-- ──────────────────────────────────────────────────────────
-- creator:drawRectangle(corners, allPoints)
--   Draws two tris that form a quad from 4 corners.
--   Colour: white (valid) or dim (insufficient points).
-- ──────────────────────────────────────────────────────────
function creator:drawRectangle(corners, allPoints)
    local enough = #allPoints >= 4
    local r = enough and 255 or 255
    local g = enough and 255 or 40
    local b = enough and 0   or 24

    -- First triangle: corners[1], corners[2], corners[3]
    DrawPoly(
        corners[1].x, corners[1].y, corners[1].z,
        corners[2].x, corners[2].y, corners[2].z,
        corners[3].x, corners[3].y, corners[3].z,
        r, g, b, 100)
    DrawPoly(
        corners[2].x, corners[2].y, corners[2].z,
        corners[1].x, corners[1].y, corners[1].z,
        corners[3].x, corners[3].y, corners[3].z,
        r, g, b, 100)
    -- Second triangle: corners[1], corners[4], corners[3]
    DrawPoly(
        corners[1].x, corners[1].y, corners[1].z,
        corners[4].x, corners[4].y, corners[4].z,
        corners[3].x, corners[3].y, corners[3].z,
        r, g, b, 100)
    DrawPoly(
        corners[4].x, corners[4].y, corners[4].z,
        corners[1].x, corners[1].y, corners[1].z,
        corners[3].x, corners[3].y, corners[3].z,
        r, g, b, 100)
end

-- ──────────────────────────────────────────────────────────
-- creator:drawLines()
--   Renders the current raycast polyzone as wire-frame lines
--   and filled quads between each consecutive pair of points.
-- ──────────────────────────────────────────────────────────
function creator:drawLines()
    local halfHeight = vec(0, 0, self.raycast.height / 2)
    local pts        = self.raycast.points

    for i = 1, #pts do
        local z = self.raycast.zCoords or pts[i].z
        pts[i]  = vec(pts[i].x, pts[i].y, z)

        local top    = pts[i] + halfHeight
        local bottom = pts[i] - halfHeight

        -- Next point (wraps to 1)
        local nextIdx   = i + 1
        local nextPoint = pts[nextIdx] and vec(pts[nextIdx].x, pts[nextIdx].y, z)
                       or pts[1]

        local nextTop    = nextPoint + halfHeight
        local nextBottom = nextPoint - halfHeight
        local curPoint   = pts[i]
        local nextP      = pts[nextIdx] and vec(pts[nextIdx].x, pts[nextIdx].y, z) or pts[1]

        -- Vertical edges
        DrawLine(top.x, top.y, top.z, bottom.x, bottom.y, bottom.z,   255, 42, 24, 225)
        DrawLine(top.x, top.y, top.z, nextTop.x, nextTop.y, nextTop.z, 255, 42, 24, 225)
        DrawLine(bottom.x, bottom.y, bottom.z, nextBottom.x, nextBottom.y, nextBottom.z, 255, 42, 24, 225)
        DrawLine(curPoint.x, curPoint.y, curPoint.z, nextP.x, nextP.y, nextP.z, 255, 42, 24, 225)

        -- Filled quad between this pair of points
        self:drawRectangle({ top, bottom, nextBottom, nextTop }, pts)
    end
end

-- ──────────────────────────────────────────────────────────
-- creator:isPointInAnyZone(point) → bool
-- ──────────────────────────────────────────────────────────
function creator:isPointInAnyZone(point)
    for _, zone in pairs(OrganizationManager:getPolyzones()) do
        if zone:contains(point) then return true end
    end
    return false
end

-- ──────────────────────────────────────────────────────────
-- creator:raycastRectangle() → { points, thickness } | nil
--   Launches a free-camera mode where the user places polyzone
--   points by clicking. Returns the finalized zone or nil.
-- ──────────────────────────────────────────────────────────
function creator:raycastRectangle()
    -- Reset state
    self.raycast.points = {}
    local playerPos     = GetEntityCoords(cache.ped)
    self.raycast.zCoords = math.round(playerPos.z) + 0.0
    self.raycast.height  = 25.0

    -- Update control labels
    ActionControls.leftClick.label        = i18n.t("creator.raycast.add_point")
    ActionControls.rotate_z_scroll.label  = i18n.t("creator.raycast.point_size")

    Notification(i18n.t("creator.raycast.info"), "info")

    -- Per-frame callback passed to raycast.freeCamera
    local function onFrame(rcData)
        self:drawLines()

        -- Cancel
        if IsDisabledControlJustPressed(0, ActionControls.cancel.codes[1])
           or IsDisabledControlJustPressed(0, 322) then
            rcData:destroy()
            return
        end

        -- Done
        if IsDisabledControlJustPressed(0, ActionControls.done.codes[1]) then
            if not (self.raycast.points and #self.raycast.points > 0) then
                Notification(i18n.t("creator.raycast.no_point_selected"), "error")
            else
                rcData:destroy()
            end
            return
        end

        -- Add point
        if IsDisabledControlJustPressed(0, ActionControls.leftClick.codes[1]) then
            if rcData.hit then
                if self:isPointInAnyZone(rcData.coords) then
                    Notification(i18n.t("creator.raycast.point_in_another_zone"), "error")
                else
                    local n = #self.raycast.points + 1
                    self.raycast.points[n] = vec3(rcData.coords.x, rcData.coords.y, rcData.coords.z)
                end
            end
        end

        -- Undo last point
        if IsDisabledControlJustPressed(0, ActionControls.undo_point.codes[1]) then
            local n = #self.raycast.points
            if n > 0 then self.raycast.points[n] = nil end
        end

        -- Adjust boundary height
        if IsDisabledControlPressed(0, ActionControls.boundary_height.codes[1]) then
            self.raycast.height = self.raycast.height + 15.0 * GetFrameTime()
        elseif IsDisabledControlPressed(0, ActionControls.boundary_height.codes[2]) then
            self.raycast.height = self.raycast.height - 15.0 * GetFrameTime()
        end
    end

    raycast.freeCamera(raycast, onFrame,
        { "done", "undo_point", "leftClick", "cancel", "boundary_height" })

    -- Clear temp zCoords
    self.raycast.zCoords = nil

    if #self.raycast.points < 4 then return nil end

    return {
        points    = self.raycast.points,
        thickness = self.raycast.height,
    }
end

-- ──────────────────────────────────────────────────────────
-- creator:isInPoints(point) → bool
--   2D point-in-polygon (ray-casting algorithm) + Z range check.
-- ──────────────────────────────────────────────────────────
function creator:isInPoints(point)
    local pts = self.raycast.points
    if not pts or #pts < 3 then return false end

    -- Z range check
    local halfH = self.raycast.height / 2.4
    local minZ  = pts[1].z
    local maxZ  = pts[1].z

    for i = 2, #pts do
        if pts[i].z < minZ then minZ = pts[i].z end
        if pts[i].z > maxZ then maxZ = pts[i].z end
    end

    if point.z < minZ - halfH or point.z > maxZ + halfH then
        return false
    end

    -- 2D ray casting
    local x, y    = point.x, point.y
    local inside  = false
    local n       = #pts

    for i = 1, n do
        local j  = (i % n) + 1
        local xi, yi = pts[i].x, pts[i].y
        local xj, yj = pts[j].x, pts[j].y

        if (yi > y) ~= (yj > y) then
            local xCross = (xj - xi) * (y - yi) / (yj - yi) + xi
            if x < xCross then
                inside = not inside
            end
        end
    end

    return inside
end

-- ──────────────────────────────────────────────────────────
-- creator:selectPoint(pointType, count, options) → vec4[] | nil
--   Interactive point picker (gameplay or free camera).
--
--   pointType: "empty"|"ped"|"vehicle"|"object"
--   count:     how many points to collect
--   options:   { model, points, externalUsage, freeCamera }
--
--   Existing points in options.points are pre-loaded as
--   ghost entities. Returns an array of vec4 on completion,
--   or nil on cancel.
-- ──────────────────────────────────────────────────────────
function creator:selectPoint(pointType, count, options)
    Debug("creator:selectPoint", options)

    -- If no raycast zone points, and this is not an external-usage call, notify
    if #self.raycast.points == 0 then
        if not (options and options.externalUsage) then
            Notification(i18n.t("creator.no_points_selected"), "error")
            return nil
        end
    end

    pointType = pointType or "empty"
    count     = count     or 1
    options   = options   or {}
    if not options.points then options.points = {} end

    local collected   = {}   -- array of { coords = vec3/vec4, handle = entity? }
    local currentRot  = 0

    -- Load model for the ghost entity (if not "empty")
    if pointType ~= "empty" then
        if not options.model then
            options.model = self.raycast.defaults.models[pointType]
        end
        lib.requestModel(options.model, Config.DefaultRequestModelTimeout)
    end

    -- ── Inner helper: spawn ghost entity at coords ──────
    local function spawnGhost(model, coords)
        if not model then coords = coords or vec4(0, 0, 0, 0) end
        if not coords then coords = vec4(0, 0, 0, 0) end

        local handle = nil
        if pointType == "empty" then
            return nil
        elseif pointType == "ped" then
            handle = CreatePed(28, model,
                coords.x, coords.y, coords.z, coords.w, false, false)
        elseif pointType == "vehicle" then
            handle = CreateVehicle(model,
                coords.x, coords.y, coords.z, coords.w, false, true)
        elseif pointType == "object" then
            handle = CreateObject(model,
                coords.x, coords.y, coords.z, false, false)
            if coords.w then SetEntityHeading(handle, coords.w) end
        end

        if handle then
            Wait(0)
            FreezeEntityPosition(handle, true)
            SetEntityInvincible(handle, true)
        end
        return handle
    end

    -- Spawn a ghost entity at the player position (the "cursor ghost").
    -- Must pass the model and a real starting position so CreateVehicle/CreatePed
    -- receives a valid model hash — calling spawnGhost() with no args passes nil,
    -- the native fails, ghostHandle = 0, and GetEntityCoords(0) always returns
    -- 0,0,0 no matter where the player clicks.
    local pedCoords  = GetEntityCoords(cache.ped)
    local pedHeading = GetEntityHeading(cache.ped)
    local initCoords = vec4(pedCoords.x, pedCoords.y, pedCoords.z, pedHeading)
    local ghostHandle = spawnGhost(options.model, initCoords)

    -- Control keys
    local controlKeys = { "leftClick" }
    if pointType ~= "empty" then
        table.insert(controlKeys, "rotate_z")
    end

    -- Pre-load any existing points as ghost entities
    for _, existingPt in pairs(options.points) do
        if existingPt.model then
            lib.requestModel(existingPt.model, Config.DefaultRequestModelTimeout)
            local h = spawnGhost(joaat(existingPt.model), existingPt.coords)
            existingPt.handle = h
            if h then
                SetEntityDrawOutline(h, true)
                if existingPt.coords and existingPt.coords.w then
                    SetEntityHeading(h, existingPt.coords.w)
                end
            end
        end
    end

    -- Control labels
    ActionControls.leftClick.label  = i18n.t("creator.raycast.add_point")
    ActionControls.rotate_z.label   = i18n.t("creator.raycast.rotate_z_scroll")

    -- Use free camera if options.freeCamera is set, else gameplay camera
    local camMode = (options.freeCamera and raycast.freeCamera) or raycast.gameplayCamera

    -- ── Per-frame callback ────────────────────────────────
    local function onFrame(rcData)
        -- Disable weapon / enter vehicle
        DisableControlAction(0, 25, true)
        DisableControlAction(0, 20, true)
        DisableControlAction(0, 73, true)

        -- Draw existing point markers
        for _, existingPt in pairs(options.points) do
            DrawMarker(28,
                existingPt.coords.x, existingPt.coords.y, existingPt.coords.z,
                0, 0, 0, 0, 0, 0,
                0.2, 0.2, 0.2,
                255, 42, 24, 100,
                false, false, 0, true, false, false, false)
        end

        self:drawLines()
        if not rcData.hit then return end

        -- Move ghost to hit position
        if ghostHandle then
            if rcData.lastCoords ~= rcData.coords then
                SetEntityCoords(ghostHandle,
                    rcData.coords.x, rcData.coords.y, rcData.coords.z,
                    false, false, true)
            end
        end

        -- Confirm point (left-click)
        if IsDisabledControlJustPressed(0, 24) then
            if not self:isInPoints(rcData.coords) then
                if not (options and options.externalUsage) then
                    Notification(i18n.t("creator.raycast.not_in_points"), "error")
                    return
                end
            end

            local selectedCoords = vec3(rcData.coords.x, rcData.coords.y, rcData.coords.z)
            local selectedHandle = nil

            if pointType ~= "empty" then
                local entityCoords = GetEntityCoords(ghostHandle)
                local entityH      = GetEntityHeading(ghostHandle)
                selectedCoords     = vec4(entityCoords.x, entityCoords.y, entityCoords.z, entityH)
                selectedHandle     = spawnGhost(selectedCoords)
                if selectedHandle then
                    SetEntityAlpha(selectedHandle, 170, false)
                end
            end

            local n = #collected + 1
            collected[n] = { coords = selectedCoords, handle = selectedHandle }

            if #collected == count then
                Notification(i18n.t("creator.raycast.completed"), "info")
                rcData:destroy()
            else
                Notification(i18n.t("creator.raycast.selected_point",
                    { count = #collected }), "info")
            end
        end

        -- Rotate ghost (scroll-wheel controls)
        if pointType ~= "empty" then
            if IsDisabledControlPressed(0, 20) then
                currentRot = (currentRot + 1.0) % 360
                SetEntityHeading(ghostHandle, currentRot)
            elseif IsDisabledControlPressed(0, 73) then
                currentRot = (currentRot - 1.0) % 360
                SetEntityHeading(ghostHandle, currentRot)
            end
        end
    end

    camMode(raycast, onFrame, controlKeys, self.raycast.flags[pointType] or 1)

    -- ── Cleanup ───────────────────────────────────────────
    -- Delete ghost handles from collected points
    for _, entry in pairs(collected) do
        if entry.handle then DeleteEntity(entry.handle) end
    end
    -- Delete option pre-loaded ghosts
    for _, existingPt in pairs(options.points) do
        if existingPt.model and existingPt.handle then
            DeleteEntity(existingPt.handle)
            SetModelAsNoLongerNeeded(existingPt.model)
        end
    end

    Utils.RemoveInstructional()

    if ghostHandle then
        DeleteEntity(ghostHandle)
        SetModelAsNoLongerNeeded(options.model)
    end

    -- Return just the coords
    return table.map(collected, function(e) return e.coords end)
end

-- ──────────────────────────────────────────────────────────
-- creator:selectEntity(entityType, count, options) → result[] | nil
--   Interactive entity picker; uses gameplay camera.
--   Returns an array of { entity, coords: vec4 }.
--
--   options: { disabledEntities, ped: { model, anim } }
-- ──────────────────────────────────────────────────────────
function creator:selectEntity(entityType, count, options)
    if #self.raycast.points == 0 then
        Notification(i18n.t("creator.no_points_selected"), "error")
        return nil
    end

    assert(entityType, "creator:selectEntity ::: entityType is required")

    count   = count   or 1
    options = options or {}
    if not options.disabledEntities then options.disabledEntities = {} end

    local collected       = {}
    local currentOffset   = vec4(0, 0, 0, 0)
    local prevEntity      = 0
    local ghostPed        = nil

    -- Highlight disabled entities
    for _, ent in pairs(options.disabledEntities) do
        SetEntityDrawOutline(ent, true)
    end

    -- Spawn optional ghost ped that follows the cursor
    local controlKeys = { "leftClick" }
    if options.ped then
        lib.requestModel(options.ped.model)
        ghostPed = CreatePed(28, options.ped.model, 0, 0, 0, 0, false, false)
        SetEntityVisible(ghostPed, false, false)
        SetEntityInvincible(ghostPed, true)
        FreezeEntityPosition(ghostPed, true)
        SetEntityCompletelyDisableCollision(ghostPed, true, false)

        local anim = options.ped.anim
        lib.requestAnimDict(anim.dict, 3000)
        TaskPlayAnim(ghostPed, anim.dict, anim.name,
            8.0, 1.0, -1, 1, 0, false, false, false)
        RemoveAnimDict(anim.dict)

        table.insert(options.disabledEntities, ghostPed)
        table.insert(controlKeys, "rotate_z")
        table.insert(controlKeys, "offset_z")
    end

    -- Control label
    ActionControls.leftClick.label = i18n.t("creator.raycast.select_entity")

    Notification(i18n.t("creator.raycast.select_entity_info",
        { entityType = entityType }), "info")

    -- ── Per-frame callback ────────────────────────────────
    local function onFrame(rcData)
        -- Disable scroll-wheel controls
        DisableControlAction(0, ActionControls.rotate_z.codes[1], true)
        DisableControlAction(0, ActionControls.rotate_z.codes[2], true)
        DisableControlAction(0, ActionControls.offset_z.codes[1], true)
        DisableControlAction(0, ActionControls.offset_z.codes[2], true)

        self:drawLines()

        -- Draw bounding box around ghost ped
        if ghostPed then
            Utils.DrawEntityBoundingBox(ghostPed, 255, 42, 24, 100)
        end

        -- Remove outline from previous hovered entity if it changed
        if prevEntity ~= rcData.entity then
            if not table.contains(options.disabledEntities, prevEntity) then
                SetEntityDrawOutline(prevEntity, false)
                if ghostPed then SetEntityVisible(ghostPed, false, false) end
            end
        end

        prevEntity = rcData.entity

        if rcData.hit and rcData.entity then
            if not table.contains(options.disabledEntities, prevEntity) then
                -- Highlight hovered entity
                SetEntityDrawOutline(rcData.entity, true)

                -- Move ghost ped near hovered entity
                if ghostPed then
                    local entityPos = GetEntityCoords(rcData.entity)
                    local newPos    = entityPos + currentOffset.xyz
                    SetEntityCoords(ghostPed,
                        newPos.x, newPos.y, newPos.z,
                        false, false, false, false)
                    SetEntityVisible(ghostPed, true, false)
                    SetEntityHeading(ghostPed,
                        GetEntityHeading(rcData.entity) + currentOffset.w)
                end
            end

            -- Ghost ped controls: rotate / offset
            if ghostPed then
                if IsDisabledControlPressed(0, ActionControls.rotate_z.codes[1]) then
                    currentOffset = currentOffset + vec4(0, 0, 0, 0.5)
                    prevEntity = 0
                elseif IsDisabledControlPressed(0, ActionControls.rotate_z.codes[2]) then
                    currentOffset = currentOffset + vec4(0, 0, 0, -0.5)
                    prevEntity = 0
                end
                if IsDisabledControlPressed(0, ActionControls.offset_z.codes[1]) then
                    currentOffset = currentOffset + vec4(0, 0, 0.005, 0)
                    prevEntity = 0
                elseif IsDisabledControlPressed(0, ActionControls.offset_z.codes[2]) then
                    currentOffset = currentOffset + vec4(0, 0, -0.005, 0)
                    prevEntity = 0
                end
            end

            -- Confirm selection
            if IsDisabledControlJustPressed(0, ActionControls.leftClick.codes[1]) then
                local entityPos = GetEntityCoords(rcData.entity)

                -- Must be inside zone
                if not self:isInPoints(entityPos) then
                    Notification(i18n.t("creator.raycast.not_in_points"), "error")
                    return
                end

                -- Must not be disabled
                if table.contains(options.disabledEntities, rcData.entity) then
                    Notification(i18n.t("creator.raycast.entity_disabled"), "error")
                    return
                end

                local heading      = GetEntityHeading(rcData.entity)
                local selectedCoords = vec4(entityPos.x, entityPos.y, entityPos.z, heading)
                                     + currentOffset

                collected[#collected + 1] = {
                    entity = rcData.entity,
                    coords = selectedCoords,
                }

                if #collected == count then
                    Notification(i18n.t("creator.raycast.completed"), "info")
                    rcData:destroy()
                else
                    Notification(i18n.t("creator.raycast.selected_entity",
                        { count = #collected }), "info")
                end
            end
        end
    end

    raycast.gameplayCamera(raycast, onFrame, controlKeys)

    -- ── Cleanup ───────────────────────────────────────────
    SetEntityDrawOutline(prevEntity, false)
    for _, ent in pairs(options.disabledEntities) do
        SetEntityDrawOutline(ent, false)
    end

    if ghostPed then
        DeleteEntity(ghostPed)
        SetModelAsNoLongerNeeded(options.ped.model)
    end

    if #collected == 0 then return nil end
    return collected
end
