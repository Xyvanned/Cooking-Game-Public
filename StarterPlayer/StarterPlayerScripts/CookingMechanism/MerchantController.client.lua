-- Merchant stall interaction controller
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local TweenUtil = require(script.Parent.Modules.TweenUtil)
local SoundController = require(script.Parent.Modules.SoundController)
local UIEffectController = require(script.Parent.Modules.UIEffectController)
local MessengerController = require(script.Parent.Modules.MessengerController)
local MerchantConfig = require(ReplicatedStorage.CookingMechanism.Configs.MerchantConfig)
local CookingConfig = require(ReplicatedStorage.CookingMechanism.Configs.CookingConfig)
local AssetRegistry = require(ReplicatedStorage.CookingMechanism.Configs.AssetRegistry)
local Remotes = ReplicatedStorage.CookingMechanism.Remotes

local merchantUI = playerGui:WaitForChild("MerchantUI")
local dialogFrame = merchantUI:WaitForChild("Dialog")
local uiContainer = merchantUI:WaitForChild("UIContainer")
local dialogTemplate = dialogFrame:WaitForChild("template")

for _, panel in uiContainer:GetChildren() do
	if panel:IsA("ImageLabel") then
		UIEffectController.RegisterPanel(panel)
	end
end

local clickSound = SoundController.Get("UIClicks")
local blipSound = SoundController.Get("DialogueBlip")

local shopBezier = TweenUtil.CubicBezier(0.34, 1.56, 0.64, 1)

local activeMerchant = nil
local activeStallTrigger = nil
local DISMISS_DISTANCE = 20

----- Dialog helpers -----

local function clearDialog()
	for _, child in dialogFrame:GetChildren() do
		if child:IsA("ImageButton") and child ~= dialogTemplate then
			child:Destroy()
		end
	end
end

----- Distance check -----

local function getPlayerDistance(triggerPart)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or not triggerPart then return math.huge end
	return (root.Position - triggerPart.Position).Magnitude
end

local function dismissAll()
	if blipSound then blipSound:Stop() end
	clearDialog()
	dialogFrame.Visible = false
	local shopWasOpen = false
	for _, panel in uiContainer:GetChildren() do
		if panel:IsA("ImageLabel") then
			if panel.Visible then shopWasOpen = true end
			panel.Visible = false
		end
	end
	if shopWasOpen then
		UIEffectController.Close()
	end
	activeMerchant = nil
	activeStallTrigger = nil
end

local function createLine(isNpc)
	local clone = dialogTemplate:Clone()
	clone.Name = "DialogLine"
	clone.Visible = true
	clone.Size = UDim2.new(1, 0, 0, 40)
	clone.AutomaticSize = Enum.AutomaticSize.None
	clone.BackgroundTransparency = isNpc and 1 or 1
	clone.ImageTransparency = 1
	clone.Interactable = not isNpc

	local label = clone:FindFirstChild("text")
	if label then
		label.Text = ""
		label.Size = UDim2.new(1, -10, 1, 0)
		label.Position = UDim2.new(0, 5, 0, 0)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = isNpc and Color3.fromRGB(255, 230, 150) or Color3.fromRGB(255, 255, 255)
	end

	clone.Parent = dialogFrame
	return clone
end

local function typeLine(lineInstance, fullText, withBlip)
	local label = lineInstance:FindFirstChild("text")
	if not label then return end
	label.Text = ""
	for i = 1, #fullText do
		label.Text = string.sub(fullText, 1, i)
		if withBlip and blipSound and i % 3 == 0 then
			blipSound:Play()
		end
		task.wait(MerchantConfig.TYPE_SPEED)
	end
	if blipSound then blipSound:Stop() end
end

----- Shop UI bezier open/close -----

local function openShopUI(shopName)
	local panel = uiContainer:FindFirstChild(shopName)
	if not panel then return end

	UIEffectController.Open()
	panel.Visible = true
	local baseSize = panel.Size
	panel.Size = UDim2.new(baseSize.X.Scale * 0.3, 0, baseSize.Y.Scale * 0.3, 0)
	panel.ImageTransparency = 1

	TweenUtil.PlayCustomEase(MerchantConfig.SHOP_TWEEN_TIME, shopBezier, function(alpha)
		local s = 0.3 + 0.7 * alpha
		panel.Size = UDim2.new(baseSize.X.Scale * s, 0, baseSize.Y.Scale * s, 0)
		panel.ImageTransparency = 1 - alpha
	end)

	local exitBtn = panel:FindFirstChild("Exit")
	if exitBtn then
		TweenUtil.AddHoverEffect(exitBtn, 1.1, clickSound)
	end
end

