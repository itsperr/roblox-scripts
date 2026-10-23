--=============================================================================
--  BLOXBURG DUPE  v3  ·  PACKET FINDER + REMOTE REPLAY
--=============================================================================
--  New in v3 (fixes log spam):
--    · Packets AGGREGATE by signature -> 500 identical fires = 1 row with xN
--    · Auto-mute: anything firing > 25/s is hidden automatically [U]
--    · RECORD WINDOW [R]: samples 1s of background chatter as a baseline,
--      then records 3s and shows ONLY packets that were not already firing.
--      -> press [R], then do the action. Your packet is the only new row.
--    · Freeze [F2], text filter box, live rate/s on every row
--
--  WORKFLOW:
--    1. Press [R]. Wait for "RECORDING" (takes 1s to baseline).
--    2. Do the action ONCE (take the cookie).
--    3. The new packet appears in the top CAPTURED box. Click it (or [G]).
--    4. [B] floods it. [H] swaps slot, [V] scatters with slot B.
--
--  HOTKEYS: [R] record  [F2] freeze  [U] mute noisy  [G] grab newest
--           [H] swap slot  [B] flood A  [V] scatter B  [N] auto-place
--           [M] burst/spread  [K] clear  [P] set scatter origin
--=============================================================================

if getgenv().BDupeV3_Cleanup then getgenv().BDupeV3_Cleanup() end
getgenv().BDupeV3_Conn = {}
local function track(c) table.insert(getgenv().BDupeV3_Conn, c) return c end

local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")
local player  = Players.LocalPlayer

local unpack            = table.unpack or unpack
local newcclosure       = newcclosure or function(f) return f end
local getnamecallmethod = getnamecallmethod or function() return nil end

-- tuning ---------------------------------------------------------------------
local BASELINE_SECONDS = 1.0
local RECORD_SECONDS   = 3.0
local MUTE_RATE        = 25      -- fires/sec above which a packet is auto-muted
local spawnCount       = 25
local radius           = 40

-- state ----------------------------------------------------------------------
local slots        = { A = nil, B = nil }
local activeSlot   = "A"
local activity     = {}          -- sig -> record
local activityList = {}
local captured     = {}          -- sig -> record
local baseline     = {}
local recording    = nil         -- nil | "baseline" | "capture"
local frozen       = false
local autoMute     = true
local spyEnabled   = true
local autoPlace    = false
local burstMode    = "burst"
local plotCenter   = nil
local running      = true
local suppress     = false
local filterText   = ""
local flashMsg, flashToken = nil, 0
local dirty = false

--=============================================================================
-- HELPERS
--=============================================================================
local function deepCopy(v, seen)
    if type(v) ~= "table" then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local out = {}; seen[v] = out
    for k, val in pairs(v) do out[deepCopy(k, seen)] = deepCopy(val, seen) end
    return out
end

