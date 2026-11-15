-- Removes the recipes listed in src/recipes.lua.

local load = lep_core.loader("lep_survival")
local recipes = load("src/recipes")

local function is_mod_loaded(name)
	return core.get_modpath(name) ~= nil
end

for _, item in ipairs(recipes.to_remove(is_mod_loaded)) do
	if core.registered_items[item] then
		core.clear_craft({ output = item })
		core.log("action", "[lep_survival] removed the recipes for " .. item)
	end
end
