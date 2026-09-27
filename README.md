# Cooking Game – public showcase

Client-side scripts and shared configs from **Cook!**, a Roblox restaurant tycoon built in **Luau**: take orders, cook real recipes (starting with Chicken Adobo), serve customers and grow your eatery.

This is a **filtered** copy for sharing. It only contains code that already ships to players' devices:

| Folder | What's here |
|---|---|
| `StarterPlayer/StarterPlayerScripts/CookingMechanism/` | Gameplay UI and controllers: restaurant flow, inventory/hotbar, skill tree, merchant, intro sequence, camera modes |
| `…/Modules/TutorialGuide.lua` + `StarterGuide.client.lua` | Onboarding: spotlight tutorial, chef NPC dialogue with expressions and voice, pathfinding guide beam |
| `ReplicatedStorage/CookingMechanism/Configs/` | Data-driven configs: recipes, customers, skills, merchant, dialogue, asset IDs |
| `StarterGui/` | UI helper scripts |

Server-side logic (gameplay authority, data persistence and game protection) is kept private.

Extensions follow the Rojo convention: `.client.lua` = LocalScript, `.lua` = ModuleScript.

© Xyvan. All rights reserved. Shared for viewing only.
