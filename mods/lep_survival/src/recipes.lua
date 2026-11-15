-- Recipes of Minetest Game that are removed because a third-party mod
-- offers a better fitting item. Pure Lua, no engine calls.

local recipes = {}

-- Protector has its own doors, trapdoor and chest. They follow the
-- protected area: everyone who is a member there can use them. The items
-- of Minetest Game belong to exactly one player. Offering both would
-- confuse, so only the ones of Protector can be crafted.
recipes.REPLACED_BY = {
	protector = {
		"doors:door_steel",
		"doors:trapdoor_steel",
		"default:chest_locked",
	},
}

--- Returns the items whose recipes are removed, given a function that
-- tells whether a mod is loaded. Nothing is removed for a missing mod, so
-- the world never ends up without lockable doors and chests.
function recipes.to_remove(is_mod_loaded)
	local list = {}
	local names = {}
	for mod_name in pairs(recipes.REPLACED_BY) do
		names[#names + 1] = mod_name
	end
	table.sort(names)
	for _, mod_name in ipairs(names) do
		if is_mod_loaded(mod_name) then
			for _, item in ipairs(recipes.REPLACED_BY[mod_name]) do
				list[#list + 1] = item
			end
		end
	end
	return list
end

return recipes
