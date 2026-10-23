--=============================================================================
--  WELCOME TO BLOXBURG · SERVER-SIDE ITEM DUPLICATOR (v2.1 — MOBILE & FILTER)
--=============================================================================
--  - Horizontal/landscape UI layout optimized for mobile screens.
--  - Packet blacklist & noise filter to eliminate background core/chat spam.
--  - Spy toggle actually gates the namecall hook.
--  - Logs detect and display Bloxburg's first-argument RPC actions.
--=============================================================================

if getgenv().BloxburgDupeV2_Cleanup then getgenv().BloxburgDupeV2_Cleanup() end

getgenv().BloxburgDupeV2_Conn = {}
local function track(c)
    table.insert(getgenv().BloxburgDupeV2_Conn, c)
    return c
end

local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")
local player  = Players.LocalPlayer

local unpack            = table.unpack or unpack
local newcclosure       = newcclosure or function(f) return f end
local getnamecallmethod = getnamecallmethod or function() return nil end

-- settings ------------------------------------------------------------------
local spawnCount = 25
local radius     = 40
local activeSlot = "A"
local spyEnabled = false  -- Default OFF to keep logs completely clean until ready
local autoPlace  = false
local burstMode  = "burst" -- "burst" | "spread"
local SPREAD_GAP = 0.03
local LOG_MAX    = 40
local running    = true
local plotCenter = nil

-- packet noise filter -------------------------------------------------------
local IGNORED_REMOTES = {
    ["SayMessageRequest"]          = true,
    ["DefaultChatSystemChatEvents"] = true,
    ["OnNewMessage"]               = true,
    ["OnMessageDoneFiltering"]     = true,
    ["ChatScript"]                 = true,
    ["UpdatePlayerBlockList"]      = true,
    ["SetDialogInUse"]             = true,
    ["ClientDataUpdate"]           = true,
    ["GetServerVersion"]           = true,
    ["CharacterLoaded"]            = true,
    ["TouchRemote"]                = true,
}

local function shouldIgnore(remote, args)
    local name = remote.Name
    if IGNORED_REMOTES[name] then return true end

    -- Core engine & chat network instances
    if remote:IsDescendantOf(game:GetService("RobloxReplicatedStorage")) then
        return true
    end

    -- Filter periodic telemetry, sound, and ping events
    local lower = name:lower()
    if lower:find("ping") or lower:find("heartbeat") or lower:find("analytics") or lower:find("sound") then
        return true
    end

    return false
end

-- state ---------------------------------------------------------------------
local slots         = { A = nil, B = nil }
local registry      = {}
local registryOrder = {}
local logEntries    = {}
local logDirty      = false
local fireTotal     = 0
local suppress      = false
local flashMsg, flashToken = nil, 0

--=============================================================================
-- HELPERS
--=============================================================================
local function deepCopy(v, seen)
    if type(v) ~= "table" then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local out = {}
    seen[v] = out
    for k, val in pairs(v) do
        out[deepCopy(k, seen)] = deepCopy(val, seen)
    end
    return out
end