local function describe(v, depth)
    depth = depth or 0
    local t = typeof(v)
    if t == "Instance" then return v.Name
    elseif t == "string" then return string.format("%q", v)
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
    for i = 1, math.min(#args, 5) do parts[#parts + 1] = describe(args[i]) end
    if #args > 5 then parts[#parts + 1] = "..." end
    local s = table.concat(parts, ", ")
    if #s > 52 then s = s:sub(1, 49) .. "..." end
    return s
end

-- coarse key: remote name + packet-name string + arg TYPES.
-- This is what makes aggregation and the baseline diff work.
local function signature(remote, args)
    local parts = { remote.Name }
    for i = 1, math.min(#args, 3) do
        local v  = args[i]
        local t  = typeof(v)
        if t == "string" then
            parts[#parts + 1] = "s:" .. v
        elseif t == "Instance" then
            parts[#parts + 1] = "i:" .. v.ClassName
        elseif t == "number" then
            parts[#parts + 1] = "n"
        else
            parts[#parts + 1] = t
        end
    end
    return table.concat(parts, "|")
end

--=============================================================================
-- RECORDER
--=============================================================================
local function recordFire(remote, args)
    local sig = signature(remote, args)

    if recording == "baseline" then
        baseline[sig] = true
    elseif recording == "capture" and not baseline[sig] then
        local c = captured[sig]
        if not c then
            c = { remote = remote, sig = sig, desc = argString(args), count = 0 }
            captured[sig] = c
        end
        c.count += 1
        c.last  = args
        c.t     = os.clock()
        dirty = true
    end

    local e = activity[sig]
    if not e then
        e = { remote = remote, sig = sig, desc = argString(args), count = 0, rate = 0 }
        activity[sig] = e
        table.insert(activityList, e)
    end
    e.count += 1
    e.last   = args
    e.lastT  = os.clock()
end

--=============================================================================
-- NAMECALL HOOK
--=============================================================================
local hookOK, hookedMT, hookedOld = pcall(function()
    local mt  = getrawmetatable(game)
    local old = mt.__namecall
    setreadonly(mt, false)
    mt.__namecall = newcclosure(function(self, ...)
        local m = getnamecallmethod()
        if spyEnabled and not suppress and (m == "FireServer" or m == "InvokeServer") then
            if typeof(self) == "Instance" and self.ClassName
                and (self.ClassName == "RemoteEvent"
                  or self.ClassName == "RemoteFunction"
                  or self.ClassName == "UnreliableRemoteEvent") then
                recordFire(self, { ... })
            end
        end
        return old(self, ...)
    end)
    setreadonly(mt, true)
    return mt, old
end)

--=============================================================================
-- UI
--=============================================================================
local playerGui = player:WaitForChild("PlayerGui")
local uiParent  = (typeof(gethui) == "function" and gethui()) or playerGui
for _, c in ipairs({ playerGui, uiParent }) do
    local old = c:FindFirstChild("BDupeV3UI"); if old then old:Destroy() end
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BDupeV3UI"
screenGui.ResetOnSpawn = false
screenGui.Parent = uiParent

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 262, 0, 430)
mainFrame.Position = UDim2.new(0.5, -131, 0.5, -215)
mainFrame.BackgroundColor3 = Color3.fromRGB(22, 24, 30)
mainFrame.BackgroundTransparency = 0.12
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 10)

local dragBar = Instance.new("Frame")
dragBar.Size = UDim2.new(1, 0, 0, 28)
dragBar.BackgroundColor3 = Color3.fromRGB(42, 46, 56)
dragBar.BorderSizePixel = 0
dragBar.Parent = mainFrame
Instance.new("UICorner", dragBar).CornerRadius = UDim.new(0, 10)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -40, 1, 0); title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Text = "Bloxburg Dupe v3 · PACKET FINDER"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextSize = 12; title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = dragBar

local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Size = UDim2.new(0, 22, 0, 22); minimizeBtn.Position = UDim2.new(1, -26, 0, 3)
minimizeBtn.BackgroundColor3 = Color3.fromRGB(255, 170, 0); minimizeBtn.Text = "–"
minimizeBtn.TextColor3 = Color3.fromRGB(255, 255, 255); minimizeBtn.TextSize = 16
minimizeBtn.Font = Enum.Font.GothamBold; minimizeBtn.ZIndex = 2; minimizeBtn.Parent = dragBar
Instance.new("UICorner", minimizeBtn).CornerRadius = UDim.new(0, 6)

local function makeDraggable(handle, target)
    local dragging, dragInput, dragStart, startPos, moved = false, nil, nil, nil, false
    track(handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging, moved = true, false
            dragStart = input.Position; startPos = target.Position
            track(input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end))
        end
    end))
    track(handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end
    end))
    track(UIS.InputChanged:Connect(function(input)
        if dragging and input == dragInput then
            local d = input.Position - dragStart
            if d.Magnitude > 4 then moved = true end
            target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                        startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
    return function() return moved end
end
makeDraggable(dragBar, mainFrame)

local function mkButton(text, x, y, w, h, color, size)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, w, 0, h); b.Position = UDim2.new(0, x, 0, y)
    b.BackgroundColor3 = color; b.Text = text
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.TextSize = size or 11; b.Font = Enum.Font.GothamBold
    b.Parent = mainFrame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    return b
end

local function mkLabel(text, y, h, color, size)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -20, 0, h); l.Position = UDim2.new(0, 10, 0, y)
    l.BackgroundTransparency = 1; l.Text = text
    l.TextColor3 = color or Color3.fromRGB(180, 185, 195)
    l.TextSize = size or 10; l.Font = Enum.Font.Gotham
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextTruncate = Enum.TextTruncate.AtEnd
    l.Parent = mainFrame
    return l
