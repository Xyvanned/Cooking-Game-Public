-- Orchestrates the intro sequence
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local screenGui = playerGui:WaitForChild("DesignatedLoadingScreen")

local LoadingStage = require(script.Parent.Modules.LoadingStage)
local CinematicStage = require(script.Parent.Modules.CinematicStage)
local PlotSelectionStage = require(script.Parent.Modules.PlotSelectionStage)
local AmbientController = require(script.Parent.AmbientController)

local Remotes = ReplicatedStorage.CookingMechanism.Remotes
local RequestIntroData = Remotes.RequestIntroData

local camera = Workspace.CurrentCamera

local function runIntro()
	local introData = RequestIntroData:InvokeServer()

	LoadingStage.Run(screenGui)

	CinematicStage.Run(
		screenGui,
		camera,
		introData.Cinematic.CenterPosition,
		introData.Cinematic.CircularPositions
	)

	PlotSelectionStage.Run(screenGui, camera, introData)

	-- Plot selected — start ambient (5s delay inside)
	AmbientController.Start()

	screenGui.Enabled = false

	-- Enable gameplay GUIs
	local cookingGui = playerGui:FindFirstChild("CookingMechanismGui")
	local merchantGui = playerGui:FindFirstChild("MerchantUI")
	if cookingGui then cookingGui.Enabled = true end
	if merchantGui then merchantGui.Enabled = true end
end

runIntro()