local function describe(v, depth)
    depth = depth or 0
    local t = typeof(v)
    if t == "Instance" then
        return v.Name
    elseif t == "string" then
        return string.format("%q", v)
    elseif t == "table" then
        if depth >= 2 then return "{...}" end
        local parts, n = {}, 0
        for k, val in pairs(v) do
            n += 1
            if n > 3 then parts[#parts + 1] = "..." break end
            parts[#parts + 1] = tostring(k) .. "=" .. describe(val, depth + 1)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return tostring(v)
end

local function argString(args)
    local parts = {}
    for i = 1, math.min(#args, 4) do
        parts[#parts + 1] = describe(args[i])
    end
    if #args > 4 then parts[#parts + 1] = "..." end
    local s = table.concat(parts, ", ")
    if #s > 48 then s = s:sub(1, 45) .. "..." end
    return s
end

--=============================================================================
-- PACKET RECORDER
--=============================================================================
local function recordFire(remote, args)
    fireTotal += 1

    local actionTag = ""
    if type(args[1]) == "string" then
        actionTag = " [" .. args[1] .. "]"
    elseif type(args[1]) == "table" and type(args[1].Action) == "string" then
        actionTag = " [" .. args[1].Action .. "]"
    end

    local e = registry[remote]
    if not e then
        e = { remote = remote, count = 0 }
        registry[remote] = e
        table.insert(registryOrder, e)
    end
    e.count += 1
    e.last   = args
    e.stamp  = os.clock()

    table.insert(logEntries, {
        remote    = remote,
        args      = args,
        desc      = argString(args),
        actionTag = actionTag,
        n         = fireTotal,
    })
    if #logEntries > LOG_MAX then table.remove(logEntries, 1) end
    logDirty = true
end

--=============================================================================
-- HOOK (With Spy Check & Ignored Remotes Filter)
--=============================================================================
local hookInstalled = false
local hookedMT, hookedOld

-- Replace the hook section with this:
hookInstalled = pcall(function()
    local mt  = getrawmetatable(game)
    local old = mt.__namecall
    hookedMT, hookedOld = mt, old

    setreadonly(mt, false)
    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        
        -- Always call original first to ensure game function works
        -- Then log after if needed
        if spyEnabled and not suppress and method and (method == "FireServer" or method == "InvokeServer") then
            if typeof(self) == "Instance" and self.ClassName ~= nil
                and (self.ClassName == "RemoteEvent"
                  or self.ClassName == "RemoteFunction"
                  or self.ClassName == "UnreliableRemoteEvent") then
                
                -- Wrap logging in pcall so it never breaks the game
                task.spawn(function()
                    local args = { ... }
                    local success, err = pcall(function()
                        if not shouldIgnore(self, args) then
                            recordFire(self, args)
                        end
                    end)
                    if not success then
                        warn("BloxburgDupe Spy Error: " .. tostring(err))
                    end
                end)
            end
        end
        
        return old(self, ...)
    end)
    setreadonly(mt, true)
end)

--=============================================================================
-- HORIZONTAL UI SETUP
--=============================================================================
local playerGui = player:WaitForChild("PlayerGui")
local uiParent  = (typeof(gethui) == "function" and gethui()) or playerGui

for _, container in ipairs({ playerGui, uiParent }) do
    local old = container:FindFirstChild("ItemDupeV2UI")
    if old then old:Destroy() end
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ItemDupeV2UI"
screenGui.ResetOnSpawn = false
screenGui.Parent = uiParent

-- Dimensions: 460 x 220 fits landscape mobile phones without vertical clipping
local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 460, 0, 220)
mainFrame.Position = UDim2.new(0.5, -230, 0.5, -110)
mainFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
mainFrame.BackgroundTransparency = 0.1
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 8)

local dragBar = Instance.new("Frame")
dragBar.Size = UDim2.new(1, 0, 0, 26)
dragBar.BackgroundColor3 = Color3.fromRGB(35, 39, 48)
dragBar.BorderSizePixel = 0
dragBar.Parent = mainFrame
Instance.new("UICorner", dragBar).CornerRadius = UDim.new(0, 8)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -35, 1, 0)
title.Position = UDim2.new(0, 10, 0, 0)
title.BackgroundTransparency = 1
title.Text = "Bloxburg Dupe v2.1 (Horizontal)"
title.TextColor3 = Color3.fromRGB(240, 240, 240)
title.TextSize = 11
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = dragBar

local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Size = UDim2.new(0, 20, 0, 20)
minimizeBtn.Position = UDim2.new(1, -24, 0, 3)
minimizeBtn.BackgroundColor3 = Color3.fromRGB(245, 160, 20)
minimizeBtn.Text = "–"
minimizeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
minimizeBtn.TextSize = 14
minimizeBtn.Font = Enum.Font.GothamBold
minimizeBtn.ZIndex = 2
minimizeBtn.Parent = dragBar
Instance.new("UICorner", minimizeBtn).CornerRadius = UDim.new(0, 5)

