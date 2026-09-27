function waitForChild(parent, childName)
	local child = parent:FindFirstChild(childName)
	if child then return child end
	while true do
		child = parent.ChildAdded:Wait()
		if child.Name == childName then return child end
	end
end

local Figure = script.Parent
local Humanoid = waitForChild(Figure, "Humanoid")
local pose = "Standing"

local currentAnim = ""
local currentAnimInstance = nil
local currentAnimTrack = nil
local currentAnimKeyframeHandler = nil
local currentAnimSpeed = 1.0
local animTable = {}
local animNames = {
	idle = {
		{ id = "http://www.roblox.com/asset/?id=180435571", weight = 1 },
		{ id = "http://www.roblox.com/asset/?id=180435571", weight = 1 },
		{ id = "http://www.roblox.com/asset/?id=180435571", weight = 9 },
	},
	walk = {{ id = "rbxassetid://180426354", weight = 10 }},
	run = {{ id = "rbxassetid://180426354", weight = 10 }},
	swim = {{ id = "http://www.roblox.com/asset/?id=180426354", weight = 10 }},
	swimidle = {{ id = "http://www.roblox.com/asset/?id=180426354", weight = 10 }},
	jump = {{ id = "http://www.roblox.com/asset/?id=125750702", weight = 10 }},
	fall = {{ id = "http://www.roblox.com/asset/?id=180436148", weight = 10 }},
	climb = {{ id = "http://www.roblox.com/asset/?id=180426354", weight = 10 }},
	sit = {{ id = "http://www.roblox.com/asset/?id=180426354", weight = 10 }},
	toolnone = {{ id = "http://www.roblox.com/asset/?id=180426354", weight = 10 }},
	toolslash = {{ id = "http://www.roblox.com/asset/?id=180426354", weight = 10 }},
	toollunge = {{ id = "http://www.roblox.com/asset/?id=180426354", weight = 10 }},
	wave = {{ id = "http://www.roblox.com/asset/?id=180426354", weight = 10 }},
	point = {{ id = "http://www.roblox.com/asset/?id=180426354", weight = 10 }},
	dance = {
		{ id = "http://www.roblox.com/asset/?id=507771019", weight = 10 },
		{ id = "http://www.roblox.com/asset/?id=507771955", weight = 10 },
		{ id = "http://www.roblox.com/asset/?id=507772104", weight = 10 },
	},
	dance2 = {
		{ id = "http://www.roblox.com/asset/?id=507776043", weight = 10 },
		{ id = "http://www.roblox.com/asset/?id=507776720", weight = 10 },
		{ id = "http://www.roblox.com/asset/?id=507776879", weight = 10 },
	},
	dance3 = {
		{ id = "http://www.roblox.com/asset/?id=507777268", weight = 10 },
		{ id = "http://www.roblox.com/asset/?id=507777451", weight = 10 },
		{ id = "http://www.roblox.com/asset/?id=507777623", weight = 10 },
	},
	laugh = {{ id = "http://www.roblox.com/asset/?id=507770818", weight = 10 }},
	cheer = {{ id = "http://www.roblox.com/asset/?id=507770677", weight = 10 }},
}

local emoteNames = { wave = false, point = false, dance = true, dance2 = true, dance3 = true, laugh = false, cheer = false }

math.randomseed(tick())

function configureAnimationSet(name, fileList)
	if animTable[name] then
		for _, conn in pairs(animTable[name].connections) do conn:Disconnect() end
	end
	animTable[name] = { count = 0, totalWeight = 0, connections = {} }

	local config = script:FindFirstChild(name)
	if config then
		table.insert(animTable[name].connections, config.ChildAdded:Connect(function() configureAnimationSet(name, fileList) end))
		table.insert(animTable[name].connections, config.ChildRemoved:Connect(function() configureAnimationSet(name, fileList) end))
		local idx = 1
		for _, child in config:GetChildren() do
			if child:IsA("Animation") then
				table.insert(animTable[name].connections, child.Changed:Connect(function() configureAnimationSet(name, fileList) end))
				animTable[name][idx] = { anim = child, weight = 1 }
				local w = child:FindFirstChild("Weight")
				if w then animTable[name][idx].weight = w.Value end
				animTable[name].count += 1
				animTable[name].totalWeight += animTable[name][idx].weight
				idx += 1
			end
		end
	end

	if animTable[name].count <= 0 then
		for idx, anim in ipairs(fileList) do
			local a = Instance.new("Animation")
			a.Name = name
			a.AnimationId = anim.id
			animTable[name][idx] = { anim = a, weight = anim.weight }
			animTable[name].count += 1
			animTable[name].totalWeight += anim.weight
		end
	end
