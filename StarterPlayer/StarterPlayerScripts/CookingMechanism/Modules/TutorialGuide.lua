-- Guided-onboarding spotlight: dims the whole screen (85% black) except
-- a box around the ONE thing the player should click/press next, with an
-- animated focus ring, bouncing pointer and a hint bubble.
--
-- The overlay itself is a real, Studio-editable ScreenGui
-- (StarterGui.TutorialSpotlightGui). The dim is 4 frames around a
-- rectangular hole (Roblox has no GUI masks); only the hole lets clicks
-- through, so the real button underneath receives them - nothing is
-- cloned or re-wired.
--
-- RestaurantController owns game state and pushes it here via
-- SetContext() (which area the world guide is on, what item is needed,
-- etc.). This module only decides WHICH on-screen element to spotlight
-- from that context + what UI is currently visible. World-walking
-- phases have nothing to click, so the overlay hides and the world
-- Highlights guide instead.
--
-- Enabled state is saved on the profile (Remotes.RequestTutorial /
-- SetTutorial): on for new players, off once finished or skipped,
-- toggleable from Settings.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local CookingConfig = require(ReplicatedStorage.CookingMechanism.Configs.CookingConfig)
local RecipeConfig  = CookingConfig.RecipeConfig
local MessengerController = require(script.Parent.MessengerController)

local Remotes = ReplicatedStorage.CookingMechanism.Remotes
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local DIM_TRANSPARENCY = 0.15 -- 85% opacity black
local HOLE_PADDING     = 8    -- px of breathing room around the target
local FOLLOW_SPEED     = 14   -- higher = hole snaps to targets faster
local RESOLVE_INTERVAL = 0.1  -- how often the target is re-picked

local TutorialGuide = {}

local enabled = false
local loaded = false
local ctx = {}
local zones = {} -- RestaurantController's live detectorState table
-- StarterGuide sets this once the chef's welcome is done (player inside
-- the eatery); no button spotlight before that.
local introDone = false
local enabledListeners = {}
local completedListeners = {}

local function notifyEnabled()
	for _, fn in enabledListeners do
		task.spawn(fn, enabled)
	end
end

-- Display names for hint text.
local displayName = {}
for _, def in CookingConfig.ContainerItems do displayName[def.Name] = def.Display end
for _, def in CookingConfig.FridgeItems do displayName[def.Name] = def.Display end
for _, recipe in RecipeConfig.Recipes do
	for _, step in recipe.Sequence do displayName[step.Name] = step.Display end
end
local function nice(item) return displayName[item] or item or "" end

-- ---- Overlay instances ----

local gui = playerGui:WaitForChild("TutorialSpotlightGui")
local dimFolder = gui:WaitForChild("Dim")
local dimTop, dimBottom = dimFolder:WaitForChild("Top"), dimFolder:WaitForChild("Bottom")
local dimLeft, dimRight = dimFolder:WaitForChild("Left"), dimFolder:WaitForChild("Right")
local dims = { dimTop, dimBottom, dimLeft, dimRight }
-- Focus ring = 4 gold edge bars (no UIStroke), each with a Shine gradient.
local ring = gui:WaitForChild("FocusRing")
local edges = {
	ring:WaitForChild("EdgeTop"), ring:WaitForChild("EdgeBottom"),
	ring:WaitForChild("EdgeLeft"), ring:WaitForChild("EdgeRight"),
}
local edgeShines = {}
for _, e in edges do table.insert(edgeShines, e:WaitForChild("Shine")) end
local pointer = gui:WaitForChild("Pointer")
local tooltip = gui:WaitForChild("Tooltip")
local hintLabel = tooltip:WaitForChild("Hint")
local skipButton = gui:WaitForChild("SkipButton")
gui.Enabled = false

-- ---- Helpers ----

-- Truly on screen: every ancestor Visible, its ScreenGui/Billboard
-- Enabled, and it has a real size.
local function isShown(g)
	if not (g and g:IsA("GuiObject") and g:IsDescendantOf(playerGui)) then return false end
	local n = g
	while n and n ~= playerGui do
		if n:IsA("GuiObject") and not n.Visible then return false end
		if n:IsA("LayerCollector") and not n.Enabled then return false end
		n = n.Parent
	end
	return g.AbsoluteSize.X > 2 and g.AbsoluteSize.Y > 2
end

