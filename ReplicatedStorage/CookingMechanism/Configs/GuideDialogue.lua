-- Tutorial chef dialogue (StarterGui.Guide), one entry per guide step.
-- Edit freely: add/remove/reorder lines, change Face (any key of
-- AssetRegistry.ChefExpressions: Default, Excited, LittleSurprise,
-- Happy, HappySatisfied). The first time a step is reached ALL its lines
-- play in order; if the step comes back later, only its LAST line shows.
--
-- Beam = which GuideBeam attachment the path beam points to during that
-- step (nil = no beam).

local GuideDialogue = {}

GuideDialogue.TYPE_SPEED = 0.025 -- seconds per character
GuideDialogue.LINE_HOLD  = 2.6   -- pause after a line before the next one
GuideDialogue.DONE_HOLD  = 6     -- how long the final line stays up

-- Sound played when the chef switches to an expression (children of
-- ReplicatedStorage.CookingMechanism.Sounds.TutorialGuideSound). Faces
-- not listed (Default) play no sound. While one plays, the DialogueBlip
-- typing sound drops to half volume.
GuideDialogue.FaceSounds = {
	Excited        = "Excited",
	LittleSurprise = "LittleSurprised",
	Happy          = "Happy",
	HappySatisfied = "HappyAndSatisfied",
}
GuideDialogue.BLIP_SOUND = "DialogueBlip"

GuideDialogue.Steps = {
	welcome = {
		Beam = "Restaurant",
		{ Face = "Excited",        Text = "Oh, hello! Welcome to Cook!" },
		{ Face = "Happy",          Text = "I'll show you how to survive in this city!" },
		{ Face = "Default",        Text = "First, head inside your eatery." },
	},
	waitCustomer = {
		{ Face = "Default",        Text = "Customers will arrive any moment now. Get ready!" },
	},
	customer = {
		{ Face = "LittleSurprise", Text = "Looks like you just got your first customer!" },
		{ Face = "Default",        Text = "Take their order, and they'll find a seat." },
	},
	placePot = {
		Beam = "CookingArea",
		{ Face = "Excited",        Text = "Now, let's head into the kitchen and cook their food!" },
		{ Face = "Default",        Text = "Place the cooking pot on the stove. The checklist above it shows every ingredient you need!" },
	},
	fridge = {
		Beam = "FridgeArea",
		{ Face = "Happy",          Text = "Great! Now grab the meat from the fridge." },
	},
	container = {
		Beam = "ContainerArea",
		{ Face = "Default",        Text = "Then, grab the remaining ingredients from the dry storage." },
	},
	chopMeat = {
		Beam = "ChoppingArea",
		{ Face = "Excited",        Text = "Let's head to the chopping station!" },
		{ Face = "Default",        Text = "Chop the meat first, then place it in the pot." },
	},
	addMeat = {
		Beam = "CookingArea",
		{ Face = "Happy",          Text = "Nice cut! Now place the meat in the pot." },
	},
	chopRest = {
		Beam = "ChoppingArea",
		{ Face = "Happy",          Text = "Good job! Now chop the onion and garlic." },
	},
	addRest = {
		Beam = "CookingArea",
		{ Face = "Default",        Text = "Add the remaining ingredients to the pot." },
	},
	startFire = {
		Beam = "CookingArea",
		{ Face = "Excited",        Text = "Everything's ready! Turn on the stove and wait for it to finish cooking." },
	},
	cooking = {
		{ Face = "Happy",          Text = "Smells delicious... just a little longer!" },
	},
	kitchenIsle = {
		Beam = "KitchenIsle",
		{ Face = "LittleSurprise", Text = "Your food is ready!" },
		{ Face = "Default",        Text = "Pick up the dish from the serving station and deliver it to your customer." },
	},
	deliver = {
		Beam = "DiningArea",
		{ Face = "Excited",        Text = "Bring it to the glowing table!" },
	},
	eating = {
		{ Face = "HappySatisfied", Text = "Your customer is enjoying the meal!" },
	},
	usedPlate = {
		Beam = "DiningArea",
		{ Face = "LittleSurprise", Text = "They're done! Collect the empty plate from the table." },
	},
	wash = {
		Beam = "WashArea",
		{ Face = "Default",        Text = "Take it to the sink and wash it so you can use it again." },
	},
	done = {
		{ Face = "HappySatisfied", Text = "And that's it! You're ready to run your eatery. Good luck, chef!" },
	},
}

return GuideDialogue
