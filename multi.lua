-- Bloxburg Toolkit (Infinite Jump + Noclip + Player ESP + Safe Speed)
-- Optimized for Delta Executor & Mobile/PC compatibility

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local infJumpEnabled = false
local noclipEnabled = false
local espEnabled = false
local speedEnabled = false
local minimized = false

local DEFAULT_SPEED = 16
local targetSpeed = DEFAULT_SPEED
local MAX_HEIGHT = 80 -- Max studs above ground for jumps

-- ESP settings
local ESP_RANGE = 5000   -- Max distance (studs)
local ESP_REFRESH = 0.15 -- Throttle (seconds) to conserve FPS

-- Safe UI Parent (Protects against PlayerGui scanning)
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

-- ========== DRAG HELPER (Touch + Mouse Safe) ==========
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

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
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

    return function() return moved end
end

-- ========== UI SETUP ==========
local parentContainer = getSafeUiParent()

local oldGui = parentContainer:FindFirstChild("BloxburgToolkitUI")
if oldGui then oldGui:Destroy() end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BloxburgToolkitUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = parentContainer

-- Main window (height expanded to 215 to fit Speed)
local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 180, 0, 215)
mainFrame.Position = UDim2.new(0.5, -90, 0.5, -107)
mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
mainFrame.BackgroundTransparency = 0.2
mainFrame.Parent = screenGui

local frameCorner = Instance.new("UICorner")
frameCorner.CornerRadius = UDim.new(0, 10)
frameCorner.Parent = mainFrame

-- Drag bar
local dragBar = Instance.new("Frame")
dragBar.Name = "DragBar"
dragBar.Size = UDim2.new(1, 0, 0, 32)
dragBar.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
dragBar.BackgroundTransparency = 0.3
dragBar.BorderSizePixel = 0
dragBar.Parent = mainFrame

local dragBarCorner = Instance.new("UICorner")
dragBarCorner.CornerRadius = UDim.new(0, 10)
dragBarCorner.Parent = dragBar

local grip = Instance.new("TextLabel")
grip.Size = UDim2.new(0, 20, 1, 0)
grip.Position = UDim2.new(0, 8, 0, 0)
grip.BackgroundTransparency = 1
grip.Text = "≡"
grip.TextColor3 = Color3.fromRGB(180, 180, 180)
grip.TextSize = 20
grip.Font = Enum.Font.GothamBold
grip.Parent = dragBar

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -75, 1, 0)
title.Position = UDim2.new(0, 30, 0, 0)
title.BackgroundTransparency = 1
title.Text = "Bloxburg Toolkit"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextSize = 14
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = dragBar

-- Minimize button
local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Size = UDim2.new(0, 24, 0, 24)
minimizeBtn.Position = UDim2.new(1, -29, 0, 4)
minimizeBtn.BackgroundColor3 = Color3.fromRGB(255, 170, 0)
minimizeBtn.Text = "–"
minimizeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
minimizeBtn.TextSize = 18
minimizeBtn.Font = Enum.Font.GothamBold
minimizeBtn.ZIndex = 2
minimizeBtn.Parent = mainFrame

local minCorner = Instance.new("UICorner")
minCorner.CornerRadius = UDim.new(0, 6)
minCorner.Parent = minimizeBtn

-- Standard Button Helper
local function createButton(text, yPos)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -20, 0, 32)
    btn.Position = UDim2.new(0, 10, 0, yPos)
    btn.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextSize = 13
    btn.Font = Enum.Font.GothamBold
    btn.Parent = mainFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = btn
    return btn
end

local jumpBtn = createButton("Inf Jump: OFF [J]", 40)
local noclipBtn = createButton("Noclip: OFF [N]", 78)
local espBtn = createButton("ESP: OFF [K]", 116)

-- Speed UI Section (Side-by-side Button + Input Box)
local speedContainer = Instance.new("Frame")
speedContainer.Size = UDim2.new(1, -20, 0, 32)
speedContainer.Position = UDim2.new(0, 10, 0, 154)
speedContainer.BackgroundTransparency = 1
speedContainer.Parent = mainFrame

local speedBtn = Instance.new("TextButton")
speedBtn.Size = UDim2.new(0.68, 0, 1, 0)
speedBtn.Position = UDim2.new(0, 0, 0, 0)
speedBtn.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
speedBtn.Text = "Speed: OFF [B]"
speedBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
speedBtn.TextSize = 12
speedBtn.Font = Enum.Font.GothamBold
speedBtn.Parent = speedContainer

