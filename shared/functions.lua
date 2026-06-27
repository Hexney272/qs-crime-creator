-- ============================================================
-- shared/functions.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Global logging helpers, Lua stdlib extensions, and shared
-- math/utility functions used across the entire resource.
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- Resource version (read from fxmanifest metadata)
-- ──────────────────────────────────────────────────────────
local resourceVersion = GetResourceMetadata(GetCurrentResourceName(), "version", 0)

-- ──────────────────────────────────────────────────────────
-- Debug(...)
--   Prints a coloured debug message to the console ONLY when
--   Config.Debug is true.  Tables are JSON-encoded first.
--   Prefix: "^5[DEBUG <version>]^7"
-- ──────────────────────────────────────────────────────────
function Debug(...)
    if not Config.Debug then return end

    -- Collect up to 8 variadic arguments into an array
    local args = {}
    local a1, a2, a3, a4, a5, a6, a7, a8 = ...
    args[1] = a1 ; args[2] = a2 ; args[3] = a3 ; args[4] = a4
    args[5] = a5 ; args[6] = a6 ; args[7] = a7 ; args[8] = a8

    -- JSON-encode any table values for readability
    for i, v in ipairs(args) do
        if "table" == type(v) then
            args[i] = json.encode(v)
        end
    end

    print("^5[DEBUG " .. resourceVersion .. "]^7", table.unpack(args))
end

-- ──────────────────────────────────────────────────────────
-- Warning(...)
--   Prints a yellow warning message.
--   Prefix: "^3CRIME WARNING:^0 "
-- ──────────────────────────────────────────────────────────
function Warning(...)
    local message = "^3CRIME WARNING:^0 "

    local args = {}
    local a1, a2, a3, a4, a5, a6, a7 = ...
    args[1]=a1 ; args[2]=a2 ; args[3]=a3 ; args[4]=a4
    args[5]=a5 ; args[6]=a6 ; args[7]=a7

    for _, v in pairs(args) do
        message = message .. tostring(v) .. "\t"
    end

    print(message)
end

-- ──────────────────────────────────────────────────────────
-- Info(...)
--   Prints a cyan informational message.
--   Tables are JSON-encoded.  Prefix: "^5CRIME INFO:^0 "
-- ──────────────────────────────────────────────────────────
function Info(...)
    local message = "^5CRIME INFO:^0 "

    local args = {}
    local a1, a2, a3, a4, a5, a6, a7 = ...
    args[1]=a1 ; args[2]=a2 ; args[3]=a3 ; args[4]=a4
    args[5]=a5 ; args[6]=a6 ; args[7]=a7

    for _, v in pairs(args) do
        if "table" == type(v) then
            message = message .. json.encode(v) .. "\t"
        else
            message = message .. tostring(v) .. "\t"
        end
    end

    print(message)
end

-- ──────────────────────────────────────────────────────────
-- Error(...)
--   Prints a red error message.  Tables are JSON-encoded.
--   Prefix: "^1CRIME ERROR:^0 "
-- ──────────────────────────────────────────────────────────
function Error(...)
    local message = "^1CRIME ERROR:^0 "

    local args = {}
    local a1, a2, a3, a4, a5, a6, a7 = ...
    args[1]=a1 ; args[2]=a2 ; args[3]=a3 ; args[4]=a4
    args[5]=a5 ; args[6]=a6 ; args[7]=a7

    for _, v in pairs(args) do
        if "table" == type(v) then
            message = message .. json.encode(v) .. "\t"
        else
            message = message .. tostring(v) .. "\t"
        end
    end

    print(message)
end

-- ──────────────────────────────────────────────────────────
-- LoopError(...)
--   Spawns a thread that repeatedly prints a red
--   "[ERROR]" message every 5 seconds.
--   Used to flag critical non-recoverable failures.
-- ──────────────────────────────────────────────────────────
function LoopError(...)
    local errorMsg = table.unpack({ ... })

    CreateThread(function()
        while true do
            print("^1[ERROR]^7", errorMsg)
            Wait(5000)
        end
    end)
end

-- ──────────────────────────────────────────────────────────
-- table.includes(tbl, value)
--   Returns true if any value in `tbl` equals `value`.
-- ──────────────────────────────────────────────────────────
function table.includes(tbl, value)
    if not tbl then return false end

-- table.contains is an alias for table.includes (used in some modules)
function table.contains(tbl, value)
    return table.includes(tbl, value)
end

    for _, v in pairs(tbl) do
        if v == value then return true end
    end

    return false
end

-- ──────────────────────────────────────────────────────────
-- table.find(tbl, predicateOrValue)
--   Searches `tbl` for the first element that matches.
--   If `predicateOrValue` is a function it is called as
--     predicate(value, key) → truthy to match.
--   Otherwise strict equality is used.
--   Returns (value, key) on match, or (false, false).
-- ──────────────────────────────────────────────────────────
function table.find(tbl, predicateOrValue)
    if not tbl then return false, false end

    for k, v in pairs(tbl) do
        if "function" == type(predicateOrValue) then
            if predicateOrValue(v, k) then
                return v, k
            end
        elseif v == predicateOrValue then
            return v, k
        end
    end

    return false, false
end

