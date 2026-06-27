--──────────────────────────────────────────────────────────────────────────────
-- Mission Configuration                                                       [EDIT]
--──────────────────────────────────────────────────────────────────────────────
-- [INFO] Default mission definitions. Each mission has a unique ID.
--        Missions are organized by their ID (e.g., 'spray-5', 'spray-10').
--        Each mission can have different rewards and requirements.
--──────────────────────────────────────────────────────────────────────────────

Config.Missions = {
    -- Spray Missions
    ['spray-5'] = {
        id = 'spray-5',
        label = 'Fess 5 graffitit',
        description = 'Fess 5 graffitit a szervezeted területén',
        type = 'graffiti',
        target_type = 'spray_count',
        target_value = 5,
        daily_limit = 1, -- [EDIT] How many times this mission can be completed per day
        rewards = {
            { type = 'money', value = 5000, moneyType = 'money' },
            { type = 'xp',    value = 100 }
        },
        rare = 'common',
        active = true
    },
    ['spray-10'] = {
        id = 'spray-10',
        label = 'Fess 10 graffitit',
        description = 'Fess 10 graffitit a szervezeted területén',
        type = 'graffiti',
        target_type = 'spray_count',
        target_value = 1,
        daily_limit = 1,
        rewards = {
            { type = 'money', value = 10000, moneyType = 'money' },
            { type = 'xp',    value = 200 }
        },
        rare = 'rare',
        active = true
    },
    ['spray-20'] = {
        id = 'spray-20',
        label = 'Fess 20 graffitit',
        description = 'Fess 20 graffitit a szervezeted területén',
        type = 'graffiti',
        target_type = 'spray_count',
        target_value = 20,
        daily_limit = 1,
        rewards = {
            { type = 'money', value = 20000,      moneyType = 'money' },
            { type = 'xp',    value = 500 },
            { type = 'item',  item = 'spray_can', value = 5 }
        },
        rare = 'epic',
        active = true
    },

    -- Territory War Missions
    ['territory-war-win'] = {
        id = 'territory-war-win',
        label = 'Területi háború megnyerése',
        description = 'Nyerj meg egy területi háborút és foglald el a területet',
        type = 'territory_war',
        target_type = 'war_win',
        target_value = 1,
        daily_limit = 1, -- [EDIT] Can complete once per day
        rewards = {
            { type = 'money', value = 50000, moneyType = 'money' },
            { type = 'xp',    value = 1000 }
        },
        rare = 'legendary',
        active = true
    },

    -- Drug Selling Missions
    ['drug-sell-10000'] = {
        id = 'drug-sell-10000',
        label = 'Adj el $10,000 értékű drogot',
        description = 'Adj el $10,000 értékű drogot a szervezet területén',
        type = 'drug_selling',
        target_type = 'drug_sale_amount',
        target_value = 10000,
        daily_limit = 2,
        rewards = {
            { type = 'money', value = 5000, moneyType = 'money' },
            { type = 'xp',    value = 150 }
        },
        rare = 'common',
        active = true
    },

    -- Graffiti Removal Missions
    ['remove-graffiti-5'] = {
        id = 'remove-graffiti-5',
        label = 'Távolíts el 5 ellenséges graffitit',
        description = 'Távolíts el 5 graffitit ellenséges szervezetektől',
        type = 'graffiti',
        target_type = 'remove_count',
        target_value = 5,
        daily_limit = 2,
        rewards = {
            { type = 'money', value = 7500, moneyType = 'money' },
            { type = 'xp',    value = 150 }
        },
        rare = 'rare',
        active = true
    },

    -- Vehicle Theft Missions
    ['vehicle-theft'] = {
        id = 'vehicle-theft',
        label = 'Jármű lopása',
        description = 'Lopj el egy járművet és vidd el a vevőhöz',
        type = 'vehicle_theft',
        target_type = 'vehicle_delivery',
        target_value = 1,
        daily_limit = 3, -- [EDIT] Can complete up to 3 per day
        rewards = {
            { type = 'money', value = 500, moneyType = 'money' },
            { type = 'xp',    value = 500 }
        },
        rare = 'common',
        active = true
    }
}

