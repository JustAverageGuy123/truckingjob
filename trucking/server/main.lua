local QBCore = exports['qb-core']:GetCoreObject()
local Leaderboard = {}
local function InitializeLeaderboard()
    local result = MySQL.Sync.fetchAll('SELECT * FROM trucking_leaderboard ORDER BY routes_completed DESC LIMIT ?', {
        Config.Leaderboard.displayLimit
    })
    
    if result[1] then
        Leaderboard = result
    end
end

MySQL.ready(function()
    MySQL.Sync.execute([[
        DROP TABLE IF EXISTS trucking_leaderboard;
    ]])

    MySQL.Sync.execute([[
        CREATE TABLE trucking_leaderboard (
            citizenid VARCHAR(50) PRIMARY KEY,
            name VARCHAR(255),
            routes_completed INT DEFAULT 0,
            total_earned INT DEFAULT 0,
            total_distance FLOAT DEFAULT 0,
            small_routes INT DEFAULT 0,
            medium_routes INT DEFAULT 0,
            large_routes INT DEFAULT 0,
            last_update TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        );
    ]])
    
    print('Trucking leaderboard table created successfully')
    InitializeLeaderboard()
end)

local function UpdatePlayerStats(citizenid, name, routes, earned, distance, routeType)
    local smallRoutes, mediumRoutes, largeRoutes = 0, 0, 0
    if routeType == "small" then
        smallRoutes = 1
    elseif routeType == "medium" then
        mediumRoutes = 1
    elseif routeType == "large" then
        largeRoutes = 1
    end

    local query = [[
        INSERT INTO trucking_leaderboard 
            (citizenid, name, routes_completed, total_earned, total_distance, small_routes, medium_routes, large_routes) 
        VALUES 
            (?, ?, ?, ?, ?, ?, ?, ?) 
        ON DUPLICATE KEY UPDATE 
            name = ?,
            routes_completed = routes_completed + ?,
            total_earned = total_earned + ?,
            total_distance = total_distance + ?,
            small_routes = small_routes + ?,
            medium_routes = medium_routes + ?,
            large_routes = large_routes + ?
    ]]

    local params = {
        citizenid, name, routes, earned, distance, smallRoutes, mediumRoutes, largeRoutes,
        name, routes, earned, distance, smallRoutes, mediumRoutes, largeRoutes
    }

    MySQL.Sync.execute(query, params)

    local result = MySQL.Sync.fetchAll('SELECT * FROM trucking_leaderboard ORDER BY routes_completed DESC LIMIT ?', {
        Config.Leaderboard.displayLimit
    })
    
    if result then
        Leaderboard = result
        TriggerClientEvent('qb-trucking:client:refreshLeaderboard', -1, Leaderboard)
    end
end

local function SendDiscordLog(webhookType, title, message, color)
    if not Config.Webhooks.enabled then return end
    
    local webhook = Config.Webhooks.urls[webhookType]
    if not webhook then return end
    
    local embed = {
        {
            ["title"] = title,
            ["description"] = message,
            ["type"] = "rich",
            ["color"] = color,
            ["footer"] = {
                ["text"] = "QB Trucking | " .. os.date("%Y-%m-%d %H:%M:%S")
            }
        }
    }

    PerformHttpRequest(webhook, function(err, text, headers) end, 'POST', json.encode({
        username = "Trucking Logs",
        embeds = embed
    }), { ['Content-Type'] = 'application/json' })
end

RegisterNetEvent('qb-trucking:server:takeDeposit', function(vehicleType)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local depositAmount = Config.VehicleTypes[vehicleType].deposit
    
    if not depositAmount then 
        TriggerClientEvent('QBCore:Notify', src, 'Invalid vehicle type!', 'error')
        return
    end
    
    if Player.Functions.RemoveMoney('cash', depositAmount, "trucking-deposit") then
        TriggerClientEvent('qb-trucking:client:depositPaid', src)
        TriggerClientEvent('QBCore:Notify', src, 'Deposit of £'..depositAmount..' paid', 'success')
        
        SendDiscordLog(
            'deposits',
            '💰 Deposit Paid',
            string.format(
                "**Player:** %s\n**Amount:** £%s\n**Vehicle Type:** %s\n**CitizenID:** %s",
                Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname,
                depositAmount,
                vehicleType,
                Player.PlayerData.citizenid
            ),
            Config.Webhooks.color.deposit
        )
    else
        TriggerClientEvent('QBCore:Notify', src, 'You need £'..depositAmount..' cash for the deposit!', 'error')
    end
end)

