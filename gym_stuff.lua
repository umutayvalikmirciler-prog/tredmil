local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local INTERVAL = 1
local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local CFG = {
    DISTANCE_UPDATE = 0.5,
    MAX_CARDS       = 8,
    CLOSE_DIST      = 30,
    MEDIUM_DIST     = 80,
    COLOR_CLOSE     = Color3.fromRGB(255,  60,  60),
    COLOR_MEDIUM    = Color3.fromRGB(255, 200,  40),
    COLOR_FAR       = Color3.fromRGB( 60, 220, 100),
    SEL_CLOSE       = BrickColor.new("Bright red"),
    SEL_MEDIUM      = BrickColor.new("Bright yellow"),
    SEL_FAR         = BrickColor.new("Lime green"),
    PLAY_SOUND      = true,
    SOUND_ID        = "rbxassetid://4203251375",
    SOUND_VOLUME    = 1.5,
    SOUND_INTERVAL  = 2.5,
    SLIDE_TIME      = 0.35,
    CARD_WIDTH      = 280,
    CARD_HEIGHT     = 80,
    CARD_PADDING    = 8,
}

local LocalPlayer = Players.LocalPlayer

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name           = "NPCDetectorGui"
ScreenGui.ResetOnSpawn   = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent         = LocalPlayer:WaitForChild("PlayerGui")

local Container = Instance.new("Frame")
Container.Name                   = "CardContainer"
Container.BackgroundTransparency = 1
Container.AnchorPoint            = Vector2.new(1, 0)
Container.Position               = UDim2.new(1, -12, 0, 12)
Container.Size                   = UDim2.new(0, CFG.CARD_WIDTH, 1, -12)
Container.ClipsDescendants       = false
Container.Parent                 = ScreenGui

local Layout = Instance.new("UIListLayout")
Layout.SortOrder           = Enum.SortOrder.LayoutOrder
Layout.Padding             = UDim.new(0, CFG.CARD_PADDING)
Layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
Layout.VerticalAlignment   = Enum.VerticalAlignment.Top
Layout.Parent              = Container

local tracked   = {}
local cardQueue = {}
local cardCount = 0

local function getRootPart(model)
    local function validPart(name)
        local p = model:FindFirstChild(name)
        return (p and p:IsA("BasePart")) and p or nil
    end
    return validPart("HumanoidRootPart")
        or validPart("Torso")
        or validPart("UpperTorso")
        or model:FindFirstChildWhichIsA("BasePart")
end

local function getPlayerRoot()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
end

local function distanceTo(npcRoot)
    local myRoot = getPlayerRoot()
    if not myRoot or not npcRoot or not npcRoot.Parent then return math.huge end
    return (npcRoot.Position - myRoot.Position).Magnitude
end

local function dangerColor(dist)
    if dist <= CFG.CLOSE_DIST  then return CFG.COLOR_CLOSE,  CFG.SEL_CLOSE  end
    if dist <= CFG.MEDIUM_DIST then return CFG.COLOR_MEDIUM, CFG.SEL_MEDIUM end
    return CFG.COLOR_FAR, CFG.SEL_FAR
end

local function fmt(d)
    return d == math.huge and "?" or string.format("%.1f m", d)
end

local function isInsideAlive(model)
    local ancestor = model.Parent
    while ancestor and ancestor ~= workspace do
        if ancestor:IsA("Folder") and ancestor.Name == "Alive" then
            return true
        end
        ancestor = ancestor.Parent
    end
    return false
end

local function isNPC(model)
    if not model:IsA("Model") then return false end
    if not model:FindFirstChildOfClass("Humanoid") then return false end
    if not getRootPart(model) then return false end
    if model == LocalPlayer.Character then return false end
    if isInsideAlive(model) then return false end
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character == model then return false end
    end
    return true
end

local function makeSound()
    if not CFG.PLAY_SOUND then return nil end
    local s = Instance.new("Sound")
    s.SoundId            = CFG.SOUND_ID
    s.Volume             = CFG.SOUND_VOLUME
    s.RollOffMaxDistance = 0
    s.Parent             = LocalPlayer.PlayerGui
    return s
end

local function startAlertLoop(data)
    if not CFG.PLAY_SOUND then return end
    data.alertActive = true
    task.spawn(function()
        while data.alertActive do
            if data.sound then
                data.sound:Play()
            end
            task.wait(CFG.SOUND_INTERVAL)
        end
        if data.sound then
            data.sound:Stop()
        end
    end)
