-- Orchestrates all in-restaurant gameplay
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local TweenUtil            = require(script.Parent.Modules.TweenUtil)
local SoundController      = require(script.Parent.Modules.SoundController)
local MessengerController  = require(script.Parent.Modules.MessengerController)
local InventoryController  = require(script.Parent.Modules.InventoryController)
local UIEffectController   = require(script.Parent.Modules.UIEffectController)
local POVController        = require(script.Parent.Modules.POVController)
local PanelManager         = require(script.Parent.Modules.PanelManager)
-- Also used as a tiny shared state bag (orderOpen / awaitingSeat /
-- usedPlateIndex) so no new top-level locals are needed here - this
-- chunk is near Luau's ~200-local limit.
local TutorialGuide        = require(script.Parent.Modules.TutorialGuide)
local CookingConfig        = require(ReplicatedStorage.CookingMechanism.Configs.CookingConfig)
local RecipeConfig         = CookingConfig.RecipeConfig
local AssetRegistry        = require(ReplicatedStorage.CookingMechanism.Configs.AssetRegistry)
local CustomerConfig       = require(ReplicatedStorage.CookingMechanism.Configs.CustomerConfig)
local FunFacts             = require(ReplicatedStorage.CookingMechanism.Configs.FunFacts)
local LoadingConfig        = require(ReplicatedStorage.CookingMechanism.Configs.LoadingConfig)

local ProximityPromptService = game:GetService("ProximityPromptService")

local StarterGui = game:GetService("StarterGui")
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local Remotes = ReplicatedStorage.CookingMechanism.Remotes
local clickSound = SoundController.Get("UIClicks")

local function getRestaurant()
	local cm = workspace:FindFirstChild("CookingMechanism")
	local restaurants = cm and cm:FindFirstChild("Restaurants")
	if not restaurants then return nil end
	for _, r in restaurants:GetChildren() do
		local ov = r:FindFirstChild("Owner")
		if ov and ov.Value == player.UserId then return r end
	end
	return nil
end

-- Wait for CookingMechanismGui to be enabled
local cmGui = playerGui:WaitForChild("CookingMechanismGui")

-- ---- Money counter (mirrors leaderstats.Money, set server-side) ----

local moneyCounterLabel = cmGui:WaitForChild("Counter"):WaitForChild("MoneyCounter")

local function refreshMoneyCounter()
	local leaderstats = player:FindFirstChild("leaderstats")
	local money = leaderstats and leaderstats:FindFirstChild("Money")
	moneyCounterLabel.Text = "$" .. tostring(money and money.Value or 0)
end

task.spawn(function()
	local leaderstats = player:WaitForChild("leaderstats")
	local money = leaderstats:WaitForChild("Money")
	money.Changed:Connect(refreshMoneyCounter)
	refreshMoneyCounter()
end)

local invFrame    = cmGui:WaitForChild("InventoryFrameContainer")
local showInvBtn  = invFrame:WaitForChild("ShowInventory")
local hoverInv    = invFrame:WaitForChild("HoverInventory")
local hoverScroll = hoverInv:WaitForChild("ItemSelection")
local hoverTpl    = hoverScroll:WaitForChild("Template")
local hoverExit   = hoverInv:WaitForChild("Exit")
local coreUI      = cmGui:WaitForChild("CoreRelatedUIContainer")
coreUI.Visible = true -- children control their own visibility individually
local popupFrame  = coreUI:WaitForChild("UIPopUpRequest")
UIEffectController.RegisterPanel(popupFrame)
local askLabel    = popupFrame:WaitForChild("Ask")
local yesBtn      = popupFrame:WaitForChild("Yes")
local noBtn       = popupFrame:WaitForChild("No")
local storageUI   = coreUI:WaitForChild("IngredientStorage")
UIEffectController.RegisterPanel(storageUI)
local container   = storageUI:WaitForChild("Container")
local scrollFrame = container:WaitForChild("RecipeIndexContainer")
local itemTemplate = scrollFrame:WaitForChild("IngredientTemplate")
local showInfo    = container:WaitForChild("ShowInfo")
local showInfoUse = showInfo:WaitForChild("ButtonContainer"):WaitForChild("Use")
local showInfoImg = showInfo:WaitForChild("IngredientImage")
local showInfoName = showInfo:WaitForChild("ItemName")
local exitStorage = storageUI:WaitForChild("Exit")
local returnBtn   = storageUI:FindFirstChild("Return")

-- FridgeStorage: same structure/function as IngredientStorage, just a
-- different naming convention and a different item list (frozen/
-- refrigerated items - CookingConfig.FridgeItems).
local fridgeStorageUI    = coreUI:WaitForChild("FridgeStorage")
UIEffectController.RegisterPanel(fridgeStorageUI)
local fridgeContainer    = fridgeStorageUI:WaitForChild("Container")
local fridgeScrollFrame  = fridgeContainer:WaitForChild("IngredientsContainer")
local fridgeItemTemplate = fridgeScrollFrame:WaitForChild("IngredientTemplate")
local fridgeShowInfo     = fridgeContainer:WaitForChild("ShowInfo")
local fridgeShowInfoUse  = fridgeShowInfo:WaitForChild("ButtonContainer"):WaitForChild("Use")
local fridgeShowInfoImg  = fridgeShowInfo:WaitForChild("IngredientImage")
local fridgeShowInfoName = fridgeShowInfo:WaitForChild("ItemName")
local exitFridgeStorage  = fridgeStorageUI:WaitForChild("Exit")
local fridgeReturnBtn    = fridgeStorageUI:FindFirstChild("Return")

local BEZIER = TweenUtil.CubicBezier(0.34, 1.56, 0.64, 1)
local POPUP_DIST = CookingConfig.DETECT_DISTANCE

TweenUtil.AddHoverEffect(yesBtn, 1.06, clickSound)
TweenUtil.AddHoverEffect(noBtn,  1.06, clickSound)
TweenUtil.AddHoverEffect(exitStorage, 1.06, clickSound)
TweenUtil.AddHoverEffect(showInvBtn, 1.08, clickSound)
TweenUtil.AddHoverEffect(hoverExit, 1.06, clickSound)
TweenUtil.AddHoverEffect(showInfoUse, 1.06, clickSound)
TweenUtil.AddHoverEffect(exitFridgeStorage, 1.06, clickSound)
TweenUtil.AddHoverEffect(fridgeShowInfoUse, 1.06, clickSound)

local pendingStorageItem = nil -- item currently displayed in ShowInfo
local pendingFridgeItem = nil -- item currently displayed in FridgeStorage's ShowInfo

-- ---- HoverInventory toggle (overflow only, no hotbar duplicates) ----

local hoverOpen = false

local function refreshHoverInventory()
	for _, c in hoverScroll:GetChildren() do
		if c:IsA("ImageButton") and c.Name ~= "Template" then c:Destroy() end
	end
	local overflow = InventoryController.GetOverflowItems()
	for i, data in overflow do
		local btn = hoverTpl:Clone()
		btn.LayoutOrder = i
		btn.Visible = true
		btn.Name = data.Name
		local img = btn:FindFirstChild("ItemImage")
		if img then img.Image = AssetRegistry.GetIngredientImage(data.Name) end
		local lbl = btn:FindFirstChild("ItemName")
		if lbl then lbl.Text = data.Name end
		local num = btn:FindFirstChild("SlotNumber")
		if num then num.Text = tostring(data.Count) end
		TweenUtil.AddHoverEffect(btn, 1.05, clickSound)
		btn.Activated:Connect(function()
			if clickSound then clickSound:Play() end
			local result = Remotes.ToggleHold:InvokeServer(data.Name)
			if result and result.Success then
				InventoryController.SetHeld(result.Holding and data.Name or nil)
			end
		end)
		InventoryController.MakeDraggable(btn, "Overflow", data.Name)
		btn.Parent = hoverScroll
	end
end

InventoryController.OnOverflowChanged(refreshHoverInventory)

local function openHoverInventory()
	if hoverOpen then return end
	PanelManager.CloseAllExcept("HoverInventory")
	hoverOpen = true
	refreshHoverInventory()
	hoverInv.Size = UDim2.new(0.1, 0, 0.1, 0)
	hoverInv.ImageTransparency = 1
	hoverInv.Visible = true
	TweenUtil.PlayCustomEase(0.35, BEZIER, function(alpha)
		hoverInv.Size = UDim2.new(0.45 * alpha, 0, 0.45 * alpha, 0)
		hoverInv.ImageTransparency = 1 - alpha
	end)
end

local function closeHoverInventory()
	if not hoverOpen then return end
	TweenUtil.Tween(hoverInv, 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In, {
		Size = UDim2.new(0.1, 0, 0.1, 0),
		ImageTransparency = 1,
	})
	task.wait(0.2)
	hoverInv.Visible = false
	hoverOpen = false
end

PanelManager.Register("HoverInventory", closeHoverInventory)

showInvBtn.Activated:Connect(function()
	if hoverOpen then closeHoverInventory() else openHoverInventory() end
end)
hoverExit.Activated:Connect(closeHoverInventory)

-- ---- Customer panel toggle (OptionSelectionToggles -> Customer) ----

local optionToggles = cmGui:WaitForChild("OptionSelectionToggles")
local customerToggleBtn = optionToggles:WaitForChild("Customer")

-- Forward-declared: real implementations are assigned further down once
-- customerPanelOpen/openCustomerPanel/closeCustomerPanel exist. Needed
-- here because the spotlight overlay (built immediately below, right
-- after this button reference) has to wire its click handler before
-- those are in scope.
local hasAcceptedCustomer = false -- gates the whole cooking mechanism - must accept someone first

-- Full-screen spotlight: cmGui is switched to Global ZIndexBehavior so a
-- single full-screen dim Frame (parented directly to cmGui, high ZIndex)
-- can sit above everything, while the REAL Customer button just gets an
-- even higher ZIndex - no cloning or cross-ScreenGui position math
-- needed, it naturally pokes through pixel-perfectly since it's the
-- exact same instance. Dim blocks all other clicks; the real button's
-- own existing Activated handler (wired further below) also hides this.
cmGui.ZIndexBehavior = Enum.ZIndexBehavior.Global

local customerGuideDim = Instance.new("Frame")
customerGuideDim.Name = "CustomerGuideDim"
customerGuideDim.Size = UDim2.new(1, 0, 1, 0)
customerGuideDim.Position = UDim2.new(0, 0, 0, 0)
customerGuideDim.BackgroundColor3 = Color3.new(0, 0, 0)
customerGuideDim.BackgroundTransparency = 0.5
customerGuideDim.BorderSizePixel = 0
customerGuideDim.ZIndex = 1000
customerGuideDim.Active = true
customerGuideDim.Visible = false
customerGuideDim.Parent = cmGui

-- Lift the button AND its whole subtree (ClickIndicator, label...) by the
-- same amount - in Global mode, children left at their authored ZIndex
-- would otherwise render underneath the dim.
do
	local delta = 1001 - customerToggleBtn.ZIndex
	customerToggleBtn.ZIndex = 1001
	for _, d in customerToggleBtn:GetDescendants() do
		if d:IsA("GuiObject") then d.ZIndex += delta end
	end
end

local function hideCustomerGuide()
	customerGuideDim.Visible = false
end

-- Only shows while a customer is actually WAITING to be accepted (not
-- just "none accepted yet" - no point nagging when nobody has shown up).
local hasWaitingCustomer = false

-- The old 50% customer-only dim is superseded by Modules.TutorialGuide's
-- spotlight (which also covers the Customer button step). Kept as a
-- no-op so existing call sites stay valid; the ClickIndicator blink
-- still runs for players with the tutorial turned off.
local function showCustomerGuideIfNeeded()
end

-- Blinking "Click!" callout on the Customer button itself, same gating.
local clickIndicator = customerToggleBtn:WaitForChild("ClickIndicator")
local clickIndicatorBlinking = false

local function startClickIndicatorBlink()
	if clickIndicatorBlinking then return end
	clickIndicatorBlinking = true
	clickIndicator.Visible = true
	task.spawn(function()
		while clickIndicatorBlinking do
			clickIndicator.Visible = not clickIndicator.Visible
			task.wait(0.5)
		end
		clickIndicator.Visible = false
	end)
end

local function stopClickIndicatorBlink()
	clickIndicatorBlinking = false
end

customerToggleBtn.Activated:Connect(function()
	hideCustomerGuide()
	stopClickIndicatorBlink()
end)
local customerFrame = cmGui:WaitForChild("Customer")
UIEffectController.RegisterPanel(customerFrame)
local customerExit = customerFrame:WaitForChild("Exit")
local customerTabToggle = customerFrame:FindFirstChild("Return") -- slides between the two lists
local customerSelContainer = customerFrame:WaitForChild("SelectionContainer")
local customerSelection = customerSelContainer:WaitForChild("CustomerSelection")
local customerSelTemplate = customerSelection:WaitForChild("CustomerTemplate")
local customerSelHover = customerSelContainer:WaitForChild("CustomerSelectionHoverCard")
local customerEating = customerSelContainer:WaitForChild("CustomerCurrentlyEating")
local customerEatingTemplate = customerEating:WaitForChild("CustomerTemplate")
local customerEatingHover = customerSelContainer:WaitForChild("CustomerEatingHoverCard")

