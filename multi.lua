-- Bloxburg & Universal Toolkit (Landscape Mobile Modal UI)
-- Optimized for Mobile Landscape & Delta Executor

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

-- State Flags
local infJumpEnabled = false
local noclipEnabled = false
local espEnabled = false
local itemEspEnabled = false
local speedEnabled = false
local minimized = false

-- Settings
local DEFAULT_SPEED = 16
local targetSpeed = 24
local MAX_HEIGHT = 80
local ESP_RANGE = 5000
local ITEM_ESP_RANGE = 2500
local ESP_REFRESH = 0.15
local ITEM_SCAN_INTERVAL = 1.0

-- Theme Palette (Inspired by Modern Card UI)
local THEME = {
    CardBg = Color3.fromRGB(24, 26, 32),
    CardStroke = Color3.fromRGB(45, 48, 58),
    HeaderTitle = Color3.fromRGB(245, 245, 245),
    SectionTitle = Color3.fromRGB(130, 138, 153),
    PillInactiveBg = Color3.fromRGB(32, 35, 44),
    PillInactiveStroke = Color3.fromRGB(55, 60, 74),
    PillInactiveText = Color3.fromRGB(180, 185, 198),
    PillActiveTealBg = Color3.fromRGB(20, 45, 40),
    PillActiveTealStroke = Color3.fromRGB(50, 205, 140),
    PillActiveTealText = Color3.fromRGB(255, 255, 255),
    PillActivePurpleBg = Color3.fromRGB(110, 90, 205),
    PillActivePurpleStroke = Color3.fromRGB(150, 130, 245),
    PillActivePurpleText = Color3.fromRGB(255, 255, 255),
}

-- Safe UI Container
local function getSafeUiParent()
    if gethui then return gethui() end
    local success, coreGui = pcall(function() return game:GetService("CoreGui") end)
    if success and coreGui then return coreGui end
    return player:WaitForChild("PlayerGui")
end

local parentContainer = getSafeUiParent()

-- Clean prior instances
local oldGui = parentContainer:FindFirstChild("BT_LandscapeUI")
if oldGui then oldGui:Destroy() end
local oldPEsp = parentContainer:FindFirstChild("BT_PEspFolder")
if oldPEsp then oldPEsp:Destroy() end
local oldIEsp = parentContainer:FindFirstChild("BT_IEspFolder")
if oldIEsp then oldIEsp:Destroy() end

local playerEspFolder = Instance.new("Folder")
playerEspFolder.Name = "BT_PEspFolder"
playerEspFolder.Parent = parentContainer

local itemEspFolder = Instance.new("Folder")
itemEspFolder.Name = "BT_IEspFolder"
itemEspFolder.Parent = parentContainer

-- ========== DRAG HELPER ==========
local function makeDraggable(handle, target)
    local dragging = false
    local dragInput, dragStart, startPos
    local moved = false

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            moved = false
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
            if delta.Magnitude > 4 then moved = true end
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

    return function() return moved end
end

-- ========== UI CONSTRUCTION ==========
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BT_LandscapeUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = parentContainer

-- Main Landscape Card (360x210)
local mainCard = Instance.new("Frame")
mainCard.Name = "MainCard"
mainCard.Size = UDim2.new(0, 360, 0, 210)
mainCard.Position = UDim2.new(0.5, -180, 0.5, -105)
mainCard.BackgroundColor3 = THEME.CardBg
mainCard.BorderSizePixel = 0
mainCard.Parent = screenGui

local cardCorner = Instance.new("UICorner")
cardCorner.CornerRadius = UDim.new(0, 18)
cardCorner.Parent = mainCard

local cardStroke = Instance.new("UIStroke")
cardStroke.Color = THEME.CardStroke
cardStroke.Thickness = 1.5
cardStroke.Parent = mainCard

-- Top Header Bar
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 42)
header.BackgroundTransparency = 1
header.Parent = mainCard

-- Close / Minimize Button (✕)
local closeBtn = Instance.new("TextButton")
closeBtn.Name = "CloseBtn"
closeBtn.Size = UDim2.new(0, 32, 0, 32)
closeBtn.Position = UDim2.new(0, 10, 0, 5)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "✕"
closeBtn.TextColor3 = THEME.HeaderTitle
closeBtn.TextSize = 16
closeBtn.Font = Enum.Font.GothamBold
closeBtn.Parent = header

