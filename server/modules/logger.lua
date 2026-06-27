-- ============================================================
-- server/modules/logger.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Discord webhook logger with rate-limit handling, FiveManage
-- screenshot support, and player info helpers.
-- ============================================================

_G.logger = {}

-- ──────────────────────────────────────────────────────────
-- Module-private state
-- ──────────────────────────────────────────────────────────
local logQueue    = {}       -- pending embed payloads
local isRunning   = false    -- queue processor active?
local sendCount   = 0        -- messages sent in current cycle
local lastSendAt  = 0        -- game-timer timestamp of last send
local rateDelay   = 0        -- ms to wait due to rate-limit

-- ──────────────────────────────────────────────────────────
-- Weapon hash → name lookup table (GTA V weapons)
-- ──────────────────────────────────────────────────────────
local weaponNames = {
    [-1569615261] = "Unarmed",
    [-1716189206] = "Knife",
    [1737195953]  = "Nightstick",
    [1317494643]  = "Hammer",
    [-1786099057] = "Baseball Bat",
    [1141786504]  = "Golf Club",
    [-2067956739] = "Crowbar",
    [453432689]   = "Pistol",
    [1593441988]  = "Combat Pistol",
    [584646201]   = "AP Pistol",
    [-1716589765] = "Pistol .50",
    [324215364]   = "Micro SMG",
    [736523883]   = "SMG",
    [-270015777]  = "Assault SMG",
    [-1074790547] = "Assault Rifle",
    [-2084633992] = "Carbine Rifle",
    [-1357824103] = "Advanced Rifle",
    [-1660422300] = "MG",
    [2144741730]  = "Combat MG",
    [487013001]   = "Pump Shotgun",
    [2017895192]  = "Sawed-Off Shotgun",
    [-494615257]  = "Assault Shotgun",
    [-1654528753] = "Bullpup Shotgun",
    [911657153]   = "Stun Gun",
    [100416529]   = "Sniper Rifle",
    [205991906]   = "Heavy Sniper",
    [856002082]   = "Remote Sniper",
    [-1568386805] = "Grenade Launcher",
    [1305664598]  = "Smoke Grenade Launcher",
    [-1312131151] = "RPG",
    [375527679]   = "Passenger Rocket",
    [324506233]   = "Airstrike Rocket",
    [1752584910]  = "Stinger [Vehicle]",
    [1119849093]  = "Minigun",
    [-1813897027] = "Grenade",
    [741814745]   = "Sticky Bomb",
    [-37975472]   = "Tear Gas",
    [-1600701090] = "BZ Gas",
    [615608432]   = "Molotov",
    [101631238]   = "Fire Extinguisher",
    [883325847]   = "Jerry Can",
    [966099553]   = "Object",
    [600439132]   = "Ball",
    [1233104067]  = "Flare",
    [1945616459]  = "Tank Cannon",
    [-123497569]  = "Rockets",
    [-268631733]  = "Laser",
    [1742569970]  = "Rocket",
    [-1474608608] = "Tank",
    [527765612]   = "Rocket",
    [-165357558]  = "Laser",
    [-1372674932] = "Laser",
    [133987706]   = "Rammed by Car",
    [-102323637]  = "Bottle",
    [1627465347]  = "Gusenberg Sweeper",
    [-1076751822] = "SNS Pistol",
    [137902532]   = "Vintage Pistol",
    [-1834847097] = "Antique Cavalry Dagger",
    [1198879012]  = "Flare Gun",
    [-771403250]  = "Heavy Pistol",
    [-1063057011] = "Special Carbine",
    [-1466123874] = "Musket",
    [2138347493]  = "Firework Launcher",
    [-952879014]  = "Marksman Rifle",
    [984333226]   = "Heavy Shotgun",
    [-1420407917] = "Proximity Mine",
    [1672152130]  = "Homing Launcher",
    [-102973651]  = "Hatchet",
    [171789620]   = "Combat PDW",
    [-656458692]  = "Knuckle Duster",
    [-598887786]  = "Marksman Pistol",
    [-581044007]  = "Machete",
    [-619010992]  = "Machine Pistol",
    [-1951375401] = "Flashlight",
    [-275439685]  = "Double Barrel Shotgun",
    [1649403952]  = "Compact Rifle",
    [-538741184]  = "Switchblade",
    [-1045183535] = "Heavy Revolver",
    [-544306709]  = "Fire",
    [341774354]   = "Heli Crash",
    [-1553120962] = "Run over by Car",
    [-868994466]  = "Hit by Water Cannon",
    [910830060]   = "Exhaustion",
    [539292904]   = "Explosion",
    [-1833087301] = "Electric Fence",
    [-1955384325] = "Bleeding",
    [1936677264]  = "Drowning in Vehicle",
    [-10959621]   = "Drowning",
    [1223143800]  = "Barbed Wire",
    [-1090665087] = "Vehicle Rocket",
    [2132975508]  = "Bullpup Rifle",
    [392730790]   = "Assault Sniper",
    [-1323279794] = "Rotors",
    [1834241177]  = "Railgun",
    [738733437]   = "Air Defence Gun",
    [317205821]   = "Automatic Shotgun",
    [-853065399]  = "Battle Axe",
    [125959754]   = "Compact Grenade Launcher",
    [-1121678507] = "Mini SMG",
    [-1169823560] = "Pipebomb",
    [-1810795771] = "Poolcue",
    [419712736]   = "Wrench",
    [126349499]   = "Snowball",
    [-100946242]  = "Animal",
    [148160082]   = "Cougar",
}