customerSelTemplate.Visible = false
customerEatingTemplate.Visible = false

TweenUtil.AddHoverEffect(customerToggleBtn, 1.08, clickSound)
TweenUtil.AddHoverEffect(customerExit, 1.06, clickSound)
if customerTabToggle then
	TweenUtil.AddHoverEffect(customerTabToggle, 1.06, clickSound)
end

local customerPanelOpen = false
local showingEatingTab = false
local showSelectionHoverCard, showEatingHoverCard
local refreshGuideHighlights = function() end -- reassigned once real areas are known
local dishReadyAtKitchenIsle = false
-- gates the whole cooking mechanism - must accept someone first
local openHoverSeatIndex = nil -- which waiting-list hover card is currently shown, if any

local function refreshCustomerLists()
	local restaurant = getRestaurant()
	if not restaurant then return end

	local data = Remotes.RequestCustomerList:InvokeServer()
	if not data then return end

	-- Waiting list
	for _, c in customerSelection:GetChildren() do
		if c:IsA("ImageButton") and c ~= customerSelTemplate then c:Destroy() end
	end
	-- Server builds these lists from a keyed table (no guaranteed order),
	-- so sort by seat before assigning LayoutOrder.
	table.sort(data.Waiting, function(a, b) return a.SeatIndex < b.SeatIndex end)
	table.sort(data.Eating, function(a, b) return a.SeatIndex < b.SeatIndex end)
	for i, entry in data.Waiting do
		local btn = customerSelTemplate:Clone()
		btn.LayoutOrder = i
		btn.Visible = true
		btn.Name = "Seat" .. entry.SeatIndex
		local nameLbl = btn:FindFirstChild("CustomerName")
		local rarityLbl = btn:FindFirstChild("CustomerRarity")
		if nameLbl then nameLbl.Text = entry.Name end
		if rarityLbl then rarityLbl.Text = entry.Rarity end
		CustomerConfig.ApplyRarityGradient(rarityLbl, entry.Rarity)
		TweenUtil.AddHoverEffect(btn, 1.05, clickSound)
		btn.Activated:Connect(function()
			if clickSound then clickSound:Play() end
			showSelectionHoverCard(entry)
		end)
		btn.Parent = customerSelection

		-- Keep an already-open hover card's patience counter live and accurate
		if openHoverSeatIndex == entry.SeatIndex and customerSelHover.Visible then
			local patience = customerSelHover:FindFirstChild("PatienceCounter")
			if patience then
				local m = math.floor(entry.PatienceLeft / 60)
				local s = entry.PatienceLeft % 60
				patience.Text = string.format("%d:%02d", m, s)
			end
		end
	end

	-- Eating list
	for _, c in customerEating:GetChildren() do
		if c:IsA("ImageButton") and c ~= customerEatingTemplate then c:Destroy() end
	end
	for i, entry in data.Eating do
		local btn = customerEatingTemplate:Clone()
		btn.LayoutOrder = i
		btn.Visible = true
		btn.Name = "Seat" .. entry.SeatIndex
		local nameLbl = btn:FindFirstChild("CustomerName")
		local rarityLbl = btn:FindFirstChild("CustomerRarity")
		if nameLbl then nameLbl.Text = entry.Name end
		if rarityLbl then rarityLbl.Text = entry.Rarity end
		CustomerConfig.ApplyRarityGradient(rarityLbl, entry.Rarity)
		TweenUtil.AddHoverEffect(btn, 1.05, clickSound)
		btn.Activated:Connect(function()
			if clickSound then clickSound:Play() end
			showEatingHoverCard(entry)
		end)
		btn.Parent = customerEating
	end

	-- Light up the DiningArea table(s) that have a customer actually
	-- seated at a serving seat waiting for / eating their dish.
	local occupiedServingSeats = {}
	for _, entry in data.Eating do
		if (entry.Status == "AwaitingFood" or entry.Status == "Accepted")
			and entry.ServingSeatIndex then
			occupiedServingSeats[entry.ServingSeatIndex] = true
		end
	end
	setActiveTables(occupiedServingSeats)
end

showSelectionHoverCard = function(entry)
	openHoverSeatIndex = entry.SeatIndex
	local hint = customerSelHover:FindFirstChild("HintText")
	local patience = customerSelHover:FindFirstChild("PatienceCounter")
	if hint then hint.Text = entry.Name .. " (" .. entry.Rarity .. ")" end
	if patience then
		local m = math.floor(entry.PatienceLeft / 60)
		local s = entry.PatienceLeft % 60
		patience.Text = string.format("%d:%02d", m, s)
	end
	customerSelHover:SetAttribute("SeatIndex", entry.SeatIndex)
	customerSelHover.Visible = true
end

showEatingHoverCard = function(entry)
	local hint = customerEatingHover:FindFirstChild("HintText")
	if hint then hint.Text = entry.Name .. " (" .. entry.Rarity .. ")" end
	customerEatingHover:SetAttribute("SeatIndex", entry.SeatIndex)
	customerEatingHover.Visible = true
end

local selHoverReturn = customerSelHover:FindFirstChild("Return")
local selHoverAccept = customerSelHover:FindFirstChild("AcceptButton")
local selHoverDecline = customerSelHover:FindFirstChild("DeclineButton")
local eatHoverReturn = customerEatingHover:FindFirstChild("Return")

if selHoverReturn then
	TweenUtil.AddHoverEffect(selHoverReturn, 1.06, clickSound)
	selHoverReturn.Activated:Connect(function()
		if clickSound then clickSound:Play() end
		openHoverSeatIndex = nil
		customerSelHover.Visible = false
	end)
end

if selHoverAccept then
	TweenUtil.AddHoverEffect(selHoverAccept, 1.06, clickSound)
	selHoverAccept.Activated:Connect(function()
		if clickSound then clickSound:Play() end
		local seatIndex = customerSelHover:GetAttribute("SeatIndex")
		if seatIndex then
			-- Only flip to "accepted" if the server actually agreed (the
			-- customer may have just run out of patience, or every serving
			-- seat is taken) - otherwise the guide would start an order that
			-- doesn't exist.
			local accepted, reason = Remotes.RespondToCustomer:InvokeServer(seatIndex, true)
			if accepted then
				TutorialGuide.orderOpen = true
				-- Flip immediately rather than waiting for the 1/sec poll, so
				-- the guide highlights turn on the instant an order is accepted.
				hasAcceptedCustomer = true
				refreshGuideHighlights()
			elseif reason == "NoServingSeat" then
				MessengerController.Warn("All tables are full - serve someone first!")
			else
				MessengerController.Warn("That customer already left.")
			end
		end
		openHoverSeatIndex = nil
		customerSelHover.Visible = false
		refreshCustomerLists()
	end)
end

if selHoverDecline then
	TweenUtil.AddHoverEffect(selHoverDecline, 1.06, clickSound)
	selHoverDecline.Activated:Connect(function()
		if clickSound then clickSound:Play() end
		local seatIndex = customerSelHover:GetAttribute("SeatIndex")
		if seatIndex then
			Remotes.RespondToCustomer:InvokeServer(seatIndex, false)
		end
		openHoverSeatIndex = nil
		customerSelHover.Visible = false
		refreshCustomerLists()
	end)
end

if eatHoverReturn then
	TweenUtil.AddHoverEffect(eatHoverReturn, 1.06, clickSound)
	eatHoverReturn.Activated:Connect(function()
		if clickSound then clickSound:Play() end
		customerEatingHover.Visible = false
	end)
end

-- Return acts as a tab slider: toggles which list is visible
local function setEatingTabVisible(showEating)
	showingEatingTab = showEating
	customerSelection.Visible = not showEating
	customerEating.Visible = showEating
	openHoverSeatIndex = nil
	customerSelHover.Visible = false
	customerEatingHover.Visible = false
end

if customerTabToggle then
	customerTabToggle.Activated:Connect(function()
		if clickSound then clickSound:Play() end
		setEatingTabVisible(not showingEatingTab)
	end)
end

local customerRefreshThread = nil

local function openCustomerPanel()
	if customerPanelOpen then return end
	PanelManager.CloseAllExcept("Customer")
	customerPanelOpen = true
	UIEffectController.Open()
	setEatingTabVisible(false)
	refreshCustomerLists()
	customerFrame.Size = UDim2.new(0.1, 0, 0.1, 0)
	customerFrame.Visible = true

	TweenUtil.PlayCustomEase(0.4, BEZIER, function(alpha)
		customerFrame.Size = UDim2.new(0.6 * alpha, 0, 0.8 * alpha, 0)
	end)

	customerRefreshThread = task.spawn(function()
		while customerPanelOpen do
			task.wait(1)
			if customerPanelOpen then refreshCustomerLists() end
		end
	end)
end

local function closeCustomerPanel()
	if not customerPanelOpen then return end
	TweenUtil.Tween(customerFrame, 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In, {
		Size = UDim2.new(0.1, 0, 0.1, 0),
	})
	task.wait(0.2)
	customerFrame.Visible = false
	customerFrame.Size = UDim2.new(0.6, 0, 0.8, 0)
	customerPanelOpen = false
	openHoverSeatIndex = nil
	customerSelHover.Visible = false
	customerEatingHover.Visible = false
	UIEffectController.Close()
end

PanelManager.Register("Customer", closeCustomerPanel)

customerToggleBtn.Activated:Connect(function()
	if clickSound then clickSound:Play() end
	if customerPanelOpen then closeCustomerPanel() else openCustomerPanel() end
end)

customerExit.Activated:Connect(function()
	if clickSound then clickSound:Play() end
	closeCustomerPanel()
end)

-- ---- Settings panel toggle (OptionSelectionToggles -> Settings) ----

local settingsToggleBtn = optionToggles:WaitForChild("Settings")
local settingsPanel = cmGui:WaitForChild("OptionSelectionContaner"):WaitForChild("SettingsPanel")
UIEffectController.RegisterPanel(settingsPanel)
local settingsExit = settingsPanel:WaitForChild("Header"):WaitForChild("Exit")

TweenUtil.AddHoverEffect(settingsToggleBtn, 1.08, clickSound)
TweenUtil.AddHoverEffect(settingsExit, 1.06, clickSound)

local settingsOpen = false

local function openSettingsPanel()
	if settingsOpen then return end
	PanelManager.CloseAllExcept("Settings")
	settingsOpen = true
	UIEffectController.Open()
	settingsPanel.Size = UDim2.new(0.1, 0, 0.1, 0)
	settingsPanel.ImageTransparency = 1
	settingsPanel.Visible = true
	TweenUtil.PlayCustomEase(0.45, BEZIER, function(alpha)
		settingsPanel.Size = UDim2.new(0.38 * alpha, 0, 0.6 * alpha, 0)
		settingsPanel.ImageTransparency = 1
	end)
end

local function closeSettingsPanel()
	if not settingsOpen then return end
	TweenUtil.Tween(settingsPanel, 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In, {
		Size = UDim2.new(0.1, 0, 0.1, 0),
		ImageTransparency = 1,
	})
	task.wait(0.2)
	settingsPanel.Visible = false
	settingsOpen = false
	UIEffectController.Close()
end

PanelManager.Register("Settings", closeSettingsPanel)

-- Settings: Tutorial Guide on/off (saved on the profile).
do
	local tutorialToggle = settingsPanel:WaitForChild("Header"):FindFirstChild("TutorialToggle")
	if tutorialToggle then
		TweenUtil.AddHoverEffect(tutorialToggle, 1.06, clickSound)
		TutorialGuide.OnEnabledChanged(function(on)
			tutorialToggle.Text = on and "GUIDE: ON" or "GUIDE: OFF"
		end)
		tutorialToggle.Activated:Connect(function()
			if clickSound then clickSound:Play() end
			TutorialGuide.SetEnabled(not TutorialGuide.IsEnabled(), true)
		end)
	end
end

settingsToggleBtn.Activated:Connect(function()
	if clickSound then clickSound:Play() end
	if settingsOpen then closeSettingsPanel() else openSettingsPanel() end
end)

settingsExit.Activated:Connect(function()
	if clickSound then clickSound:Play() end
	closeSettingsPanel()
end)

-- ---- Volume sliders (drag the SeekHandle, or click anywhere on the
-- track to jump there; ProgressFill always mirrors the current value) ----