-- Title Label
local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.Size = UDim2.new(1, -90, 1, 0)
titleLabel.Position = UDim2.new(0, 46, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Bloxburg Toolkit"
titleLabel.TextColor3 = THEME.HeaderTitle
titleLabel.TextSize = 15
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = header

-- Reset All Button (↻)
local resetBtn = Instance.new("TextButton")
resetBtn.Name = "ResetBtn"
resetBtn.Size = UDim2.new(0, 32, 0, 32)
resetBtn.Position = UDim2.new(1, -40, 0, 5)
resetBtn.BackgroundTransparency = 1
resetBtn.Text = "↻"
resetBtn.TextColor3 = THEME.SectionTitle
resetBtn.TextSize = 18
resetBtn.Font = Enum.Font.GothamBold
resetBtn.Parent = header

-- Helper: Create Section Title
local function createSectionTitle(text, yPos)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -30, 0, 16)
    label.Position = UDim2.new(0, 16, 0, yPos)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = THEME.SectionTitle
    label.TextSize = 11
    label.Font = Enum.Font.GothamBold
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = mainCard
    return label
end

-- Helper: Create Pill Button
local function createPillButton(name, defaultText, xPos, yPos, width, height)
    local btn = Instance.new("TextButton")
    btn.Name = name
    btn.Size = UDim2.new(0, width, 0, height or 32)
    btn.Position = UDim2.new(0, xPos, 0, yPos)
    btn.BackgroundColor3 = THEME.PillInactiveBg
    btn.Text = defaultText
    btn.TextColor3 = THEME.PillInactiveText
    btn.TextSize = 11
    btn.Font = Enum.Font.GothamBold
    btn.AutoButtonColor = false
    btn.Parent = mainCard

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 16)
    corner.Parent = btn

    local stroke = Instance.new("UIStroke")
    stroke.Name = "Stroke"
    stroke.Color = THEME.PillInactiveStroke
    stroke.Thickness = 1.2
    stroke.Parent = btn

    return btn
end

-- Section 1: Movement
createSectionTitle("Movement", 46)
local jumpBtn = createPillButton("JumpBtn", "Inf Jump", 16, 66, 96)
local noclipBtn = createPillButton("NoclipBtn", "Noclip", 118, 66, 88)
local speedBtn = createPillButton("SpeedBtn", "Speed", 212, 66, 76)

-- Speed Input Pill Box
local speedBox = Instance.new("TextBox")
speedBox.Name = "SpeedInput"
speedBox.Size = UDim2.new(0, 48, 0, 32)
speedBox.Position = UDim2.new(0, 294, 0, 66)
speedBox.BackgroundColor3 = THEME.PillInactiveBg
speedBox.Text = tostring(targetSpeed)
speedBox.TextColor3 = THEME.HeaderTitle
speedBox.TextSize = 12
speedBox.Font = Enum.Font.GothamBold
speedBox.ClearTextOnFocus = false
speedBox.Parent = mainCard

local speedBoxCorner = Instance.new("UICorner")
speedBoxCorner.CornerRadius = UDim.new(0, 16)
speedBoxCorner.Parent = speedBox

local speedBoxStroke = Instance.new("UIStroke")
speedBoxStroke.Color = THEME.PillInactiveStroke
speedBoxStroke.Thickness = 1.2
speedBoxStroke.Parent = speedBox

-- Section 2: Visuals & ESP
createSectionTitle("Visuals & Detection", 112)
local espBtn = createPillButton("PlayerEspBtn", "Player ESP", 16, 132, 110)
local itemEspBtn = createPillButton("ItemEspBtn", "Item ESP", 132, 132, 110)

-- Floating Minimized Pill
local restoreBtn = Instance.new("TextButton")
restoreBtn.Size = UDim2.new(0, 68, 0, 32)
restoreBtn.Position = UDim2.new(0.5, -34, 0.05, 0)
restoreBtn.BackgroundColor3 = THEME.CardBg
restoreBtn.Text = "⚡ Toolkit"
restoreBtn.TextColor3 = THEME.HeaderTitle
restoreBtn.TextSize = 11
restoreBtn.Font = Enum.Font.GothamBold
restoreBtn.Visible = false
restoreBtn.Parent = screenGui

local resCorner = Instance.new("UICorner")
resCorner.CornerRadius = UDim.new(0, 16)
resCorner.Parent = restoreBtn

local resStroke = Instance.new("UIStroke")
resStroke.Color = THEME.PillActiveTealStroke
resStroke.Thickness = 1.2
resStroke.Parent = restoreBtn

-- Drag & Minimize Connections
makeDraggable(header, mainCard)
local restoreWasDragged = makeDraggable(restoreBtn, restoreBtn)

