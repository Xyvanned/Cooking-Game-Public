-- Image IDs for UI referencing
local AssetRegistry = {}

-- Customer portrait IDs
-- Each entry: { Acquired = "imageId", Silhouette = "imageId" }
AssetRegistry.Customers = {
	-- Common
	Student1 = { Acquired = "", Silhouette = "" },
	Student2 = { Acquired = "", Silhouette = "" },
	Student3 = { Acquired = "", Silhouette = "" },
	Student4 = { Acquired = "", Silhouette = "" },
	Student5 = { Acquired = "", Silhouette = "" },
	Filipino1 = { Acquired = "", Silhouette = "" },
	Filipino2 = { Acquired = "", Silhouette = "" },
	Filipino3 = { Acquired = "", Silhouette = "" },
	Filipino4 = { Acquired = "", Silhouette = "" },
	Filipino5 = { Acquired = "", Silhouette = "" },
	Filipino6 = { Acquired = "", Silhouette = "" },
	Filipino7 = { Acquired = "", Silhouette = "" },
	-- Uncommon
	OfficeWorker1 = { Acquired = "", Silhouette = "" },
	OfficeWorker2 = { Acquired = "", Silhouette = "" },
	OfficeWorker3 = { Acquired = "", Silhouette = "" },
	OfficeWorker4 = { Acquired = "", Silhouette = "" },
	Tourist1 = { Acquired = "", Silhouette = "" },
	Tourist2 = { Acquired = "", Silhouette = "" },
	-- Rare
	Nurse1 = { Acquired = "", Silhouette = "" },
	Nurse2 = { Acquired = "", Silhouette = "" },
	Engineer1 = { Acquired = "", Silhouette = "" },
	Engineer2 = { Acquired = "", Silhouette = "" },
	Teacher1 = { Acquired = "", Silhouette = "" },
	Teacher2 = { Acquired = "", Silhouette = "" },
	Businessman1 = { Acquired = "", Silhouette = "" },
	Businessman2 = { Acquired = "", Silhouette = "" },
	-- Epic
	Musician1 = { Acquired = "", Silhouette = "" },
	Musician2 = { Acquired = "", Silhouette = "" },
	Dancer1 = { Acquired = "", Silhouette = "" },
	Dancer2 = { Acquired = "", Silhouette = "" },
	Artist1 = { Acquired = "", Silhouette = "" },
	Artist2 = { Acquired = "", Silhouette = "" },
	Athlete1 = { Acquired = "", Silhouette = "" },
	Athlete2 = { Acquired = "", Silhouette = "" },
	-- Legendary
	["Dragon King"] = { Acquired = "", Silhouette = "" },
	["Dragon Queen"] = { Acquired = "", Silhouette = "" },
	["Elven King"] = { Acquired = "", Silhouette = "" },
	["Elven Queen"] = { Acquired = "", Silhouette = "" },
	["Human King"] = { Acquired = "", Silhouette = "" },
	["Human Queen"] = { Acquired = "", Silhouette = "" },
	["Merfolk King"] = { Acquired = "", Silhouette = "" },
	["Merfolk Queen"] = { Acquired = "", Silhouette = "" },
	-- Mythical
	Angel1 = { Acquired = "", Silhouette = "" },
	Angel2 = { Acquired = "", Silhouette = "" },
	Vampire = { Acquired = "", Silhouette = "" },
	Kid = { Acquired = "", Silhouette = "" },
	["Poor Man"] = { Acquired = "", Silhouette = "" },
	Celestial = { Acquired = "", Silhouette = "" },
	["Binary Coder"] = { Acquired = "", Silhouette = "" },
	Joker = { Acquired = "", Silhouette = "" },
	-- Secret
	Secret1 = { Acquired = "", Silhouette = "" },
	Secret2 = { Acquired = "", Silhouette = "" },
	Secret3 = { Acquired = "", Silhouette = "" },
	-- FoodCritic
	Critic1 = { Acquired = "", Silhouette = "" },
	Critic2 = { Acquired = "", Silhouette = "" },
}

-- Ingredient image IDs (keyed by item name)
AssetRegistry.Ingredients = {
	WholeOnion = "124479270707340",
	Garlic = "6213390108",
	WholeChicken = "12840842201",
	SoySauce = "92915841519236",
	Seasoning = "14148271441",
	ChoppedChicken = "136110254",
	ChoppedGarlic = "126142083384193",
	ChoppedOnion = "114207571090488",
	Spoon = "10974184307",
	EmptyPlate = "5152435991",
	KitchenKnife = "97424246",
	Pot = "4658918662",
	Vinegar = "73031483925637",
}

