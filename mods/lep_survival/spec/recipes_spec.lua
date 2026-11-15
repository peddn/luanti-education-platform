local recipes = dofile("mods/lep_survival/src/recipes.lua")

describe("lep_survival recipes", function()
	it("removes nothing when the replacing mod is missing", function()
		assert.are.same({}, recipes.to_remove(function() return false end))
	end)

	it("removes the lockable items of Minetest Game when Protector is loaded", function()
		local list = recipes.to_remove(function(name) return name == "protector" end)
		assert.are.same(
			{ "doors:door_steel", "doors:trapdoor_steel", "default:chest_locked" }, list)
	end)

	it("lists every item only once", function()
		local seen = {}
		for _, item in ipairs(recipes.to_remove(function() return true end)) do
			assert.is_nil(seen[item])
			seen[item] = true
			assert.is_truthy(item:match("^[a-z0-9_]+:[a-z0-9_]+$"))
		end
	end)
end)