closeBtn.MouseButton1Click:Connect(function()
    minimized = true
    restoreBtn.Position = UDim2.new(mainCard.Position.X.Scale, mainCard.Position.X.Offset, mainCard.Position.Y.Scale, mainCard.Position.Y.Offset)
    mainCard.Visible = false
    restoreBtn.Visible = true
end)

restoreBtn.MouseButton1Click:Connect(function()
    if restoreWasDragged() then return end
    minimized = false
    mainCard.Position = UDim2.new(restoreBtn.Position.X.Scale, restoreBtn.Position.X.Offset, restoreBtn.Position.Y.Scale, restoreBtn.Position.Y.Offset)
    mainCard.Visible = true
    restoreBtn.Visible = false
end)

speedBox.FocusLost:Connect(function()
    local val = tonumber(speedBox.Text)
    if val and val > 0 then
        targetSpeed = math.floor(val)
    else
        targetSpeed = DEFAULT_SPEED
    end
    speedBox.Text = tostring(targetSpeed)
end)

-- ========== PILL STYLE HANDLERS ==========
local function updatePillVisual(btn, active, activeText, inactiveText, usePurple)
    local stroke = btn:FindFirstChild("Stroke")
    if active then
        btn.BackgroundColor3 = usePurple and THEME.PillActivePurpleBg or THEME.PillActiveTealBg
        btn.TextColor3 = usePurple and THEME.PillActivePurpleText or THEME.PillActiveTealText
        if stroke then
            stroke.Color = usePurple and THEME.PillActivePurpleStroke or THEME.PillActiveTealStroke
        end
        btn.Text = activeText .. " ✓"
    else
        btn.BackgroundColor3 = THEME.PillInactiveBg
        btn.TextColor3 = THEME.PillInactiveText
        if stroke then
            stroke.Color = THEME.PillInactiveStroke
        end
        btn.Text = inactiveText
    end
end

local function setJumpEnabled(state)
    infJumpEnabled = state
    updatePillVisual(jumpBtn, infJumpEnabled, "Inf Jump", "Inf Jump", false)
end

local function setNoclipEnabled(state)
    noclipEnabled = state
    updatePillVisual(noclipBtn, noclipEnabled, "Noclip", "Noclip", false)

    if not noclipEnabled and player.Character then
        for _, part in ipairs(player.Character:GetDescendants()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                part.CanCollide = true
            end
        end
    end
end

local function setSpeedEnabled(state)
    speedEnabled = state
    updatePillVisual(speedBtn, speedEnabled, "Speed", "Speed", true) -- Uses purple accent from the image
end

local function setPlayerESPEnabled(state)
    espEnabled = state
    updatePillVisual(espBtn, espEnabled, "Player ESP", "Player ESP", false)
    if not espEnabled then
        playerEspFolder:ClearAllChildren()
    end
end

local function setItemESPEnabled(state)
    itemEspEnabled = state
    updatePillVisual(itemEspBtn, itemEspEnabled, "Item ESP", "Item ESP", false)
    if not itemEspEnabled then
        itemEspFolder:ClearAllChildren()
    end
end

-- Button Clicks
jumpBtn.MouseButton1Click:Connect(function() setJumpEnabled(not infJumpEnabled) end)
noclipBtn.MouseButton1Click:Connect(function() setNoclipEnabled(not noclipEnabled) end)
speedBtn.MouseButton1Click:Connect(function() setSpeedEnabled(not speedEnabled) end)
espBtn.MouseButton1Click:Connect(function() setPlayerESPEnabled(not espEnabled) end)
itemEspBtn.MouseButton1Click:Connect(function() setItemESPEnabled(not itemEspEnabled) end)

-- Reset All (↻)
resetBtn.MouseButton1Click:Connect(function()
    setJumpEnabled(false)
    setNoclipEnabled(false)
    setSpeedEnabled(false)
    setPlayerESPEnabled(false)
    setItemESPEnabled(false)
end)

-- Keybind Fallbacks (PC)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.J then setJumpEnabled(not infJumpEnabled)
    elseif input.KeyCode == Enum.KeyCode.N then setNoclipEnabled(not noclipEnabled)
    elseif input.KeyCode == Enum.KeyCode.B then setSpeedEnabled(not speedEnabled)
    elseif input.KeyCode == Enum.KeyCode.K then setPlayerESPEnabled(not espEnabled)
    elseif input.KeyCode == Enum.KeyCode.L then setItemESPEnabled(not itemEspEnabled)
    end
end)

-- ========== ENGINE LOOPS ==========

-- Noclip loop
RunService.Stepped:Connect(function()
    if not noclipEnabled then return end
    local character = player.Character
    if not character then return end

    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") and part.CanCollide then
            part.CanCollide = false
        end
    end
end)

