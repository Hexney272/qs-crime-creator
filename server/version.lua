-- ============================================================
-- server/version.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Checks the resource version against the GitHub release feed
-- and prints an update notice to the server console.
-- ============================================================

local currentVersion = GetResourceMetadata(GetCurrentResourceName(), "version", 0)
local resourceName   = GetCurrentResourceName()

-- ──────────────────────────────────────────────────────────
-- Local: versionToInt(versionStr)
--   Strips dots from a version string (e.g. "1.2.3" → 123)
--   so two versions can be compared as plain integers.
-- ──────────────────────────────────────────────────────────
local function versionToInt(versionStr)
    local parts = versionStr:split(".")
    local combined = ""
    for i = 1, #parts, 1 do
        combined = combined .. parts[i]
    end
    return tonumber(combined)
end

-- ──────────────────────────────────────────────────────────
-- Local: compareVersions(remoteVersion, descriptions)
--   Returns (diff, descriptions) where:
--     diff > 0  → remote is newer (update available)
--     diff == 0 → versions match (up to date)
--     diff < 0  → local is newer (dev/pre-release)
-- ──────────────────────────────────────────────────────────
local function compareVersions(remoteVersion, descriptions)
    local local_int  = versionToInt(currentVersion)
    local remote_int = versionToInt(remoteVersion)
    return remote_int - local_int, descriptions
end

-- ──────────────────────────────────────────────────────────
-- Version check — only runs if a version string was found
-- ──────────────────────────────────────────────────────────
if currentVersion then
    local versionUrl = "https://raw.githubusercontent.com/quasar-scripts/version/main/"
                    .. resourceName .. ".json"

    PerformHttpRequest(versionUrl, function(statusCode, body)
        if statusCode == 404 then
            print("^1API is not available. Unable to check the version.^0")
            return
        end

        if statusCode == 200 then
            local data           = json.decode(body)
            local remoteVersion  = data.version
            local descriptions   = data.descriptions

            local diff, changelogs = compareVersions(remoteVersion, descriptions)

            if diff == 0 then
                print("^2You are using the latest version of " .. resourceName .. "!^0")

            elseif diff > 0 then
                print("^3New version available for " .. resourceName .. "!^0")

                for _, changeNote in pairs(changelogs) do
                    print("^3- " .. changeNote .. "^0")
                end

                print("^3You have version " .. currentVersion
                    .. ", upgrade to version " .. remoteVersion .. "!^0")

            else
                -- Local is newer than GitHub (dev / pre-release build)
                print("^1You are using a newer version of " .. resourceName
                    .. " than the one available on GitHub.^0")
            end
        end
    end, "GET", "", {}, {})

else
    print("Unable to obtain the version of " .. resourceName
        .. ". Make sure it is defined in your fxmanifest.lua.")
end
