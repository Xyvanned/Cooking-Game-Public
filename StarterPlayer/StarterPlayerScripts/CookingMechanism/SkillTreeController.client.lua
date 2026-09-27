-- Skill Tree behavior: wires up the REAL, hand-placed UI built in
-- StarterGui.SkillTreeGui (Studio-navigable, not runtime-generated) -
-- the tree's structure (nodes, connectors, panel, sizing) is all real,
-- persistent instances. The only things generated at runtime here are
-- the galaxy star particles, constellation pop-ups, and short-lived
-- one-off click ripples - all inherently dynamic/transient by nature.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SkillConfig = require(ReplicatedStorage.CookingMechanism.Configs.SkillConfig)
local Remotes = ReplicatedStorage.CookingMechanism.Remotes
local TweenUtil = require(script.Parent.Modules.TweenUtil)
local PanelManager = require(script.Parent.Modules.PanelManager)

local cmGui = playerGui:WaitForChild("CookingMechanismGui")
local optionToggles = cmGui:WaitForChild("OptionSelectionToggles")
local skillTreeBtn = optionToggles:WaitForChild("SkillTree")

local SoundController = require(script.Parent.Modules.SoundController)
local clickSound = SoundController.Get("UIClicks")
TweenUtil.AddHoverEffect(skillTreeBtn, 1.08, clickSound)

local gui = playerGui:WaitForChild("SkillTreeGui")
local backdrop = gui:WaitForChild("Backdrop")
local panel = backdrop:WaitForChild("Panel")
local titleLabel = panel:WaitForChild("Title")
local moneyLabel = panel:WaitForChild("MoneyLabel")
local closeBtn = panel:WaitForChild("CloseButton")
local descLabel = panel:WaitForChild("DescriptionLabel")
local viewport = panel:WaitForChild("Viewport")
local starsContainer = viewport:WaitForChild("StarsContainer")
local canvas = viewport:WaitForChild("Canvas")
local canvasScale = canvas:WaitForChild("UIScale")
local hubNode = canvas:WaitForChild("ChefUnlockHub")

local LINEAR_BRANCHES = { "CustomerRarity", "CookTime", "ChopTime", "WashTime", "WalkSpeed" }

local nodeButtons = {}
for _, branchName in LINEAR_BRANCHES do
	local folder = canvas:WaitForChild(branchName .. "Nodes")
	nodeButtons[branchName] = {}
	for tier = 1, SkillConfig.MaxTier do
		nodeButtons[branchName][tier] = folder:WaitForChild("Tier" .. tier)
	end
end

-- Unified styling: locked/unacquired = grey scheme (regardless of
-- branch), acquired/owned = golden scheme. No more per-branch rainbow
-- coloring on the nodes themselves (branch titles keep their own
-- colors purely as identification labels, not state indicators).
local LOCKED_BG = Color3.fromRGB(70, 70, 78)
local LOCKED_GRADIENT = { Color3.fromRGB(110, 110, 122), Color3.fromRGB(55, 55, 64) }
local AVAILABLE_BG = Color3.fromRGB(150, 150, 162)
local AVAILABLE_GRADIENT = { Color3.fromRGB(205, 205, 215), Color3.fromRGB(140, 140, 155) }
local OWNED_BG = Color3.fromRGB(214, 168, 60)
local OWNED_GRADIENT = { Color3.fromRGB(255, 236, 168), Color3.fromRGB(200, 140, 40) }

local LOCKED_TEXT_GRADIENT = { Color3.fromRGB(220, 220, 226), Color3.fromRGB(150, 150, 160) }
local OWNED_TEXT_GRADIENT = { Color3.fromRGB(255, 250, 220), Color3.fromRGB(255, 200, 90) }

-- ---- Galaxy stars: dynamically created, lots of them, smooth
-- continuous drift via per-frame velocity ----

local STAR_IDS = {
	"rbxassetid://87910357585538",
	"rbxassetid://100468850320718",
	"rbxassetid://512454095",
}

local STAR_COUNT = 90
local stars = {}

