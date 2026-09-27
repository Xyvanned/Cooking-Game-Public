-- Replaces default Animate with Anima
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local animaTemplate = script:WaitForChild("Anima")
animaTemplate.Disabled = true

local function onCharacterAdded(character)
	local defaultAnimate = character:WaitForChild("Animate", 5)
	if defaultAnimate then
		defaultAnimate.Disabled = true
		defaultAnimate:Destroy()
	end

	local existing = character:FindFirstChild("Anima")
	if existing then existing:Destroy() end

	local clone = animaTemplate:Clone()
	clone.Disabled = false
	clone.Parent = character
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	onCharacterAdded(player.Character)
end