local function path(root, ...)
	local n = root
	for _, name in { ... } do
		n = n and n:FindFirstChild(name)
	end
	return n
end

-- Rect of a GuiObject in the overlay's own offset space, or nil if it
-- can't be spotlighted right now.
--  * ScreenGui content: every ScreenGui's AbsolutePosition shares one
--    space, and the overlay's origin is its own AbsolutePosition (e.g.
--    (0, -58) when it ignores the top bar), so a plain subtraction lines
--    up regardless of IgnoreGuiInset/ScreenInsets.
--  * BillboardGui content (world ProximityPrompts): AbsolutePosition is
--    relative to the billboard's own canvas, NOT the screen - so project
--    the billboard's 3D anchor through the camera instead. Viewport
--    pixels start at the very top of the screen, same as the overlay.
local MAX_TARGET_FRACTION = 0.6 -- bigger than this = camera too close, skip

local function screenRect(g)
	local bb = g:FindFirstAncestorWhichIsA("BillboardGui")
	local x, y
	local size = g.AbsoluteSize
	if bb then
		local adornee = bb.Adornee or bb.Parent
		local worldPos
		if adornee and adornee:IsA("Attachment") then
			worldPos = adornee.WorldPosition
		elseif adornee and adornee:IsA("BasePart") then
			worldPos = adornee.Position
		else
			return nil
		end
		local cam = workspace.CurrentCamera
		worldPos += bb.StudsOffsetWorldSpace + cam.CFrame:VectorToWorldSpace(bb.StudsOffset)
		local v, onScreen = cam:WorldToViewportPoint(worldPos)
		if not onScreen then return nil end
		local canvas = bb.AbsoluteSize
		local rel = g.AbsolutePosition - bb.AbsolutePosition
		x = v.X - canvas.X / 2 + canvas.X * bb.SizeOffset.X + rel.X
		y = v.Y - canvas.Y / 2 - canvas.Y * bb.SizeOffset.Y + rel.Y
	else
		local pos = g.AbsolutePosition - gui.AbsolutePosition
		x, y = pos.X, pos.Y
	end
	local screen = gui.AbsoluteSize
	if size.X > screen.X * MAX_TARGET_FRACTION or size.Y > screen.Y * MAX_TARGET_FRACTION then
		return nil
	end
	return x, y, size.X, size.Y
end

-- The on-screen UI of a world ProximityPrompt (CustomProximity clones a
-- BillboardGui into PlayerGui.ProximityPrompts, Adornee = prompt.Parent).
local function promptWidget(prompt)
	if not (prompt and prompt.Enabled) then return nil end
	local holder = playerGui:FindFirstChild("ProximityPrompts")
	if not holder then return nil end
	for _, bb in holder:GetChildren() do
		if bb:IsA("BillboardGui") and bb.Adornee == prompt.Parent then
			return bb:FindFirstChild("PromptFrame") or bb:FindFirstChildWhichIsA("GuiObject")
		end
	end
	return nil
end