end

local recordBtn = mkButton("● RECORD 3s  [R]", 10, 32, 128, 22, Color3.fromRGB(150, 60, 60), 11)
local freezeBtn = mkButton("Freeze  [F2]", 144, 32, 108, 22, Color3.fromRGB(60, 70, 90), 11)

local filterBox = Instance.new("TextBox")
filterBox.Size = UDim2.new(1, -20, 0, 20); filterBox.Position = UDim2.new(0, 10, 0, 58)
filterBox.BackgroundColor3 = Color3.fromRGB(40, 44, 54)
filterBox.PlaceholderText = "filter... (type to narrow rows)"
filterBox.Text = ""; filterBox.TextColor3 = Color3.fromRGB(255, 255, 255)
filterBox.TextSize = 11; filterBox.Font = Enum.Font.Gotham
filterBox.ClearTextOnFocus = false; filterBox.Parent = mainFrame
Instance.new("UICorner", filterBox).CornerRadius = UDim.new(0, 5)

local recStatus = mkLabel("idle", 80, 14, Color3.fromRGB(255, 210, 130), 10)
local capHeader = mkLabel("▼ CAPTURED — new packets", 96, 13, Color3.fromRGB(120, 255, 160), 10)
local capFrame  = Instance.new("ScrollingFrame")
capFrame.Size = UDim2.new(1, -20, 0, 58); capFrame.Position = UDim2.new(0, 10, 0, 110)
capFrame.BackgroundColor3 = Color3.fromRGB(14, 18, 16); capFrame.BackgroundTransparency = 0.25
capFrame.BorderSizePixel = 0; capFrame.ScrollBarThickness = 4
capFrame.CanvasSize = UDim2.new(0, 0, 0, 0); capFrame.Parent = mainFrame
Instance.new("UICorner", capFrame).CornerRadius = UDim.new(0, 6)

local actHeader = mkLabel("▼ ACTIVITY — all packets (noise muted)", 172, 13,
    Color3.fromRGB(150, 190, 255), 10)
local actFrame  = Instance.new("ScrollingFrame")
actFrame.Size = UDim2.new(1, -20, 0, 74); actFrame.Position = UDim2.new(0, 10, 0, 186)
actFrame.BackgroundColor3 = Color3.fromRGB(14, 16, 22); actFrame.BackgroundTransparency = 0.25
actFrame.BorderSizePixel = 0; actFrame.ScrollBarThickness = 4
actFrame.CanvasSize = UDim2.new(0, 0, 0, 0); actFrame.Parent = mainFrame
Instance.new("UICorner", actFrame).CornerRadius = UDim.new(0, 6)

local slotALbl = mkLabel("Slot A: empty", 264, 13, Color3.fromRGB(255, 200, 120), 10)
local slotBLbl = mkLabel("Slot B: empty", 277, 13, Color3.fromRGB(150, 220, 255), 10)
local swapBtn  = mkButton("Active Slot: A  [H]", 10, 292, 242, 18, Color3.fromRGB(70, 70, 90), 10)

local countBox = Instance.new("TextBox")
countBox.Size = UDim2.new(0, 40, 0, 18); countBox.Position = UDim2.new(0, 28, 0, 314)
countBox.BackgroundColor3 = Color3.fromRGB(40, 44, 54); countBox.Text = tostring(spawnCount)
countBox.TextColor3 = Color3.fromRGB(255, 255, 255); countBox.TextSize = 11
countBox.Font = Enum.Font.Gotham; countBox.ClearTextOnFocus = false; countBox.Parent = mainFrame
Instance.new("UICorner", countBox).CornerRadius = UDim.new(0, 5)
local countLbl = mkLabel("N:", 314, 18); countLbl.Size = UDim2.new(0, 16, 0, 18)

local radiusBox = Instance.new("TextBox")
radiusBox.Size = UDim2.new(0, 40, 0, 18); radiusBox.Position = UDim2.new(0, 138, 0, 314)
radiusBox.BackgroundColor3 = Color3.fromRGB(40, 44, 54); radiusBox.Text = tostring(radius)
radiusBox.TextColor3 = Color3.fromRGB(255, 255, 255); radiusBox.TextSize = 11
radiusBox.Font = Enum.Font.Gotham; radiusBox.ClearTextOnFocus = false; radiusBox.Parent = mainFrame
Instance.new("UICorner", radiusBox).CornerRadius = UDim.new(0, 5)
local radiusLbl = mkLabel("scatter r:", 314, 18); radiusLbl.Size = UDim2.new(0, 56, 0, 18)
radiusLbl.Position = UDim2.new(0, 82, 0, 314)

