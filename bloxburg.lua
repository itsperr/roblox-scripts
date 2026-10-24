-- Bloxburg Targeted Food Spawner (Scan -> Select -> Plot Spawn)
-- Optimized for Delta Executor & Mobile Landscape UI

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- Visual container for spawned food
local visualFolder = Workspace:FindFirstChild("BT_VisualFoodStorage")
if not visualFolder then
    visualFolder = Instance.new("Folder")
    visualFolder.Name = "BT_VisualFoodStorage"
    visualFolder.Parent = Workspace
end

-- State
local scannedFoods = {}    -- { [foodName] = ModelInstance }
local selectedFoods = {}   -- { [foodName] = true }
local isScanning = false

-- Theme Palette
local THEME = {
    CardBg = Color3.fromRGB(24, 26, 32),
    CardStroke = Color3.fromRGB(45, 48, 58),
    HeaderTitle = Color3.fromRGB(245, 245, 245),
    SubText = Color3.fromRGB(130, 138, 153),
    PillInactiveBg = Color3.fromRGB(32, 35, 44),
    PillInactiveStroke = Color3.fromRGB(55, 60, 74),
    PillInactiveText = Color3.fromRGB(180, 185, 198),
    PillActiveBg = Color3.fromRGB(20, 50, 42),
    PillActiveStroke = Color3.fromRGB(45, 190, 130),
    PillActiveText = Color3.fromRGB(255, 255, 255),
    PrimaryActionBg = Color3.fromRGB(35, 80, 65),
    PrimaryActionStroke = Color3.fromRGB(50, 220, 150),
}

-- Safe UI Parent
local function getSafeUiParent()
    if gethui then return gethui() end
    local success, coreGui = pcall(function() return game:GetService("CoreGui") end)
    if success and coreGui then return coreGui end
    return player:WaitForChild("PlayerGui")
end

local parentContainer = getSafeUiParent()
local oldUi = parentContainer:FindFirstChild("BT_TargetFoodSpawnerUI")
if oldUi then oldUi:Destroy() end

-- ========== DRAG HELPER ==========
local function makeDraggable(handle, target)
    local dragging = false
    local dragInput, dragStart, startPos

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = target.Position
        end
    end)

    handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and input == dragInput then
            local delta = input.Position - dragStart
            target.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

-- ========== SCANNER ENGINE ==========
local function findFoodModel(foodName)
    local searchLocations = {
        ReplicatedStorage:FindFirstChild("GameObjects"),
        ReplicatedStorage:FindFirstChild("Items"),
        ReplicatedStorage:FindFirstChild("_streamingHolder"),
        ReplicatedStorage
    }

    for _, loc in ipairs(searchLocations) do
        if loc then
            local found = loc:FindFirstChild(foodName) or loc:FindFirstChild(foodName, true)
            if found and (found:IsA("Model") or found:IsA("BasePart")) then
                return found
            end
        end
    end
    return nil
end

local function scanGameFoods()
    local namesToScan = {}

    -- 1. Scan dynamically through game Food Module
    local foodModule = ReplicatedStorage:FindFirstChild("Items") and ReplicatedStorage.Items:FindFirstChild("Food")
    if foodModule and foodModule:IsA("ModuleScript") then
        pcall(function()
            local commonTypes = ReplicatedStorage:FindFirstChild("Modules") 
                and ReplicatedStorage.Modules:FindFirstChild("SharedTypes") 
                and ReplicatedStorage.Modules.SharedTypes:FindFirstChild("CommonTypes")
            if commonTypes then require(commonTypes) end
            local data = require(foodModule)(nil, {})
            for name, _ in pairs(data) do
                table.insert(namesToScan, name)
            end
        end)
    end

    -- 2. Fallback food dictionary if module cannot be required
    if #namesToScan == 0 then
        namesToScan = {
            "Pizza", "Hot Dogs", "Hamburgers", "Tacos", "Turkey", "Pancakes",
            "Spaghetti and Meatballs", "Spaghetti Bolognese", "Caesar Salad", "Garden Salad",
            "Cake", "Birthday Cake", "Plain Cheesecake", "Strawberry Swirl Cheesecake",
            "Bacon and Eggs", "Apple Pie", "Pumpkin Pie", "Pecan Pie", "Mixed Berry Pie",
            "Sushi Rolls", "Lobster", "Salmon", "Meatloaf", "BBQ Ribs", "Steak",
            "Chicken Nuggets", "Fish Sticks", "French Fries", "Mozzarella Sticks",
            "Boba Tea", "Matcha Boba Tea", "Pumpkin Spice Latte", "Vanilla Milkshake",
            "Chocolate Cupcakes", "Sprinkle Donuts", "Sugar Donuts", "Croissant",
            "Baguette", "Pan de Muerto", "Mooncakes", "Pumpkin Soup", "Chili Bowl"
        }
    end

    -- Filter items that actually have physical 3D models in game files
    scannedFoods = {}
    for _, foodName in ipairs(namesToScan) do
        local model = findFoodModel(foodName)
        if model then
            scannedFoods[foodName] = model
        end
    end

    return scannedFoods