end

local function stopAlertLoop(data)
    data.alertActive = false
    if data.sound then
        data.sound:Stop()
        data.sound:Destroy()
        data.sound = nil
    end
end

local function makeHighlight(model, selColor)
    local hl = Instance.new("Highlight")
    hl.Adornee             = model
    hl.OutlineColor        = selColor.Color
    hl.FillColor           = selColor.Color
    hl.OutlineTransparency = 0
    hl.FillTransparency    = 0.65
    hl.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent              = model

    task.spawn(function()
        while hl.Parent do
            local tweenIn = TweenService:Create(hl,
                TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                { FillTransparency = 0.35 })
            local tweenOut = TweenService:Create(hl,
                TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                { FillTransparency = 0.65 })
            tweenIn:Play()
            tweenIn.Completed:Connect(function()
                if hl.Parent then tweenOut:Play() end
            end)
            task.wait(1.4)
        end
    end)

    return hl
end

local function makeCard(model)
    local npcRoot = getRootPart(model)
    local dist    = distanceTo(npcRoot)
    local col, _  = dangerColor(dist)

    local card = Instance.new("Frame")
    card.Name             = "NPCCard_" .. model.Name
    card.Size             = UDim2.new(0, CFG.CARD_WIDTH, 0, CFG.CARD_HEIGHT)
    card.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
    card.BorderSizePixel  = 0
    card.ClipsDescendants = false
    card.Position         = UDim2.new(0, CFG.CARD_WIDTH + 20, 0, 0)
    card.Parent           = Container
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)

    local accent = Instance.new("Frame")
    accent.Name             = "Accent"
    accent.Size             = UDim2.new(0, 5, 1, 0)
    accent.BackgroundColor3 = col
    accent.BorderSizePixel  = 0
    accent.Parent           = card
    Instance.new("UICorner", accent).CornerRadius = UDim.new(0, 10)

    local icon = Instance.new("TextLabel")
    icon.Size                   = UDim2.new(0, 36, 0, 36)
    icon.Position               = UDim2.new(0, 14, 0.5, -18)
    icon.BackgroundTransparency = 1
    icon.Text                   = "!"
    icon.TextColor3             = col
    icon.Font                   = Enum.Font.GothamBold
    icon.TextSize               = 26
    icon.TextXAlignment         = Enum.TextXAlignment.Center
    icon.Parent                 = card

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size                   = UDim2.new(1, -80, 0, 26)
    nameLabel.Position               = UDim2.new(0, 58, 0, 12)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text                   = model.Name
    nameLabel.TextColor3             = Color3.fromRGB(240, 240, 240)
    nameLabel.Font                   = Enum.Font.GothamBold
    nameLabel.TextSize               = 15
    nameLabel.TextXAlignment         = Enum.TextXAlignment.Left
    nameLabel.TextTruncate           = Enum.TextTruncate.AtEnd
    nameLabel.Parent                 = card

    local distLabel = Instance.new("TextLabel")
    distLabel.Name                   = "DistLabel"
    distLabel.Size                   = UDim2.new(1, -80, 0, 20)
    distLabel.Position               = UDim2.new(0, 58, 0, 40)
    distLabel.BackgroundTransparency = 1
    distLabel.Text                   = "Distance: " .. fmt(dist)
    distLabel.TextColor3             = col
    distLabel.Font                   = Enum.Font.Gotham
    distLabel.TextSize               = 13
    distLabel.TextXAlignment         = Enum.TextXAlignment.Left
    distLabel.Parent                 = card

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size             = UDim2.new(0, 26, 0, 26)
    closeBtn.Position         = UDim2.new(1, -32, 0, 8)
    closeBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
    closeBtn.BorderSizePixel  = 0
    closeBtn.Text             = "x"
    closeBtn.TextColor3       = Color3.fromRGB(180, 180, 180)
    closeBtn.Font             = Enum.Font.GothamBold
    closeBtn.TextSize         = 14
    closeBtn.AutoButtonColor  = true
    closeBtn.Parent           = card
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

    TweenService:Create(card,
        TweenInfo.new(CFG.SLIDE_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        { Position = UDim2.new(0, 0, 0, 0) }):Play()

    return card, distLabel, accent, icon, closeBtn
end

local function slideOut(card, cb)
    if not card or not card.Parent then
        if cb then cb() end
        return
    end
    TweenService:Create(card,
        TweenInfo.new(CFG.SLIDE_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.In),
        { Position = UDim2.new(0, CFG.CARD_WIDTH + 20, 0, 0) }):Play()
    task.delay(CFG.SLIDE_TIME + 0.05, function()
        if card and card.Parent then card:Destroy() end
        if cb then cb() end
    end)
end

local promoteQueue

local function attachCard(model)
    if cardCount >= CFG.MAX_CARDS then return false end
    local data = tracked[model]
    if not data or data.card then return false end

    cardCount  = cardCount + 1
    data.sound = makeSound()
    startAlertLoop(data)

    local card, distLabel, accent, icon, closeBtn = makeCard(model)
    data.card      = card
    data.distLabel = distLabel
    data.accent    = accent
    data.icon      = icon

    closeBtn.MouseButton1Click:Connect(function()
        stopAlertLoop(data)
        slideOut(card)
        cardCount      = cardCount - 1
        data.card      = nil
        data.distLabel = nil
        data.accent    = nil
        data.icon      = nil
        promoteQueue()
    end)

    return true
end

promoteQueue = function()
    while #cardQueue > 0 and cardCount < CFG.MAX_CARDS do
        local next = table.remove(cardQueue, 1)
        if next.Parent and tracked[next] and not tracked[next].card then
            attachCard(next)
        end
    end
end

local function removeNPC(model)
    local data = tracked[model]
    if not data then return end
    tracked[model] = nil

    stopAlertLoop(data)

    if data.conn then data.conn:Disconnect() end
    if data.highlight and data.highlight.Parent then data.highlight:Destroy() end

    if data.card then
        cardCount = cardCount - 1
        slideOut(data.card, promoteQueue)
    end

    for i = #cardQueue, 1, -1 do
        if cardQueue[i] == model then table.remove(cardQueue, i) end
    end
end

local function registerExisting(model)
    if tracked[model] then return end
    local conn = model.AncestryChanged:Connect(function(_, newParent)
        if not newParent then removeNPC(model) end
    end)
    tracked[model] = { conn = conn, npcRoot = getRootPart(model) }
end

local function addNewNPC(model)
    if tracked[model] then return end

    local npcRoot   = getRootPart(model)
    local dist      = distanceTo(npcRoot)
    local _, selCol = dangerColor(dist)

    local conn = model.AncestryChanged:Connect(function(_, newParent)
        if not newParent then removeNPC(model) end
    end)

    tracked[model] = {
        highlight = makeHighlight(model, selCol),
        conn      = conn,
        npcRoot   = npcRoot,
    }

    if not attachCard(model) then
        table.insert(cardQueue, model)
    end
end

task.spawn(function()
    while true do
        task.wait(CFG.DISTANCE_UPDATE)
        for model, data in pairs(tracked) do
            local root = data.npcRoot
            if not root or not root.Parent then continue end

            local dist        = distanceTo(root)
            local col, selCol = dangerColor(dist)

            if data.distLabel and data.distLabel.Parent then
                data.distLabel.Text       = "Distance: " .. fmt(dist)
                data.distLabel.TextColor3 = col
            end
            if data.accent and data.accent.Parent then
                data.accent.BackgroundColor3 = col
            end
            if data.icon and data.icon.Parent then
                data.icon.TextColor3 = col
            end
            if data.highlight and data.highlight.Parent then
                data.highlight.OutlineColor = selCol.Color
                data.highlight.FillColor    = selCol.Color
            end
        end
    end
end)

local function silentScan(parent)
    for _, child in ipairs(parent:GetChildren()) do
        if child:IsA("Model") and isNPC(child) then
            registerExisting(child)
        end
        if child:IsA("Folder") or child:IsA("Model") then
            silentScan(child)
        end
    end
end

local function watchContainer(container)
    container.ChildAdded:Connect(function(child)
        task.wait()
        if child:IsA("Model") and isNPC(child) then
            addNewNPC(child)
        end
        if child:IsA("Folder") or child:IsA("Model") then
            watchContainer(child)
            silentScan(child)
        end
    end)
end

silentScan(workspace)
watchContainer(workspace)

Players.PlayerRemoving:Connect(function(p)
    if p ~= LocalPlayer then return end
    for _, data in pairs(tracked) do
        stopAlertLoop(data)
        if data.conn then data.conn:Disconnect() end
        if data.highlight and data.highlight.Parent then data.highlight:Destroy() end
    end
    tracked = {}
end)
local machineConfig = {
	{ name = "Treadmill", folder = workspace.Machines.Treadmill },
	{ name = "Curls",     folder = workspace.Machines.Curls     },
	{ name = "Pullups",   folder = workspace.Machines.Pullups   },
}

local machineModels = {}
for _, cfg in ipairs(machineConfig) do
	local models = {}
	for _, child in ipairs(cfg.folder:GetChildren()) do
		if child:IsA("Model") then
			table.insert(models, child)
		end
	end
	machineModels[cfg.name] = models
end

local selectedIndex = { Treadmill = 1, Curls = 1, Pullups = 1 }
local currentTarget = nil
local currentHighlights = {}

local function clearHighlights()
	for _, h in ipairs(currentHighlights) do
		h:Destroy()
	end
	currentHighlights = {}
end

local function highlightModel(model)
	clearHighlights()
	local h = Instance.new("Highlight")
	h.Adornee = model
	h.OutlineColor = Color3.fromRGB(255, 215, 0)
	h.FillColor = Color3.fromRGB(255, 215, 0)
	h.FillTransparency = 0.85
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop 
	h.Parent = workspace
	table.insert(currentHighlights, h)
end

local function selectMachine(machineName)
	local models = machineModels[machineName]
	if not models or #models == 0 then return end

	-- Cycle index with wrap-around
	local idx = selectedIndex[machineName]
	if currentTarget and machineModels[machineName][idx] == currentTarget then
		idx = (idx % #models) + 1
		selectedIndex[machineName] = idx
	end

	currentTarget = models[selectedIndex[machineName]]
	highlightModel(currentTarget)
end

local screenGui = Instance.new("ScreenGui")
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 240, 0, 210)
frame.Position = UDim2.new(0.5, -120, 0.5, -105)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = screenGui

local frameCorner = Instance.new("UICorner")
frameCorner.CornerRadius = UDim.new(0, 10)
frameCorner.Parent = frame

local frameStroke = Instance.new("UIStroke")
frameStroke.Color = Color3.fromRGB(80, 80, 120)
frameStroke.Thickness = 1.5
frameStroke.Parent = frame

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 32)
titleBar.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
titleBar.BorderSizePixel = 0
titleBar.Parent = frame