-- Touch & mouse drag support
local function makeDraggable(handle, target)
    local dragging, dragInput, dragStart, startPos = false, nil, nil, nil
    local moved = false

    track(handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging, moved = true, false
            dragStart = input.Position
            startPos  = target.Position
            track(input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end))
        end
    end))

    track(handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end))

    track(UIS.InputChanged:Connect(function(input)
        if dragging and input == dragInput then
            local delta = input.Position - dragStart
            if delta.Magnitude > 4 then moved = true end
            target.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end))

    return function() return moved end
end

makeDraggable(dragBar, mainFrame)

-- UI Column Division --------------------------------------------------------
-- Left Column: Controls (Width: 215)
local leftCol = Instance.new("Frame")
leftCol.Size = UDim2.new(0, 215, 1, -32)
leftCol.Position = UDim2.new(0, 8, 0, 28)
leftCol.BackgroundTransparency = 1
leftCol.Parent = mainFrame

-- Right Column: Network Log (Width: 220)
local rightCol = Instance.new("Frame")
rightCol.Size = UDim2.new(0, 220, 1, -32)
rightCol.Position = UDim2.new(0, 230, 0, 28)
rightCol.BackgroundTransparency = 1
rightCol.Parent = mainFrame

-- UI Helpers
local function createLabel(parent, text, x, y, w, h, color, size)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(0, w, 0, h)
    l.Position = UDim2.new(0, x, 0, y)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = color or Color3.fromRGB(180, 185, 195)
    l.TextSize = size or 10
    l.Font = Enum.Font.Gotham
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextTruncate = Enum.TextTruncate.AtEnd
    l.Parent = parent
    return l
end

local function createButton(parent, text, x, y, w, h, color, size)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, w, 0, h)
    b.Position = UDim2.new(0, x, 0, y)
    b.BackgroundColor3 = color
    b.Text = text
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.TextSize = size or 10
    b.Font = Enum.Font.GothamBold
    b.Parent = parent
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
    return b
end

-- Left Column Content -------------------------------------------------------
local topStatusLbl = createLabel(leftCol, "Status: Ready", 0, 0, 215, 14, Color3.fromRGB(140, 150, 165), 10)
local slotALbl     = createLabel(leftCol, "Slot A: empty", 0, 14, 215, 13, Color3.fromRGB(255, 200, 110), 9)
local slotBLbl     = createLabel(leftCol, "Slot B: empty", 0, 27, 215, 13, Color3.fromRGB(130, 210, 255), 9)

-- Row 1: Spy & Slot Toggle
local spyBtn      = createButton(leftCol, "Spy: OFF", 0, 44, 104, 22, Color3.fromRGB(110, 50, 50))
local slotSwapBtn = createButton(leftCol, "Slot: A", 110, 44, 105, 22, Color3.fromRGB(60, 65, 80))

-- Row 2: Inputs (Count & Scatter Radius)
createLabel(leftCol, "N:", 0, 72, 16, 18)
local countBox = Instance.new("TextBox")
countBox.Size = UDim2.new(0, 36, 0, 18)
countBox.Position = UDim2.new(0, 18, 0, 72)
countBox.BackgroundColor3 = Color3.fromRGB(42, 46, 56)
countBox.Text = tostring(spawnCount)
countBox.TextColor3 = Color3.fromRGB(255, 255, 255)
countBox.TextSize = 10
countBox.Font = Enum.Font.Gotham
countBox.ClearTextOnFocus = false
countBox.Parent = leftCol
Instance.new("UICorner", countBox).CornerRadius = UDim.new(0, 4)