RegisterNetEvent('qb-trucking:server:returnDeposit', function(vehicleType)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local depositAmount = Config.VehicleTypes[vehicleType].deposit
    
    if depositAmount then
        Player.Functions.AddMoney('cash', depositAmount, "trucking-deposit-return")
        TriggerClientEvent('QBCore:Notify', src, 'Deposit of £'..depositAmount..' returned in cash', 'success')
        
        SendDiscordLog(
            'deposits',
            '💸 Deposit Returned',
            string.format(
                "**Player:** %s\n**Amount:** £%s\n**Vehicle Type:** %s\n**CitizenID:** %s",
                Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname,
                depositAmount,
                vehicleType,
                Player.PlayerData.citizenid
            ),
            Config.Webhooks.color.refund
        )
    end
end)

local function CalculateExperience(Player, routeType)
    if not Config.Experience.enabled then return end
    
    local currentXP = Player.PlayerData.metadata.truckingxp or 0
    local xpGain = Config.Experience.xp_per_delivery
    
    if routeType == "medium" then
        xpGain = xpGain * 1.5
    elseif routeType == "large" then
        xpGain = xpGain * Config.Experience.bonus_xp_multiplier
    end
    
    local newXP = currentXP + xpGain
    local currentLevel = 1
    
    for i, levelData in ipairs(Config.Experience.levels) do
        if newXP >= levelData.required_xp then
            currentLevel = levelData.level
        else
            break
        end
    end
    
    local oldLevel = Player.PlayerData.metadata.truckinglevel or 1
    
    Player.Functions.SetMetaData('truckingxp', newXP)
    Player.Functions.SetMetaData('truckinglevel', currentLevel)
    
    if currentLevel > oldLevel then
        TriggerClientEvent('QBCore:Notify', Player.PlayerData.source, 'Level Up! You are now level '..currentLevel..'!', 'success')
    end
    
    TriggerClientEvent('QBCore:Notify', Player.PlayerData.source, 'Earned '..xpGain..' trucking XP!', 'success')
    return currentLevel
end

RegisterNetEvent('qb-trucking:server:completeDelivery', function(payment, routeType, distance)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local amount = math.random(payment.min, payment.max)
    amount = math.floor(amount * Config.VehicleTypes[routeType].payment_multiplier)
    
    Player.Functions.AddMoney('cash', amount, "trucking-payment")
    TriggerClientEvent('QBCore:Notify', src, 'Delivery completed! You earned £'..amount..' in cash', 'success')
    
    local newLevel = CalculateExperience(Player, routeType)
    
    SendDiscordLog(
        'deliveries',
        '🚛 Delivery Completed',
        string.format(
            "**Player:** %s\n**Amount Earned:** £%s\n**Route Type:** %s\n**Distance:** %.2f km\n**New Level:** %s\n**CitizenID:** %s",
            Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname,
            amount,
            routeType,
            (distance or 0) / 1000,
            newLevel or 1,
            Player.PlayerData.citizenid
        ),
        Config.Webhooks.color.delivery
    )
    
    UpdatePlayerStats(
        Player.PlayerData.citizenid,
        Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname,
        1,
        amount,
        distance or 0,
        routeType
    )
end)

RegisterNetEvent('qb-trucking:server:requestLeaderboard', function()
    local src = source
    TriggerClientEvent('qb-trucking:client:refreshLeaderboard', src, Leaderboard)
end)

RegisterNetEvent('qb-trucking:server:refreshLeaderboard', function()
    MySQL.query('SELECT * FROM trucking_leaderboard ORDER BY routes_completed DESC LIMIT ?', 
        {Config.Leaderboard.displayLimit}, 
        function(result)
            if result then
                Leaderboard = result
                TriggerClientEvent('qb-trucking:client:refreshLeaderboard', -1, Leaderboard)
            end
        end
    )
end)

if Config.Leaderboard.resetPeriod ~= "never" then
    CreateThread(function()
        while true do
            local resetInterval = {
                daily = 86400,
                weekly = 604800,
                monthly = 2592000
            }
            
            Wait(resetInterval[Config.Leaderboard.resetPeriod] * 1000)
            MySQL.Sync.execute('TRUNCATE TABLE trucking_leaderboard')
            Leaderboard = {}
            TriggerClientEvent('qb-trucking:client:refreshLeaderboard', -1, Leaderboard)
        end
    end)
end 