-- Status indicator icons (CookingArea.PopUp.CheckList ingredient
-- checklist). "Pending" [X] is authored directly on the Template's
-- Status ImageLabel; only the "Done" check mark is swapped in by script.
AssetRegistry.StatusIcons = {
	Done = "72382659",
}

-- Tutorial chef (StarterGui.Guide.Frame.Model) expressions. These are
-- already Image ids, used as rbxassetid:// directly (no rbxthumb).
AssetRegistry.ChefExpressions = {
	Default        = "109461522594994", -- normal face
	Excited        = "119475274258276", -- sparkling eyes
	LittleSurprise = "104616527742640", -- little surprised
	Happy          = "134141695925248", -- smiling
	HappySatisfied = "80648893558001",  -- smiling + happy hand gesture
}

-- Guide path beam texture (StarterGuide's pathfinding beam).
AssetRegistry.GuideBeamTexture = "10249261576"

AssetRegistry.Plating = {
	AdoboPlating = "99965577613888",

}

-- Recipe image IDs
-- Each entry: { Acquired = "imageId", Silhouette = "imageId" }
AssetRegistry.Recipes = {
	Adobo = { Acquired = "124878843220168", Silhouette = "134979196777402" },
}

-- Flag image IDs for the Recipe Index's "Learn More" card (RecipeIndex
-- ShowInfo.LearnMoreCard.Flag) - keyed by recipe name, one flag per
-- recipe (e.g. representing its country/cuisine of origin). Fill in as
-- IDs are provided; GetFlagImage returns "" for anything not set yet.
AssetRegistry.Flags = {
	Adobo = "",
}

-- Rarity gradient colors: CustomerConfig.RarityGradients is now the single
-- canonical source (matches the actually-authored in-game colors) - kept
-- here only so any existing caller of AssetRegistry.GetRarityGradient still
-- gets the same real colors, instead of maintaining a second table.
local CustomerConfig = require(script.Parent.CustomerConfig)

-- Every raw ID stored above (WholeOnion = "124479270707340", etc.) is a
-- DECAL id (the number on the asset's website page), not the underlying
-- Image id. Roblox Studio silently swaps a pasted Decal id for the real
-- Image id when you set an ImageLabel's Image property by hand in the
-- editor - but a SCRIPT setting the same raw id via rbxassetid:// gets
-- no such conversion, so the label just stays blank. rbxthumb:// asks
-- Roblox's thumbnail service to resolve a Decal id to its rendered
-- image directly, which works correctly from a script. Every getter
-- below routes through this so nothing has to special-case it.
local function toImageUri(id)
	if not id or id == "" then return "" end
	return "rbxthumb://type=Asset&w=420&h=420&id=" .. id
end

-- acquired: true = show Acquired image, false = show Silhouette
function AssetRegistry.GetCustomerImage(modelName, acquired)
	local entry = AssetRegistry.Customers[modelName]
	if not entry then return "" end
	return toImageUri(acquired and entry.Acquired or entry.Silhouette)
end

function AssetRegistry.GetIngredientImage(itemName)
	return toImageUri(AssetRegistry.Ingredients[itemName])
end

function AssetRegistry.GetRecipeImage(dishName, acquired)
	local entry = AssetRegistry.Recipes[dishName]
	if not entry then return "" end
	return toImageUri(acquired and entry.Acquired or entry.Silhouette)
end

function AssetRegistry.GetFlagImage(recipeName)
	return toImageUri(AssetRegistry.Flags[recipeName])
end

function AssetRegistry.GetPlatingImage(dishName)
	return toImageUri(AssetRegistry.Plating[dishName])
end

function AssetRegistry.GetStatusImage(statusName)
	return toImageUri(AssetRegistry.StatusIcons[statusName])
end

function AssetRegistry.GetChefExpression(name)
	local id = AssetRegistry.ChefExpressions[name] or AssetRegistry.ChefExpressions.Default
	return "rbxassetid://" .. id
end

function AssetRegistry.GetGuideBeamTexture()
	return "rbxassetid://" .. AssetRegistry.GuideBeamTexture
end

function AssetRegistry.GetRarityGradient(rarity)
	return CustomerConfig.GetRarityGradient(rarity)
end

return AssetRegistry