local function closeShopUI(shopName)
	local panel = uiContainer:FindFirstChild(shopName)
	if not panel then return end

	local baseSize = panel.Size
	TweenUtil.Tween(panel, 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In, {
		Size = UDim2.new(baseSize.X.Scale * 0.3, 0, baseSize.Y.Scale * 0.3, 0),
		ImageTransparency = 1,
	})
	task.wait(0.25)
	panel.Visible = false
	panel.Size = baseSize
	panel.ImageTransparency = 0
	UIEffectController.Close()
end

----- Ingredient shop: rewire IngredientUI.Item to our real ingredients -----
-- (WholeOnion, Garlic, SoySauce, Seasoning, Vinegar, WholeChicken) - the
-- same six CookingConfig.ContainerItems/FridgeItems tracks starting
-- stock for. Prices come from MerchantConfig.IngredientPrices (a
-- SEPARATE list from that starting stock). Buying goes through
-- Remotes.PurchaseIngredient, Money only - no Robux path for ingredients.

local ingredientItemList = uiContainer:WaitForChild("IngredientUI"):WaitForChild("Item")
local ingredientTemplateButton = ingredientItemList:WaitForChild("TemplateButton")
local ingredientHover = ingredientItemList:WaitForChild("HoverTemplate")
ingredientTemplateButton.Visible = false
ingredientHover.Visible = false

local shopIngredients = {}
for _, def in CookingConfig.ContainerItems do
	table.insert(shopIngredients, def)
end
for _, def in CookingConfig.FridgeItems do
	table.insert(shopIngredients, def)
end

local ingredientButtons = {} -- itemName -> button
local selectedIngredient = nil

local function hideIngredientHover()
	ingredientHover.Visible = false
	selectedIngredient = nil
end

local function selectIngredient(itemDef, order)
	selectedIngredient = itemDef.Name
	local price = MerchantConfig.IngredientPrices[itemDef.Name]

	local robuxSelection = ingredientHover:FindFirstChild("RobuxSelection")
	local robuxBuySelection = ingredientHover:FindFirstChild("RobuxBuySelection")
	local buyMoney = ingredientHover:FindFirstChild("BuyMoney")
	-- Ingredients are Money-only - no Robux path for this stall.
	if robuxSelection then robuxSelection.Visible = false end
	if robuxBuySelection then robuxBuySelection.Visible = false end
	if buyMoney then buyMoney.Text = "$" .. tostring(price or 0) end

	-- Sits directly after the item that was clicked in the list.
	ingredientHover.LayoutOrder = order + 1
	ingredientHover.Visible = true
end

local function buildIngredientShop()
	for _, btn in ingredientButtons do
		btn:Destroy()
	end
	table.clear(ingredientButtons)
	hideIngredientHover()

	for i, def in shopIngredients do
		local btn = ingredientTemplateButton:Clone()
		btn.Name = "Item_" .. def.Name
		btn.Visible = true
		btn.LayoutOrder = i * 2

		local imgLabel = btn:FindFirstChild("ItemImage")
		if imgLabel then imgLabel.Image = AssetRegistry.GetIngredientImage(def.Name) end
		local nameLabel = btn:FindFirstChild("ItemName")
		if nameLabel then nameLabel.Text = def.Display end
		local rarityLabel = btn:FindFirstChild("Rarity")
		if rarityLabel then rarityLabel.Text = "" end

		TweenUtil.AddHoverEffect(btn, 1.05, clickSound)
		btn.Activated:Connect(function()
			if clickSound then clickSound:Play() end
			if selectedIngredient == def.Name then
				hideIngredientHover()
			else
				selectIngredient(def, btn.LayoutOrder)
			end
		end)

		btn.Parent = ingredientItemList
		ingredientButtons[def.Name] = btn
	end
end
buildIngredientShop()

local ingredientBuyMoneyBtn = ingredientHover:FindFirstChild("BuyMoney")
if ingredientBuyMoneyBtn then
	TweenUtil.AddHoverEffect(ingredientBuyMoneyBtn, 1.06, clickSound)
	ingredientBuyMoneyBtn.Activated:Connect(function()
		if clickSound then clickSound:Play() end
		local itemName = selectedIngredient
		if not itemName then return end

		local ok, reason = Remotes.PurchaseIngredient:InvokeServer(itemName)
		if ok then
			MessengerController.Warn("Bought more " .. itemName .. "!")
			hideIngredientHover()
		elseif reason == "NotEnoughMoney" then
			MessengerController.Warn("Not enough money for that.")
		elseif reason == "NotOutYet" then
			MessengerController.Warn("You still have some of that left.")
		else
			MessengerController.Warn("Could not buy: " .. tostring(reason))
		end
	end)
end

----- Restocking surface countdown -----

