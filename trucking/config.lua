Config = {}

Config.UseTarget = true

-- Starting Location
Config.Location = vector4(153.68, -3214.12, 5.91, 274.5)

-- Vehicle Settings
Config.VehicleSpawn = vector4(147.52, -3204.12, 5.91, 267.5)
Config.TrailerSpawn = vector4(141.52, -3204.12, 5.91, 267.5)

Config.VehicleTypes = {
    small = {
        vehicles = {"speedo", "burrito3", "surfer"},
        trailer = false,
        payment_multiplier = 1.0,
        deposit = 500
    },
    medium = {
        vehicles = {"mule4", "boxville4"},
        trailer = false,
        payment_multiplier = 1.5,
        deposit = 750
    },
    large = {
        vehicles = {"phantom3", "hauler2"},
        trailer = "trailers",
        payment_multiplier = 2.0,
        deposit = 1000
    }
}

-- Distance Settings
Config.MaxTrailerDistance = 10.0
Config.RequiredAttachDistance = 2.5

-- Route Settings
Config.Routes = {
    {
        name = "City Route",
        type = "small",
        locations = {
            {
                name = "Downtown Storage",
                coords = vector4(1013.12, -3110.32, 5.91, 0.0),
                payment = {
                    min = 750,
                    max = 1250
                }
            },
            {
                name = "Vinewood Storage",
                coords = vector4(858.45, -1952.12, 29.85, 85.5),
                payment = {
                    min = 1000,
                    max = 1500
                }
            }
        }
    },
    {
        name = "State Route",
        type = "medium",
        locations = {
            {
                name = "Sandy Shores Depot",
                coords = vector4(2664.89, 3526.78, 52.32, 175.5),
                payment = {
                    min = 1500,
                    max = 2000
                }
            },
            {
                name = "Grapeseed Storage",
                coords = vector4(2415.42, 4991.57, 46.23, 315.5),
                payment = {
                    min = 1750,
                    max = 2250
                }
            }
        }
    },
    {
        name = "Long Haul Route",
        type = "large",
        locations = {
            {
                name = "Paleto Storage",
                coords = vector4(-156.41, 6178.56, 31.21, 315.5),
                payment = {
                    min = 2500,
                    max = 3500
                }
            },
            {
                name = "Port Storage",
                coords = vector4(-802.87, -2746.52, 13.83, 235.5),
                payment = {
                    min = 3000,
                    max = 4000
                }
            }
        }
    }
}

-- Progression Settings
Config.ContinueDelay = 30
Config.BonusMultiplier = 1.1
Config.MaxConsecutiveBonus = 5

-- NPC Settings
Config.PedModel = "s_m_m_trucker_01"
Config.PedLocation = vector4(153.68, -3214.12, 5.91, 90)

-- Blip Settings
Config.Blip = {
    sprite = 477,
    color = 5,
    scale = 0.7,
    label = "Trucking Job",
    display = 4,
    shortRange = true
}

-- Leaderboard Settings
Config.Leaderboard = {
    enabled = true,
    displayLimit = 10,
    resetPeriod = "weekly",
    location = vector3(153.68, -3214.12, 5.91),
    categories = {
        "Most Deliveries",
        "Highest Earnings",
        "Longest Distance"
    }
}

-- Experience System
Config.Experience = {
    enabled = true,
    levels = {
        {
            level = 1,
            required_xp = 0,
            routes = {"City Route"}
        },
        {
            level = 5,
            required_xp = 1000,
            routes = {"City Route", "State Route"}
        },
        {
            level = 10,
            required_xp = 5000,
            routes = {"City Route", "State Route", "Long Haul Route"}
        }
    },
    xp_per_delivery = 100,
    bonus_xp_multiplier = 1.5
}

Config.Warehouse = {
    location = vector4(147.52, -3204.12, 5.91, 267.5),
    marker = {
        type = 1,
        size = vector3(3.0, 3.0, 1.0),
        color = {r = 255, g = 255, b = 255, a = 100},
        returnDistance = 5.0
    }
}

Config.Webhooks = {
    enabled = true,
    urls = {
        deposits = "YOUR WEBHOOK URL HERE",
        deliveries = "YOUR WEBHOOK URL HERE"
    },
    color = {
        deposit = 16776960, -- Yellow
        delivery = 65280,   -- Green
        refund = 16711680   -- Red
    }
}