local function setupVolumeSlider(track, fill, handle, initialValue, onChanged)
	if not (track and fill and handle) then return end
	track.Active = true -- Frames default to Active=false, which blocks InputBegan

	local handleWidthScale = handle.Size.X.Scale
	local maxScale = 1 - handleWidthScale

	local function setValue(value)
		value = math.clamp(value, 0, 1)
		fill.Size = UDim2.new(value, 0, fill.Size.Y.Scale, fill.Size.Y.Offset)
		handle.Position = UDim2.new(value * maxScale, 0, handle.Position.Y.Scale, handle.Position.Y.Offset)
		if onChanged then onChanged(value) end
		return value
	end

	setValue(initialValue or 1)

	local dragging = false

	local function updateFromScreenX(screenX)
		local absPos = track.AbsolutePosition.X
		local absSize = track.AbsoluteSize.X
		if absSize <= 0 then return end
		setValue((screenX - absPos) / absSize)
	end

	local function isPointerInput(input)
		return input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
	end

	handle.InputBegan:Connect(function(input)
		if isPointerInput(input) then dragging = true end
	end)

	track.InputBegan:Connect(function(input)
		if isPointerInput(input) then
			dragging = true
			updateFromScreenX(input.Position.X)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			updateFromScreenX(input.Position.X)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if isPointerInput(input) then dragging = false end
	end)

	return setValue
end

-- Found by name anywhere inside SettingsPanel (recursive), so layout
-- changes (e.g. the Scroll.Container1 wrapper) don't break these.
local masterVolumeTrack  = settingsPanel:FindFirstChild("MasterAudioProgress", true)
local restaurantVolumeTrack = settingsPanel:FindFirstChild("RestaurantAudioRelated", true)

-- ---- Volume control: Master scales every Sound in the game; Restaurant
-- scales only this player's restaurant SoundContainer, layered on top of
-- Master. Each Sound's original Volume is remembered via an attribute so
-- repeated scale changes never compound.
local Sounds = ReplicatedStorage.CookingMechanism.Sounds
local masterScale = 1
local restaurantScale = 1

local function isInRestaurantSoundContainer(sound)
	local restaurant = getRestaurant()
	local soundContainer = restaurant and restaurant:FindFirstChild("SoundContainer")
	return soundContainer ~= nil and sound:IsDescendantOf(soundContainer)
end

local function refreshSoundVolume(sound)
	local base = sound:GetAttribute("BaseVolume")
	if base == nil then
		base = sound.Volume
		sound:SetAttribute("BaseVolume", base)
	end
	local scale = masterScale
	if isInRestaurantSoundContainer(sound) then
		scale *= restaurantScale
	end
	sound.Volume = base * scale
end

local volumeRoots = { workspace, Sounds }

local function setMasterVolume(value)
	masterScale = value
	for _, root in volumeRoots do
		for _, d in root:GetDescendants() do
			if d:IsA("Sound") then refreshSoundVolume(d) end
		end
	end
end

local function setRestaurantVolume(value)
	restaurantScale = value
	local restaurant = getRestaurant()
	local soundContainer = restaurant and restaurant:FindFirstChild("SoundContainer")
	if not soundContainer then return end
	for _, d in soundContainer:GetDescendants() do
		if d:IsA("Sound") then refreshSoundVolume(d) end
	end
end

-- Keep newly-appearing sounds (new restaurant clone, dynamic pot sounds,
-- etc.) in line with whatever scale is currently set.
for _, root in volumeRoots do
	root.DescendantAdded:Connect(function(d)
		if d:IsA("Sound") then
			task.defer(refreshSoundVolume, d)
		end
	end)
end

if masterVolumeTrack then
	setupVolumeSlider(
		masterVolumeTrack,
		masterVolumeTrack:FindFirstChild("ProgressFill"),
		masterVolumeTrack:FindFirstChild("SeekHandle"),
		1,
		setMasterVolume
	)
end

if restaurantVolumeTrack then
	setupVolumeSlider(
		restaurantVolumeTrack,
		restaurantVolumeTrack:FindFirstChild("ProgressFill"),
		restaurantVolumeTrack:FindFirstChild("SeekHandle"),
		1,
		setRestaurantVolume
	)
end

-- ---- POV changer (Default / Isometric) ----

local povChanger = settingsPanel:FindFirstChild("POVChanger", true)
if povChanger then
	local isoBtn = povChanger:FindFirstChild("Isometric")
	local defBtn = povChanger:FindFirstChild("Default")

	local SELECTED_TRANSP = 0    -- fully opaque = active
	local UNSELECTED_TRANSP = 0.5 -- dimmed = inactive

	local function reflectMode(mode)
		if isoBtn then isoBtn.TextTransparency = (mode == "Isometric") and SELECTED_TRANSP or UNSELECTED_TRANSP end
		if defBtn then defBtn.TextTransparency = (mode == "Default") and SELECTED_TRANSP or UNSELECTED_TRANSP end
	end

	if isoBtn then
		TweenUtil.AddHoverEffect(isoBtn, 1.06, clickSound)
		isoBtn.Activated:Connect(function()
			if clickSound then clickSound:Play() end
			POVController.SetMode("Isometric")
			reflectMode("Isometric")
		end)
	end
	if defBtn then
		TweenUtil.AddHoverEffect(defBtn, 1.06, clickSound)
		defBtn.Activated:Connect(function()
			if clickSound then clickSound:Play() end
			POVController.SetMode("Default")
			reflectMode("Default")
		end)
	end

	-- Default is the default view.
	reflectMode(POVController.GetMode())
end

-- ---- ThreeTopButtons: Merchant/Restaurant teleport + Recipe book ----
-- Wrapped in a do...end block: this file was hitting Luau's ~200-local
-- register limit for the whole chunk, and none of these locals need to
-- be visible outside this self-contained feature.
do

local threeTopButtons = cmGui:WaitForChild("ThreeTopButtons")
local merchantTeleportBtn = threeTopButtons:WaitForChild("Merchant"):WaitForChild("Teleport")
local restaurantTeleportBtn = threeTopButtons:WaitForChild("Restaurant"):WaitForChild("Teleport")
local recipeShowBookBtn = threeTopButtons:WaitForChild("RecipeIndex"):WaitForChild("ShowBook")

TweenUtil.AddHoverEffect(merchantTeleportBtn, 1.06, clickSound)
TweenUtil.AddHoverEffect(restaurantTeleportBtn, 1.06, clickSound)
TweenUtil.AddHoverEffect(recipeShowBookBtn, 1.06, clickSound)

local restaurantSpawnPoints = workspace:WaitForChild("CookingMechanism"):WaitForChild("RestaurantSpawnPointContainer")

local function teleportCharacterTo(attachment)
	local char = player.Character
	if not (char and attachment) then return end
	char:PivotTo(attachment.WorldCFrame + Vector3.new(0, 3, 0))
end

merchantTeleportBtn.Activated:Connect(function()
	if clickSound then clickSound:Play() end
	teleportCharacterTo(restaurantSpawnPoints:FindFirstChild("Market"))
end)

restaurantTeleportBtn.Activated:Connect(function()
	if clickSound then clickSound:Play() end
	-- The actual spawn points live in ServerStorage (never replicated to
	-- clients), so the server picks the right one and does the teleport.
	Remotes.RequestRestaurantTeleport:InvokeServer()
end)

-- ---- Recipe Index book (browse all recipes + equip up to 3 owned
-- ones). Only Adobo exists right now, so it's the only thing shown on
-- either page, but this is written to extend cleanly once more recipes
-- are added (one rarity template per recipe rarity, shown/filled in
-- based on RecipeConfig.GetAll()). ----

local recipeIndexUI = coreUI:WaitForChild("RecipeIndex")
UIEffectController.RegisterPanel(recipeIndexUI)
local recipeExit = recipeIndexUI:WaitForChild("Exit")

local firstPage = recipeIndexUI:WaitForChild("FirstPage")
local firstPageContainer = firstPage:WaitForChild("RecipeIndexContainer")
local firstPageShowInfo = firstPage:WaitForChild("ShowInfo")
local firstShowInfoImg = firstPageShowInfo:WaitForChild("RecipeImage")
local firstShowInfoName = firstPageShowInfo:WaitForChild("ItemName")
local firstShowInfoRarity = firstPageShowInfo:WaitForChild("Rarity")
local firstShowInfoReturn = firstPageShowInfo:WaitForChild("Return")

local secondPage = recipeIndexUI:WaitForChild("SecondPage")
local secondPageContainer = secondPage:WaitForChild("RecipeOwnedContainer")
local secondPageShowInfo = secondPage:WaitForChild("ShowInfo")
local secondShowInfoImg = secondPageShowInfo:WaitForChild("RecipeImage")
local secondShowInfoName = secondPageShowInfo:WaitForChild("ItemName")
local secondShowInfoRarity = secondPageShowInfo:WaitForChild("Rarity")
local secondShowInfoReturn = secondPageShowInfo:WaitForChild("Return")
local secondShowInfoEquip = secondPageShowInfo:WaitForChild("ButtonContainer"):WaitForChild("Equip")
local secondShowInfoUnequip = secondPageShowInfo:WaitForChild("ButtonContainer"):WaitForChild("Unequip")

local MAX_EQUIPPED_RECIPES = 3
-- Adobo starts equipped since it's the only recipe that exists so far.
-- Client-only for now (no server-side gameplay effect yet from which
-- recipes are equipped - RecipeConfig.ActiveRecipe is still global).
local equippedRecipes = { Adobo = true }
local pendingRecipeKey = nil

local function forEachRarityTemplate(container, callback)
	for _, child in container:GetChildren() do
		if child:IsA("ImageButton") and child.Name:match("Template$") then
			callback(child, (child.Name:gsub("Template$", "")))
		end
	end
end

-- "Learn More" card: shows the recipe's dining-crowd split as two fill
-- bars (Casual vs High Class), plus a flag image and its price. The
-- Filler frames (CasualDinnerFiller/HighClassDinerFiller) already have
-- their own rounded-corner/gradient styling and act as the bar's track;
-- a "Fill" child is added once inside each and resized to the actual
-- percentage on top of that track.
local function getOrCreateFill(fillerFrame, gradientColors)
	local fill = fillerFrame:FindFirstChild("Fill")
	if not fill then
		fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.BorderSizePixel = 0
		fill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		fill.Position = UDim2.new(0, 0, 0, 0)
		fill.Size = UDim2.new(0, 0, 1, 0)
		fill.ZIndex = fillerFrame.ZIndex + 1
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = fill
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(gradientColors[1], gradientColors[2])
		gradient.Rotation = 0
		gradient.Parent = fill
		fill.Parent = fillerFrame
	end
	return fill
end

local function setupLearnMoreCard(showInfoFrame)
	local card = showInfoFrame:FindFirstChild("LearnMoreCard")
	local casualFiller = card and card:FindFirstChild("CasualDinnerFiller")
	local highClassFiller = card and card:FindFirstChild("HighClassDinerFiller")
	local flag = card and card:FindFirstChild("Flag")
	local casualPercentLabel = card and card:FindFirstChild("CasualPercentage")
	local highClassPercentLabel = card and card:FindFirstChild("HighClassPercentage")
	local valueLabel = card and card:FindFirstChild("Value")
	local buttonContainer = showInfoFrame:FindFirstChild("ButtonContainer")
	local learnMoreBtn = buttonContainer and buttonContainer:FindFirstChild("LearnMore")

	-- This page's LearnMoreCard isn't fully built out yet (e.g. SecondPage
	-- currently ships as an empty placeholder ImageLabel) - degrade
	-- gracefully instead of hanging on a WaitForChild that never resolves
	-- or erroring on a nil field. The button still exists either way, so
	-- just make it a no-op until the card catches up.
	if not (card and casualFiller and highClassFiller and flag
		and casualPercentLabel and highClassPercentLabel and valueLabel) then
		if card then card.Visible = false end
		return function() end, card
	end

	card.Visible = false
	if learnMoreBtn then
		TweenUtil.AddHoverEffect(learnMoreBtn, 1.06, clickSound)
	end

	-- Casual = warm, friendly orange-to-yellow gradient; High Class =
	-- rich purple-to-gold gradient, so the two bars read distinctly at a
	-- glance even before checking the percentage labels.
	local casualFill = getOrCreateFill(casualFiller, {
		Color3.fromRGB(255, 145, 60),
		Color3.fromRGB(255, 214, 92),
	})
	local highClassFill = getOrCreateFill(highClassFiller, {
		Color3.fromRGB(122, 63, 196),
		Color3.fromRGB(255, 200, 87),
	})

	local function populate(recipe)
		local dinnerType = recipe.DinnerType or { Casual = 0, HighClass = 0 }
		local casualPct = dinnerType.Casual or 0
		local highClassPct = dinnerType.HighClass or 0

		casualFill.Size = UDim2.new(casualPct / 100, 0, 1, 0)
		highClassFill.Size = UDim2.new(highClassPct / 100, 0, 1, 0)
		casualPercentLabel.Text = casualPct .. "%"
		highClassPercentLabel.Text = highClassPct .. "%"
		flag.Image = AssetRegistry.GetFlagImage(recipe.Key)
		valueLabel.Text = "$" .. tostring(recipe.Price or 0)
	end

	if learnMoreBtn then
		learnMoreBtn.Activated:Connect(function()
			if clickSound then clickSound:Play() end
			card.Visible = not card.Visible
		end)
	end

	return populate, card
