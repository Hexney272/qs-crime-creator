--──────────────────────────────────────────────────────────────────────────────
--  Quasar Store · Configuration Guidelines
--──────────────────────────────────────────────────────────────────────────────
--  This configuration file defines all adjustable parameters for qs-crime-creator.
--  Comments are standardized to indicate which parts are safe to edit.
--
--  • [EDIT] – Safe to modify. Adjust as needed for your server.
--  • [INFO] – Explains purpose or behavior of a variable/block.
--  • [ADV]  – Advanced settings. Edit only if you understand the logic.
--  • [CORE] – Core functionality. Avoid changes unless you are a developer.
--  • [AUTO] – Automatically handled. Never modify manually.
--
--  Always make a backup before editing configuration files.
--  Documentation: https://docs.quasar-store.com/
--──────────────────────────────────────────────────────────────────────────────

--──────────────────────────────────────────────────────────────────────────────
-- Language Selection                                                          [EDIT]
-- [INFO] Select your main language. Files are located in locales/*.
--        You can create your own locale if it doesn’t exist yet.
--            ar, cs, da, de, el, en, es, fa, fr, hi, it, ja,
--            ko, nl, no, pt, ro, ru, sl, sv, th, tr, zh-CN
--──────────────────────────────────────────────────────────────────────────────
Config                              = {}

Config.Locale                       = 'hu'                          -- [EDIT] Language code. Available: ar, bg, da, de, el, en, es, fa, fr, hi, hu, it, ja, ko, nl, pt, ro, ru, tr, zh-CN
Config.Path                         = 'nui://qs-crime-creator/web/' -- [ADV]  Base NUI path (keep if you didn't move /web).
Config.ImagePath                    = Config.Path .. 'images/'      -- [ADV]  Asset path for images.

--──────────────────────────────────────────────────────────────────────────────
-- Framework Detection                                                         [AUTO]
-- [INFO] Automatically detects your framework (ESX or QBCore).
-- [INFO] If renamed, edit the framework name here or create adapters inside:
--        client/custom/framework/* and server/custom/framework/*
--──────────────────────────────────────────────────────────────────────────────
local frameworks                    = {
    ['es_extended'] = 'esx',
    ['qb-core'] = 'qb',
    ['qbx_core'] = 'qb'
}

Config.Framework                    = DependencyCheck(frameworks) or 'none' -- [AUTO]
Config.QBX                          = GetResourceState('qbx_core') == 'started'

--──────────────────────────────────────────────────────────────────────────────
-- Inventory Detection                                                         [AUTO]
-- [INFO] Detects which inventory system is running.
-- [INFO] To integrate another, create an adapter inside client/custom/inventory/.
--──────────────────────────────────────────────────────────────────────────────
local inventories                   = {
    ['qs-inventory'] = 'qs',
    ['ox_inventory'] = 'ox',
    ['qb-inventory'] = 'qb',
    ['tgiann-inventory'] = 'tgiann',
    ['codem-inventory'] = 'codem'
}

Config.Inventory                    = DependencyCheck(inventories) or 'standalone' -- [AUTO]

--──────────────────────────────────────────────────────────────────────────────
-- Default Stash Data                                                          [EDIT]
-- [INFO] Defines the base stash capacity for created shops.
--──────────────────────────────────────────────────────────────────────────────
Config.DefaultStashData             = {
    maxweight = 1000000, -- [EDIT] Maximum weight capacity.
    slots = 30,          -- [EDIT] Total number of item slots.
}

Config.MaxSearchResults             = 20     -- [EDIT] Maximum number of search results.
Config.MinZOffset                   = 30     -- [EDIT] Minimum shell Z spawn offset
Config.CreatorAlpha                 = 200    -- [EDIT] Creator ghost alpha (visual aid)
Config.MinPointLength               = 50.0   -- [EDIT] Minimum polygon length for areas
Config.RemoveHandcuffTimer          = 300000 -- [EDIT] Milliseconds before auto-uncuff (300000 = 5 minutes).

--──────────────────────────────────────────────────────────────────────────────
-- FiveGuard / InteractSound                                                   [EDIT]
-- [INFO] Set your FiveGuard resource name if used, or false if not.
-- [INFO] You can disable interaction sounds if your anticheat blocks them.
--──────────────────────────────────────────────────────────────────────────────
Config.FiveGuard                    = false -- [EDIT] false | 'your-resource-name'
Config.DisableInteractSound         = false -- [EDIT] true to disable ring doorbell.

--──────────────────────────────────────────────────────────────────────────────
-- Currency & Intl Formatting                                                  [EDIT]
-- [INFO] Purely visual. Affects how prices/dates appear in the NUI.
--──────────────────────────────────────────────────────────────────────────────
Config.Intl                         = {
    locales = 'en-US',            -- [EDIT] Format locale (e.g. en-US, pt-BR, es-ES, fr-FR, etc.)
    options = {
        style = 'currency',       -- [EDIT] Display style: 'decimal', 'currency', 'percent', 'unit'
        currency = 'USD',         -- [EDIT] Currency code (e.g. USD, EUR, BRL, RUB, CNY)
        minimumFractionDigits = 0 -- [EDIT] Number of decimal places shown.
    }
}

--──────────────────────────────────────────────────────────────────────────────
-- Door Logic                                                                  [EDIT]
-- [INFO] Interaction distances and duplicate detection.
--──────────────────────────────────────────────────────────────────────────────
Config.DoorDistance                 = 1.5 -- [EDIT] Interaction distance for doors
Config.DoorDuplicateDistance        = 3.0 -- [EDIT] Merge doors if closer than this

--──────────────────────────────────────────────────────────────────────────────
-- Ambulance System Detection                                                  [AUTO]
--──────────────────────────────────────────────────────────────────────────────
-- [INFO] Used to hook death/medical flows automatically if a supported resource is running.
--──────────────────────────────────────────────────────────────────────────────
local ambulances                    = { -- [CORE]
    ['qb-ambulancejob']      = 'qb',
    ['esx_ambulancejob']     = 'esx',
    ['wasabi_ambulance']     = 'wasabi',
    ['ars_ambulancejob']     = 'ars',
    ['qbx_medical']          = 'qbx',
    ['p_ambulancejob']       = 'piotreq',
    ['qs-medical-creator']   = 'qs',
    ['ak47_qb_ambulancejob'] = 'ak47qb',
    ['ak47_ambulancejob']    = 'ak47',
}
Config.Ambulance                    = DependencyCheck(ambulances) or 'standalone' -- [AUTO]

--──────────────────────────────────────────────────────────────────────────────
-- Drug Price Ranges                                                           [EDIT]
-- [INFO] Min/Max payout per item. Actual payout may vary with other modifiers.
--──────────────────────────────────────────────────────────────────────────────
Config.DrugsPrice                   = {
    ['weed_white-widow'] = { min = 15, max = 24 },
    ['weed_og-kush']     = { min = 15, max = 28 },
    ['weed_skunk']       = { min = 15, max = 31 },
    ['weed_amnesia']     = { min = 18, max = 34 },
    ['weed_purple-haze'] = { min = 18, max = 37 },
    ['weed_ak47']        = { min = 18, max = 40 },
    ['crack_baggy']      = { min = 18, max = 34 },
    ['cocaine_baggy']    = { min = 18, max = 37 },
    ['meth_baggy']       = { min = 18, max = 40 },
}

Config.SuccessChance                = 50 -- [EDIT] % chance of a successful sale
Config.ScamChance                   = 25 -- [EDIT] % chance NPC scams the player
Config.RobberyChance                = 15 -- [EDIT] % chance NPC attempts robbery
Config.RequiredCops                 = 0  -- [EDIT] Minimum online police needed to sell drugs
Config.PoliceCallChance             = 15 -- [EDIT] % chance an NPC calls police during a sale
Config.VehicleTheftPoliceCallChance = 15 -- [EDIT] % chance an NPC calls police during a vehicle theft mission

Config.PoliceJobs                   = {
    'police',
    'sheriff'
}

local dispatches                    = {
    ['qb-policejob'] = 'qb-policejob',
    ['qs-dispatch'] = 'qs-dispatch'
}

Config.Dispatch                     = DependencyCheck(dispatches) or 'standalone'

Config.DefaultLightIntensity        = 20.0       -- [EDIT] Default light intensity inside shells
Config.SellObjectCommision          = 0.3        -- [EDIT] Furniture sale commission (0.30 = 30%)
Config.EnableF3Shop                 = true       -- [EDIT] Disable decoration purchase from F3
Config.DynamicDoors                 = true       -- [EDIT] Enable dynamic doors?
Config.SpawnDistance                = 100.0      -- [EDIT] Object spawn radius (meters)
Config.MaximumDistanceForDecorate   = 350.0      -- [EDIT] Max decorate distance or false to disable
Config.MoneyType                    = 'money'    -- [EDIT] Options: 'money' | 'bank' (actually using for decorate)
Config.DefaultRequestModelTimeout   = 15000
Config.Music                        = 'decorate' -- [EDIT] false to disable music
Config.MusicVolume                  = 0.05       -- [EDIT] Music volume (0.0–1.0)

Config.Cleaning                     = true
Config.JunkObjects                  = {
    'qs_dust_prop_01',
    'qs_dust_prop_01',
    'qs_garbage_prop_01',
    'qs_garbage_prop_02',
    'qs_garbage_prop_03'
}
Config.JunkObjectTime               = 10 * 60 * 1000 -- 10 minutes
Config.MaxJunkPerHouse              = 10             -- Maximum junk objects per house

-- Cleaner Robot Settings                                                        [EDIT]
-- [INFO] Settings for the autonomous cleaning robot furniture.
Config.CleanerRobot                 = {
    moveSpeed = 0.012,               -- Base movement speed (very slow, realistic)
    maxSpeed = 0.024,                -- Maximum movement speed
    acceleration = 0.0003,           -- How fast robot accelerates
    deceleration = 0.0008,           -- How fast robot decelerates
    raycastDistance = 0.8,           -- Distance for obstacle detection
    junkDetectRadius = 1.0,          -- Radius to detect junk to clean
    maxDistanceFromDock = 12.0,      -- Maximum distance robot can travel from dock (prevents leaving house)
    cleaningTimeout = 5 * 60 * 1000, -- Time (ms) before robot auto-returns to dock (5 minutes)
    randomDirectionTime = 15000,     -- Time (ms) before random direction change
    maxStuckTime = 5000,             -- Time (ms) before robot tries to unstick itself
    wobbleEnabled = true,            -- Enable slight wobble for realism
    wobbleAmount = 0.15,             -- Wobble intensity (degrees)
    wobbleSpeed = 0.08,              -- Wobble oscillation speed
}

--──────────────────────────────────────────────────────────────────────────────
-- Wardrobe / Appearance Detection                                             [AUTO]
-- [INFO] Detects your clothing/appearance system automatically.
-- [INFO] To add support for a new one, create adapters in:
-- client/custom/wardrobe/*.lua
--──────────────────────────────────────────────────────────────────────────────
local wardrobes                     = { -- [CORE]
    ['qs-appearance']       = 'qs-appearance',
    ['qb-clothing']         = 'qb-clothing',
    ['codem-appearance']    = 'codem-appearance',
    ['ak47_clothing']       = 'ak47_clothing',
    ['fivem-appearance']    = 'fivem-appearance',
    ['illenium-appearance'] = 'illenium-appearance',
    ['raid_clothes']        = 'raid_clothes',
    ['rcore_clothes']       = 'rcore_clothes',
    ['origen_clothing']     = 'origen_clothing',
    ['rcore_clothing']      = 'rcore_clothing',
    ['sleek-clothestore']   = 'sleek-clothestore',
    ['tgiann-clothing']     = 'tgiann-clothing',
    ['p_appearance']        = 'p_appearance',
    ['0r-clothingv2']       = '0r-clothingv2'
}
Config.Wardrobe                     = DependencyCheck(wardrobes) or 'default' -- [AUTO]

--──────────────────────────────────────────────────────────────────────────────
-- Shells & Interior Models                                                    [EDIT]
-- [INFO] Define available interior shells (MLO replacements or instanced).
-- [INFO] Each shell can include custom stash settings.
--──────────────────────────────────────────────────────────────────────────────
Config.Shells                       = { -- [EDIT]
    -- SubhamPRO Colab Shells
    {
        model = 'mv_sh_01_subhampro_tebex_io',
        stash = { maxweight = 1000000, slots = 5 }
    },
    {
        model = 'mv_sh_02_subhampro_tebex_io',
        stash = { maxweight = 1000000, slots = 5 }
    }
}


Config.TimeInterior         = 4

--──────────────────────────────────────────────────────────────────────────────
-- IPL Interiors & Themes                                                      [EDIT]
-- [INFO] Preconfigured IPL entries (coords, themes, stash). Add/remove freely.
-- [INFO] For bob74_ipl entries, export returns the related IPL object.
--──────────────────────────────────────────────────────────────────────────────
Config.IplData              = {
    {
        -- Apartment
        export       = function()
            return exports['bob74_ipl']:GetExecApartment1Object()
        end,
        defaultTheme = 'seductive',
        themes       = {
            { label = 'Modern',     value = 'modern',     price = 500, image = Config.ImagePath .. 'management/themes/apartment/modern.png' },
            { label = 'Moody',      value = 'moody',      price = 500, image = Config.ImagePath .. 'management/themes/apartment/moody.png' },
            { label = 'Vibrant',    value = 'vibrant',    price = 500, image = Config.ImagePath .. 'management/themes/apartment/vibrant.png' },
            { label = 'Monochrome', value = 'monochrome', price = 500, image = Config.ImagePath .. 'management/themes/apartment/monochrome.png' },
            { label = 'Seductive',  value = 'seductive',  price = 500, image = Config.ImagePath .. 'management/themes/apartment/seductive.png' },
            { label = 'Regal',      value = 'regal',      price = 500, image = Config.ImagePath .. 'management/themes/apartment/regal.png' },
            { label = 'Aqua',       value = 'aqua',       price = 500, image = Config.ImagePath .. 'management/themes/apartment/aqua.png' },
            -- { label = 'Sharp',   value = 'sharp',      price = 500, image = './assets/img/management/themes/apartment/sharp.png' }
        },
        exitCoords   = vec3(-787.44, 315.81, 217.64),
        iplCoords    = vec3(-787.78050000, 334.92320000, 215.83840000),
        stash        = { maxweight = 1000000, slots = 10 },
        shower       = {
            ptfxOffset = vec3(0.760, 15.928, 5.837),
            animationOffset = vec4(0.760, 15.928, 4.637, 175.785)
        },
        sink         = {
            ptfxOffset = vec3(-2.595, 16.937, 4.600),
            animationOffset = vec4(-2.561, 17.011, 4.600, 175.747),
        },
        cooking      = {
            animationOffset = vec4(-5.337, -5.332, 1.200, 91.176),
            recipes = Config.CookingRecipes
        },
        toilet       = {
            ptfxOffset = vec3(-2.954, 19.387, 5.113),
            animationOffset = vec4(-2.954, 19.387, 5.113, 176.495),
        }
    },
    {
        -- Office
        export       = function()
            return exports['bob74_ipl']:GetFinanceOffice1Object()
        end,
        defaultTheme = 'warm',
        themes       = {
            { label = 'Warm',         value = 'warm',         price = 500, image = Config.ImagePath .. 'management/themes/office/warm.png' },
            { label = 'Classical',    value = 'classical',    price = 500, image = Config.ImagePath .. 'management/themes/office/classical.png' },
            { label = 'Vintage',      value = 'vintage',      price = 500, image = Config.ImagePath .. 'management/themes/office/vintage.png' },
            { label = 'Contrast',     value = 'contrast',     price = 500, image = Config.ImagePath .. 'management/themes/office/contrast.png' },
            { label = 'Rich',         value = 'rich',         price = 500, image = Config.ImagePath .. 'management/themes/office/rich.png' },
            { label = 'Cool',         value = 'cool',         price = 500, image = Config.ImagePath .. 'management/themes/office/cool.png' },
            { label = 'Ice',          value = 'ice',          price = 500, image = Config.ImagePath .. 'management/themes/office/ice.png' },
            { label = 'Conservative', value = 'conservative', price = 500, image = Config.ImagePath .. 'management/themes/office/conservative.png' },
            { label = 'Polished',     value = 'polished',     price = 500, image = Config.ImagePath .. 'management/themes/office/polished.png' }
        },
        exitCoords   = vec3(-141.1987, -620.913, 168.8205),
        iplCoords    = vec3(-141.1987, -620.913, 168.8205),
        stash        = { maxweight = 1000000, slots = 10 },
    },
    {
        -- Night Club
        exitCoords = vec3(-1569.402222, -3017.604492, -74.413940),
        iplCoords  = vec3(-1604.664, -3012.583, -78.000),
        stash      = { maxweight = 1000000, slots = 10 },
    },
    {
        -- Clubhouse 1
        exitCoords = vec3(1121.037354, -3152.782471, -37.074707),
        iplCoords  = vec3(1107.04, -3157.399, -37.51859),
        stash      = { maxweight = 1000000, slots = 10 },
    },
    {
        -- Clubhouse 2
        exitCoords = vec3(997.028564, -3158.136230, -38.911377),
        iplCoords  = vec3(998.4809, -3164.711, -38.90733),
        stash      = { maxweight = 1000000, slots = 10 },
    },
    {
        -- Cocaine Lab
        exitCoords = vec3(1088.703247, -3187.463623, -38.995605),
        iplCoords  = vec3(1093.6, -3196.6, -38.99841),
        stash      = { maxweight = 1000000, slots = 10 },
    },
    {
        -- Meth Lab
        exitCoords = vec3(996.896729, -3200.914307, -36.400757),
        iplCoords  = vec3(1009.5, -3196.6, -38.99682),
        stash      = { maxweight = 1000000, slots = 10 },
    },
    {
        -- Weed Lab
        exitCoords = vec3(1066.298950, -3183.586914, -39.164062),
        iplCoords  = vec3(1056.975830, -3194.571533, -39.164062),
        stash      = { maxweight = 1000000, slots = 10 },
    },
    {
        -- Counterfeit Cash Factory
        exitCoords = vec3(1138.101074, -3199.107666, -39.669556),
        iplCoords  = vec3(1121.897, -3195.338, -40.4025),
        stash      = { maxweight = 1000000, slots = 10 },
    },
    {
        -- Document Forgery
        exitCoords = vec3(1173.7, -3196.73, -39.01),
        iplCoords  = vec3(1165, -3196.6, -39.01306),
        stash      = { maxweight = 1000000, slots = 10 },
    },
    {
        -- Penthouse Casino
        exitCoords = vec3(980.83, 56.51, 116.16),
        iplCoords  = vec3(976.636, 70.295, 115.164),
        stash      = { maxweight = 1000000, slots = 10 },
    },
    {
        -- NightClub Warehouse
        exitCoords = vec3(-1520.88, -2978.54, -80.45),
        iplCoords  = vec3(-1505.783, -3012.587, -80.000),
        stash      = { maxweight = 1000000, slots = 10 },
    },
    {
        -- 2 Car
        exitCoords = vec3(179.15, -1000.15, -99.0),
        iplCoords  = vec3(173.2903, -1003.6, -99.65707),
        stash      = { maxweight = 1000000, slots = 10 },
    },
    {
        -- 6 Car
        exitCoords = vec3(212.4, -998.97, -99.0),
        iplCoords  = vec3(197.8153, -1002.293, -99.65749),
        stash      = { maxweight = 1000000, slots = 10 },
    },
    {
        -- 10 Car
        exitCoords = vec3(240.67, -1004.69, -99.0),
        iplCoords  = vec3(229.9559, -981.7928, -99.66071),
        stash      = { maxweight = 1000000, slots = 10 },
    },
    {
        -- Casino NightClub
        exitCoords = vec3(1545.57, 254.22, -46.01),
        iplCoords  = vec3(1550.0, 250.0, -48.0),
        stash      = { maxweight = 1000000, slots = 10 },
    },
    {
        -- Warehouse Small
        exitCoords = vec3(1087.43, -3099.48, -39.0),
        iplCoords  = vec3(1094.988, -3101.776, -39.00363),
        stash      = { maxweight = 1000000, slots = 10 },
    },
    {
        -- Warehouse Medium
        exitCoords = vec3(1048.12, -3097.28, -39.0),
        iplCoords  = vec3(1056.486, -3105.724, -39.00439),
        stash      = { maxweight = 1000000, slots = 10 },
    },
    {
        -- Warehouse Large
        exitCoords = vec3(992.38, -3098.08, -39.0),
        iplCoords  = vec3(1006.967, -3102.079, -39.0035),
        stash      = { maxweight = 1000000, slots = 10 },
    },
    {
        -- Vehicle Warehouse
        exitCoords = vec3(956.12, -2987.24, -39.65),
        iplCoords  = vec3(994.5925, -3002.594, -39.64699),
        stash      = { maxweight = 1000000, slots = 10 },
    },
    {
        -- Old Bunker Interior
        exitCoords = vec3(899.5518, -3246.038, -98.04907),
        iplCoords  = vec3(899.5518, -3246.038, -98.04907),
        stash      = { maxweight = 1000000, slots = 10 },
    },
    {
        -- Arcadius Garage 1
        exitCoords = vec3(-198.666, -580.515, 136.00),
        iplCoords  = vec3(-191.0133, -579.1428, 135.0000),
        stash      = { maxweight = 1000000, slots = 10 },
    },
    {
        -- Arcadius Mod Shop
        exitCoords = vec3(-139.388, -587.917, 167.00),
        iplCoords  = vec3(-146.6166, -596.6301, 166.0000),
        stash      = { maxweight = 1000000, slots = 10 },
    },
    {
        -- 2133 Mad Wayne Thunder
        exitCoords = vec3(-1289.89, 449.83, 97.9),
        iplCoords  = vec3(-1288, 440.748, 97.69459),
        stash      = { maxweight = 1000000, slots = 10 },
    },
    {
        -- 2868 Hillcrest Avenue
        exitCoords = vec3(-753.04, 618.82, 144.14),
        iplCoords  = vec3(-763.107, 615.906, 144.1401),
        stash      = { maxweight = 1000000, slots = 10 },
    },
    {
        -- Eclipse Towers, Apt 3
        exitCoords = vec3(-785.12, 323.75, 212.0),
        iplCoords  = vec3(-773.407, 341.766, 211.397),
        stash      = { maxweight = 1000000, slots = 10 },
    },
    {
        -- Del Perro Heights, Apt 7
        exitCoords = vec3(-1453.86, -517.64, 56.93),
        iplCoords  = vec3(-1477.14, -538.7499, 55.5264),
        stash      = { maxweight = 1000000, slots = 10 },
    },
    {
        -- 3717 Mansion 1
        exitCoords = vec3(537.4049072265625, 749.0591430664062, 202.4766540527344),
        iplCoords  = vec3(533.525269, 725.169250, 202.293823),
        stash      = { maxweight = 1000000, slots = 10 },
        zone       = {
            points = {
                vec3(546.3588256835938, 809.3697509765625, 200.2849273681641),
                vec3(605.490478515625, 768.5374755859375, 203.1336212158203),
                vec3(540.7081909179688, 663.1214599609375, 162.0594940185547),
                vec3(466.2291259765625, 740.6036376953125, 198.61166381835935)

            }
        }
    },
    {
        -- 3717 Mansion 2
        exitCoords = vec3(-1666.8931884765625, 477.24078369140625, 129.33653259277344),
        iplCoords  = vec3(-1630.219727, 469.938477, 129.131836),
        stash      = { maxweight = 1000000, slots = 10 },
        zone       = {
            points = {
                vec3(-1709.6185302734375, 489.9075927734375, 129.32821655273438),
                vec3(-1643.3818359375, 528.0819091796875, 129.74615478515625),
                vec3(-1586.5408935546875, 427.3875122070313, 107.04544830322266),
                vec3(-1669.523193359375, 391.99224853515625, 89.07738494873047)
            }
        }
    },
    {
        -- 3717 Mansion 3
        exitCoords = vec3(-2587.67724609375, 1911.02001953125, 167.4906005859375),
        iplCoords  = vec3(-2602.984619, 1874.663696, 167.296753),
        stash      = { maxweight = 1000000, slots = 10 },
        zone       = {
            points = {
                vec3(-2610.777099609375, 1940.5137939453127, 171.35894775390625),
                vec3(-2531.7802734375, 1935.3734130859375, 171.43614196777344),
                vec3(-2548.482177734375, 1858.4361572265625, 171.41339111328125),
                vec3(-2665.338623046875, 1859.841552734375, 171.62115478515625)
            }
        }
    },
}

-- Set false if you don't want to use a key to open the interaction menu
-- You can configure the interaction menu in custom/client.lua
Config.InteractionKey       = 'F4'

Config.ManagementButtons    = {
    wardrobe = true,        -- [EDIT] Show/hide wardrobe button
    storage = true,         -- [EDIT] Show/hide storage button
    charge = true,          -- [EDIT] Show/hide charge button (requires qs-smartphone-pro)
    music = true,           -- [EDIT] Show/hide music button
    decorate = true,        -- [EDIT] Show/hide decorate button
    rent = true,            -- [EDIT] Show/hide rent button
    cancelRent = true,      -- [EDIT] Show/hide cancel rent button
    sellBank = true,        -- [EDIT] Show/hide sell to bank button
    sellPlayer = true,      -- [EDIT] Show/hide sell to player button
    cancelSellHouse = true, -- [EDIT] Show/hide cancel sell house button
    leave = true,           -- [EDIT] Show/hide leave button
}

Config.IllegalMedic         = {
    {
        label = 'Ricardo',
        price = 5000,
        coords = vec4(-116.43928527832033, 6479.689453125, 30.46393775939941, 42.01502227783203),
        pedModel = 's_m_m_doctor_01'
    }
}

--──────────────────────────────────────────────────────────────────────────────
-- Creator Job Permissions                                                     [EDIT]
-- [INFO] Define which jobs (and grades) can access the shop creator.
-- [INFO] Set grade=false to allow all grades.
--──────────────────────────────────────────────────────────────────────────────
Config.CreatorJobs          = {
    {
        job = 'police',
        grade = { 1, 2, 3 } -- [EDIT] Specific grades allowed.
    },
    {
        job = 'ambulance',
        grade = false -- [EDIT] All grades allowed.
    }
}

--──────────────────────────────────────────────────────────────────────────────
-- Targeting Settings                                                          [EDIT]
-- [INFO] Define interaction method and hitbox dimensions.
--──────────────────────────────────────────────────────────────────────────────
Config.TargetWidth          = 5.0   -- [EDIT] Interaction area width.
Config.TargetHeight         = 5.0   -- [EDIT] Interaction area height.
Config.UseTarget            = false -- [EDIT] true = qb-target/ox_target | false = disable target system.

--──────────────────────────────────────────────────────────────────────────────
-- Creator Core Settings                                                       [EDIT]
-- [INFO] Configure minimum limits and editor behaviors.
--──────────────────────────────────────────────────────────────────────────────
Config.MinPointLength       = 70.0 -- [EDIT] Minimum polygon length for area creation.

--──────────────────────────────────────────────────────────────────────────────
-- Free Mode Controls                                                          [EDIT]
-- [INFO] Defines movement and rotation keys used in creation mode.
--──────────────────────────────────────────────────────────────────────────────
Config.FreeModeKeys         = {
    ChangeKey = Keys['LEFTCTRL'],       -- [EDIT] Toggle free mode controls.

    MoreSpeed = Keys['.'],              -- [EDIT] Increase movement speed.
    LessSpeed = Keys[','],              -- [EDIT] Decrease movement speed.

    MoveToTop = Keys['TOP'],            -- [EDIT] Move object upward.
    MoveToDown = Keys['DOWN'],          -- [EDIT] Move object downward.

    MoveToForward = Keys['TOP'],        -- [EDIT] Move object forward.
    MoveToBack = Keys['DOWN'],          -- [EDIT] Move object backward.
    MoveToRight = Keys['RIGHT'],        -- [EDIT] Move object to the right.
    MoveToLeft = Keys['LEFT'],          -- [EDIT] Move object to the left.

    RotateToTop = Keys['6'],            -- [EDIT] Rotate upward.
    RotateToDown = Keys['7'],           -- [EDIT] Rotate downward.
    RotateToLeft = Keys['8'],           -- [EDIT] Rotate to the left.
    RotateToRight = Keys['9'],          -- [EDIT] Rotate to the right.

    TiltToTop = Keys['Z'],              -- [EDIT] Tilt upward.
    TiltToDown = Keys['X'],             -- [EDIT] Tilt downward.
    TiltToLeft = Keys['C'],             -- [EDIT] Tilt left.
    TiltToRight = Keys['V'],            -- [EDIT] Tilt right.

    StickToTheGround = Keys['LEFTALT'], -- [EDIT] Snap object to ground.
}

-- Points must be used from inside their poly? (entry, board, customHouse, shell)
Config.NeedToBeInsidePoints = { -- [EDIT]
    ['entry']       = true,     -- [INFO] Require to be inside entry poly to interact.
    ['board']       = true,     -- [INFO] Require to be inside board poly to interact.
    ['customHouse'] = false,    -- [INFO] Allow custom house actions from outside.
    ['shell']       = false     -- [INFO] Force shell interactions inside shell poly.
}

Config.Upgrades             = { -- [EDIT]
    {
        name = 'stash',
        title = 'Stash Capacity',
        description = 'Increase your organization stash capacity. Each upgrade adds more storage space.',
        maxLevel = 5,
        levels = {
            { price = 10000, value = 5 },  -- Level 1: +5kg
            { price = 15000, value = 15 }, -- Level 2: +15kg
            { price = 20000, value = 20 }, -- Level 3: +20kg
            { price = 25000, value = 25 }, -- Level 4: +25kg
            { price = 30000, value = 30 }, -- Level 5: +30kg (max)
        }
    },
    {
        name = 'stash_slots',
        title = 'Stash Slots',
        description = 'Increase your organization stash slots. Each upgrade adds more item slots.',
        maxLevel = 5,
        levels = {
            { price = 10000, value = 5 },  -- Level 1: +5 slots
            { price = 15000, value = 10 }, -- Level 2: +10 slots
            { price = 20000, value = 15 }, -- Level 3: +15 slots
            { price = 25000, value = 20 }, -- Level 4: +20 slots
            { price = 30000, value = 25 }, -- Level 5: +25 slots (max)
        }
    },
    {
        name = 'camera',
        title = 'Security Cameras',
        description = 'High-definition surveillance system with night vision and motion detection. Monitor your property from anywhere with remote access.',
        maxLevel = 1,
        levels = {
            { price = 35000, value = 1 }, -- Level 1: Basic cameras
        }
    },
    {
        name = 'vault',
        title = 'Vault Lock',
        description = 'Military-grade security vault with biometric access and time-delay mechanisms. Maximum protection for your valuables.',
        maxLevel = 1,
        levels = {
            { price = 50000, value = 1 },
        }
    },
    {
        name = 'furniture',
        title = 'Furniture Upgrade',
        description = 'Expand your property\'s furniture capacity. Each upgrade increases the maximum number of furniture items.',
        maxLevel = 4,
        levels = {
            { price = 30000, value = 100 }, -- Level 1: 100 items
            { price = 45000, value = 125 }, -- Level 2: 125 items
            { price = 60000, value = 150 }, -- Level 3: 150 items
            { price = 80000, value = 200 }, -- Level 4: 200 items (max)
        }
    },
    {
        name = 'garage',
        title = 'Garage Slots',
        description = 'Increase your organization garage capacity. Each upgrade adds more vehicle slots.',
        maxLevel = 50,
        levels = {
            { price = 10000, value = 1 }, -- Level 1: +1 slot (total 2)
            { price = 15000, value = 2 }, -- Level 2: +2 slots (total 4)
            { price = 20000, value = 3 }, -- Level 3: +3 slots (total 7)
            { price = 25000, value = 4 }, -- Level 4: +4 slots (total 11)
            { price = 30000, value = 5 }, -- Level 5: +5 slots (total 16)
        }
    },
    {
        name = 'illegal_medic_locations',
        title = 'Illegal Medic Locations',
        description = 'Unlock the locations of illegal medics on your crime tablet map. Find trusted medical contacts across the city.',
        maxLevel = 1,
        levels = {
            { price = 25000, value = 1 }, -- Level 1: Show illegal medic locations
        }
    },
    {
        name = 'money_laundering',
        title = 'Money Laundering Access',
        description = 'Unlock access to money laundering operations. Convert your dirty money into clean cash through a network of discrete delivery points across the city.',
        maxLevel = 1,
        levels = {
            { price = 50000, value = 1 }, -- Level 1: Unlock money laundering
        }
    },
}


--──────────────────────────────────────────────────────────────────────────────
-- Organization Garage Settings                                                [EDIT]
-- [INFO] Configure organization garage system settings.
--──────────────────────────────────────────────────────────────────────────────
Config.OrganizationGarage = {
    DefaultSlots = 1,         -- [EDIT] Starting garage slots for new organizations
    MaxSlots = 50,            -- [EDIT] Maximum garage slots that can be upgraded
    ImpoundPrice = 5000,      -- [EDIT] Price to retrieve vehicle from impound
    SellPricePercent = 30,    -- [EDIT] Percentage of original purchase price when selling vehicle (30 = 30%)
    SpawnDistance = 50.0,     -- [EDIT] Distance to check if vehicle is spawned in world
    InteractionDistance = 2.5 -- [EDIT] Distance to interact with garage
}

--──────────────────────────────────────────────────────────────────────────────
-- Editor / Action Controls                                                    [EDIT]
-- [INFO] Defines the control bindings used in polygon/creator editing mode.
--──────────────────────────────────────────────────────────────────────────────
ActionControls            = {
    leftClick              = { label = 'Left Click', codes = { 24 } },
    forward                = { label = 'Forward +/-', codes = { 33, 32 } },
    right                  = { label = 'Right +/-', codes = { 35, 34 } },
    up                     = { label = 'Up +/-', codes = { 52, 51 } },
    add_point              = { label = 'Add Point', codes = { 24 } },
    undo_point             = { label = 'Undo Last', codes = { 25 } },
    rotate_z               = { label = 'RotateZ +/-', codes = { 20, 73 } },
    rotate_z_scroll        = { label = 'RotateZ +/-', codes = { 17, 16 } },
    offset_z               = { label = 'Offset Z +/-', codes = { 44, 46 } },
    boundary_height        = { label = 'Z Boundary +/-', codes = { 20, 73 } },
    done                   = { label = 'Done', codes = { 191 } },
    cancel                 = { label = 'Cancel', codes = { 194 } },
    arrow_left             = { label = 'Previous', codes = { 174 } },
    arrow_right            = { label = 'Next', codes = { 175 } },
    -- Decorate (Modern Mode)
    place_object_on_ground = { label = 'Place Object on Ground', codes = { 47 } },
    toggle_free_mode       = { label = 'Toggle Free Mode', codes = { 167 } },
    toggle_cursor          = { label = 'Toggle Cursor', codes = { 166 } },
    toggle_editor_mode     = { label = 'Toggle Translate/Rotate', codes = { 311 } },
    toggle_gizmo_mode      = { label = 'Toggle Gizmo Mode', codes = { 244 } },
    toggle_free_camera     = { label = 'Toggle Free Camera', codes = { 170 } },
    focus_free_camera      = { label = 'Focus Object', codes = { 49 } },
    zoom                   = { label = 'Zoom +/-', codes = { 17, 16 } },

    -- DEPREACTED NEED TO CHECK
    set_any                = { label = 'Set', codes = { 24 } },
    set_position           = { label = 'Set Position', codes = { 24 } },
    add_garage             = { label = 'Add Garage', codes = { 24 } },
    increase_z             = { label = 'Z Boundary +/-', codes = { 180, 181 } },
    decrease_z             = { label = 'Z Boundary +/-', codes = { 21, 180, 181 } },
    change_player          = { label = 'Player +/-', codes = { 82, 81 } },
    change_shell           = { label = 'Change Shell +/-', codes = { 189, 190 } },
    select_player          = { label = 'Select Player', codes = { 191 } },
    change_outfit          = { label = 'Outfit +/-', codes = { 82, 81 } },
    delete_outfit          = { label = 'Delete Outfit', codes = { 178 } },
    select_vehicle         = { label = 'Vehicle +/-', codes = { 82, 81 } },
    spawn_vehicle          = { label = 'Spawn Vehicle', codes = { 191 } },
    leftApt                = { label = 'Previous Apartment', codes = { 174 } },
    rightApt               = { label = 'Next Apartment', codes = { 175 } },
    testPos                = { label = 'Test Pos', codes = { 47 } },
}

--──────────────────────────────────────────────────────────────────────────────
-- Camera Options                                                              [EDIT]
-- [INFO] Adjusts free-camera movement speed and sensitivity.
--──────────────────────────────────────────────────────────────────────────────
CameraOptions             = {
    lookSpeedX = 1000.0, -- [EDIT] Horizontal camera speed.
    lookSpeedY = 1000.0, -- [EDIT] Vertical camera speed.
    moveSpeed = 20.0,    -- [EDIT] General camera movement speed.
    climbSpeed = 10.0,   -- [EDIT] Vertical (up/down) speed.
    rotateSpeed = 20.0,  -- [EDIT] Camera rotation speed.
}

--──────────────────────────────────────────────────────────────────────────────
-- Money Types                                                                 [EDIT]
-- [INFO] Define available money types for season pass rewards.
--──────────────────────────────────────────────────────────────────────────────
Config.MoneyTypes         = { -- [EDIT]
    {
        label = 'Money',
        value = 'money',
    },
    {
        label = 'Bank',
        value = 'bank',
    },
    {
        label = 'Black Money',
        value = 'black_money',
    }
}

--──────────────────────────────────────────────────────────────────────────────
-- Finance Money Types                                                         [EDIT]
-- [INFO] Define available money types for organization finance deposits and withdrawals.
--──────────────────────────────────────────────────────────────────────────────
Config.FinanceMoneyTypes  = { -- [EDIT]
    'money',
    'bank',
    'black_money'
}

--──────────────────────────────────────────────────────────────────────────────
-- Reward Types                                                                [EDIT]
-- [INFO] Define available reward types for season pass. You can add custom types.
--──────────────────────────────────────────────────────────────────────────────
Config.RewardTypes        = { -- [EDIT]
    'money',
    'vehicle',
    'item'
}

--──────────────────────────────────────────────────────────────────────────────
-- Reward Rarities                                                             [EDIT]
-- [INFO] Define available rarities for season pass rewards.
--──────────────────────────────────────────────────────────────────────────────
Config.RewardRarities     = { -- [EDIT]
    'common',
    'rare',
    'epic',
    'legendary'
}

--──────────────────────────────────────────────────────────────────────────────
-- Debug Mode                                                                  [EDIT]
-- [INFO] Enables or disables verbose console logging. Keep off in production.
--──────────────────────────────────────────────────────────────────────────────
Config.Debug              = true -- [EDIT]
Config.ZoneDebug          = false

--──────────────────────────────────────────────────────────────────────────────
-- Graffiti System                                                             [EDIT]
-- [INFO] Configure the graffiti/spray paint system for organizations.
--──────────────────────────────────────────────────────────────────────────────
Config.Graffiti           = {
    Enabled = true,        -- [EDIT] Enable/disable the graffiti system
    RenderDistance = 50.0, -- [EDIT] Distance at which graffitis are rendered

    -- Item Settings
    DefaultItem = 'organization_paint', -- [EDIT] Default item name for spray paint
    SprayDuration = 5000,               -- [EDIT] Duration of spray animation (ms)
    CleanerItem = 'spray_cleaner',      -- [EDIT] Default item name for spray cleaner

    -- Scale Settings
    MinScale = 2.0,     -- [EDIT] Minimum graffiti scale
    MaxScale = 7.0,     -- [EDIT] Maximum graffiti scale
    DefaultScale = 4.0, -- [EDIT] Default graffiti scale

    fonts = {
        'sprayf',
        'sprayouth',
        'spraynot'
    },

    CheckDistance = 50.0, -- [EDIT] Distance to check for nearby sprays (in meters)
    MaxSprayCount = 15    -- [EDIT] Maximum number of sprays allowed within CheckDistance (do not change this)

}

--──────────────────────────────────────────────────────────────────────────────
-- Crime Tablet Settings                                                       [EDIT]
-- [INFO] Configure crime tablet system settings.
--──────────────────────────────────────────────────────────────────────────────
Config.CrimeTablet        = {
    Item = 'tablet',                -- [EDIT] Item to open tablet (set false if you don't want to use an item)
    EnableTerritoryWar = true,      -- [EDIT] Enable territory war system
    WarStartCost = 50000,           -- [EDIT] Cost to start a territory war
    WarDuration = 3600,             -- [EDIT] War duration in seconds (1 hour = 3600)
    WarMinPlayers = 1,              -- [EDIT] Minimum players required to start a war
    WarProtectionDuration = 172800, -- [EDIT] Protection duration after war in seconds (2 days = 172800)
    WarScore = {
        TaxStolen = 100,            -- [EDIT] Points for stealing taxing
        DrugSaleMultiplier = 0.33,  -- [EDIT] Points from drug sales (1/3 of sale price)
        GraffitiSpray = 3,          -- [EDIT] Points for spraying graffiti
        GraffitiRemove = 5,         -- [EDIT] Points for removing graffiti (attacker +5, defender -5)
    }
}

Config.FurnitureLimits    = {
    normal = 50,  -- Default limit
    upgrade = 150 -- Upgrade Limit
}

--──────────────────────────────────────────────────────────────────────────────
-- Mission System Settings                                                     [EDIT]
-- [INFO] Configure mission system settings for organizations.
--──────────────────────────────────────────────────────────────────────────────
Config.MissionSystem      = {
    DailyMissionLimit = 5,              -- [EDIT] Daily mission limit per organization
    MissionResetTime = '00:00',         -- [EDIT] Mission reset time (HH:MM format)
    XPFormula = {
        BaseXPPerMission = 100,         -- [EDIT] Base XP per mission completion
        TerritoryWarMultiplier = 50,    -- [EDIT] Multiplier for territory war missions
        LevelUpXP = function(level)     -- [EDIT] XP required to level up formula
            return 1000 + (level * 500) -- Level 1->2: 1500 XP, Level 2->3: 2000 XP, etc.
        end
    }
}

--──────────────────────────────────────────────────────────────────────────────
-- Mission Rarity Colors                                                       [EDIT]
-- [INFO] Define rarity colors for missions and rewards.
--──────────────────────────────────────────────────────────────────────────────
Config.MissionRarity      = {
    common = { color = '#9CA3AF', name = 'Common' },
    rare = { color = '#3B82F6', name = 'Rare' },
    epic = { color = '#A855F7', name = 'Epic' },
    legendary = { color = '#F59E0B', name = 'Legendary' }
}

--──────────────────────────────────────────────────────────────────────────────
-- PvP System Settings                                                          [EDIT]
-- [INFO] Configure PvP battle system settings.
--──────────────────────────────────────────────────────────────────────────────
Config.PvpSystem          = {
    ScorePerPlayer = 1,                   -- [EDIT] Points per player in zone per interval (per second)
    DeathPenalty = 10,                    -- [EDIT] Points lost when player dies in zone
    NotificationTimes = { 600, 300, 60 }, -- [EDIT] Notification times in seconds (10, 5, 1 minutes)
    MaxConcurrentBattles = 1,             -- [EDIT] Maximum concurrent battles per organization
    ScoreUpdateInterval = 1000            -- [EDIT] Score update interval in milliseconds (1 second)
}
