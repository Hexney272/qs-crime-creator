-- ============================================================
-- client/modules/territory/helper.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Geometry helpers for the territory system.
-- ============================================================

TerritoryHelper = {}

-- ──────────────────────────────────────────────────────────
-- TerritoryHelper.calculateCorners(pointA, pointB, width)
--   Given two end-points of a line segment and a `width`,
--   calculates the 4 corners of a rectangle centred on the
--   segment (plus any extra unpacked values from vec3 calls).
--   Returns a table of corner vec3 values.
-- ──────────────────────────────────────────────────────────
function TerritoryHelper.calculateCorners(pointA, pointB, width)
    local dx = pointB.x - pointA.x
    local dy = pointB.y - pointA.y

    local length = math.sqrt(dx * dx + dy * dy)
    if length == 0 then return end

    -- Perpendicular unit vector scaled by half the width
    local perpX =  (-dy / length) * (width / 2)
    local perpY =  ( dx / length) * (width / 2)

    local corners = {}

    corners[1] = vec3(pointA.x + perpX, pointA.y + perpY, pointA.z or 0)
    corners[2] = vec3(pointA.x - perpX, pointA.y - perpY, pointA.z or 0)
    corners[3] = vec3(pointB.x - perpX, pointB.y - perpY, pointB.z or 0)

    -- corners[4..7] are the extra return values from the last vec3 call
    local c4, c5, c6, c7 = vec3(pointB.x + perpX, pointB.y + perpY, pointB.z or 0)
    corners[4] = c4
    corners[5] = c5
    corners[6] = c6
    corners[7] = c7

    return corners
end

-- ──────────────────────────────────────────────────────────
-- TerritoryHelper.calculateRectangleBounds(zoneData)
--   Given a zone config table with `topPoint`, `bottomPoint`,
--   and optional `width`, returns:
--     centre  (vec3),  width  (number),
--     length  (number), heading (number)
-- ──────────────────────────────────────────────────────────
function TerritoryHelper.calculateRectangleBounds(zoneData)
    -- Guard: need both endpoints
    if not (zoneData and zoneData.topPoint and zoneData.bottomPoint) then
        return vec3(0, 0, 0), 0, 0, 0
    end

    local topPt = vec3(
        zoneData.topPoint.x,
        zoneData.topPoint.y,
        zoneData.topPoint.z or 0
    )
    local botPt = vec3(
        zoneData.bottomPoint.x,
        zoneData.bottomPoint.y,
        zoneData.bottomPoint.z or 0
    )

    local centre  = (topPt + botPt) * 0.5
    local length  = #(topPt - botPt)
    local heading = GetHeadingFromVector_2d(botPt.x - topPt.x, botPt.y - topPt.y)
    local width   = (zoneData.width or 50.0) + 0.0

    return centre, width, length + 0.0, heading
end

-- ──────────────────────────────────────────────────────────
-- TerritoryHelper.hexToRgb(hexColor)
--   Converts a CSS hex colour string ("#RRGGBB" or "#RGB")
--   to three integers (r, g, b) in the 0-255 range.
--   Returns 100, 100, 100 for invalid inputs.
-- ──────────────────────────────────────────────────────────
function TerritoryHelper.hexToRgb(hexColor)
    if not hexColor or hexColor == "" then
        return 100, 100, 100
    end

    local clean = hexColor:gsub("#", "")

    local r = tonumber(string.sub(clean, 1, 2), 16) or 100
    local g = tonumber(string.sub(clean, 3, 4), 16) or 100
    local b = tonumber(string.sub(clean, 5, 6), 16) or 100

    return r, g, b
end

-- ──────────────────────────────────────────────────────────
-- TerritoryHelper.hexToBlipColor(hexColor)
--   Converts a CSS hex colour to the RGBA integer format
--   used by GTA blip colour setters (0xRRGGBBFF).
--   Expands 3-char shorthand (#RGB → #RRGGBB).
--   Returns 0xFFFFFFFF (white) for invalid inputs.
-- ──────────────────────────────────────────────────────────
function TerritoryHelper.hexToBlipColor(hexColor)
    if not hexColor or hexColor == "" then
        return 0xFFFFFFFF
    end

    local clean = hexColor:gsub("#", ""):upper()

    -- Expand shorthand hex (#RGB → #RRGGBB)
    if #clean == 3 then
        local r1 = string.sub(clean, 1, 1)
        local g1 = string.sub(clean, 2, 2)
        local b1 = string.sub(clean, 3, 3)
        clean = r1 .. r1 .. g1 .. g1 .. b1 .. b1
    end

    if #clean ~= 6 then
        return 0xFFFFFFFF
    end

    -- Build "0xRRGGBBFF" and parse as hex integer
    local hexStr    = "0x" .. clean .. "FF"
    local colorInt  = tonumber(hexStr)

    return colorInt or 0xFFFFFFFF
end
