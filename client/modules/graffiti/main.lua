-- ============================================================
-- client/modules/graffiti/main.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- GraffitiModule: scaleform-based world graffiti rendering,
-- interactive placement, spray animation, and CRUD management.
-- ============================================================

_G.GraffitiModule = {
    graffitis           = {},
    activeGraffiti      = nil,
    isPlacing           = false,
    previewScaleform    = nil,
    scaleformPool       = {},     -- [slotId] = { scaleform, graffitiId }
    activeScaleforms    = {},     -- [graffitiId] = slotId
    renderDistance      = (Config.Graffiti and Config.Graffiti.RenderDistance) or 50.0,
    maxVisibleGraffitis = 15,
    isSpraying          = false,
    sprayData           = nil,
}

-- ──────────────────────────────────────────────────────────
-- GraffitiModule:getScaleformName(slotId) → string
--   Returns the PLAYER_NAME scaleform identifier for slotId.
-- ──────────────────────────────────────────────────────────
function GraffitiModule:getScaleformName(slotId)
    if slotId < 1 or slotId > 15 then slotId = 1 end
    return string.format("PLAYER_NAME_%02d", slotId)
end

-- ──────────────────────────────────────────────────────────
-- GraffitiModule:loadScaleform(slotId, text) → handle | 0
--   Loads an interactive scaleform at the given slot and sets
--   its displayed text via SHOW_POPUP_WARNING.
-- ──────────────────────────────────────────────────────────
function GraffitiModule:loadScaleform(slotId, text)
    if slotId < 1 or slotId > 15 then
        Error("GraffitiModule:loadScaleform", "Invalid scaleform ID, must be 1-15")
        return 0
    end

    local name    = self:getScaleformName(slotId)
    local handle  = RequestScaleformMovieInteractive(name)
    local timeout = GetGameTimer() + 5000

    while not HasScaleformMovieLoaded(handle) do
        Wait(0)
        if GetGameTimer() > timeout then
            Error("GraffitiModule:loadScaleform", "Timeout loading scaleform: " .. name)
            return 0
        end
    end

    BeginScaleformMovieMethod(handle, "SHOW_POPUP_WARNING")
    ScaleformMovieMethodAddParamInt(0)
    PushScaleformMovieFunctionParameterString(text or "")
    PushScaleformMovieFunctionParameterString("")
    PushScaleformMovieFunctionParameterString("")
    PushScaleformMovieFunctionParameterBool(true)
    PushScaleformMovieFunctionParameterInt(0)
    PushScaleformMovieFunctionParameterBool(false)
    EndScaleformMovieMethod()

    return handle
end

-- ──────────────────────────────────────────────────────────
-- GraffitiModule:getAvailableScaleformId() → slotId | nil
--   Finds the first scaleform slot not currently in use.
-- ──────────────────────────────────────────────────────────
function GraffitiModule:getAvailableScaleformId()
    for i = 1, self.maxVisibleGraffitis do
        local slot = self.scaleformPool[i]
        if not (slot and slot.graffitiId) then
            return i
        end
    end
    return nil
end

-- ──────────────────────────────────────────────────────────
-- GraffitiModule:assignScaleformToGraffiti(graffitiId, text) → slotId | nil
--   Assigns an available scaleform slot to the given graffiti,
--   reusing the existing slot if valid, or allocating a new one.
-- ──────────────────────────────────────────────────────────
function GraffitiModule:assignScaleformToGraffiti(graffitiId, text)
    -- Check if graffiti already has a valid scaleform
    local existingSlot = self.activeScaleforms[graffitiId]
    if existingSlot then
        local poolEntry = self.scaleformPool[existingSlot]
        if poolEntry and poolEntry.scaleform
           and HasScaleformMovieLoaded(poolEntry.scaleform) then
            return existingSlot
        end
    end

    -- Find a free slot
    local slotId = self:getAvailableScaleformId()
    if not slotId then
        Debug("GraffitiModule:assignScaleformToGraffiti",
            "No available scaleform slot for graffiti:", graffitiId)
        return nil
    end

    -- Release previous scaleform if one existed
    if existingSlot then
        self:releaseScaleform(existingSlot)
    end

    -- Load and store
    local handle = self:loadScaleform(slotId, text)
    if handle == 0 then return nil end

    self.scaleformPool[slotId]       = { scaleform = handle, graffitiId = graffitiId }
    self.activeScaleforms[graffitiId] = slotId
    return slotId
