--=============================================================================
--  WELCOME TO BLOXBURG  ·  SERVER-SIDE ITEM DUPLICATOR  (v2 — REMOTE REPLAY)
--=============================================================================
--  v1 used :Clone() locally      -> copies only existed on YOUR client.
--  v2 replays the game's remotes -> the SERVER creates the items, so they
--  replicate to everyone, are pick-up-able, edible and fridge-storable.
--
--  WORKFLOW:
--    1. Leave Spy ON. Play normally ~5s so the log fills with packets.
--    2. Take ONE item the normal way (click the tray / press the game's
--       own "Take" button). The exact packet lands in the log.
--    3. Press [G] -> grabs that packet into the ACTIVE SLOT (A by default).
--    4. Press [B] -> fires it N times inside ONE frame (packet flood).
--       The missing server mutex makes it spawn N real items.
--    5. Optional: move one item normally, grab that "place/move" packet into
--       Slot B, press [V] to scatter real items around you.
--
--  HOTKEYS: [F1] spy   [G] grab last -> active slot   [H] swap slot
--           [B] burst A   [V] burst B (scatter)   [N] auto-place
--           [P] plot center   [K] clear log   [M] burst/spread mode
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

local unpack          = table.unpack or unpack
local newcclosure     = newcclosure or function(f) return f end
local getnamecallmethod = getnamecallmethod or function() return nil end

-- settings ------------------------------------------------------------------
local spawnCount = 25
local radius     = 40
local activeSlot = "A"
local spyEnabled = true
local autoPlace  = false
local burstMode  = "burst"   -- "burst" | "spread"
local SPREAD_GAP = 0.03
local LOG_MAX    = 45
local running    = true
local plotCenter = nil

-- state ---------------------------------------------------------------------
local slots        = { A = nil, B = nil }
local registry     = {}
local registryOrder= {}
local logEntries   = {}
local logDirty     = false
local fireTotal    = 0
local suppress     = false   -- true while WE fire, keeps the log clean
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
            if n > 4 then parts[#parts + 1] = "..." break end
            parts[#parts + 1] = tostring(k) .. "=" .. describe(val, depth + 1)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return tostring(v)
end

local function argString(args)
    local parts = {}
    for i = 1, math.min(#args, 5) do
        parts[#parts + 1] = describe(args[i])
    end
    if #args > 5 then parts[#parts + 1] = "..." end
    local s = table.concat(parts, ", ")
    if #s > 58 then s = s:sub(1, 55) .. "..." end
    return s
end

--=============================================================================
-- PACKET RECORDER
--=============================================================================
local function recordFire(remote, args)
    fireTotal += 1

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
        remote = remote,
        args   = args,
        desc   = argString(args),
        n      = fireTotal,
    })
    if #logEntries > LOG_MAX then table.remove(logEntries, 1) end
    logDirty = true
end

--=============================================================================
-- NAMECALL HOOK
--=============================================================================
local hookInstalled = false
local hookedMT, hookedOld

hookInstalled = pcall(function()
    local mt  = getrawmetatable(game)
    local old = mt.__namecall
    hookedMT, hookedOld = mt, old

    setreadonly(mt, false)
    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        if not suppress and (method == "FireServer" or method == "InvokeServer") then
            if typeof(self) == "Instance" and self.ClassName ~= nil
                and (self.ClassName == "RemoteEvent"
                  or self.ClassName == "RemoteFunction"
                  or self.ClassName == "UnreliableRemoteEvent") then
                recordFire(self, { ... })
            end
        end
        return old(self, ...)
    end)
    setreadonly(mt, true)
end)

--=============================================================================
-- UI
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

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 250, 0, 384)
mainFrame.Position = UDim2.new(0.5, -125, 0.5, -192)
mainFrame.BackgroundColor3 = Color3.fromRGB(24, 26, 32)
mainFrame.BackgroundTransparency = 0.15
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 10)