-- Physics-based Velocity Speed loop
RunService.Heartbeat:Connect(function()
    if not speedEnabled then return end
    local character = player.Character
    if not character then return end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")

    if humanoid and rootPart and humanoid.Health > 0 then
        if humanoid.MoveDirection.Magnitude > 0 then
            local moveDir = humanoid.MoveDirection.Unit
            rootPart.AssemblyLinearVelocity = Vector3.new(
                moveDir.X * targetSpeed,
                rootPart.AssemblyLinearVelocity.Y,
                moveDir.Z * targetSpeed
            )
        end
    end
end)

-- Infinite Jump with Ground-Proximity Raycast
local jumpRayParams = RaycastParams.new()
jumpRayParams.FilterType = Enum.RaycastFilterType.Exclude
jumpRayParams.IgnoreWater = true

UserInputService.JumpRequest:Connect(function()
    if not infJumpEnabled then return end
    local character = player.Character
    if not character then return end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")

    if humanoid and rootPart then
        jumpRayParams.FilterDescendantsInstances = {character}
        local ray = Workspace:Raycast(rootPart.Position, Vector3.new(0, -MAX_HEIGHT, 0), jumpRayParams)
        if ray then
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end)

-- ========== ESP BILLBOARD HELPERS ==========
local function getDistColor(dist)
    if dist < 100 then return Color3.fromRGB(90, 255, 90) end
    if dist < 400 then return Color3.fromRGB(255, 220, 90) end
    return Color3.fromRGB(255, 90, 90)
end

local function createPlayerBillboard(targetPlayer, head)
    local billboard = Instance.new("BillboardGui")
    billboard.Name = targetPlayer.Name .. "_PESP"
    billboard.Adornee = head
    billboard.AlwaysOnTop = true
    billboard.StudsOffset = Vector3.new(0, 2.5, 0)
    billboard.Size = UDim2.new(0, 150, 0, 32)
    billboard.MaxDistance = ESP_RANGE
    billboard.Parent = playerEspFolder

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.Size = UDim2.new(1, 0, 0, 16)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = targetPlayer.DisplayName ~= targetPlayer.Name 
        and (targetPlayer.DisplayName .. " (@" .. targetPlayer.Name .. ")")
        or targetPlayer.Name
    nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    nameLabel.TextStrokeTransparency = 0.4
    nameLabel.TextSize = 12
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.Parent = billboard

    local distLabel = Instance.new("TextLabel")
    distLabel.Name = "DistLabel"
    distLabel.Position = UDim2.new(0, 0, 0, 16)
    distLabel.Size = UDim2.new(1, 0, 0, 14)
    distLabel.BackgroundTransparency = 1
    distLabel.Text = "-- studs"
    distLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    distLabel.TextStrokeTransparency = 0.4
    distLabel.TextSize = 10
    distLabel.Font = Enum.Font.Gotham
    distLabel.Parent = billboard

    return billboard
end

local lastPlayerUpdate = 0
RunService.Heartbeat:Connect(function()
    if not espEnabled then return end

    local now = os.clock()
    if now - lastPlayerUpdate < ESP_REFRESH then return end
    lastPlayerUpdate = now

    local myChar = player.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end

    for _, targetPlayer in ipairs(Players:GetPlayers()) do
        if targetPlayer ~= player then
            local theirChar = targetPlayer.Character
            local theirHead = theirChar and theirChar:FindFirstChild("Head")
            local theirRoot = theirChar and theirChar:FindFirstChild("HumanoidRootPart")
            local existingTag = playerEspFolder:FindFirstChild(targetPlayer.Name .. "_PESP")

            if theirHead and theirRoot then
                local billboard = existingTag or createPlayerBillboard(targetPlayer, theirHead)
                billboard.Adornee = theirHead

                local dist = (theirRoot.Position - myRoot.Position).Magnitude
                local distLabel = billboard:FindFirstChild("DistLabel")
                if distLabel then
                    distLabel.Text = string.format("%d studs", math.floor(dist))
                    distLabel.TextColor3 = getDistColor(dist)
                end
            elseif existingTag then
                existingTag:Destroy()
            end
        end
    end
end)

Players.PlayerRemoving:Connect(function(leavingPlayer)
    local tag = playerEspFolder:FindFirstChild(leavingPlayer.Name .. "_PESP")
    if tag then tag:Destroy() end
end)