local grabBtn    = mkButton("Grab newest → Slot  [G]", 10, 336, 242, 20, Color3.fromRGB(70, 70, 95))
local burstBtn   = mkButton("FLOOD SLOT A  [B]", 10, 360, 242, 28, Color3.fromRGB(55, 160, 90), 13)
local scatterBtn = mkButton("Scatter Slot B  [V]", 10, 392, 242, 20, Color3.fromRGB(50, 105, 160))
local autoPlaceBtn = mkButton("Auto-Place: OFF  [N]", 10, 416, 118, 16, Color3.fromRGB(85, 55, 85), 10)
local muteBtn      = mkButton("MuteNoise: ON  [U]", 134, 416, 118, 16, Color3.fromRGB(55, 95, 65), 10)

local restoreBtn = Instance.new("TextButton")
restoreBtn.Size = UDim2.new(0, 40, 0, 40); restoreBtn.Position = mainFrame.Position
restoreBtn.BackgroundColor3 = Color3.fromRGB(22, 24, 30); restoreBtn.Text = "D3"
restoreBtn.TextColor3 = Color3.fromRGB(255, 255, 255); restoreBtn.TextSize = 14
restoreBtn.Font = Enum.Font.GothamBold; restoreBtn.Visible = false; restoreBtn.Parent = screenGui
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
-- FLASH
--=============================================================================
local function flash(msg)
    flashToken += 1
    local my = flashToken
    flashMsg = msg
    recStatus.Text = msg
    recStatus.TextColor3 = Color3.fromRGB(255, 230, 140)
    task.delay(2.2, function()
        if flashToken == my then flashMsg = nil end
    end)
end

--=============================================================================
-- ROW RENDERING
--=============================================================================
local grabEntry

local function matches(e)
    if filterText ~= "" then
        local hay = (e.remote.Name .. " " .. (e.desc or "")):lower()
        if not hay:find(filterText:lower(), 1, true) then return false end
    end
    return true
end

