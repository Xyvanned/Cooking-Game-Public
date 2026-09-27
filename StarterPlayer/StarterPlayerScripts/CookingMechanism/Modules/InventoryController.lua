-- Client hotbar state + UI sync
local Players        = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TweenUtil         = require(script.Parent.TweenUtil)
local SoundController   = require(script.Parent.SoundController)
local CookingConfig     = require(ReplicatedStorage.CookingMechanism.Configs.CookingConfig)
local AssetRegistry     = require(ReplicatedStorage.CookingMechanism.Configs.AssetRegistry)
local Remotes           = ReplicatedStorage.CookingMechanism.Remotes

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local clickSound = SoundController.Get("UIClicks")

local InventoryController = {}

-- { [slotIndex] = { Name, Count } }
local slots = {}
-- The single item physically held in the character's hand right now
-- (independent of hotbar slots - a slotless item can still be held)
local currentHeldItem = nil

local function getHotbar()
	local gui = playerGui:FindFirstChild("CookingMechanismGui")
	if not gui then return nil end
	local inv = gui:FindFirstChild("InventoryFrameContainer")
	if not inv then return nil end
	return inv:FindFirstChild("HotBarContainer")
end

local slotButtons = {}

local HOTBAR_SLOTS = 6

-- Overflow items that didn't fit in the 4 hotbar slots
local overflowItems = {} -- { {Name, Count}, ... }

local function buildHotbar()
	local hotbar = getHotbar()
	if not hotbar then return end
	local template = hotbar:FindFirstChild("Template")
	if not template then return end
	template.Visible = false

	for i = 1, HOTBAR_SLOTS do
		local existing = hotbar:FindFirstChild("Slot" .. i)
		if existing then existing:Destroy() end

		local btn = template:Clone()
		btn.Name = "Slot" .. i
		btn.Visible = false
		btn.LayoutOrder = i

		local numLabel = btn:FindFirstChild("SlotNumber")
		if numLabel then numLabel.Text = tostring(i) end

		local imgLabel = btn:FindFirstChild("ItemImage")
		if imgLabel then imgLabel.Image = "" end

		local nameLabel = btn:FindFirstChild("ItemName")
		if nameLabel then nameLabel.Text = "" end

		TweenUtil.AddHoverEffect(btn, 1.06, clickSound)

		btn.Activated:Connect(function()
			InventoryController.SelectSlot(i)
		end)
		InventoryController.MakeDraggable(btn, "Hotbar", i)

		btn.Parent = hotbar
		slotButtons[i] = btn
	end
end

local function findSlotForItem(itemName)
	for i = 1, HOTBAR_SLOTS do
		if slots[i] and slots[i].Name == itemName then
			return i
		end
	end
	return nil
end

local function refreshSlot(i)
	local btn = slotButtons[i]
	if not btn then return end

	local data = slots[i]
	local imgLabel  = btn:FindFirstChild("ItemImage")
	local nameLabel = btn:FindFirstChild("ItemName")

	if data and data.Count > 0 then
		if imgLabel  then imgLabel.Image = AssetRegistry.GetIngredientImage(data.Name) end
		if nameLabel then nameLabel.Text  = data.Name end
		btn.Visible = true
	else
		slots[i] = nil
		btn.Visible = false
		if imgLabel  then imgLabel.Image = "" end
		if nameLabel then nameLabel.Text  = "" end
	end

	local isSelected = data ~= nil and data.Name == currentHeldItem
	TweenUtil.Tween(btn, 0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, {
		ImageTransparency = isSelected and 0 or 0.35,
	})
end

local function refreshAllSlots()
	for i = 1, HOTBAR_SLOTS do
		refreshSlot(i)
	end
end

-- ---- Drag & drop between Hotbar slots and HoverInventory overflow ----

local UserInputService = game:GetService("UserInputService")
local dragGhost = nil
local dragInfo = nil -- { Kind = "Hotbar"|"Overflow", Key = slotIndex or itemName }
local DRAG_THRESHOLD = 6
local overflowChangedCallback = nil

-- RestaurantController registers this to rebuild HoverInventory after a swap
function InventoryController.OnOverflowChanged(callback)
	overflowChangedCallback = callback
end

local function notifyOverflowChanged()
	if overflowChangedCallback then overflowChangedCallback() end
end

local heldChangedCallback = nil

