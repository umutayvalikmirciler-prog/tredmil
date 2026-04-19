local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local LocalPlayer   = Players.LocalPlayer
local remoteEvent   = ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteEvent")
local remotePayload = buffer.fromstring("\a\002\001")

local SEARCH_LIST = {"Black","Red","White","Gilbert"}
local TELEPORT_INTERVAL = 0.1

-- ── NOCLIP ────────────────────────────────────────────────────────────────────

local noclipEnabled = false
local noclipConn    = nil
local noclipParts = {}
        local function rebuildParts()
            noclipParts = {}
            local char = LocalPlayer.Character
            if not char then return end
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    table.insert(noclipParts, part)
                end
            end
        end
        rebuildParts()
        -- Rebuild on respawn
        LocalPlayer.CharacterAdded:Connect(function()
            task.wait()
            rebuildParts()
        end)
local function setNoclip(state)
    if state then
        -- Build a list of parts once, update it only when character changes
        
        noclipConn = RunService.Stepped:Connect(function()
            for _, part in ipairs(noclipParts) do
                if part.Parent then
                    part.CanCollide = false
                end
            end
        end)
    else
        if noclipConn then
            noclipConn:Disconnect()
            noclipConn = nil
        end
        local char = LocalPlayer.Character
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = true
                end
            end
        end
    end
end

LocalPlayer.CharacterAdded:Connect(function()
    if noclipEnabled then
        task.wait()
        setNoclip(true)
    end
end)

-- ── TELEPORT ──────────────────────────────────────────────────────────────────

local teleportEnabled = false
local loopThread      = nil