local function renderInto(frame, list, isCaptured)
    for _, c in ipairs(frame:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end
    local y = 0
    for _, e in ipairs(list) do
        if matches(e) then
            local b = Instance.new("TextButton")
            b.Size = UDim2.new(1, -6, 0, 15); b.Position = UDim2.new(0, 2, 0, y)
            b.BackgroundColor3 = isCaptured and Color3.fromRGB(30, 60, 40)
                                              or Color3.fromRGB(36, 40, 50)
            b.BackgroundTransparency = 0.25
            b.TextColor3 = isCaptured and Color3.fromRGB(150, 255, 175)
                                         or Color3.fromRGB(165, 200, 250)
            b.TextSize = 9; b.Font = Enum.Font.Code
            b.TextXAlignment = Enum.TextXAlignment.Left
            b.TextTruncate = Enum.TextTruncate.AtEnd
            b.Text = (isCaptured and "[NEW] " or "")
                .. e.remote.Name .. "(" .. (e.desc or "") .. ")"
                .. (isCaptured and ("  x" .. e.count)
                    or (e.rate and string.format("  %.0f/s", e.rate) or ""))
            b.Parent = frame
            b.MouseButton1Click:Connect(function() grabEntry(e) end)
            y += 16
            if y > 400 then break end
        end
    end
    frame.CanvasSize = UDim2.new(0, 0, 0, y)
end

local function sortByRecency(t)
    local copy = {}
    for _, e in ipairs(t) do copy[#copy + 1] = e end
    table.sort(copy, function(a, b)
        return (a.t or a.lastT or 0) > (b.t or b.lastT or 0)
    end)
    return copy
end

local function rebuild()
    local capList = {}
    for _, e in ipairs(activityList) do end -- keep order stable
    local cap = {}
    for _, e in pairs(captured) do cap[#cap + 1] = e end
    renderInto(capFrame, sortByRecency(cap), true)

    local act = {}
    for _, e in ipairs(activityList) do
        if not (autoMute and (e.rate or 0) > MUTE_RATE) then act[#act + 1] = e end
    end
    renderInto(actFrame, sortByRecency(act), false)
end

--=============================================================================
-- SLOTS / REPLAY
--=============================================================================
grabEntry = function(e)
    slots[activeSlot] = {
        remote = e.remote, args = deepCopy(e.last or {}),
        name = e.remote.Name, isFunc = (e.remote.ClassName == "RemoteFunction"),
    }
    slotALbl.Text = "Slot A: " .. (slots.A and slots.A.name or "empty")
    slotBLbl.Text = "Slot B: " .. (slots.B and slots.B.name or "empty")
    flash("Grabbed " .. e.remote.Name .. " → Slot " .. activeSlot)
end

local function callRemote(s, args)
    suppress = true
    if s.isFunc then s.remote:InvokeServer(unpack(args))
    else s.remote:FireServer(unpack(args)) end
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
        else out[i] = v end
    end
    return out
end

local function burst(slotId, n, doJitter, spread)
    local s = slots[slotId]
    if not s then flash("Slot " .. slotId .. " empty — record, do action, [G]") return end
    n = n or spawnCount
    if spread then
        task.spawn(function()
            for _ = 1, n do
                if not running then break end
                callRemote(s, doJitter and jitter(s.args) or s.args)
                task.wait(0.03)
            end
        end)
    else
        for _ = 1, n do callRemote(s, doJitter and jitter(s.args) or s.args) end
    end
end

local function doFlood()
    if not slots.A then flash("Slot A empty") return end
    burst("A", spawnCount, false, burstMode == "spread")
    flash("Flooded " .. spawnCount .. "x " .. slots.A.name)
    if autoPlace and slots.B then
        task.delay(0.7, function() if running then burst("B", spawnCount, true, true) end end)
    end
end

--=============================================================================
-- RECORD WINDOW
--=============================================================================
local function startRecord()
    if recording then return end
    for k in pairs(captured) do captured[k] = nil end
    for k in pairs(baseline) do baseline[k] = nil end
    frozen = false
    recording = "baseline"
    rebuild()
    recStatus.Text = "sampling background..."
    recStatus.TextColor3 = Color3.fromRGB(255, 200, 120)

    task.spawn(function()
        task.wait(BASELINE_SECONDS)
        if not running then return end
        recording = "capture"
        recStatus.Text = "● RECORDING — do the action NOW"
        recStatus.TextColor3 = Color3.fromRGB(255, 90, 90)
        task.wait(RECORD_SECONDS)
        recording = nil
        frozen = true
        local n = 0
        for _ in pairs(captured) do n += 1 end
        if n == 0 then
            flash("No new packets — repeat the action, or press R again")
        else
            flash("Captured " .. n .. " new packet type(s) — click one")
        end
        rebuild()
    end)
end

--=============================================================================
-- BUTTONS
--=============================================================================
recordBtn.MouseButton1Click:Connect(startRecord)
freezeBtn.MouseButton1Click:Connect(function()
    frozen = not frozen
    freezeBtn.BackgroundColor3 = frozen and Color3.fromRGB(150, 110, 40) or Color3.fromRGB(60, 70, 90)
    freezeBtn.Text = frozen and "FROZEN  [F2]" or "Freeze  [F2]"
    if not frozen then rebuild() end
end)
swapBtn.MouseButton1Click:Connect(function()
    activeSlot = (activeSlot == "A") and "B" or "A"
    swapBtn.Text = "Active Slot: " .. activeSlot .. "  [H]"
end)
grabBtn.MouseButton1Click:Connect(function()
    local best, bt
    for _, e in pairs(captured) do
        if not bt or (e.t or 0) > bt then best, bt = e, e.t or 0 end
    end
    if not best then
        for _, e in ipairs(activityList) do
            if not bt or (e.lastT or 0) > bt then best, bt = e, e.lastT or 0 end
        end
    end
    if best then grabEntry(best) else flash("Nothing to grab yet") end
end)
burstBtn.MouseButton1Click:Connect(doFlood)
scatterBtn.MouseButton1Click:Connect(function() burst("B", spawnCount, true, true) end)
autoPlaceBtn.MouseButton1Click:Connect(function()
    autoPlace = not autoPlace
    autoPlaceBtn.Text = "Auto-Place: " .. (autoPlace and "ON" or "OFF") .. "  [N]"
    autoPlaceBtn.BackgroundColor3 = autoPlace and Color3.fromRGB(55, 130, 85) or Color3.fromRGB(85, 55, 85)
end)
muteBtn.MouseButton1Click:Connect(function()
    autoMute = not autoMute
    muteBtn.Text = "MuteNoise: " .. (autoMute and "ON" or "OFF") .. "  [U]"
    muteBtn.BackgroundColor3 = autoMute and Color3.fromRGB(55, 95, 65) or Color3.fromRGB(95, 65, 65)
    rebuild()
end)
filterBox.Changed:Connect(function(prop)
    if prop == "Text" then filterText = filterBox.Text; rebuild() end
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
    if gp or filterBox:IsFocused() then return end
    local k = input.KeyCode
    if k == Enum.KeyCode.R then startRecord()
    elseif k == Enum.KeyCode.F2 then
        frozen = not frozen
        freezeBtn.BackgroundColor3 = frozen and Color3.fromRGB(150, 110, 40) or Color3.fromRGB(60, 70, 90)
        freezeBtn.Text = frozen and "FROZEN  [F2]" or "Freeze  [F2]"
        if not frozen then rebuild() end
    elseif k == Enum.KeyCode.U then
        autoMute = not autoMute
        muteBtn.Text = "MuteNoise: " .. (autoMute and "ON" or "OFF") .. "  [U]"
        rebuild()
    elseif k == Enum.KeyCode.G then
        grabBtn.MouseButton1Click:Fire() -- reuse logic
    elseif k == Enum.KeyCode.H then
        activeSlot = (activeSlot == "A") and "B" or "A"
        swapBtn.Text = "Active Slot: " .. activeSlot .. "  [H]"
    elseif k == Enum.KeyCode.B then doFlood()
    elseif k == Enum.KeyCode.V then burst("B", spawnCount, true, true)
    elseif k == Enum.KeyCode.N then
        autoPlace = not autoPlace
        autoPlaceBtn.Text = "Auto-Place: " .. (autoPlace and "ON" or "OFF") .. "  [N]"
    elseif k == Enum.KeyCode.M then
        burstMode = (burstMode == "burst") and "spread" or "burst"
    elseif k == Enum.KeyCode.P then
        local ch = player.Character
        local root = ch and ch:FindFirstChild("HumanoidRootPart")
        if root then plotCenter = root.Position flash("Scatter origin set") end
    elseif k == Enum.KeyCode.K then
        for key in pairs(captured) do captured[key] = nil end
        for _, e in ipairs(activityList) do e.count = 0 end
        rebuild(); flash("Cleared")
    end
end))

--=============================================================================
-- LIVE LOOP (rate calc + throttled redraw)
--=============================================================================
task.spawn(function()
    local last = os.clock()
    while running do
        task.wait(0.3)
        local now = os.clock()
        local dt  = math.max(now - last, 0.001)
        last = now

        for _, e in ipairs(activityList) do
            local d = e.count - (e.prev or 0)
            e.prev = e.count
            e.rate = d / dt
        end

        if not flashMsg then
            recStatus.Text = recording == "capture" and "● RECORDING"
                or recording == "baseline" and "sampling..."
                or (frozen and "frozen — click a row to grab" or "idle · press [R]")
            recStatus.TextColor3 = recording and Color3.fromRGB(255, 120, 120)
                or Color3.fromRGB(150, 160, 175)
        end

        if not frozen then rebuild() end
    end
end)

--=============================================================================
-- CLEANUP
--=============================================================================
getgenv().BDupeV3_Cleanup = function()
    running = false
    for _, c in ipairs(getgenv().BDupeV3_Conn) do
        if typeof(c) == "RBXScriptConnection" then c:Disconnect() end
    end
    table.clear(getgenv().BDupeV3_Conn)
    if hookOK and hookedMT and hookedOld then
        pcall(function()
            setreadonly(hookedMT, false); hookedMT.__namecall = hookedOld; setreadonly(hookedMT, true)
        end)
    end
    if screenGui then screenGui:Destroy() end
    getgenv().BDupeV3_Cleanup = nil
end
