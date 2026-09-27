-- Plot selection camera + hotbar stage
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TweenUtil = require(script.Parent.TweenUtil)
local SoundController = require(script.Parent.SoundController)
local LoadingConfig = require(ReplicatedStorage.CookingMechanism.Configs.LoadingConfig)

local Remotes = ReplicatedStorage.CookingMechanism.Remotes
local SelectPlot = Remotes.SelectPlot
local PlotStateChanged = Remotes.PlotStateChanged

local PlotSelectionStage = {}

local function findFreePlot(occupancy, plotCount, preferredId)
	if preferredId then
		return preferredId
	end
	for plotId = 1, plotCount do
		if not occupancy[plotId] then
			return plotId
		end
	end
	return 1
end

function PlotSelectionStage.Run(screenGui, camera, introData)
	local hotbar = screenGui.PlotSelectionHotbar
	local leftArrow = hotbar.LeftArrow
	local rightArrow = hotbar.RightArrow
	local plotDisplay = hotbar.Plot
	local counter = plotDisplay.Counter
	local enterButton = plotDisplay.Enter

	local plotCount = introData.PlotCount
	local occupancy = introData.Occupancy or {}
	local cameraPositions = introData.CameraPositions
	local focusPositions = introData.FocusPositions

	local clickSound = SoundController.Get("UIClicks")
	TweenUtil.AddHoverEffect(leftArrow, 1.1, clickSound)
	TweenUtil.AddHoverEffect(rightArrow, 1.1, clickSound)
	TweenUtil.AddHoverEffect(enterButton, 1.08, clickSound)

	hotbar.Visible = true
	camera.CameraType = Enum.CameraType.Scriptable

	local currentPlot = findFreePlot(occupancy, plotCount, introData.OwnedPlotId)

	local function focusCamera(plotId)
		local camPos = cameraPositions[plotId]
		local focusPos = focusPositions[plotId]
		if camPos and focusPos then
			TweenUtil.Tween(camera, 0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, {
				CFrame = CFrame.lookAt(camPos, focusPos),
			})
		end
	end

	local function refreshDisplay()
		local occupied = occupancy[currentPlot] ~= nil
		local isOwnPlot = introData.OwnedPlotId == currentPlot
		local canEnter = (not occupied) or isOwnPlot

		counter.Visible = true
		counter.Text = canEnter and "Enter" or tostring(currentPlot)
		enterButton.Interactable = canEnter
	end

	focusCamera(currentPlot)
	refreshDisplay()

	local stateConnection = PlotStateChanged.OnClientEvent:Connect(function(newOccupancy)
		occupancy = newOccupancy
		refreshDisplay()
	end)

	leftArrow.Activated:Connect(function()
		currentPlot = ((currentPlot - 2) % plotCount) + 1
		focusCamera(currentPlot)
		refreshDisplay()
	end)

	rightArrow.Activated:Connect(function()
		currentPlot = (currentPlot % plotCount) + 1
		focusCamera(currentPlot)
		refreshDisplay()
	end)

	local completed = false
	enterButton.Activated:Connect(function()
		if not enterButton.Interactable then return end
		enterButton.Interactable = false

		local result = SelectPlot:InvokeServer(currentPlot)
		if result and result.Success then
			completed = true
		else
			enterButton.Interactable = true
		end
	end)

	repeat task.wait() until completed

	stateConnection:Disconnect()
	hotbar.Visible = false
	camera.CameraType = Enum.CameraType.Custom
end

return PlotSelectionStage