end

local populateFirstLearnMore, firstLearnMoreCard = setupLearnMoreCard(firstPageShowInfo)
local populateSecondLearnMore, secondLearnMoreCard = setupLearnMoreCard(secondPageShowInfo)

local function showFirstPageInfo(recipe)
	firstPageContainer.Visible = false
	firstPageShowInfo.Visible = true
	firstShowInfoImg.Image = AssetRegistry.GetRecipeImage(recipe.Key, true)
	firstShowInfoName.Text = recipe.DisplayName
	firstShowInfoRarity.Text = recipe.Rarity or "Common"
	CustomerConfig.ApplyRarityGradient(firstShowInfoRarity, recipe.Rarity or "Common")
	populateFirstLearnMore(recipe)
	firstLearnMoreCard.Visible = false
end

local function hideFirstPageInfo()
	firstPageShowInfo.Visible = false
	firstLearnMoreCard.Visible = false
	firstPageContainer.Visible = true
end

TweenUtil.AddHoverEffect(firstShowInfoReturn, 1.06, clickSound)
firstShowInfoReturn.Activated:Connect(function()
	if clickSound then clickSound:Play() end
	hideFirstPageInfo()
end)

local function buildFirstPage()
	forEachRarityTemplate(firstPageContainer, function(template)
		template.Visible = false
	end)
	for _, recipe in RecipeConfig.GetAll() do
		local template = firstPageContainer:FindFirstChild((recipe.Rarity or "Common") .. "Template")
		if template then
			template.Visible = true
			local img = template:FindFirstChild("ItemImage")
			if img then img.Image = AssetRegistry.GetRecipeImage(recipe.Key, true) end
			local lbl = template:FindFirstChild("ItemName")
			if lbl then lbl.Text = recipe.DisplayName end
		end
	end
end

forEachRarityTemplate(firstPageContainer, function(template, rarity)
	TweenUtil.AddHoverEffect(template, 1.05, clickSound)
	template.Activated:Connect(function()
		if clickSound then clickSound:Play() end
		for _, recipe in RecipeConfig.GetAll() do
			if (recipe.Rarity or "Common") == rarity then
				showFirstPageInfo(recipe)
				break
			end
		end
	end)
end)

local function reflectEquipButtons(recipeKey)
	local isEquipped = equippedRecipes[recipeKey] == true
	secondShowInfoEquip.Visible = not isEquipped
	secondShowInfoUnequip.Visible = isEquipped
end

local function showSecondPageInfo(recipe)
	pendingRecipeKey = recipe.Key
	secondPageContainer.Visible = false
	secondPageShowInfo.Visible = true
	secondShowInfoImg.Image = AssetRegistry.GetRecipeImage(recipe.Key, true)
	secondShowInfoName.Text = recipe.DisplayName
	secondShowInfoRarity.Text = recipe.Rarity or "Common"
	CustomerConfig.ApplyRarityGradient(secondShowInfoRarity, recipe.Rarity or "Common")
	reflectEquipButtons(recipe.Key)
	populateSecondLearnMore(recipe)
	secondLearnMoreCard.Visible = false
end

local function hideSecondPageInfo()
	pendingRecipeKey = nil
	secondPageShowInfo.Visible = false
	secondLearnMoreCard.Visible = false
	secondPageContainer.Visible = true
end

TweenUtil.AddHoverEffect(secondShowInfoReturn, 1.06, clickSound)
secondShowInfoReturn.Activated:Connect(function()
	if clickSound then clickSound:Play() end
	hideSecondPageInfo()
end)

TweenUtil.AddHoverEffect(secondShowInfoEquip, 1.06, clickSound)
secondShowInfoEquip.Activated:Connect(function()
	if not pendingRecipeKey then return end
	if clickSound then clickSound:Play() end
	local count = 0
	for _ in equippedRecipes do count += 1 end
	if count >= MAX_EQUIPPED_RECIPES then
		MessengerController.Warn("You can only equip up to " .. MAX_EQUIPPED_RECIPES .. " recipes.")
		return
	end
	equippedRecipes[pendingRecipeKey] = true
	reflectEquipButtons(pendingRecipeKey)
end)

TweenUtil.AddHoverEffect(secondShowInfoUnequip, 1.06, clickSound)
secondShowInfoUnequip.Activated:Connect(function()
	if not pendingRecipeKey then return end
	if clickSound then clickSound:Play() end
	equippedRecipes[pendingRecipeKey] = nil
	reflectEquipButtons(pendingRecipeKey)
end)

local function buildSecondPage()
	forEachRarityTemplate(secondPageContainer, function(template)
		template.Visible = false
	end)
	for _, recipe in RecipeConfig.GetAll() do
		local template = secondPageContainer:FindFirstChild((recipe.Rarity or "Common") .. "Template")
		if template then
			template.Visible = true
			local img = template:FindFirstChild("ItemImage")
			if img then img.Image = AssetRegistry.GetRecipeImage(recipe.Key, true) end
			local lbl = template:FindFirstChild("ItemName")
			if lbl then lbl.Text = recipe.DisplayName end
		end
	end
end

forEachRarityTemplate(secondPageContainer, function(template, rarity)
	TweenUtil.AddHoverEffect(template, 1.05, clickSound)
	template.Activated:Connect(function()
		if clickSound then clickSound:Play() end
		for _, recipe in RecipeConfig.GetAll() do
			if (recipe.Rarity or "Common") == rarity then
				showSecondPageInfo(recipe)
				break
			end
		end
	end)
end)

local recipeIndexOpen = false

local function openRecipeIndex()
	if recipeIndexOpen then return end
	PanelManager.CloseAllExcept("RecipeIndex")
	recipeIndexOpen = true
	UIEffectController.Open()
	buildFirstPage()
	buildSecondPage()
	recipeIndexUI.Size = UDim2.new(0.1, 0, 0.1, 0)
	recipeIndexUI.ImageTransparency = 1
	recipeIndexUI.Visible = true
	TweenUtil.PlayCustomEase(0.45, BEZIER, function(alpha)
		recipeIndexUI.Size = UDim2.new(0.7 * alpha, 0, 0.8 * alpha, 0)
		recipeIndexUI.ImageTransparency = 1 - alpha
	end)
end

local function closeRecipeIndex()
	if not recipeIndexOpen then return end
	TweenUtil.Tween(recipeIndexUI, 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In, {
		Size = UDim2.new(0.1, 0, 0.1, 0),
		ImageTransparency = 1,
	})
	task.wait(0.2)
	recipeIndexUI.Visible = false
	recipeIndexOpen = false
	UIEffectController.Close()
end

recipeShowBookBtn.Activated:Connect(function()
	if clickSound then clickSound:Play() end
	if recipeIndexOpen then closeRecipeIndex() else openRecipeIndex() end
end)

recipeExit.Activated:Connect(function()
	if clickSound then clickSound:Play() end
	hideFirstPageInfo()
	hideSecondPageInfo()
	closeRecipeIndex()
end)

local function fullCloseRecipeIndex()
	hideFirstPageInfo()
	hideSecondPageInfo()
	closeRecipeIndex()
end
PanelManager.Register("RecipeIndex", fullCloseRecipeIndex)
end -- do block for ThreeTopButtons + Recipe Index (register-limit workaround)

-- ---- Helpers ----

local function getHRP()
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function distanceTo(part)
	local hrp = getHRP()
	if not hrp then return math.huge end
	return (hrp.Position - part.Position).Magnitude
end

-- Region check: is the player standing within this part's footprint
-- (horizontal box test + generous vertical tolerance), plus a margin.
local function isInZone(part, margin)
	local hrp = getHRP()
	if not hrp then return false end
	margin = margin or 3

	local relative = part.CFrame:PointToObjectSpace(hrp.Position)
	local halfSize = part.Size / 2

	return math.abs(relative.X) <= halfSize.X + margin
		and math.abs(relative.Y) <= halfSize.Y + 6
		and math.abs(relative.Z) <= halfSize.Z + margin
end

-- ---- Popup ----

local popupActive = false

local function showPopup(question)
	if popupActive then return end
	popupActive = true
	UIEffectController.Open()
	askLabel.Text = question
	-- Zoom effect restored, but built the same safe way as every other
	-- panel in this file (Customer/Settings/Storage/etc.) and the way
	-- UIEffectController's camera fix works: every tween here targets a
	-- FIXED absolute value (0.05 -> 0.2 -> 0.05), never something read
	-- off the popup's own "current" size. That's what actually caused
	-- the camera drift bug - re-reading a possibly-mid-tween live value
	-- as the next baseline. Size is also reset to the fixed 0.05 start
	-- point at the top of every call, and popupActive above blocks any
	-- re-entrant call while one is still mid-flight, so there's no way
	-- for two competing animations to fight over popupFrame.Size the way
	-- the camera's FieldOfView could get fought over across panels.
	popupFrame.Size = UDim2.new(0.05, 0, 0.05, 0)
	popupFrame.BackgroundTransparency = 1
	popupFrame.Visible = true

	TweenUtil.PlayCustomEase(0.35, BEZIER, function(alpha)
		popupFrame.Size = UDim2.new(0.2 * alpha, 0, 0.2 * alpha, 0)
		popupFrame.BackgroundTransparency = 1 - (alpha * 0.6)
	end)

	local choice = nil
	local yesCon = yesBtn.Activated:Once(function() choice = true end)
	local noCon  = noBtn.Activated:Once(function() choice = false end)
	repeat task.wait() until choice ~= nil
	yesCon:Disconnect()
	noCon:Disconnect()

	if clickSound then clickSound:Play() end
	TweenUtil.Tween(popupFrame, 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In, {
		BackgroundTransparency = 1,
		Size = UDim2.new(0.05, 0, 0.05, 0),
	})
	task.wait(0.2)
	popupFrame.Visible = false
	popupActive = false
	UIEffectController.Close()
	return choice
end

-- ---- Storage UI ----

local function showItemInfo(itemDef)
	pendingStorageItem = itemDef
	showInfoImg.Image = AssetRegistry.GetIngredientImage(itemDef.Name)
	showInfoName.Text = itemDef.Display
	scrollFrame.Visible = false
	showInfo.Visible = true
end

local function hideItemInfo()
	pendingStorageItem = nil
	showInfo.Visible = false
	scrollFrame.Visible = true
end

showInfoUse.Activated:Connect(function()
	if not pendingStorageItem then return end
	if clickSound then clickSound:Play() end
	local success, result = Remotes.EquipIngredient:InvokeServer(pendingStorageItem.Name)
	if success then
		InventoryController.AddItem(pendingStorageItem.Name)
		InventoryController.SetHeld(pendingStorageItem.Name)
	else
		MessengerController.Warn("Could not equip: " .. tostring(result))
	end
	hideItemInfo()
end)

if returnBtn then
	TweenUtil.AddHoverEffect(returnBtn, 1.06, clickSound)
	returnBtn.Activated:Connect(function()
		if clickSound then clickSound:Play() end
		hideItemInfo()
	end)
end

local function buildStorageItems()
	for _, child in scrollFrame:GetChildren() do
		if child:IsA("ImageButton") and child ~= itemTemplate then
			child:Destroy()
		end
	end

	for i, itemDef in CookingConfig.ContainerItems do
		local btn = itemTemplate:Clone()
		btn.LayoutOrder = i
		btn.Visible = true
		btn.Name = itemDef.Name

		local img = btn:FindFirstChild("ItemImage")
		if img then img.Image = AssetRegistry.GetIngredientImage(itemDef.Name) end

		local lbl = btn:FindFirstChild("ItemName")
		if lbl then lbl.Text = itemDef.Display end

		local stk = btn:FindFirstChild("Stacks")
		if stk then stk.Text = itemDef.Stock == math.huge and "∞" or tostring(itemDef.Stock) end

		TweenUtil.AddHoverEffect(btn, 1.05, clickSound)

		btn.Activated:Connect(function()
			if clickSound then clickSound:Play() end
			showItemInfo(itemDef)
		end)

		btn.Parent = scrollFrame
	end
end

local storageOpen = false

local function openStorageUI()
	if storageOpen then return end
	PanelManager.CloseAllExcept("Storage")
	storageOpen = true
	UIEffectController.Open()
	buildStorageItems()
	storageUI.Size = UDim2.new(0.2, 0, 0.4, 0)
	storageUI.ImageTransparency = 1
	storageUI.Visible = true

	TweenUtil.PlayCustomEase(0.45, BEZIER, function(alpha)
		storageUI.Size = UDim2.new(0.4 * alpha, 0, 0.85 * alpha, 0)
		storageUI.ImageTransparency = 1 - alpha
	end)
end

local function closeStorageUI()
	if not storageOpen then return end
	TweenUtil.Tween(storageUI, 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In, {
		Size = UDim2.new(0.1, 0, 0.1, 0),
		ImageTransparency = 1,
	})
	task.wait(0.2)
	storageUI.Visible = false
	storageOpen = false
	UIEffectController.Close()