-- Embed colour palette
local COLORS = {
    default    = 14423100,
    blue       = 255,
    red        = 16711680,
    green      = 65280,
    white      = 16777215,
    black      = 0,
    orange     = 16744192,
    yellow     = 16776960,
    pink       = 16761035,
    lightgreen = 65309,
}

-- ──────────────────────────────────────────────────────────
-- local throttle()
--   Enforces the Discord rate-limit delay between sends.
-- ──────────────────────────────────────────────────────────
local function throttle()
    local now     = GetGameTimer()
    local elapsed = now - lastSendAt
    if elapsed < rateDelay then
        Wait(rateDelay - elapsed)
    end
    lastSendAt = GetGameTimer()
end

-- HTTP status codes that Discord considers successful
local SUCCESS_CODES = { [200] = true, [201] = true, [204] = true, [304] = true }

-- ──────────────────────────────────────────────────────────
-- local sendWebhook(payload)
--   Posts a single embed payload to Discord via HTTP.
--   Reads X-RateLimit-* headers to set rateDelay.
-- ──────────────────────────────────────────────────────────
local function sendWebhook(payload)
    if not payload.webhook or payload.webhook == "" then
        return Debug("no webhook")
    end

    local tagsStr = nil
    if payload.tags then
        tagsStr = ""
        for _, tag in ipairs(payload.tags) do
            tagsStr = tagsStr .. tag
        end
    end

    PerformHttpRequest(payload.webhook, function(statusCode, _, headers)
        if statusCode and not SUCCESS_CODES[statusCode] then
            return Debug("can't send log to discord", statusCode)
        end

        local remaining = tonumber(headers and headers["X-RateLimit-Remaining"])
        local resetAt   = tonumber(headers and headers["X-RateLimit-Reset"])

        if remaining and resetAt and remaining == 0 then
            local secsUntilReset = resetAt - os.time()
            if secsUntilReset > 0 then
                rateDelay = (secsUntilReset * 1000) / 10
            end
        end
    end, "POST", json.encode({
        username   = "Shop Logs",
        avatar_url = "https://i.ibb.co/Jwg1bBw9/hospital.png",
        content    = tagsStr,
        embeds     = payload.embed,
    }), { ["Content-Type"] = "application/json" })
end

-- ──────────────────────────────────────────────────────────
-- local processQueue()
--   Drains logQueue one entry at a time.
--   After every 5 sends, waits 60 s to avoid rate-limits.
-- ──────────────────────────────────────────────────────────
local function processQueue()
    if #logQueue > 0 then
        local entry = table.remove(logQueue, 1)
        sendWebhook(entry)
        sendCount = sendCount + 1

        if sendCount % 5 == 0 then
            Wait(60000)
        else
            throttle()
        end

        processQueue()
    else
        isRunning = false
    end
end

-- ──────────────────────────────────────────────────────────
-- local queueLog(data)
--   Builds an embed from `data` and pushes it to logQueue.
--   Starts the queue processor thread if not already running.
-- ──────────────────────────────────────────────────────────
local function queueLog(data)
    local embeds = {}
    local embed  = {
        title       = data.event,
        color       = COLORS[data.color] or COLORS.default,
        footer      = { text = os.date("%H:%M:%S %m-%d-%Y") },
        description = data.message,
        author      = { name = data.source },
    }

    -- Optionally attach a screenshot
    if data.takeScreenshot then
        local screenshotUrl = logger:takeScreenshot(data.takeScreenshot)
        if screenshotUrl then
            embed.image = { url = screenshotUrl }
        end
    end

    embeds[1] = embed

    logQueue[#logQueue + 1] = {
        webhook = data.webhook,
        tags    = data.tags,
        embed   = embeds,
    }

    if not isRunning then
        isRunning = true
        CreateThread(processQueue)
    end
end