local speedBtnCorner = Instance.new("UICorner")
speedBtnCorner.CornerRadius = UDim.new(0, 8)
speedBtnCorner.Parent = speedBtn

local speedBox = Instance.new("TextBox")
speedBox.Size = UDim2.new(0.28, 0, 1, 0)
speedBox.Position = UDim2.new(0.72, 0, 0, 0)
speedBox.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
speedBox.Text = tostring(DEFAULT_SPEED)
speedBox.TextColor3 = Color3.fromRGB(255, 255, 255)
speedBox.TextSize = 13
speedBox.TextScaled = true -- Ensures 4-digit numbers fit without truncation
speedBox.Font = Enum.Font.GothamBold
speedBox.ClearTextOnFocus = false
speedBox.Parent = speedContainer

local speedBoxCorner = Instance.new("UICorner")
speedBoxCorner.CornerRadius = UDim.new(0, 8)
speedBoxCorner.Parent = speedBox

-- Restore bubble
local restoreBtn = Instance.new("TextButton")
restoreBtn.Size = UDim2.new(0, 42, 0, 42)
restoreBtn.Position = UDim2.new(0.5, -21, 0.5, -21)
restoreBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
restoreBtn.BackgroundTransparency = 0.2
restoreBtn.Text = "BT"
restoreBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
restoreBtn.TextSize = 14
restoreBtn.Font = Enum.Font.GothamBold
restoreBtn.Visible = false
restoreBtn.Parent = screenGui

local restoreCorner = Instance.new("UICorner")
restoreCorner.CornerRadius = UDim.new(0, 12)
restoreCorner.Parent = restoreBtn

-- Drag & minimize connections
makeDraggable(dragBar, mainFrame)
local restoreWasDragged = makeDraggable(restoreBtn, restoreBtn)

minimizeBtn.MouseButton1Click:Connect(function()
    minimized = true
    restoreBtn.Position = mainFrame.Position
    mainFrame.Visible = false
    restoreBtn.Visible = true
end)

restoreBtn.MouseButton1Click:Connect(function()
    if restoreWasDragged() then return end
    minimized = false
    mainFrame.Position = restoreBtn.Position
    mainFrame.Visible = true
    restoreBtn.Visible = false
end)

-- Sanitize and handle speed input (Allows up to 9999)
speedBox.FocusLost:Connect(function()
    local val = tonumber(speedBox.Text)
    if val and val > 0 then
        targetSpeed = math.clamp(math.floor(val), 1, 9999)
    else
        targetSpeed = DEFAULT_SPEED
    end
    speedBox.Text = tostring(targetSpeed)
end)

-- ========== ESP HELPERS ==========
local function getDistColor(dist)
    if dist < 100 then return Color3.fromRGB(90, 255, 90) end
    if dist < 400 then return Color3.fromRGB(255, 220, 90) end
    return Color3.fromRGB(255, 100, 100)
end

local function createESPBillboard(targetPlayer, head)
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "ESP_Tag"
    billboard.Adornee = head
    billboard.AlwaysOnTop = true
    billboard.StudsOffset = Vector3.new(0, 2.5, 0)
    billboard.Size = UDim2.new(0, 160, 0, 36)
    billboard.MaxDistance = ESP_RANGE
    billboard.Parent = head

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.Size = UDim2.new(1, 0, 0, 18)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = targetPlayer.DisplayName ~= targetPlayer.Name
        and (targetPlayer.DisplayName .. " (@" .. targetPlayer.Name .. ")")
        or targetPlayer.Name
    nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    nameLabel.TextStrokeTransparency = 0.4
    nameLabel.TextSize = 13
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.Parent = billboard

    local distLabel = Instance.new("TextLabel")
    distLabel.Name = "DistLabel"
    distLabel.Position = UDim2.new(0, 0, 0, 19)
    distLabel.Size = UDim2.new(1, 0, 0, 14)
    distLabel.BackgroundTransparency = 1
    distLabel.Text = "-- studs"
    distLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    distLabel.TextStrokeTransparency = 0.4
    distLabel.TextSize = 12
    distLabel.Font = Enum.Font.Gotham
    distLabel.Parent = billboard

    return billboard
end

