-- All recipe definitions live here
local RecipeConfig = {}

RecipeConfig.ActiveRecipe = "Adobo"

-- Cooked color for the Pot's SoupConfiguration part
RecipeConfig.CookedSoupColor = Color3.fromRGB(92, 51, 23)

RecipeConfig.Recipes = {
	Adobo = {
		DisplayName = "Chicken Adobo",
		Rarity      = "Common",
		-- Which dining crowd this recipe appeals to, shown as two fill
		-- bars in the Recipe Index's "Learn More" card. Common-rarity
		-- dishes are purely casual dining; rarer recipes would shift
		-- toward High Class as they're added.
		DinnerType  = { Casual = 100, HighClass = 0 },
		CookTime    = 20,
		SizzleDelay = 10,
		PlatingName = "AdoboPlating",
		Price       = 50,
		-- Strict order ingredients must be added to the pot
		Sequence = {
			{ Name = "ChoppedChicken", Display = "Chopped Chicken" },
			{ Name = "ChoppedGarlic",  Display = "Chopped Garlic"  },
			{ Name = "ChoppedOnion",   Display = "Chopped Onion"   },
			{ Name = "Seasoning",      Display = "Seasoning"       },
			{ Name = "SoySauce",       Display = "Soy Sauce"       },
			{ Name = "Vinegar",        Display = "Vinegar"         },
		},
	},
}

function RecipeConfig.GetActive()
	return RecipeConfig.Recipes[RecipeConfig.ActiveRecipe]
end

-- Returns { {Key="Adobo", ...fields}, ... } for UI listing (RecipeIndex book)
function RecipeConfig.GetAll()
	local list = {}
	for key, data in RecipeConfig.Recipes do
		local entry = table.clone(data)
		entry.Key = key
		table.insert(list, entry)
	end
	return list
end

return RecipeConfig