local function firstCard(list, prefix)
	local best
	for _, c in list:GetChildren() do
		if c:IsA("GuiButton") and c.Name:sub(1, #prefix) == prefix and isShown(c) then
			if not best or c.LayoutOrder < best.LayoutOrder then best = c end
		end
	end
	return best
end

-- Hotbar slot currently showing this item.
local function hotbarSlot(cm, item)
	local bar = path(cm, "InventoryFrameContainer", "HotBarContainer")
	if not bar then return nil end
	for _, slot in bar:GetChildren() do
		local lbl = slot:FindFirstChild("ItemName")
		if slot.Name:match("^Slot%d+$") and lbl and lbl.Text == item and isShown(slot) then
			return slot
		end
	end
	return nil
end

-- The world prompt for the current step, if any.
local function stepPrompt()
	local r = ctx.restaurant
	if not (r and r.Parent) then return nil end
	local area = r:FindFirstChild("AreaContainer")
	if not area then return nil end
	local function promptIn(inst)
		return inst and inst:FindFirstChildOfClass("ProximityPrompt")
	end
	local function servedPrompt(index)
		return index and promptIn(path(r, "ServingToCustomer", "ServedSpawner", tostring(index)))
	end

	if ctx.area == "FridgeArea" then
		return promptIn(path(area, "FridgeArea", "ProximityContainer")), "Press the prompt to look inside the fridge"
	elseif ctx.area == "CookingArea" and ctx.potPlaced then
		if ctx.allAdded then
			return promptIn(path(area, "CookingArea", "ProximityContainer")), "Everything's in - start the fire!"
		elseif ctx.wantHeld and ctx.held == ctx.wantHeld then
			return promptIn(path(area, "CookingArea", "ProximityContainer")), "Add " .. nice(ctx.wantHeld) .. " to the pot"
		end
	elseif ctx.area == "KitchenIsle" then
		local spawner = path(area, "KitchenIsle", "TobeServedSpawner")
		if spawner then
			for _, att in spawner:GetChildren() do
				if att:GetAttribute("PlatedDish") then
					return promptIn(att), "Pick up the finished dish"
				end
			end
		end
	elseif ctx.area == "DiningArea" then
		return servedPrompt(ctx.awaitingSeat), "Serve the dish to your customer"
	elseif ctx.area == "UsedPlate" then
		return servedPrompt(ctx.usedPlateIndex), "Collect the empty plate"
	elseif ctx.area == "WashArea" then
		return promptIn(path(area, "WashArea", "Proximity")), "Put the plate in the sink and wash it"
	end
	return nil
end

-- Picks the single element to spotlight right now (or nil = hide).
-- ---- Station locks (tutorial only) ----
-- While the tutorial runs, stations outside the current step are "off":
-- their zone popups are skipped (RestaurantController asks
-- IsStationActive) and their always-on world prompts are hidden
-- locally. CookingArea and WashArea are never locked.
local LOCKABLE = {
	FridgeArea = true, ItemContainerArea = true, ChoppingArea = true,
	KitchenIsle = true, DiningArea = true,
}
local lockedPrompts = {} -- prompts WE disabled -> true (restored later)

function TutorialGuide.IsStationActive(area)
	if not (enabled and loaded) then return true end
	if not LOCKABLE[area] then return true end
	if area == "DiningArea" and ctx.area == "UsedPlate" then return true end
	return ctx.area == area
end

local function setPromptLock(prompt, active)
	if not prompt then return end
	if active then
		if lockedPrompts[prompt] then
			lockedPrompts[prompt] = nil
			prompt.Enabled = true
		end
	elseif prompt.Enabled then
		lockedPrompts[prompt] = true
		prompt.Enabled = false
	end
end

-- Only the always-on prompts are locked here (KitchenIsle pickup points,
-- table delivery/plate points). The fridge's prompt is already driven by
-- the fridge door (server), so it's gated through its zone popup instead.
local function applyPromptLocks()
	local r = ctx.restaurant
	if not (r and r.Parent) then return end
	local isle = path(r, "AreaContainer", "KitchenIsle", "TobeServedSpawner")
	if isle then
		local active = TutorialGuide.IsStationActive("KitchenIsle")
		for _, att in isle:GetChildren() do
			setPromptLock(att:FindFirstChildOfClass("ProximityPrompt"), active)
		end
	end
	local served = path(r, "ServingToCustomer", "ServedSpawner")
	if served then
		local active = TutorialGuide.IsStationActive("DiningArea")
		for _, att in served:GetChildren() do
			setPromptLock(att:FindFirstChildOfClass("ProximityPrompt"), active)
		end
	end
end

local function releaseAllPromptLocks()
	for prompt in lockedPrompts do
		if prompt.Parent then prompt.Enabled = true end
	end
	table.clear(lockedPrompts)
end

local function resolveTarget()
	if not (enabled and loaded and introDone) then return nil end
	local cm = playerGui:FindFirstChild("CookingMechanismGui")
	if not (cm and cm.Enabled) then return nil end

	-- Never hijack panels that aren't part of the guided flow.
	local skill = playerGui:FindFirstChild("SkillTreeGui")
	if skill and skill.Enabled then return nil end
	if isShown(path(cm, "OptionSelectionContaner", "SettingsPanel")) then return nil end
	if isShown(path(cm, "CoreRelatedUIContainer", "RecipeIndex")) then return nil end
	if isShown(path(cm, "InventoryFrameContainer", "HoverInventory")) then return nil end
	local merchant = playerGui:FindFirstChild("MerchantUI")
	if merchant and (isShown(merchant:FindFirstChild("Dialog")) or isShown(path(merchant, "UIContainer", "IngredientUI")) or isShown(path(merchant, "UIContainer", "ConstructionUI"))) then
		return nil
	end

	local core = cm:FindFirstChild("CoreRelatedUIContainer")

	-- Any Yes/No popup in the guided flow: the answer is always Yes.
	local popup = core and core:FindFirstChild("UIPopUpRequest")
	if isShown(popup) then
		return popup:FindFirstChild("Yes"), "Click Yes to continue"
	end

	-- Step 0: accept a waiting customer.
	if not ctx.hasAccepted then
		if not ctx.hasWaiting then return nil end
		local cust = cm:FindFirstChild("Customer")
		if not isShown(cust) then
			return path(cm, "OptionSelectionToggles", "Customer"), "A customer is waiting! Open the Customer panel"
		end
		local sel = cust:FindFirstChild("SelectionContainer")
		local hover = sel and sel:FindFirstChild("CustomerSelectionHoverCard")
		if isShown(hover) then
			return hover:FindFirstChild("AcceptButton"), "Accept their order"
		end
		local list = sel and sel:FindFirstChild("CustomerSelection")
		if isShown(list) then
			local card = firstCard(list, "Seat")
			if card then return card, "Select the waiting customer" end
			return nil
		end
		return cust:FindFirstChild("Return"), "Switch to the waiting list"
	end

	-- Storage panels: pick the needed item, then Use.
	local function storageTarget(panel, listName, wantArea)
		if not isShown(panel) then return nil end
		local container = panel:FindFirstChild("Container")
		local info = container and container:FindFirstChild("ShowInfo")
		if isShown(info) then
			return path(info, "ButtonContainer", "Use"), "Take it!"
		end
		if ctx.area == wantArea and ctx.needItem then
			local card = path(container, listName, ctx.needItem)
			if isShown(card) then return card, "Grab the " .. nice(ctx.needItem) end
		end
		return panel:FindFirstChild("Exit"), "All set here - close it"
	end
	if core then
		local t, h = storageTarget(core:FindFirstChild("IngredientStorage"), "RecipeIndexContainer", "ItemContainerArea")
		if t then return t, h end
		t, h = storageTarget(core:FindFirstChild("FridgeStorage"), "IngredientsContainer", "FridgeArea")
		if t then return t, h end
	end

	-- Customer panel re-opened later: nothing to do in it.
	if isShown(cm:FindFirstChild("Customer")) then return nil end

	-- At a station but holding the wrong thing: point at the hotbar slot.
	local atStation = (ctx.area == "ChoppingArea" and zones.Chopping)
		or (ctx.area == "CookingArea" and zones.Cooking)
		or (ctx.area == "WashArea" and zones.Wash)
	if ctx.wantHeld and ctx.held ~= ctx.wantHeld and atStation then
		local slot = hotbarSlot(cm, ctx.wantHeld)
		if slot then return slot, "Hold the " .. nice(ctx.wantHeld) .. " from your hotbar" end
	end

	-- A world prompt that's currently on screen.
	local prompt, hint = stepPrompt()
	local widget = promptWidget(prompt)
	if widget and isShown(widget) then return widget, hint end

	return nil
end

-- ---- Animation ----

local currentTarget = nil
local rect = nil -- {x, y, w, h} currently drawn
local holeRectAbs = nil -- same, in absolute GUI coords (nil when hidden)
local visibleAlpha = 0 -- 0 hidden .. 1 fully shown
local clock = 0
local resolveTimer = 0
local lastHint = nil

local function setDimAlpha(a)
	local t = 1 - (1 - DIM_TRANSPARENCY) * a
	for _, d in dims do d.BackgroundTransparency = t end
end

local function layout(x, y, w, h, screen)
	-- Whole pixels only: fractional edges (mid-glide) left a visible
	-- 1px seam between the side and bottom dim frames.
	local x2, y2 = math.ceil(x + w), math.ceil(y + h)
	x, y = math.floor(x), math.floor(y)
	w, h = x2 - x, y2 - y
	local W, H = math.ceil(screen.X), math.ceil(screen.Y)
	local BIG = 200 -- overshoot past the screen edges (notch/safe areas)
	dimTop.Position    = UDim2.fromOffset(-BIG, -BIG)
	dimTop.Size        = UDim2.fromOffset(W + BIG * 2, y + BIG)
	dimBottom.Position = UDim2.fromOffset(-BIG, y + h)
	dimBottom.Size     = UDim2.fromOffset(W + BIG * 2, math.max(0, H - (y + h)) + BIG)
	dimLeft.Position   = UDim2.fromOffset(-BIG, y)
	dimLeft.Size       = UDim2.fromOffset(x + BIG, h)
	dimRight.Position  = UDim2.fromOffset(x + w, y)
	dimRight.Size      = UDim2.fromOffset(math.max(0, W - (x + w)) + BIG, h)

	ring.Position = UDim2.fromOffset(x, y)
	ring.Size     = UDim2.fromOffset(w, h)

	-- Pointer + hint go above the target, or below if there's no room.
	local cx = x + w / 2
	local bounce = math.abs(math.sin(clock * 4)) * 10
	local tipW = tooltip.AbsoluteSize.X
	local tipX = math.clamp(cx, tipW / 2 + 10, W - tipW / 2 - 10)
	if y > 140 then
		pointer.Rotation = 0
		pointer.AnchorPoint = Vector2.new(0.5, 1)
		pointer.Position = UDim2.fromOffset(cx, y - 6 - bounce)
		tooltip.AnchorPoint = Vector2.new(0.5, 1)
		tooltip.Position = UDim2.fromOffset(tipX, y - 56 - bounce)
	else
		pointer.Rotation = 180
		pointer.AnchorPoint = Vector2.new(0.5, 0)
		pointer.Position = UDim2.fromOffset(cx, y + h + 6 + bounce)
		tooltip.AnchorPoint = Vector2.new(0.5, 0)
		tooltip.Position = UDim2.fromOffset(tipX, y + h + 56 + bounce)
	end
end

RunService.RenderStepped:Connect(function(dt)
	clock += dt
	resolveTimer -= dt
	if resolveTimer <= 0 then
		resolveTimer = RESOLVE_INTERVAL
		local target, hint = resolveTarget()
		if target ~= currentTarget then
			if target and not currentTarget then
				rect = nil -- fresh appearance: zoom in from wide
			end
			currentTarget = target
		end
		if hint ~= lastHint then
			lastHint = hint
			if hint then
				hintLabel.Text = hint
				-- little pop whenever the instruction changes
				tooltip.Size = UDim2.fromOffset(260, 46)
				TweenService:Create(tooltip, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Size = UDim2.fromOffset(300, 54),
				}):Play()
			end
		end
	end

	-- Target vanished mid-frame (panel closed / prompt off screen) ->
	-- start hiding now.
	local target = currentTarget
	local tx, ty, tw, th
	if target and isShown(target) then
		tx, ty, tw, th = screenRect(target)
		if not tx then target = nil end
	else
		target = nil
	end

	visibleAlpha = math.clamp(visibleAlpha + (target and dt or -dt) / 0.25, 0, 1)
	if visibleAlpha <= 0 then
		if gui.Enabled then gui.Enabled = false end
		rect = nil
		return
	end
	if not gui.Enabled then gui.Enabled = true end
	setDimAlpha(visibleAlpha)

	local screen = gui.AbsoluteSize
	if target then
		tx, ty, tw, th = tx - HOLE_PADDING, ty - HOLE_PADDING, tw + HOLE_PADDING * 2, th + HOLE_PADDING * 2
		if not rect then
			-- Appear: start 2.5x wider around the target and close in.
			local cx, cy = tx + tw / 2, ty + th / 2
			rect = { cx - tw * 1.25, cy - th * 1.25, tw * 2.5, th * 2.5 }
		end
		-- Frame-rate independent ease toward the target (also glides
		-- smoothly from one target to the next).
		local a = 1 - math.exp(-dt * FOLLOW_SPEED)
		rect[1] += (tx - rect[1]) * a
		rect[2] += (ty - rect[2]) * a
		rect[3] += (tw - rect[3]) * a
		rect[4] += (th - rect[4]) * a
	end
	if rect then
		layout(rect[1], rect[2], rect[3], rect[4], screen)
		-- Shared (absolute coords) so the chef dialog can dodge it: the
		-- hole PLUS the pointer and hint bubble (the chef draws above the
		-- spotlight, so it would otherwise cover the bubble).
		if target then
			local origin = gui.AbsolutePosition
			local x1, y1 = rect[1] + origin.X, rect[2] + origin.Y
			local x2, y2 = x1 + rect[3], y1 + rect[4]
			for _, g in { tooltip, pointer } do
				local p, s = g.AbsolutePosition, g.AbsoluteSize
				x1, y1 = math.min(x1, p.X), math.min(y1, p.Y)
				x2, y2 = math.max(x2, p.X + s.X), math.max(y2, p.Y + s.Y)
			end
			holeRectAbs = { x1, y1, x2 - x1, y2 - y1 }
		else
			holeRectAbs = nil
		end
	else
		holeRectAbs = nil
	end

	-- Ring: shine sweeping along each edge + breathing thickness.
	local pulse = (math.sin(clock * 5) + 1) / 2
	local thick = 3 + pulse * 3
	local sweep = ((clock * 0.8) % 2) - 1 -- -1 .. 1
	for i, e in edges do
		if i <= 2 then
			e.Size = UDim2.new(1, thick * 2, 0, thick)
		else
			e.Size = UDim2.new(0, thick, 1, 0)
		end
		e.BackgroundTransparency = (1 - visibleAlpha) + pulse * 0.2 * visibleAlpha
		edgeShines[i].Rotation = i <= 2 and 0 or 90
		edgeShines[i].Offset = i <= 2 and Vector2.new(sweep, 0) or Vector2.new(0, sweep)
	end
	pointer.TextTransparency = 1 - visibleAlpha
	hintLabel.TextTransparency = 1 - visibleAlpha
end)