end

local function fullCloseStorageUI()
	hideItemInfo()
	closeStorageUI()
end
PanelManager.Register("Storage", fullCloseStorageUI)

exitStorage.Activated:Connect(function()
	hideItemInfo()
	closeStorageUI()
end)

-- ---- Fridge Storage UI (same structure/function as the regular
-- storage UI, different naming convention and item list) ----

local function showFridgeItemInfo(itemDef)
	pendingFridgeItem = itemDef
	fridgeShowInfoImg.Image = AssetRegistry.GetIngredientImage(itemDef.Name)
	fridgeShowInfoName.Text = itemDef.Display
	fridgeScrollFrame.Visible = false
	fridgeShowInfo.Visible = true
end

local function hideFridgeItemInfo()
	pendingFridgeItem = nil
	fridgeShowInfo.Visible = false
	fridgeScrollFrame.Visible = true
end

fridgeShowInfoUse.Activated:Connect(function()
	if not pendingFridgeItem then return end
	if clickSound then clickSound:Play() end
	local success, result = Remotes.EquipIngredient:InvokeServer(pendingFridgeItem.Name)
	if success then
		InventoryController.AddItem(pendingFridgeItem.Name)
		InventoryController.SetHeld(pendingFridgeItem.Name)
	else
		MessengerController.Warn("Could not equip: " .. tostring(result))
	end
	hideFridgeItemInfo()
end)

if fridgeReturnBtn then
	TweenUtil.AddHoverEffect(fridgeReturnBtn, 1.06, clickSound)
	fridgeReturnBtn.Activated:Connect(function()
		if clickSound then clickSound:Play() end
		hideFridgeItemInfo()
	end)
end

local function buildFridgeItems()
	for _, child in fridgeScrollFrame:GetChildren() do
		if child:IsA("ImageButton") and child ~= fridgeItemTemplate then
			child:Destroy()
		end
	end

	for i, itemDef in CookingConfig.FridgeItems do
		local btn = fridgeItemTemplate:Clone()
		btn.LayoutOrder = i
		btn.Visible = true
		btn.Name = itemDef.Name

		local img = btn:FindFirstChild("ItemImage")
		if img then img.Image = AssetRegistry.GetIngredientImage(itemDef.Name) end

		local lbl = btn:FindFirstChild("ItemName")
		if lbl then lbl.Text = itemDef.Display end

		local stk = btn:FindFirstChild("Stacks")
		if stk then stk.Text = itemDef.Stock == math.huge and "∞" or tostring(itemDef.Stock) end

		TweenUtil.AddHoverEffect(btn, 1.05, clickSound)

		btn.Activated:Connect(function()
			if clickSound then clickSound:Play() end
			showFridgeItemInfo(itemDef)
		end)

		btn.Parent = fridgeScrollFrame
	end
end

local fridgeStorageOpen = false

local function openFridgeStorageUI()
	if fridgeStorageOpen then return end
	PanelManager.CloseAllExcept("FridgeStorage")
	fridgeStorageOpen = true
	UIEffectController.Open()
	buildFridgeItems()
	fridgeStorageUI.Size = UDim2.new(0.2, 0, 0.4, 0)
	fridgeStorageUI.ImageTransparency = 1
	fridgeStorageUI.Visible = true

	TweenUtil.PlayCustomEase(0.45, BEZIER, function(alpha)
		fridgeStorageUI.Size = UDim2.new(0.4 * alpha, 0, 0.85 * alpha, 0)
		fridgeStorageUI.ImageTransparency = 1 - alpha
	end)
end

local function closeFridgeStorageUI()
	if not fridgeStorageOpen then return end
	TweenUtil.Tween(fridgeStorageUI, 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In, {
		Size = UDim2.new(0.1, 0, 0.1, 0),
		ImageTransparency = 1,
	})
	task.wait(0.2)
	fridgeStorageUI.Visible = false
	fridgeStorageOpen = false
	UIEffectController.Close()
end

local function fullCloseFridgeStorageUI()
	hideFridgeItemInfo()
	closeFridgeStorageUI()
end
PanelManager.Register("FridgeStorage", fullCloseFridgeStorageUI)

exitFridgeStorage.Activated:Connect(function()
	hideFridgeItemInfo()
	closeFridgeStorageUI()
end)

-- Remove unused sizzle delay from client - server handles sounds now

-- ---- Cooking countdown UI ----

local cookCountActive = false

local function getCookingCounterLabel(restaurant)
	local cookingArea = restaurant.AreaContainer:FindFirstChild("CookingArea")
	local surfaceContainer = cookingArea and cookingArea:FindFirstChild("SurfaceGuiContainer")
	local surfaceGui = surfaceContainer and surfaceContainer:FindFirstChild("SurfaceGuiCooking")
	return surfaceGui and surfaceGui:FindFirstChild("CounterText")
end

local function formatTime(seconds)
	local m = math.floor(seconds / 60)
	local s = seconds % 60
	return string.format("%d:%02d", m, s)
end

local function playSizzleAfterDelay(delaySeconds)
	task.spawn(function()
		task.wait(delaySeconds)
		if not cookCountActive then return end
		SoundController.Play("Boiling")
		SoundController.Play("Sizzling")
	end)
end

local function showCookCountdown(duration, restaurant)
	if cookCountActive then return end
	cookCountActive = true

	local counterLabel = getCookingCounterLabel(restaurant)

	task.spawn(function()
		for t = duration, 0, -1 do
			if counterLabel then
				counterLabel.Text = formatTime(t)
			end
			task.wait(1)
		end
		if counterLabel then
			counterLabel.Text = "Done!"
		end
		cookCountActive = false
	end)
end

-- ---- DiningArea funfact display (same rotation as the loading screen) ----

local funfactLoopStarted = false

local function startFunfactLoop(restaurant)
	if funfactLoopStarted then return end
	local diningArea = restaurant.AreaContainer:FindFirstChild("DiningArea")
	local display = diningArea and diningArea:FindFirstChild("FunfactDisplay")
	local surfaceGui = display and display:FindFirstChild("Funfact")
	local label = surfaceGui and surfaceGui:FindFirstChild("Fact")
	if not label then return end

	funfactLoopStarted = true
	task.spawn(function()
		local index = 1
		while true do
			local fact = FunFacts.List[index]
			local startTime = os.clock()
			TweenUtil.TypeText(label, fact, LoadingConfig.FACT_TYPE_SPEED)
			local remaining = LoadingConfig.FACT_DISPLAY_TIME - (os.clock() - startTime)
			if remaining > 0 then
				task.wait(remaining)
			end
			index = (index % #FunFacts.List) + 1
		end
	end)
end

-- ---- Area detection ----

local detectorState = {
	Container = false,
	Chopping  = false,
	Cooking   = false,
	Wash      = false,
	Fridge    = false,
}
TutorialGuide.BindZones(detectorState)

local triggerHandled = {}

-- The whole prep/cooking mechanism requires an accepted customer in
-- progress first - nothing to cook for otherwise.
local function requireAcceptedCustomer()
	if hasAcceptedCustomer then return true end
	MessengerController.Warn("Accept a customer first!")
	return false
end

local function handleContainerZone(restaurant)
	if triggerHandled.Container then return end
	-- Tutorial sequencing: station off until it's this step's turn.
	if not TutorialGuide.IsStationActive("ItemContainerArea") then
		detectorState.Container = false -- re-check once it activates
		return
	end
	if not requireAcceptedCustomer() then return end
	triggerHandled.Container = true

	task.spawn(function()
		local yes = showPopup("Would you like to open the ingredient container?")
		if yes then
			openStorageUI()
		end
		task.wait(0.5)
		triggerHandled.Container = false
	end)
end

-- Fridge: entering the zone asks to open it (Yes/No popup, same pattern
-- as the ingredient container); leaving the zone closes it automatically,
-- no popup needed - matches walking away from an open fridge door.
local fridgeOpen = false

local function handleFridgeZoneEnter(restaurant)
	if triggerHandled.Fridge then return end
	if fridgeOpen then return end
	if not TutorialGuide.IsStationActive("FridgeArea") then
		detectorState.Fridge = false -- re-check once it activates
		return
	end
	if not requireAcceptedCustomer() then return end
	triggerHandled.Fridge = true

	task.spawn(function()
		local yes = showPopup("Do you want to open the fridge?")
		if yes then
			local ok = Remotes.RequestFridge:InvokeServer(true)
			if ok then fridgeOpen = true end
		end
		task.wait(0.5)
		triggerHandled.Fridge = false
	end)
end

local function handleFridgeZoneExit()
	if not fridgeOpen then return end
	fridgeOpen = false
	Remotes.RequestFridge:InvokeServer(false)
	if fridgeStorageOpen then
		hideFridgeItemInfo()
		closeFridgeStorageUI()
	end
end

local function handleChoppingZone(restaurant)
	if triggerHandled.Chopping then return end
	if not TutorialGuide.IsStationActive("ChoppingArea") then
		detectorState.Chopping = false -- re-check once it activates
		return
	end

	local item = InventoryController.GetSelectedItem()
	if not item then
		return
	end

	-- Already chopped? Guide them to the pot instead of re-chopping.
	if item.Name:match("^Chopped") then
		return
	end

	-- A spice / liquid that isn't chopped at all.
	if not CookingConfig.ChoppableMap[item.Name] then
		return
	end

	if not requireAcceptedCustomer() then return end

	triggerHandled.Chopping = true
	task.spawn(function()
		local yes = showPopup("Chop " .. item.Name .. "?")
		if yes then
			local ok, result = Remotes.ChopIngredient:InvokeServer(item.Name)
			if ok then
				InventoryController.RemoveItem(item.Name)
				InventoryController.AddItem(result)
				InventoryController.SetHeld(result)
			else
				MessengerController.Warn("Chop failed: " .. tostring(result))
			end
		end
		task.wait(1)
		triggerHandled.Chopping = false
	end)
end

-- Re-opens the chop popup on a fresh equip while already standing in
-- the zone, instead of requiring the player to step out and back in.
local function recheckChoppingZone()
	if not detectorState.Chopping then return end
	local restaurant = getRestaurant()
	if not restaurant then return end
	triggerHandled.Chopping = false
	handleChoppingZone(restaurant)
end

InventoryController.OnHeldChanged(function()
	-- Guide state first, so the chopping re-check sees the current step
	-- (station locks depend on it).
	refreshGuideHighlights()
	recheckChoppingZone()
end)

local potPlaced = false
local recipeStepIndex = 0 -- how many ingredients successfully added
local addedIngredients = {} -- item name -> true, tracks WHICH steps are done (reset with each new pot)

-- ---- CookingArea ingredient checklist (CookingSurfaceUI -> CookUI) ----

local function getIngredientListUI(restaurant)
	local cookingArea = restaurant.AreaContainer:FindFirstChild("CookingArea")
	local surfacePart = cookingArea and cookingArea:FindFirstChild("CookingSurfaceUI")
	local cookUI = surfacePart and surfacePart:FindFirstChild("CookUI")
	local pageContainer = cookUI and cookUI:FindFirstChild("PageContainer")
	return pageContainer and pageContainer:FindFirstChild("IngredientList")
end

-- Shows only the ingredients still needed (in order), removing each one
-- from the list as it's successfully added to the pot. Also drives the
-- CookingArea.PopUp.CheckList billboard (see below), which instead keeps
-- EVERY recipe step visible and flips each one's Status [X] -> check mark.
local function refreshIngredientChecklist(restaurant)
	-- PopUp.CheckList billboard: one Template clone per recipe step, shown
	-- only while a pot is placed (List is authored Visible=false). Status
	-- keeps the Template's authored [X] (pulsing) until that step is in the
	-- pot, then shows AssetRegistry's "Done" check mark. Sort (UIGridLayout
	-- by LayoutOrder, same step order as CookUI's IngredientList): pending
	-- steps fill slots 0,1,2... in recipe order; added steps fill from the
	-- LAST slot backward in the order they were added (1st added = N-1,
	-- 2nd = N-2, ...). With Adobo: Chicken starts at 0, jumps to 5 once
	-- added, Garlic then takes 4, and so on. The border (UIStroke) gets a
	-- rotating gradient shimmer + color tween (warm = pending, green/gold
	-- = done).
	-- Client-only, like the guide highlights. Kept inside this function
	-- (not a new top-level local) because this chunk is near Luau's
	-- ~200-local limit.
	do
		local popUp = restaurant.AreaContainer:FindFirstChild("CookingArea")
			and restaurant.AreaContainer.CookingArea:FindFirstChild("PopUp")
		local checkList = popUp and popUp:FindFirstChild("CheckList")
		local billboardList = checkList and checkList:FindFirstChild("List")
		local billboardTemplate = billboardList and billboardList:FindFirstChild("Template")
		if billboardTemplate then
			billboardTemplate.Visible = false
			for _, c in billboardList:GetChildren() do
				if c:IsA("ImageLabel") and c ~= billboardTemplate then c:Destroy() end
			end
			billboardList.Visible = potPlaced
			checkList.Enabled = true
			if potPlaced then
				local recipe = RecipeConfig.GetActive()
				local total = #recipe.Sequence
				local TS = game:GetService("TweenService")
				local pendingSlot = 0
				for i, step in recipe.Sequence do
					local clone = billboardTemplate:Clone()
					clone.Name = tostring(i)
					clone.Image = AssetRegistry.GetIngredientImage(step.Name)
					local status = clone:FindFirstChild("Status")
					local stroke = clone:FindFirstChildOfClass("UIStroke")
					-- Steps are added in strict recipe order, so step i is the
					-- i-th one added.
					local done = i <= recipeStepIndex
					if done then
						clone.LayoutOrder = total - i
						if status then status.Image = AssetRegistry.GetStatusImage("Done") end
					else
						clone.LayoutOrder = pendingSlot
						pendingSlot += 1
						-- Pulse the [X]: re-anchor at its center first so it
						-- scales in place instead of growing from the corner.
						if status then
							local size, pos = status.Size, status.Position
							status.AnchorPoint = Vector2.new(0.5, 0.5)
							status.Position = UDim2.new(pos.X.Scale + size.X.Scale / 2, pos.X.Offset + size.X.Offset / 2, pos.Y.Scale + size.Y.Scale / 2, pos.Y.Offset + size.Y.Offset / 2)
							TS:Create(status, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
								Size = UDim2.new(size.X.Scale * 1.25, size.X.Offset, size.Y.Scale * 1.25, size.Y.Offset),
							}):Play()
						end
					end
					if stroke then
						local fromColor = done and Color3.fromRGB(70, 220, 110) or Color3.fromRGB(255, 80, 80)
						local toColor = done and Color3.fromRGB(255, 210, 70) or Color3.fromRGB(255, 170, 60)
						stroke.Color = fromColor
						stroke.Thickness = 3
						local shine = Instance.new("UIGradient")
						shine.Color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
							ColorSequenceKeypoint.new(0.5, Color3.fromRGB(120, 120, 120)),
							ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
						})
						shine.Parent = stroke
						TS:Create(shine, TweenInfo.new(done and 3 or 1.8, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
							Rotation = 360,
						}):Play()
						TS:Create(stroke, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
							Color = toColor,
						}):Play()
					end
					clone.Visible = true
					clone.Parent = billboardList
				end
			end
		end
	end

	local list = getIngredientListUI(restaurant)
	if not list then return end
	local template = list:FindFirstChild("TemplateName")
	if not template then return end
	template.Visible = false

	for _, c in list:GetChildren() do
		if c:IsA("TextLabel") and c ~= template then c:Destroy() end
	end

	if not potPlaced then return end

	local recipe = RecipeConfig.GetActive()
	for i = recipeStepIndex + 1, #recipe.Sequence do
		local step = recipe.Sequence[i]
		local clone = template:Clone()
		clone.Name = "Ingredient_" .. step.Name
		clone.LayoutOrder = i
		clone.Text = step.Name
		local img = clone:FindFirstChild("ItemImage")
		if img then img.Image = AssetRegistry.GetIngredientImage(step.Name) end
		clone.Visible = true
		clone.Parent = list
	end