local function clearAllESP()
    for _, targetPlayer in ipairs(Players:GetPlayers()) do
        local char = targetPlayer.Character
        local head = char and char:FindFirstChild("Head")
        local tag = head and head:FindFirstChild("ESP_Tag")
        if tag then tag:Destroy() end
    end
end

-- ========== TOGGLE FUNCTIONS ==========
local function setJumpEnabled(state)
    infJumpEnabled = state
    jumpBtn.BackgroundColor3 = infJumpEnabled and Color3.fromRGB(60, 255, 60) or Color3.fromRGB(255, 60, 60)
    jumpBtn.Text = "Inf Jump: " .. (infJumpEnabled and "ON [J]" or "OFF [J]")
end

local function setNoclipEnabled(state)
    noclipEnabled = state
    noclipBtn.BackgroundColor3 = noclipEnabled and Color3.fromRGB(60, 255, 60) or Color3.fromRGB(255, 60, 60)
    noclipBtn.Text = "Noclip: " .. (noclipEnabled and "ON [N]" or "OFF [N]")
end

local function setESPEnabled(state)
    espEnabled = state
    espBtn.BackgroundColor3 = espEnabled and Color3.fromRGB(60, 255, 60) or Color3.fromRGB(255, 60, 60)
    espBtn.Text = "ESP: " .. (espEnabled and "ON [K]" or "OFF [K]")
    if not espEnabled then
        clearAllESP()
    end
end

local function setSpeedEnabled(state)
    speedEnabled = state
    speedBtn.BackgroundColor3 = speedEnabled and Color3.fromRGB(60, 255, 60) or Color3.fromRGB(255, 60, 60)
    speedBtn.Text = "Speed: " .. (speedEnabled and "ON [B]" or "OFF [B]")
end

jumpBtn.MouseButton1Click:Connect(function() setJumpEnabled(not infJumpEnabled) end)
noclipBtn.MouseButton1Click:Connect(function() setNoclipEnabled(not noclipEnabled) end)
espBtn.MouseButton1Click:Connect(function() setESPEnabled(not espEnabled) end)
speedBtn.MouseButton1Click:Connect(function() setSpeedEnabled(not speedEnabled) end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.J then
        setJumpEnabled(not infJumpEnabled)
    elseif input.KeyCode == Enum.KeyCode.N then
        setNoclipEnabled(not noclipEnabled)
    elseif input.KeyCode == Enum.KeyCode.K then
        setESPEnabled(not espEnabled)
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

-- ========== SAFE SPEED ENGINE LOOP ==========
-- Uses delta displacement without touching WalkSpeed property
RunService.Heartbeat:Connect(function(deltaTime)
    if not speedEnabled then return end
    local character = player.Character
    if not character then return end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")

    if humanoid and rootPart and humanoid.MoveDirection.Magnitude > 0 then
        -- Multiplier beyond default WalkSpeed (16)
        local extraSpeed = targetSpeed - DEFAULT_SPEED
        if extraSpeed > 0 then
            local moveOffset = humanoid.MoveDirection * (extraSpeed * deltaTime)
            rootPart.CFrame = rootPart.CFrame + Vector3.new(moveOffset.X, 0, moveOffset.Z)
        end
    end
end)

-- ========== INFINITE JUMP WITH FILTERED RAYCAST ==========
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

-- ========== ESP ENGINE LOOP ==========
local lastESPUpdate = 0
RunService.Heartbeat:Connect(function()
    if not espEnabled then return end

    local now = os.clock()
    if now - lastESPUpdate < ESP_REFRESH then return end
    lastESPUpdate = now

    local myChar = player.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end

    for _, targetPlayer in ipairs(Players:GetPlayers()) do
        if targetPlayer ~= player then
            local theirChar = targetPlayer.Character
            local theirHead = theirChar and theirChar:FindFirstChild("Head")
            local theirRoot = theirChar and theirChar:FindFirstChild("HumanoidRootPart")

            if theirHead and theirRoot then
                local billboard = theirHead:FindFirstChild("ESP_Tag") or createESPBillboard(targetPlayer, theirHead)
                local dist = (theirRoot.Position - myRoot.Position).Magnitude
                local distLabel = billboard:FindFirstChild("DistLabel")

                if distLabel then
                    distLabel.Text = string.format("%d studs", math.floor(dist))
                    distLabel.TextColor3 = getDistColor(dist)
                end
            end
        end
    end
end)
