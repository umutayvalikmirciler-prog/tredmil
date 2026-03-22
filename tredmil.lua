local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local INTERVAL = 1

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