-- ──────────────────────────────────────────────────────────
-- logger.getPresignedUrl(self)
--   Fetches a FiveManage presigned S3 URL for screenshot upload.
-- ──────────────────────────────────────────────────────────
function logger.getPresignedUrl(self)
    local p = promise.new()

    PerformHttpRequest(
        "https://fmapi.net/api/v2/presigned-url?fileType=image",
        function(_, body)
            local decoded = json.decode(body)
            if decoded and decoded.data then
                p:resolve(decoded.data.presignedUrl)
            else
                Error("logger:getPresignedUrl",
                    "Failed to get presigned url. Probably your fivemanage token is invalid.")
                p:resolve("")
            end
        end,
        "GET", nil,
        { Authorization = fivemanage.webhook }
    )

    return Citizen.Await(p)
end

-- ──────────────────────────────────────────────────────────
-- logger.takeScreenshot(self, playerId, presignedUrl)
--   Uses screenshot-basic to capture the player's screen and
--   upload it to FiveManage.  Returns the public URL.
-- ──────────────────────────────────────────────────────────
function logger.takeScreenshot(self, playerId, presignedUrl)
    local state = GetResourceState("screenshot-basic")
    if not state:find("started") then
        return Debug("screenshot-basic not started, webhook screenshot will not be shown")
    end

    if not fivemanage.webhook or fivemanage.webhook == "" then
        return Debug("fivemanage token not set, webhook screenshot will not be shown")
    end

    local url = presignedUrl or self:getPresignedUrl()
    return lib.callback.await("crime:takeScreenshot", playerId, url)
end

-- ──────────────────────────────────────────────────────────
-- logger.log(self, data)
--   Public entry point.  Queues a Discord log in a new thread.
--   data: { webhook, event, message, source, color, tags,
--           takeScreenshot }
-- ──────────────────────────────────────────────────────────
function logger.log(self, data)
    CreateThread(function()
        if data.webhook and data.webhook ~= "" then
            queueLog(data)
        end
    end)
end

-- ──────────────────────────────────────────────────────────
-- logger.getPlayerInfo(self, playerId)
--   Returns a table with all identifiers for `playerId`.
-- ──────────────────────────────────────────────────────────
local UNKNOWN = i18n.t("logs.unknown")

function logger.getPlayerInfo(self, playerId)
    if not DoesPlayerExist(playerId) then
        Debug("logger.getPlayerInfo :: Player:", playerId, "does not exist")
        return {
            name       = playerId,
            identifier = UNKNOWN,
            steam      = UNKNOWN, ip       = UNKNOWN,
            discord    = UNKNOWN, license  = UNKNOWN,
            license2   = UNKNOWN, xbl      = UNKNOWN,
            fivem      = UNKNOWN,
        }
    end

    local info = {
        name       = GetPlayerName(playerId),
        identifier = sfr:getIdentifier(playerId),
    }

    -- Parse all FiveM identifiers
    for i = 0, GetNumPlayerIdentifiers(playerId) - 1, 1 do
        local id = GetPlayerIdentifier(playerId, i)

        local prefixes = {
            steam    = "steam:",
            ip       = "ip:",
            discord  = "discord:",
            license  = "license:",
            license2 = "license2:",
            xbl      = "xbl:",
            live     = "live:",
            fivem    = "fivem:",
        }

        for key, prefix in pairs(prefixes) do
            if id:find(prefix) then
                info[key] = id:gsub(prefix, "")
                break
            end
        end
    end

    -- Fill any missing identifiers with the unknown placeholder
    for _, key in ipairs({"steam","ip","discord","license","license2","xbl","fivem"}) do
        if not info[key] then info[key] = UNKNOWN end
    end

    if not Config.ShowWebhookIP then
        info.ip = "Disabled"
    end

    return info
end

-- ──────────────────────────────────────────────────────────
-- logger.getPlayerInfoEmbed(self, title, playerId, playerInfo)
--   Returns a formatted i18n string with all player identifiers,
--   suitable for use as an embed description.
-- ──────────────────────────────────────────────────────────
function logger.getPlayerInfoEmbed(self, title, playerId, playerInfo)
    assert(title,    "logger.getPlayerInfoEmbed :: title is nil")
    assert(playerId, "logger.getPlayerInfoEmbed :: src is nil")

    if not playerInfo then
        playerInfo = self:getPlayerInfo(playerId)
    end

    return i18n.t("logs.player_info", {
        title      = title,
        name       = playerInfo.name,
        source     = playerId,
        identifier = playerInfo.identifier,
        steam      = playerInfo.steam,
        discord    = playerInfo.discord,
        license    = playerInfo.license,
        license2   = playerInfo.license2,
        xbl        = playerInfo.xbl,
        fivem      = playerInfo.fivem,
        ip         = playerInfo.ip,
    })
end