local function startRestockLoop(stallModel, labelPartName, restockTime)
	local surfaceContainer = stallModel:FindFirstChild("SurfaceGuiContainer")
	if not surfaceContainer then return end
	local labelPart = surfaceContainer:FindFirstChild(labelPartName)
	if not labelPart then return end
	local surfaceGui = labelPart:FindFirstChildOfClass("SurfaceGui")
	if not surfaceGui then return end
	local restockLabel = surfaceGui:FindFirstChild("RestockTyping")
	if not restockLabel then return end

	task.spawn(function()
		while true do
			for t = restockTime, 0, -1 do
				local dotCount = (restockTime - t) % 4
				local dots = string.rep(".", dotCount)
				restockLabel.Text = "Restocking in about " .. t .. "s" .. dots
				task.wait(1)
			end
			restockLabel.Text = "Restocked!"
			task.wait(2)
		end
	end)
end

----- Dialog sequence -----

local function runDialogSequence(stallConfig, triggerPart)
	if activeMerchant then return end
	activeMerchant = stallConfig
	activeStallTrigger = triggerPart

	-- Phase 1: NPC greeting (read-only, alone)
	dialogFrame.Size = UDim2.new(0.4, 0, 0, 50)
	clearDialog()
	dialogFrame.Visible = true

	local npcLine = createLine(true)
	typeLine(npcLine, stallConfig.Greeting, true)

	-- Hold for remaining time up to 7s
	local greetingHold = 7 - (#stallConfig.Greeting * MerchantConfig.TYPE_SPEED)
	if greetingHold > 0 then task.wait(greetingHold) end

	if not activeMerchant then
		return
	end

	-- Destroy NPC line, show player choices
	npcLine:Destroy()

	-- Phase 2: Player choices (separate)
	dialogFrame.Size = UDim2.new(0.4, 0, 0, 90)

	local buyLine = createLine(false)
	buyLine:FindFirstChild("text").Text = stallConfig.BuyOption
	TweenUtil.AddHoverEffect(buyLine, 1.05, clickSound)

	local leaveLine = createLine(false)
	leaveLine:FindFirstChild("text").Text = stallConfig.LeaveOption
	TweenUtil.AddHoverEffect(leaveLine, 1.05, clickSound)

	local choice = nil
	local buyCon = buyLine.Activated:Once(function() choice = "buy" end)
	local leaveCon = leaveLine.Activated:Once(function() choice = "leave" end)

	repeat task.wait() until choice or not activeMerchant
	buyCon:Disconnect()
	leaveCon:Disconnect()

	if not activeMerchant then
		return
	end
	if clickSound then clickSound:Play() end

	if choice == "buy" then
		dialogFrame.Visible = false
		clearDialog()
		openShopUI(stallConfig.ShopUI)

		local panel = uiContainer:FindFirstChild(stallConfig.ShopUI)
		if panel then
			local exitBtn = panel:FindFirstChild("Exit")
			if exitBtn then
				local exited = false
				local exitCon = exitBtn.Activated:Once(function() exited = true end)
				repeat task.wait() until exited or not activeMerchant
				exitCon:Disconnect()
				if not activeMerchant then
					return
				end
				if clickSound then clickSound:Play() end
			end
		end

		closeShopUI(stallConfig.ShopUI)
	end

	if not activeMerchant then
		return
	end

	-- Phase 3: Farewell (read-only)
	clearDialog()
	dialogFrame.Size = UDim2.new(0.4, 0, 0, 50)
	dialogFrame.Visible = true
	local farewellLine = createLine(true)
	typeLine(farewellLine, stallConfig.Farewell, true)
	task.wait(1.5)
	dialogFrame.Visible = false
	clearDialog()

	activeMerchant = nil
	activeStallTrigger = nil
end

----- Wire proximity prompts -----

local function resolveStall(prompt)
	local stallModel = prompt.Parent and prompt.Parent.Parent
	if not stallModel then return nil end

	for _, config in MerchantConfig.Stalls do
		local parts = string.split(config.StallPath, ".")
		local name = parts[#parts]
		if stallModel.Name == name then
			return config, stallModel
		end
	end
	return nil
end

ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
	if triggeringPlayer ~= player then return end
	local config, stallModel = resolveStall(prompt)
	if not config then return end
	local triggerPart = stallModel:FindFirstChild("Trigger")
	runDialogSequence(config, triggerPart)
end)

----- Distance monitor -----

task.spawn(function()
	while true do
		if activeMerchant and activeStallTrigger then
			if getPlayerDistance(activeStallTrigger) > DISMISS_DISTANCE then
				dismissAll()
			end
		end
		task.wait(0.3)
	end
end)

----- Start restocking loops -----

local stalls = game.Workspace:WaitForChild("CookingMechanism")
startRestockLoop(stalls:WaitForChild("ConstructionStall"), "ConstructionRestocking", MerchantConfig.Stalls.Construction.RestockTime)
startRestockLoop(stalls:WaitForChild("IngredientStall"), "IngredientRestocking", MerchantConfig.Stalls.Ingredient.RestockTime)