local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0, 10)
titleCorner.Parent = titleBar

local titleFix = Instance.new("Frame")
titleFix.Size = UDim2.new(1, 0, 0, 10)
titleFix.Position = UDim2.new(0, 0, 1, -10)
titleFix.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
titleFix.BorderSizePixel = 0
titleFix.Parent = titleBar

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -40, 1, 0)
titleLabel.Position = UDim2.new(0, 10, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "ege denizi"
titleLabel.TextColor3 = Color3.fromRGB(200, 200, 255)
titleLabel.TextSize = 13
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 24, 0, 24)
closeBtn.Position = UDim2.new(1, -28, 0, 4)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.TextSize = 12
closeBtn.Font = Enum.Font.GothamBold
closeBtn.BorderSizePixel = 0
closeBtn.Parent = titleBar

local closeBtnCorner = Instance.new("UICorner")
closeBtnCorner.CornerRadius = UDim.new(0, 6)
closeBtnCorner.Parent = closeBtn

-- Machine selector buttons (3 buttons side by side)
local machineButtonsFrame = Instance.new("Frame")
machineButtonsFrame.Size = UDim2.new(1, -20, 0, 30)
machineButtonsFrame.Position = UDim2.new(0, 10, 0, 40)
machineButtonsFrame.BackgroundTransparency = 1
machineButtonsFrame.Parent = frame

