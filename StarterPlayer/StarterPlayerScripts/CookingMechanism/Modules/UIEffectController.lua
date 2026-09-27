-- Camera zoom + blur when modal UIs are open (ref-counted, with a
-- self-healing watchdog: if every registered panel is actually hidden
-- but the counter thinks something's still open, snap back to normal
-- instead of leaving the zoom/blur stuck forever).
--
-- The zoom target is always a FIXED default FOV captured exactly once,
-- at module load - never re-read from the camera's current FieldOfView
-- on each Open(). Reading "current FOV" as the baseline is racy: if a
-- panel opens again before the previous close-tween has fully finished
-- (rapid clicking through several popups/panels back to back), the
-- camera is still mid-tween at that moment, so "current FOV" is some
-- partially-zoomed intermediate value, not the true spawn default. Each
-- such race baked a little extra zoom into the new baseline, and it
-- never fully unwound on close - that's the "builds up over time" bug.
-- A single fixed target eliminates that entirely: every Close() always
-- returns to the exact same number, no matter how many opens/closes or
-- races happened in between.
local Lighting      = game:GetService("Lighting")
local Workspace     = game:GetService("Workspace")
local TweenService  = game:GetService("TweenService")
local RunService    = game:GetService("RunService")

local BLUR_SIZE   = 14
local FOV_ZOOM    = 8
local TWEEN_TIME  = 0.35

local blur = Lighting:FindFirstChild("UIBlur")
if not blur then
	blur = Instance.new("BlurEffect")
	blur.Name = "UIBlur"
	blur.Size = 0
	blur.Parent = Lighting
end
blur.Enabled = false

local UIEffectController = {}
local activeCount = 0

-- Captured exactly once, at module load - this is the one and only
-- "home" FOV every Close() ever targets. 70 is Roblox's own engine
-- default, used as a sane fallback only if the camera somehow isn't
-- ready yet (shouldn't happen in practice).
local DEFAULT_FOV = (Workspace.CurrentCamera and Workspace.CurrentCamera.FieldOfView) or 70

function UIEffectController.Open()
	activeCount += 1
	if activeCount == 1 then
		local camera = Workspace.CurrentCamera
		blur.Enabled = true
		TweenService:Create(camera, TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			FieldOfView = DEFAULT_FOV - FOV_ZOOM,
		}):Play()
		TweenService:Create(blur, TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Size = BLUR_SIZE,
		}):Play()
	end
end

function UIEffectController.Close()
	activeCount = math.max(0, activeCount - 1)
	if activeCount == 0 then
		local camera = Workspace.CurrentCamera
		TweenService:Create(camera, TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			FieldOfView = DEFAULT_FOV,
		}):Play()
		local blurTween = TweenService:Create(blur, TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Size = 0,
		})
		blurTween.Completed:Connect(function()
			if activeCount == 0 then
				blur.Enabled = false
			end
		end)
		blurTween:Play()
	end
end

local registeredPanels = {}

-- Called once per modal panel (not per open/close) so the watchdog
-- always knows the full set of panels to check.
function UIEffectController.RegisterPanel(guiObject)
	table.insert(registeredPanels, guiObject)
end

local function anyPanelVisible()
	for _, panel in registeredPanels do
		if panel and panel.Parent and panel.Visible then
			return true
		end
	end
	return false
end

local function snapToNormal()
	local camera = Workspace.CurrentCamera
	camera.FieldOfView = DEFAULT_FOV
	blur.Size = 0
	blur.Enabled = false
end

-- Watchdog: if the counter says something's open but every registered
-- panel is actually hidden, the counter desynced - self-heal immediately
-- instead of leaving the player stuck zoomed/blurred forever.
RunService.Heartbeat:Connect(function()
	if activeCount > 0 and not anyPanelVisible() then
		activeCount = 0
		snapToNormal()
	end
end)

-- Extra safety net: even when activeCount correctly reads 0 (nothing
-- registered as open), if the LIVE camera FOV has still drifted off the
-- fixed default for more than a brief moment (the only legitimate
-- reason is mid-tween, which resolves within TWEEN_TIME), snap it back.
-- This catches any future zoom effect that doesn't go through this
-- module at all yet still leaves the camera off its home value.
local driftSince = nil
RunService.Heartbeat:Connect(function()
	if activeCount > 0 then
		driftSince = nil
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera then return end
	if math.abs(camera.FieldOfView - DEFAULT_FOV) > 0.05 then
		if not driftSince then
			driftSince = os.clock()
		elseif os.clock() - driftSince > TWEEN_TIME + 0.5 then
			camera.FieldOfView = DEFAULT_FOV
			driftSince = nil
		end
	else
		driftSince = nil
	end
end)

return UIEffectController