end

-- ========== PLOT DETECTOR ==========
local function getMyPlot()
    local plotsFolder = Workspace:FindFirstChild("Plots")
    if not plotsFolder then return nil end

    for _, plot in ipairs(plotsFolder:GetChildren()) do
        local ownerVal = plot:FindFirstChild("Owner")
        if ownerVal and (ownerVal.Value == player or ownerVal.Value == player.Name) then
            return plot
        end
        if plot:GetAttribute("Owner") == player.Name or plot:GetAttribute("Owner") == player.UserId then
            return plot
        end
        local sign = plot:FindFirstChild("Sign", true) or plot:FindFirstChild("Mailbox", true)
        if sign then
            for _, desc in ipairs(sign:GetDescendants()) do
                if desc:IsA("TextLabel") and (string.find(desc.Text, player.Name) or string.find(desc.Text, player.DisplayName)) then
                    return plot
                end
            end
        end
    end
    return nil
end

-- ========== SPAWN ENGINE ==========
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function spawnSelectedFoodOnPlot()
    local activeSelection = {}
    for name, isSel in pairs(selectedFoods) do
        if isSel and scannedFoods[name] then
            table.insert(activeSelection, name)
        end
    end

    if #activeSelection == 0 then
        return false, "Select at least 1 food first!"
    end

    local randomFoodName = activeSelection[math.random(1, #activeSelection)]
    local rawModel = scannedFoods[randomFoodName]
    if not rawModel then return false, "Model unavailable" end

    -- Plot boundary target calculation
    local myPlot = getMyPlot()
    local targetPos = Vector3.zero

    if myPlot then
        local cf, size = myPlot:GetBoundingBox()
        local halfX = math.max((size.X / 2) - 10, 5)
        local halfZ = math.max((size.Z / 2) - 10, 5)
        local randX = math.random(-math.floor(halfX), math.floor(halfX))
        local randZ = math.random(-math.floor(halfZ), math.floor(halfZ))
        targetPos = cf.Position + Vector3.new(randX, 35, randZ)
    else
        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            targetPos = root.Position + Vector3.new(math.random(-20, 20), 20, math.random(-20, 20))
        else
            return false, "Character not found"
        end
    end

    -- Downward raycast for surface attachment
    if player.Character then
        rayParams.FilterDescendantsInstances = {player.Character, visualFolder}
    end
    local hit = Workspace:Raycast(targetPos, Vector3.new(0, -60, 0), rayParams)
    local finalPos = hit and hit.Position or (targetPos - Vector3.new(0, 25, 0))

    -- Clone and configure
    local clone = rawModel:Clone()
    clone.Name = "Visual_" .. randomFoodName

    for _, part in ipairs(clone:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Anchored = true
            part.CanCollide = false
        end
    end
    if clone:IsA("BasePart") then
        clone.Anchored = true
        clone.CanCollide = false
    end

    local rot = CFrame.Angles(0, math.rad(math.random(0, 360)), 0)
    if clone:IsA("Model") then
        local primary = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart")
        if primary then
            clone:SetPrimaryPartCFrame(CFrame.new(finalPos + Vector3.new(0, 0.2, 0)) * rot)
        end
    elseif clone:IsA("BasePart") then
        clone.CFrame = CFrame.new(finalPos + Vector3.new(0, 0.2, 0)) * rot
    end

    clone.Parent = visualFolder
    return true, randomFoodName
end

-- ========== UI SETUP (LANDSCAPE SPLIT CARD) ==========
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BT_TargetFoodSpawnerUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = parentContainer

-- Landscape Card (Width: 420, Height: 210)
local mainCard = Instance.new("Frame")
mainCard.Name = "MainCard"
mainCard.Size = UDim2.new(0, 420, 0, 210)
mainCard.Position = UDim2.new(0.5, -210, 0.5, -105)
mainCard.BackgroundColor3 = THEME.CardBg
mainCard.BorderSizePixel = 0
mainCard.Parent = screenGui

local cardCorner = Instance.new("UICorner")
cardCorner.CornerRadius = UDim.new(0, 16)
cardCorner.Parent = mainCard

local cardStroke = Instance.new("UIStroke")
cardStroke.Color = THEME.CardStroke
cardStroke.Thickness = 1.5
cardStroke.Parent = mainCard

-- Top Header Bar (Draggable handle)
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 38)
header.BackgroundTransparency = 1
header.Parent = mainCard

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -50, 1, 0)
titleLabel.Position = UDim2.new(0, 16, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Bloxburg Food Spawner"
titleLabel.TextColor3 = THEME.HeaderTitle
titleLabel.TextSize = 13
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 28, 0, 28)
closeBtn.Position = UDim2.new(1, -34, 0, 5)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "✕"
closeBtn.TextColor3 = THEME.HeaderTitle
closeBtn.TextSize = 15
closeBtn.Font = Enum.Font.GothamBold
closeBtn.Parent = header

makeDraggable(header, mainCard)

-- Floating Minimized Bubble
local restoreBtn = Instance.new("TextButton")
restoreBtn.Size = UDim2.new(0, 70, 0, 32)
restoreBtn.Position = UDim2.new(0.5, -35, 0.05, 0)
restoreBtn.BackgroundColor3 = THEME.CardBg
restoreBtn.Text = "🍔 Spawner"
restoreBtn.TextColor3 = THEME.HeaderTitle
restoreBtn.TextSize = 11
restoreBtn.Font = Enum.Font.GothamBold
restoreBtn.Visible = false
restoreBtn.Parent = screenGui

local resCorner = Instance.new("UICorner")
resCorner.CornerRadius = UDim.new(0, 16)
resCorner.Parent = restoreBtn

local resStroke = Instance.new("UIStroke")
resStroke.Color = THEME.PillActiveStroke
resStroke.Thickness = 1.2
resStroke.Parent = restoreBtn

makeDraggable(restoreBtn, restoreBtn)

closeBtn.MouseButton1Click:Connect(function()
    restoreBtn.Position = UDim2.new(mainCard.Position.X.Scale, mainCard.Position.X.Offset, mainCard.Position.Y.Scale, mainCard.Position.Y.Offset)
    mainCard.Visible = false
    restoreBtn.Visible = true
end)

restoreBtn.MouseButton1Click:Connect(function()
    mainCard.Position = UDim2.new(restoreBtn.Position.X.Scale, restoreBtn.Position.X.Offset, restoreBtn.Position.Y.Scale, restoreBtn.Position.Y.Offset)
    mainCard.Visible = true
    restoreBtn.Visible = false
end)

-- LEFT PANEL: Controls (Width: 150)
local leftPanel = Instance.new("Frame")
leftPanel.Size = UDim2.new(0, 145, 1, -44)
leftPanel.Position = UDim2.new(0, 12, 0, 38)
leftPanel.BackgroundTransparency = 1
leftPanel.Parent = mainCard

local function createPanelBtn(text, yPos, isPrimary)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 32)
    btn.Position = UDim2.new(0, 0, 0, yPos)
    btn.BackgroundColor3 = isPrimary and THEME.PrimaryActionBg or THEME.PillInactiveBg
    btn.Text = text
    btn.TextColor3 = isPrimary and THEME.PrimaryActionStroke or THEME.PillInactiveText
    btn.TextSize = 11
    btn.Font = Enum.Font.GothamBold
    btn.Parent = leftPanel

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = btn

    local stroke = Instance.new("UIStroke")
    stroke.Color = isPrimary and THEME.PrimaryActionStroke or THEME.PillInactiveStroke
    stroke.Thickness = 1.2
    stroke.Parent = btn

    return btn
