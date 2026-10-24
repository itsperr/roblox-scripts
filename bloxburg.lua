-- Player Scanner & Kamikaze Void Eliminator (PJ Modern Edition)
-- Optimized for Delta Executor & Touch / Mouse

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- UI Theme
local THEME = {
    CardBg = Color3.fromRGB(18, 20, 26),
    CardStroke = Color3.fromRGB(36, 40, 52),
    HeaderTitle = Color3.fromRGB(240, 242, 248),
    SectionTitle = Color3.fromRGB(120, 128, 146),
    
    TileBg = Color3.fromRGB(28, 31, 40),
    TileHover = Color3.fromRGB(36, 40, 52),
    TileText = Color3.fromRGB(200, 205, 220),
    
    EliminateBtnBg = Color3.fromRGB(235, 60, 75),
    EliminateBtnText = Color3.fromRGB(255, 255, 255),
    
    WidgetBg = Color3.fromRGB(22, 25, 34),
    WidgetStroke = Color3.fromRGB(235, 60, 75),
    WidgetText = Color3.fromRGB(235, 60, 75),
    
    Font = Enum.Font.Ubuntu
}

-- Safe UI Parent
local function getSafeUiParent()
    if gethui then return gethui() end
    local success, coreGui = pcall(function() return game:GetService("CoreGui") end)
    if success and coreGui then return coreGui end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local parentContainer = getSafeUiParent()

-- Clean existing instances
local oldGui = parentContainer:FindFirstChild("PE_PJ_ScreenGui")
if oldGui then oldGui:Destroy() end

-- ScreenGui Setup
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "PE_PJ_ScreenGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = parentContainer

-- ========== DRAG HELPER (TOUCH & MOUSE) ==========
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

-- Main Window Card (320x215)
local MainCard = Instance.new("Frame")
MainCard.Name = "MainCard"
MainCard.Size = UDim2.new(0, 320, 0, 215)
MainCard.Position = UDim2.new(0.5, -160, 0.5, -107)
MainCard.BackgroundColor3 = THEME.CardBg
MainCard.BorderSizePixel = 0
MainCard.Parent = ScreenGui

local cardCorner = Instance.new("UICorner")
cardCorner.CornerRadius = UDim.new(0, 16)
cardCorner.Parent = MainCard

local cardStroke = Instance.new("UIStroke")
cardStroke.Color = THEME.CardStroke
cardStroke.Thickness = 1.2
cardStroke.Parent = MainCard

-- Header
local Header = Instance.new("Frame")
Header.Name = "Header"
Header.Size = UDim2.new(1, 0, 0, 42)
Header.BackgroundTransparency = 1
Header.Parent = MainCard