end

script.ChildAdded:Connect(function(child)
	local fl = animNames[child.Name]
	if fl then configureAnimationSet(child.Name, fl) end
end)
script.ChildRemoved:Connect(function(child)
	local fl = animNames[child.Name]
	if fl then configureAnimationSet(child.Name, fl) end
end)

for name, fl in animNames do configureAnimationSet(name, fl) end

local toolAnim = "None"
local toolAnimTime = 0
local jumpAnimTime = 0
local jumpAnimDuration = 0.31
local toolTransitionTime = 0.1
local fallTransitionTime = 0.2

function stopAllAnimations()
	local oldAnim = currentAnim
	if emoteNames[oldAnim] ~= nil and not emoteNames[oldAnim] then oldAnim = "idle" end
	currentAnim = ""
	currentAnimInstance = nil
	if currentAnimKeyframeHandler then currentAnimKeyframeHandler:Disconnect() end
	if currentAnimTrack then
		currentAnimTrack:Stop()
		currentAnimTrack:Destroy()
		currentAnimTrack = nil
	end
	return oldAnim
end

function setAnimationSpeed(speed)
	if speed ~= currentAnimSpeed then
		currentAnimSpeed = speed
		if currentAnimTrack then currentAnimTrack:AdjustSpeed(currentAnimSpeed) end
	end
end

function keyFrameReachedFunc(frameName)
	if frameName == "End" then
		local repeatAnim = currentAnim
		if emoteNames[repeatAnim] ~= nil and not emoteNames[repeatAnim] then repeatAnim = "idle" end
		local animSpeed = currentAnimSpeed
		playAnimation(repeatAnim, 0.15, Humanoid)
		setAnimationSpeed(animSpeed)
	end
end

function playAnimation(animName, transitionTime, humanoid)
	if not animTable[animName] or animTable[animName].count <= 0 then return end
	local roll = math.random(1, animTable[animName].totalWeight)
	local idx = 1
	while roll > animTable[animName][idx].weight do
		roll -= animTable[animName][idx].weight
		idx += 1
	end
	local anim = animTable[animName][idx].anim
	if anim ~= currentAnimInstance then
		if currentAnimTrack then
			currentAnimTrack:Stop(transitionTime)
			currentAnimTrack:Destroy()
		end
		currentAnimSpeed = 1.0
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			currentAnimTrack = animator:LoadAnimation(anim)
		else
			currentAnimTrack = humanoid:LoadAnimation(anim)
		end
		currentAnimTrack:Play(transitionTime)
		currentAnim = animName
		currentAnimInstance = anim
		if currentAnimKeyframeHandler then currentAnimKeyframeHandler:Disconnect() end
		currentAnimKeyframeHandler = currentAnimTrack.KeyframeReached:Connect(keyFrameReachedFunc)
	end
end

local toolAnimName = ""
local toolAnimTrack = nil
local toolAnimInstance = nil
local currentToolAnimKeyframeHandler = nil

function toolKeyFrameReachedFunc(frameName)
	if frameName == "End" then playToolAnimation(toolAnimName, 0, Humanoid) end
end

function playToolAnimation(animName, transitionTime, humanoid)
	if not animTable[animName] or animTable[animName].count <= 0 then return end
	local roll = math.random(1, animTable[animName].totalWeight)
	local idx = 1
	while roll > animTable[animName][idx].weight do
		roll -= animTable[animName][idx].weight
		idx += 1
	end
	local anim = animTable[animName][idx].anim
	if toolAnimInstance ~= anim then
		if toolAnimTrack then toolAnimTrack:Stop(); toolAnimTrack:Destroy(); transitionTime = 0 end
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			toolAnimTrack = animator:LoadAnimation(anim)
		else
			toolAnimTrack = humanoid:LoadAnimation(anim)
		end
		toolAnimTrack:Play(transitionTime)
		toolAnimName = animName
		toolAnimInstance = anim
		currentToolAnimKeyframeHandler = toolAnimTrack.KeyframeReached:Connect(toolKeyFrameReachedFunc)
	end
end

function stopToolAnimations()
	if currentToolAnimKeyframeHandler then currentToolAnimKeyframeHandler:Disconnect() end
	toolAnimName = ""
	toolAnimInstance = nil
	if toolAnimTrack then toolAnimTrack:Stop(); toolAnimTrack:Destroy(); toolAnimTrack = nil end
