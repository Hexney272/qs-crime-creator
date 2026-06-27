-- ============================================================
-- client/modules/taxing/main.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Client-side taxing system.  Polls configured taxing
-- collection points and allows the player to collect taxes
-- when standing close enough.
-- ============================================================

TaxingManager = {}

local taxCollectDrawText = i18n.t("drawtext.tax_collect")

-- ──────────────────────────────────────────────────────────
-- Main taxing proximity loop
--   Every 500 ms (reduced to 0 ms when near a point),
--   checks all active taxing locations and draws the
--   interaction hint.  Pressing E collects taxes.
-- ──────────────────────────────────────────────────────────
CreateThread(function()
    while true do
        local loopWait = 500   -- default tick interval

        local playerPos = GetEntityCoords(cache.ped)
        local currentOrgId = OrganizationManager:getCurrentOrganization()

        if not currentOrgId then
            -- Not in an org — sleep longer and try again
            Wait(1250)
        else
            -- Fetch all active taxing storage locations
            local taxingStorage = RecordHandler.configs.taxing.getStorage()
            if not taxingStorage then taxingStorage = {} end

            for _, taxEntry in ipairs(taxingStorage) do
                if taxEntry.taxing_data and taxEntry.taxing_data.location then
                    local loc = taxEntry.taxing_data.location
                    local locationPos = vec3(loc.x, loc.y, loc.z or 0)
                    local dist = #(playerPos - locationPos)

                    if dist <= 2.5 then
                        loopWait = 0   -- speed up loop when near

                        -- Draw interaction prompt
                        DrawText3D(
                            locationPos.x, locationPos.y, locationPos.z,
                            taxCollectDrawText,
                            "collect_taxing_" .. taxEntry.id,
                            "E"
                        )

                        -- Detect E key press
                        local pressedE = IsControlJustPressed(0, 38)
                                      or IsDisabledControlJustPressed(0, 38)

                        if pressedE then
                            local success, errorCode, amount =
                                lib.callback.await("crime:collectTaxing", false, taxEntry.id)

                            if success then
                                -- Successful collection
                                Notification(
                                    i18n.t("creator.taxing.collected",
                                        { amount = amount or 0 }),
                                    "success"
                                )

                            elseif errorCode == "cooldown_active" then
                                -- Still on cooldown — fetch the remaining time
                                local status = lib.callback.await(
                                    "crime:getTaxingCollectionStatus", false, taxEntry.id
                                )

                                if status and status.formatted_time then
                                    Notification(
                                        i18n.t("creator.taxing.already_collected",
                                            { time = status.formatted_time }),
                                        "error"
                                    )
                                else
                                    Notification(
                                        i18n.t("creator.taxing.already_collected",
                                            { time = "Unknown" }),
                                        "error"
                                    )
                                end

                            elseif errorCode == "not_authorized" then
                                Notification(i18n.t("creator.taxing.not_authorized"), "error")

                            elseif errorCode == "no_territory" then
                                Notification(i18n.t("creator.taxing.no_territory"), "error")

                            else
                                Notification(i18n.t("creator.taxing.collect_failed"), "error")
                            end

                            Wait(100)
                        end
                    end
                end
            end

            Wait(loopWait)
        end
    end
end)