-- RestaurantController registers this to react whenever the held item
-- changes (e.g. re-check chopping zone popup on a fresh equip)
function InventoryController.OnHeldChanged(callback)
	heldChangedCallback = callback
end

local function notifyHeldChanged()
	if heldChangedCallback then heldChangedCallback(currentHeldItem) end
end

local function getDragGhost()
	if dragGhost and dragGhost.Parent then return dragGhost end
	local gui = playerGui:FindFirstChild("CookingMechanismGui")
	if not gui then return nil end
	local ghost = Instance.new("ImageLabel")
	ghost.Name = "DragGhost"
	ghost.Size = UDim2.new(0, 64, 0, 64)
	ghost.AnchorPoint = Vector2.new(0.5, 0.5)
	ghost.BackgroundTransparency = 1
	ghost.ImageTransparency = 0.15
	ghost.ZIndex = 1000
	ghost.Visible = false
	ghost.Parent = gui
	dragGhost = ghost
	return ghost
end

-- Swaps two hotbar slots' contents directly
function InventoryController.SwapSlots(a, b)
	if a == b then return end
	slots[a], slots[b] = slots[b], slots[a]
	refreshSlot(a)
	refreshSlot(b)
end

-- Swaps a hotbar slot's contents with a named overflow item
function InventoryController.SwapSlotWithOverflow(slotIndex, itemName)
	local slotData = slots[slotIndex]
	local overflowIdx, overflowData = nil, nil
	for i, entry in overflowItems do
		if entry.Name == itemName then
			overflowIdx, overflowData = i, entry
			break
		end
	end
	if not overflowData then return end

	if slotData then
		overflowItems[overflowIdx] = { Name = slotData.Name, Count = slotData.Count }
	else
		table.remove(overflowItems, overflowIdx)
	end
	slots[slotIndex] = { Name = overflowData.Name, Count = overflowData.Count }

	refreshSlot(slotIndex)
	notifyOverflowChanged()
end

local function endDrag(dropPosition)
	local info = dragInfo
	dragInfo = nil
	local ghost = getDragGhost()
	if ghost then ghost.Visible = false end
	if not info or not dropPosition then return end

	local hitObjects = playerGui:GetGuiObjectsAtPosition(dropPosition.X, dropPosition.Y)
	local targetButton = nil
	for _, obj in hitObjects do
		if obj:GetAttribute("DragKind") then
			targetButton = obj
			break
		end
	end
	if not targetButton then return end

	local targetKind = targetButton:GetAttribute("DragKind")
	local targetKey  = targetButton:GetAttribute("DragKey")

	if info.Kind == "Hotbar" and targetKind == "Hotbar" then
		InventoryController.SwapSlots(info.Key, targetKey)
	elseif info.Kind == "Hotbar" and targetKind == "Overflow" then
		InventoryController.SwapSlotWithOverflow(info.Key, targetKey)
	elseif info.Kind == "Overflow" and targetKind == "Hotbar" then
		InventoryController.SwapSlotWithOverflow(targetKey, info.Key)
	end
end

-- Makes a UI button draggable so dropping it on another draggable
-- swaps their contents (Hotbar <-> HoverInventory overflow).
function InventoryController.MakeDraggable(button, kind, key)
	button:SetAttribute("DragKind", kind)
	button:SetAttribute("DragKey", key)

	local pressed = false
	local pressPos = nil

	button.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		pressed = true
		pressPos = input.Position
	end)

	button.InputChanged:Connect(function(input)
		if not pressed then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		if not dragInfo and pressPos and (input.Position - pressPos).Magnitude > DRAG_THRESHOLD then
			local imgLabel = button:FindFirstChild("ItemImage")
			local ghost = getDragGhost()
			if ghost and imgLabel and imgLabel.Image ~= "" then
				ghost.Image = imgLabel.Image
				ghost.Visible = true
				dragInfo = { Kind = kind, Key = key }
			end
		end

		if dragInfo and dragInfo.Kind == kind and dragInfo.Key == key then
			local ghost = getDragGhost()
			if ghost then
				ghost.Position = UDim2.new(0, input.Position.X, 0, input.Position.Y)
			end
		end
	end)

	button.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		pressed = false
		if dragInfo and dragInfo.Kind == kind and dragInfo.Key == key then
			endDrag(input.Position)
		end
	end)
end

