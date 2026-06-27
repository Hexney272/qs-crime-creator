-- ============================================================
-- client/modules/creator/nui.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- NUI callbacks for the admin creator tool.
-- Bridges the creator React UI to Lua raycasting helpers,
-- record CRUD, and server callbacks.
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- Category → payload-field map (used by create/update)
-- ──────────────────────────────────────────────────────────
local CATEGORY_FIELD = {
    organizations = "organization_data",
    territories   = "territory_data",
    taxing        = "taxing_data",
    vehicle_store = "vehicle_store_data",
    season_pass   = "season_pass_data",
    pvp           = "pvp_data",
}

-- ──────────────────────────────────────────────────────────
-- Select rectangular zone points (draws overlay, returns pts)
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("creator_select_points", function(_, cb)
    local result = creator:raycastRectangle()
    creator:open()

    if not result then return cb(nil) end

    -- Serialise vec3 → plain table for NUI
    result.points = table.map(result.points, function(p)
        return { x = p.x, y = p.y, z = p.z }
    end)
    cb(result)
end)

-- ──────────────────────────────────────────────────────────
-- select_organization  — update raycast zone from NUI data
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("select_organization", function(data, cb)
    if data and data.zone and data.zone.points then
        creator.raycast.points = table.map(data.zone.points, function(p)
            return vec3(p.x, p.y, p.z)
        end)
        creator.raycast.height = data.zone.thickness
    else
        creator.raycast.points = {}
    end
    cb(true)
end)

-- ──────────────────────────────────────────────────────────
-- select_point  — lets the player pick N world coords
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("select_point", function(data, cb)
    -- Validate model if provided
    if data and data.options and data.options.model then
        if not IsModelInCdimage(data.options.model) then
            Notification(i18n.t("creator.raycast.model_is_not_valid",
                { model = data.options.model }), "error")
            return cb(nil)
        end
    end

    local pointType = (data and data.pointType) or "empty"
    local count     = (data and data.count)     or 1
    local options   = (data and data.options) or {}

    -- Allow selecting entry/garage/exit coords anywhere in the world,
    -- not just inside a pre-drawn zone. Without this flag, creator:selectPoint
    -- returns nil when no zone points have been drawn, leaving the coord
    -- field stuck at 0,0,0,0.
    if options.externalUsage == nil then
        options.externalUsage = true
    end

    local result = creator:selectPoint(pointType, count, options)
    creator:open()

    if not result then return cb(nil) end

    -- Serialise vec4/vec3 → plain tables for NUI
    local serialised = table.map(result, function(p)
        local t = { x = p.x, y = p.y, z = p.z }
        if p.w then t.w = p.w end
        return t
    end)

    if count == 1 then
        cb(serialised[1])
    else
        cb(serialised)
    end
end)

-- ──────────────────────────────────────────────────────────
-- select_entity  — lets the player click on world entities
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("select_entity", function(data, cb)
    local entityType = (data and data.entityType) or "object"
    local count      = (data and data.count)      or 1
    local options    = (data and data.options)

    Debug("select_entity", data)

    local result = creator:selectEntity(entityType, count, options)
    creator:open()

    if not result then return cb(nil) end

    local serialised = table.map(result, function(e)
        return {
            entity = e.entity,
            coords = {
                x = e.coords.x, y = e.coords.y, z = e.coords.z, w = e.coords.w,
            },
        }
    end)

    if count == 1 then
        cb(serialised[1])
    else
        cb(serialised)
    end
end)

-- ──────────────────────────────────────────────────────────
-- teleport_to_coords
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("teleport_to_coords", function(data, cb)
    if not (data and data.coords and data.zone) then
        Notification(i18n.t("creator.invalid_data"), "error")
        return cb(false)
    end

    local coords = data.coords
    if coords.z then
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        SetEntityCoords(cache.ped, coords.x, coords.y, coords.z,
            false, false, false, false)
    else
        Utils.teleportToCoords(coords)
    end

    Notification(i18n.t("creator.teleported", { zone = data.zone }), "success")
    cb(true)
end)

-- ──────────────────────────────────────────────────────────
-- creator_select_shell  — raycast to find a shell interior
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("creator_select_shell", function(_, cb)
    local tier, coords = RayCastSelector("shell")
    creator:open()

    if not tier or not coords then return cb(nil) end

    cb({
        tier   = tier,
        coords = { x = coords.x, y = coords.y, z = coords.z, w = coords.w },
    })
end)

-- ──────────────────────────────────────────────────────────
-- creator_select_mlo_doors  — get MLO door coords
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("creator_select_mlo_doors", function(_, cb)
    local doors = RayCastGetMLO()
    creator:open()

    if not doors then return cb(nil) end

    -- Serialise coords
    doors = table.map(doors, function(d)
        d.coords = { x = d.coords.x, y = d.coords.y, z = d.coords.z, w = d.coords.w }
        return d
    end)

    cb(doors)
end)

-- ──────────────────────────────────────────────────────────
-- creator_select_ipl  — choose an IPL interior
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("creator_select_ipl", function(_, cb)
    -- Save player position so they can return after IPL preview
    CreatorStartedPosition = GetEntityCoords(cache.ped)

    local tier = ShowcaseOfIplHouse()
    creator:open()

    if not tier then return cb(nil) end

    local iplData = Config.IplData[tier]
    if not iplData then return cb(nil) end

    cb({
        tier    = tier,
        themeId = iplData.defaultTheme or "seductive",
        exit    = {
            x = iplData.exitCoords.x,
            y = iplData.exitCoords.y,
            z = iplData.exitCoords.z,
        },
    })
end)

