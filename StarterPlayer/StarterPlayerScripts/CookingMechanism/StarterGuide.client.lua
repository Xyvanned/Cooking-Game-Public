-- Starter guide, part 2 (part 1 = Modules.TutorialGuide's spotlight):
--  * Chef NPC dialog (StarterGui.Guide): Model = expression image,
--    Board.Container.Message = typewriter text. Lines/faces per step live
--    in Configs.GuideDialogue; expression ids in AssetRegistry.
--  * Pathfinding beam from the player's torso to the current station
--    (StarterRestaurant.GuideBeam attachments), texture from
--    AssetRegistry.GuideBeamTexture. Client-only, owner-only.
-- Both run only while the tutorial is enabled. The current step is read
-- from TutorialGuide.GetContext(), which RestaurantController keeps
-- current - this script never decides gameplay state itself.

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local TweenService       = game:GetService("TweenService")
local PathfindingService = game:GetService("PathfindingService")

local Configs       = ReplicatedStorage.CookingMechanism.Configs
local GuideDialogue = require(Configs.GuideDialogue)
local AssetRegistry = require(Configs.AssetRegistry)
local TutorialGuide = require(script.Parent.Modules.TutorialGuide)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local guideGui = playerGui:WaitForChild("Guide")
local frame = guideGui:WaitForChild("Frame")
local model = frame:WaitForChild("Model")
local board = frame:WaitForChild("Board")
local message = board:WaitForChild("Container"):WaitForChild("Message")
guideGui.Enabled = false

local ENTER_RADIUS = 10    -- studs from the Restaurant attachment = "inside"
local BEAM_HIDE_RADIUS = 6 -- hide the beam once basically at the station
-- The beam leaves the torso, drops to just above the floor a few studs
-- ahead and follows the path there - a waist-height beam pointing away
-- from the camera hid behind the character in testing.
local BEAM_LIFT = 0.4      -- studs above the path's floor waypoints
local BEAM_LEAD = 3        -- studs ahead of the player where it touches down
local MAX_SEGMENTS = 16

-- ---- State ----

local entered = false      -- reached the Restaurant attachment once
local delivered = false    -- dish delivered, customer now eating
local completedAt = nil    -- os.clock() when the tutorial finished
local played = {}          -- step -> true once all its lines have played
local currentStep = nil
local playToken = 0
local lastArea = nil

-- ---- Sounds (Sounds.TutorialGuideSound) ----

local guideSounds = ReplicatedStorage.CookingMechanism:WaitForChild("Sounds"):WaitForChild("TutorialGuideSound")
local blip = guideSounds:WaitForChild(GuideDialogue.BLIP_SOUND)
blip.Looped = true -- one long clip, looped while text is typing
local BLIP_VOLUME = blip.Volume
local faceSoundToken = 0

local function playFaceSound(face)
	local soundName = GuideDialogue.FaceSounds[face]
	local sound = soundName and guideSounds:FindFirstChild(soundName)
	if not sound then return end
	sound.TimePosition = 0
	sound:Play()
	-- Duck the typing blip to half while the expression sound plays.
	faceSoundToken += 1
	local token = faceSoundToken
	blip.Volume = BLIP_VOLUME / 2
	local length = sound.TimeLength > 0 and sound.TimeLength or 1.5
	task.delay(length, function()
		if token == faceSoundToken then
			blip.Volume = BLIP_VOLUME
		end
	end)
end

-- ---- Expression pop ----

local faceScale = model:FindFirstChild("ExpressionScale") or Instance.new("UIScale")
faceScale.Name = "ExpressionScale"
faceScale.Parent = model

local function setFace(name)
	local image = AssetRegistry.GetChefExpression(name)
	if model.Image == image then return end
	model.Image = image
	faceScale.Scale = 0.85
	TweenService:Create(faceScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	playFaceSound(name)
end

-- ---- Dialogue playback ----

local function typeLine(text, token)
	message.Text = ""
	blip.TimePosition = math.random() * math.max(0, blip.TimeLength - 1)
	blip:Play()
	for i = 1, #text do
		if token ~= playToken then
			blip:Stop()
			return false
		end
		message.Text = string.sub(text, 1, i)
		task.wait(GuideDialogue.TYPE_SPEED)
	end
	blip:Stop()
	return true
end

local function playStep(step)
	playToken += 1
	local token = playToken
	local lines = GuideDialogue.Steps[step]
	if not lines or #lines == 0 then return end
	task.spawn(function()
		local from = played[step] and #lines or 1
		for i = from, #lines do
			if token ~= playToken then return end
			setFace(lines[i].Face or "Default")
			if not typeLine(lines[i].Text, token) then return end
			if i < #lines then
				task.wait(GuideDialogue.LINE_HOLD)
			end
		end
		if token == playToken then played[step] = true end
	end)
end

-- ---- Step selection (from RestaurantController's context) ----

local function getRestaurantAttachment(ctx, name)
	local r = ctx.restaurant
	local folder = r and r.Parent and r:FindFirstChild("GuideBeam")
	return folder and name and folder:FindFirstChild(name)
end

local function flatDistance(a, b)
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

local function getRoot()
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function pickStep(ctx)
	if completedAt then return "done" end
	local area = ctx.area

	-- Track "just delivered": area goes DiningArea -> nothing.
	if lastArea == "DiningArea" and area == nil and not ctx.dishReady then
		delivered = true
	elseif area == "UsedPlate" or area == "WashArea" or ctx.potPlaced then
		delivered = false
	end
	lastArea = area

	if not entered then
		if ctx.hasAccepted then
			entered = true -- already mid-order (e.g. re-enabled from Settings)
		else
			local att = getRestaurantAttachment(ctx, "Restaurant")
			local root = getRoot()
			if att and root and flatDistance(root.Position, att.WorldPosition) <= ENTER_RADIUS then
				entered = true
			else
				TutorialGuide.SetIntroDone(false)
				return "welcome"
			end
		end
	end
	-- Welcome finished: the button spotlight may start now.
	TutorialGuide.SetIntroDone(true)

	if area == nil then
		if ctx.cooking then return "cooking" end
		if delivered then return "eating" end
		if ctx.hasWaiting and not ctx.hasAccepted then return "customer" end
		return "waitCustomer"
	elseif area == "CookingArea" then
		if not ctx.potPlaced then return "placePot" end
		if ctx.allAdded then return "startFire" end
		if not ctx.anyAdded then return "addMeat" end
		return "addRest"
	elseif area == "FridgeArea" then return "fridge"
	elseif area == "ItemContainerArea" then return "container"
	elseif area == "ChoppingArea" then return ctx.anyAdded and "chopRest" or "chopMeat"
	elseif area == "KitchenIsle" then return "kitchenIsle"
	elseif area == "DiningArea" then return "deliver"
	elseif area == "UsedPlate" then return "usedPlate"
	elseif area == "WashArea" then return "wash"
	end
	return nil
end

-- ---- Pathfinding beam ----

local beamFolder = Instance.new("Folder")
beamFolder.Name = "LocalGuideBeam"
beamFolder.Parent = workspace

local anchor = Instance.new("Part")
anchor.Name = "BeamAnchor"
anchor.Anchored = true
anchor.CanCollide = false
anchor.CanQuery = false
anchor.CanTouch = false
anchor.Transparency = 1
anchor.Size = Vector3.new(0.2, 0.2, 0.2)
anchor.CFrame = CFrame.new()
anchor.Parent = beamFolder

local points = {} -- Attachments on the anchor, one per path point
local beams = {}
local startAttachment = nil

local function newBeam()
	local b = Instance.new("Beam")
	b.Texture = AssetRegistry.GetGuideBeamTexture()
	b.TextureMode = Enum.TextureMode.Wrap
	b.TextureLength = 3
	b.TextureSpeed = 1.2
	b.FaceCamera = true
	b.Width0 = 1.4
	b.Width1 = 1.4
	b.LightEmission = 0.6
	b.Transparency = NumberSequence.new(0.1)
	b.Segments = 1
	b.Enabled = false
	b.Parent = beamFolder
	return b
end

local function ensureStartAttachment()
	local char = player.Character
	local torso = char and (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso"))
	if not torso then return nil end
	if startAttachment and startAttachment.Parent == torso then return startAttachment end
	startAttachment = Instance.new("Attachment")
	startAttachment.Name = "GuideBeamStart"
	startAttachment.Parent = torso
	return startAttachment
end

local function hideBeam()
	for _, b in beams do b.Enabled = false end
end

-- Draws torso -> p1 -> p2 -> ... -> target.
local function drawPath(worldPoints)
	local startAtt = ensureStartAttachment()
	if not startAtt then hideBeam() return end
	for i, pos in worldPoints do
		local att = points[i]
		if not att then
			att = Instance.new("Attachment")
			att.Parent = anchor
			points[i] = att
		end
		att.WorldPosition = pos
	end
	for i = 1, #worldPoints do
		local b = beams[i] or newBeam()
		beams[i] = b
		b.Attachment0 = (i == 1) and startAtt or points[i - 1]
		b.Attachment1 = points[i]
		b.Enabled = true
	end
	for i = #worldPoints + 1, #beams do
		beams[i].Enabled = false
	end
end

-- Floor-level points: a touch-down point just ahead of the player, then
-- only the corners of the path, then the target (at floor height).
local function simplify(waypoints, targetPos)
	local out = {}
	local lift = Vector3.new(0, BEAM_LIFT, 0)
	if #waypoints >= 2 then
		local a, b = waypoints[1].Position, waypoints[2].Position
		local dir = b - a
		if dir.Magnitude > BEAM_LEAD then
			table.insert(out, a + dir.Unit * BEAM_LEAD + lift)
		end
	end
	for i = 2, #waypoints - 1 do
		local prev, cur, nxt = waypoints[i - 1].Position, waypoints[i].Position, waypoints[i + 1].Position
		local d1, d2 = (cur - prev), (nxt - cur)
		if d1.Magnitude > 0.01 and d2.Magnitude > 0.01 and d1.Unit:Dot(d2.Unit) < 0.97 then
			table.insert(out, cur + lift)
			if #out >= MAX_SEGMENTS - 1 then break end
		end
	end
	local floorY = (#waypoints > 0 and waypoints[#waypoints].Position.Y or targetPos.Y) + BEAM_LIFT
	table.insert(out, Vector3.new(targetPos.X, floorY, targetPos.Z))
	return out
end

local path = PathfindingService:CreatePath({
	AgentRadius = 2,
	AgentHeight = 5,
	AgentCanJump = true,
})

local beamTarget = nil  -- Attachment currently pointed at
local lastComputePos = nil
local lastComputeTarget = nil
local lastComputeTime = 0
local computing = false

local function updateBeam()
	local root = getRoot()
	if not (beamTarget and beamTarget.Parent and root) then
		hideBeam()
		return
	end
	local targetPos = beamTarget.WorldPosition
	if flatDistance(root.Position, targetPos) <= BEAM_HIDE_RADIUS then
		hideBeam()
		return
	end

	local moved = not lastComputePos or (root.Position - lastComputePos).Magnitude > 3
	local changed = lastComputeTarget ~= beamTarget
	local stale = os.clock() - lastComputeTime > 1.5
	if computing or not (moved or changed or stale) then return end

	computing = true
	lastComputePos = root.Position
	lastComputeTarget = beamTarget
	lastComputeTime = os.clock()
	local ok = pcall(function()
		path:ComputeAsync(root.Position, targetPos)
	end)
	if ok and path.Status == Enum.PathStatus.Success then
		drawPath(simplify(path:GetWaypoints(), targetPos))
	else
		drawPath({ targetPos }) -- no path: straight line fallback
	end
	computing = false
end

-- ---- Visibility (dodge panels / the spotlight hole) ----

local SLIDE_TIME = 0.3
local shownPos = frame.Position
local hiddenPos = shownPos + UDim2.new(0, 0, 0.6, 0)
local slidOut = false

local function isVisible(g)
	local n = g
	while n and n ~= playerGui do
		if n:IsA("GuiObject") and not n.Visible then return false end
		if n:IsA("LayerCollector") and not n.Enabled then return false end
		n = n.Parent
	end
	return n == playerGui
end

-- Overlap test against where the element sits when the chef is SHOWN
-- (not its current, possibly slid-away position) - otherwise sliding
-- out would clear the overlap and it would bounce back in.
local function rectsOverlap(a, gObj)
	local slideDelta = frame.AbsolutePosition - (guideGui.AbsolutePosition + Vector2.new(
		shownPos.X.Scale * guideGui.AbsoluteSize.X + shownPos.X.Offset,
		shownPos.Y.Scale * guideGui.AbsoluteSize.Y + shownPos.Y.Offset))
	local p, s = gObj.AbsolutePosition - slideDelta, gObj.AbsoluteSize
	return a[1] < p.X + s.X and p.X < a[1] + a[3] and a[2] < p.Y + s.Y and p.Y < a[2] + a[4]
end

local function modalOpen()
	local cm = playerGui:FindFirstChild("CookingMechanismGui")
	if not cm then return false end
	local core = cm:FindFirstChild("CoreRelatedUIContainer")
	local checks = {
		cm:FindFirstChild("Customer"),
		core and core:FindFirstChild("IngredientStorage"),
		core and core:FindFirstChild("FridgeStorage"),
		core and core:FindFirstChild("RecipeIndex"),
		cm:FindFirstChild("OptionSelectionContaner") and cm.OptionSelectionContaner:FindFirstChild("SettingsPanel"),
	}
	for _, g in checks do
		if g and isVisible(g) then return true end
	end
	local skill = playerGui:FindFirstChild("SkillTreeGui")
	return skill ~= nil and skill.Enabled
end

local function setSlid(out)
	if out == slidOut then return end
	slidOut = out
	TweenService:Create(frame, TweenInfo.new(SLIDE_TIME, Enum.EasingStyle.Quad, out and Enum.EasingDirection.In or Enum.EasingDirection.Out), {
		Position = out and hiddenPos or shownPos,
	}):Play()
end

-- ---- Main loop ----

TutorialGuide.OnCompleted(function()
	completedAt = os.clock()
end)

-- Counter (money/tickets HUD) is hidden while the tutorial runs - which
-- includes brand-new players, whose tutorial starts on. Hidden from the
-- start until the saved preference loads, so it never flashes.
local function setCounterVisible(visible)
	local cm = playerGui:WaitForChild("CookingMechanismGui", 10)
	local counter = cm and cm:FindFirstChild("Counter")
	if counter then counter.Visible = visible end
end
setCounterVisible(false)

TutorialGuide.OnEnabledChanged(function(on)
	setCounterVisible(not on)
	if on then
		-- Replaying from Settings: start the dialogue fresh (the player is
		-- usually already inside, so the welcome check passes quickly).
		table.clear(played)
		entered = false
		completedAt = nil
		currentStep = nil
	end
end)

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 0.2 then return end
	accumulator = 0

	local cm = playerGui:FindFirstChild("CookingMechanismGui")
	local ctx = TutorialGuide.GetContext()
	local finishing = completedAt and (os.clock() - completedAt) < GuideDialogue.DONE_HOLD
	local active = TutorialGuide.IsLoaded() and cm and cm.Enabled and ctx.restaurant ~= nil
		and (TutorialGuide.IsEnabled() or finishing)

	if not active then
		if guideGui.Enabled then guideGui.Enabled = false end
		if blip.IsPlaying then blip:Stop() end
		beamTarget = nil
		hideBeam()
		if completedAt and not finishing then completedAt = nil end
		return
	end
	if not guideGui.Enabled then
		guideGui.Enabled = true
		slidOut = true
		frame.Position = hiddenPos
	end

	local step = pickStep(ctx)
	if step ~= currentStep then
		currentStep = step
		if step then playStep(step) end
	end

	-- Beam toward this step's station.
	local lines = step and GuideDialogue.Steps[step]
	beamTarget = lines and getRestaurantAttachment(ctx, lines.Beam) or nil
	task.spawn(updateBeam)

	-- Slide the chef away while a panel is open or the spotlight hole
	-- would sit under the board/face.
	local hole = TutorialGuide.GetHoleRect()
	local blocked = modalOpen() or (hole ~= nil and (rectsOverlap(hole, board) or rectsOverlap(hole, model)))
	setSlid(blocked or step == nil)
end)
