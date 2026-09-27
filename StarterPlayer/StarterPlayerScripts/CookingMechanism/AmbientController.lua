-- Sequential ambient music, call .Start() after plot selected
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ambientFolder = ReplicatedStorage
	:WaitForChild("CookingMechanism")
	:WaitForChild("Sounds")
	:WaitForChild("MapAmbient")

local AMBIENT_ORDER = { "Ambient1", "Ambient2", "Ambient3" }
local started = false

local function playSequence()
	local index = 1
	while true do
		local sound = ambientFolder:FindFirstChild(AMBIENT_ORDER[index])
		if sound then
			sound:Play()
			sound.Ended:Wait()
		end
		index = (index % #AMBIENT_ORDER) + 1
	end
end

local AmbientController = {}

function AmbientController.Start()
	if started then return end
	started = true
	task.spawn(function()
		task.wait(5)
		playSequence()
	end)
end

return AmbientController
