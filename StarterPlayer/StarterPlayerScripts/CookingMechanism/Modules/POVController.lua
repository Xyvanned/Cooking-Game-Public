-- Client-side POV switcher: Default (normal Roblox camera) vs Isometric
-- (fixed-angle camera, zoomable via mouse wheel on desktop or a
-- two-finger pinch gesture on mobile/touch).
--
-- Two DECOUPLED concerns, both required together before anything hides:
--  1. currentMode must be "Isometric" (a player preference, toggled via
--     the Settings panel, stays on for the whole session once picked).
--  2. The player must be standing on IsometricPhysicalDisabler.
--     StandDetector right now.
-- Only when BOTH are true does the TransparencyDisabler content hide.
-- In Default mode, transparency NEVER applies, no matter where the
-- player stands - this is deliberately not "always on based on the
-- pad alone". Stepping off the pad while in Isometric mode restores
-- transparency immediately; switching to Default also restores it
-- immediately regardless of the pad.
--
-- TransparencyDisabler holds two folders, each with its own target
-- transparency when hidden:
--   CustomTransparent -> Transparency = 0.65
--   Transparent100    -> Transparency = 1
-- (Any other loose BasePart/Model directly under TransparencyDisabler,
-- from before these two folders existed, still falls back to full 1.)

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")
local UserInputService  = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local POVController = {}

local MODE_DEFAULT   = "Default"
local MODE_ISOMETRIC = "Isometric"

-- Base camera offset from the character in isometric mode. The classic
-- ~45-degree angle. The X sign/magnitude is what side of the character
-- the camera sits on - less negative/more positive shifts the camera
-- toward the right (which pushes the character further left on screen).
-- Y = height, Z = depth. Zoom scales this whole vector.
local ISO_OFFSET = Vector3.new(-35, 30, 28)
local ISO_FOV    = 40

-- Zoom: a scalar multiplier on ISO_OFFSET, adjusted by the mouse wheel.
local ISO_ZOOM_MIN  = 0.25  -- closest
local ISO_ZOOM_MAX  = 2.5  -- farthest
local ISO_ZOOM_STEP = 0.12 -- per wheel notch
local isoZoom = 1

local currentMode = MODE_DEFAULT
local activeRestaurant = nil
local cameraConn = nil
local transparencyConn = nil
local zoomConn = nil
local pinchConn = nil
local pinchStartZoom = nil -- isoZoom captured at TouchPinch Begin, nil when no pinch in progress
local roofHidden = false -- transparency currently applied?

-- Remember what we changed so we restore each part exactly.
local savedTransparency = {} -- BasePart -> original Transparency

local function getDisabler(restaurant)
	return restaurant and restaurant:FindFirstChild("IsometricPhysicalDisabler")
end

local function getHRP()
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

-- ---- Transparency (Isometric mode AND StandDetector, both required) ----

local function applyToRoot(root, targetTransparency, hidden)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			if hidden then
				if savedTransparency[d] == nil then
					savedTransparency[d] = d.Transparency
				end
				d.Transparency = targetTransparency
			else
				if savedTransparency[d] ~= nil then
					d.Transparency = savedTransparency[d]
					savedTransparency[d] = nil
				end
			end
		end
	end
end

local function setRoofHidden(restaurant, hidden)
	local disabler = getDisabler(restaurant)
	local folder = disabler and disabler:FindFirstChild("TransparencyDisabler")
	if not folder then return end

	for _, child in folder:GetChildren() do
		if child.Name == "CustomTransparent" then
			applyToRoot(child, 0.65, hidden)
		elseif child.Name == "Transparent100" then
			applyToRoot(child, 1, hidden)
		elseif child:IsA("BasePart") then
			if hidden then
				if savedTransparency[child] == nil then savedTransparency[child] = child.Transparency end
				child.Transparency = 1
			else
				if savedTransparency[child] ~= nil then
					child.Transparency = savedTransparency[child]
					savedTransparency[child] = nil
				end
			end
		elseif child:IsA("Model") or child:IsA("Folder") then
			-- Legacy grouped content predating the two named folders.
			applyToRoot(child, 1, hidden)
		end
	end
	roofHidden = hidden
end

-- Is the player standing on the StandDetector pad right now?
local function onStandPad(restaurant)
	local disabler = getDisabler(restaurant)
	local pad = disabler and disabler:FindFirstChild("StandDetector")
	local hrp = getHRP()
	if not (pad and hrp) then return false end
	local rel = pad.CFrame:PointToObjectSpace(hrp.Position)
	local half = pad.Size * 0.5
	return math.abs(rel.X) <= half.X
		and math.abs(rel.Z) <= half.Z
		and math.abs(rel.Y) <= (half.Y + 8)