local CloseBtn = Instance.new("TextButton")
CloseBtn.Name = "CloseBtn"
CloseBtn.Size = UDim2.new(0, 32, 0, 32)
CloseBtn.Position = UDim2.new(0, 8, 0, 5)
CloseBtn.BackgroundTransparency = 1
CloseBtn.BorderSizePixel = 0
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = THEME.HeaderTitle
CloseBtn.TextSize = 14
CloseBtn.Font = THEME.Font
CloseBtn.Parent = Header

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Name = "TitleLabel"
TitleLabel.Size = UDim2.new(1, -85, 1, 0)
TitleLabel.Position = UDim2.new(0, 40, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "Kamikaze Void Slammer"
TitleLabel.TextColor3 = THEME.HeaderTitle
TitleLabel.TextSize = 13
TitleLabel.Font = THEME.Font
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = Header

local RefreshBtn = Instance.new("TextButton")
RefreshBtn.Name = "RefreshBtn"
RefreshBtn.Size = UDim2.new(0, 32, 0, 32)
RefreshBtn.Position = UDim2.new(1, -40, 0, 5)
RefreshBtn.BackgroundTransparency = 1
RefreshBtn.BorderSizePixel = 0
RefreshBtn.Text = "↻"
RefreshBtn.TextColor3 = THEME.SectionTitle
RefreshBtn.TextSize = 16
RefreshBtn.Font = THEME.Font
RefreshBtn.Parent = Header

-- Target Section Label
local TargetLabel = Instance.new("TextLabel")
TargetLabel.Size = UDim2.new(1, -32, 0, 16)
TargetLabel.Position = UDim2.new(0, 16, 0, 48)
TargetLabel.BackgroundTransparency = 1
TargetLabel.Text = "TARGET SELECTION"
TargetLabel.TextColor3 = THEME.SectionTitle
TargetLabel.TextSize = 10
TargetLabel.Font = THEME.Font
TargetLabel.TextXAlignment = Enum.TextXAlignment.Left
TargetLabel.Parent = MainCard

-- Dropdown Button
local Dropdown = Instance.new("TextButton")
Dropdown.Name = "DropdownTrigger"
Dropdown.Size = UDim2.new(1, -32, 0, 36)
Dropdown.Position = UDim2.new(0, 16, 0, 70)
Dropdown.BackgroundColor3 = THEME.TileBg
Dropdown.BorderSizePixel = 0
Dropdown.Text = "  Select Target Player  ▼"
Dropdown.TextColor3 = THEME.TileText
Dropdown.TextSize = 11
Dropdown.Font = THEME.Font
Dropdown.TextXAlignment = Enum.TextXAlignment.Left
Dropdown.AutoButtonColor = false
Dropdown.Parent = MainCard

local dropCorner = Instance.new("UICorner")
dropCorner.CornerRadius = UDim.new(0, 10)
dropCorner.Parent = Dropdown

-- Void Slam Button
local EliminateButton = Instance.new("TextButton")
EliminateButton.Name = "EliminateButton"
EliminateButton.Size = UDim2.new(1, -32, 0, 38)
EliminateButton.Position = UDim2.new(0, 16, 0, 120)
EliminateButton.BackgroundColor3 = THEME.EliminateBtnBg
EliminateButton.BorderSizePixel = 0
EliminateButton.Text = "Void Slam (Kamikaze)"
EliminateButton.TextColor3 = THEME.EliminateBtnText
EliminateButton.TextSize = 12
EliminateButton.Font = THEME.Font
EliminateButton.AutoButtonColor = false
EliminateButton.Parent = MainCard

local elimCorner = Instance.new("UICorner")
elimCorner.CornerRadius = UDim.new(0, 10)
elimCorner.Parent = EliminateButton

-- Status Label
local StatusLabel = Instance.new("TextLabel")
StatusLabel.Name = "StatusLabel"
StatusLabel.Size = UDim2.new(1, -32, 0, 20)
StatusLabel.Position = UDim2.new(0, 16, 0, 172)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "Status: Idle"
StatusLabel.TextColor3 = THEME.SectionTitle
StatusLabel.TextSize = 10
StatusLabel.Font = THEME.Font
StatusLabel.TextXAlignment = Enum.TextXAlignment.Center
StatusLabel.Parent = MainCard

-- Dropdown Scrolling Frame
local ListFrame = Instance.new("ScrollingFrame")
ListFrame.Name = "PlayerListScroll"
ListFrame.Size = UDim2.new(1, -32, 0, 110)
ListFrame.Position = UDim2.new(0, 16, 0, 110)
ListFrame.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
ListFrame.BorderSizePixel = 0
ListFrame.Visible = false
ListFrame.ZIndex = 10
ListFrame.ScrollBarThickness = 3
ListFrame.ScrollBarImageColor3 = THEME.SectionTitle
ListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
ListFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
ListFrame.Parent = MainCard

local listCorner = Instance.new("UICorner")
listCorner.CornerRadius = UDim.new(0, 10)
listCorner.Parent = ListFrame

local listStroke = Instance.new("UIStroke")
listStroke.Color = THEME.CardStroke
listStroke.Thickness = 1
listStroke.Parent = ListFrame

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 2)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = ListFrame

-- Squared PJ Minimized Widget
local RestoreBtn = Instance.new("TextButton")
RestoreBtn.Name = "PJ_EliminatorWidget"
RestoreBtn.Size = UDim2.new(0, 42, 0, 42)
RestoreBtn.Position = UDim2.new(0.5, -21, 0.05, 0)
RestoreBtn.BackgroundColor3 = THEME.WidgetBg
RestoreBtn.BorderSizePixel = 0
RestoreBtn.Text = "PJ"
RestoreBtn.TextColor3 = THEME.WidgetText
RestoreBtn.TextSize = 15
RestoreBtn.Font = THEME.Font
RestoreBtn.Visible = false
RestoreBtn.Parent = ScreenGui

local resCorner = Instance.new("UICorner")
resCorner.CornerRadius = UDim.new(0, 10)
resCorner.Parent = RestoreBtn

local resStroke = Instance.new("UIStroke")
resStroke.Color = THEME.WidgetStroke
resStroke.Thickness = 1.4
resStroke.Parent = RestoreBtn

-- Drag & Window Toggles
makeDraggable(Header, MainCard)
local restoreWasDragged = makeDraggable(RestoreBtn, RestoreBtn)

CloseBtn.MouseButton1Click:Connect(function()
    RestoreBtn.Position = UDim2.new(MainCard.Position.X.Scale, MainCard.Position.X.Offset, MainCard.Position.Y.Scale, MainCard.Position.Y.Offset)
    MainCard.Visible = false
    RestoreBtn.Visible = true
end)

RestoreBtn.MouseButton1Click:Connect(function()
    if restoreWasDragged() then return end
    MainCard.Position = UDim2.new(RestoreBtn.Position.X.Scale, RestoreBtn.Position.X.Offset, RestoreBtn.Position.Y.Scale, RestoreBtn.Position.Y.Offset)
    MainCard.Visible = true
    RestoreBtn.Visible = false
end)

-- Player List Builder
local selectedPlayer = nil

