-- Skill tree definitions - a proper branching tree from one root:
--
--   Root
--    +-- CustomerRarity (top branch, linear, 5 tiers)
--    +-- ChefUnlock (middle branch hub, 1 tier - gated by Served >= 50,
--    |     not money - see PlayerDataService.PurchaseSkillTier)
--    |     +-- CookTime  (child branch, linear, 5 tiers - needs ChefUnlock)
--    |     +-- ChopTime  (child branch, linear, 5 tiers - needs ChefUnlock)
--    |     +-- WashTime  (child branch, linear, 5 tiers - needs ChefUnlock)
--    +-- WalkSpeed (bottom branch, linear, 5 tiers)

local SkillConfig = {}

SkillConfig.MaxTier = 5

-- Customers required served before ChefUnlock can be bought at all
-- (in addition to/instead of a money cost - see PlayerDataService).
SkillConfig.ChefUnlockServedRequirement = 50

SkillConfig.Branches = {
	CustomerRarity = {
		DisplayName = "Customer Rarity",
		Description = "Small chance for rarer customers (Legendary/Mythical/Secret) to visit, on top of whatever your equipped recipe normally attracts.",
		-- Each tier is a table of ADDITIVE bonus chances (fractions),
		-- not a single number - rolled via CustomerConfig.RollBonusRarity
		-- before falling back to the recipe's own weighted pick. Doubles
		-- each tier.
		TierValues = {
			{ Legendary = 0.01,  Mythical = 0.001,  Secret = 0.000001 },
			{ Legendary = 0.02,  Mythical = 0.002,  Secret = 0.000002 },
			{ Legendary = 0.04,  Mythical = 0.004,  Secret = 0.000004 },
			{ Legendary = 0.08,  Mythical = 0.008,  Secret = 0.000008 },
			{ Legendary = 0.16,  Mythical = 0.016,  Secret = 0.000016 },
		},
		TierCosts = { 500, 1500, 3000, 5000, 10000 },
		Format = function(value)
			return string.format("+%.4f%% Legendary, +%.4f%% Mythical, +%.6f%% Secret",
				value.Legendary * 100, value.Mythical * 100, value.Secret * 100)
		end,
	},
	ChefUnlock = {
		DisplayName = "Chef Unlock",
		Description = "Unlocks the Cooking, Chopping, and Washing skill branches. Requires having served " .. 50 .. " customers.",
		TierValues = { 1 },
		TierCosts  = { 0 }, -- free - gated by ServedRequirement instead of money
		Format = function() return "Unlocked" end,
	},
	CookTime = {
		DisplayName = "Cooking Time",
		Description = "Reduce how long dishes take to cook.",
		RequiresBranch = "ChefUnlock",
		TierValues = { 0.04, 0.08, 0.12, 0.16, 0.20 },
		TierCosts  = { 1000, 2500, 5000, 10000, 20000 },
		Format = function(value) return "-" .. math.floor(value * 100) .. "% Cook Time" end,
	},
	ChopTime = {
		DisplayName = "Chopping Time",
		Description = "Chop ingredients faster.",
		RequiresBranch = "ChefUnlock",
		TierValues = { 0.04, 0.08, 0.12, 0.16, 0.20 },
		TierCosts  = { 1000, 2500, 5000, 10000, 20000 },
		Format = function(value) return "-" .. math.floor(value * 100) .. "% Chop Time" end,
	},
	WashTime = {
		DisplayName = "Washing Time",
		Description = "Wash plates faster.",
		RequiresBranch = "ChefUnlock",
		TierValues = { 0.04, 0.08, 0.12, 0.16, 0.20 },
		TierCosts  = { 1000, 2500, 5000, 10000, 20000 },
		Format = function(value) return "-" .. math.floor(value * 100) .. "% Wash Time" end,
	},
	WalkSpeed = {
		DisplayName = "Walking Speed",
		Description = "Move a little faster around your restaurant.",
		TierValues = { 2, 4, 6, 8, 10 },
		TierCosts  = { 150, 500, 2000, 5000, 8000 },
		Format = function(value) return "+" .. value .. " Speed" end,
	},
}

-- Root's three main branches, in draw order (top/middle/bottom).
SkillConfig.RootBranches = { "CustomerRarity", "ChefUnlock", "WalkSpeed" }
-- ChefUnlock's own children, in draw order (top/middle/bottom of that group).
SkillConfig.ChefChildren = { "CookTime", "ChopTime", "WashTime" }

-- Every branch in a flat, sensible render order (used by anything that
-- doesn't care about tree shape, e.g. building a plain list).
SkillConfig.BranchOrder = { "CustomerRarity", "ChefUnlock", "CookTime", "ChopTime", "WashTime", "WalkSpeed" }

function SkillConfig.GetCost(branchName, tier)
	local branch = SkillConfig.Branches[branchName]
	if not branch then return nil end
	return branch.TierCosts[tier + 1]
end

function SkillConfig.GetValueAtTier(branchName, tier)
	local branch = SkillConfig.Branches[branchName]
	if not branch then return 0 end
	if tier <= 0 then
		-- CustomerRarity's "zero" is a table of zero fractions, not the
		-- number 0 - match whatever shape TierValues actually uses.
		if typeof(branch.TierValues[1]) == "table" then
			return { Legendary = 0, Mythical = 0, Secret = 0 }
		end
		return 0
	end
	local maxTier = #branch.TierValues
	return branch.TierValues[math.min(tier, maxTier)]
end

return SkillConfig
