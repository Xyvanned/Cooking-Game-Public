-- Customer rarity weights, recipe attraction, gradient colors
local CustomerConfig = {}

-- Ordered weakest-to-strongest. Used to be what the SkillConfig.
-- CustomerRarity skill branch gated eligibility by; that branch now
-- works differently (a flat bonus-chance roll for Legendary/Mythical/
-- Secret on top of the recipe's own weights - see
-- CustomerConfig.RollBonusRarity), so this list is now just the
-- canonical weakest->strongest ordering used elsewhere (gradients, etc).
CustomerConfig.RarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythical", "Secret" }

-- Baseline spawn odds (used when player has no recipe equipped)
CustomerConfig.GlobalRarityWeights = {
	Common    = 63.8,
	Uncommon  = 24.1,
	Rare      = 14,
	Epic      = 8,
	Legendary = 4,
	Mythical  = 0.1,
}

-- Per-recipe attraction odds (overrides global odds while that recipe is equipped)
CustomerConfig.RecipeAttraction = {
	Adobo = {
		Common   = 80,
		Uncommon = 15,
		Rare     = 5,
	},
}

-- Rarity text gradients (3-stop: start, middle, end), extracted from the
-- customer Rarity labels already authored in ServerStorage.
-- Common has no gradient (plain white).
CustomerConfig.RarityGradients = {
	Uncommon = {
		Color3.fromRGB(0, 255, 60),
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(91, 254, 21),
	},
	Rare = {
		Color3.fromRGB(51, 86, 152),
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(65, 58, 255),
	},
	Epic = {
		Color3.fromRGB(247, 183, 255),
		Color3.fromRGB(251, 251, 251),
		Color3.fromRGB(255, 188, 235),
	},
	Legendary = {
		Color3.fromRGB(255, 170, 0),
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(255, 170, 0),
	},
	Mythical = {
		Color3.fromRGB(255, 0, 4),
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(255, 8, 12),
	},
	Secret = {
		Color3.fromRGB(20, 20, 20),
		Color3.fromRGB(120, 0, 130),
		Color3.fromRGB(20, 20, 20),
	},
	FoodCritic = {
		Color3.fromRGB(255, 215, 0),
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(184, 134, 11),
	},
}

function CustomerConfig.GetRarityGradient(rarity)
	local stops = CustomerConfig.RarityGradients[rarity]
	if not stops then return nil end
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, stops[1]),
		ColorSequenceKeypoint.new(0.5, stops[2]),
		ColorSequenceKeypoint.new(1, stops[3]),
	})
end

-- Seconds per full 360 spin, faster for rarer tiers
CustomerConfig.RaritySpinTime = {
	Uncommon   = 4,
	Rare       = 3.5,
	Epic       = 3,
	Legendary  = 2.5,
	Mythical   = 2,
	Secret     = 1.6,
	FoodCritic = 2.2,
}

-- Single shared entry point for every UI that shows a rarity-colored,
-- rotating gradient (customer nametag Rarity chip, Customer-panel cards,
-- anywhere else). Common gets no gradient (plain color). Creates a
-- UIGradient on the target if one doesn't already exist.
local TweenService = game:GetService("TweenService")

function CustomerConfig.ApplyRarityGradient(guiObject, rarity)
	if not guiObject then return end

	local gradient = guiObject:FindFirstChildOfClass("UIGradient")
	local sequence = CustomerConfig.GetRarityGradient(rarity)

	if rarity == "Common" or not sequence then
		if gradient then gradient.Enabled = false end
		return
	end

	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Parent = guiObject
	end
	gradient.Enabled = true
	gradient.Color = sequence

	local spinTime = CustomerConfig.RaritySpinTime[rarity] or 3
	TweenService:Create(gradient, TweenInfo.new(spinTime, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false), {
		Rotation = 360,
	}):Play()
end

-- Folder names under CustomersContainer, matching each rarity tier
CustomerConfig.RarityFolders = {
	Common    = "Common",
	Uncommon  = "Uncommon",
	Rare      = "Rare",
	Epic      = "Epic",
	Legendary = "Legendary",
	Mythical  = "Mythical",
	Secret    = "Secret",
}

-- Gameplay tuning
CustomerConfig.PATIENCE_TIME = 60 -- seconds once seated
CustomerConfig.SPAWN_INTERVAL_MIN = 12
CustomerConfig.SPAWN_INTERVAL_MAX = 22

-- Weighted random pick from a { Name = weight } table
function CustomerConfig.WeightedPick(weights)
	local total = 0
	for _, w in weights do
		total += w
	end
	local roll = math.random() * total
	local cumulative = 0
	for name, w in weights do
		cumulative += w
		if roll <= cumulative then
			return name
		end
	end
	-- fallback (floating point edge case)
	local first
	for name in weights do first = name break end
	return first
end

-- Rolls for a bonus-unlocked rarity (Legendary/Mythical/Secret) based on
-- the restaurant owner's CustomerRarity skill tier, BEFORE falling back
-- to the recipe's own weighted pick. This is additive, not a filter -
-- a recipe like Adobo only lists Common/Uncommon/Rare in its own
-- attraction table, so without this roll those rarer customers could
-- never appear no matter what's equipped. `bonus` is
-- SkillConfig.GetValueAtTier("CustomerRarity", tier), a table of
-- {Legendary=frac, Mythical=frac, Secret=frac} fractions. Returns a
-- rarity name, or nil if the roll didn't hit any of the three (caller
-- should fall back to the normal weighted pick in that case).
function CustomerConfig.RollBonusRarity(bonus)
	if not bonus then return nil end
	local roll = math.random()
	if roll < (bonus.Secret or 0) then return "Secret" end
	if roll < (bonus.Secret or 0) + (bonus.Mythical or 0) then return "Mythical" end
	if roll < (bonus.Secret or 0) + (bonus.Mythical or 0) + (bonus.Legendary or 0) then return "Legendary" end
	return nil
end

return CustomerConfig
