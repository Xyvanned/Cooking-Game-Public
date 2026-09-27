-- Cinematic swipe + circular camera stage
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local TweenUtil = require(script.Parent.TweenUtil)
local SoundController = require(script.Parent.SoundController)
local LoadingConfig = require(ReplicatedStorage.CookingMechanism.Configs.LoadingConfig)

local CinematicStage = {}

local DOT_STATES = { "Click anywhere", "Click anywhere.", "Click anywhere..", "Click anywhere..." }

local function runDotTyping(textLabel, isCancelled)
	task.spawn(function()
		local index = 1
		while not isCancelled() do
			textLabel.Text = DOT_STATES[index]
			index = (index % #DOT_STATES) + 1
			task.wait(0.4)
		end
	end)
end

local function runCircularCamera(camera, centerPosition, circularPositions, isCancelled)
	task.spawn(function()
		local index = 1
		camera.CameraType = Enum.CameraType.Scriptable

		while not isCancelled() do
			local position = circularPositions[index]
			if position then
				local targetCFrame = CFrame.lookAt(position, centerPosition)
				local startCFrame = camera.CFrame
				local elapsed = 0
				while elapsed < LoadingConfig.CIRCULAR_STEP_TIME do
					if isCancelled() then return end
					local dt = RunService.RenderStepped:Wait()
					elapsed += dt
					local alpha = math.clamp(elapsed / LoadingConfig.CIRCULAR_STEP_TIME, 0, 1)
					camera.CFrame = startCFrame:Lerp(targetCFrame, alpha)
				end
			end
			index = (index % 18) + 1
		end
	end)
end

function CinematicStage.Run(screenGui, camera, centerPosition, circularPositions)
	local cinematicFrame = screenGui.CinematicFrame
	local topFrame = cinematicFrame.TopFrame
	local bottomFrame = cinematicFrame.BottomFrame
	local textLabel = bottomFrame.Text
	local clickButton = cinematicFrame.ClickButton

	local cancelled = false
	local function isCancelled() return cancelled end

	cinematicFrame.Visible = true
	clickButton.Interactable = false
	textLabel.Visible = false

	topFrame.Size = UDim2.new(1, 0, 0.5, 0)
	topFrame.Position = UDim2.new(0, 0, 0, 0)
	bottomFrame.Size = UDim2.new(1, 0, 0.5, 0)
	bottomFrame.Position = UDim2.new(0, 0, 0.49, 0)

	runCircularCamera(camera, centerPosition, circularPositions, isCancelled)

	local topTween = TweenUtil.Tween(topFrame, LoadingConfig.CINEMATIC_SWIPE_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, {
		Size = UDim2.new(1, 0, 0.1, 0),
		Position = UDim2.new(0, 0, 0, 0),
	})
	TweenUtil.Tween(bottomFrame, LoadingConfig.CINEMATIC_SWIPE_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, {
		Size = UDim2.new(1, 0, 0.1, 0),
		Position = UDim2.new(0, 0, 0.9, 0),
	})

	topTween.Completed:Wait()
	SoundController.Play("CinematicSwipe")

	task.wait(LoadingConfig.CINEMATIC_TEXT_DELAY)
	textLabel.Visible = true
	runDotTyping(textLabel, isCancelled)

	clickButton.Interactable = true

	local completed = false
	clickButton.Activated:Connect(function()
		completed = true
	end)

	repeat task.wait() until completed

	cancelled = true
	cinematicFrame.Visible = false
end

return CinematicStage
