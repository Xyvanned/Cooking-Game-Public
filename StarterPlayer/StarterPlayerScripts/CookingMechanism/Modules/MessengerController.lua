-- Displays warning messages in Messenger.WarningContainer
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local warningSound = ReplicatedStorage.CookingMechanism.Sounds:FindFirstChild("MechanismSound")
warningSound = warningSound and warningSound:FindFirstChild("Warning")

local MessengerController = {}
local queue = {}
local running = false

local SHOW_TIME  = 2.5
local FADE_TIME  = 0.35

local function getWarningContainer()
	local gui = playerGui:FindFirstChild("CookingMechanismGui")
	if not gui then return nil end
	local messenger = gui:FindFirstChild("Messenger")
	if not messenger then return nil end
	return messenger:FindFirstChild("WarningContainer")
end

local function processQueue()
	if running then return end
	running = true
	task.spawn(function()
		while #queue > 0 do
			local msg = table.remove(queue, 1)
			local container = getWarningContainer()
			if container then
				local template = container:FindFirstChild("Template")
				if template then
					template.Visible = false -- keep original hidden

					local clone = template:Clone()
					clone.Text = msg
					clone.TextTransparency = 1
					clone.Visible = true
					clone.Name = "ActiveMessage"
					clone.Parent = container
					container.Visible = true
					if warningSound then warningSound:Play() end

					TweenService:Create(clone, TweenInfo.new(FADE_TIME), { TextTransparency = 0 }):Play()
					task.wait(SHOW_TIME)
					local t = TweenService:Create(clone, TweenInfo.new(FADE_TIME), { TextTransparency = 1 })
					t:Play()
					t.Completed:Wait()
					clone:Destroy()

					-- Hide container when no active messages remain
					local hasActive = false
					for _, c in container:GetChildren() do
						if c.Name == "ActiveMessage" then
							hasActive = true
							break
						end
					end
					if not hasActive then
						container.Visible = false
					end
				end
			end
		end
		running = false
	end)
end

function MessengerController.Warn(message)
	table.insert(queue, message)
	processQueue()
end

return MessengerController