end

-- Always running once a restaurant is known: toggles the disabler's
-- transparency, but ONLY when currentMode is Isometric AND the player is
-- on the pad. In Default mode this always resolves to "not hidden".
local function startTransparencyLoop()
	if transparencyConn then return end
	transparencyConn = RunService.Heartbeat:Connect(function()
		if not activeRestaurant or not activeRestaurant.Parent then
			if roofHidden then setRoofHidden(activeRestaurant, false) end
			return
		end
		local shouldHide = (currentMode == MODE_ISOMETRIC) and onStandPad(activeRestaurant)
		if shouldHide ~= roofHidden then
			setRoofHidden(activeRestaurant, shouldHide)
		end
	end)
end

-- ---- Isometric camera ----

local function updateIsoCamera()
	local hrp = getHRP()
	if not hrp then return end
	local focus = hrp.Position
	camera.CFrame = CFrame.lookAt(focus + ISO_OFFSET * isoZoom, focus)
end

local function startCameraLoop()
	if cameraConn then return end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = ISO_FOV
	cameraConn = RunService.RenderStepped:Connect(updateIsoCamera)

	-- Mouse-wheel zoom while in isometric mode (Scriptable camera eats the
	-- default wheel zoom, so we drive it ourselves).
	if not zoomConn then
		zoomConn = UserInputService.InputChanged:Connect(function(input, gameProcessed)
			if gameProcessed then return end
			if currentMode ~= MODE_ISOMETRIC then return end
			if input.UserInputType == Enum.UserInputType.MouseWheel then
				isoZoom = math.clamp(isoZoom - input.Position.Z * ISO_ZOOM_STEP, ISO_ZOOM_MIN, ISO_ZOOM_MAX)
			end
		end)
	end

	-- Pinch-to-zoom on mobile/touch, same idea as the mouse wheel above:
	-- the Scriptable camera doesn't get any built-in pinch handling, so we
	-- drive isoZoom from UserInputService.TouchPinch ourselves. `scale` is
	-- cumulative relative to the pinch gesture's starting finger distance
	-- (not a per-frame delta), so we snapshot isoZoom once at Begin and
	-- divide it by scale each Change: fingers spreading apart (scale > 1,
	-- "pinch out") shrinks isoZoom -> camera moves closer -> zooms in;
	-- pinching in (scale < 1) zooms back out. Matches desktop's zoom range.
	if not pinchConn then
		pinchConn = UserInputService.TouchPinch:Connect(function(_touchPositions, scale, _velocity, state, gameProcessed)
			if gameProcessed then return end
			if currentMode ~= MODE_ISOMETRIC then return end
			if state == Enum.UserInputState.Begin then
				pinchStartZoom = isoZoom
			elseif state == Enum.UserInputState.Change then
				if pinchStartZoom and scale > 0 then
					isoZoom = math.clamp(pinchStartZoom / scale, ISO_ZOOM_MIN, ISO_ZOOM_MAX)
				end
			else -- End or Cancel
				pinchStartZoom = nil
			end
		end)
	end
end

local function stopCameraLoop()
	if cameraConn then cameraConn:Disconnect() cameraConn = nil end
	if zoomConn then zoomConn:Disconnect() zoomConn = nil end
	if pinchConn then pinchConn:Disconnect() pinchConn = nil end
	pinchStartZoom = nil
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
end

-- ---- Public API ----

-- Tells the controller which restaurant's disabler to use, and (re)starts
-- the always-on transparency loop for it.
function POVController.SetRestaurant(restaurant)
	activeRestaurant = restaurant
	startTransparencyLoop()
end

function POVController.SetMode(mode)
	if mode ~= MODE_DEFAULT and mode ~= MODE_ISOMETRIC then return end
	if mode == currentMode then return end
	currentMode = mode

	if mode == MODE_ISOMETRIC then
		startCameraLoop()
	else
		stopCameraLoop()
		-- Default: transparency must never apply here, regardless of the
		-- pad - force it off immediately instead of waiting for the next
		-- transparency-loop tick to notice the mode changed.
		if roofHidden then
			setRoofHidden(activeRestaurant, false)
		end
	end
end

function POVController.GetMode()
	return currentMode
end

return POVController
