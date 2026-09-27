-- Client sound access
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sounds = ReplicatedStorage.CookingMechanism.Sounds

local SoundController = {}

function SoundController.Get(name)
	local sound = Sounds:FindFirstChild(name)
	if sound then return sound end
	for _, folder in Sounds:GetChildren() do
		if folder:IsA("Folder") then
			local found = folder:FindFirstChild(name)
			if found then return found end
		end
	end
	return nil
end

function SoundController.Play(name)
	local sound = SoundController.Get(name)
	if sound then sound:Play() end
	return sound
end

function SoundController.Stop(name)
	local sound = SoundController.Get(name)
	if sound then sound:Stop() end
end

return SoundController