function InventoryController.AddItem(itemName)
	-- Try existing hotbar slot first
	for i = 1, HOTBAR_SLOTS do
		if slots[i] and slots[i].Name == itemName then
			slots[i].Count += 1
			refreshSlot(i)
			return i
		end
	end
	-- Try free hotbar slot
	for i = 1, HOTBAR_SLOTS do
		if not slots[i] then
			slots[i] = { Name = itemName, Count = 1 }
			refreshSlot(i)
			return i
		end
	end
	-- Hotbar full: add to overflow (for HoverInventory)
	for _, entry in overflowItems do
		if entry.Name == itemName then
			entry.Count += 1
			return -1
		end
	end
	table.insert(overflowItems, { Name = itemName, Count = 1 })
	return -1
end

-- Pulls the first overflow item (if any) into the given empty hotbar
-- slot, so a slot freed by consuming its last item is auto-refilled
-- from HoverInventory instead of sitting empty.
local function refillSlotFromOverflow(slotIndex)
	if slots[slotIndex] then return end -- only fill genuinely empty slots
	local entry = overflowItems[1]
	if not entry then return end
	table.remove(overflowItems, 1)
	slots[slotIndex] = { Name = entry.Name, Count = entry.Count }
	refreshSlot(slotIndex)
	notifyOverflowChanged()
end

function InventoryController.RemoveItem(itemName)
	for i = 1, HOTBAR_SLOTS do
		if slots[i] and slots[i].Name == itemName then
			slots[i].Count -= 1
			if slots[i].Count <= 0 then
				slots[i] = nil
				refreshSlot(i)
				refillSlotFromOverflow(i)
			else
				refreshSlot(i)
			end
			return true
		end
	end
	-- Check overflow
	for idx, entry in overflowItems do
		if entry.Name == itemName then
			entry.Count -= 1
			if entry.Count <= 0 then
				table.remove(overflowItems, idx)
				notifyOverflowChanged()
			end
			return true
		end
	end
	return false
end

function InventoryController.GetSelectedItem()
	if not currentHeldItem then return nil end
	-- Check hotbar
	local slotIdx = findSlotForItem(currentHeldItem)
	if slotIdx then return slots[slotIdx] end
	-- Check overflow
	for _, entry in overflowItems do
		if entry.Name == currentHeldItem then return entry end
	end
	return { Name = currentHeldItem, Count = 1 }
end

-- Marks an item as physically held right now (does not touch server state;
-- call this after a server call already confirmed the item is in hand)
function InventoryController.SetHeld(itemName)
	currentHeldItem = itemName
	refreshAllSlots()
	notifyHeldChanged()
end

function InventoryController.ClearHeld()
	currentHeldItem = nil
	refreshAllSlots()
	notifyHeldChanged()
end

local togglingHold = false

function InventoryController.SelectSlot(i)
	if togglingHold then return end
	local data = slots[i]
	if not data then return end

	if clickSound then clickSound:Play() end

	togglingHold = true
	local result = Remotes.ToggleHold:InvokeServer(data.Name)
	togglingHold = false

	if result and result.Success then
		currentHeldItem = result.Holding and data.Name or nil
	end

	refreshAllSlots()
	notifyHeldChanged()
end

function InventoryController.Clear()
	for i = 1, HOTBAR_SLOTS do
		slots[i] = nil
	end
	overflowItems = {}
	currentHeldItem = nil
	refreshAllSlots()
end

-- Returns hotbar + overflow combined (for HoverInventory display)
-- Skips items already in hotbar for HoverInventory (no visual duplicates)
function InventoryController.GetAllItems()
	local result = {}
	for i = 1, HOTBAR_SLOTS do
		if slots[i] then
			table.insert(result, { Slot = i, Name = slots[i].Name, Count = slots[i].Count })
		end
	end
	return result
end

function InventoryController.GetOverflowItems()
	local result = {}
	for _, entry in overflowItems do
		if entry.Count > 0 then
			table.insert(result, { Name = entry.Name, Count = entry.Count })
		end
	end
	return result
end

local HOTBAR_KEYS = {
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.Five,
	Enum.KeyCode.Six,
}

local function bindHotbarKeys()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		for i, keyCode in HOTBAR_KEYS do
			if input.KeyCode == keyCode then
				InventoryController.SelectSlot(i)
				break
			end
		end
	end)
end

local initialized = false

function InventoryController.Init()
	if initialized then return end
	initialized = true
	buildHotbar()
	bindHotbarKeys()
end

return InventoryController
