-- Bloxburg & Universal Toolkit (Horizontal Mobile Dock)
-- Optimized for Delta Executor & Touch / Mouse input

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
local targetSpeed = 24 -- Recommended default to prevent server rubberbanding
local MAX_HEIGHT = 80
local ESP_RANGE = 5000
local ITEM_ESP_RANGE = 2500
local ESP_REFRESH = 0.15
local ITEM_SCAN_INTERVAL = 1.0

-- Safe UI Container
local function getSafeUiParent()
    if gethui then
        return gethui()
    end
    local success, coreGui = pcall(function() return game:GetService("CoreGui") end)
    if success and coreGui then
        return coreGui
    end
    return player:WaitForChild("PlayerGui")
end

local parentContainer = getSafeUiParent()

-- Cleanup prior script runs
local oldGui = parentContainer:FindFirstChild("BloxburgToolkitUI")
if oldGui then oldGui:Destroy() end

local oldPlayerEsp = parentContainer:FindFirstChild("BT_PlayerESP")
if oldPlayerEsp then oldPlayerEsp:Destroy() end

local oldItemEsp = parentContainer:FindFirstChild("BT_ItemESP")
if oldItemEsp then oldItemEsp:Destroy() end

-- Dedicated folders inside protected UI space
local playerEspFolder = Instance.new("Folder")
playerEspFolder.Name = "BT_PlayerESP"
playerEspFolder.Parent = parentContainer

local itemEspFolder = Instance.new("Folder")
itemEspFolder.Name = "BT_ItemESP"
itemEspFolder.Parent = parentContainer

-- ========== LEAK-FREE DRAG HELPER ==========
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
            if delta.Magnitude > 4 then
                moved = true
            end
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

-- ========== HORIZONTAL UI SETUP ==========
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BloxburgToolkitUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = parentContainer

-- Horizontal Dock (Width: 510, Height: 36)
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainDock"
mainFrame.Size = UDim2.new(0, 510, 0, 36)
mainFrame.Position = UDim2.new(0.5, -255, 0.04, 0) -- Centered near top of screen
mainFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
mainFrame.BackgroundTransparency = 0.15
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui

local frameCorner = Instance.new("UICorner")
frameCorner.CornerRadius = UDim.new(0, 8)
frameCorner.Parent = mainFrame

local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Horizontal
listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 5)
listLayout.Parent = mainFrame

local framePadding = Instance.new("UIPadding")
framePadding.PaddingLeft = UDim.new(0, 6)
framePadding.PaddingRight = UDim.new(0, 6)
framePadding.PaddingTop = UDim.new(0, 4)
framePadding.PaddingBottom = UDim.new(0, 4)
framePadding.Parent = mainFrame

-- Drag Grip Label
local grip = Instance.new("TextLabel")
grip.Name = "Grip"
grip.LayoutOrder = 1
grip.Size = UDim2.new(0, 40, 1, 0)
grip.BackgroundTransparency = 1
grip.Text = "≡ BT"
grip.TextColor3 = Color3.fromRGB(200, 200, 200)
grip.TextSize = 13
grip.Font = Enum.Font.GothamBold
grip.Parent = mainFrame

local function createDockButton(name, text, width, order)
    local btn = Instance.new("TextButton")
    btn.Name = name
    btn.LayoutOrder = order
    btn.Size = UDim2.new(0, width, 1, 0)
    btn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextSize = 11
    btn.Font = Enum.Font.GothamBold
    btn.Parent = mainFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = btn
    return btn
end

local jumpBtn = createDockButton("JumpBtn", "Jump: OFF", 68, 2)
local noclipBtn = createDockButton("NoclipBtn", "Noclip: OFF", 70, 3)
local espBtn = createDockButton("PlayerEspBtn", "P-ESP: OFF", 68, 4)
local itemEspBtn = createDockButton("ItemEspBtn", "I-ESP: OFF", 68, 5)
local speedBtn = createDockButton("SpeedBtn", "Spd: OFF", 62, 6)

-- Speed Input Box
local speedBox = Instance.new("TextBox")
speedBox.Name = "SpeedInput"
speedBox.LayoutOrder = 7
speedBox.Size = UDim2.new(0, 36, 1, 0)
speedBox.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
speedBox.Text = tostring(targetSpeed)
speedBox.TextColor3 = Color3.fromRGB(255, 255, 255)
speedBox.TextSize = 11
speedBox.Font = Enum.Font.GothamBold
speedBox.ClearTextOnFocus = false
speedBox.Parent = mainFrame

local speedBoxCorner = Instance.new("UICorner")
speedBoxCorner.CornerRadius = UDim.new(0, 6)
speedBoxCorner.Parent = speedBox

-- Minimize Button
local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Name = "MinBtn"
minimizeBtn.LayoutOrder = 8
minimizeBtn.Size = UDim2.new(0, 24, 1, 0)
minimizeBtn.BackgroundColor3 = Color3.fromRGB(230, 150, 20)
minimizeBtn.Text = "–"
minimizeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
minimizeBtn.TextSize = 14
minimizeBtn.Font = Enum.Font.GothamBold
minimizeBtn.Parent = mainFrame

local minCorner = Instance.new("UICorner")
minCorner.CornerRadius = UDim.new(0, 6)
minCorner.Parent = minimizeBtn