createLabel(leftCol, "Rad:", 60, 72, 28, 18)
local radiusBox = Instance.new("TextBox")
radiusBox.Size = UDim2.new(0, 36, 0, 18)
radiusBox.Position = UDim2.new(0, 90, 0, 72)
radiusBox.BackgroundColor3 = Color3.fromRGB(42, 46, 56)
radiusBox.Text = tostring(radius)
radiusBox.TextColor3 = Color3.fromRGB(255, 255, 255)
radiusBox.TextSize = 10
radiusBox.Font = Enum.Font.Gotham
radiusBox.ClearTextOnFocus = false
radiusBox.Parent = leftCol
Instance.new("UICorner", radiusBox).CornerRadius = UDim.new(0, 4)

local grabBtn = createButton(leftCol, "Grab Last", 132, 72, 83, 18, Color3.fromRGB(70, 75, 95))

-- Row 3: Actions
local burstBtn   = createButton(leftCol, "FLOOD (A)", 0, 96, 104, 26, Color3.fromRGB(50, 150, 80), 11)
local scatterBtn = createButton(leftCol, "Scatter (B)", 110, 96, 105, 26, Color3.fromRGB(45, 100, 150), 11)

-- Row 4: Secondary Options
local autoPlaceBtn = createButton(leftCol, "Auto-Place: OFF", 0, 128, 104, 20, Color3.fromRGB(80, 50, 80), 9)
local modeBtn      = createButton(leftCol, "Mode: BURST", 110, 128, 105, 20, Color3.fromRGB(70, 70, 70), 9)
local originBtn    = createButton(leftCol, "Set Origin Here", 0, 152, 215, 20, Color3.fromRGB(50, 55, 68), 9)

-- Right Column Content (Log) ------------------------------------------------
local logHeader = createLabel(rightCol, "Captured Packets (Tap to select):", 0, 0, 160, 14, Color3.fromRGB(160, 170, 185), 9)
local clearLogBtn = createButton(rightCol, "Clear", 175, 0, 45, 14, Color3.fromRGB(85, 45, 45), 9)

local logFrame = Instance.new("ScrollingFrame")
logFrame.Size = UDim2.new(1, 0, 1, -18)
logFrame.Position = UDim2.new(0, 0, 0, 16)
logFrame.BackgroundColor3 = Color3.fromRGB(14, 16, 20)
logFrame.BackgroundTransparency = 0.2
logFrame.BorderSizePixel = 0
logFrame.ScrollBarThickness = 3
logFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
logFrame.Parent = rightCol
Instance.new("UICorner", logFrame).CornerRadius = UDim.new(0, 5)

-- Minimized Pill (for quick restore on mobile)
local restoreBtn = Instance.new("TextButton")
restoreBtn.Size = UDim2.new(0, 34, 0, 34)
restoreBtn.Position = mainFrame.Position
restoreBtn.BackgroundColor3 = Color3.fromRGB(24, 26, 32)
restoreBtn.Text = "BB"
restoreBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
restoreBtn.TextSize = 12
restoreBtn.Font = Enum.Font.GothamBold
restoreBtn.Visible = false
restoreBtn.Parent = screenGui
Instance.new("UICorner", restoreBtn).CornerRadius = UDim.new(0, 8)
local restoreWasDragged = makeDraggable(restoreBtn, restoreBtn)

minimizeBtn.MouseButton1Click:Connect(function()
    restoreBtn.Position = mainFrame.Position
    mainFrame.Visible, restoreBtn.Visible = false, true
end)
restoreBtn.MouseButton1Click:Connect(function()
    if restoreWasDragged() then return end
    mainFrame.Position = restoreBtn.Position
    mainFrame.Visible, restoreBtn.Visible = true, false
end)

--=============================================================================
-- STATUS / FLASH
--=============================================================================
local function flash(msg)
    flashToken += 1
    local my = flashToken
    flashMsg = msg
    topStatusLbl.Text = msg
    topStatusLbl.TextColor3 = Color3.fromRGB(255, 225, 120)
    task.delay(2, function()
        if flashToken == my then
            flashMsg = nil
            topStatusLbl.TextColor3 = Color3.fromRGB(140, 150, 165)
        end
    end)
end

