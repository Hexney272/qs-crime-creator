-- ============================================================
-- server/modules/version.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Dependency version-checking helper.  Exposes a `version`
-- global with utilities for comparing semver strings and
-- validating that required scripts meet minimum versions.
-- Also performs the self-update check against GitHub.
-- ============================================================

_G.version = {
    currentVersion = GetResourceMetadata(GetCurrentResourceName(), "version", 0),
    resourceName   = GetCurrentResourceName(),
}

-- ──────────────────────────────────────────────────────────
-- version.tonumberToVersion(self, versionStr)
--   Strips dots from a semver string and returns it as an
--   integer so two versions can be compared numerically.
--   e.g. "1.2.3" → 123
-- ──────────────────────────────────────────────────────────
function version.tonumberToVersion(self, versionStr)
    if not versionStr or type(versionStr) ~= "string" then return 0 end
    local combined = ""
    for part in versionStr:gmatch("[^%.]+") do
        combined = combined .. part
    end
    return tonumber(combined) or 0
end

-- ──────────────────────────────────────────────────────────
-- version.checkVersionDifference(self, remoteVersion, local?)
--   Returns (remoteInt - localInt).
--   > 0 means remote is newer, 0 means same, < 0 means local
--   is newer.  `localVersion` defaults to self.currentVersion.
-- ──────────────────────────────────────────────────────────
function version.checkVersionDifference(self, remoteVersion, localVersion)
    localVersion = localVersion or self.currentVersion
    if not remoteVersion then return 0 end
    local localInt  = self:tonumberToVersion(localVersion)
    local remoteInt = self:tonumberToVersion(remoteVersion)
    return remoteInt - localInt
end

-- ──────────────────────────────────────────────────────────
-- version.checkScriptVersion(self, scriptName, minVersion)
--   Verifies that `scriptName` is running and is at least
--   `minVersion`.  Returns true on success, false + LoopError
--   on failure.
-- ──────────────────────────────────────────────────────────
function version.checkScriptVersion(self, scriptName, minVersion)
    if not scriptName or not minVersion then
        LoopError("You must provide a script name and version.")
        return false
    end

    -- Check the script is running
    if GetResourceState(scriptName) ~= "started" then
        LoopError(string.format(
            "The script named %s could not be found. This script is required for %s.",
            scriptName, GetCurrentResourceName()
        ))
        return false
    end

    -- Read the script's version metadata
    local installedVersion = GetResourceMetadata(scriptName, "version", 0)
    if not installedVersion then
        LoopError(string.format(
            "We could not check the version. Because you are using a interesting version of %s. "
            .. "Please update the script.",
            scriptName
        ))
        return false
    end

    -- Compare against the minimum required version
    local diff = self:checkVersionDifference(minVersion, installedVersion)

    if diff <= 0 then
        -- Installed version meets or exceeds the minimum
        return true
    elseif diff > 1 then
        -- Very outdated — hard error
        LoopError(string.format(
            "^1You need to update the %s script. "
            .. "Minimum version required: %s Otherwise you can't use %s.",
            scriptName, minVersion, GetCurrentResourceName()
        ))
        return false
    else
        -- One minor version behind — soft warning
        LoopError(string.format(
            "You are using an old version of %s. Please update the script.",
            scriptName
        ))
        return false
    end
end

-- ──────────────────────────────────────────────────────────
-- Self update check
-- ──────────────────────────────────────────────────────────
if version.currentVersion then
    local versionUrl = "https://raw.githubusercontent.com/quasar-scripts/version/main/"
                    .. version.resourceName .. ".json"

    PerformHttpRequest(versionUrl, function(statusCode, body)
        if statusCode == 404 then
            print("^1API is not available. Unable to check the version.^0")
            return
        end

        if statusCode ~= 200 or not body then return end

        local ok, data = pcall(json.decode, body)
        if not ok or type(data) ~= "table" then return end

        local remoteVersion = data.version
        local descriptions  = data.descriptions

        if not remoteVersion or type(remoteVersion) ~= "string" then return end

        local diff = version:checkVersionDifference(remoteVersion)

        if diff == 0 then
            print("^2You are using the latest version of " .. version.resourceName .. "!^0")

        elseif diff > 0 then
            print("^3New version available for " .. version.resourceName .. "!^0")
            if type(descriptions) == "table" then
                for _, note in pairs(descriptions) do
                    print("^3- " .. tostring(note) .. "^0")
                end
            end
            print("^3You have version " .. version.currentVersion
                .. ", upgrade to version " .. remoteVersion .. "!^0")

        else
            print("^1You are using a newer version of " .. version.resourceName
                .. " than the one available on GitHub.^0")
        end
    end, "GET", "", {}, {})

else
    print("^3[" .. version.resourceName .. "] Could not read version metadata.^0")
end