end

local function handleCookingZone(restaurant)
	if triggerHandled.Cooking then return end
	if potPlaced then return end -- adding ingredients now happens via the ProximityPrompt
	if not requireAcceptedCustomer() then return end
	triggerHandled.Cooking = true

	task.spawn(function()
		local yes = showPopup("Place a pot on the cooking area?")
		if yes then
			local ok, err = Remotes.PlacePot:InvokeServer()
			if ok then
				potPlaced = true
				recipeStepIndex = 0
				addedIngredients = {}
				refreshIngredientChecklist(restaurant)
			else
				MessengerController.Warn("Could not place pot: " .. tostring(err))
			end
		end

		task.wait(1)
		triggerHandled.Cooking = false
	end)
end

-- ---- Wash Area: WashDetector popup + water fill feedback ----

-- true once RequestWash's fill duration has actually elapsed (mirrors
-- the server's state.sinkReady, updated from the client's own successful
-- RequestWash call rather than a separate poll).
local sinkFilled = false
-- true once a dirty plate has been handed off into RightSink and until
-- it's actually washed - mirrors the server's "is anything pending" check.
local plateInSink = false

-- Forward-declared: full bodies defined further down with the rest of
-- the sink prompt logic, but referenced here (handleWashZone) and in
-- cacheCookingPrompts, both of which come first in the file.
local refreshSinkPromptText
local setupSinkPromptHoldTrick
local doWashConfirm

local function handleWashZone(restaurant)
	if triggerHandled.Wash then return end

	-- Water not on yet: only offer to turn it on when there's actually a
	-- dirty plate to wash - the player is carrying one, or one is waiting
	-- on a dining table. Otherwise the sink stays inactive.
	if not sinkFilled then
		local hasPlate = TutorialGuide.usedPlateIndex ~= nil
		if not hasPlate then
			for _, e in InventoryController.GetAllItems() do
				if e.Name == "EmptyPlate" then hasPlate = true break end
			end
		end
		if not hasPlate then
			for _, e in InventoryController.GetOverflowItems() do
				if e.Name == "EmptyPlate" then hasPlate = true break end
			end
		end
		if not hasPlate then return end
		triggerHandled.Wash = true
		task.spawn(function()
			local yes = showPopup("Do you want to wash plates?")
			if yes then
				local ok, result = Remotes.RequestWash:InvokeServer()
				if ok then
					-- Wait out the fill INSIDE this handler, so triggerHandled.Wash
					-- stays set the whole time. (It used to re-arm after 1s while
					-- the water was still filling, asking "wash plates?" twice.)
					task.wait(result)
					sinkFilled = true
					refreshSinkPromptText()
				elseif result == "AlreadyWashing" then
					MessengerController.Warn("Already washing.")
				else
					MessengerController.Warn("Could not start washing: " .. tostring(result))
				end
			end
			task.wait(1)
			triggerHandled.Wash = false
		end)
		return
	end

	-- Water's already on. Plate TRANSFER (stage 2) still happens via
	-- WashArea.Proximity's single ProximityPrompt (see onSinkPromptTriggered
	-- below) - nothing to do here for that part.
	--
	-- Stage 3 (the "wash the plate?" popup) is re-checked from HERE too,
	-- not only chained automatically off a successful doTransfer(): this
	-- is the requested "recheck/checker pass" - every time the player is
	-- standing inside the Wash Detector zone (this function is now called
	-- every frame they're in it, not just on entry - see the Heartbeat
	-- loop), if a plate is already sitting in the sink (plateInSink) the
	-- popup gets (re-)surfaced. doWashConfirm() is itself idempotent
	-- (guarded by washPopupShowing/plateInSink), so calling it repeatedly
	-- here every frame is harmless - it just keeps making sure stage 3
	-- never gets silently missed.
	if plateInSink then
		doWashConfirm()
	end
end

-- ---- Cooking prompt: add ingredient to pot / start cooking ----

local cookingAddPrompt = nil
local washPrompt = nil
local fridgeAddPrompt = nil
local servingPrompts = {} -- ProximityPrompt -> servingPointName
local deliveryPrompts = {} -- ProximityPrompt -> servedSpawnerIndex (number)
local promptsCached = false

local function cacheCookingPrompts(restaurant)
	if promptsCached then return end
	local areaContainer = restaurant:FindFirstChild("AreaContainer")
	if not areaContainer then return end

	local cookingArea = areaContainer:FindFirstChild("CookingArea")
	local proxContainer = cookingArea and cookingArea:FindFirstChild("ProximityContainer")
	cookingAddPrompt = proxContainer and proxContainer:FindFirstChildOfClass("ProximityPrompt")

	local washArea = areaContainer:FindFirstChild("WashArea")
	local washProxPart = washArea and washArea:FindFirstChild("Proximity")
	washPrompt = washProxPart and washProxPart:FindFirstChildOfClass("ProximityPrompt")
	if washPrompt then
		setupSinkPromptHoldTrick(washPrompt)
		refreshSinkPromptText()
	end

	local fridgeArea = areaContainer:FindFirstChild("FridgeArea")
	local fridgeProxContainer = fridgeArea and fridgeArea:FindFirstChild("ProximityContainer")
	fridgeAddPrompt = fridgeProxContainer and fridgeProxContainer:FindFirstChildOfClass("ProximityPrompt")

	local kitchenIsle = areaContainer:FindFirstChild("KitchenIsle")
	local spawner = kitchenIsle and kitchenIsle:FindFirstChild("TobeServedSpawner")
	if spawner then
		for _, att in spawner:GetChildren() do
			if att:IsA("Attachment") then
				local prompt = att:FindFirstChildOfClass("ProximityPrompt")
				if prompt then
					servingPrompts[prompt] = att.Name
				end
			end
		end
	end

	local servingToCustomer = restaurant:FindFirstChild("ServingToCustomer")
	local servedSpawner = servingToCustomer and servingToCustomer:FindFirstChild("ServedSpawner")
	if servedSpawner then
		for _, att in servedSpawner:GetChildren() do
			if att:IsA("Attachment") then
				local prompt = att:FindFirstChildOfClass("ProximityPrompt")
				local idx = tonumber(att.Name)
				if prompt and idx then
					deliveryPrompts[prompt] = idx
				end
			end
		end
	end

	if cookingAddPrompt then
		promptsCached = true
	end
end

local addingIngredient = false