end

-- ──────────────────────────────────────────────────────────
-- GraffitiModule:releaseScaleform(slotId)
-- ──────────────────────────────────────────────────────────
function GraffitiModule:releaseScaleform(slotId)
    local entry = self.scaleformPool[slotId]
    if not entry then return end

    if entry.graffitiId then
        self.activeScaleforms[entry.graffitiId] = nil
    end
    if entry.scaleform then
        self:unloadScaleform(entry.scaleform)
    end
    self.scaleformPool[slotId] = nil
end

-- ──────────────────────────────────────────────────────────
-- GraffitiModule:releaseScaleformByGraffitiId(graffitiId)
-- ──────────────────────────────────────────────────────────
function GraffitiModule:releaseScaleformByGraffitiId(graffitiId)
    local slotId = self.activeScaleforms[graffitiId]
    if slotId then self:releaseScaleform(slotId) end
end

-- ──────────────────────────────────────────────────────────
-- GraffitiModule:unloadScaleform(handle)
-- ──────────────────────────────────────────────────────────
function GraffitiModule:unloadScaleform(handle)
    if handle and handle ~= 0 then
        SetScaleformMovieAsNoLongerNeeded(handle)
    end
end

-- ──────────────────────────────────────────────────────────
-- GraffitiModule:render()
--   Called every frame when graffitis are nearby.
--   Assigns scaleforms to the maxVisibleGraffitis closest
--   ones and draws them.
-- ──────────────────────────────────────────────────────────
function GraffitiModule:render()
    local playerPos = GetEntityCoords(cache.ped)

    -- Build sorted list of nearby graffitis
    local nearby = {}
    for id, graffiti in pairs(self.graffitis) do
        if graffiti.coords then
            local dist = #(playerPos - graffiti.coords)
            if dist <= self.renderDistance then
                nearby[#nearby + 1] = { id = id, graffiti = graffiti, distance = dist }
            end
        end
    end
    table.sort(nearby, function(a, b) return a.distance < b.distance end)

    -- Assign scaleforms and draw
    local rendered = {}
    local count    = 0

    for _, entry in ipairs(nearby) do
        if count >= self.maxVisibleGraffitis then break end

        local graffiti = entry.graffiti
        local id       = entry.id
        local label    = graffiti.label or "Graffiti"

        local slotId = self:assignScaleformToGraffiti(id, label)
        if slotId then
            rendered[id] = true
            local poolEntry = self.scaleformPool[slotId]
            if poolEntry and poolEntry.scaleform then
                local defaultScale = (Config.Graffiti and Config.Graffiti.DefaultScale) or 1.0
                local defaultFont  = (Config.Graffiti and Config.Graffiti.fonts and
                    #Config.Graffiti.fonts > 0 and Config.Graffiti.fonts[1])
                                  or (Config.Graffiti and Config.Graffiti.font)
                                  or "Chalet-LondonNineteenSixty"

                self:drawGraffiti(poolEntry.scaleform, {
                    coords   = graffiti.coords,
                    rotation = graffiti.rotation,
                    scale    = (graffiti.scale or defaultScale) * 2.0,
                    text     = label,
                    font     = graffiti.font or defaultFont,
                    color    = graffiti.color or "FFFFFFFF",
                    label    = label,
                })
            end
            count = count + 1
        end
    end

    -- Release scaleforms for graffitis that are no longer visible
    for graffitiId in pairs(self.activeScaleforms) do
        if not rendered[graffitiId] then
            self:releaseScaleformByGraffitiId(graffitiId)
        end
    end
end

-- ──────────────────────────────────────────────────────────
-- GraffitiModule:startPlacement(label, options) → bool, data
--   Interactive graffiti placement loop.
--   Left-click to confirm; cancel key to abort.
--   options: { label, organizationColor, font, organization_id }
-- ──────────────────────────────────────────────────────────
function GraffitiModule:startPlacement(label, options)
    if self.isPlacing then
        Notification(i18n.t("graffiti.already_placing"), "error")
        return false, nil
    end

    options = options or {}
    self.isPlacing = true

    -- Free slot 15 (reserved for preview)
    if self.scaleformPool[15] and self.scaleformPool[15].graffitiId then
        self:releaseScaleform(15)
    end

    local displayLabel = label or options.label or "Graffiti"

    -- Load preview scaleform
    local previewHandle = self:loadScaleform(15, displayLabel)
    self.previewScaleform = previewHandle
    if previewHandle == 0 then
        self.isPlacing = false
        Notification(i18n.t("graffiti.failed_to_load"), "error")
        return false, nil
    end

    -- Parse org color
    local rawColor = (options.organizationColor or "#FFFFFF")
        :gsub("#", ""):upper()
    if #rawColor == 3 then
        rawColor = rawColor:sub(1,1):rep(2) .. rawColor:sub(2,2):rep(2) .. rawColor:sub(3,3):rep(2)
    end
    if #rawColor ~= 6 then rawColor = "FFFFFF" end
    local colorCode = "FF" .. rawColor   -- AARRGGBB with full alpha

    -- Font list
    local fontList = (Config.Graffiti and Config.Graffiti.fonts and
        #Config.Graffiti.fonts > 0) and Config.Graffiti.fonts
        or { (Config.Graffiti and Config.Graffiti.font) or "Chalet-LondonNineteenSixty" }

    -- Current font index (try to match options.font)
    local fontIndex = 1
    if options.font then
        for i, f in ipairs(fontList) do
            if f == options.font then fontIndex = i break end
        end
    end
    local currentFont = fontList[fontIndex]

    -- Scale
    local defaultScale = (Config.Graffiti and Config.Graffiti.DefaultScale) or 1.0
    local scale        = defaultScale
    local maxScale     = (Config.Graffiti and Config.Graffiti.MaxScale)     or 5.0
    local minScale     = (Config.Graffiti and Config.Graffiti.MinScale)     or 0.2

    -- Build controls
    local controlDefs = {
        { key = "leftClick",   label = i18n.t("graffiti.controls.place")     },
        { key = "arrow_left",  label = i18n.t("graffiti.controls.prev_font") },
        { key = "arrow_right", label = i18n.t("graffiti.controls.next_font") },
        { key = "offset_z",    label = i18n.t("graffiti.controls.scale")     },
        { key = "cancel",      label = i18n.t("graffiti.controls.cancel")    },
    }
    local controls     = Utils.GetControls(controlDefs)
    local instructional = Utils.CreateInstructional(controls)

    Notification(i18n.t("graffiti.placement_started"), "info")

    -- Create temporary camera for placement
    local cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", false)
    SetCamActive(cam, true)

    -- Placement state
    local hitCoords  = vec3(0, 0, 0)
    local hitNormal  = vec3(0, 0, 0)
    local hitResult  = false
    local rotation   = vec3(0, 0, 0)
    local placedData = nil

    while self.isPlacing do
        Wait(0)

        -- Disable attack / aim controls during placement
        DisableControlAction(0, 24,  true)
        DisableControlAction(0, 25,  true)
        DisableControlAction(0, 140, true)
        DisableControlAction(0, 141, true)
        DisableControlAction(0, 142, true)
        DisableControlAction(0, ActionControls.offset_z.codes[1], true)
        DisableControlAction(0, ActionControls.offset_z.codes[2], true)

        -- Raycast from camera
        local camData = Utils.GetCamera()
        local forward = RotationToDirection(camData.rotation)
        local rayEnd  = camData.coords + (forward * 10.0)

        local rayHandle = StartShapeTestRay(
            camData.coords.x, camData.coords.y, camData.coords.z,
            rayEnd.x, rayEnd.y, rayEnd.z,
            1, cache.ped, 0)
        local _, hit, pos, normal, _ = GetShapeTestResult(rayHandle)

        hitResult = hit
        if hit then
            hitCoords = pos + (normal * 0.02)
            local normalOffset = normal + vec3(0, 0, 0.03)
            rotation = self:getRotationFromCamera(cam, hitCoords, normalOffset)

            self:drawGraffiti(self.previewScaleform, {
                coords   = hitCoords,
                rotation = rotation,
                scale    = scale * 2.0,
                text     = displayLabel,
                font     = currentFont,
                color    = colorCode,
                label    = displayLabel,
            })
        end

        -- Font cycling
        if IsDisabledControlJustPressed(0, ActionControls.arrow_left.codes[1]) then
            fontIndex = fontIndex - 1
            if fontIndex < 1 then fontIndex = #fontList end
            currentFont = fontList[fontIndex]
        elseif IsDisabledControlJustPressed(0, ActionControls.arrow_right.codes[1]) then
            fontIndex = fontIndex + 1
            if fontIndex > #fontList then fontIndex = 1 end
            currentFont = fontList[fontIndex]
        end

        -- Scale adjustment
        if IsDisabledControlPressed(0, ActionControls.offset_z.codes[1]) then
            scale = math.min(scale + 0.01, maxScale)
        elseif IsDisabledControlPressed(0, ActionControls.offset_z.codes[2]) then
            scale = math.max(scale - 0.01, minScale)
        end

        -- Place on left-click
        if IsDisabledControlJustPressed(0, ActionControls.leftClick.codes[1]) and hitResult then
            local normalOffset = normal + vec3(0, 0, 0.03)
            rotation = self:getRotationFromCamera(cam, hitCoords, normalOffset)

            placedData = {
                coords          = hitCoords,
                rotation        = rotation,
                scale           = scale,
                font            = currentFont,
                color           = colorCode,
                alpha           = 255,
                label           = options.label or label,
                organization_id = options.organization_id,
            }
            self.isPlacing = false
        end

        -- Cancel
        if IsDisabledControlJustPressed(0, ActionControls.cancel.codes[1]) then
            self.isPlacing = false
        end

        Utils.DrawScaleform(instructional)
    end

    -- Cleanup
    SetCamActive(cam, false)
    DestroyCam(cam, false)
    Utils.RemoveInstructional()
    self:unloadScaleform(self.previewScaleform)
    self.previewScaleform = nil

    if placedData then
        return true, placedData
    else
        Notification(i18n.t("graffiti.placement_cancelled"), "info")
        return false, nil
    end
end

-- ──────────────────────────────────────────────────────────
-- GraffitiModule:drawGraffiti(scaleformHandle, data)
--   data: { coords, rotation, scale, text/label, font,
--            color (AARRGGBB hex), alpha? }
-- ──────────────────────────────────────────────────────────

-- Font color template
local FONT_COLOR_TEMPLATE = '<FONT color="#%s" face="%s">%s</FONT>'

-- local clampByte(v) → 2-char hex string
local function clampByte(v)
    v = math.max(0, math.min(255, math.floor(v)))
    return string.format("%02X", v)
end

-- local blendColorWithAlpha(colorHex, alpha) → 6-char hex
-- Blends the color toward a dark background (50, 50, 50)
-- proportionally to alpha.
local function blendColorWithAlpha(colorHex, alpha)
    local hex = colorHex
    if #hex == 8 then hex = hex:sub(3, 8)
    elseif #hex ~= 6 then hex = "FFFFFF"
    end

    local r   = tonumber(hex:sub(1, 2), 16) or 255
    local g   = tonumber(hex:sub(3, 4), 16) or 255
    local b   = tonumber(hex:sub(5, 6), 16) or 255
    local a   = math.max(0.0, math.min(1.0, alpha / 255.0))
    local bg  = 50  -- dark background component

    return string.format("%02X%02X%02X",
        math.floor(r * a + bg * (1 - a)),
        math.floor(g * a + bg * (1 - a)),
        math.floor(b * a + bg * (1 - a)))
end

function GraffitiModule:drawGraffiti(handle, data)
    if not (handle and HasScaleformMovieLoaded(handle)) then return end
    if IsPauseMenuActive() then return end

    -- Resolve font
    local font = data.font
    if not font then
        local fonts = Config.Graffiti and Config.Graffiti.fonts
        font = (fonts and #fonts > 0 and fonts[1])
            or (Config.Graffiti and Config.Graffiti.font)
            or "Chalet-LondonNineteenSixty"
    end

    local text  = data.label or data.text or ""
    local color = data.color or "FFFFFFFF"

    -- Compute display color (accounting for alpha fade)
    local displayHex
    local alpha = data.alpha
    if alpha ~= nil then
        if alpha >= 0 and alpha < 255 then
            displayHex = blendColorWithAlpha(color, alpha)
        else
            -- Full alpha — extract RGB portion
            if #color == 8 then
                displayHex = color:sub(3, 8)
            elseif #color == 6 then
                displayHex = color
            else
                displayHex = "FFFFFF"
            end
        end
    else
        if #color == 8 then
            displayHex = color:sub(3, 8)
        elseif #color == 6 then
            displayHex = color
        else
            displayHex = "FFFFFF"
        end
    end

    local formatted = string.format(FONT_COLOR_TEMPLATE, displayHex, font, text)

    PushScaleformMovieFunction(handle, "SET_PLAYER_NAME")
    PushScaleformMovieFunctionParameterString(formatted)
    PopScaleformMovieFunctionVoid()

    DrawScaleformMovie_3dSolid(handle,
        data.coords.x, data.coords.y, data.coords.z,
        data.rotation.x, data.rotation.y, data.rotation.z,
        1.0, 1.0, 1.0,
        data.scale, data.scale, 0.1, 0)
end

-- ──────────────────────────────────────────────────────────
-- GraffitiModule:getRotationFromCamera(cam, surfacePos, normal)
--   Positions the cam at surfacePos looking toward normal,
--   and returns the camera rotation.
-- ──────────────────────────────────────────────────────────
function GraffitiModule:getRotationFromCamera(cam, surfacePos, normal)
    local lookTarget = surfacePos - normal
    SetCamCoord(cam, surfacePos.x, surfacePos.y, surfacePos.z)
    PointCamAtCoord(cam, lookTarget.x, lookTarget.y, lookTarget.z)
    return GetCamRot(cam, 2)
end

-- ──────────────────────────────────────────────────────────
-- GraffitiModule:cancelPlacement()
-- ──────────────────────────────────────────────────────────
function GraffitiModule:cancelPlacement()
    self.isPlacing = false
end

-- ──────────────────────────────────────────────────────────
-- GraffitiModule:startSpraying(graffitiData, duration)
--   Animates a graffiti spray-on effect by linearly increasing
--   the alpha from 0 → 255 over `duration` ms.
-- ──────────────────────────────────────────────────────────
function GraffitiModule:startSpraying(graffitiData, duration)
    if self.isSpraying then return end
    self.isSpraying = true

    local label = graffitiData.label or "Graffiti"

    self.sprayData = {
        coords   = graffitiData.coords,
        rotation = graffitiData.rotation,
        scale    = graffitiData.scale,
        font     = graffitiData.font,
        color    = graffitiData.color,
        alpha    = 0,
        label    = graffitiData.label,
    }

    -- Free spray slot 14
    if self.scaleformPool[14] and self.scaleformPool[14].graffitiId then
        self:releaseScaleform(14)
    end

    local sprayHandle = self:loadScaleform(14, label)
    if sprayHandle == 0 then
        self.isSpraying = false
        self.sprayData  = nil
        return
    end

    local startTime = GetGameTimer()
    local endTime   = startTime + duration

    CreateThread(function()
        local handle = sprayHandle
        while self.isSpraying and GetGameTimer() < endTime do
            Wait(0)
            if not self.isSpraying then break end

            local elapsed  = GetGameTimer() - startTime
            local progress = math.min(1.0, elapsed / duration)
            local alpha    = math.floor(progress * 255)

            if self.sprayData then
                self.sprayData.alpha = alpha
                self:drawGraffiti(handle, {
                    coords   = self.sprayData.coords,
                    rotation = self.sprayData.rotation,
                    scale    = (self.sprayData.scale or 1.0) * 2.0,
                    text     = self.sprayData.label or "Graffiti",
                    font     = self.sprayData.font,
                    color    = self.sprayData.color,
                    alpha    = alpha,
                })
            end
        end

        if handle and handle ~= 0 then
            self:unloadScaleform(handle)
        end
        if self.isSpraying then
            self.sprayData  = nil
            self.isSpraying = false
        end
    end)
end

-- ──────────────────────────────────────────────────────────
-- GraffitiModule:stopSpraying()
-- ──────────────────────────────────────────────────────────
function GraffitiModule:stopSpraying()
    self.isSpraying = false
    self.sprayData  = nil
end

-- ──────────────────────────────────────────────────────────
-- GraffitiModule:add(graffitiData)
--   Normalises coords/rotation (plain table → vec3) and stores.
-- ──────────────────────────────────────────────────────────
local function normaliseVec3(t)
    if type(t) == "table" and not t.x then
        return vec3(t[1] or t.x or 0, t[2] or t.y or 0, t[3] or t.z or 0)
    end
    return t
end

function GraffitiModule:add(data)
    data.coords   = normaliseVec3(data.coords)
    data.rotation = normaliseVec3(data.rotation) or vec3(0, 0, 0)
    self.graffitis[data.id] = data
    Debug("GraffitiModule:add", "Added graffiti:", data.id, data.label)
end

-- ──────────────────────────────────────────────────────────
-- GraffitiModule:update(graffitiData)
-- ──────────────────────────────────────────────────────────
function GraffitiModule:update(data)
    local existing = self.graffitis[data.id]
    if existing and existing.label ~= data.label then
        self:releaseScaleformByGraffitiId(data.id)
    end

    data.coords   = normaliseVec3(data.coords)
    data.rotation = normaliseVec3(data.rotation) or vec3(0, 0, 0)
    self.graffitis[data.id] = data
    Debug("GraffitiModule:update", "Updated graffiti:", data.id)
end

-- ──────────────────────────────────────────────────────────
-- GraffitiModule:remove(graffitiId)
-- ──────────────────────────────────────────────────────────
function GraffitiModule:remove(graffitiId)
    if self.graffitis[graffitiId] then
        self:releaseScaleformByGraffitiId(graffitiId)
        self.graffitis[graffitiId] = nil
        Debug("GraffitiModule:remove", "Removed graffiti:", graffitiId)
    end
end

-- ──────────────────────────────────────────────────────────
-- GraffitiModule:clearAll()
-- ──────────────────────────────────────────────────────────
function GraffitiModule:clearAll()
    for i = 1, self.maxVisibleGraffitis do self:releaseScaleform(i) end
    self.graffitis        = {}
    self.activeScaleforms = {}
    self.scaleformPool    = {}
    Debug("GraffitiModule:clearAll", "Cleared all graffitis")
end

-- ──────────────────────────────────────────────────────────
-- GraffitiModule:initialize(graffitiList)
--   Replaces the current set with graffitiList.
-- ──────────────────────────────────────────────────────────
function GraffitiModule:initialize(graffitiList)
    self:clearAll()
    for _, g in ipairs(graffitiList) do
        self:add(g)
    end
    Debug("GraffitiModule:initialize", "Initialized", #graffitiList, "graffitis")
end

-- ──────────────────────────────────────────────────────────
-- GraffitiModule:getNearby(radius) → graffiti | nil
--   Returns the closest graffiti within radius (default 2 m).
-- ──────────────────────────────────────────────────────────
function GraffitiModule:getNearby(radius)
    radius = radius or 2.0
    local playerPos   = GetEntityCoords(cache.ped)
    local closest     = nil
    local closestDist = radius

    for _, graffiti in pairs(self.graffitis) do
        if graffiti.coords then
            local dist = #(playerPos - graffiti.coords)
            if dist < closestDist then
                closest     = graffiti
                closestDist = dist
            end
        end
    end
    return closest
end

-- ──────────────────────────────────────────────────────────
-- Render thread — polls every 500 ms; switches to per-frame
-- when graffitis are within render distance.
-- ──────────────────────────────────────────────────────────
CreateThread(function()
    while true do
        local waitMs = 500

        if next(GraffitiModule.graffitis) then
            local playerPos = GetEntityCoords(cache.ped)
            local anyNearby = false

            for _, graffiti in pairs(GraffitiModule.graffitis) do
                if graffiti.coords then
                    if #(playerPos - graffiti.coords) <= GraffitiModule.renderDistance then
                        anyNearby = true
                        break
                    end
                end
            end

            if anyNearby then
                waitMs = 0
                GraffitiModule:render()
            end
        end

        Wait(waitMs)
    end
end)

-- ──────────────────────────────────────────────────────────
-- Cleanup on resource stop
-- ──────────────────────────────────────────────────────────
AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        GraffitiModule:clearAll()
        if GraffitiModule.previewScaleform then
            GraffitiModule:unloadScaleform(GraffitiModule.previewScaleform)
        end
    end
end)

-- ──────────────────────────────────────────────────────────
-- Register custom graffiti fonts after a short delay
-- ──────────────────────────────────────────────────────────
CreateThread(function()
    Wait(100)
    for _, fontName in pairs(Config.Graffiti.fonts) do
        RegisterFontFile(fontName)
        RegisterFontId(fontName)
    end
end)
