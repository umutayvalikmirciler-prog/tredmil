local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local remoteEvent = ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteEvent")
local remotePayload = buffer.fromstring("\b\005\001")  -- built once, reused forever

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
    SOUND_ID        = "rbxassetid://138901491787668",
    SOUND_VOLUME    = 10,
    SLIDE_TIME      = 0.35,
    CARD_WIDTH      = 280,
    CARD_HEIGHT     = 80,
    CARD_PADDING    = 8,
}

local TIER_CLOSE  = 1
local TIER_MEDIUM = 2
local TIER_FAR    = 3

local TWEEN_SLIDE_IN  = TweenInfo.new(CFG.SLIDE_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TWEEN_SLIDE_OUT = TweenInfo.new(CFG.SLIDE_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.In)

local CARD_OFF = UDim2.new(0, CFG.CARD_WIDTH + 20, 0, 0)
local CARD_ON  = UDim2.new(0, 0, 0, 0)
local CARD_BG  = Color3.fromRGB(15, 15, 20)
local WHITE    = Color3.fromRGB(240, 240, 240)

local TIER_COLOR     = { CFG.COLOR_CLOSE, CFG.COLOR_MEDIUM, CFG.COLOR_FAR }
local TIER_SEL       = { CFG.SEL_CLOSE,   CFG.SEL_MEDIUM,   CFG.SEL_FAR   }
-- Pre-extract Color3 values from BrickColors so highlight updates never call .Color
local TIER_SEL_COLOR = { CFG.SEL_CLOSE.Color, CFG.SEL_MEDIUM.Color, CFG.SEL_FAR.Color }

-- ── DETECTOR GUI ──────────────────────────────────────────────────────────────

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name           = "NPCDetectorGui"
ScreenGui.ResetOnSpawn   = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent         = playerGui

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

-- ── STATE ─────────────────────────────────────────────────────────────────────

local tracked   = {}
local cardQueue = {}
local cardCount = 0

-- ── HELPERS ───────────────────────────────────────────────────────────────────

local function getRootPart(model)
    local p
    p = model:FindFirstChild("HumanoidRootPart")
    if p and p:IsA("BasePart") then return p end
    p = model:FindFirstChild("Torso")
    if p and p:IsA("BasePart") then return p end
    p = model:FindFirstChild("UpperTorso")
    if p and p:IsA("BasePart") then return p end
    return model:FindFirstChildWhichIsA("BasePart")
end

local cachedPlayerRoot = nil
LocalPlayer.CharacterAdded:Connect(function(char)
    cachedPlayerRoot = nil
    char:WaitForChild("HumanoidRootPart", 5)
    cachedPlayerRoot = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
end)
LocalPlayer.CharacterRemoving:Connect(function()
    cachedPlayerRoot = nil
end)
if LocalPlayer.Character then
    local char = LocalPlayer.Character
    cachedPlayerRoot = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
end

local function getDistance(npcRoot)
    if not cachedPlayerRoot or not npcRoot or not npcRoot.Parent then return math.huge end
    return (npcRoot.Position - cachedPlayerRoot.Position).Magnitude
end

local function getTier(dist)
    if dist <= CFG.CLOSE_DIST  then return TIER_CLOSE  end
    if dist <= CFG.MEDIUM_DIST then return TIER_MEDIUM end
    return TIER_FAR
end

local function isInsideAlive(model)
    local a = model.Parent
    while a and a ~= workspace do
        if a:IsA("Folder") and a.Name == "Alive" then return true end
        a = a.Parent
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

-- ── SOUND ─────────────────────────────────────────────────────────────────────

local function makeSound()
    if not CFG.PLAY_SOUND then return nil end
    local s = Instance.new("Sound")
    s.SoundId            = CFG.SOUND_ID
    s.Volume             = CFG.SOUND_VOLUME
    s.Looped             = true
    s.RollOffMaxDistance = 0
    s.Parent             = playerGui
    return s
end

local function startAlert(data)
    if CFG.PLAY_SOUND and data.sound then data.sound:Play() end
end

local function stopAlert(data)
    if data.sound then
        data.sound:Stop()
        data.sound:Destroy()
        data.sound = nil
    end
end

-- ── HIGHLIGHT ─────────────────────────────────────────────────────────────────

local function makeHighlight(model, tier)
    local col = TIER_SEL_COLOR[tier]
    local hl  = Instance.new("Highlight")
    hl.Adornee             = model
    hl.OutlineColor        = col
    hl.FillColor           = col
    hl.OutlineTransparency = 0
    hl.FillTransparency    = 0.65
    hl.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent              = model

    -- Static highlight — no pulse animation.
    -- Animating FillTransparency forces the renderer to redraw the depth pass
    -- every frame during the tween, which is the main source of GPU cost when
    -- many NPCs are highlighted at once. Static is dramatically cheaper.
    return hl
end

-- ── CARD UI ───────────────────────────────────────────────────────────────────

local function makeCard(model)
    local npcRoot = getRootPart(model)
    local dist    = getDistance(npcRoot)
    local tier    = getTier(dist)
    local col     = TIER_COLOR[tier]

    local card = Instance.new("Frame")
    card.Name             = "NPCCard_" .. model.Name
    card.Size             = UDim2.new(0, CFG.CARD_WIDTH, 0, CFG.CARD_HEIGHT)
    card.BackgroundColor3 = CARD_BG
    card.BorderSizePixel  = 0
    card.ClipsDescendants = false
    card.Position         = CARD_OFF
    card.Parent           = Container
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)

    local accent = Instance.new("Frame")
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
    nameLabel.TextColor3             = WHITE
    nameLabel.Font                   = Enum.Font.GothamBold
    nameLabel.TextSize               = 15
    nameLabel.TextXAlignment         = Enum.TextXAlignment.Left
    nameLabel.TextTruncate           = Enum.TextTruncate.AtEnd
    nameLabel.Parent                 = card

    local distLabel = Instance.new("TextLabel")
    distLabel.Size                   = UDim2.new(1, -80, 0, 20)
    distLabel.Position               = UDim2.new(0, 58, 0, 40)
    distLabel.BackgroundTransparency = 1
    distLabel.Text                   = string.format("Distance: %.1f m", dist)
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

    TweenService:Create(card, TWEEN_SLIDE_IN, { Position = CARD_ON }):Play()

    return card, distLabel, accent, icon, closeBtn