local function onCookingPromptTriggered(restaurant)
	if addingIngredient then return end
	if not potPlaced then
		MessengerController.Warn("Place a pot first.")
		return
	end

	local recipe = RecipeConfig.GetActive()

	if recipeStepIndex >= #recipe.Sequence then
		-- All ingredients in: ask before turning on the fire
		addingIngredient = true
		local yes = showPopup("Do you want to start the fire?")
		if yes then
			local startOk, cookTime = Remotes.StartCooking:InvokeServer()
			if startOk then
				showCookCountdown(cookTime, restaurant)
				refreshGuideHighlights()
			elseif cookTime == "NoPlates" then
				MessengerController.Warn("No clean plates left! Go wash some at the Wash Area.")
			else
				MessengerController.Warn("Could not start cooking: " .. tostring(cookTime))
			end
		end
		addingIngredient = false
		return
	end

	local item = InventoryController.GetSelectedItem()
	if not item then
		MessengerController.Warn("Equip an ingredient to add to the pot.")
		return
	end

	addingIngredient = true
	local ok, result, remaining = Remotes.AddToPot:InvokeServer(item.Name)
	if ok then
		InventoryController.RemoveItem(item.Name)
		InventoryController.ClearHeld()
		recipeStepIndex += 1
		addedIngredients[item.Name] = true
		refreshIngredientChecklist(restaurant)
		refreshGuideHighlights()
	else
		if result == "NeedsChopping" then
			MessengerController.Warn(item.Name .. " must be chopped first!")
		elseif result == "NotHeld" then
			MessengerController.Warn("You must be holding the ingredient.")
		elseif result == "WrongOrder" then
			-- 'remaining' doubles as the expected item's Display-less Name here
			-- (server's 3rd return value on this specific failure).
			local recipe = RecipeConfig.GetActive()
			local expectedName = remaining
			local expectedDisplay = expectedName
			for _, step in recipe.Sequence do
				if step.Name == expectedName then
					expectedDisplay = step.Display or expectedName
					break
				end
			end
			MessengerController.Warn("Add " .. expectedDisplay .. " next!")
		elseif result == "NotInRecipe" or result == "AlreadyAdded" then
			-- Obvious from context, no toast needed
		else
			MessengerController.Warn("Error: " .. tostring(result))
		end
	end
	addingIngredient = false
end

local function onServingPromptTriggered(pointName)
	local ok, result = Remotes.PickupPlatedDish:InvokeServer(pointName)
	if ok then
		InventoryController.AddItem(result)
		InventoryController.SetHeld(result)
		dishReadyAtKitchenIsle = false
		refreshGuideHighlights()
	else
		MessengerController.Warn("Nothing to pick up.")
	end
end

local function onDeliveryPromptTriggered(servedSpawnerIndex)
	local item = InventoryController.GetSelectedItem()
	local recipe = RecipeConfig.GetActive()
	local holdingDish = item and item.Name == recipe.PlatingName

	if holdingDish then
		local ok, reason = Remotes.DeliverDish:InvokeServer(servedSpawnerIndex)
		if ok then
			InventoryController.ClearHeld()
			InventoryController.RemoveItem(item.Name)
			MessengerController.Warn("Served to Customer!")
		elseif reason == "WrongSpot" then
			MessengerController.Warn("No customer waiting at this table.")
		else
			MessengerController.Warn("Could not deliver: " .. tostring(reason))
		end
		return
	end

	-- Not holding the dish - try picking up a leftover used plate instead
	local ok, result = Remotes.PickupUsedPlate:InvokeServer(servedSpawnerIndex)
	if ok then
		InventoryController.AddItem(result)
		InventoryController.SetHeld(result)
	elseif result == "StillEating" then
		MessengerController.Warn("They're still eating - come back once they're done.")
	elseif result == "AlreadyHoldingPlate" then
		MessengerController.Warn("Wash your current plate first!")
	else
		MessengerController.Warn("Nothing to pick up here.")
	end
end

-- ---- WashArea.Proximity single prompt: TRANSFER or WASH-confirm ----
-- Per design change: no more separate prompt on the sink attachment -
-- only WashArea.Proximity's ProximityPrompt exists, and what a hold on
-- it does depends on current state:
--   * sinkFilled, not plateInSink, holding EmptyPlate -> TRANSFER
--   * otherwise (plateInSink, nothing to transfer)     -> WASH (popup-gated)
-- Using one prompt instead of two closely-spaced same-key prompts
-- removes any chance of ProximityPromptService's exclusivity handoff
-- silently switching which prompt is "active" mid-hold - which is the
-- most likely source of WashPlate (the only thing that ever anchors to
-- PlayerStand) firing right after what should have been a plain
-- transfer.

local function isTransferEligible()
	if not sinkFilled or plateInSink then return false end
	local item = InventoryController.GetSelectedItem()
	return item ~= nil and item.Name == "EmptyPlate"
end

-- Captured once per hold, at PromptButtonHoldBegan, BEFORE the mid-hold
-- unequip trick below ever runs. isTransferEligible() depends on
-- GetSelectedItem() still showing EmptyPlate as held - but the trick
-- clears that at the halfway point, so re-checking isTransferEligible()
-- again at Triggered (full hold) would already see nothing held and
-- wrongly decide "wash" for what was actually a transfer hold, which is
-- why the wash confirm popup never showed: it silently bailed with
-- "transfer a dirty plate first" instead, since plateInSink was still
-- false. Locking in the decision at hold-begin fixes that.
local sinkPromptTransferEligible = false

-- The sink prompt is ONLY for the transfer step: visible while the water
-- is on and the player is holding a dirty plate, hidden otherwise (the
-- final wash is the "wash the plate?" popup, not this prompt).
-- Never flipped mid-hold (the "Holding" attribute, set by the hold trick
-- below), since the halfway unequip would otherwise hide the prompt and
-- cancel the very hold that's doing the transfer.
function refreshSinkPromptText()
	if not washPrompt then return end
	washPrompt.ActionText = "Transfer Plate"
	if not washPrompt:GetAttribute("Holding") then
		washPrompt.Enabled = isTransferEligible()
	end
end

-- (doWashConfirm was already forward-declared above, alongside
-- refreshSinkPromptText/setupSinkPromptHoldTrick - handleWashZone above
-- and doTransfer below both need to see it before its real body is
-- defined further down.)

local transferring = false
local function doTransfer()
	if transferring then return end
	transferring = true

	local ok, reason = Remotes.RequestPlateTransfer:InvokeServer()
	if ok then
		InventoryController.ClearHeld()
		InventoryController.RemoveItem("EmptyPlate")
		plateInSink = true
		refreshSinkPromptText()
		refreshGuideHighlights() -- guide stays on the sink until it's washed
	elseif reason == "SinkFull" then
		MessengerController.Warn("The sink is full right now.")
	elseif reason == "AlreadyWashing" then
		MessengerController.Warn("Still washing the last plate - wait a moment.")
	elseif reason == "SinkNotReady" then
		MessengerController.Warn("Turn the water on first!")
	elseif reason == "TooFar" then
		-- Server-side filler re-check (same convention as Doors) rejected
		-- this because the player drifted out of range mid-hold - obvious
		-- from the prompt just closing, no toast needed.
	elseif reason ~= "AlreadyPending" and reason ~= "WrongItem" then
		MessengerController.Warn("Could not transfer the plate: " .. tostring(reason))
	end

	transferring = false

	-- Stage 3 (wash confirm popup) follows automatically once stage 2
	-- (transfer) actually lands - per design this should never need a
	-- second separate hold on the prompt. A one-frame wait lets the
	-- server's Tool:Destroy() (already fired before this invoke even
	-- returned - either by the earlier mid-hold trick, or by
	-- RequestPlateTransfer's own fallback destroy) finish replicating,
	-- so doWashConfirm()'s "still holding something" guard below doesn't
	-- see a stale, about-to-vanish Tool instance and wrongly bail.
	if ok then
		task.wait()
		doWashConfirm()
	end
end

-- Washing is popup-gated: we only surface "start washing?" once we've
-- validated (a) the plate is really sitting in RightSink and (b) nothing
-- is left equipped in the Right Arm - only then can the wash
-- animation/VFX (the only thing allowed to anchor to PlayerStand) begin.
local washPopupShowing = false
function doWashConfirm()
	if washPopupShowing then return end

	if not plateInSink then
		MessengerController.Warn("Transfer a dirty plate to the sink first!")
		return
	end

	local char = player.Character
	local heldTool = char and char:FindFirstChildOfClass("Tool")
	if heldTool then
		MessengerController.Warn("Put away what you're holding first!")
		return
	end

	washPopupShowing = true
	task.spawn(function()
		local yes = showPopup("Do you want to wash the plate?")
		if yes then
			local ok, result = Remotes.WashPlate:InvokeServer()
			if ok then
				plateInSink = false
				MessengerController.Warn("Plate washed!")
				refreshSinkPromptText()
				-- Washing the first plate closes the full loop.
				TutorialGuide.Complete()
			elseif result == "NothingToWash" then
				-- Nothing pending in the sink yet - obvious, no toast
			elseif result == "SinkNotReady" then
				MessengerController.Warn("Turn the water on first!")
			elseif result == "AlreadyWashing" then
				MessengerController.Warn("Already washing that plate.")
			elseif result == "TooFar" then
				MessengerController.Warn("Get back to the sink first!")
			else
				MessengerController.Warn("Could not wash: " .. tostring(result))
			end
		end
		washPopupShowing = false
	end)
end

local function onSinkPromptTriggered()
	if sinkPromptTransferEligible then
		doTransfer()
	else
		doWashConfirm()
	end
end

-- The "filler" trick: halfway through a TRANSFER hold, actually unequip
-- the plate through the exact same ToggleHold codepath normal
-- hotbar-unequip uses (proven to fully clear the Right Arm), instead of
-- leaving cleanup to RequestPlateTransfer's own tool-destroy at the very
-- end. By the time the hold completes there's no equipped Tool left to
-- ever show up as a remnant on the arm. Only armed for a
-- transfer-eligible hold - a wash-confirm hold shouldn't touch equip
-- state, since nothing should be held for that one anyway.
local unequipTimer = nil
local function cancelMidHoldUnequip()
	if unequipTimer then
		task.cancel(unequipTimer)
		unequipTimer = nil
	end
end

function setupSinkPromptHoldTrick(prompt)
	prompt.PromptButtonHoldBegan:Connect(function()
		prompt:SetAttribute("Holding", true)
		cancelMidHoldUnequip()
		-- Lock in the transfer/wash decision for this hold right now, before
		-- anything below can clear the held item (see comment above the
		-- sinkPromptTransferEligible declaration).
		sinkPromptTransferEligible = isTransferEligible()
		if not sinkPromptTransferEligible then return end
		local halfway = prompt.HoldDuration / 2
		if halfway <= 0 then return end
		unequipTimer = task.delay(halfway, function()
			unequipTimer = nil
			local result = Remotes.ToggleHold:InvokeServer("EmptyPlate")
			if result and result.Success and result.Holding == false then
				InventoryController.ClearHeld()
				-- Also drop the EmptyPlate entry from the Hotbar UI right away,
				-- not just the Right Arm - once it's unequipped it shouldn't
				-- still show as carried. doTransfer()'s own RemoveItem call
				-- later becomes a safe no-op (slot's already gone).
				InventoryController.RemoveItem("EmptyPlate")
			end
		end)
	end)

	-- Hold over (released early or finished): re-evaluate visibility on
	-- the next frame, after Triggered has had its chance to run.
	local function holdOver()
		cancelMidHoldUnequip()
		task.defer(function()
			prompt:SetAttribute("Holding", nil)
			refreshSinkPromptText()
		end)
	end
	prompt.PromptButtonHoldEnded:Connect(holdOver)
	prompt.TriggerEnded:Connect(holdOver)
end

-- Fridge is only interactable via this prompt while actually open
-- (server enables/disables it in FridgeFunction.Open/Close) - if this
-- ever fires the fridge is guaranteed open, so just show the UI.
local function onFridgeAddPromptTriggered()
	openFridgeStorageUI()
end

ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
	if triggeringPlayer ~= player then return end
	if prompt == cookingAddPrompt then
		onCookingPromptTriggered(getRestaurant())
	elseif prompt == washPrompt then
		onSinkPromptTriggered()
	elseif prompt == fridgeAddPrompt then
		onFridgeAddPromptTriggered()
	elseif servingPrompts[prompt] then
		onServingPromptTriggered(servingPrompts[prompt])
	elseif deliveryPrompts[prompt] then
		onDeliveryPromptTriggered(deliveryPrompts[prompt])
	end
end)

-- AreaStateChanged from server
Remotes.AreaStateChanged.OnClientEvent:Connect(function(event, data)
	if event == "CookingDone" then
		potPlaced = false
		recipeStepIndex = 0
		addedIngredients = {}
		dishReadyAtKitchenIsle = true
		refreshGuideHighlights()
		local restaurant = getRestaurant()
		if restaurant then refreshIngredientChecklist(restaurant) end
		MessengerController.Warn("Adobo Plating is ready! Pick it up from the counter.")
	elseif event == "DishBurnt" then
		potPlaced = false
		recipeStepIndex = 0
		addedIngredients = {}
		refreshGuideHighlights()
		local restaurant = getRestaurant()
		if restaurant then refreshIngredientChecklist(restaurant) end
		MessengerController.Warn("The dish got burnt! Try again.")
	end
end)

-- ---- Owner-only design highlights (client-only instances, so other
-- players near this restaurant never see them), driven by what the
-- player is currently holding / what state the restaurant is in - not
-- just "always on" ----

local HIGHLIGHT_AREAS = { "ChoppingArea", "CookingArea", "ItemContainerArea", "KitchenIsle", "WashArea", "DiningArea", "FridgeArea" }
local highlightsApplied = false
local guideHighlights = {} -- areaName -> { Highlight instances }
local tableHighlights = {} -- DiningArea table model Name -> Highlight

-- Which DiningArea table serves each ServingSeat index
local SEAT_TO_TABLE = {
	[1] = "OneAndTwoTable",
	[2] = "OneAndTwoTable",
	[3] = "ThreeAndFourTable",
	[4] = "ThreeAndFourTable",
}

local function setAreaHighlight(areaName, active)
	local list = guideHighlights[areaName]
	if not list then return end
	for _, h in list do
		h.Enabled = active
	end
end

-- Highlights only the DiningArea table(s) where a customer is currently
-- seated waiting for / eating their food, so the player knows which
-- table to walk their dish to. Driven by the eating-list refresh, not
-- the held-item refresh, since it depends on customer state. Gated by
-- diningAreaGuideActive so a table only actually lights when it's also
-- this player's turn in the guide sequence (holding the plated dish) -
-- otherwise a waiting customer would light their table the whole time,
-- breaking the one-area-at-a-time guide.
local diningAreaGuideActive = false

setActiveTables = function(occupiedSeatIndices)
	local wantTable = {}
	if diningAreaGuideActive then
		for seatIdx in occupiedSeatIndices do
			local tbl = SEAT_TO_TABLE[seatIdx]
			if tbl then wantTable[tbl] = true end
		end
	end
	for tableName, highlight in tableHighlights do
		highlight.Enabled = wantTable[tableName] == true
	end
end

-- Recomputes which SINGLE area should be glowing right now, following the
-- fixed guide sequence (one area at a time):
--   accept customer -> CookingArea (place pot) -> FridgeArea (fridge
--   items) -> ItemContainerArea (shelf items) -> ChoppingArea (chop ALL
--   choppables) -> CookingArea (add in order, start fire) -> [cooking]
--   -> KitchenIsle (pick up dish) -> DiningArea (serve) -> used plate on
--   the table (once the customer is done eating) -> WashArea.
-- Also pushes the same state to Modules.TutorialGuide, which decides
-- which on-screen button (if any) to spotlight for this step.
refreshGuideHighlights = function()
	if not highlightsApplied then return end

	local item = InventoryController.GetSelectedItem()
	local heldName = item and item.Name
	local recipe = RecipeConfig.GetActive()
	local restaurant = getRestaurant()

	-- Everything the player is carrying (hotbar + overflow).
	local owned = {}
	for _, e in InventoryController.GetAllItems() do owned[e.Name] = true end
	for _, e in InventoryController.GetOverflowItems() do owned[e.Name] = true end

	-- For each recipe step not yet in the pot: is it (or its raw form)
	-- already carried? If not, where does it come from?
	local allAdded = true
	local needFridge, needContainer, rawToChop, nextStep, nextRaw
	for _, step in recipe.Sequence do
		if not addedIngredients[step.Name] then
			allAdded = false
			local raw = nil
			for r, chopped in CookingConfig.ChoppableMap do
				if chopped == step.Name then raw = r break end
			end
			if not nextStep then
				nextStep, nextRaw = step.Name, raw
			end
			local source = raw or step.Name
			if not owned[step.Name] and not (raw and owned[raw]) then
				local inFridge = false
				for _, def in CookingConfig.FridgeItems do
					if def.Name == source then inFridge = true break end
				end
				if inFridge then
					needFridge = needFridge or source
				else
					needContainer = needContainer or source
				end
			elseif raw and not owned[step.Name] then
				rawToChop = rawToChop or raw
			end
		end
	end

	-- An order is "open" from Accept until the dish is delivered (the
	-- poll keeps TutorialGuide.orderOpen current; Accept sets it at once).
	local orderOpen = TutorialGuide.orderOpen == true
	local usedPlate = TutorialGuide.usedPlateIndex

	local anyAdded = next(addedIngredients) ~= nil
	-- The very next pot step still needs chopping (raw carried, chopped not).
	local nextNeedsChop = nextRaw ~= nil and owned[nextRaw] and not owned[nextStep]

	local activeArea, needItem, wantHeld = nil, nil, nil
	if heldName == recipe.PlatingName or owned[recipe.PlatingName] then
		-- Carrying the finished dish (in hand or in the hotbar).
		activeArea, wantHeld = "DiningArea", recipe.PlatingName
	elseif heldName == "EmptyPlate" or owned.EmptyPlate then
		-- Carrying a dirty plate (in hand or just in the hotbar).
		activeArea, wantHeld = "WashArea", "EmptyPlate"
	elseif plateInSink then
		-- Plate already in the sink, not washed yet (or mid-wash).
		activeArea = "WashArea"
	elseif dishReadyAtKitchenIsle then
		activeArea = "KitchenIsle"
	elseif usedPlate and heldName == nil then
		activeArea = "UsedPlate"
	elseif not orderOpen or cookCountActive then
		activeArea = nil -- nothing to do yet / dish is cooking
	elseif not potPlaced then
		activeArea = "CookingArea" -- place a pot first
	elseif allAdded then
		activeArea = "CookingArea" -- start the fire
	elseif needFridge then
		activeArea, needItem = "FridgeArea", needFridge
	elseif needContainer then
		activeArea, needItem = "ItemContainerArea", needContainer
	elseif nextNeedsChop or (anyAdded and rawToChop) then
		-- Tutorial script order: chop the MEAT first and put it in the
		-- pot; after that, chop everything else (onion + garlic) in one go.
		activeArea = "ChoppingArea"
		wantHeld = nextNeedsChop and nextRaw or rawToChop
	else
		activeArea, wantHeld = "CookingArea", nextStep
	end

	setAreaHighlight("ItemContainerArea", activeArea == "ItemContainerArea")
	setAreaHighlight("ChoppingArea", activeArea == "ChoppingArea")
	setAreaHighlight("CookingArea", activeArea == "CookingArea")
	setAreaHighlight("KitchenIsle", activeArea == "KitchenIsle")
	setAreaHighlight("WashArea", activeArea == "WashArea")
	setAreaHighlight("FridgeArea", activeArea == "FridgeArea")
	diningAreaGuideActive = (activeArea == "DiningArea")

	-- Used plate: client-only Highlight on the leftover plate model
	-- (kept in guideHighlights.UsedPlate, no extra local needed).
	local plateModel = nil
	if activeArea == "UsedPlate" and restaurant then
		local stc = restaurant:FindFirstChild("ServingToCustomer")
		local spawner = stc and stc:FindFirstChild("ServedSpawner")
		local att = spawner and spawner:FindFirstChild(tostring(usedPlate))
		plateModel = att and att:FindFirstChild("ServedModel")
	end
	local current = guideHighlights.UsedPlate and guideHighlights.UsedPlate[1]
	if current and (not plateModel or current.Adornee ~= plateModel) then
		current:Destroy()
		guideHighlights.UsedPlate = nil
		current = nil
	end
	if plateModel and not current then
		local h = Instance.new("Highlight")
		h.Name = "UsedPlateGuideHighlight"
		h.FillColor = Color3.fromRGB(255, 221, 88)
		h.FillTransparency = 0.6
		h.OutlineColor = Color3.fromRGB(255, 221, 88)
		h.OutlineTransparency = 0
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		h.Adornee = plateModel
		h.Parent = plateModel
		guideHighlights.UsedPlate = { h }
	end

	-- The sink prompt's visibility depends on what's held, so keep it in
	-- step with every guide refresh (held-item changes land here too).
	refreshSinkPromptText()

	TutorialGuide.SetContext({
		restaurant = restaurant,
		area = activeArea,
		hasAccepted = orderOpen or activeArea ~= nil,
		hasWaiting = hasWaitingCustomer,
		potPlaced = potPlaced,
		allAdded = allAdded,
		anyAdded = anyAdded,
		cooking = cookCountActive,
		dishReady = dishReadyAtKitchenIsle,
		needItem = needItem,
		wantHeld = wantHeld,
		held = heldName,
		awaitingSeat = TutorialGuide.awaitingSeat,
		usedPlateIndex = usedPlate,
	})
end

local function applyOwnerHighlights(restaurant)
	if highlightsApplied then return end
	local areaContainer = restaurant:FindFirstChild("AreaContainer")
	if not areaContainer then return end

	for _, areaName in HIGHLIGHT_AREAS do
		local area = areaContainer:FindFirstChild(areaName)
		local highlightFolder = area and area:FindFirstChild("HighlightDesign")
		if highlightFolder then
			local list = {}
			for _, model in highlightFolder:GetChildren() do
				if model:IsA("Model") or model:IsA("BasePart") then
					-- Reuse the Highlight the designer already placed inside
					-- each model (keeps their chosen color/fill), just make
					-- sure it starts off; only create one if none exists.
					local highlight = model:FindFirstChildOfClass("Highlight")
					if not highlight then
						highlight = Instance.new("Highlight")
						highlight.Name = "OwnerGuideHighlight"
						highlight.FillTransparency = 1
						highlight.OutlineColor = Color3.fromRGB(255, 221, 88)
						highlight.OutlineTransparency = 0
						highlight.DepthMode = Enum.HighlightDepthMode.Occluded
						highlight.Adornee = model
						highlight.Parent = model
					end
					highlight.Enabled = false
					-- DiningArea tables are tracked per-model (each glows only
					-- when its own seats are occupied), not as one always-
					-- together group like the other areas.
					if areaName == "DiningArea" then
						tableHighlights[model.Name] = highlight
					else
						table.insert(list, highlight)
					end
				end
			end
			guideHighlights[areaName] = list
		end
	end

	highlightsApplied = true
	refreshGuideHighlights()
end

-- ---- Proximity polling loop ----

InventoryController.Init()

-- Keep the DiningArea table highlights current even when the Customer
-- panel is closed (that panel's own refresh loop only runs while it's
-- open). Light-weight: one RequestCustomerList poll per second.
task.spawn(function()
	while true do
		task.wait(1)
		if highlightsApplied and not customerPanelOpen then
			local restaurant = getRestaurant()
			if restaurant then
				local data = Remotes.RequestCustomerList:InvokeServer()
				if data then
					local occupied = {}
					local accepted = false
					local stillEating = {}
					TutorialGuide.orderOpen = false
					TutorialGuide.awaitingSeat = nil
					for _, entry in data.Eating do
						if entry.Status == "AwaitingFood" or entry.Status == "Accepted" then
							accepted = true
							if entry.ServingSeatIndex then
								occupied[entry.ServingSeatIndex] = true
							end
						end
						-- Order still needs its dish: accepted, walking over, or
						-- seated waiting.
						if entry.Status == "Relocating" or entry.Status == "AwaitingFood" then
							TutorialGuide.orderOpen = true
						end
						if entry.Status == "AwaitingFood" then
							TutorialGuide.awaitingSeat = entry.ServingSeatIndex
						end
						if entry.Status == "Accepted" and entry.ServingSeatIndex then
							stillEating[entry.ServingSeatIndex] = true
						end
					end
					-- A leftover plate is collectable once nobody is eating
					-- at that table anymore.
					TutorialGuide.usedPlateIndex = nil
					local stc = restaurant:FindFirstChild("ServingToCustomer")
					local spawner = stc and stc:FindFirstChild("ServedSpawner")
					if spawner then
						for _, att in spawner:GetChildren() do
							local idx = tonumber(att.Name)
							if idx and att:FindFirstChild("ServedModel") and not stillEating[idx] then
								TutorialGuide.usedPlateIndex = idx
								break
							end
						end
					end
					hasAcceptedCustomer = accepted
					hasWaitingCustomer = #data.Waiting > 0
					refreshGuideHighlights() -- sets diningAreaGuideActive first
					setActiveTables(occupied)
					if accepted or not hasWaitingCustomer then
						hideCustomerGuide()
						stopClickIndicatorBlink()
					elseif not customerPanelOpen then
						showCustomerGuideIfNeeded()
						startClickIndicatorBlink()
					end
				end
			end
		end
	end
end)

RunService.Heartbeat:Connect(function()
	local hrp = getHRP()
	if not hrp then return end

	local restaurant

	restaurant = getRestaurant()
	if not restaurant then return end
	cacheCookingPrompts(restaurant)
	startFunfactLoop(restaurant)
	applyOwnerHighlights(restaurant)
	POVController.SetRestaurant(restaurant)

	local areaContainer = restaurant:FindFirstChild("AreaContainer")
	if not areaContainer then return end

	-- Container zone
	-- (ItemContainerArea and WashArea sit close together in this map, so
	-- this zone uses a tighter/negative margin instead of the default 3 -
	-- otherwise their trigger boxes overlap and standing near one can
	-- wrongly pop the other's prompt too.)
	local contDetector = areaContainer:FindFirstChild("ItemContainerArea")
		and areaContainer.ItemContainerArea:FindFirstChild("ContainerDetector")
	if contDetector then
		local inZone = isInZone(contDetector, -0.5)
		if inZone and not detectorState.Container then
			detectorState.Container = true
			handleContainerZone(restaurant)
		elseif not inZone then
			detectorState.Container = false
			if storageOpen then closeStorageUI() end
		end
	end

	-- Chopping zone
	local chopDetector = areaContainer:FindFirstChild("ChoppingArea")
		and areaContainer.ChoppingArea:FindFirstChild("ChoppingDetector")
	if chopDetector then
		local inZone = isInZone(chopDetector)
		if inZone and not detectorState.Chopping then
			detectorState.Chopping = true
			handleChoppingZone(restaurant)
		elseif not inZone then
			detectorState.Chopping = false
		end
	end

	-- Cooking zone
	local cookDetector = areaContainer:FindFirstChild("CookingArea")
		and areaContainer.CookingArea:FindFirstChild("CookingDetector")
	if cookDetector then
		local inZone = isInZone(cookDetector)
		if inZone and not detectorState.Cooking then
			detectorState.Cooking = true
			handleCookingZone(restaurant)
		elseif not inZone then
			detectorState.Cooking = false
		end
	end

	-- Wash zone (tight margin - see the Container zone comment above).
	-- Called every frame the player is inside the zone, not just on
	-- entry - handleWashZone's own internal guards (triggerHandled.Wash,
	-- and doWashConfirm's washPopupShowing/plateInSink checks) make
	-- repeat calls a safe no-op. This is what makes stage 3 (the wash
	-- confirm popup) reliably "always detect" a plate that's already
	-- sitting in the sink while the player is standing here, instead of
	-- only ever checking once at the moment they first walked in.
	local washDetector = areaContainer:FindFirstChild("WashArea")
		and areaContainer.WashArea:FindFirstChild("RightSink")
		and areaContainer.WashArea.RightSink:FindFirstChild("WashDetector")
	if washDetector then
		local inZone = isInZone(washDetector, -0.5)
		if inZone then
			detectorState.Wash = true
			handleWashZone(restaurant)
		else
			detectorState.Wash = false
		end
	end

	-- Fridge zone: enter asks to open (popup), exit auto-closes
	local fridgePlayerDetector = areaContainer:FindFirstChild("FridgeArea")
		and areaContainer.FridgeArea:FindFirstChild("PlayerDetector")
	if fridgePlayerDetector then
		local inZone = isInZone(fridgePlayerDetector)
		if inZone and not detectorState.Fridge then
			detectorState.Fridge = true
			handleFridgeZoneEnter(restaurant)
		elseif not inZone and detectorState.Fridge then
			detectorState.Fridge = false
			handleFridgeZoneExit()
		end
	end
end)