-- Item ESP Scanner
local function getTargetPart(instance)
    if instance:IsA("BasePart") then
        return instance
    elseif instance:IsA("Model") then
        return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
    elseif instance:IsA("ProximityPrompt") or instance:IsA("ClickDetector") then
        local p = instance.Parent
        if p:IsA("BasePart") then return p end
        if p:IsA("Model") then return p.PrimaryPart or p:FindFirstChildWhichIsA("BasePart") end
    end
    return nil
end

local function getItemDisplayName(obj, targetPart)
    if obj:IsA("ProximityPrompt") then
        local text = ""
        if obj.ObjectText ~= "" then text = obj.ObjectText end
        if obj.ActionText ~= "" then
            text = text ~= "" and (text .. " [" .. obj.ActionText .. "]") or obj.ActionText
        end
        if text ~= "" then return text end
    end
    if obj:IsA("Tool") then
        return obj.Name
    end
    local model = targetPart:FindFirstAncestorOfClass("Model")
    if model and model ~= Workspace and not Players:GetPlayerFromCharacter(model) then
        return model.Name
    end
    return targetPart.Name
end

local function createItemBillboard(id, targetPart, displayName)
    local billboard = Instance.new("BillboardGui")
    billboard.Name = id
    billboard.Adornee = targetPart
    billboard.AlwaysOnTop = true
    billboard.StudsOffset = Vector3.new(0, 1.5, 0)
    billboard.Size = UDim2.new(0, 140, 0, 28)
    billboard.MaxDistance = ITEM_ESP_RANGE
    billboard.Parent = itemEspFolder

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.Size = UDim2.new(1, 0, 0, 14)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = displayName
    nameLabel.TextColor3 = Color3.fromRGB(80, 220, 255)
    nameLabel.TextStrokeTransparency = 0.3
    nameLabel.TextSize = 11
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.Parent = billboard

    local distLabel = Instance.new("TextLabel")
    distLabel.Name = "DistLabel"
    distLabel.Position = UDim2.new(0, 0, 0, 14)
    distLabel.Size = UDim2.new(1, 0, 0, 12)
    distLabel.BackgroundTransparency = 1
    distLabel.Text = "-- studs"
    distLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
    distLabel.TextStrokeTransparency = 0.4
    distLabel.TextSize = 9
    distLabel.Font = Enum.Font.Gotham
    distLabel.Parent = billboard

    return billboard
end

local trackedItems = {}
local lastItemScan = 0

RunService.Heartbeat:Connect(function()
    if not itemEspEnabled then return end

    local myChar = player.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end

    local now = os.clock()

    if now - lastItemScan >= ITEM_SCAN_INTERVAL then
        lastItemScan = now
        local newTracked = {}

        for _, desc in ipairs(Workspace:GetDescendants()) do
            local isCharacterPart = false
            for _, p in ipairs(Players:GetPlayers()) do
                if p.Character and desc:IsDescendantOf(p.Character) then
                    isCharacterPart = true
                    break
                end
            end

            if not isCharacterPart then
                local isValid = false
                local targetPart = nil
                local displayName = ""

                if desc:IsA("ProximityPrompt") and desc.Enabled then
                    targetPart = getTargetPart(desc)
                    if targetPart then
                        isValid = true
                        displayName = getItemDisplayName(desc, targetPart)
                    end
                elseif desc:IsA("ClickDetector") then
                    targetPart = getTargetPart(desc)
                    if targetPart then
                        isValid = true
                        displayName = getItemDisplayName(desc, targetPart)
                    end
                elseif desc:IsA("Tool") and desc.Parent == Workspace then
                    targetPart = desc:FindFirstChild("Handle") or desc:FindFirstChildWhichIsA("BasePart")
                    if targetPart then
                        isValid = true
                        displayName = desc.Name
                    end
                end

                if isValid and targetPart then
                    local id = "ITEM_" .. targetPart:GetDebugId()
                    newTracked[id] = {
                        part = targetPart,
                        name = displayName
                    }
                end
            end
        end

        for _, gui in ipairs(itemEspFolder:GetChildren()) do
            if not newTracked[gui.Name] then
                gui:Destroy()
            end
        end

        trackedItems = newTracked
    end

    for id, data in pairs(trackedItems) do
        if data.part and data.part.Parent then
            local billboard = itemEspFolder:FindFirstChild(id) or createItemBillboard(id, data.part, data.name)
            billboard.Adornee = data.part

            local dist = (data.part.Position - myRoot.Position).Magnitude
            local distLabel = billboard:FindFirstChild("DistLabel")
            if distLabel then
                distLabel.Text = string.format("%d studs", math.floor(dist))
            end
        else
            local oldTag = itemEspFolder:FindFirstChild(id)
            if oldTag then oldTag:Destroy() end
            trackedItems[id] = nil
        end
    end
end)
