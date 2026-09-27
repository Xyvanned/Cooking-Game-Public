-- Merchant dialog + shop config
local MerchantConfig = {}

MerchantConfig.RESTOCK_TIME = 60
MerchantConfig.TYPE_SPEED = 0.035
MerchantConfig.NPC_LINE_HOLD = 5
MerchantConfig.SHOP_TWEEN_TIME = 0.5

MerchantConfig.Stalls = {
	Construction = {
		StallPath = "Workspace.CookingMechanism.ConstructionStall",
		MerchantName = "Construction Merchant",
		ShopUI = "ConstructionUI",
		RestockLabel = "ConstructionRestocking",
		RestockTime = 120,
		Greeting = "Kamusta, Mabuhay! Ano ho ang maipaglilingkod ko?",
		BuyOption = "Nais ko pong bumili ng materyales",
		LeaveOption = "Wag muna ipagpatuloy",
		Farewell = "Salamat! Balik ho kayo",
	},
	Ingredient = {
		StallPath = "Workspace.CookingMechanism.IngredientStall",
		MerchantName = "Ingredient Merchant",
		ShopUI = "IngredientUI",
		RestockLabel = "IngredientRestocking",
		RestockTime = 60,
		Greeting = "Kamusta, Mabuhay! Ano ho ang maipaglilingkod ko?",
		BuyOption = "Nais ko pong bumili ng rekados",
		LeaveOption = "Wag muna ipagpatuloy",
		Farewell = "Salamat! Balik ho kayo",
	},
}

-- Cost (in Money) to buy ONE unit of a Container/Fridge ingredient from
-- the Ingredient Merchant once a player's own free stock of it runs out
-- (CookingConfig.ContainerItems/FridgeItems Stock, which starts every
-- ingredient at 2 - a SEPARATE number from this price list).
MerchantConfig.IngredientPrices = {
	WholeOnion   = 2,
	Garlic       = 2,
	WholeChicken = 15,
	SoySauce     = 2,
	Seasoning    = 5,
	Vinegar      = 2,
}

return MerchantConfig