local dragBar = Instance.new("Frame")
dragBar.Size = UDim2.new(1, 0, 0, 30)
dragBar.BackgroundColor3 = Color3.fromRGB(44, 48, 58)
dragBar.BorderSizePixel = 0
dragBar.Parent = mainFrame
Instance.new("UICorner", dragBar).CornerRadius = UDim.new(0, 10)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -40, 1, 0)
title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Text = "Bloxburg Dupe  v2  ·  SERVER"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextSize = 13
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = dragBar

local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Size = UDim2.new(0, 22, 0, 22)
minimizeBtn.Position = UDim2.new(1, -26, 0, 4)
minimizeBtn.BackgroundColor3 = Color3.fromRGB(255, 170, 0)
minimizeBtn.Text = "–"
minimizeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
minimizeBtn.TextSize = 16
minimizeBtn.Font = Enum.Font.GothamBold
minimizeBtn.ZIndex = 2
minimizeBtn.Parent = dragBar
Instance.new("UICorner", minimizeBtn).CornerRadius = UDim.new(0, 6)

-- generic dragger
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

local function label(text, y, h, color, size)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -20, 0, h)
    l.Position = UDim2.new(0, 10, 0, y)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = color or Color3.fromRGB(190, 195, 205)
    l.TextSize = size or 11
    l.Font = Enum.Font.Gotham
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextTruncate = Enum.TextTruncate.AtEnd
    l.Parent = mainFrame
    return l
end

local function button(text, y, h, color, size)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -20, 0, h)
    b.Position = UDim2.new(0, 10, 0, y)
    b.BackgroundColor3 = color
    b.Text = text
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.TextSize = size or 12
    b.Font = Enum.Font.GothamBold
    b.Parent = mainFrame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
    return b
end

local spyBtn     = button("Spy: ON  [F1]", 36, 22, Color3.fromRGB(50, 120, 60))
local topRemoteLbl = label("busiest remote: scanning...", 60, 14, Color3.fromRGB(150, 160, 175), 10)
local slotALbl   = label("Slot A (produce): empty", 76, 14, Color3.fromRGB(255, 200, 120), 10)
local slotBLbl   = label("Slot B (place): empty", 90, 14, Color3.fromRGB(150, 220, 255), 10)
local slotSwapBtn= button("Active Slot: A   [H]", 106, 20, Color3.fromRGB(70, 70, 90), 11)

-- count / radius row
local countLbl = label("N:", 130, 18, nil, 11)
countLbl.Size = UDim2.new(0, 16, 0, 18)
countLbl.Position = UDim2.new(0, 10, 0, 130)

local countBox = Instance.new("TextBox")
countBox.Size = UDim2.new(0, 42, 0, 18)
countBox.Position = UDim2.new(0, 28, 0, 130)
countBox.BackgroundColor3 = Color3.fromRGB(48, 52, 62)
countBox.Text = tostring(spawnCount)
countBox.TextColor3 = Color3.fromRGB(255, 255, 255)
countBox.TextSize = 11
countBox.Font = Enum.Font.Gotham
countBox.ClearTextOnFocus = false
countBox.Parent = mainFrame
Instance.new("UICorner", countBox).CornerRadius = UDim.new(0, 5)

local radiusLbl = label("scatter r:", 130, 18, nil, 11)
radiusLbl.Size = UDim2.new(0, 56, 0, 18)
radiusLbl.Position = UDim2.new(0, 84, 0, 130)

local radiusBox = Instance.new("TextBox")
radiusBox.Size = UDim2.new(0, 42, 0, 18)
radiusBox.Position = UDim2.new(0, 138, 0, 130)
radiusBox.BackgroundColor3 = Color3.fromRGB(48, 52, 62)
radiusBox.Text = tostring(radius)
radiusBox.TextColor3 = Color3.fromRGB(255, 255, 255)
radiusBox.TextSize = 11
radiusBox.Font = Enum.Font.Gotham
radiusBox.ClearTextOnFocus = false
radiusBox.Parent = mainFrame
Instance.new("UICorner", radiusBox).CornerRadius = UDim.new(0, 5)

