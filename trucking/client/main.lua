local QBCore = exports['qb-core']:GetCoreObject()
local CurrentTruck = nil
local CurrentTrailer = nil
local CurrentDelivery = nil
local DeliveryBlip = nil
local hasDeliveryJob = false
local isTrailerAttached = false
local showTrailerDistance = false
local currentRoute = nil
local consecutiveDeliveries = 0
local isContinuing = false
local leaderboardData = {}
local startingLocation = nil -- To track distance

-- Add this helper function at the top of your client.lua
local function FormatNumber(number)
    local i, j, minus, int, fraction = tostring(number):find('([-]?)(%d+)([.]?%d*)')
    int = int:reverse():gsub("(%d%d%d)", "%1,")
    return minus .. int:reverse():gsub("^,", "") .. fraction
end

-- Function to get available routes based on player level
local function GetAvailableRoutes()
    local PlayerData = QBCore.Functions.GetPlayerData()
    local level = PlayerData.metadata.truckinglevel or 1
    local availableRoutes = {}
    
    for _, levelData in ipairs(Config.Experience.levels) do
        if level >= levelData.level then
            for _, routeName in ipairs(levelData.routes) do
                for _, route in ipairs(Config.Routes) do
                    if route.name == routeName then
                        table.insert(availableRoutes, route)
                    end
                end
            end
        end
    end
    
    return availableRoutes
end

-- Function to spawn the job NPC
local function SpawnNPC()
    local model = Config.PedModel
    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(0)
    end
    
    local ped = CreatePed(0, model, Config.PedLocation.x, Config.PedLocation.y, Config.PedLocation.z - 1, Config.PedLocation.w, false, false)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    
    if Config.UseTarget then
        exports['qb-target']:AddTargetEntity(ped, {
            options = {
                {
                    type = "client",
                    event = "qb-trucking:client:showRouteMenu",
                    icon = "fas fa-truck",
                    label = "Start Trucking Job",
                    canInteract = function()
                        return not hasDeliveryJob
                    end
                },
                {
                    type = "client",
                    event = "qb-trucking:client:cancelJob",
                    icon = "fas fa-ban",
                    label = "Cancel Job",
                    canInteract = function()
                        return hasDeliveryJob
                    end
                }
            },
            distance = 2.0
        })
    end
end

-- Function to spawn trailer
local function SpawnTrailer(trailerModel)
    if not trailerModel then return end
    
    QBCore.Functions.SpawnVehicle(trailerModel, function(trailer)
        SetEntityHeading(trailer, Config.TrailerSpawn.w)
        CurrentTrailer = trailer
        showTrailerDistance = true
    end, Config.TrailerSpawn, true)
end