--──────────────────────────────────────────────────────────────────────────────
-- Money Laundering Configuration                                             [EDIT]
--──────────────────────────────────────────────────────────────────────────────
-- [INFO] Configure the money laundering mission system.
--        Players must have the upgrade and permission to access this feature.
--──────────────────────────────────────────────────────────────────────────────
Config.MoneyLaundering = {
    price = 500,                -- [EDIT] Initial price to start the laundering mission
    vehiclePrice = 1000,        -- [EDIT] Vehicle deposit (refunded if mission cancelled properly)
    limitPerDay = 1,            -- [EDIT] Maximum laundering missions per day per player
    minBlackMoney = 5000,       -- [EDIT] Minimum black money required to start
    xpReward = 150,             -- [EDIT] XP reward per delivery
    xpBonusComplete = 300,      -- [EDIT] Bonus XP for completing all deliveries
    sphereRadius = 15.0,        -- [EDIT] Zone radius for ped spawn/despawn
    progressBarDuration = 5000, -- [EDIT] Progress bar duration in milliseconds
    deliveryRadius = 3.0,       -- [EDIT] Radius to detect delivery point arrival
    launder = {
        min = 400,              -- [EDIT] Minimum clean money per delivery
        max = 800               -- [EDIT] Maximum clean money per delivery
    },
    ped = {
        coords = vec4(845.8065185546875, -902.8513793945312, 24.25149154663086, 266.29779052734375),
        model = 'a_m_m_beach_01',
        anim = {
            dict = 'amb@world_human_stand_guard@male@base',
            name = 'base'
        },
        vehicle = {
            spawnCoords = vec4(855.768310546875, -892.13330078125, 25.38961410522461, 269.5998840332031),
            model = 'boxville2'
        }
    },
    locations = {
        vec3(845.3008422851562, -2360.95166015625, 30.34267234802246),
        vec3(1562.7291259765625, -2141.549072265625, 77.62047576904297),
        vec3(-413.1394653320313, 294.4962463378906, 83.22920227050781)
    },
    checkpointBlip = { -- [EDIT] Blip settings for delivery checkpoints
        sprite = 1,
        color = 2,
        scale = 0.8
    },
    returnBlip = { -- [EDIT] Blip settings for return point
        sprite = 50,
        color = 3,
        scale = 1.0
    }
}

--──────────────────────────────────────────────────────────────────────────────
-- Vehicle Theft Configuration                                                [EDIT]
--──────────────────────────────────────────────────────────────────────────────
-- [INFO] Configure the vehicle theft mission system.
--        Players steal a vehicle and deliver it to a buyer location.
--──────────────────────────────────────────────────────────────────────────────
Config.VehicleTheft = {
    progressBarDuration = 3000, -- [EDIT] Progress bar duration in milliseconds
    deliveryRadius = 5.0,       -- [EDIT] Radius to detect delivery point arrival

    -- [EDIT] Vehicle models to randomly select from
    vehicles = {
        'sultan',
        'elegy',
        'comet2',
        'sentinel',
        'buffalo',
        'banshee',
        'infernus',
        'turismor'
    },

    -- [EDIT] Spawn locations for vehicles (random selection)
    spawnLocations = {
        vec4(215.78, -810.12, 30.73, 160.0),    -- Pillbox Hill
        vec4(-1045.29, -2721.65, 13.76, 240.0), -- Airport
        vec4(1208.12, -1402.27, 35.23, 0.0),    -- Mirror Park
        vec4(-337.66, -932.58, 31.08, 180.0),   -- Mission Row
        vec4(897.33, -1799.74, 31.14, 90.0)     -- La Mesa
    },

    -- [EDIT] Delivery locations for vehicles (random selection)
    deliveryLocations = {
        vec4(479.05, -1316.47, 29.21, 270.0),  -- Pillbox South
        vec4(-68.59, -1828.11, 26.94, 140.0),  -- Davis
        vec4(-1152.13, -1521.25, 4.36, 215.0), -- Del Perro Beach
        vec4(721.92, -1088.76, 22.17, 180.0)   -- La Mesa Docks
    },

    -- [EDIT] Blip settings for vehicle spawn point
    vehicleBlip = {
        sprite = 225, -- Car icon
        color = 1,    -- Red
        scale = 1.0
    },

    -- [EDIT] Blip settings for delivery point
    deliveryBlip = {
        sprite = 473, -- Briefcase icon
        color = 2,    -- Green
        scale = 1.0
    }
}

---@param activeOnly? boolean
---@return table[]
function Config.GetMissions(activeOnly)
    local missions = {}
    for id, mission in pairs(Config.Missions) do
        if not activeOnly or mission.active then
            missions[#missions + 1] = mission
        end
    end
    return missions
end

---@param missionId string
---@return table|nil
function Config.GetMission(missionId)
    return Config.Missions[missionId]
end

---@param type string
---@param activeOnly? boolean
---@return table[]
function Config.GetMissionsByType(type, activeOnly)
    local missions = {}
    for id, mission in pairs(Config.Missions) do
        if mission.type == type and (not activeOnly or mission.active) then
            missions[#missions + 1] = mission
        end
    end
    return missions
end
