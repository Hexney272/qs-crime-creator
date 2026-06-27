-- ============================================================
-- shared/utils.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Utility/helper library shared between client and server.
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- Global Utils namespace + character/number seed tables
-- ──────────────────────────────────────────────────────────
Utils = {}
Utils.RenderList  = {}   -- Active render-loop entries (markers, drawText)
Utils.Characters  = {}   -- A-Z + a-z used for random-ID generation
Utils.Numbers     = {}   -- 0-9  used for random-ID generation

-- Populate Numbers: ASCII 48-57 → "0".."9"
for asciiCode = 48, 57, 1 do
    table.insert(Utils.Numbers, string.char(asciiCode))
end

-- Populate Characters: ASCII 65-90 → "A".."Z"
for asciiCode = 65, 90, 1 do
    table.insert(Utils.Characters, string.char(asciiCode))
end

-- Populate Characters (continued): ASCII 97-122 → "a".."z"
for asciiCode = 97, 122, 1 do
    table.insert(Utils.Characters, string.char(asciiCode))
end

-- ──────────────────────────────────────────────────────────
-- Utils.GenerateRandomUid(numLetters, numDigits)
--   Returns a random string of `numLetters` alpha chars
--   followed by `numDigits` numeric chars.
-- ──────────────────────────────────────────────────────────
function Utils.GenerateRandomUid(numLetters, numDigits)
    math.randomseed(GetGameTimer())

    local result = ""

    -- Append random letters
    for i = 1, numLetters, 1 do
        local charIndex = math.random(#Utils.Characters)
        result = result .. Utils.Characters[charIndex]
    end

    -- Append random digits
    for i = 1, numDigits, 1 do
        local digitIndex = math.random(#Utils.Numbers)
        result = result .. Utils.Numbers[digitIndex]
    end

    return result
end

-- ──────────────────────────────────────────────────────────
-- Utils.GenerateUniqueId(existingTable, numLetters, numDigits)
--   Like GenerateRandomUid but keeps regenerating until the
--   key is not already present in `existingTable`.
-- ──────────────────────────────────────────────────────────
function Utils.GenerateUniqueId(existingTable, numLetters, numDigits)
    local uid = Utils.GenerateRandomUid(numLetters, numDigits)

    -- Retry until the generated key is not already in use
    while true do
        if not existingTable[uid] then
            break
        end
        uid = Utils.GenerateRandomUid(numLetters, numDigits)
    end

    return uid
end

-- ──────────────────────────────────────────────────────────
-- Utils.GetForwardVector(rotation)
--   Converts a rotation vector (degrees) to a normalised
--   forward direction vector3.
-- ──────────────────────────────────────────────────────────
function Utils.GetForwardVector(rotation)
    -- Convert degrees to radians
    local rotRad  = rotation * (math.pi / 180.0)
    local cosX    = math.abs(math.cos(rotRad.x))

    return vec3(
        -math.sin(rotRad.z) * cosX,
         math.cos(rotRad.z) * cosX,
         math.sin(rotRad.x)
    )
end

-- ──────────────────────────────────────────────────────────
-- Utils.SplitString(str, separator)
--   Splits `str` on `separator` (default ":") and returns
--   a table of substrings.
-- ──────────────────────────────────────────────────────────
function Utils.SplitString(str, separator)
    separator = separator or ":"

    local parts   = {}
    local pattern = string.format("([^%s]+)", separator)

    str:gsub(pattern, function(part)
        parts[#parts + 1] = part
    end)

    return parts
end

-- ──────────────────────────────────────────────────────────
-- Utils.BreakString(str, maxLength)
--   Truncates `str` to `maxLength` characters.
--   Tries to break at a word boundary and appends "...".
-- ──────────────────────────────────────────────────────────
function Utils.BreakString(str, maxLength)
    if not str then
        return ""
    end

    if maxLength >= #str then
        return str
    end

    local truncated = string.sub(str, 1, maxLength)

    -- Attempt to break at the last space before the cut-off
    local spacePos = string.find(truncated, " ", #truncated - 5)
    if spacePos then
        truncated = string.sub(truncated, 1, spacePos - 1)
    end

    return truncated .. "..."
end

-- ──────────────────────────────────────────────────────────
-- Utils.JsonEncode(value)
--   JSON-encodes `value`, first converting any FiveM vector
--   types (vector2/3/4) to plain Lua tables so json.encode
--   can handle them.
-- ──────────────────────────────────────────────────────────
function Utils.JsonEncode(value)
    -- Inner recursive converter: vectors → plain tables
    local function convertVectorsToTables(tbl)
        local converted = {}
        for key, val in pairs(tbl) do
            local valType = type(val)
            if "vector4" == valType then
                converted[key] = { x = val.x, y = val.y, z = val.z, w = val.w }
            elseif "vector3" == valType then
                converted[key] = { x = val.x, y = val.y, z = val.z }
            elseif "vector2" == valType then
                converted[key] = { x = val.x, y = val.y }
            elseif "table" == valType then
                converted[key] = __utilsJsonEncodeInternalDecode(val)
            else
                converted[key] = val
            end
        end
        return converted
    end

    __utilsJsonEncodeInternalDecode = convertVectorsToTables

    local plainTable = __utilsJsonEncodeInternalDecode(value)
    return json.encode(plainTable)
end

-- ──────────────────────────────────────────────────────────
-- Utils.JsonDecode(jsonStr)
--   JSON-decodes `jsonStr`, converting any plain x/y/z[/w]
--   tables back to FiveM vector types.
-- ──────────────────────────────────────────────────────────
function Utils.JsonDecode(jsonStr)
    -- Inner recursive converter: plain tables → vectors
    local function convertTablesToVectors(tbl)
        local converted = {}
        for key, val in pairs(tbl) do
            local valType = type(val)
            if "table" == valType then
                if val.x then
                    if val.y then
                        if val.z then
                            if val.w then
                                -- vector4
                                if Utils.TableCount(val) == 4 then
                                    converted[key] = vector4(val.x, val.y, val.z, val.w)
                                end
                            else
                                -- vector3
                                if Utils.TableCount(val) == 3 then
                                    converted[key] = vector3(val.x, val.y, val.z)
                                end
                            end
                        else
                            -- vector2
                            if Utils.TableCount(val) == 2 then
                                converted[key] = vector2(val.x, val.y)
                            end
                        end
                    end
                else
                    converted[key] = __utilsJsonDecodeInternalDecode(val)
                end
            else
                converted[key] = val
            end
        end
        return converted
    end

    __utilsJsonDecodeInternalDecode = convertTablesToVectors

    local decoded = json.decode(jsonStr)
    return __utilsJsonDecodeInternalDecode(decoded)
end

-- ──────────────────────────────────────────────────────────
-- Utils.TableCopy(tbl)
--   Deep-copies a Lua table (recursive for nested tables).
-- ──────────────────────────────────────────────────────────
function Utils.TableCopy(tbl)
    local copy = {}
    for key, val in pairs(tbl) do
        if "table" == type(val) then
            copy[key] = Utils.TableCopy(val)
        else
            copy[key] = val
        end
    end
    return copy
end

-- ──────────────────────────────────────────────────────────
-- Utils.TableCount(tbl)
--   Returns the number of key/value pairs in `tbl`
--   (works for non-sequential / mixed tables, unlike #).
-- ──────────────────────────────────────────────────────────
function Utils.TableCount(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- ──────────────────────────────────────────────────────────
-- Utils.PrintT(value)
--   Pretty-prints any value (table or primitive) to the
--   console, with recursive indentation for nested tables.
--   Guards against circular references via a visited set.
-- ──────────────────────────────────────────────────────────
function Utils.PrintT(value)
    local visited = {}

    local function printRecursive(val, indent)
        local valKey = tostring(val)

        if visited[valKey] then
            -- Circular reference detected
            print(indent .. "*" .. valKey)
            return
        end

        visited[valKey] = true

        if "table" == type(val) then
            for k, v in pairs(val) do
                if "table" == type(v) then
                    print(indent .. "[" .. k .. "] => " .. tostring(val) .. " {")
                    printRecursive(v, indent .. string.rep(" ", string.len(k) + 8))
                    print(indent .. string.rep(" ", string.len(k) + 6) .. "}")
                else
                    print(indent .. "[" .. k .. "] => " .. tostring(v))
                end
            end
        else
            print(indent .. tostring(val))
        end
    end

    printRecursive(value, "  ")
end

-- ──────────────────────────────────────────────────────────
-- Utils.getCentreOfTwoVector3D(vecA, vecB)
--   Returns the midpoint between two vector3 values.
-- ──────────────────────────────────────────────────────────
function Utils.getCentreOfTwoVector3D(vecA, vecB)
    return vec3(
        (vecA.x + vecB.x) / 2,
        (vecA.y + vecB.y) / 2,
        (vecA.z + vecB.z) / 2
    )
end

-- ──────────────────────────────────────────────────────────
-- Utils.CreateBlip(opts)
--   Creates and configures a map blip.
--   opts: { location, sprite, color, scale, display,
--           shortRange, highDetail, text }
-- ──────────────────────────────────────────────────────────
function Utils.CreateBlip(opts)
    local blip = AddBlipForCoord(opts.location.x, opts.location.y, opts.location.z)

    local isShortRange = false
    if opts.shortRange then
        isShortRange = opts.shortRange
    end

    SetBlipSprite(blip,   opts.sprite      or 1)
    SetBlipColour(blip,   opts.color       or 4)
    SetBlipScale(blip,    opts.scale       or 1.0)
    SetBlipDisplay(blip,  opts.display     or 4)
    SetBlipAsShortRange(blip, isShortRange)
    SetBlipHighDetail(blip, opts.highDetail ~= nil and opts.highDetail or true)

    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(opts.text)
    EndTextCommandSetBlipName(blip)

    return blip
end

-- ──────────────────────────────────────────────────────────
-- Utils.RemoveBlip(blip)
--   Removes a blip from the map.
-- ──────────────────────────────────────────────────────────
function Utils.RemoveBlip(blip)
    RemoveBlip(blip)
end

-- ──────────────────────────────────────────────────────────
-- Utils.CreatePed(modelHash, spawnCoords, frozen)
--   Spawns a ped at `spawnCoords` (vector4 with heading).
--   If `frozen` is true the ped is invincible, frozen and
--   has its AI events blocked.
-- ──────────────────────────────────────────────────────────
function Utils.CreatePed(modelHash, spawnCoords, frozen)
    -- Accept model name strings as well as hashes
    if "string" == type(modelHash) then
        modelHash = joaat(modelHash)
    end

    lib.requestModel(modelHash, Config.DefaultRequestModelTimeout)

    local ped = CreatePed(
        7,
        modelHash,
        spawnCoords.x, spawnCoords.y, spawnCoords.z, spawnCoords.w,
        false, false
    )

    if frozen then
        SetEntityInvincible(ped, true)
        FreezeEntityPosition(ped, true)
        SetEntityInvincible(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
    end

    SetModelAsNoLongerNeeded(modelHash)
    return ped
end

-- ──────────────────────────────────────────────────────────
-- Utils.AddMarkerToRenderList(name, opts)
--   Registers a marker for the per-frame render loop.
--   Returns the render entry table.
-- ──────────────────────────────────────────────────────────
function Utils.AddMarkerToRenderList(name, opts)
    if not name or not opts then return end

    local entry = { name = name, type = "marker", opts = opts }
    table.insert(Utils.RenderList, entry)
    return entry
end

-- ──────────────────────────────────────────────────────────
-- Utils.RemoveMarkerFromRenderList(entry)
--   Removes a previously-registered marker render entry.
-- ──────────────────────────────────────────────────────────
function Utils.RemoveMarkerFromRenderList(entry)
    for i, renderItem in ipairs(Utils.RenderList) do
        if renderItem == entry then
            table.remove(Utils.RenderList, i)
            return
        end
    end
end

-- ──────────────────────────────────────────────────────────
-- Utils.AddDrawTextToRenderList(name, opts)
--   Registers a 3-D text label for the per-frame render loop.
-- ──────────────────────────────────────────────────────────
function Utils.AddDrawTextToRenderList(name, opts)
    if not name or not opts then return end

    local entry = { name = name, type = "drawText", opts = opts }
    table.insert(Utils.RenderList, entry)
    return entry
end

-- ──────────────────────────────────────────────────────────
-- Utils.RemoveDrawTextFromRenderList(entry)
--   Removes a previously-registered drawText render entry.
-- ──────────────────────────────────────────────────────────
function Utils.RemoveDrawTextFromRenderList(entry)
    for i, renderItem in ipairs(Utils.RenderList) do
        if renderItem == entry then
            table.remove(Utils.RenderList, i)
            return
        end
    end
end

-- ──────────────────────────────────────────────────────────
-- Utils.RotateVectorFlat(vec, angleDegrees)
--   Rotates a vector2/3/4 around the Z axis by `angleDegrees`.
--   The z (and w) components are preserved unchanged.
-- ──────────────────────────────────────────────────────────
function Utils.RotateVectorFlat(vec, angleDegrees)
    local angleRad = angleDegrees / 57.2958
    local cosA = math.cos(angleRad)
    local sinA = math.sin(angleRad)

    local vecType = type(vec)

    if "vector4" == vecType then
        return vector4(
            cosA * vec.x - sinA * vec.y,
            sinA * vec.x + cosA * vec.y,
            vec.z,
            vec.w
        )
    elseif "vector3" == vecType then
        return vector3(
            cosA * vec.x - sinA * vec.y,
            sinA * vec.x + cosA * vec.y,
            vec.z
        )
    elseif "vector2" == vecType then
        return vector2(
            cosA * vec.x - sinA * vec.y,
            sinA * vec.x + cosA * vec.y
        )
    end
end

-- ──────────────────────────────────────────────────────────
-- Utils.CreateCamera(name, coords, rotation, activate,
--                    trackEntity, transitionTime)
--   Creates a scripted camera, optionally activates it and
--   optionally points it at an entity.
-- ──────────────────────────────────────────────────────────
function Utils.CreateCamera(name, coords, rotation, activate, trackEntity, transitionTime)
    local cam = CreateCamWithParams(
        name,
        coords.x, coords.y, coords.z,
        0, 0, 0,
        50.0
    )

    SetCamCoord(cam, coords.x, coords.y, coords.z)
    SetCamRot(cam, rotation.x, rotation.y, rotation.z, 2)

    if activate then
        SetCamActive(cam, true)
        RenderScriptCams(true, true, transitionTime or 0, true, true)
    end

    if trackEntity then
        PointCamAtEntity(cam, trackEntity)
    end

    return cam
end

-- ──────────────────────────────────────────────────────────
-- Utils.DrawMarker(opts)
--   Draws a GTA marker every frame. opts table fields:
--   type, location, direction, rotation, scale,
--   red, green, blue, alpha, bobUpAndDown, faceCamera,
--   p19, rotate
-- ──────────────────────────────────────────────────────────
function Utils.DrawMarker(opts)
    -- Require a valid location with all three components
    if not (opts.location and opts.location.x
            and opts.location.y and opts.location.z) then
        return
    end

    -- Direction components (default to forward)
    local dirX = (opts.direction and opts.direction.x) or 1.0
    local dirY = (opts.direction and opts.direction.y) or 0.0
    local dirZ = (opts.direction and opts.direction.z) or 0.0

    -- Rotation components
    local rotX = (opts.rotation and opts.rotation.x) or 1.0
    local rotY = (opts.rotation and opts.rotation.y) or 0.0
    local rotZ = (opts.rotation and opts.rotation.z) or 0.0

    -- Scale components (default 1.0)
    local scaleX = (opts.scale and opts.scale.x) or 1.0
    local scaleY = (opts.scale and opts.scale.y) or 1.0
    local scaleZ = (opts.scale and opts.scale.z) or 1.0

    -- Colour / visual properties
    local red          = opts.red          or 255
    local green        = opts.green        or 255
    local blue         = opts.blue         or 255
    local alpha        = opts.alpha        or 255
    local bobUpAndDown = opts.bobUpAndDown or false
    local faceCamera   = opts.faceCamera   == nil or opts.faceCamera  -- default true
    local p19          = opts.p19          or 2
    local rotate       = opts.rotate       or false

    DrawMarker(
        opts.type or 0,
        opts.location.x, opts.location.y, opts.location.z,
        dirX, dirY, dirZ,
        rotX, rotY, rotZ,
        scaleX, scaleY, scaleZ,
        red, green, blue, alpha,
        bobUpAndDown, faceCamera, p19, rotate
    )
end

-- ──────────────────────────────────────────────────────────
-- Utils.ShowNotification(message)
--   Displays a GTA notification on screen.
-- ──────────────────────────────────────────────────────────
function Utils.ShowNotification(message)
    SetNotificationTextEntry("STRING")
    AddTextComponentSubstringPlayerName(message)
    DrawNotification(false, true)
end

-- ──────────────────────────────────────────────────────────
-- Utils.ShowHelpNotification(message)
--   Displays a context/help notification (bottom-left hint).
-- ──────────────────────────────────────────────────────────
function Utils.ShowHelpNotification(message)
    AddTextEntry("housingHelp", message)
    DisplayHelpTextThisFrame("housingHelp", false)
end

-- ──────────────────────────────────────────────────────────
-- Utils.DrawText3D(opts)
--   Draws a 3-D world-space text label every frame.
--   opts: { location, text, font, size, red, green, blue, alpha }
-- ──────────────────────────────────────────────────────────
function Utils.DrawText3D(opts)
    local worldPos = vector3(opts.location.x, opts.location.y, opts.location.z)

    -- Project world position to screen 2-D
    local onScreen, screenX, screenY = World3dToScreen2d(
        worldPos.x, worldPos.y, worldPos.z
    )

    local camPos  = GetGameplayCamCoords()
    local distance = GetDistanceBetweenCoords(camPos, worldPos.x, worldPos.y, worldPos.z, true)

    -- Scale text inversely with distance
    local sizeOpt = opts.size or 1
    local scaleFactor = (sizeOpt / distance) * 2
    local fovScale    = (1 / GetGameplayCamFov()) * 100
    scaleFactor       = scaleFactor * fovScale

    if onScreen then
        SetTextScale(0.0 * scaleFactor, 0.55 * scaleFactor)
        SetTextFont(opts.font  or 1)
        SetTextColour(
            opts.red   or 255,
            opts.green or 255,
            opts.blue  or 255,
            opts.alpha or 255
        )
        SetTextDropshadow(0, 0, 0, 0, 255)
        SetTextDropShadow()
        SetTextOutline()
        SetTextEntry("STRING")
        SetTextCentre(1)
        AddTextComponentString(opts.text)
        DrawText(screenX, screenY)
    end
end

-- ──────────────────────────────────────────────────────────
-- Server-only / Client-only branching
-- IsDuplicityVersion() returns true on the server
-- ──────────────────────────────────────────────────────────
if IsDuplicityVersion() then

    -- ── SERVER ──────────────────────────────────────────

    -- Utils.TriggerClientEvent(eventName, playerId, ...)
    --   Fires a namespaced client event from the server.
    function Utils.TriggerClientEvent(eventName, playerId, ...)
        local fullEventName = string.format("%s:%s", Protected.ResourceName, eventName)
        TriggerClientEvent(fullEventName, playerId, ...)

        if Config.Debug then
            Utils.Log(string.format("Triggering client event: %s (%i).", fullEventName, playerId))
        end
    end

    -- Utils.GetDatabaseName()
    --   Parses the mysql_connection_string convar and
    --   returns just the database name string.
    function Utils.GetDatabaseName()
        local connStr = GetConvar("mysql_connection_string", "Empty")

        if not connStr or connStr == "Empty" then
            return false
        end

        -- Format: "...database=<name>;..." or "mysql://<user>:<pass>@<host>/<name>?..."
        local dbStart, dbEnd = string.find(connStr, "database=")

        if not dbStart or not dbEnd then
            -- Try mysql:// URI format
            local protoStart, protoEnd = string.find(connStr, "mysql://")

            if not protoStart or not protoEnd then
                return false
            end

            local _, atEnd       = string.find(connStr, "@", protoEnd)
            local slashStart, _  = string.find(connStr, "/", atEnd + 1)
            local qStart, qEnd   = string.find(connStr, "?")

            local nameEnd = qEnd and (qEnd - 1) or #connStr
            return string.sub(connStr, slashStart + 1, nameEnd)
        else
            -- Format: database=<name>;...
            local semiStart, _ = string.find(connStr, ";", dbEnd)
            local nameEnd      = semiStart and (semiStart - 1) or #connStr
            return string.sub(connStr, dbEnd + 1, nameEnd)
        end
    end

else

    -- ── CLIENT ──────────────────────────────────────────

    -- Utils.TriggerServerEvent(eventName, ...)
    --   Fires a namespaced server event from the client.
    function Utils.TriggerServerEvent(eventName, ...)
        local fullEventName = string.format("%s:%s", Protected.ResourceName, eventName)
        TriggerServerEvent(fullEventName, ...)

        if Config.Debug then
            Utils.Log(string.format("Triggering server event: %s.", fullEventName))
        end
    end

end

-- ──────────────────────────────────────────────────────────
-- Utils.RegisterNetEvent(eventName, handler)
--   Registers a network event with the resource namespace
--   and attaches `handler`.  Logs trigger calls in Debug mode.
-- ──────────────────────────────────────────────────────────
function Utils.RegisterNetEvent(eventName, handler)
    local fullEventName = string.format("%s:%s", Protected.ResourceName, eventName)
    RegisterNetEvent(fullEventName)

    if Config.Debug then
        Utils.Log(string.format("Net event %s registered.", fullEventName))

        AddEventHandler(fullEventName, function(...)
            Utils.Log(string.format("Net event %s triggered.", fullEventName))
            handler(...)
        end)
    else
        AddEventHandler(fullEventName, handler)
    end
end

-- ──────────────────────────────────────────────────────────
-- Utils.RegisterEvent(eventName, handler)
--   Registers a local (non-network) event with the resource
--   namespace and attaches `handler`.
-- ──────────────────────────────────────────────────────────
function Utils.RegisterEvent(eventName, handler)
    local fullEventName = string.format("%s:%s", Protected.ResourceName, eventName)
    AddEventHandler(fullEventName, handler)
end

-- ──────────────────────────────────────────────────────────
-- Utils.DisableControlActions(...)
--   Disables one or more GTA control action IDs each frame.
-- ──────────────────────────────────────────────────────────
function Utils.DisableControlActions(...)
    local argCount = select("#", ...)
    for i = 1, argCount, 1 do
        local controlId = select(i, ...)
        DisableControlAction(0, controlId, true)
    end
end

-- ──────────────────────────────────────────────────────────
-- Utils.DrawEntityBoundingBox(entity, r, g, b, a)
--   Draws the full 3-D bounding box of `entity` as coloured
--   polygon faces + edge lines.
-- ──────────────────────────────────────────────────────────
function Utils.DrawEntityBoundingBox(entity, r, g, b, a)
    local corners = Utils.GetEntityBoundingBox(entity)
    Utils.DrawBoundingBox(corners, r, g, b, a)
end

-- ──────────────────────────────────────────────────────────
-- Utils.GetEntityBoundingBox(entity)
--   Returns 8 world-space corner vectors of the entity's
--   axis-aligned bounding box.
-- ──────────────────────────────────────────────────────────
function Utils.GetEntityBoundingBox(entity)
    local minDim, maxDim = GetModelDimensions(GetEntityModel(entity))
    local eps = 0.001
    local corners = {}

    -- Bottom 4 corners (z = minDim.z)
    corners[1] = GetOffsetFromEntityInWorldCoords(entity, minDim.x - eps, minDim.y - eps, minDim.z - eps)
    corners[2] = GetOffsetFromEntityInWorldCoords(entity, maxDim.x + eps, minDim.y - eps, minDim.z - eps)
    corners[3] = GetOffsetFromEntityInWorldCoords(entity, maxDim.x + eps, maxDim.y + eps, minDim.z - eps)
    corners[4] = GetOffsetFromEntityInWorldCoords(entity, minDim.x - eps, maxDim.y + eps, minDim.z - eps)

    -- Top 4 corners (z = maxDim.z)
    corners[5] = GetOffsetFromEntityInWorldCoords(entity, minDim.x - eps, minDim.y - eps, maxDim.z + eps)
    corners[6] = GetOffsetFromEntityInWorldCoords(entity, maxDim.x + eps, minDim.y - eps, maxDim.z + eps)
    corners[7] = GetOffsetFromEntityInWorldCoords(entity, maxDim.x + eps, maxDim.y + eps, maxDim.z + eps)
    corners[8] = GetOffsetFromEntityInWorldCoords(entity, minDim.x - eps, maxDim.y + eps, maxDim.z + eps)

    return corners
end

-- ──────────────────────────────────────────────────────────
-- Utils.Get2DEntityBoundingBox(entity)
--   Returns only the 4 bottom-face corners (2-D footprint).
-- ──────────────────────────────────────────────────────────
function Utils.Get2DEntityBoundingBox(entity)
    local minDim, maxDim = GetModelDimensions(GetEntityModel(entity))
    local eps = 0.001
    local corners = {}

    corners[1] = GetOffsetFromEntityInWorldCoords(entity, minDim.x - eps, minDim.y - eps, minDim.z - eps)
    corners[2] = GetOffsetFromEntityInWorldCoords(entity, maxDim.x + eps, minDim.y - eps, minDim.z - eps)
    corners[3] = GetOffsetFromEntityInWorldCoords(entity, maxDim.x + eps, maxDim.y + eps, minDim.z - eps)
    corners[4] = GetOffsetFromEntityInWorldCoords(entity, minDim.x - eps, maxDim.y + eps, minDim.z - eps)

    return corners
end

-- ──────────────────────────────────────────────────────────
-- Utils.DrawBoundingBox(corners, r, g, b, a)
--   Draws polygon faces and edges for the 8 corner points
--   returned by GetEntityBoundingBox.
-- ──────────────────────────────────────────────────────────
function Utils.DrawBoundingBox(corners, r, g, b, a)
    Utils.DrawPolyMatrix(Utils.GetBoundingBoxPolyMatrix(corners),  r,   g,   b,   a)
    Utils.DrawEdgeMatrix(Utils.GetBoundingBoxEdgeMatrix(corners), 255, 255, 255, 255)
end

-- ──────────────────────────────────────────────────────────
-- Utils.GetBoundingBoxPolyMatrix(corners)
--   Builds 12 triangles (2 per face × 6 faces) from the
--   8 bounding-box corner vectors.
-- ──────────────────────────────────────────────────────────
function Utils.GetBoundingBoxPolyMatrix(corners)
    local tris = {}

    -- Bottom face
    tris[1]  = { corners[3], corners[2], corners[1] }
    tris[2]  = { corners[4], corners[3], corners[1] }
    -- Top face
    tris[3]  = { corners[5], corners[6], corners[7] }
    tris[4]  = { corners[5], corners[7], corners[8] }
    -- Front face
    tris[5]  = { corners[3], corners[4], corners[7] }
    tris[6]  = { corners[8], corners[7], corners[4] }
    -- Back face
    tris[7]  = { corners[1], corners[2], corners[5] }
    tris[8]  = { corners[6], corners[5], corners[2] }
    -- Right face
    tris[9]  = { corners[2], corners[3], corners[6] }
    tris[10] = { corners[3], corners[7], corners[6] }
    -- Left face
    tris[11] = { corners[5], corners[8], corners[4] }
    tris[12] = { corners[5], corners[4], corners[1] }

    return tris
end

-- ──────────────────────────────────────────────────────────
-- Utils.GetBoundingBoxEdgeMatrix(corners)
--   Returns 12 edges (pairs of corner vectors) forming the
--   wireframe of the bounding box.
-- ──────────────────────────────────────────────────────────
function Utils.GetBoundingBoxEdgeMatrix(corners)
    local edges = {}

    -- Bottom ring
    edges[1]  = { corners[1], corners[2] }
    edges[2]  = { corners[2], corners[3] }
    edges[3]  = { corners[3], corners[4] }
    edges[4]  = { corners[4], corners[1] }
    -- Top ring
    edges[5]  = { corners[5], corners[6] }
    edges[6]  = { corners[6], corners[7] }
    edges[7]  = { corners[7], corners[8] }
    edges[8]  = { corners[8], corners[5] }
    -- Vertical pillars
    edges[9]  = { corners[1], corners[5] }
    edges[10] = { corners[2], corners[6] }
    edges[11] = { corners[3], corners[7] }
    edges[12] = { corners[4], corners[8] }

    return edges
end

-- ──────────────────────────────────────────────────────────
-- Utils.DrawPolyMatrix(triList, r, g, b, a)
--   Calls DrawPoly for each {p1,p2,p3} triangle in triList.
-- ──────────────────────────────────────────────────────────
function Utils.DrawPolyMatrix(triList, r, g, b, a)
    for i = 1, #triList, 1 do
        local tri = triList[i]
        DrawPoly(
            tri[1].x, tri[1].y, tri[1].z,
            tri[2].x, tri[2].y, tri[2].z,
            tri[3].x, tri[3].y, tri[3].z,
            r, g, b, a
        )
    end
end

-- ──────────────────────────────────────────────────────────
-- Utils.DrawEdgeMatrix(edgeList, r, g, b, a)
--   Calls DrawLine for each {p1,p2} edge pair in edgeList.
-- ──────────────────────────────────────────────────────────
function Utils.DrawEdgeMatrix(edgeList, r, g, b, a)
    for i = 1, #edgeList, 1 do
        local edge = edgeList[i]
        DrawLine(
            edge[1].x, edge[1].y, edge[1].z,
            edge[2].x, edge[2].y, edge[2].z,
            r, g, b, a
        )
    end
end

-- ──────────────────────────────────────────────────────────
-- Utils.DrawScaleform(scaleformHandle)
--   Draws a full-screen scaleform movie.
-- ──────────────────────────────────────────────────────────
function Utils.DrawScaleform(scaleformHandle)
    DrawScaleformMovieFullscreen(scaleformHandle, 255, 255, 255, 255)
end

-- ──────────────────────────────────────────────────────────
-- Utils.DisableControlAction(controlId)
--   Disables a single control action for the current frame.
-- ──────────────────────────────────────────────────────────
function Utils.DisableControlAction(controlId)
    DisableControlAction(0, controlId, true)
end

-- ──────────────────────────────────────────────────────────
-- Utils.CreateInstructional(controlList)
--   Builds and returns an instructional-buttons scaleform.
--   controlList: array of { codes = {…}, label = "…" }
-- ──────────────────────────────────────────────────────────
function Utils.CreateInstructional(controlList)
    local scaleform = Scaleforms.LoadMovie("INSTRUCTIONAL_BUTTONS")
    Scaleforms.PopVoid(scaleform, "CLEAR_ALL")
    Scaleforms.PopInt(scaleform, "SET_CLEAR_SPACE", 200)

    for slot = 1, #controlList, 1 do
        PushScaleformMovieFunction(scaleform, "SET_DATA_SLOT")
        PushScaleformMovieFunctionParameterInt(slot - 1)

        -- Push each button glyph for the control
        for codeIdx = 1, #controlList[slot].codes, 1 do
            local buttonStr = GetControlInstructionalButton(
                0,
                controlList[slot].codes[codeIdx],
                true
            )
            ScaleformMovieMethodAddParamPlayerNameString(buttonStr)
        end

        BeginTextCommandScaleformString("STRING")
        AddTextComponentScaleform(controlList[slot].label)
        EndTextCommandScaleformString()
        PopScaleformMovieFunctionVoid()
    end

    Scaleforms.PopVoid(scaleform, "DRAW_INSTRUCTIONAL_BUTTONS")
    return scaleform
end

-- ──────────────────────────────────────────────────────────
-- Utils.GetControls(...)
--   Resolves control key names (strings or {key,label} tables)
--   from the ActionControls global and returns their data.
-- ──────────────────────────────────────────────────────────
function Utils.GetControls(...)
    local resolved = {}

    -- Accept either a single array argument (table of strings/objects)
    -- or multiple vararg strings/objects
    local args
    local firstArg = select(1, ...)
    if select("#", ...) == 1 and type(firstArg) == "table" and (#firstArg > 0 or next(firstArg) ~= nil) then
        -- Called as Utils.GetControls({"key1","key2",...})
        -- but only treat it as a list if it has numeric keys (array)
        if firstArg[1] ~= nil then
            args = firstArg
        else
            -- It's a {key=..., label=...} single control descriptor
            args = { firstArg }
        end
    else
        -- Called as Utils.GetControls("key1","key2",...)
        args = { ... }
    end

    for i = 1, #args do
        local item      = args[i]
        local controlData = nil

        if "table" == type(item) then
            -- { key = "keyName", label = "override label" }
            controlData = ActionControls[item.key]
            if not controlData then
                Error("Utils.GetControls ::: ", item, " not found")
                return
            end
            controlData = table.deepclone and table.deepclone(controlData) or controlData
            controlData.label = item.label
        else
            controlData = ActionControls[item]
            if not controlData then
                Error("Utils.GetControls ::: ", item, " not found")
                return
            end
        end

        resolved[#resolved + 1] = controlData
    end

    return resolved
end

-- ──────────────────────────────────────────────────────────
-- Fly-cam state  (module-private)
-- ──────────────────────────────────────────────────────────
local flyCamPositionDirty = false
local flyCamRotationDirty = false

-- ──────────────────────────────────────────────────────────
-- Utils.HandleFlyCam(camHandle, opts)
--   Updates a free-roam camera's position and rotation based
--   on keyboard / mouse input.  Returns (newCoords, newRot).
--   opts: { boundPos, boundDist, mouse, keyboard,
--           updatePlayerCoords }
-- ──────────────────────────────────────────────────────────
function Utils.HandleFlyCam(camHandle, opts)
    if not opts then opts = {} end

    local boundPos  = opts.boundPos
    local boundDist = opts.boundDist

    -- Default mouse and keyboard enabled
    local useMouse    = (opts.mouse    == nil) or opts.mouse
    local useKeyboard = (opts.keyboard == nil) or opts.keyboard

    local camPos = GetCamCoord(camHandle)
    local camRot = GetCamRot(camHandle, 2)

    -- Raw mouse axis inputs
    local mouseX = GetDisabledControlNormal(0, 1)
    local mouseY = GetDisabledControlNormal(0, 2)

    -- Camera orientation matrix
    local rightVec, forwardVec, _, _ = GetCamMatrix(camHandle)

    local upVec = vector3(0.0, 0.0, 1.0)

    -- Flat right/forward vectors (z stripped) for panning
    local flatRight   = norm(vector3(rightVec.x,   rightVec.y,   0.0))
    local flatForward = norm(vector3(forwardVec.x, forwardVec.y, 0.0))

    local dt = GetFrameTime()

    -- ── Keyboard movement ──────────────────────────────
    if useKeyboard then
        -- Up / climb (E key code [2], down is [1])
        if IsDisabledControlPressed(0, ActionControls.up.codes[2]) then
            camPos = camPos + upVec * (CameraOptions.climbSpeed * dt)
            flyCamPositionDirty = true
        elseif IsDisabledControlPressed(0, ActionControls.up.codes[1]) then
            camPos = camPos - upVec * (CameraOptions.climbSpeed * dt)
            flyCamPositionDirty = true
        end

        -- Forward / backward
        if IsDisabledControlPressed(0, ActionControls.forward.codes[2]) then
            camPos = camPos + flatForward * (CameraOptions.moveSpeed * dt)
            flyCamPositionDirty = true
        elseif IsDisabledControlPressed(0, ActionControls.forward.codes[1]) then
            camPos = camPos - flatForward * (CameraOptions.moveSpeed * dt)
            flyCamPositionDirty = true
        end

        -- Strafe right / left
        if IsDisabledControlPressed(0, ActionControls.right.codes[1]) then
            camPos = camPos + flatRight * (CameraOptions.moveSpeed * dt)
            flyCamPositionDirty = true
        elseif IsDisabledControlPressed(0, ActionControls.right.codes[2]) then
            camPos = camPos - flatRight * (CameraOptions.moveSpeed * dt)
            flyCamPositionDirty = true
        end
    end

    -- ── Mouse look ─────────────────────────────────────
    if useMouse then
        -- Pitch (X axis) – vertical mouse movement, clamp to ±80°
        if mouseY ~= 0.0 then
            local newPitch = math.max(-80.0, math.min(80.0,
                camRot.x - (mouseY * CameraOptions.lookSpeedX * dt)
            ))
            camRot = vector3(newPitch, camRot.y, camRot.z)
            flyCamRotationDirty = true
        end

        -- Yaw (Z axis) – horizontal mouse movement
        if mouseX ~= 0.0 then
            local newHeading = camRot.z - (mouseX * CameraOptions.lookSpeedY * dt)
            camRot = vector3(camRot.x, camRot.y, newHeading)
            flyCamRotationDirty = true
        end
    end

    -- Apply position update
    if flyCamPositionDirty then
        SetCamCoord(camHandle, camPos)
    end

    -- Apply rotation update
    if flyCamRotationDirty then
        SetCamRot(camHandle, camRot, 2)
    end

    -- Enforce boundary sphere
    if boundPos and boundDist then
        local dist = #(camPos - boundPos)
        if dist > boundDist then
            local clamped = boundPos + norm(camPos - boundPos) * boundDist
            camPos = clamped
            SetCamCoord(camHandle, camPos)
        end
    end

    -- Optionally sync player ped position to the camera
    if opts.updatePlayerCoords then
        SetEntityCoords(cache.ped, camPos.x, camPos.y, camPos.z, false, false, false, false)
        SetEntityHeading(cache.ped, camRot.z)
    end

    return camPos, camRot
end

-- ──────────────────────────────────────────────────────────
-- Utils.DestroyFlyCam(camHandle, transitionTime)
--   Deactivates and destroys a scripted camera, returning
--   control to the gameplay camera.
-- ──────────────────────────────────────────────────────────
function Utils.DestroyFlyCam(camHandle, transitionTime)
    if not transitionTime then transitionTime = 0 end

    SetCamActive(camHandle, false)
    RenderScriptCams(false, true, transitionTime, true, true)
    DestroyCam(camHandle, false)
    SetFocusEntity(cache.ped)
end

-- ──────────────────────────────────────────────────────────
-- Utils.ScreenToWorld()
--   Fires a ray from the gameplay camera through the mouse
--   cursor into the game world.
--   Returns (hit, hitCoords, hitEntity).
-- ──────────────────────────────────────────────────────────
function Utils.ScreenToWorld()
    local camRot    = GetGameplayCamRot(0)
    local camPos    = GetGameplayCamCoord()
    local mouseX    = GetControlNormal(0, 239)
    local mouseY    = GetControlNormal(0, 240)
    local mouseVec  = vector2(mouseX, mouseY)

    local worldPos, worldDir = Utils.ScreenRelToWorld(camPos, camRot, mouseVec)

    local farPoint = camPos + worldDir * 50.0

    local rayHandle = StartShapeTestRay(
        worldPos.x, worldPos.y, worldPos.z,
        farPoint.x, farPoint.y, farPoint.z,
        -1, 0, 4
    )

    local _, hit, hitCoords, _, hitEntity = GetShapeTestResult(rayHandle)

    return hit, hitCoords, hitEntity
end

-- ──────────────────────────────────────────────────────────
-- Utils.ScreenRelToWorld(camPos, camRot, screenPos)
--   Converts a normalised 2-D screen position to a 3-D
--   world coordinate using the camera's orientation.
--   Returns (worldPos, worldDir).
-- ──────────────────────────────────────────────────────────
function Utils.ScreenRelToWorld(camPos, camRot, screenPos)
    local camDir = Utils.RotationToDirection(camRot)

    local rotUp    = vector3(camRot.x + 1.0, camRot.y, camRot.z)
    local rotDown  = vector3(camRot.x - 1.0, camRot.y, camRot.z)
    local rotLeft  = vector3(camRot.x, camRot.y, camRot.z - 1.0)
    local rotRight = vector3(camRot.x, camRot.y, camRot.z + 1.0)

    -- World-space right and up vectors derived from rotation delta
    local worldRight = Utils.RotationToDirection(rotRight) - Utils.RotationToDirection(rotLeft)
    local worldUp    = Utils.RotationToDirection(rotUp)    - Utils.RotationToDirection(rotDown)

    local camYRad = -(camRot.y * math.pi / 180.0)
    local cosY    = math.cos(camYRad)
    local sinY    = math.sin(camYRad)

    -- Apply Y-axis rotation to right/up
    local rotatedRight = worldRight * cosY - worldUp * sinY
    local rotatedUp    = worldRight * sinY + worldUp * cosY

    -- Reference point directly in front of cam
    local forwardPoint = camPos + camDir * 1.0
    local target       = forwardPoint + rotatedRight + rotatedUp

    -- Project reference and target points to screen space
    local targetScreen = Utils.World3DToScreen2D(target)
    local refScreen    = Utils.World3DToScreen2D(forwardPoint)

    -- Map screen-space offset to 3-D world-space offset
    local scaleX = (screenPos.x - refScreen.x) / (targetScreen.x - refScreen.x)
    local scaleY = (screenPos.y - refScreen.y) / (targetScreen.y - refScreen.y)

    local worldPos = forwardPoint + rotatedRight * scaleX + rotatedUp * scaleY
    local worldDir = camDir + rotatedRight * scaleX + rotatedUp * scaleY

    return worldPos, worldDir
end

-- ──────────────────────────────────────────────────────────
-- Utils.RotationToDirection(rotation)
--   Converts a rotation vector (degrees) to a unit direction
--   vector3.  Identical to GetForwardVector but used in
--   camera math contexts.
-- ──────────────────────────────────────────────────────────
function Utils.RotationToDirection(rotation)
    local pitchRad = rotation.x * math.pi / 180.0
    local yawRad   = rotation.z * math.pi / 180.0
    local cosX     = math.abs(math.cos(pitchRad))

    return vector3(
        -math.sin(yawRad) * cosX,
         math.cos(yawRad) * cosX,
         math.sin(pitchRad)
    )
end

-- ──────────────────────────────────────────────────────────
-- Utils.World3DToScreen2D(worldPos)
--   Projects a world vector3 to normalised screen space.
--   Returns a vector2 (0-1 range).
-- ──────────────────────────────────────────────────────────
function Utils.World3DToScreen2D(worldPos)
    local _, screenX, screenY = GetScreenCoordFromWorldCoord(worldPos.x, worldPos.y, worldPos.z)
    return vector2(screenX, screenY)
end

-- ──────────────────────────────────────────────────────────
-- Utils.CreateObject(modelHash, spawnCoords)
--   Spawns a static prop object.
-- ──────────────────────────────────────────────────────────
function Utils.CreateObject(modelHash, spawnCoords)
    if "string" == type(modelHash) then
        modelHash = joaat(modelHash) or modelHash
    end

    lib.requestModel(modelHash, Config.DefaultRequestModelTimeout)
    RequestModel(modelHash)

    while not HasModelLoaded(modelHash) do
        Wait(0)
    end

    local obj = CreateObject(modelHash, spawnCoords.x, spawnCoords.y, spawnCoords.z, false, false, false)
    SetModelAsNoLongerNeeded(modelHash)

    return obj
end

-- ──────────────────────────────────────────────────────────
-- Utils.GetAllPeds / GetAllObjects / GetAllVehicles
--   Helper that iterates a Find-style entity enumeration.
-- ──────────────────────────────────────────────────────────

-- Internal generic entity iterator
local function getAllEntitiesOfType(findFirst, findNext, endFind)
    local entities = {}
    local handle, entity = findFirst()

    while entity do
        entities[#entities + 1] = entity
        entity = findNext(handle)
    end

    endFind(handle)
    return entities
end

function Utils.GetAllPeds()
    return getAllEntitiesOfType(FindFirstPed, FindNextPed, EndFindPed)
end

function Utils.GetAllObjects()
    return getAllEntitiesOfType(FindFirstObject, FindNextObject, EndFindObject)
end

function Utils.GetAllVehicles()
    return getAllEntitiesOfType(FindFirstVehicle, FindNextVehicle, EndFindVehicle)
end

-- ──────────────────────────────────────────────────────────
-- Utils.FindNthInString(str, pattern, n)
--   Returns the start and end position of the n-th occurrence
--   of `pattern` inside `str`.
-- ──────────────────────────────────────────────────────────
function Utils.FindNthInString(str, pattern, n)
    local function strFind(s, p, startPos)
        return string.find(s, p, startPos)
    end
    find = strFind   -- module-level alias used below

    local foundStart = nil
    local foundEnd   = nil

    for _ = 1, n, 1 do
        local searchFrom = foundEnd and (foundEnd + 1) or 0
        foundStart, foundEnd = find(str, pattern, searchFrom)
    end

    return foundStart, foundEnd
end

-- ──────────────────────────────────────────────────────────
-- RotationToDirection  (global alias, used by older code)
-- ──────────────────────────────────────────────────────────
function RotationToDirection(rotation)
    local yawRad   = math.rad(rotation.z)
    local pitchRad = math.rad(rotation.x)
    local cosX     = math.abs(math.cos(pitchRad))

    return vector3(
        -math.sin(yawRad) * cosX,
         math.cos(yawRad) * cosX,
         math.sin(pitchRad)
    )
end

-- ──────────────────────────────────────────────────────────
-- Utils.GetCamera()
--   Returns the current rendered camera's coords and rotation.
-- ──────────────────────────────────────────────────────────
function Utils.GetCamera()
    return {
        coords   = GetFinalRenderedCamCoord(),
        rotation = GetFinalRenderedCamRot(2),
    }
end

-- ──────────────────────────────────────────────────────────
-- ScreenRelToWorld  (global alias used by legacy callers)
-- ──────────────────────────────────────────────────────────
function ScreenRelToWorld(worldOrigin, camRot, screenPos)
    local dist = 1000.0
    local camDir = RotationToDirection(camRot)

    -- Cardinal rotation offsets
    local rotPlusZ  = camRot + vector3(0,  0,  dist)
    local rotMinusZ = camRot + vector3(0,  0, -dist)
    local rotMinusX = camRot + vector3(0,  0, -dist)   -- Note: matches original
    local rotPlusX  = camRot + vector3(0,  0,  dist)

    -- World-space axis deltas
    local worldRight = RotationToDirection(rotPlusZ)  - RotationToDirection(rotMinusZ)
    local worldUp    = RotationToDirection(rotPlusX)  - RotationToDirection(rotMinusX)

    local camYRad = -math.rad(camRot.y)
    local cosY    = math.cos(camYRad)
    local sinY    = math.sin(camYRad)

    local rotatedRight = worldRight * cosY - worldUp * sinY
    local rotatedUp    = worldRight * sinY + worldUp * cosY

    local forwardPoint  = worldOrigin + camDir * dist
    local target        = forwardPoint + rotatedRight + rotatedUp

    local targetScreen  = { X = nil, Y = nil }
    local _, tX, tY = GetScreenCoordFromWorldCoord(target.x, target.y, target.z)
    targetScreen.X = tX ; targetScreen.Y = tY

    if not (targetScreen and tX) or not tY then
        return worldOrigin + camDir * dist
    end

    local refScreen = { X = nil, Y = nil }
    local _, rX, rY = GetScreenCoordFromWorldCoord(forwardPoint.x, forwardPoint.y, forwardPoint.z)
    refScreen.X = rX ; refScreen.Y = rY

    if not (refScreen and rX) or not rY then
        return worldOrigin + camDir * dist
    end

    -- Guard against degenerate projection
    local eps = 1.0e-5
    if math.abs(targetScreen.X - refScreen.X) < eps
    or math.abs(targetScreen.Y - refScreen.Y) < eps then
        return worldOrigin + camDir * dist
    end

    local scaleX = (screenPos.x - refScreen.X) / (targetScreen.X - refScreen.X)
    local scaleY = (screenPos.y - refScreen.Y) / (targetScreen.Y - refScreen.Y)

    return forwardPoint + rotatedRight * scaleX + rotatedUp * scaleY
end

-- ──────────────────────────────────────────────────────────
-- LocationInWorld(worldPos, camHandle, flags)
--   Fires a shape-test ray from the camera through `worldPos`.
--   Returns (hit, hitCoords, hitEntity).
-- ──────────────────────────────────────────────────────────
function LocationInWorld(worldPos, camHandle, flags)
    local camPos   = GetCamCoord(camHandle)
    local playerPed = cache.ped

    local rayHandle = StartShapeTestRay(
        camPos.x,   camPos.y,   camPos.z,
        worldPos.x, worldPos.y, worldPos.z,
        flags,
        playerPed,
        0
    )

    local _, hit, hitCoords, _, hitEntity = GetShapeTestResult(rayHandle)
    currentCoords = hitCoords

    return hit, hitCoords, hitEntity
end

-- ──────────────────────────────────────────────────────────
-- Utils.getCursorHitCoords(ignoreEntity)
--   Shoots a swept-sphere ray from the screen cursor into
--   the world and returns (hitCoords, hitEntity).
--   Returns nil, nil if nothing was hit.
-- ──────────────────────────────────────────────────────────
function Utils.getCursorHitCoords(ignoreEntity)
    local mouseX = GetDisabledControlNormal(0, 239)
    local mouseY = GetDisabledControlNormal(0, 240)

    local rayOrigin, rayDir = GetWorldCoordFromScreenCoord(mouseX, mouseY)

    local farPoint = rayOrigin + rayDir * 120
    local excludeEntity = ignoreEntity or cache.ped

    local rayHandle = StartShapeTestSweptSphere(
        rayOrigin.x, rayOrigin.y, rayOrigin.z,
        farPoint.x,  farPoint.y,  farPoint.z,
        0.01,
        17,
        excludeEntity,
        4
    )

    local status, _, hitCoords, _, hitEntity = GetShapeTestResult(rayHandle)

    if not status then
        return nil, nil
    end

    return hitCoords, hitEntity
end

-- ──────────────────────────────────────────────────────────
-- string.includes(str, valueOrTable)
--   Extension: returns true if `str` equals `valueOrTable`
--   (string) or is contained in `valueOrTable` (table).
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
-- Keys  —  keyboard control-action ID lookup table
-- ──────────────────────────────────────────────────────────
Keys = {
    ESC        = 322,
    F1         = 288, F2 = 289, F3 = 170,
    F5         = 166, F6 = 167, F7 = 168, F8 = 169,
    F9         = 56,  F10 = 57,
    ["~"]      = 243,
    ["1"]      = 157, ["2"] = 158, ["3"] = 160,
    ["4"]      = 164, ["5"] = 165, ["6"] = 159,
    ["7"]      = 161, ["8"] = 162, ["9"] = 163,
    ["-"]      = 84,  ["="] = 83,
    BACKSPACE  = 177,
    TAB        = 37,
    Q = 44, W = 32, E = 38, R = 45,  T = 245,
    Y = 246, U = 303, P = 199,
    ["["]      = 39, ["]"] = 40,
    ENTER      = 18,
    CAPS       = 137,
    A = 34, S = 8,  D = 9,  F = 23, G = 47,
    H = 74, K = 311, L = 182,
    LEFTSHIFT  = 21,
    Z = 20, X = 73, C = 26, V = 0, B = 29,
    N = 249, M = 244,
    [","]      = 82, ["."] = 81,
    LEFTCTRL   = 36,
    LEFTALT    = 19,
    SPACE      = 22,
    RIGHTCTRL  = 70,
    HOME       = 213,
    PAGEUP     = 10, PAGEDOWN = 11,
    DELETE     = 178,
    LEFT       = 174, RIGHT = 175, TOP = 27, DOWN = 173,
    NENTER     = 201,
    N4 = 108, N5 = 60,  N6 = 107,
    ["N+"]     = 96, ["N-"] = 97,
    N7 = 117, N8 = 61,  N9 = 118,
}

-- ──────────────────────────────────────────────────────────
-- Instructional-button overlay helpers
-- ──────────────────────────────────────────────────────────
DrawingInstructional = false

-- Utils.DrawInstructional(controlKeys)
--   Starts a background thread that continuously draws the
--   instructional button strip until RemoveInstructional().
function Utils.DrawInstructional(controlKeys)
    if DrawingInstructional then
        Debug("Instructional", "Instructional already being drawn, updating keys.")
        return
    end

    CreateThread(function()
        DrawingInstructional = true

        while true do
            if not DrawingInstructional then break end

            Wait(0)

            local controls  = Utils.GetControls(controlKeys)
            local scaleform = Utils.CreateInstructional(controls)
            Utils.DrawScaleform(scaleform)
        end
    end)
end

-- Utils.RemoveInstructional()
--   Stops the DrawInstructional loop.
function Utils.RemoveInstructional()
    DrawingInstructional = false
end

-- ──────────────────────────────────────────────────────────
-- Utils.SelectPlayer()
--   Shows nearby players (within 20 m) with a marker and
--   an instructional overlay, letting the local player cycle
--   through them and pick one.
--   Returns the network ID of the selected player, or nil.
-- ──────────────────────────────────────────────────────────
function Utils.SelectPlayer()
    local myPos = GetEntityCoords(cache.ped)

    -- Collect nearby player peds
    local nearbyPeds = {}
    for _, playerId in ipairs(GetActivePlayers()) do
        local playerPed = GetPlayerPed(playerId)
        if playerPed > 0 and DoesEntityExist(playerPed) then
            if #(GetEntityCoords(playerPed) - myPos) <= 20.0 then
                table.insert(nearbyPeds, playerPed)
            end
        end
    end

    local controls  = Utils.GetControls("select_player", "change_player", "cancel")
    local scaleform = Utils.CreateInstructional(controls)

    local selectedIdx = 1

    while true do
        -- Cancel
        if IsControlJustPressed(0, ActionControls.cancel.codes[1]) then
            return
        end

        -- Confirm selection → return network owner of chosen ped
        if IsControlJustPressed(0, ActionControls.select_player.codes[1]) then
            return NetworkGetEntityOwner(nearbyPeds[selectedIdx])
        end

        -- Cycle forward
        if IsControlJustPressed(0, ActionControls.change_player.codes[1]) then
            selectedIdx = selectedIdx + 1
            if selectedIdx > #nearbyPeds then
                selectedIdx = 1
            end
        elseif IsControlJustPressed(0, ActionControls.change_player.codes[2]) then
            -- Cycle backward
            selectedIdx = selectedIdx - 1
            if selectedIdx < 1 then
                selectedIdx = #nearbyPeds
            end
        end

        -- Draw selection marker above chosen ped
        Utils.DrawMarker({
            type     = 0,
            scale    = vector3(0.2, 0.2, 0.2),
            location = GetEntityCoords(nearbyPeds[selectedIdx]) + vector3(0.0, 0.0, 1.0),
        })

        Utils.DrawScaleform(scaleform)
        Wait(0)
    end
end

-- ──────────────────────────────────────────────────────────
-- Utils.teleportToCoords(coords)
--   Teleports the local player ped to coords (vector2/3)
--   using the collision-search approach.
--   Fades screen out/in around the teleport.
--   Returns true on success, false if ground was not found.
-- ──────────────────────────────────────────────────────────
function Utils.teleportToCoords(coords)
    DoScreenFadeOut(650)
    repeat
        Wait(0)
    until IsScreenFadedOut()

    local targetX    = coords.x
    local targetY    = coords.y
    local maxZ       = 850.0
    local searchStep = 950.0
    local groundFound = false

    local playerPed  = cache.ped
    local originalPos = GetEntityCoords(playerPed)
    local groundZ    = maxZ

    -- Sweep downward through multiple Z heights to find ground
    for zCheck = searchStep, 0, -25.0 do
        -- Alternate Z heights to avoid interior-cell issues
        local testZ = zCheck
        if zCheck % 2 ~= 0 then
            testZ = searchStep - zCheck
        end

        NewLoadSceneStart(
            targetX, targetY, testZ,
            targetX, targetY, testZ,
            50.0, 0
        )

        local startTime = GetGameTimer()
        while true do
            if not IsNetworkLoadingScene()                      then break end
            if GetGameTimer() - startTime > 1000               then break end
            Wait(0)
        end

        NewLoadSceneStop()
        SetPedCoordsKeepVehicle(playerPed, targetX, targetY, testZ)

        -- Wait for collision to load
        startTime = GetGameTimer()
        while true do
            if HasCollisionLoadedAroundEntity(playerPed)        then break end
            RequestCollisionAtCoord(targetX, targetY, testZ)
            if GetGameTimer() - startTime > 1000               then break end
            Wait(0)
        end

        -- Try to get a valid ground Z
        local ok, foundZ = GetGroundZFor_3dCoord(targetX, targetY, testZ, false)
        groundZ       = foundZ
        groundFound   = ok

        if groundFound then
            Wait(0)
            SetPedCoordsKeepVehicle(playerPed, targetX, targetY, groundZ)
            break
        end

        Wait(0)
    end

    DoScreenFadeIn(650)

    if not groundFound then
        -- Restore original position if ground was never found
        SetPedCoordsKeepVehicle(playerPed, originalPos.x, originalPos.y, originalPos.z)
        return false
    end

    return true
end
