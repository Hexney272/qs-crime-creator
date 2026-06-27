-- ============================================================
-- client/modules/logger.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Client-side logging helper.  Takes a screenshot via the
-- screenshot-basic export and resolves a promise with the URL.
-- ============================================================

_G.cl_logger = {}

-- ──────────────────────────────────────────────────────────
-- cl_logger.takeScreenshot(webhookUrl)
--   Uploads a screenshot to `webhookUrl` using the
--   screenshot-basic resource and returns the image URL.
-- ──────────────────────────────────────────────────────────
function cl_logger.takeScreenshot(webhookUrl)
    local p = promise.new()

    exports["screenshot-basic"]:requestScreenshotUpload(
        webhookUrl,
        "file",
        function(rawResponse)
            local decoded = json.decode(rawResponse)
            if decoded then
                p:resolve(decoded.data.url)
            else
                p:resolve(nil)
            end
        end
    )

    return Citizen.Await(p)
end

-- ──────────────────────────────────────────────────────────
-- Callback: "crime:takeScreenshot"
--   Server-triggered screenshot request.  Returns the URL.
-- ──────────────────────────────────────────────────────────
lib.callback.register("crime:takeScreenshot", function(webhookUrl)
    return cl_logger.takeScreenshot(webhookUrl)
end)