-- Station locks are gameplay, not visuals: run them on Heartbeat so they
-- keep working even when nothing is rendering.
local lockTimer = 0
RunService.Heartbeat:Connect(function(dt)
	lockTimer -= dt
	if lockTimer > 0 then return end
	lockTimer = RESOLVE_INTERVAL
	if enabled and loaded then
		applyPromptLocks()
	elseif next(lockedPrompts) then
		releaseAllPromptLocks()
	end
end)

-- ---- Public API ----

-- Game state from RestaurantController. Fields: restaurant, area,
-- hasAccepted, hasWaiting, potPlaced, allAdded, needItem, wantHeld,
-- held, awaitingSeat, usedPlateIndex.
function TutorialGuide.SetContext(newCtx)
	ctx = newCtx or {}
end

function TutorialGuide.GetContext()
	return ctx
end

function TutorialGuide.SetIntroDone(value)
	introDone = value == true
end

-- Area the spotlight is using right now (hole + pointer + hint bubble)
-- in absolute GUI coords {x, y, w, h}, or nil.
function TutorialGuide.GetHoleRect()
	return holeRectAbs
end

function TutorialGuide.IsLoaded()
	return loaded
end

-- Live zone flags ({ Chopping = bool, Cooking = bool, ... }), read by
-- reference every resolve so standing at a station is always current.
function TutorialGuide.BindZones(zoneState)
	zones = zoneState or {}