local grabBtn    = button("Grab Last → Slot  [G]", 152, 24, Color3.fromRGB(70, 70, 90))
local burstBtn   = button("FLOOD  [B]", 180, 30, Color3.fromRGB(60, 165, 90), 14)
local scatterBtn = button("Scatter B  [V]", 214, 24, Color3.fromRGB(55, 110, 165))
local autoPlaceBtn = button("Auto-Place: OFF  [N]", 242, 20, Color3.fromRGB(90, 60, 90), 11)
local modeBtn    = button("Mode: BURST  [M]", 266, 20, Color3.fromRGB(80, 80, 80), 11)

local logFrame = Instance.new("ScrollingFrame")
logFrame.Size = UDim2.new(1, -20, 0, 84)
logFrame.Position = UDim2.new(0, 10, 0, 292)
logFrame.BackgroundColor3 = Color3.fromRGB(16, 18, 22)
logFrame.BackgroundTransparency = 0.3
logFrame.BorderSizePixel = 0
logFrame.ScrollBarThickness = 4
logFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
logFrame.Parent = mainFrame
Instance.new("UICorner", logFrame).CornerRadius = UDim.new(0, 6)

local restoreBtn = Instance.new("TextButton")
restoreBtn.Size = UDim2.new(0, 40, 0, 40)
restoreBtn.Position = mainFrame.Position
restoreBtn.BackgroundColor3 = Color3.fromRGB(24, 26, 32)
restoreBtn.Text = "D2"
restoreBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
restoreBtn.TextSize = 14
restoreBtn.Font = Enum.Font.GothamBold
restoreBtn.Visible = false
restoreBtn.Parent = screenGui
Instance.new("UICorner", restoreBtn).CornerRadius = UDim.new(0, 10)
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
-- FLASH / STATUS
--=============================================================================
local function flash(msg)
    flashToken += 1
    local my = flashToken
    flashMsg = msg
    topRemoteLbl.Text = msg
    topRemoteLbl.TextColor3 = Color3.fromRGB(255, 230, 140)
    task.delay(1.8, function()
        if flashToken == my then
            flashMsg = nil
            topRemoteLbl.TextColor3 = Color3.fromRGB(150, 160, 175)
        end
    end)
end

local function refreshSlots()
    slotALbl.Text = "Slot A (produce): " .. (slots.A and slots.A.name or "empty")
    slotBLbl.Text = "Slot B (place): "   .. (slots.B and slots.B.name or "empty")
    slotSwapBtn.Text = "Active Slot: " .. activeSlot .. "   [H]"
end
refreshSlots()

--=============================================================================
-- LOG RENDER
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
        b.Size = UDim2.new(1, -6, 0, 16)
        b.Position = UDim2.new(0, 2, 0, y)
        b.BackgroundColor3 = Color3.fromRGB(38, 42, 52)
        b.BackgroundTransparency = 0.35
        b.TextColor3 = Color3.fromRGB(170, 205, 255)
        b.TextSize = 10
        b.Font = Enum.Font.Code
        b.TextXAlignment = Enum.TextXAlignment.Left
        b.TextTruncate = Enum.TextTruncate.AtEnd
        b.Text = "[" .. e.n .. "] " .. e.remote.Name .. "(" .. e.desc .. ")"
        b.Parent = logFrame
        b.MouseButton1Click:Connect(function() grabEntry(e) end)
        y += 17
    end
    logFrame.CanvasSize = UDim2.new(0, 0, 0, y)
end

--=============================================================================
-- SLOT GRAB / REPLAY
--=============================================================================
grabEntry = function(e)
    slots[activeSlot] = {
        remote = e.remote,
        args   = deepCopy(e.args),
        name   = e.remote.Name,
        isFunc = (e.remote.ClassName == "RemoteFunction"),
    }
    refreshSlots()
    flash("Grabbed " .. e.remote.Name .. " → Slot " .. activeSlot)
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
        flash("Slot " .. slotId .. " empty — do the action with Spy ON, then [G]")
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
    if not slots.A then flash("Slot A empty — take an item with Spy ON, then [G]") return end
    burst("A", spawnCount, false, burstMode == "spread")
    flash("Flooded " .. spawnCount .. "x " .. slots.A.name)
    if autoPlace and slots.B then
        task.delay(0.7, function()
            if running then burst("B", spawnCount, true, true) end
        end)
    end
