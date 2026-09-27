-- Shared tween helpers
local TweenService = game:GetService("TweenService")

local TweenUtil = {}

function TweenUtil.Tween(instance, duration, style, direction, props)
	local info = TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
	local tween = TweenService:Create(instance, info, props)
	tween:Play()
	return tween
end

-- Cubic bezier easing (P1, P2 as control points, 0..1 range)
function TweenUtil.CubicBezier(p1x, p1y, p2x, p2y)
	local function bezierAxis(t, a, b)
		local it = 1 - t
		return 3 * it * it * t * a + 3 * it * t * t * b + t * t * t
	end
	return function(t)
		return bezierAxis(t, p1y, p2y)
	end
end

-- Drives a callback across duration using a custom easing function
function TweenUtil.PlayCustomEase(duration, easeFn, callback)
	local elapsed = 0
	local connection
	connection = game:GetService("RunService").RenderStepped:Connect(function(dt)
		elapsed += dt
		local t = math.clamp(elapsed / duration, 0, 1)
		callback(easeFn(t))
		if t >= 1 then
			connection:Disconnect()
		end
	end)
	return connection
end

function TweenUtil.AddHoverEffect(guiButton, hoverScale, clickSound)
	local baseSize = guiButton.Size
	local hoverSize = UDim2.new(
		baseSize.X.Scale * hoverScale, baseSize.X.Offset * hoverScale,
		baseSize.Y.Scale * hoverScale, baseSize.Y.Offset * hoverScale
	)

	guiButton.MouseEnter:Connect(function()
		TweenUtil.Tween(guiButton, 0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, { Size = hoverSize })
	end)
	guiButton.MouseLeave:Connect(function()
		TweenUtil.Tween(guiButton, 0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, { Size = baseSize })
	end)

	if clickSound then
		guiButton.Activated:Connect(function()
			clickSound:Play()
		end)
	end
end

function TweenUtil.TypeText(label, fullText, charDelay, isCancelled)
	label.Text = ""
	for i = 1, #fullText do
		if isCancelled and isCancelled() then return end
		label.Text = string.sub(fullText, 1, i)
		task.wait(charDelay)
	end
end

return TweenUtil
