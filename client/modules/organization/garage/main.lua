-- ============================================================
-- client/modules/organization/garage/main.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Organization garage system.  Handles opening/closing the
-- garage NUI, proximity-based store/retrieve interactions, and
-- spawning vehicles with full property restoration.
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- Garage class (ox_lib based)
-- ──────────────────────────────────────────────────────────
Garage = lib.class("Garage")
CurrentGarage = nil   -- The currently open Garage instance (or nil)

-- ──────────────────────────────────────────────────────────
-- Garage constructor
--   self.organization – the parent organization object
--   self.vehicles     – cached vehicle list
--   self.isOpen       – UI open flag
-- ──────────────────────────────────────────────────────────
function Garage:constructor(organization)
    self.organization = organization
    self.vehicles     = {}
    self.isOpen       = false
end

-- ──────────────────────────────────────────────────────────
-- Garage:open()
--   Fetches the vehicle list from the server and opens the
--   garage NUI panel.
-- ──────────────────────────────────────────────────────────
function Garage:open()
    if self.isOpen then return end

    -- The organization must have garage coords configured
    if not self.organization.garage_coords then
        Notification(i18n.t("garage_not_found"), "error")
        return
    end

    CurrentGarage  = self
    self.isOpen    = true

    -- Fetch the vehicle list
    local vehicles = lib.callback.await(
        "crime:getOrganizationVehicles", false, self.organization.id
    ) or {}

    self.vehicles = vehicles

    -- Send vehicles to the React UI
    SendReactMessage("organization_garage:open", {
        organizationId = self.organization.id,
        vehicles       = vehicles,
    })

    SetNuiFocus(true, true)
end

-- ──────────────────────────────────────────────────────────
-- Garage:close()
--   Closes the garage NUI panel and resets state.
-- ──────────────────────────────────────────────────────────
function Garage:close()
    if not self.isOpen then return end

    self.isOpen   = false
    self.vehicles = {}
    CurrentGarage = nil

    SendReactMessage("organization_garage:close")
    SetNuiFocus(false, false)
end

-- ──────────────────────────────────────────────────────────
-- Garage interaction draw-text labels (cached)
-- ──────────────────────────────────────────────────────────
local storeVehicleText = i18n.t("drawtext.store_vehicle")
local openGarageText   = i18n.t("drawtext.open_garage")

-- ──────────────────────────────────────────────────────────
-- Garage:checkInteraction()
--   Called every frame when the organization is active.
--   Detects proximity to the garage coords and shows the
--   appropriate prompt:
--     - If in a vehicle → "Store Vehicle"
--     - If on foot       → "Open Garage"
-- ──────────────────────────────────────────────────────────
function Garage:checkInteraction()
    local garageCoords = self.organization.garage_coords
    if not garageCoords then return end

    local playerPos = GetEntityCoords(cache.ped)
    local dist      = #(playerPos - garageCoords.xyz)
    local interactDist = Config.OrganizationGarage.InteractionDistance

    if dist > interactDist then return end

    -- Player is inside interaction range
    self.organization.sleep = 0

    local currentVehicle = GetVehiclePedIsIn(cache.ped, false)

    if currentVehicle ~= 0 then
        -- Player is in a vehicle → offer to store it
        DrawText3D(
            garageCoords.x, garageCoords.y, garageCoords.z,
            storeVehicleText,
            "store_vehicle_" .. self.organization.id,
            "E"
        )

        if IsControlJustPressed(0, Keys.E) then
            -- Get the vehicle's plate (trimmed of whitespace)
            local plate = string.gsub(
                GetVehicleNumberPlateText(currentVehicle),
                "^%s*(.-)%s*$", "%1"
            )

            -- Verify this plate belongs to the organization
            local vehicleRecord = lib.callback.await(
                "crime:getOrganizationVehicleByPlate", false,
                self.organization.id, plate
            )

            if not vehicleRecord then
                Notification(i18n.t("vehicle_not_belongs_to_organization"), "error")
                return
            end

            -- Check permission
            if not self.organization:hasPermission("canAccessGarage") then
                Notification(i18n.t("not_have_permission"), "error")
                return
            end

            -- Store the vehicle
            local stored = lib.callback.await(
                "crime:storeOrganizationVehicle", false,
                self.organization.id, plate
            )

            if stored then
                SetEntityAsMissionEntity(currentVehicle, true, true)
                DeleteEntity(currentVehicle)
                Notification(i18n.t("vehicle_stored"), "success")
            else
                Notification(i18n.t("vehicle_storage_failed"), "error")
            end
        end
    else
        -- Player is on foot → offer to open the garage UI
        if self.organization:hasPermission("canAccessGarage") then
            DrawText3D(
                garageCoords.x, garageCoords.y, garageCoords.z,
                openGarageText,
                "open_garage_" .. self.organization.id,
                "E"
            )

            if IsControlJustPressed(0, Keys.E) then
                self:open()
            end
        end
    end