local function refreshSlots()
    slotALbl.Text = "Slot A: " .. (slots.A and (slots.A.name .. (slots.A.actionTag or "")) or "empty")
    slotBLbl.Text = "Slot B: " .. (slots.B and (slots.B.name .. (slots.B.actionTag or "")) or "empty")
    slotSwapBtn.Text = "Slot: " .. activeSlot
end
refreshSlots()

--=============================================================================
-- LOG RENDERING
--=============================================================================
local grabEntry

local function renderLog()
    for _, c in ipairs(logFrame:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end
    local y = 0
    for i = #logEntries, 1, -1 do
        local e = logEntries[i]
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -4, 0, 18)
        b.Position = UDim2.new(0, 2, 0, y)
        b.BackgroundColor3 = Color3.fromRGB(32, 36, 46)
        b.BackgroundTransparency = 0.2
        b.TextColor3 = Color3.fromRGB(160, 200, 255)
        b.TextSize = 9
        b.Font = Enum.Font.Code
        b.TextXAlignment = Enum.TextXAlignment.Left
        b.TextTruncate = Enum.TextTruncate.AtEnd
        b.Text = "[" .. e.n .. "]" .. e.actionTag .. " " .. e.remote.Name
        b.Parent = logFrame
        b.MouseButton1Click:Connect(function() grabEntry(e) end)
        y += 19
    end
    logFrame.CanvasSize = UDim2.new(0, 0, 0, y)
end

--=============================================================================
-- ACTIONS & BURST
--=============================================================================
grabEntry = function(e)
    slots[activeSlot] = {
        remote    = e.remote,
        args      = deepCopy(e.args),
        name      = e.remote.Name,
        actionTag = e.actionTag,
        isFunc    = (e.remote.ClassName == "RemoteFunction"),
    }
    refreshSlots()
    flash("Grabbed " .. e.remote.Name .. (e.actionTag or "") .. " -> " .. activeSlot)
end

local function callRemote(s, args)
    suppress = true
    if s.isFunc then
        s.remote:InvokeServer(unpack(args))
    else
        s.remote:FireServer(unpack(args))
    end
    suppress = false
end

local function jitter(args)
    local out, done = {}, false
    for i = 1, #args do
        local v = args[i]
        if not done and (typeof(v) == "Vector3" or typeof(v) == "CFrame") then
            local a = math.random() * math.pi * 2
            local d = radius * math.sqrt(math.random())
            if typeof(v) == "Vector3" then
                local base = plotCenter or v
                out[i] = Vector3.new(base.X + math.cos(a) * d, v.Y, base.Z + math.sin(a) * d)
            else
                local base = plotCenter or v.Position
                out[i] = CFrame.new(base.X + math.cos(a) * d, v.Position.Y, base.Z + math.sin(a) * d)
                    * (v - v.Position)
            end
            done = true
        else
            out[i] = v
        end
    end
    return out
end

local function burst(slotId, n, doJitter, spread)
    local s = slots[slotId]
    if not s then
        flash("Slot " .. slotId .. " is empty")
        return
    end
    n = n or spawnCount

    if spread then
        task.spawn(function()
            for _ = 1, n do
                if not running then break end
                callRemote(s, doJitter and jitter(s.args) or s.args)
                task.wait(SPREAD_GAP)
            end
        end)
    else
        for _ = 1, n do
            callRemote(s, doJitter and jitter(s.args) or s.args)
        end
    end
end

local function doBurstA()
    if not slots.A then flash("Slot A empty — spy an item take first") return end
    burst("A", spawnCount, false, burstMode == "spread")
    flash("Sent " .. spawnCount .. "x " .. slots.A.name)
    if autoPlace and slots.B then
        task.delay(0.7, function()
            if running then burst("B", spawnCount, true, true) end
        end)
    end
end

--=============================================================================
-- BUTTON CONNECTIONS
--=============================================================================
spyBtn.MouseButton1Click:Connect(function()
    spyEnabled = not spyEnabled
    spyBtn.Text = "Spy: " .. (spyEnabled and "ON" or "OFF")
    spyBtn.BackgroundColor3 = spyEnabled and Color3.fromRGB(50, 120, 60) or Color3.fromRGB(110, 50, 50)
    flash(spyEnabled and "Spy Active: Perform action now" or "Spy Paused")
end)