end

--=============================================================================
-- BUTTON WIRING
--=============================================================================
spyBtn.MouseButton1Click:Connect(function()
    spyEnabled = not spyEnabled
    spyBtn.Text = "Spy: " .. (spyEnabled and "ON" or "OFF") .. "  [F1]"
    spyBtn.BackgroundColor3 = spyEnabled and Color3.fromRGB(50, 120, 60) or Color3.fromRGB(120, 55, 55)
end)

slotSwapBtn.MouseButton1Click:Connect(function()
    activeSlot = (activeSlot == "A") and "B" or "A"
    refreshSlots()
end)

grabBtn.MouseButton1Click:Connect(function()
    local last = logEntries[#logEntries]
    if last then grabEntry(last) else flash("Log empty — play for a few seconds first") end
end)

burstBtn.MouseButton1Click:Connect(doBurstA)
scatterBtn.MouseButton1Click:Connect(function() burst("B", spawnCount, true, true) end)

autoPlaceBtn.MouseButton1Click:Connect(function()
    autoPlace = not autoPlace
    autoPlaceBtn.Text = "Auto-Place: " .. (autoPlace and "ON" or "OFF") .. "  [N]"
    autoPlaceBtn.BackgroundColor3 = autoPlace and Color3.fromRGB(70, 140, 90) or Color3.fromRGB(90, 60, 90)
end)

modeBtn.MouseButton1Click:Connect(function()
    burstMode = (burstMode == "burst") and "spread" or "burst"
    modeBtn.Text = "Mode: " .. burstMode:upper() .. "  [M]"
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
-- HOTKEYS
--=============================================================================
track(UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    local k = input.KeyCode
    if k == Enum.KeyCode.F1 then
        spyEnabled = not spyEnabled
        spyBtn.Text = "Spy: " .. (spyEnabled and "ON" or "OFF") .. "  [F1]"
        spyBtn.BackgroundColor3 = spyEnabled and Color3.fromRGB(50, 120, 60) or Color3.fromRGB(120, 55, 55)
    elseif k == Enum.KeyCode.G then
        local last = logEntries[#logEntries]
        if last then grabEntry(last) else flash("Log empty") end
    elseif k == Enum.KeyCode.H then
        activeSlot = (activeSlot == "A") and "B" or "A"
        refreshSlots()
    elseif k == Enum.KeyCode.B then
        doBurstA()
    elseif k == Enum.KeyCode.V then
        burst("B", spawnCount, true, true)
    elseif k == Enum.KeyCode.N then
        autoPlace = not autoPlace
        autoPlaceBtn.Text = "Auto-Place: " .. (autoPlace and "ON" or "OFF") .. "  [N]"
        autoPlaceBtn.BackgroundColor3 = autoPlace and Color3.fromRGB(70, 140, 90) or Color3.fromRGB(90, 60, 90)
    elseif k == Enum.KeyCode.M then
        burstMode = (burstMode == "burst") and "spread" or "burst"
        modeBtn.Text = "Mode: " .. burstMode:upper() .. "  [M]"
    elseif k == Enum.KeyCode.P then
        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then plotCenter = root.Position flash("Scatter origin set") end
    elseif k == Enum.KeyCode.K then
        table.clear(logEntries)
        renderLog()
        flash("Log cleared")
    end
end))

--=============================================================================
-- LIVE LOOP
--=============================================================================
task.spawn(function()
    while running do
        task.wait(0.25)

        if not flashMsg then
            local best, bc
            for _, e in ipairs(registryOrder) do
                if not bc or e.count > bc then best, bc = e, e.count end
            end
            topRemoteLbl.Text = "busiest: " .. (best and (best.remote.Name .. "  (" .. bc .. " fires)") or "—")
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