local function findBlackNPC()
    -- Check if current target is still valid
    if cachedNPCRoot and cachedNPCRoot.Parent and cachedNPCRoot.Parent.Parent then
        return cachedNPCRoot
    end
    
    cachedNPCRoot = nil
    
    -- Loop through everything in the workspace
    for _, obj in ipairs(workspace.Alive:GetDescendants()) do
        if obj:IsA("Model") then
            -- Check if the Model name starts with ANY of our prefixes
            local matchFound = false
            for _, prefix in ipairs(SEARCH_LIST) do
                if obj.Name:sub(1, #prefix) == prefix then
                    matchFound = true
                    break
                end
            end

            if matchFound then
                local root = obj:FindFirstChild("HumanoidRootPart") 
                    or obj:FindFirstChild("Torso") 
                    or obj:FindFirstChildWhichIsA("BasePart")
                
                if root then
                    cachedNPCRoot = root
                    return root
                end
            end
        end
    end
    return nil
end

local floatConn   = nil
local cachedNPCRoot = nil  -- cached so workspace scan only runs when needed

local function getHRP()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end


local teleportConn = nil -- We will use a connection instead of a task loop

local function startTeleport()
    teleportEnabled = true
    cachedNPCRoot = nil
    
    -- Disconnect any old connection just in case
    if teleportConn then teleportConn:Disconnect() end

    -- PreSimulation runs right before physics, making it the "snappiest" for teleports
    teleportConn = RunService.PreSimulation:Connect(function()
        if not teleportEnabled then return end
        
        local hrp = getHRP()
        local npcRoot = findBlackNPC()
        
        if hrp and npcRoot then
            -- Position update (Object Space)
            hrp.CFrame = npcRoot.CFrame * CFrame.new(0, -4, 2)
            
            -- Velocity kill
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
    end)

    -- Keep the remote firing on a separate slower loop to avoid lag/kicks
    loopThread = task.spawn(function()
        while teleportEnabled do
            remoteEvent:FireServer(remotePayload)
            task.wait(0.1) -- Keep the network traffic at 10Hz
        end
    end)
end

local function stopTeleport()
    teleportEnabled = false
    cachedNPCRoot = nil
    if teleportConn then
        teleportConn:Disconnect()
        teleportConn = nil
    end
    if loopThread then
        task.cancel(loopThread)
        loopThread = nil
    end
end

-- ── GUI ───────────────────────────────────────────────────────────────────────

local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "raid"
screenGui.ResetOnSpawn   = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent         = playerGui

-- Window is taller now to fit two buttons
local frame = Instance.new("Frame")
frame.Size             = UDim2.new(0, 200, 0, 132)
frame.AnchorPoint      = Vector2.new(0.5, 0)
frame.Position         = UDim2.new(0.5, 0, 0, 12)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
frame.BorderSizePixel  = 0
frame.Active           = true
frame.Parent           = screenGui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local frameStroke = Instance.new("UIStroke")
frameStroke.Color     = Color3.fromRGB(80, 80, 120)
frameStroke.Thickness = 1.5
frameStroke.Parent    = frame

local titleBar = Instance.new("Frame")
titleBar.Size             = UDim2.new(1, 0, 0, 32)
titleBar.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
titleBar.BorderSizePixel  = 0
titleBar.Parent           = frame
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

local titleFix = Instance.new("Frame")
titleFix.Size             = UDim2.new(1, 0, 0, 10)
titleFix.Position         = UDim2.new(0, 0, 1, -10)
titleFix.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
titleFix.BorderSizePixel  = 0
titleFix.Parent           = titleBar

local titleLabel = Instance.new("TextLabel")
titleLabel.Size                   = UDim2.new(1, -40, 1, 0)
titleLabel.Position               = UDim2.new(0, 10, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text                   = "raid şeysi i guess"
titleLabel.TextColor3             = Color3.fromRGB(200, 200, 255)
titleLabel.TextSize               = 13
titleLabel.Font                   = Enum.Font.GothamBold
titleLabel.TextXAlignment         = Enum.TextXAlignment.Left
titleLabel.Parent                 = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size             = UDim2.new(0, 24, 0, 24)
closeBtn.Position         = UDim2.new(1, -28, 0, 4)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
closeBtn.BorderSizePixel  = 0
closeBtn.Text             = "X"
closeBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
closeBtn.TextSize         = 12
closeBtn.Font             = Enum.Font.GothamBold
closeBtn.AutoButtonColor  = true
closeBtn.Parent           = titleBar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

-- Teleport toggle button
local teleportBtn = Instance.new("TextButton")
teleportBtn.Size             = UDim2.new(1, -20, 0, 34)
teleportBtn.Position         = UDim2.new(0, 10, 0, 42)
teleportBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
teleportBtn.BorderSizePixel  = 0
teleportBtn.Text             = "Teleport: OFF"
teleportBtn.TextColor3       = Color3.fromRGB(200, 200, 200)
teleportBtn.Font             = Enum.Font.GothamBold
teleportBtn.TextSize         = 13
teleportBtn.AutoButtonColor  = true
teleportBtn.Parent           = frame
Instance.new("UICorner", teleportBtn).CornerRadius = UDim.new(0, 8)

local teleportStroke = Instance.new("UIStroke")
teleportStroke.Color     = Color3.fromRGB(80, 80, 120)
teleportStroke.Thickness = 1.5
teleportStroke.Parent    = teleportBtn

-- Noclip toggle button
local noclipBtn = Instance.new("TextButton")
noclipBtn.Size             = UDim2.new(1, -20, 0, 34)
noclipBtn.Position         = UDim2.new(0, 10, 0, 86)
noclipBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
noclipBtn.BorderSizePixel  = 0
noclipBtn.Text             = "Noclip: OFF"
noclipBtn.TextColor3       = Color3.fromRGB(200, 200, 200)
noclipBtn.Font             = Enum.Font.GothamBold
noclipBtn.TextSize         = 13
noclipBtn.AutoButtonColor  = true
noclipBtn.Parent           = frame
Instance.new("UICorner", noclipBtn).CornerRadius = UDim.new(0, 8)

local noclipStroke = Instance.new("UIStroke")
noclipStroke.Color     = Color3.fromRGB(80, 80, 120)
noclipStroke.Thickness = 1.5
noclipStroke.Parent    = noclipBtn

local function updateTeleportBtn()
    if teleportEnabled then
        teleportBtn.Text             = "Teleport: ON"
        teleportBtn.BackgroundColor3 = Color3.fromRGB(50, 160, 80)
        teleportStroke.Color         = Color3.fromRGB(40, 200, 90)
    else
        teleportBtn.Text             = "Teleport: OFF"
        teleportBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
        teleportStroke.Color         = Color3.fromRGB(80, 80, 120)
    end
end

local function updateNoclipBtn()
    if noclipEnabled then
        noclipBtn.Text             = "Noclip: ON"
        noclipBtn.BackgroundColor3 = Color3.fromRGB(50, 160, 80)
        noclipStroke.Color         = Color3.fromRGB(40, 200, 90)
    else
        noclipBtn.Text             = "Noclip: OFF"
        noclipBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
        noclipStroke.Color         = Color3.fromRGB(80, 80, 120)
    end
end

teleportBtn.MouseButton1Click:Connect(function()
    if teleportEnabled then stopTeleport() else startTeleport() end
    updateTeleportBtn()
end)

noclipBtn.MouseButton1Click:Connect(function()
    noclipEnabled = not noclipEnabled
    setNoclip(noclipEnabled)
    updateNoclipBtn()
end)

closeBtn.MouseButton1Click:Connect(function()
    stopTeleport()
    noclipEnabled = false
    setNoclip(false)
    screenGui:Destroy()
end)

-- ── DRAGGING ──────────────────────────────────────────────────────────────────

local dragging, dragStart, startPos

titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging  = true
        dragStart = input.Position
        startPos  = frame.Position
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)