end

-- ──────────────────────────────────────────────────────────
-- Garage:spawnVehicle(vehicleId, vehicleData)
--   Spawns a vehicle at the garage spawn coords and applies
--   all stored vehicle properties (plate, paint, mods, etc).
-- ──────────────────────────────────────────────────────────
function Garage:spawnVehicle(vehicleId, vehicleData)
    Debug("spawnVehicle", vehicleId, vehicleData)

    if not (vehicleData and vehicleData.vehicle_model) then return end

    local garageCoords = self.organization.garage_coords
    if not garageCoords then
        Notification(i18n.t("garage_not_found"), "error")
        return
    end

    -- Request the model hash
    local modelHash = joaat(vehicleData.vehicle_model)
    lib.requestModel(modelHash)

    -- Spawn the vehicle at the garage spawn point
    local vehicle = CreateVehicle(
        modelHash,
        garageCoords.x, garageCoords.y, garageCoords.z,
        garageCoords.w or 0.0,
        true, false
    )

    if not vehicle or vehicle == 0 then
        Notification(i18n.t("vehicle_spawn_failed"), "error")
        return
    end

    -- Build the property table to apply
    local props = lib.getVehicleProperties(vehicle) or {}

    if vehicleData.vehicle_props then
        local savedProps = vehicleData.vehicle_props

        -- Merge saved properties (only keys that already exist in the props table,
        -- plus always-allowed keys: plate, model)
        for key, value in pairs(savedProps) do
            if props[key] ~= nil or key == "plate" or key == "model" then
                props[key] = value
            end
        end

        -- Apply plate (prefer vehicle_props.plate, then vehicleData.plate)
        if savedProps.plate then
            props.plate = savedProps.plate
        elseif vehicleData.plate then
            props.plate = vehicleData.plate
        end

        -- Apply model (convert string to hash if necessary)
        if savedProps.model then
            if type(savedProps.model) == "string" then
                props.model = joaat(savedProps.model)
            end
        else
            props.model = modelHash
        end

        -- Apply health values individually so they survive lib.setVehicleProperties
        if savedProps.fuel ~= nil then
            SetVehicleFuelLevel(vehicle, tonumber(savedProps.fuel) or 100.0)
        end
        if savedProps.engine ~= nil then
            SetVehicleEngineHealth(vehicle, tonumber(savedProps.engine) or 1000.0)
        end
        if savedProps.body ~= nil then
            SetVehicleBodyHealth(vehicle, tonumber(savedProps.body) or 1000.0)
        end
    else
        -- No saved props — at minimum set the plate and model
        if vehicleData.plate then
            props.plate = vehicleData.plate
        end
        props.model = modelHash
    end

    -- Apply properties via ox_lib
    if props then
        lib.setVehicleProperties(vehicle, props)
    end

    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleOnGroundProperly(vehicle)
    SetModelAsNoLongerNeeded(modelHash)

    -- Warp player into the driver seat
    TaskWarpPedIntoVehicle(cache.ped, vehicle, -1)

    Notification(i18n.t("garage.vehicle_spawned"), "success")
end

-- ──────────────────────────────────────────────────────────
-- Net event: "crime:spawnOrganizationVehicle"
--   Server triggers this on the owning client after the
--   vehicle spawn request is validated.
-- ──────────────────────────────────────────────────────────
RegisterNetEvent("crime:spawnOrganizationVehicle", function(orgId, vehicleId, vehicleData)
    local org = OrganizationManager:get(orgId)
    if not (org and org.garage) then return end

    org.garage:spawnVehicle(vehicleId, vehicleData)
end)

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:getVehicleProps"
--   Returns the full property table for the vehicle whose
--   plate matches `plate`.  Searches the current vehicle
--   first; if the player is on foot, scans all nearby
--   vehicles.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:getVehicleProps", function(plate)
    -- Try the player's current vehicle first
    local vehicle = GetVehiclePedIsIn(cache.ped, false)

    if vehicle == 0 then
        -- Scan all vehicles in the world for a matching plate
        for _, v in ipairs(GetAllVehicles()) do
            local vPlate = string.gsub(
                GetVehicleNumberPlateText(v),
                "^%s*(.-)%s*$", "%1"
            )
            if vPlate == plate then
                vehicle = v
                break
            end
        end
    end

    if vehicle == 0 then return {} end

    local props = lib.getVehicleProperties(vehicle) or {}

    -- Fill health values if lib.getVehicleProperties didn't include them
    if props.fuel   == nil then props.fuel   = GetVehicleFuelLevel(vehicle) end
    if props.engine == nil then props.engine = GetVehicleEngineHealth(vehicle) end
    if props.body   == nil then props.body   = GetVehicleBodyHealth(vehicle) end

    return props
end)