end

local function slideOut(card, cb)
    if not card or not card.Parent then
        if cb then cb() end
        return
    end
    local t = TweenService:Create(card, TWEEN_SLIDE_OUT, { Position = CARD_OFF })
    t:Play()
    t.Completed:Connect(function()
        if card.Parent then card:Destroy() end
        if cb then cb() end
    end)
end

-- ── QUEUE ─────────────────────────────────────────────────────────────────────

local promoteQueue

local function attachCard(model)
    if cardCount >= CFG.MAX_CARDS then return false end
    local data = tracked[model]
    if not data or data.card then return false end

    cardCount  = cardCount + 1
    data.sound = makeSound()
    startAlert(data)

    local card, distLabel, accent, icon, closeBtn = makeCard(model)
    data.card      = card
    data.distLabel = distLabel
    data.accent    = accent
    data.icon      = icon

    closeBtn.MouseButton1Click:Connect(function()
        stopAlert(data)
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
        local nxt = table.remove(cardQueue, 1)
        if nxt.Parent and tracked[nxt] and not tracked[nxt].card then
            attachCard(nxt)
        end
    end
end

-- ── NPC LIFECYCLE ─────────────────────────────────────────────────────────────

local function removeNPC(model)
    local data = tracked[model]
    if not data then return end
    tracked[model] = nil

    stopAlert(data)
    if data.conn      then data.conn:Disconnect() end
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
    local npcRoot = getRootPart(model)
    local tier    = getTier(getDistance(npcRoot))
    local conn    = model.AncestryChanged:Connect(function(_, newParent)
        if not newParent then removeNPC(model) end
    end)
    tracked[model] = {
        highlight = makeHighlight(model, tier),
        conn      = conn,
        npcRoot   = npcRoot,
        tier      = tier,
        hlTier    = tier,
        lastDist  = -1,  -- forces first distLabel write
    }
    if not attachCard(model) then
        table.insert(cardQueue, model)
    end
end

-- ── UPDATE LOOP ───────────────────────────────────────────────────────────────
-- Runs every DISTANCE_UPDATE seconds.
-- Skips silent-only entries (no card, no highlight).
-- Compares rounded integer distance to avoid redundant string allocs.
-- Only touches UI properties when tier or distance actually changed.

task.spawn(function()
    while true do
        task.wait(CFG.DISTANCE_UPDATE)
        for _, data in pairs(tracked) do
            local root = data.npcRoot
            if not root or not root.Parent then continue end
            if not data.card and not data.highlight then continue end

            local dist    = getDistance(root)
            local newTier = getTier(dist)

            -- Round to 1 decimal to avoid updating text every tick while standing still
            local roundedDist = math.floor(dist * 10 + 0.5)

            if newTier ~= data.tier then
                data.tier = newTier
                local col = TIER_COLOR[newTier]
                if data.distLabel then data.distLabel.TextColor3 = col end
                if data.accent    then data.accent.BackgroundColor3 = col end
                if data.icon      then data.icon.TextColor3 = col end
            end

            if data.distLabel and roundedDist ~= data.lastDist then
                data.lastDist = roundedDist
                data.distLabel.Text = string.format("Distance: %.1f m", dist)
            end

            if data.highlight and data.highlight.Parent and newTier ~= data.hlTier then
                data.hlTier = newTier
                local c = TIER_SEL_COLOR[newTier]
                data.highlight.OutlineColor = c
                data.highlight.FillColor    = c
            end
        end
    end
end)

-- ── SCANNER ───────────────────────────────────────────────────────────────────
-- Only attaches ChildAdded to Folders, not to every Model in the game.
-- For newly added Models that arrive before their Humanoid, we wait for
-- the Humanoid via a single ChildAdded connection that self-disconnects.

local setupContainer

local function onChildAdded(child)
    if child:IsA("Model") then
        if child:FindFirstChildOfClass("Humanoid") then
            if isNPC(child) then addNewNPC(child) end
        else
            local conn
            conn = child.ChildAdded:Connect(function(grandchild)
                if grandchild:IsA("Humanoid") then
                    conn:Disconnect()
                    conn = nil
                    task.defer(function()
                        if child.Parent and isNPC(child) then addNewNPC(child) end
                    end)
                end
            end)
            task.delay(10, function()
                if conn then conn:Disconnect() end
            end)
        end
    elseif child:IsA("Folder") then
        setupContainer(child)
    end
end

setupContainer = function(parent)
    parent.ChildAdded:Connect(onChildAdded)
    for _, child in ipairs(parent:GetChildren()) do
        if child:IsA("Model") and isNPC(child) then
            registerExisting(child)
    end
end

local npcFolder = workspace:WaitForChild("NPCs")
setupContainer(npcFolder)

Players.PlayerRemoving:Connect(function(p)
    if p ~= LocalPlayer then return end
    for _, data in pairs(tracked) do
        stopAlert(data)
        if data.conn      then data.conn:Disconnect() end
        if data.highlight and data.highlight.Parent then data.highlight:Destroy() end
    end
    tracked = {}
end)

-- ── MACHINE GUI ───────────────────────────────────────────────────────────────

local machineConfig = {
    { name = "Treadmill", folder = workspace.Machines.Treadmill },
    { name = "Curls",     folder = workspace.Machines.Curls     },
    { name = "Pullups",   folder = workspace.Machines.Pullups   },
}

local machineModels = {}
for _, cfg in ipairs(machineConfig) do
    local models = {}
    for _, child in ipairs(cfg.folder:GetChildren()) do
        if child:IsA("Model") then table.insert(models, child) end
    end
    machineModels[cfg.name] = models
end

local selectedIndex     = { Treadmill = 1, Curls = 1, Pullups = 1 }
local currentTarget     = nil
local currentHighlights = {}

local function clearHighlights()
    for _, h in ipairs(currentHighlights) do h:Destroy() end
    currentHighlights = {}
end

local function highlightModel(model)
    clearHighlights()
    local h = Instance.new("Highlight")
    h.Adornee             = model
    h.OutlineColor        = Color3.fromRGB(255, 215, 0)
    h.FillColor           = Color3.fromRGB(255, 215, 0)
    h.FillTransparency    = 0.85
    h.OutlineTransparency = 0
    h.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
    h.Parent              = workspace
    table.insert(currentHighlights, h)
end

local screenGui = Instance.new("ScreenGui")
screenGui.ResetOnSpawn   = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent         = playerGui

local frame = Instance.new("Frame")
frame.Size             = UDim2.new(0, 240, 0, 254)
frame.Position         = UDim2.new(0.5, -120, 0.5, -127)
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
titleLabel.Text                   = "ege denizi"
titleLabel.TextColor3             = Color3.fromRGB(200, 200, 255)
titleLabel.TextSize               = 13
titleLabel.Font                   = Enum.Font.GothamBold
titleLabel.TextXAlignment         = Enum.TextXAlignment.Left
titleLabel.Parent                 = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size             = UDim2.new(0, 24, 0, 24)
closeBtn.Position         = UDim2.new(1, -28, 0, 4)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
closeBtn.Text             = "X"
closeBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
closeBtn.TextSize         = 12
closeBtn.Font             = Enum.Font.GothamBold
closeBtn.BorderSizePixel  = 0
closeBtn.Parent           = titleBar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

local machineButtonsFrame = Instance.new("Frame")
machineButtonsFrame.Size                   = UDim2.new(1, -20, 0, 30)
machineButtonsFrame.Position               = UDim2.new(0, 10, 0, 40)
machineButtonsFrame.BackgroundTransparency = 1
machineButtonsFrame.Parent                 = frame

local machineLayout = Instance.new("UIListLayout")
machineLayout.FillDirection = Enum.FillDirection.Horizontal
machineLayout.Padding       = UDim.new(0, 6)
machineLayout.Parent        = machineButtonsFrame

local machineButtons      = {}
local machineButtonColors = {
    Treadmill = Color3.fromRGB(70, 130, 200),
    Curls     = Color3.fromRGB(160, 80, 200),
    Pullups   = Color3.fromRGB(200, 130, 40),
}
-- Pre-computed dimmed versions (used when a button is deselected)
local machineButtonDimmed = {
    Treadmill = Color3.fromRGB(35, 65, 100),
    Curls     = Color3.fromRGB(80, 40, 100),
    Pullups   = Color3.fromRGB(100, 65, 20),
}

for _, cfg in ipairs(machineConfig) do
    local btn = Instance.new("TextButton")
    btn.Size             = UDim2.new(0, 68, 1, 0)
    btn.BackgroundColor3 = machineButtonColors[cfg.name]
    btn.Text             = cfg.name
    btn.TextColor3       = Color3.fromRGB(255, 255, 255)
    btn.TextSize         = 11
    btn.Font             = Enum.Font.GothamBold
    btn.BorderSizePixel  = 0
    btn.Parent           = machineButtonsFrame
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 7)
    machineButtons[cfg.name] = btn

    btn.MouseButton1Click:Connect(function()
        for name, b in pairs(machineButtons) do
            b.BackgroundColor3 = machineButtonDimmed[name]
        end
        btn.BackgroundColor3 = machineButtonColors[cfg.name]
        local models = machineModels[cfg.name]
        if not models or #models == 0 then return end
        local idx = selectedIndex[cfg.name]
        if currentTarget and currentTarget == models[idx] then
            idx = (idx % #models) + 1
            selectedIndex[cfg.name] = idx
        end
        currentTarget = models[selectedIndex[cfg.name]]
        highlightModel(currentTarget)
        statusLabel.Text = cfg.name .. " #" .. selectedIndex[cfg.name] .. " / " .. #models
    end)
end

local statusLabel = Instance.new("TextLabel")
statusLabel.Size                   = UDim2.new(1, -20, 0, 20)
statusLabel.Position               = UDim2.new(0, 10, 0, 78)
statusLabel.BackgroundTransparency = 1
statusLabel.Text                   = "No machine selected"
statusLabel.TextColor3             = Color3.fromRGB(180, 180, 220)
statusLabel.TextSize               = 11
statusLabel.Font                   = Enum.Font.Gotham
statusLabel.TextXAlignment         = Enum.TextXAlignment.Center
statusLabel.Parent                 = frame

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size             = UDim2.new(1, -20, 0, 34)
toggleBtn.Position         = UDim2.new(0, 10, 0, 108)
toggleBtn.BackgroundColor3 = Color3.fromRGB(60, 180, 100)
toggleBtn.Text             = "Start"
toggleBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
toggleBtn.TextSize         = 13
toggleBtn.Font             = Enum.Font.GothamBold
toggleBtn.BorderSizePixel  = 0
toggleBtn.Parent           = frame
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 8)