-- ──────────────────────────────────────────────────────────
-- string.split(str, separator)
--   Splits `str` on `separator` (default ":").
--   Returns a table of substrings.
-- ──────────────────────────────────────────────────────────
function string.split(str, separator)
    separator = separator or ":"

    local parts   = {}
    local pattern = string.format("([^%s]+)", separator)

    str:gsub(pattern, function(part)
        parts[#parts + 1] = part
    end)

    return parts
end

-- ──────────────────────────────────────────────────────────
-- table.filter(tbl, predicate)
--   Returns a new table containing only the elements for
--   which predicate(value, key, tbl) returns truthy.
-- ──────────────────────────────────────────────────────────
function table.filter(tbl, predicate)
    local result = {}

    for k, v in pairs(tbl) do
        if predicate(v, k, tbl) then
            result[#result + 1] = v
        end
    end

    return result
end

-- ──────────────────────────────────────────────────────────
-- table.map(tbl, transform)
--   Returns a new table where each element is the result of
--   transform(value, key, tbl).
-- ──────────────────────────────────────────────────────────
function table.map(tbl, transform)
    local result = {}

    for k, v in pairs(tbl) do
        result[#result + 1] = transform(v, k, tbl)
    end

    return result
end

-- ──────────────────────────────────────────────────────────
-- table.slice(tbl, startIdx, endIdx, step)
--   Returns a sequential sub-array of `tbl`.
--   Defaults: startIdx=1, endIdx=#tbl, step=1.
-- ──────────────────────────────────────────────────────────
function table.slice(tbl, startIdx, endIdx, step)
    local result = {}
    local from   = startIdx or 1
    local to     = endIdx   or #tbl
    local by     = step     or 1

    for i = from, to, by do
        result[#result + 1] = tbl[i]
    end

    return result
end

-- ──────────────────────────────────────────────────────────
-- string.includes(str, valueOrTable)  (re-declared here for
--   files that only load functions.lua without utils.lua)
--   Returns true if `str` equals `valueOrTable` (string) or
--   is contained in `valueOrTable` (table).
-- ──────────────────────────────────────────────────────────
function string.includes(str, valueOrTable)
    if "string" == type(valueOrTable) then
        return str == valueOrTable
    elseif "table" == type(valueOrTable) then
        for _, v in ipairs(valueOrTable) do
            if str == v then return true end
        end
        return false
    end
end

-- ──────────────────────────────────────────────────────────
-- DependencyCheck(dependencyMap)
--   Iterates a { ["resourceName"] = value } map and returns
--   the value associated with the FIRST resource that is
--   currently in the "started" state.
--   Returns false if no dependency is running.
-- ──────────────────────────────────────────────────────────
function DependencyCheck(dependencyMap)
    for resourceName, value in pairs(dependencyMap) do
        local state = GetResourceState(resourceName)
        if state:find("started") ~= nil then
            return value
        end
    end

    return false
end

-- ──────────────────────────────────────────────────────────
-- FormatTime(seconds)
--   Converts a number of seconds to a human-readable string:
--     < 60         → "N seconds"
--     < 3600       → "N min"
--     < 86400      → "N hours"
--     >= 86400     → "N days"
-- ──────────────────────────────────────────────────────────
function FormatTime(seconds)
    if seconds < 60 then
        return seconds .. " seconds"
    elseif seconds < 3600 then
        return math.floor(seconds / 60) .. " min"
    elseif seconds < 86400 then
        return math.floor(seconds / 3600) .. " hours"
    else
        return math.floor(seconds / 86400) .. " days"
    end
end

-- ──────────────────────────────────────────────────────────
-- GetCoordsWithOffset(baseCoords, offset)
--   Returns a new vector4 that is `baseCoords` (vector4 with
--   heading in .w) shifted by `offset` (vector3 x/y/z).
--   The offset is rotated to align with the entity's heading
--   before being applied, so x/y are lateral/forward in
--   local space.
-- ──────────────────────────────────────────────────────────
function GetCoordsWithOffset(baseCoords, offset)
    local headingRad = math.rad(baseCoords.w + 90)
    local cosH       = math.cos(headingRad)
    local sinH       = math.sin(headingRad)

    -- Rotate offset.x / offset.y by the entity heading
    local newX = baseCoords.x + offset.x * cosH - offset.y * sinH
    local newY = baseCoords.y + offset.x * sinH + offset.y * cosH
    local newZ = baseCoords.z + offset.z

    return vec4(newX, newY, newZ, baseCoords.w)
end

-- ──────────────────────────────────────────────────────────
-- RotationToDirection(rotation)
--   Converts a GTA rotation vector (degrees, pitch/roll/yaw)
--   to a normalised direction vector { x, y, z }.
--   Returns a plain table (not a FiveM vector type).
-- ──────────────────────────────────────────────────────────
function RotationToDirection(rotation)
    -- Convert degrees → radians per component
    local radians = {
        x = (math.pi / 180) * rotation.x,
        y = (math.pi / 180) * rotation.y,
        z = (math.pi / 180) * rotation.z,
    }

    local cosX = math.abs(math.cos(radians.x))

    return {
        x = -math.sin(radians.z) * cosX,
        y =  math.cos(radians.z) * cosX,
        z =  math.sin(radians.x),
    }
end

-- ──────────────────────────────────────────────────────────
-- RayCastGamePlayCamera(distance)
--   Fires a ray from the gameplay camera forward by
--   `distance` units and returns the world-space hit
--   point and the current camera rotation.
--   Returns (hitCoords vec3, camRotation).
-- ──────────────────────────────────────────────────────────
function RayCastGamePlayCamera(distance)
    local camRot    = GetGameplayCamRot()
    local camCoords = GetGameplayCamCoord()
    local direction = RotationToDirection(camRot)

    -- Project the camera position forward along the direction vector
    local hitCoords = vec3(
        camCoords.x + direction.x * distance,
        camCoords.y + direction.y * distance,
        camCoords.z + direction.z * distance
    )

    return hitCoords, camRot
end