slotSwapBtn.MouseButton1Click:Connect(function()
    activeSlot = (activeSlot == "A") and "B" or "A"
    refreshSlots()
end)

grabBtn.MouseButton1Click:Connect(function()
    local last = logEntries[#logEntries]
    if last then grabEntry(last) else flash("Log empty") end
end)

burstBtn.MouseButton1Click:Connect(doBurstA)
scatterBtn.MouseButton1Click:Connect(function() burst("B", spawnCount, true, true) end)

autoPlaceBtn.MouseButton1Click:Connect(function()
    autoPlace = not autoPlace
    autoPlaceBtn.Text = "Auto-Place: " .. (autoPlace and "ON" or "OFF")
    autoPlaceBtn.BackgroundColor3 = autoPlace and Color3.fromRGB(60, 130, 80) or Color3.fromRGB(80, 50, 80)
end)

modeBtn.MouseButton1Click:Connect(function()
    burstMode = (burstMode == "burst") and "spread" or "burst"
    modeBtn.Text = "Mode: " .. burstMode:upper()
end)

originBtn.MouseButton1Click:Connect(function()
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if root then
        plotCenter = root.Position
        flash("Scatter origin locked to player")
    end
end)

clearLogBtn.MouseButton1Click:Connect(function()
    table.clear(logEntries)
    renderLog()
    flash("Log wiped")
end)

countBox.FocusLost:Connect(function()
    spawnCount = math.clamp(math.floor(tonumber(countBox.Text) or spawnCount), 1, 500)
    countBox.Text = tostring(spawnCount)
end)

radiusBox.FocusLost:Connect(function()
    radius = math.clamp(math.floor(tonumber(radiusBox.Text) or radius), 5, 300)
    radiusBox.Text = tostring(radius)
end)

--=============================================================================
-- KEYBOARD SHORTCUTS (Optional fallback for PC)
--=============================================================================
track(UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    local k = input.KeyCode
    if k == Enum.KeyCode.F1 then
        spyEnabled = not spyEnabled
        spyBtn.Text = "Spy: " .. (spyEnabled and "ON" or "OFF")
        spyBtn.BackgroundColor3 = spyEnabled and Color3.fromRGB(50, 120, 60) or Color3.fromRGB(110, 50, 50)
    elseif k == Enum.KeyCode.G then
        local last = logEntries[#logEntries]
        if last then grabEntry(last) end
    elseif k == Enum.KeyCode.H then
        activeSlot = (activeSlot == "A") and "B" or "A"
        refreshSlots()
    elseif k == Enum.KeyCode.B then
        doBurstA()
    elseif k == Enum.KeyCode.V then
        burst("B", spawnCount, true, true)
    end
end))

--=============================================================================
-- REFRESH LOOP
--=============================================================================
task.spawn(function()
    while running do
        task.wait(0.25)
        if not flashMsg then
            topStatusLbl.Text = spyEnabled and "Spying packets..." or "Idle (Spy OFF)"
        end
        if logDirty then
            logDirty = false
            renderLog()
        end
    end
end)

--=============================================================================
-- CLEANUP
--=============================================================================
getgenv().BloxburgDupeV2_Cleanup = function()
    running = false
    for _, c in ipairs(getgenv().BloxburgDupeV2_Conn) do
        if typeof(c) == "RBXScriptConnection" then c:Disconnect() end
    end
    table.clear(getgenv().BloxburgDupeV2_Conn)
    if hookInstalled and hookedMT and hookedOld then
        pcall(function()
            setreadonly(hookedMT, false)
            hookedMT.__namecall = hookedOld
            setreadonly(hookedMT, true)
        end)
    end
    if screenGui then screenGui:Destroy() end
    getgenv().BloxburgDupeV2_Cleanup = nil
end