local machineLayout = Instance.new("UIListLayout")
machineLayout.FillDirection = Enum.FillDirection.Horizontal
machineLayout.Padding = UDim.new(0, 6)
machineLayout.Parent = machineButtonsFrame

local machineButtons = {}
local machineButtonColors = {
	Treadmill = Color3.fromRGB(70, 130, 200),
	Curls     = Color3.fromRGB(160, 80, 200),
	Pullups   = Color3.fromRGB(200, 130, 40),
}

for _, cfg in ipairs(machineConfig) do
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 68, 1, 0)
	btn.BackgroundColor3 = machineButtonColors[cfg.name]
	btn.Text = cfg.name
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextSize = 11
	btn.Font = Enum.Font.GothamBold
	btn.BorderSizePixel = 0
	btn.Parent = machineButtonsFrame

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 7)
	btnCorner.Parent = btn

	machineButtons[cfg.name] = btn

	btn.MouseButton1Click:Connect(function()
		for name, b in pairs(machineButtons) do
			b.BackgroundColor3 = Color3.fromRGB(
				machineButtonColors[name].R * 255 * 0.5,
				machineButtonColors[name].G * 255 * 0.5,
				machineButtonColors[name].B * 255 * 0.5
			)
		end
		btn.BackgroundColor3 = machineButtonColors[cfg.name]

		-- Cycle to next model of this machine
		local models = machineModels[cfg.name]
		if not models or #models == 0 then return end
		local idx = selectedIndex[cfg.name]
		-- If this machine is already the current target, advance index
		if currentTarget and currentTarget == models[idx] then
			idx = (idx % #models) + 1
			selectedIndex[cfg.name] = idx
		end
		currentTarget = models[selectedIndex[cfg.name]]
		highlightModel(currentTarget)
	end)
end

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -20, 0, 20)
statusLabel.Position = UDim2.new(0, 10, 0, 78)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "No machine selected"
statusLabel.TextColor3 = Color3.fromRGB(180, 180, 220)
statusLabel.TextSize = 11
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextXAlignment = Enum.TextXAlignment.Center
statusLabel.Parent = frame