end

function onRunning(speed)
	if speed > 0.01 then
		playAnimation("walk", 0.1, Humanoid)
		setAnimationSpeed(speed / 15.0)
		pose = "Running"
	else
		if emoteNames[currentAnim] == nil then
			playAnimation("idle", 0.1, Humanoid)
			pose = "Standing"
		end
	end
end

function onDied() pose = "Dead" end
function onJumping() playAnimation("jump", 0.1, Humanoid); jumpAnimTime = jumpAnimDuration; pose = "Jumping" end
function onClimbing(speed) playAnimation("climb", 0.1, Humanoid); setAnimationSpeed(speed / 5.0); pose = "Climbing" end
function onGettingUp() pose = "GettingUp" end
function onFreeFall() if jumpAnimTime <= 0 then playAnimation("fall", fallTransitionTime, Humanoid) end; pose = "FreeFall" end
function onFallingDown() pose = "FallingDown" end
function onSeated() pose = "Seated" end
function onPlatformStanding() pose = "PlatformStanding" end

function onSwimming(speed)
	if speed > 1 then
		playAnimation("swim", 0.4, Humanoid); setAnimationSpeed(speed / 10.0); pose = "Swimming"
	else
		playAnimation("swimidle", 0.4, Humanoid); pose = "Standing"
	end
end

local function getTool()
	for _, kid in Figure:GetChildren() do
		if kid:IsA("Tool") then return kid end
	end
	return nil
end

local function getToolAnim(tool)
	for _, c in tool:GetChildren() do
		if c.Name == "toolanim" and c:IsA("StringValue") then return c end
	end
	return nil
end

function animateTool()
	if toolAnim == "None" then playToolAnimation("toolnone", toolTransitionTime, Humanoid); return end
	if toolAnim == "Slash" then playToolAnimation("toolslash", 0, Humanoid); return end
	if toolAnim == "Lunge" then playToolAnimation("toollunge", 0, Humanoid); return end
end

local lastTick = os.clock()
function move(time)
	local deltaTime = time - lastTick
	lastTick = time
	if jumpAnimTime > 0 then jumpAnimTime -= deltaTime end
	if pose == "FreeFall" and jumpAnimTime <= 0 then
		playAnimation("fall", fallTransitionTime, Humanoid)
	elseif pose == "Seated" then
		playAnimation("sit", 0.5, Humanoid); return
	elseif pose == "Running" then
		playAnimation("walk", 0.1, Humanoid)
	elseif pose == "Dead" or pose == "GettingUp" or pose == "FallingDown" or pose == "PlatformStanding" then
		stopAllAnimations()
	end
	local tool = getTool()
	if tool and (tool.RequiresHandle or tool:FindFirstChild("Handle")) then
		local sv = getToolAnim(tool)
		if sv then toolAnim = sv.Value; sv.Parent = nil; toolAnimTime = time + 0.3 end
		if time > toolAnimTime then toolAnimTime = 0; toolAnim = "None" end
		animateTool()
	else
		stopToolAnimations(); toolAnim = "None"; toolAnimInstance = nil; toolAnimTime = 0
	end
end

Humanoid.Died:Connect(onDied)
Humanoid.Running:Connect(onRunning)
Humanoid.Jumping:Connect(onJumping)
Humanoid.Climbing:Connect(onClimbing)
Humanoid.GettingUp:Connect(onGettingUp)
Humanoid.FreeFalling:Connect(onFreeFall)
Humanoid.FallingDown:Connect(onFallingDown)
Humanoid.Seated:Connect(onSeated)
Humanoid.PlatformStanding:Connect(onPlatformStanding)
Humanoid.Swimming:Connect(onSwimming)

game.Players.LocalPlayer.Chatted:Connect(function(msg)
	local emote = ""
	if string.sub(msg, 1, 3) == "/e " then emote = string.sub(msg, 4)
	elseif string.sub(msg, 1, 7) == "/emote " then emote = string.sub(msg, 8) end
	if pose == "Standing" and emoteNames[emote] ~= nil then playAnimation(emote, 0.1, Humanoid) end
end)

playAnimation("idle", 0.1, Humanoid)
pose = "Standing"

while Figure.Parent ~= nil do
	local dt = task.wait(0.1)
	lastTick += dt
	move(lastTick)
end