end

local scanBtn = createPanelBtn("🔍 Scan Foods", 0, false)
local spawnBtn = createPanelBtn("✨ Spawn Selected", 38, true)
local clearBtn = createPanelBtn("🗑️ Clear Plot", 76, false)

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, 0, 0, 36)
statusLabel.Position = UDim2.new(0, 0, 0, 114)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Ready to scan\nSelected: 0"
statusLabel.TextColor3 = THEME.SubText
statusLabel.TextSize = 10
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextWrapped = true
statusLabel.Parent = leftPanel

-- RIGHT PANEL: Food Browser (Width: 245)
local rightPanel = Instance.new("Frame")
rightPanel.Size = UDim2.new(0, 245, 1, -46)
rightPanel.Position = UDim2.new(0, 163, 0, 38)
rightPanel.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
rightPanel.BorderSizePixel = 0
rightPanel.Parent = mainCard

local rightCorner = Instance.new("UICorner")
rightCorner.CornerRadius = UDim.new(0, 12)
rightCorner.Parent = rightPanel

local rightStroke = Instance.new("UIStroke")
rightStroke.Color = THEME.CardStroke
rightStroke.Thickness = 1
rightStroke.Parent = rightPanel

-- Scrolling Food List
local scrollList = Instance.new("ScrollingFrame")
scrollList.Size = UDim2.new(1, -8, 1, -8)
scrollList.Position = UDim2.new(0, 4, 0, 4)
scrollList.BackgroundTransparency = 1
scrollList.BorderSizePixel = 0
scrollList.ScrollBarThickness = 4
scrollList.ScrollBarImageColor3 = THEME.PillActiveStroke
scrollList.CanvasSize = UDim2.new(0, 0, 0, 0)
scrollList.Parent = rightPanel

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.new(0, 112, 0, 28)
gridLayout.CellPadding = UDim2.new(0, 6, 0, 6)
gridLayout.SortOrder = Enum.SortOrder.Name
gridLayout.Parent = scrollList

gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    scrollList.CanvasSize = UDim2.new(0, 0, 0, gridLayout.AbsoluteContentSize.Y + 10)
end)

local emptyNotice = Instance.new("TextLabel")
emptyNotice.Size = UDim2.new(1, 0, 1, 0)
emptyNotice.BackgroundTransparency = 1
emptyNotice.Text = "Click 'Scan Foods' to load available items"
emptyNotice.TextColor3 = THEME.SubText
emptyNotice.TextSize = 11
emptyNotice.Font = Enum.Font.Gotham
emptyNotice.TextWrapped = true
emptyNotice.Parent = scrollList

-- ========== UI INTERACTION ==========
local function updateSelectionCounter()
    local count = 0
    for _, isSel in pairs(selectedFoods) do
        if isSel then count = count + 1 end
    end
    statusLabel.Text = string.format("Scanned: %d\nSelected: %d", (function() local c=0 for _ in pairs(scannedFoods) do c=c+1 end return c end)(), count)
end

local function populateList()
    -- Clear current list items
    for _, child in ipairs(scrollList:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end

    local foodCount = 0
    for name, _ in pairs(scannedFoods) do
        foodCount = foodCount + 1

        local itemBtn = Instance.new("TextButton")
        itemBtn.Name = name
        itemBtn.Size = UDim2.new(0, 112, 0, 28)
        itemBtn.BackgroundColor3 = selectedFoods[name] and THEME.PillActiveBg or THEME.PillInactiveBg
        itemBtn.Text = selectedFoods[name] and (name .. " ✓") or name
        itemBtn.TextColor3 = selectedFoods[name] and THEME.PillActiveText or THEME.PillInactiveText
        itemBtn.TextSize = 10
        itemBtn.Font = Enum.Font.GothamBold
        itemBtn.TextTruncate = Enum.TextTruncate.AtEnd
        itemBtn.AutoButtonColor = false
        itemBtn.Parent = scrollList

        local itemCorner = Instance.new("UICorner")
        itemCorner.CornerRadius = UDim.new(0, 8)
        itemCorner.Parent = itemBtn

        local itemStroke = Instance.new("UIStroke")
        itemStroke.Name = "Stroke"
        itemStroke.Color = selectedFoods[name] and THEME.PillActiveStroke or THEME.PillInactiveStroke
        itemStroke.Thickness = 1.2
        itemStroke.Parent = itemBtn

        -- Item Toggle Handler
        itemBtn.MouseButton1Click:Connect(function()
            selectedFoods[name] = not selectedFoods[name]
            local isSel = selectedFoods[name]

            itemBtn.BackgroundColor3 = isSel and THEME.PillActiveBg or THEME.PillInactiveBg
            itemBtn.TextColor3 = isSel and THEME.PillActiveText or THEME.PillInactiveText
            itemStroke.Color = isSel and THEME.PillActiveStroke or THEME.PillInactiveStroke
            itemBtn.Text = isSel and (name .. " ✓") or name

            updateSelectionCounter()
        end)
    end

    emptyNotice.Visible = (foodCount == 0)
    updateSelectionCounter()
end

-- Button Triggers
scanBtn.MouseButton1Click:Connect(function()
    if isScanning then return end
    isScanning = true
    scanBtn.Text = "Scanning..."

    task.spawn(function()
        scanGameFoods()
        populateList()
        scanBtn.Text = "🔍 Rescan Foods"
        isScanning = false
    end)
end)

spawnBtn.MouseButton1Click:Connect(function()
    local success, result = spawnSelectedFoodOnPlot()
    if success then
        statusLabel.Text = "Spawned:\n" .. tostring(result)
    else
        statusLabel.Text = "Error:\n" .. tostring(result)
    end
end)

clearBtn.MouseButton1Click:Connect(function()
    visualFolder:ClearAllChildren()
    statusLabel.Text = "Cleared all\nvisual items"
end)