-- ──────────────────────────────────────────────────────────
-- creator_select_exit_coords  — pick the exit point for an IPL
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("creator_select_exit_coords", function(data, cb)
    if not (data and data.tier and data.coords) then
        creator:open()
        return cb(nil)
    end

    local exitCoords = vec4(
        data.coords.x, data.coords.y, data.coords.z,
        data.coords.w or 0.0)

    local result = RayCastSelector("exit", { tier = data.tier, coords = exitCoords })
    creator:open()

    if not result then return cb(nil) end

    cb({ x = result.x, y = result.y, z = result.z, w = result.w })
end)

-- ──────────────────────────────────────────────────────────
-- creator_select_garage  — pick a vehicle spawn point
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("creator_select_garage", function(data, cb)
    -- Fall back to the player's current position when no garage coords have
    -- been saved yet (data.coords is nil or still 0,0,0). Without this the
    -- callback aborted immediately, leaving the garage marker invisible.
    local startCoords
    if data and data.coords and data.coords.x and data.coords.x ~= 0 then
        startCoords = vec4(
            data.coords.x, data.coords.y, data.coords.z,
            data.coords.w or 0.0)
    else
        local pc = GetEntityCoords(cache.ped)
        startCoords = vec4(pc.x, pc.y, pc.z, GetEntityHeading(cache.ped))
    end

    local result = creator:selectPoint("vehicle", 1, {
        points        = { { coords = startCoords } },
        externalUsage = true,   -- garage spawn can be placed outside the zone boundary
    })
    creator:open()

    if not result or #result == 0 then return cb(nil) end

    local p = result[1]
    cb({ coords = { x = p.x, y = p.y, z = p.z, w = p.w } })
end)

-- ──────────────────────────────────────────────────────────
-- search_players
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("search_players", function(data, cb)
    local ok, result = pcall(function()
        return lib.callback.await("crime:searchPlayers", false, data.query)
    end)
    if not ok then
        Error("search_players ::: callback error", result)
        return cb({})
    end
    cb(result or {})
end)

-- ──────────────────────────────────────────────────────────
-- crime_tablet:get_player_coords  (also registered here)
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("crime_tablet:get_player_coords", function(_, cb)
    local coords = GetEntityCoords(cache.ped)
    cb({ x = coords.x, y = coords.y, z = coords.z })
end)

-- ──────────────────────────────────────────────────────────
-- CRUD operations
-- ──────────────────────────────────────────────────────────

RegisterNUICallback("create_item", function(data, cb)
    Debug("create_item", data)
    local field = CATEGORY_FIELD[data.category]
    if not field then
        Error("create_item ::: unknown category", data.category)
        return cb(false)
    end
    local ok, result = pcall(function()
        return lib.callback.await("crime:createRecord", false, data.category, data[field])
    end)
    if not ok then
        Error("create_item ::: callback error", result)
        return cb(false)
    end
    cb(result)
end)

RegisterNUICallback("update_item", function(data, cb)
    Debug("update_item", data)
    local field = CATEGORY_FIELD[data.category]
    if not field then
        Error("update_item ::: unknown category", data.category)
        return cb(false)
    end

    local id = data.id
    -- season_pass uses a synthetic ID of 1
    if data.category == "season_pass" and (not id or id == "season_pass") then
        id = 1
    end

    local ok, result = pcall(function()
        return lib.callback.await("crime:updateRecord", false, data.category, id, data[field])
    end)
    if not ok then
        Error("update_item ::: callback error", result)
        return cb(false)
    end
    cb(result)
end)

RegisterNUICallback("remove_item", function(data, cb)
    Debug("remove_item", data)
    local ok, result = pcall(function()
        return lib.callback.await("crime:removeRecord", false, data.category, data.id)
    end)
    if not ok then
        Error("remove_item ::: callback error", result)
        return cb(false)
    end
    cb(result)
end)

-- ──────────────────────────────────────────────────────────
-- Data getters
-- ──────────────────────────────────────────────────────────

RegisterNUICallback("get_organizations", function(_, cb)
    cb(creator.organizations or {})
end)

RegisterNUICallback("get_territories", function(_, cb)
    local result = {}
    if creator.territories then
        for _, item in ipairs(creator.territories) do
            if item.territory_data then
                result[#result + 1] = {
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
    cb(result)
end)

RegisterNUICallback("check_location_in_territory", function(data, cb)
    if not (data and data.location and data.territory_id) then return cb(false) end

    if TerritoryManager then
        local territory = TerritoryManager:get(data.territory_id)
        if territory then
            local loc = vec3(
                data.location.x, data.location.y, data.location.z or 0)
            return cb(territory:isInside(loc))
        end
    end
    cb(false)
end)

-- ──────────────────────────────────────────────────────────
-- Admin utilities
-- ──────────────────────────────────────────────────────────

RegisterNUICallback("reset_season_pass", function(_, cb)
    local ok, result = pcall(function()
        return lib.callback.await("crime:resetSeasonPass", false)
    end)
    if not ok then
        Error("reset_season_pass ::: callback error", result)
        return cb(false)
    end
    cb(result)
end)

RegisterNUICallback("confirm_action", function(data, cb)
    if not (data and data.title and data.message) then return cb(false) end

    local result = lib.inputDialog(data.title, {
        {
            type        = "input",
            label       = data.message,
            description = 'Type "CONFIRM" to proceed',
            required    = true,
            default     = "",
        },
    })

    if result and result[1] and string.upper(result[1]) == "CONFIRM" then
        cb(true)
    else
        cb(false)
    end
end)