local soundLabel = Instance.new("TextLabel")
soundLabel.Size                   = UDim2.new(1, -20, 0, 16)
soundLabel.Position               = UDim2.new(0, 10, 0, 150)
soundLabel.BackgroundTransparency = 1
soundLabel.Text                   = "Alert Sound ID"
soundLabel.TextColor3             = Color3.fromRGB(160, 160, 200)
soundLabel.TextSize               = 10
soundLabel.Font                   = Enum.Font.Gotham
soundLabel.TextXAlignment         = Enum.TextXAlignment.Left
soundLabel.Parent                 = frame

local soundRow = Instance.new("Frame")
soundRow.Size                   = UDim2.new(1, -20, 0, 28)
soundRow.Position               = UDim2.new(0, 10, 0, 168)
soundRow.BackgroundTransparency = 1
soundRow.Parent                 = frame

local soundBox = Instance.new("TextBox")
soundBox.Size              = UDim2.new(1, -70, 1, 0)
soundBox.BackgroundColor3  = Color3.fromRGB(30, 30, 42)
soundBox.BorderSizePixel   = 0
soundBox.PlaceholderText   = "rbxassetid://..."
soundBox.PlaceholderColor3 = Color3.fromRGB(100, 100, 130)
soundBox.Text              = ""
soundBox.TextColor3        = Color3.fromRGB(220, 220, 255)
soundBox.TextSize          = 10
soundBox.Font              = Enum.Font.Gotham
soundBox.ClearTextOnFocus  = false
soundBox.Parent            = soundRow
Instance.new("UICorner", soundBox).CornerRadius = UDim.new(0, 6)
local soundBoxStroke = Instance.new("UIStroke")
soundBoxStroke.Color     = Color3.fromRGB(80, 80, 120)
soundBoxStroke.Thickness = 1
soundBoxStroke.Parent    = soundBox