local function updatePlayerList()
    for _, child in ipairs(ListFrame:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end

    for _, target in ipairs(Players:GetPlayers()) do
        if target ~= LocalPlayer then
            local btn = Instance.new("TextButton")
            btn.Name = target.Name
            btn.Size = UDim2.new(1, -6, 0, 28)
            btn.BackgroundColor3 = THEME.TileBg
            btn.BorderSizePixel = 0
            btn.ZIndex = 11
            
            local nameDisplay = target.DisplayName ~= target.Name 
                and string.format(" %s (@%s)", target.DisplayName, target.Name)
                or string.format(" %s", target.Name)
            
            btn.Text = nameDisplay
            btn.TextColor3 = THEME.TileText
            btn.TextSize = 10
            btn.Font = THEME.Font
            btn.TextXAlignment = Enum.TextXAlignment.Left
            btn.AutoButtonColor = true
            btn.Parent = ListFrame

            local btnCorner = Instance.new("UICorner")
            btnCorner.CornerRadius = UDim.new(0, 6)
            btnCorner.Parent = btn

            btn.MouseButton1Click:Connect(function()
                selectedPlayer = target
                Dropdown.Text = "  " .. target.DisplayName .. "  ✓"
                Dropdown.TextColor3 = THEME.HeaderTitle
                ListFrame.Visible = false
                StatusLabel.Text = "Selected: " .. target.Name
            end)
        end
    end
end

Dropdown.MouseButton1Click:Connect(function()
    ListFrame.Visible = not ListFrame.Visible
    if ListFrame.Visible then
        updatePlayerList()
    end
end)

RefreshBtn.MouseButton1Click:Connect(function()
    updatePlayerList()
    StatusLabel.Text = "List Refreshed"
end)

-- ========== KAMIKAZE VOID SLAM ENGINE ==========
local isEliminating = false

local function voidTogether(target)
    if isEliminating then return end
    if not target or not target.Character then
        StatusLabel.Text = "Target not loaded"
        return
    end

    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local myHum = myChar and myChar:FindFirstChildOfClass("Humanoid")
    local targetChar = target.Character
    local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
    local targetHum = targetChar:FindFirstChildOfClass("Humanoid")

    if not myRoot or not myHum or myHum.Health <= 0 then
        StatusLabel.Text = "You must be alive"
        return
    end

    if not targetRoot or not targetHum or targetHum.Health <= 0 then
        StatusLabel.Text = "Target already dead"
        return
    end

    isEliminating = true
    StatusLabel.Text = "Dragging " .. target.DisplayName .. " to void..."
    StatusLabel.TextColor3 = Color3.fromRGB(235, 60, 75)

    -- Disable limb collision on self to avoid self-crushing before reaching void
    for _, part in ipairs(myChar:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = false
        end
    end
    myHum:ChangeState(Enum.HumanoidStateType.Physics)

    -- High downward velocity force to drive collision past boundaries
    local slamForce = Instance.new("BodyVelocity")
    slamForce.Name = "VoidSlamVelocity"
    slamForce.Velocity = Vector3.new(0, -5000, 0)
    slamForce.MaxForce = Vector3.new(0, math.huge, 0)
    slamForce.P = 1500
    slamForce.Parent = myRoot

    local slamTorque = Instance.new("BodyAngularVelocity")
    slamTorque.Name = "VoidSlamTorque"
    slamTorque.AngularVelocity = Vector3.new(5000, 5000, 5000)
    slamTorque.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    slamTorque.Parent = myRoot

    local startTime = os.clock()
    local maxDuration = 4.0

    local connection
    connection = RunService.Heartbeat:Connect(function()
        -- Terminate if duration exceeds, target dies, or self dies
        if (os.clock() - startTime > maxDuration) 
            or not targetRoot or not targetRoot.Parent 
            or targetHum.Health <= 0 
            or myHum.Health <= 0 then
            
            if connection then connection:Disconnect() end
            return
        end

        -- Latch directly onto their upper torso/head to force physical pushdown
        myRoot.CFrame = targetRoot.CFrame * CFrame.new(0, 1.2, 0)
    end)

    task.wait(maxDuration)
    if connection then connection:Disconnect() end

    -- Cleanup physics movers if character didn't reset
    if slamForce and slamForce.Parent then slamForce:Destroy() end
    if slamTorque and slamTorque.Parent then slamTorque:Destroy() end

    isEliminating = false
    StatusLabel.Text = "Operation Finished"
    StatusLabel.TextColor3 = THEME.SectionTitle
end

EliminateButton.MouseButton1Click:Connect(function()
    voidTogether(selectedPlayer)
end)

-- Dynamic Player List Management
Players.PlayerAdded:Connect(updatePlayerList)
Players.PlayerRemoving:Connect(function(leaving)
    if selectedPlayer == leaving then
        selectedPlayer = nil
        Dropdown.Text = "  Select Target Player  ▼"
        Dropdown.TextColor3 = THEME.TileText
        StatusLabel.Text = "Target left the game"
    end
    updatePlayerList()
end)

-- Initial population
updatePlayerList()