end

function TutorialGuide.IsEnabled()
	return enabled
end

-- Any number of listeners (Settings button, chef dialog, ...).
function TutorialGuide.OnEnabledChanged(fn)
	table.insert(enabledListeners, fn)
	if loaded then task.spawn(fn, enabled) end
end

function TutorialGuide.OnCompleted(fn)
	table.insert(completedListeners, fn)
end

function TutorialGuide.SetEnabled(value, persist)
	enabled = value == true
	if persist then
		task.spawn(function()
			Remotes.SetTutorial:InvokeServer(enabled)
		end)
	end
	notifyEnabled()
end

-- Called when the full loop finishes (first plate washed).
function TutorialGuide.Complete()
	if not enabled then return end
	for _, fn in completedListeners do
		task.spawn(fn)
	end
	TutorialGuide.SetEnabled(false, true)
	MessengerController.Warn("Tutorial complete! You can replay it from Settings.")
end

skipButton.Activated:Connect(function()
	TutorialGuide.SetEnabled(false, true)
	MessengerController.Warn("Tutorial skipped. Turn it back on anytime in Settings.")
end)

-- Load the saved preference (profile may still be loading - retry).
task.spawn(function()
	for _ = 1, 20 do
		local ok, value = pcall(function() return Remotes.RequestTutorial:InvokeServer() end)
		if ok and value ~= nil then
			enabled = value
			break
		end
		task.wait(1)
	end
	loaded = true
	notifyEnabled()
end)

return TutorialGuide
