-- Shared exclusivity manager: only one major UI panel should be open
-- at a time (Storage, Fridge Storage, Customer, Settings, Recipe Index,
-- Skill Tree, etc.). Panels register their own close function once at
-- setup, then call CloseAllExcept(theirOwnName) right before opening.
-- Works across separate scripts (RestaurantController, 
-- SkillTreeController) since it's one shared module.

local PanelManager = {}

local closeFns = {} -- name -> function

function PanelManager.Register(name, closeFn)
	closeFns[name] = closeFn
end

function PanelManager.CloseAllExcept(exceptName)
	for name, fn in closeFns do
		if name ~= exceptName then
			local ok, err = pcall(fn)
			if not ok then
				warn("PanelManager: error closing " .. name .. ": " .. tostring(err))
			end
		end
	end
end

return PanelManager
