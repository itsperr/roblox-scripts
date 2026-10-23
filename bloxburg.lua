-- Bloxburg Item Duplicator (scatter copies of a held item across your plot)
--
-- HOW TO USE:
--   1. Hold the item you want to copy (cookies, plate, book, any prop)
--   2. Press [C] or click "Capture Item"   -> snapshots the held item
--   3. Stand anywhere on your plot, press [P] -> sets the scatter center
--   4. Press [D] to scatter copies, or [A] to toggle auto-drip mode
--   5. [X] removes every copy this script spawned

-- ========== RE-RUN SAFETY ==========
if getgenv().BloxburgDupeCleanup then
    getgenv().BloxburgDupeCleanup()
end

getgenv().BloxburgDupeConnections = {}
local function track(conn)
    table.insert(getgenv().BloxburgDupeConnections, conn)
    return conn
end

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer

-- Remote Events setup
local remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
if not remotes then
    remotes = Instance.new("Folder")
    remotes.Name = "Remotes"
    remotes.Parent = ReplicatedStorage
end

local duplicateRemote = remotes:WaitForChild("DuplicateItem", 5)
if not duplicateRemote then
    duplicateRemote = Instance.new("RemoteEvent")
    duplicateRemote.Name = "DuplicateItem"
    duplicateRemote.Parent = remotes
end

local getItemDataRemote = remotes:WaitForChild("GetItemData", 5)
if not getItemDataRemote then
    getItemDataRemote = Instance.new("RemoteFunction")
    getItemDataRemote.Name = "GetItemData"
    getItemDataRemote.Parent = remotes
end

-- settings
local spawnCount = 10      -- copies per Duplicate click
local radius = 50          -- scatter radius (studs) around plot center
local AUTO_INTERVAL = 0.35 -- seconds between copies in auto mode

-- state
local itemTemplate = nil   -- cleaned clone of the captured item
local itemTemplateName = nil
local itemData = nil       -- server-validated item data
local plotCenter = nil
local autoEnabled = false
local flashMsg = nil
local flashToken = 0

-- folder that holds every spawned copy (visual only)
local dupeFolder = Instance.new("Folder")
dupeFolder.Name = "ItemDupeCopies"
dupeFolder.Parent = workspace

-- ========== DRAG HELPER ==========
local function makeDraggable(handle, target)
    local dragging = false
    local dragInput, dragStart, startPos
    local moved = false

    track(handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
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
    end))

    track(handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end))

    track(UserInputService.InputChanged:Connect(function(input)
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
    end))

    return function()
        return moved
    end
end

-- ========== UI SETUP ==========
local playerGui = player:WaitForChild("PlayerGui")
local uiParent = (typeof(gethui) == "function" and gethui()) or playerGui

for _, container in ipairs({playerGui, uiParent}) do
    local oldGui = container:FindFirstChild("ItemDupeUI")
    if oldGui then oldGui:Destroy() end
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ItemDupeUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = uiParent

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 210, 0, 272)
mainFrame.Position = UDim2.new(0.5, -105, 0.5, -136)
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
title.Text = "Item Duplicator"
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

-- Status label
local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -20, 0, 30)
statusLabel.Position = UDim2.new(0, 10, 0, 38)
statusLabel.BackgroundTransparency = 1
statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
statusLabel.TextSize = 12
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextWrapped = true
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Parent = mainFrame

-- Count input
local countLabel = Instance.new("TextLabel")
countLabel.Size = UDim2.new(0, 45, 0, 20)
countLabel.Position = UDim2.new(0, 10, 0, 74)
countLabel.BackgroundTransparency = 1
countLabel.Text = "Count:"
countLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
countLabel.TextSize = 12
countLabel.Font = Enum.Font.Gotham
countLabel.TextXAlignment = Enum.TextXAlignment.Left
countLabel.Parent = mainFrame

local countBox = Instance.new("TextBox")
countBox.Size = UDim2.new(0, 40, 0, 20)
countBox.Position = UDim2.new(0, 57, 0, 74)
countBox.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
countBox.Text = tostring(spawnCount)
countBox.PlaceholderText = "10"
countBox.TextColor3 = Color3.fromRGB(255, 255, 255)
countBox.TextSize = 12
countBox.Font =