local applyBtn = Instance.new("TextButton")
applyBtn.Size             = UDim2.new(0, 60, 1, 0)
applyBtn.Position         = UDim2.new(1, -60, 0, 0)
applyBtn.BackgroundColor3 = Color3.fromRGB(70, 130, 200)
applyBtn.Text             = "Apply"
applyBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
applyBtn.TextSize         = 11
applyBtn.Font             = Enum.Font.GothamBold
applyBtn.BorderSizePixel  = 0
applyBtn.AutoButtonColor  = true
applyBtn.Parent           = soundRow
Instance.new("UICorner", applyBtn).CornerRadius = UDim.new(0, 6)

local soundFeedback = Instance.new("TextLabel")
soundFeedback.Size                   = UDim2.new(1, -20, 0, 14)
soundFeedback.Position               = UDim2.new(0, 10, 0, 200)
soundFeedback.BackgroundTransparency = 1
soundFeedback.Text                   = ""
soundFeedback.TextColor3             = Color3.fromRGB(100, 220, 120)
soundFeedback.TextSize               = 10
soundFeedback.Font                   = Enum.Font.Gotham
soundFeedback.TextXAlignment         = Enum.TextXAlignment.Center
soundFeedback.Parent                 = frame

local function applySoundID(raw)
    local trimmed = raw:match("^%s*(.-)%s*$")
    if trimmed == "" then return end
    local id = trimmed:match("^rbxassetid://(%d+)$") or trimmed:match("^(%d+)$")
    if not id then
        soundFeedback.TextColor3 = Color3.fromRGB(255, 100, 100)
        soundFeedback.Text = "Invalid ID"
        task.delay(2, function() soundFeedback.Text = "" end)
        return
    end
    CFG.SOUND_ID = "rbxassetid://" .. id
    for _, data in pairs(tracked) do
        if data.sound then data.sound.SoundId = CFG.SOUND_ID end
    end
    soundFeedback.TextColor3 = Color3.fromRGB(100, 220, 120)
    soundFeedback.Text = "Applied!"
    task.delay(2, function() soundFeedback.Text = "" end)
