-- Player Scanner and Eliminator Script for Delta Executor
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Create GUI
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Parent = game:GetService("CoreGui")
ScreenGui.Name = "PlayerEliminator"

-- Main Frame
local MainFrame = Instance.new("Frame")
MainFrame.Parent = ScreenGui
MainFrame.Size = UDim2.new(0, 300, 0, 200)
MainFrame.Position = UDim2.new(0.5, -150, 0.5, -100)
MainFrame.BackgroundColor3 = Color3.new(0.1, 0.1, 0.1)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true

-- Title
local Title = Instance.new("TextLabel")
Title.Parent = MainFrame
Title.Size = UDim2.new(1, 0, 0, 30)
Title.Position = UDim2.new(0, 0, 0, 0)
Title.BackgroundColor3 = Color3.new(0.2, 0.2, 0.2)
Title.BorderSizePixel = 0
Title.Text = "Player Eliminator"
Title.TextColor3 = Color3.new(1, 1, 1)
Title.Font = Enum.Font.SourceSansBold
Title.TextSize = 16

-- Player Dropdown
local Dropdown = Instance.new("TextButton")
Dropdown.Parent = MainFrame
Dropdown.Size = UDim2.new(0, 280, 0, 30)
Dropdown.Position = UDim2.new(0, 10, 0, 50)
Dropdown.BackgroundColor3 = Color3.new(0.2, 0.2, 0.2)
Dropdown.BorderSizePixel = 0
Dropdown.Text = "Select Player"
Dropdown.TextColor3 = Color3.new(1, 1, 1)
Dropdown.Font = Enum.Font.SourceSans
Dropdown.TextSize = 14

-- Dropdown List Frame
local ListFrame = Instance.new("ScrollingFrame")
ListFrame.Parent = MainFrame
ListFrame.Size = UDim2.new(0, 280, 0, 100)
ListFrame.Position = UDim2.new(0, 10, 0, 80)
ListFrame.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
ListFrame.BorderSizePixel = 0
ListFrame.Visible = false
ListFrame.ScrollBarThickness = 5

-- Eliminate Button
local EliminateButton = Instance.new("TextButton")
EliminateButton.Parent = MainFrame
EliminateButton.Size = UDim2.new(0, 280, 0, 30)
EliminateButton.Position = UDim2.new(0, 10, 0, 170)
EliminateButton.BackgroundColor3 = Color3.new(0.8, 0.2, 0.2)
EliminateButton.BorderSizePixel = 0
EliminateButton.Text = "Eliminate Player"
EliminateButton.TextColor3 = Color3.new(1, 1, 1)
EliminateButton.Font = Enum.Font.SourceSansBold
EliminateButton.TextSize = 14

-- Variable to store selected player
local selectedPlayer = nil

-- Function to update player list
local function updatePlayerList()
    -- Clear existing buttons
    for _, child in pairs(ListFrame:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end
    
    -- Add buttons for each player
    local yOffset = 0
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then -- Exclude local player
            local playerButton = Instance.new("TextButton")
            playerButton.Parent = ListFrame
            playerButton.Size = UDim2.new(1, 0, 0, 25)
            playerButton.Position = UDim2.new(0, 0, 0, yOffset)
            playerButton.BackgroundColor3 = Color3.new(0.2, 0.2, 0.2)
            playerButton.BorderSizePixel = 0
            playerButton.Text = player.Name
            playerButton.TextColor3 = Color3.new(1, 1, 1)
            playerButton.Font = Enum.Font.SourceSans
            playerButton.TextSize = 14
            
            playerButton.MouseButton1Click:Connect(function()
                selectedPlayer = player
                Dropdown.Text = player.Name
                ListFrame.Visible = false
            end)
            
            yOffset = yOffset + 25
        end
    end
    
    ListFrame.CanvasSize = UDim2.new(0, 0, 0, yOffset)
end

-- Toggle dropdown visibility
Dropdown.MouseButton1Click:Connect(function()
    ListFrame.Visible = not ListFrame.Visible
    if ListFrame.Visible then
        updatePlayerList()
    end
end)

-- Close dropdown when clicking outside
MainFrame.MouseButton1Click:Connect(function()
    ListFrame.Visible = false
end)

-- Eliminate function
EliminateButton.MouseButton1Click:Connect(function()
    if selectedPlayer and selectedPlayer.Character and selectedPlayer.Character:FindFirstChild("Humanoid") then
        -- Set health to 0 to eliminate the player
        selectedPlayer.Character.Humanoid.Health = 0
    end
end)

-- Initial player list update
updatePlayerList()