for i = 1, STAR_COUNT do
	local star = Instance.new("ImageLabel")
	star.Name = "Star" .. i
	star.BackgroundTransparency = 1
	star.Image = STAR_IDS[((i - 1) % #STAR_IDS) + 1]
	local size = 0.015 + math.random() * 0.03
	star.Size = UDim2.new(size, 0, size, 0)
	star.Position = UDim2.new(math.random(), 0, math.random(), 0)
	star.Rotation = math.random(0, 360)
	star.ImageTransparency = 0.15 + math.random() * 0.35
	star.ZIndex = 2
	star.Parent = starsContainer

	stars[i] = {
		instance = star,
		vx = (math.random() - 0.5) * 0.03,
		vy = (math.random() - 0.5) * 0.03,
		vr = (math.random() - 0.5) * 25,
	}
end

RunService.RenderStepped:Connect(function(dt)
	if not gui.Enabled then return end
	for _, s in stars do
		local inst = s.instance
		local pos = inst.Position
		local nx = pos.X.Scale + s.vx * dt
		local ny = pos.Y.Scale + s.vy * dt
		if nx < -0.05 then nx = 1.05 elseif nx > 1.05 then nx = -0.05 end
		if ny < -0.05 then ny = 1.05 elseif ny > 1.05 then ny = -0.05 end
		inst.Position = UDim2.new(nx, 0, ny, 0)
		inst.Rotation = inst.Rotation + s.vr * dt
	end
end)

-- ---- Constellation pop-ups: fade in at a random spot, pulse + gentle
-- rotate for 5s, fade out, then move to a new random spot and repeat ----

local CONSTELLATION_IDS = {
	"rbxassetid://14101036795",
	"rbxassetid://14101048478",
	"rbxassetid://14101052047",
}
local CONSTELLATION_COUNT = 4
local CONSTELLATION_HOLD_TIME = 3

for i = 1, CONSTELLATION_COUNT do
	local icon = Instance.new("ImageLabel")
	icon.Name = "Constellation" .. i
	icon.BackgroundTransparency = 1
	icon.Image = CONSTELLATION_IDS[((i - 1) % #CONSTELLATION_IDS) + 1]
	icon.Size = UDim2.new(0.2, 0, 0.2, 0) -- 2x bigger
	icon.ImageTransparency = 1
	icon.ZIndex = 2
	icon.Parent = starsContainer

	task.spawn(function()
		task.wait(math.random() * CONSTELLATION_HOLD_TIME)
		while icon.Parent do
			icon.Position = UDim2.new(math.random() * 0.9, 0, math.random() * 0.9, 0)
			icon.Rotation = math.random(-15, 15)
			icon.ImageTransparency = 1

			-- Smooth pop in
			TweenService:Create(icon, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				ImageTransparency = 0.15,
			}):Play()
			task.wait(0.8)

			-- Hold, then smooth vanish
			task.wait(CONSTELLATION_HOLD_TIME)
			TweenService:Create(icon, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
				ImageTransparency = 1,
			}):Play()
			task.wait(1)
		end
	end)
end

-- ---- Gradient shimmer: sweeps Offset across every UIGradient so the
-- shine is clearly visible (a pure Rotation tween on a 2-stop gradient
-- barely reads as movement - Offset sweeping is the obvious one) ----

local function collectGradients(root)
	local list = {}
	for _, d in root:GetDescendants() do
		if d:IsA("UIGradient") then
			table.insert(list, d)
		end
	end
	return list
end

local allGradients = collectGradients(panel)
for _, grad in allGradients do
	task.spawn(function()
		task.wait(math.random())
		while grad.Parent do
			local t1 = TweenService:Create(grad, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Offset = Vector2.new(1, 0),
			})
			t1:Play()
			t1.Completed:Wait()
			local t2 = TweenService:Create(grad, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Offset = Vector2.new(-1, 0),
			})
			t2:Play()
			t2.Completed:Wait()
		end
	end)
end

-- ---- Hover pop on every clickable node ----

local function addHover(btn)
	TweenUtil.AddHoverEffect(btn, 1.12, nil)
end

addHover(hubNode)
for _, branchName in LINEAR_BRANCHES do
	for tier = 1, SkillConfig.MaxTier do
		addHover(nodeButtons[branchName][tier])
	end
end
addHover(closeBtn)

-- ---- Star-burst ripple on click: several star icons pop outward from
-- the click point and fade, instead of a single water-blue circle ----

local RIPPLE_STAR_IDS = {
	"rbxassetid://87910357585538",
	"rbxassetid://100468850320718",
	"rbxassetid://512454095",
}