end

applyBtn.MouseButton1Click:Connect(function() applySoundID(soundBox.Text) end)
soundBox.FocusLost:Connect(function(enter) if enter then applySoundID(soundBox.Text) end end)

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

-- ── MACHINE LOOP ──────────────────────────────────────────────────────────────

local isRunning  = false
local loopThread = nil
local running    = false
local INTERVAL   = 1

local function stopLoop()
    isRunning = false
    running   = false
    if loopThread then task.cancel(loopThread); loopThread = nil end
    toggleBtn.Text             = "Start"
    toggleBtn.BackgroundColor3 = Color3.fromRGB(60, 180, 100)
end

local function walkTo(target)
    if not target then return end
    local character = LocalPlayer.Character
    local humanoid  = character and character:FindFirstChild("Humanoid")
    if not humanoid then return end
    local dest = target:GetPivot().Position
    humanoid:MoveTo(dest)

    -- MoveToFinished signal instead of a polling loop — fires exactly once,
    -- no per-frame task.wait() spam.
    local done    = false
    local finConn = humanoid.MoveToFinished:Connect(function()
        done = true
    end)
    local timeout = task.delay(8, function() done = true end)
    repeat task.wait(0.1) until done or not running
    finConn:Disconnect()
    task.cancel(timeout)
end

local function myCode()
    remoteEvent:FireServer(remotePayload)
    if currentTarget then walkTo(currentTarget) end
end

local function startLoop()
    if not currentTarget then
        statusLabel.Text       = "Pick a machine first!"
        statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
        task.delay(2, function()
            statusLabel.TextColor3 = Color3.fromRGB(180, 180, 220)
            statusLabel.Text       = "No machine selected"
        end)
        return
    end
    isRunning = true
    running   = true
    toggleBtn.Text             = "Stop"
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