-- Minimized Floating Bubble
local restoreBtn = Instance.new("TextButton")
restoreBtn.Size = UDim2.new(0, 38, 0, 38)
restoreBtn.Position = UDim2.new(0.5, -19, 0.04, 0)
restoreBtn.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
restoreBtn.BackgroundTransparency = 0.2
restoreBtn.Text = "BT"
restoreBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
restoreBtn.TextSize = 13
restoreBtn.Font = Enum.Font.GothamBold
restoreBtn.Visible = false
restoreBtn.Parent = screenGui

local restoreCorner = Instance.new("UICorner")
restoreCorner.CornerRadius = UDim.new(0, 10)
restoreCorner.Parent = restoreBtn

-- Drag & Minimize Logic
makeDraggable(grip, mainFrame)
local restoreWasDragged = makeDraggable(restoreBtn, restoreBtn)

minimizeBtn.MouseButton1Click:Connect(function()
    minimized = true
    restoreBtn.Position = UDim2.new(mainFrame.Position.X.Scale, mainFrame.Position.X.Offset, mainFrame.Position.Y.Scale, mainFrame.Position.Y.Offset)
    mainFrame.Visible = false
    restoreBtn.Visible = true
end)

restoreBtn.MouseButton1Click:Connect(function()
    if restoreWasDragged() then return end
    minimized = false
    mainFrame.Position = UDim2.new(restoreBtn.Position.X.Scale, restoreBtn.Position.X.Offset, restoreBtn.Position.Y.Scale, restoreBtn.Position.Y.Offset)
    mainFrame.Visible = true
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

-- ========== TOGGLE FUNCTIONS ==========
local function setJumpEnabled(state)
    infJumpEnabled = state
    jumpBtn.BackgroundColor3 = infJumpEnabled and Color3.fromRGB(40, 180, 40) or Color3.fromRGB(200, 50, 50)
    jumpBtn.Text = infJumpEnabled and "Jump: ON" or "Jump: OFF"
end

local function setNoclipEnabled(state)
    noclipEnabled = state
    noclipBtn.BackgroundColor3 = noclipEnabled and Color3.fromRGB(40, 180, 40) or Color3.fromRGB(200, 50, 50)
    noclipBtn.Text = noclipEnabled and "Noclip: ON" or "Noclip: OFF"
    
    if not noclipEnabled and player.Character then
        for _, part in ipairs(player.Character:GetDescendants()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                part.CanCollide = true
            end
        end
    end
end

local function setPlayerESPEnabled(state)
    espEnabled = state
    espBtn.BackgroundColor3 = espEnabled and Color3.fromRGB(40, 180, 40) or Color3.fromRGB(200, 50, 50)
    espBtn.Text = espEnabled and "P-ESP: ON" or "P-ESP: OFF"
    if not espEnabled then
        playerEspFolder:ClearAllChildren()
    end
end

local function setItemESPEnabled(state)
    itemEspEnabled = state
    itemEspBtn.BackgroundColor3 = itemEspEnabled and Color3.fromRGB(40, 180, 40) or Color3.fromRGB(200, 50, 50)
    itemEspBtn.Text = itemEspEnabled and "I-ESP: ON" or "I-ESP: OFF"
    if not itemEspEnabled then
        itemEspFolder:ClearAllChildren()
    end
end

local function setSpeedEnabled(state)
    speedEnabled = state
    speedBtn.BackgroundColor3 = speedEnabled and Color3.fromRGB(40, 180, 40) or Color3.fromRGB(200, 50, 50)
    speedBtn.Text = speedEnabled and "Spd: ON" or "Spd: OFF"
end

jumpBtn.MouseButton1Click:Connect(function() setJumpEnabled(not infJumpEnabled) end)
noclipBtn.MouseButton1Click:Connect(function() setNoclipEnabled(not noclipEnabled) end)
espBtn.MouseButton1Click:Connect(function() setPlayerESPEnabled(not espEnabled) end)
itemEspBtn.MouseButton1Click:Connect(function() setItemESPEnabled(not itemEspEnabled) end)
speedBtn.MouseButton1Click:Connect(function() setSpeedEnabled(not speedEnabled) end)

-- PC Keybind Fallbacks
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.J then
        setJumpEnabled(not infJumpEnabled)
    elseif input.KeyCode == Enum.KeyCode.N then
        setNoclipEnabled(not noclipEnabled)
    elseif input.KeyCode == Enum.KeyCode.K then
        setPlayerESPEnabled(not espEnabled)
    elseif input.KeyCode == Enum.KeyCode.L then
        setItemESPEnabled(not itemEspEnabled)
    elseif input.KeyCode == Enum.KeyCode.B then
        setSpeedEnabled(not speedEnabled)
    end
end)

-- ========== NOCLIP ENGINE LOOP ==========
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

-- ========== PHYSICS-BASED VELOCITY SPEED LOOP ==========
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

-- ========== INFINITE JUMP WITH RAYCAST ==========
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

-- ========== PLAYER ESP ENGINE ==========
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

-- ========== ITEM ESP ENGINE ==========
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

    -- Periodic Workspace Scan
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

    -- Fast Per-Frame Updates
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