local function spawnRippleBurst(button)
	local burstCount = 6
	for i = 1, burstCount do
		local star = Instance.new("ImageLabel")
		star.Name = "RippleStar"
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.Position = UDim2.new(0.5, 0, 0.5, 0)
		star.Size = UDim2.new(0.18, 0, 0.18, 0)
		star.BackgroundTransparency = 1
		star.Image = RIPPLE_STAR_IDS[((i - 1) % #RIPPLE_STAR_IDS) + 1]
		star.ImageTransparency = 0
		star.Rotation = math.random(0, 360)
		star.ZIndex = (button.ZIndex or 4) + 10
		star.Parent = button

		local angle = (i / burstCount) * math.pi * 2
		local dist = 0.9
		local targetPos = UDim2.new(0.5 + math.cos(angle) * dist, 0, 0.5 + math.sin(angle) * dist, 0)

		local tween = TweenService:Create(star, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = targetPos,
			Size = UDim2.new(0.02, 0, 0.02, 0),
			ImageTransparency = 1,
			Rotation = star.Rotation + 180,
		})
		tween:Play()
		tween.Completed:Connect(function()
			star:Destroy()
		end)
	end
end

local function addRipple(btn)
	btn.Activated:Connect(function()
		spawnRippleBurst(btn)
	end)
end

addRipple(hubNode)
for _, branchName in LINEAR_BRANCHES do
	for tier = 1, SkillConfig.MaxTier do
		addRipple(nodeButtons[branchName][tier])
	end
end

-- ---- Refresh visuals from server data ----

local currentSkillData = nil

local function refreshMoneyLabel()
	local leaderstats = player:FindFirstChild("leaderstats")
	local money = leaderstats and leaderstats:FindFirstChild("Money")
	moneyLabel.Text = "$" .. tostring(money and money.Value or 0)
end

local function applyNodeState(node, state)
	-- state: "locked" | "available" | "owned"
	local bg, grad
	if state == "owned" then
		bg, grad = OWNED_BG, OWNED_GRADIENT
	elseif state == "available" then
		bg, grad = AVAILABLE_BG, AVAILABLE_GRADIENT
	else
		bg, grad = LOCKED_BG, LOCKED_GRADIENT
	end
	node.BackgroundColor3 = bg
	local bgGrad = node:FindFirstChild("BgGradient")
	if bgGrad then
		bgGrad.Color = ColorSequence.new(grad[1], grad[2])
	end
	local tierLabel = node:FindFirstChild("TierLabel")
	if tierLabel then
		local textGrad = tierLabel:FindFirstChildOfClass("UIGradient")
		if textGrad then
			local textColors = (state == "owned") and OWNED_TEXT_GRADIENT or LOCKED_TEXT_GRADIENT
			textGrad.Color = ColorSequence.new(textColors[1], textColors[2])
		end
	end
end

local function refreshNodes()
	if not currentSkillData then return end

	local hubInfo = currentSkillData.Branches.ChefUnlock
	applyNodeState(hubNode, hubInfo.Tier >= 1 and "owned" or "available")
	local hubCost = hubNode:FindFirstChild("CostLabel")
	if hubCost then
		hubCost.Text = hubInfo.Tier >= 1 and "Unlocked" or "Served 50"
	end

	for _, branchName in LINEAR_BRANCHES do
		local info = currentSkillData.Branches[branchName]
		local locked = info.RequiresBranch and (currentSkillData.Branches[info.RequiresBranch].Tier or 0) <= 0
		for t = 1, SkillConfig.MaxTier do
			local node = nodeButtons[branchName][t]
			local costLabel = node:FindFirstChild("CostLabel")
			if t <= info.Tier then
				applyNodeState(node, "owned")
				if costLabel then costLabel.Text = "Owned" end
			elseif locked then
				applyNodeState(node, "locked")
				if costLabel then costLabel.Text = "Locked" end
			elseif t == info.Tier + 1 then
				applyNodeState(node, "available")
				if costLabel then costLabel.Text = "$" .. tostring(info.TierCosts[t]) end
			else
				applyNodeState(node, "locked")
				if costLabel then costLabel.Text = "$" .. tostring(info.TierCosts[t]) end
			end
		end
	end
	refreshMoneyLabel()
end

local function loadSkillData()
	local data = Remotes.RequestSkillTree:InvokeServer()
	if data then
		currentSkillData = data
		refreshNodes()
	end
end

-- Bigger, longer celebration than the click ripple - fires only on a
-- SUCCESSFUL purchase. Many stars burst outward and drift for 3s while
-- UnlockingSound plays, instead of the quick 6-point click feedback.
-- ---- Ambient sound + game-wide ducking while the tree is open ----

local SoundService = game:GetService("SoundService")
local skillTreeSounds = ReplicatedStorage.CookingMechanism.Sounds.SkillTreeRelated

local glacialSound = skillTreeSounds.GlacialSound:Clone()
glacialSound.Name = "GlacialSoundClone"
glacialSound.Looped = true
glacialSound.Parent = SoundService

local unlockingSound = skillTreeSounds.UnlockingSound:Clone()
unlockingSound.Name = "UnlockingSoundClone"
unlockingSound.Parent = SoundService

-- Mutes every OTHER currently-playing sound in the game while the tree
-- is open (so GlacialSound reads clearly as the tree's own ambience),
-- and restores each one's exact original volume on close. Also catches
-- sounds that start playing WHILE the tree is open.
local duckedVolumes = {} -- Sound -> original Volume
local duckConnection = nil
local duckConnection2 = nil

local function isOurOwnSound(sound)
	return sound == glacialSound or sound == unlockingSound
end

local function duckSound(sound)
	if isOurOwnSound(sound) or duckedVolumes[sound] then return end
	duckedVolumes[sound] = sound.Volume
	sound.Volume = 0
end

local function startDucking()
	-- MapAmbient (and possibly other loop sounds) are played directly
	-- from ReplicatedStorage.CookingMechanism.Sounds - not workspace or
	-- SoundService - so that has to be scanned too, or that ambience
	-- keeps playing right through the tree being open.
	for _, s in workspace:GetDescendants() do
		if s:IsA("Sound") then duckSound(s) end
	end
	for _, s in SoundService:GetDescendants() do
		if s:IsA("Sound") then duckSound(s) end
	end
	for _, s in ReplicatedStorage:GetDescendants() do
		if s:IsA("Sound") then duckSound(s) end
	end
	duckConnection = workspace.DescendantAdded:Connect(function(d)
		if d:IsA("Sound") then duckSound(d) end
	end)
	duckConnection2 = ReplicatedStorage.DescendantAdded:Connect(function(d)
		if d:IsA("Sound") then duckSound(d) end
	end)
end

local function stopDucking()
	if duckConnection then
		duckConnection:Disconnect()
		duckConnection = nil
	end
	if duckConnection2 then
		duckConnection2:Disconnect()
		duckConnection2 = nil
	end
	for sound, originalVolume in duckedVolumes do
		if sound.Parent then
			sound.Volume = originalVolume
		end
	end
	table.clear(duckedVolumes)
end

local CELEBRATION_STAR_IDS = {
	"rbxassetid://87910357585538",
	"rbxassetid://100468850320718",
	"rbxassetid://512454095",
}
local CELEBRATION_DURATION = 3
local CELEBRATION_STAR_COUNT = 32

local function spawnCelebrationBurst(node)
	unlockingSound.TimePosition = 0
	unlockingSound:Play()

	-- Travel stays close to the node itself (well under half the node's
	-- own size) rather than the old 1.4-2.6x offset, which sent stars far
	-- enough outside the button's own rectangle to run into neighboring
	-- siblings/viewport clipping and never actually render. A tight,
	-- dense burst right on top of the button reads just as celebratory
	-- and is guaranteed visible regardless of zoom/pan/neighbors.
	for i = 1, CELEBRATION_STAR_COUNT do
		local star = Instance.new("ImageLabel")
		star.Name = "CelebrationStar"
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.Position = UDim2.new(0.5, 0, 0.5, 0)
		star.Size = UDim2.new(0.22, 0, 0.22, 0)
		star.BackgroundTransparency = 1
		star.Image = CELEBRATION_STAR_IDS[((i - 1) % #CELEBRATION_STAR_IDS) + 1]
		star.ImageTransparency = 0
		star.Rotation = math.random(0, 360)
		star.ZIndex = 1000
		star.Parent = node

		local angle = math.random() * math.pi * 2
		local dist = 0.35 + math.random() * 0.35
		local targetPos = UDim2.new(0.5 + math.cos(angle) * dist, 0, 0.5 + math.sin(angle) * dist, 0)
		local delay = math.random() * 0.3

		task.delay(delay, function()
			local tween = TweenService:Create(star, TweenInfo.new(CELEBRATION_DURATION - delay, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = targetPos,
				Size = UDim2.new(0.04, 0, 0.04, 0),
				ImageTransparency = 1,
				Rotation = star.Rotation + math.random(-180, 180),
			})
			tween:Play()
			tween.Completed:Connect(function()
				star:Destroy()
			end)
		end)
	end
end

local function tryPurchase(branchName, tier)
	if not currentSkillData then return end
	local info = currentSkillData.Branches[branchName]
	if tier ~= info.Tier + 1 then return end
	if clickSound then clickSound:Play() end
	local ok = Remotes.PurchaseSkillTier:InvokeServer(branchName)
	if ok then
		local node = (branchName == "ChefUnlock") and hubNode or nodeButtons[branchName][tier]
		if node then
			spawnCelebrationBurst(node)
		end
		loadSkillData()
	end
end

hubNode.Activated:Connect(function()
	tryPurchase("ChefUnlock", 1)
end)

for _, branchName in LINEAR_BRANCHES do
	for tier = 1, SkillConfig.MaxTier do
		nodeButtons[branchName][tier].Activated:Connect(function()
			tryPurchase(branchName, tier)
		end)
	end
end

-- ---- Zoom (mouse wheel) + pan (drag) over the viewport ----

local MIN_ZOOM, MAX_ZOOM = 0.5, 1.8
local dragging = false
local dragStart = Vector2.zero
local canvasStartPos = UDim2.new()

viewport.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = Vector2.new(input.Position.X, input.Position.Y)
		canvasStartPos = canvas.Position
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not dragging then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch then
		local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
		local vpSize = viewport.AbsoluteSize
		if vpSize.X <= 0 or vpSize.Y <= 0 then return end
		canvas.Position = UDim2.new(
			canvasStartPos.X.Scale + delta.X / vpSize.X, 0,
			canvasStartPos.Y.Scale + delta.Y / vpSize.Y, 0
		)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)

viewport.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		local newScale = math.clamp(canvasScale.Scale + input.Position.Z * 0.1, MIN_ZOOM, MAX_ZOOM)
		canvasScale.Scale = newScale
	end
end)

-- Mobile pinch-to-zoom: Roblox fires TouchPinch with a ready-made
-- relative `scale` factor for the gesture, so we just apply it
-- directly to the canvas UIScale each update, same clamp as the wheel.
local pinchStartScale = 1
UserInputService.TouchPinch:Connect(function(touchPositions, scale, velocity, state)
	if state == Enum.UserInputState.Begin then
		pinchStartScale = canvasScale.Scale
	elseif state == Enum.UserInputState.Change then
		canvasScale.Scale = math.clamp(pinchStartScale * scale, MIN_ZOOM, MAX_ZOOM)
	end
end)

-- ---- Open / close ----

local treeOpen = false
local BEZIER = TweenUtil.CubicBezier(0.34, 1.56, 0.64, 1)
local PANEL_OPEN_SIZE = panel.Size

local function openSkillTree()
	if treeOpen then return end
	PanelManager.CloseAllExcept("SkillTree")
	treeOpen = true
	gui.Enabled = true
	loadSkillData()

	startDucking()
	glacialSound.TimePosition = 0
	glacialSound:Play()

	panel.Size = UDim2.new(0.1, 0, 0.1, 0)
	backdrop.BackgroundTransparency = 1
	TweenUtil.PlayCustomEase(0.4, BEZIER, function(alpha)
		panel.Size = UDim2.new(PANEL_OPEN_SIZE.X.Scale * alpha, 0, PANEL_OPEN_SIZE.Y.Scale * alpha, 0)
		backdrop.BackgroundTransparency = 0.35 + (1 - 0.35) * (1 - alpha)
	end)
end

local function closeSkillTree()
	if not treeOpen then return end
	treeOpen = false
	glacialSound:Stop()
	stopDucking()
	TweenUtil.Tween(panel, 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In, {
		Size = UDim2.new(0.1, 0, 0.1, 0),
	})
	TweenUtil.Tween(backdrop, 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In, {
		BackgroundTransparency = 1,
	})
	task.wait(0.2)
	gui.Enabled = false
	panel.Size = PANEL_OPEN_SIZE
	backdrop.BackgroundTransparency = 0.35
end

PanelManager.Register("SkillTree", closeSkillTree)

skillTreeBtn.Activated:Connect(function()
	if clickSound then clickSound:Play() end
	if treeOpen then closeSkillTree() else openSkillTree() end
end)

closeBtn.Activated:Connect(function()
	if clickSound then clickSound:Play() end
	closeSkillTree()
end)