local function updateStatus()
	if currentTarget then
		local machineName = currentTarget.Parent.Name
		local idx = selectedIndex[machineName]
		local total = #machineModels[machineName]
		statusLabel.Text = machineName .. " #" .. idx .. " / " .. total
	else
		statusLabel.Text = "No machine selected"
	end
end

-- Wrap highlightModel to also update status
local _origHighlight = highlightModel
highlightModel = function(model)
	_origHighlight(model)
	updateStatus()
end

-- Start/Stop toggle button
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(1, -20, 0, 34)
toggleBtn.Position = UDim2.new(0, 10, 0, 108)
toggleBtn.BackgroundColor3 = Color3.fromRGB(60, 180, 100)
toggleBtn.Text = "Start"
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.TextSize = 13
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.BorderSizePixel = 0
toggleBtn.Parent = frame

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 8)
toggleCorner.Parent = toggleBtn

-- Dragging
local dragging, dragStart, startPos

titleBar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = true
		dragStart = input.Position
		startPos = frame.Position
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
		local delta = input.Position - dragStart
		frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = false
	end
end)

local isRunning = false
local loopThread
local running = false

local function stopLoop()
	isRunning = false
	running = false
	if loopThread then
		task.cancel(loopThread)
		loopThread = nil
	end
	toggleBtn.Text = "Start"
	toggleBtn.BackgroundColor3 = Color3.fromRGB(60, 180, 100)
end

local LocalPlayer = game.Players.LocalPlayer

local function walkTo(target)
	if not target then return end
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChild("Humanoid")
	if not humanoid then return end

	local destination = target:GetPivot().Position
	humanoid:MoveTo(destination)

	repeat
		task.wait(0.1)
		humanoid:MoveTo(destination)
	until (character.HumanoidRootPart.Position - destination).Magnitude < 3 or not running
end

local function myCode()
	local args = {
		buffer.fromstring("\b\005\001")
	}
	game:GetService("ReplicatedStorage"):WaitForChild("Network"):WaitForChild("RemoteEvent"):FireServer(unpack(args))
	if currentTarget then
		walkTo(currentTarget)
	end
end

local function startLoop()
	if not currentTarget then
		statusLabel.Text = "Pick a machine first!"
		statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
		task.delay(2, function()
			statusLabel.TextColor3 = Color3.fromRGB(180, 180, 220)
			updateStatus()
		end)
		return
	end
	isRunning = true
	running = true
	toggleBtn.Text = "Stop"
	toggleBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	loopThread = task.spawn(function()
		while isRunning do
			myCode()
			task.wait(INTERVAL)
		end
	end)
end

toggleBtn.MouseButton1Click:Connect(function()
	if isRunning then stopLoop() else startLoop() end
end)

closeBtn.MouseButton1Click:Connect(function()
	stopLoop()
	clearHighlights()
	screenGui:Destroy()
end)