-- Function to setup delivery (Move this up before SpawnTruck)
local function SetupDelivery()
    if not currentRoute then return end
    
    -- Get a random location from current route that's different from the last delivery
    local lastDeliveryCoords = CurrentDelivery and CurrentDelivery.coords
    local possibleLocations = {}
    
    for _, location in ipairs(currentRoute.locations) do
        if not lastDeliveryCoords or #(vector3(lastDeliveryCoords.x, lastDeliveryCoords.y, lastDeliveryCoords.z) - 
            vector3(location.coords.x, location.coords.y, location.coords.z)) > 100.0 then
            table.insert(possibleLocations, location)
        end
    end
    
    CurrentDelivery = possibleLocations[math.random(#possibleLocations)]
    startingLocation = GetEntityCoords(PlayerPedId())
    
    local bonus = math.min(
        math.pow(Config.BonusMultiplier, consecutiveDeliveries),
        math.pow(Config.BonusMultiplier, Config.MaxConsecutiveBonus)
    )
    CurrentDelivery.payment.min = math.floor(CurrentDelivery.payment.min * bonus)
    CurrentDelivery.payment.max = math.floor(CurrentDelivery.payment.max * bonus)
    
    if DeliveryBlip then
        RemoveBlip(DeliveryBlip)
    end
    
    DeliveryBlip = AddBlipForCoord(CurrentDelivery.coords.x, CurrentDelivery.coords.y, CurrentDelivery.coords.z)
    SetBlipSprite(DeliveryBlip, 477)
    SetBlipDisplay(DeliveryBlip, 4)
    SetBlipScale(DeliveryBlip, 0.8)
    SetBlipColour(DeliveryBlip, 5)
    SetBlipRoute(DeliveryBlip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(CurrentDelivery.name)
    EndTextCommandSetBlipName(DeliveryBlip)
    
    QBCore.Functions.Notify('New delivery: ' .. CurrentDelivery.name, 'primary')
    if consecutiveDeliveries > 0 then
        QBCore.Functions.Notify('Bonus multiplier: ' .. string.format("%.1fx", bonus), 'success')
    end
end

local function LoadModel(model)
    if not IsModelInCdimage(model) then return false end
    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(10)
    end
    return true
end

local function SpawnTruck(vehicleType)
    if not vehicleType then 
        QBCore.Functions.Notify('Invalid vehicle type!', 'error')
        return 
    end

    local vehicleConfig = Config.VehicleTypes[vehicleType]
    if not vehicleConfig then
        QBCore.Functions.Notify('Invalid vehicle configuration!', 'error')
        return
    end

    local vehicle = nil
    for _, model in ipairs(vehicleConfig.vehicles) do
        if LoadModel(model) then
            vehicle = model
            break
        end
    end

    if not vehicle then
        QBCore.Functions.Notify('No valid vehicle model found!', 'error')
        return
    end
    
    QBCore.Functions.SpawnVehicle(vehicle, function(veh)
        if not veh then
            QBCore.Functions.Notify('Failed to spawn vehicle!', 'error')
            return
        end

        SetEntityHeading(veh, Config.VehicleSpawn.w)
        CurrentTruck = veh
        TriggerEvent("vehiclekeys:client:SetOwner", QBCore.Functions.GetPlate(veh))
        SetVehicleEngineOn(veh, false, true, false)
        
        if vehicleConfig.trailer then
            if LoadModel(vehicleConfig.trailer) then
                SpawnTrailer(vehicleConfig.trailer)
            else
                QBCore.Functions.Notify('Failed to load trailer model!', 'error')
            end
        else
            SetupDelivery()
        end
    end, Config.VehicleSpawn, true)
end

local function ShowRouteMenu()
    local availableRoutes = GetAvailableRoutes()
    local menuItems = {}
    
    for _, route in ipairs(availableRoutes) do
        local vehicleType = Config.VehicleTypes[route.type]
        table.insert(menuItems, {
            header = route.name,
            txt = string.format("Deposit: £%d | Vehicle Type: %s", vehicleType.deposit, route.type),
            params = {
                event = "qb-trucking:client:startRoute",
                args = {
                    routeName = route.name,
                    vehicleType = route.type,
                    deposit = vehicleType.deposit
                }
            }
        })
    end
    
    exports['qb-menu']:openMenu(menuItems)
end

local function CalculateDeliveryDistance()
    if not startingLocation or not CurrentDelivery then return 0 end
    local currentPos = GetEntityCoords(PlayerPedId())
    return #(startingLocation - currentPos)
end

RegisterNetEvent('qb-trucking:client:showRouteMenu', function()
    ShowRouteMenu()
end)

RegisterNetEvent('qb-trucking:client:startRoute', function(data)
    if not data or not data.routeName then
        QBCore.Functions.Notify('Invalid route data!', 'error')
        return
    end

    for _, route in ipairs(Config.Routes) do
        if route.name == data.routeName then
            currentRoute = route
            -- Debug print
            print('Route type: ' .. route.type)
            TriggerServerEvent('qb-trucking:server:takeDeposit', route.type)
            break
        end
    end
end)

RegisterNetEvent('qb-trucking:client:depositPaid', function()
    if not currentRoute then
        QBCore.Functions.Notify('No route selected!', 'error')
        return
    end

    hasDeliveryJob = true
    SpawnTruck(currentRoute.type)
    if Config.VehicleTypes[currentRoute.type].trailer then
        QBCore.Functions.Notify('Reverse your truck to the trailer and attach it', 'primary')
    end
end)

local function OfferNextDelivery()
    isContinuing = true
    
    exports['qb-menu']:openMenu({
        {
            header = "Delivery Complete",
            isMenuHeader = true
        },
        {
            header = "Continue Deliveries",
            txt = "Take another delivery for bonus pay",
            params = {
                event = "qb-trucking:client:continueDeliveries"
            }
        },
        {
            header = "Return to Warehouse",
            txt = "End shift and return vehicle",
            params = {
                event = "qb-trucking:client:returnToWarehouse"
            }
        }
    })
end

RegisterNetEvent('qb-trucking:client:continueDeliveries', function()
    consecutiveDeliveries = consecutiveDeliveries + 1
    SetupDelivery()
    isContinuing = false
end)

RegisterNetEvent('qb-trucking:client:endRoute', function()
    QBCore.Functions.DeleteVehicle(CurrentTruck)
    if CurrentTrailer then
        QBCore.Functions.DeleteVehicle(CurrentTrailer)
    end
    RemoveBlip(DeliveryBlip)
    hasDeliveryJob = false
    CurrentDelivery = nil
    isTrailerAttached = false
    consecutiveDeliveries = 0
    isContinuing = false
    QBCore.Functions.Notify('Deliveries completed - Thanks for your work!', 'success')
end)

CreateThread(function()
    while true do
        Wait(1000)
        if CurrentDelivery and CurrentTruck then
            local truckPos = GetEntityCoords(CurrentTruck)
            local dist = #(vector3(CurrentDelivery.coords.x, CurrentDelivery.coords.y, CurrentDelivery.coords.z) - truckPos)
            
            if dist < 10.0 and (not Config.VehicleTypes[currentRoute.type].trailer or isTrailerAttached) then
                local deliveryDistance = CalculateDeliveryDistance()
                TriggerServerEvent('qb-trucking:server:completeDelivery', 
                    CurrentDelivery.payment, 
                    currentRoute.type,
                    deliveryDistance
                )
                RemoveBlip(DeliveryBlip)
                CurrentDelivery = nil
                
                Wait(Config.ContinueDelay * 1000)
                OfferNextDelivery()
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(0)
        if showTrailerDistance and CurrentTruck and CurrentTrailer then
            local distance = CheckTrailerAttachment()
            if distance <= Config.MaxTrailerDistance then
                local coords = GetEntityCoords(CurrentTrailer)
                DrawMarker(2, coords.x, coords.y, coords.z + 2.5, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0, 0.5, 0.5, 0.5, 255, 165, 0, 100, true, true, 2, nil, nil, false)
                
                SetTextScale(0.35, 0.35)
                SetTextFont(4)
                SetTextProportional(1)
                SetTextColour(255, 255, 255, 215)
                SetTextEntry("STRING")
                SetTextCentre(true)
                AddTextComponentString('Distance: ' .. math.floor(distance * 10) / 10 .. 'm\nReverse to attach trailer')
                DrawText(coords.x, coords.y, coords.z + 3.0)
                
                if distance <= Config.RequiredAttachDistance then
                    SetTextScale(0.35, 0.35)
                    SetTextFont(4)
                    SetTextColour(50, 255, 50, 215)
                    SetTextEntry("STRING")
                    SetTextCentre(true)
                    AddTextComponentString('Press [H] to attach trailer')
                    DrawText(coords.x, coords.y, coords.z + 3.3)
                end
            end
        end
    end
end)

local function DrawLeaderboardText(text, x, y)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry("STRING")
    SetTextCentre(true)
    AddTextComponentString(text)
    DrawText(x, y)
end

local function DisplayLeaderboard()
    local coords = Config.Leaderboard.location
    local onScreen, _x, _y = World3dToScreen2d(coords.x, coords.y, coords.z + 1.0)
    
    if onScreen then
        DrawLeaderboardText("🏆 Trucking Leaderboard 🏆", _x, _y - 0.1)
        
        if #leaderboardData == 0 then
            DrawLeaderboardText("No deliveries recorded yet!", _x, _y)
            return
        end
        
        for i, data in ipairs(leaderboardData) do
            if i <= Config.Leaderboard.displayLimit then
                local routeText = string.format("S:%d M:%d L:%d", 
                    data.small_routes or 0,
                    data.medium_routes or 0,
                    data.large_routes or 0
                )
                
                local text = string.format("%d. %s\nRoutes: %d | Earned: £%s\nDistance: %.1fkm | %s",
                    i,
                    data.name,
                    data.routes_completed,
                    FormatNumber(data.total_earned),
                    (data.total_distance or 0) / 1000,
                    routeText
                )
                DrawLeaderboardText(text, _x, _y + (i * 0.15))
            end
        end
    end
end

RegisterNetEvent('qb-trucking:client:refreshLeaderboard', function(data)
    leaderboardData = data
end)

local function CreateJobBlip()
    local blip = AddBlipForCoord(Config.Location.x, Config.Location.y, Config.Location.z)
    SetBlipSprite(blip, Config.Blip.sprite)
    SetBlipDisplay(blip, Config.Blip.display)
    SetBlipScale(blip, Config.Blip.scale)
    SetBlipColour(blip, Config.Blip.color)
    SetBlipAsShortRange(blip, Config.Blip.shortRange)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(Config.Blip.label)
    EndTextCommandSetBlipName(blip)
end

CreateThread(function()
    SpawnNPC()
    CreateJobBlip()
    TriggerServerEvent('qb-trucking:server:requestLeaderboard')
end)

CreateThread(function()
    while true do
        Wait(0)
        if Config.Leaderboard.enabled then
            local playerCoords = GetEntityCoords(PlayerPedId())
            local dist = #(playerCoords - Config.Leaderboard.location)
            
            if dist < 10.0 then
                DisplayLeaderboard()
            end
        end
    end
end)

local function CheckTrailerAttachment()
    if not CurrentTruck or not CurrentTrailer then return end
    
    local truckPos = GetEntityCoords(CurrentTruck)
    local trailerPos = GetEntityCoords(CurrentTrailer)
    local distance = #(truckPos - trailerPos)
    
    if IsEntityAttachedToEntity(CurrentTrailer, CurrentTruck) then
        if not isTrailerAttached then
            isTrailerAttached = true
            showTrailerDistance = false
            QBCore.Functions.Notify('Trailer successfully attached!', 'success')
            SetupDelivery()
        end
    end
    
    return distance
end

RegisterNetEvent('qb-trucking:client:startJob', function()
    TriggerServerEvent('qb-trucking:server:takeDeposit')
end)

RegisterNetEvent('qb-trucking:client:cancelJob', function()
    if CurrentTruck then
        QBCore.Functions.DeleteVehicle(CurrentTruck)
    end
    if CurrentTrailer then
        QBCore.Functions.DeleteVehicle(CurrentTrailer)
    end
    if DeliveryBlip then
        RemoveBlip(DeliveryBlip)
    end
    hasDeliveryJob = false
    isTrailerAttached = false
    showTrailerDistance = false
    CurrentDelivery = nil
    if currentRoute then
        TriggerServerEvent('qb-trucking:server:returnDeposit', currentRoute.type)
    end
    QBCore.Functions.Notify('Job cancelled - deposit returned', 'primary')
end)

RegisterNetEvent('qb-trucking:client:returnToWarehouse', function()
    local warehouseBlip = AddBlipForCoord(Config.Warehouse.location.x, Config.Warehouse.location.y, Config.Warehouse.location.z)
    SetBlipSprite(warehouseBlip, 38)
    SetBlipDisplay(warehouseBlip, 4)
    SetBlipScale(warehouseBlip, 0.8)
    SetBlipColour(warehouseBlip, 2)
    SetBlipRoute(warehouseBlip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Return Vehicle")
    EndTextCommandSetBlipName(warehouseBlip)
    
    QBCore.Functions.Notify('Return the vehicle to the warehouse to complete your shift', 'primary')

    CreateThread(function()
        local returning = true
        while returning do
            Wait(0)
            local playerCoords = GetEntityCoords(PlayerPedId())
            local warehouseCoords = vector3(Config.Warehouse.location.x, Config.Warehouse.location.y, Config.Warehouse.location.z)
            local distance = #(playerCoords - warehouseCoords)

            DrawMarker(
                Config.Warehouse.marker.type,
                warehouseCoords.x,
                warehouseCoords.y,
                warehouseCoords.z - 1.0,
                0.0, 0.0, 0.0,
                0.0, 0.0, 0.0,
                Config.Warehouse.marker.size.x,
                Config.Warehouse.marker.size.y,
                Config.Warehouse.marker.size.z,
                Config.Warehouse.marker.color.r,
                Config.Warehouse.marker.color.g,
                Config.Warehouse.marker.color.b,
                Config.Warehouse.marker.color.a,
                false, true, 2, nil, nil, false
            )
            
            if distance < Config.Warehouse.marker.returnDistance then
                if IsPedInAnyVehicle(PlayerPedId(), false) then
                    DrawText3D(warehouseCoords.x, warehouseCoords.y, warehouseCoords.z, '~g~E~w~ - Park Vehicle')
                    
                    if IsControlJustReleased(0, 38) then -- E key
                        if CurrentTruck and GetVehiclePedIsIn(PlayerPedId(), false) == CurrentTruck then
                            QBCore.Functions.DeleteVehicle(CurrentTruck)
                            if CurrentTrailer then
                                QBCore.Functions.DeleteVehicle(CurrentTrailer)
                            end
                            RemoveBlip(warehouseBlip)
                            returning = false
                            hasDeliveryJob = false
                            CurrentDelivery = nil
                            isTrailerAttached = false
                            consecutiveDeliveries = 0
                            isContinuing = false
                            QBCore.Functions.Notify('Vehicle returned - Thanks for your work!', 'success')
                            break
                        else
                            QBCore.Functions.Notify('This is not the delivery vehicle!', 'error')
                        end
                    end
                else
                    DrawText3D(warehouseCoords.x, warehouseCoords.y, warehouseCoords.z, 'Get in the delivery vehicle')
                end
            end
        end
    end)
end)

function DrawText3D(x, y, z, text)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry("STRING")
    SetTextCentre(true)
    AddTextComponentString(text)
    SetDrawOrigin(x, y, z, 0)
    DrawText(0.0, 0.0)
    local factor = (string.len(text)) / 370
    DrawRect(0.0, 0.0+0.0125, 0.017+ factor, 0.03, 0, 0, 0, 75)
    ClearDrawOrigin()
end 

CreateThread(function()
    while true do
        Wait(30000)
        TriggerServerEvent('qb-trucking:server:refreshLeaderboard')
    end
end) 