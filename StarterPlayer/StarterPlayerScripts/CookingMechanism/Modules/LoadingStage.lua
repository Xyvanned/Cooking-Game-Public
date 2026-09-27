-- Loading screen stage
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TweenUtil = require(script.Parent.TweenUtil)
local SoundController = require(script.Parent.SoundController)
local LoadingConfig = require(ReplicatedStorage.CookingMechanism.Configs.LoadingConfig)
local FunFacts = require(ReplicatedStorage.CookingMechanism.Configs.FunFacts)

local LoadingStage = {}

local crumbleEase = TweenUtil.CubicBezier(0.34, 1.56, 0.64, 1)

local function runFunFactsLoop(funfactsLabel, isCancelled)
	task.spawn(function()
		local index = 1
		while not isCancelled() do
			local fact = FunFacts.List[index]
			local startTime = os.clock()

			TweenUtil.TypeText(funfactsLabel, fact, LoadingConfig.FACT_TYPE_SPEED, isCancelled)
			if isCancelled() then return end

			local remaining = LoadingConfig.FACT_DISPLAY_TIME - (os.clock() - startTime)
			if remaining > 0 then
				task.wait(remaining)
			end

			index = (index % #FunFacts.List) + 1
		end
	end)
end

local function playLogoCrumble(logoIcon)
	logoIcon.Rotation = -35
	logoIcon.ImageTransparency = 1
	local baseSize = logoIcon.Size
	logoIcon.Size = UDim2.new(baseSize.X.Scale * 0.4, 0, baseSize.Y.Scale * 0.4, 0)

	TweenUtil.PlayCustomEase(LoadingConfig.LOGO_CRUMBLE_TIME, crumbleEase, function(alpha)
		logoIcon.Rotation = -35 * (1 - alpha)
		logoIcon.ImageTransparency = 1 - alpha
		local scale = 0.4 + (0.6 * alpha)
		logoIcon.Size = UDim2.new(baseSize.X.Scale * scale, 0, baseSize.Y.Scale * scale, 0)
	end)
end

local function playNameTagPulse(nameTag, isCancelled)
	local gradient = nameTag:FindFirstChildOfClass("UIGradient")
	local baseSize = nameTag.Size
	local pulseSize = UDim2.new(baseSize.X.Scale * 1.05, 0, baseSize.Y.Scale * 1.05, 0)

	task.spawn(function()
		while not isCancelled() do
			TweenUtil.Tween(nameTag, LoadingConfig.NAMETAG_PULSE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, { Size = pulseSize })
			task.wait(LoadingConfig.NAMETAG_PULSE_TIME)
			if isCancelled() then return end
			TweenUtil.Tween(nameTag, LoadingConfig.NAMETAG_PULSE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, { Size = baseSize })
			task.wait(LoadingConfig.NAMETAG_PULSE_TIME)
		end
	end)

	if gradient then
		task.spawn(function()
			while not isCancelled() do
				TweenUtil.Tween(gradient, LoadingConfig.NAMETAG_PULSE_TIME * 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, { Offset = Vector2.new(0.3, 0) })
				task.wait(LoadingConfig.NAMETAG_PULSE_TIME * 2)
				if isCancelled() then return end
				TweenUtil.Tween(gradient, LoadingConfig.NAMETAG_PULSE_TIME * 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, { Offset = Vector2.new(-0.3, 0) })
				task.wait(LoadingConfig.NAMETAG_PULSE_TIME * 2)
			end
		end)
	end
end

function LoadingStage.Run(screenGui)
	local mainFrame = screenGui.MainFrame
	local barsContainer = mainFrame.LoadingBarsContainer
	local logoContainer = mainFrame.LogoContainer
	local middlePlateEnter = mainFrame.MiddlePlateEnter
	local showText = middlePlateEnter.ShowText
	local funfacts = mainFrame.Funfacts

	local cancelled = false
	local function isCancelled() return cancelled end

	mainFrame.Visible = true
	middlePlateEnter.Interactable = false
	SoundController.Play("LoadingScreenSound")
	showText.Visible = false
	showText.TextTransparency = 1

	local leftFiller = barsContainer.LeftFiller
	local rightFiller = barsContainer.RightFiller
	leftFiller.Visible = true
	rightFiller.Visible = true

	TweenUtil.Tween(leftFiller, LoadingConfig.BAR_FILL_TIME, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, {
		Size = UDim2.new(0.398, 0, 0.159, 0),
	})
	TweenUtil.Tween(rightFiller, LoadingConfig.BAR_FILL_TIME, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, {
		Size = UDim2.new(0.398, 0, 0.159, 0),
	})

	playLogoCrumble(logoContainer.LogoIcon)
	playNameTagPulse(logoContainer.NameTag, isCancelled)
	runFunFactsLoop(funfacts, isCancelled)

	task.wait(LoadingConfig.ENTER_UNLOCK_DELAY)

	showText.Visible = true
	TweenUtil.Tween(showText, 0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, { TextTransparency = 0 })
	middlePlateEnter.Interactable = true

	local clickSound = SoundController.Get("UIClicks")
	TweenUtil.AddHoverEffect(middlePlateEnter, 1.06, clickSound)

	local completed = false
	middlePlateEnter.Activated:Connect(function()
		completed = true
	end)

	repeat task.wait() until completed

	cancelled = true
	SoundController.Stop("LoadingScreenSound")
	mainFrame.Visible = false
end

return LoadingStage
