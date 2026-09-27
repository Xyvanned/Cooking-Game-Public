-- Recipe definitions, chop map, timings
local CookingConfig = {}

CookingConfig.RecipeConfig = require(script.Parent.RecipeConfig)

-- Which raw ingredients have a chopped state
-- key = raw asset name, value = chopped asset name
CookingConfig.ChoppableMap = {
	WholeOnion   = "ChoppedOnion",
	Garlic       = "ChoppedGarlic",
	WholeChicken = "ChoppedChicken",
}

-- Seconds to finish chopping each ingredient
CookingConfig.ChopTime = {
	WholeOnion   = 4,
	Garlic       = 3,
	WholeChicken = 6,
}

-- Tool equip folders in PlayerEquips per ingredient name
CookingConfig.EquipFolder = {
	WholeOnion       = "IngredientsEquips",
	Garlic           = "IngredientsEquips",
	WholeChicken     = "IngredientsEquips",
	SoySauce         = "SpicesEquips",
	Seasoning        = "SpicesEquips",
	Vinegar          = "SpicesEquips",
	ChoppedChicken   = "IngredientsChoppedEquips",
	ChoppedGarlic    = "IngredientsChoppedEquips",
	ChoppedOnion     = "IngredientsChoppedEquips",
	AdoboPlating     = "PlatingContainer",
	EmptyPlate       = "ToolEquips",
}

-- Tool name inside its folder
CookingConfig.ToolName = {
	WholeOnion       = "OnionEquips",
	Garlic           = "GarlicEquips",
	WholeChicken     = "ChickenEquips",
	SoySauce         = "SoySauceEquips",
	Seasoning        = "SeasoningEquips",
	Vinegar          = "VinegarEquips",
	ChoppedChicken   = "ChoppedChickenEquips",
	ChoppedGarlic    = "ChoppedGarlicEquips",
	ChoppedOnion     = "ChoppedOnionEquips",
	AdoboPlating     = "Adobo",
	EmptyPlate       = "EmptyPlate",
}

-- Ingredients that physically spawn a model inside the pot when added
-- (liquids/spices are consumed without a visible model)
CookingConfig.SpawnsInPot = {
	ChoppedChicken = true,
	ChoppedGarlic  = true,
	ChoppedOnion   = true,
	SoySauce       = false,
	Seasoning      = false,
	Vinegar        = false,
}

-- Items available in the container. Finite starting stock per player -
-- every ingredient starts at 2 - once a player runs one out,
-- EquipIngredient refuses with "OutOfStock" and they need to buy more
-- from the Ingredient Merchant (see MerchantConfig.IngredientPrices +
-- Remotes.PurchaseIngredient - prices are a SEPARATE list from this
-- starting stock, not the same numbers).
-- value = display name shown in IngredientStorage UI
CookingConfig.ContainerItems = {
	{ Name = "WholeOnion",   Display = "Whole Onion",   Stock = 2 },
	{ Name = "Garlic",       Display = "Garlic",        Stock = 2 },
	{ Name = "SoySauce",     Display = "Soy Sauce",     Stock = 2 },
	{ Name = "Seasoning",    Display = "Seasoning",     Stock = 2 },
	{ Name = "Vinegar",      Display = "Vinegar",       Stock = 2 },
}

-- Frozen/refrigerated items available in the Fridge. Finite starting
-- stock per player, same OutOfStock/Merchant rule as ContainerItems
-- above - value = display name shown in FridgeStorage UI. WholeChicken
-- moved here from ContainerItems since it's a frozen meat, not a shelf
-- item.
CookingConfig.FridgeItems = {
	{ Name = "WholeChicken", Display = "Whole Chicken", Stock = 2 },
}

-- Hotbar slot count
CookingConfig.HOTBAR_SLOTS = 6

-- Detector overlap distance (studs, checked via HRP)
CookingConfig.DETECT_DISTANCE = 6

return CookingConfig
