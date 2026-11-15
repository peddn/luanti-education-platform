local loader = dofile("mods/lep_core/src/loader.lua")

describe("lep_core loader", function()
	local base = "mods/lep_core/spec/fixtures"

	it("loads a file and returns its value", function()
		local load = loader.new(base)
		local value = load("answer")
		assert.are.equal(42, value.answer)
	end)

	it("loads a file only once", function()
		local load = loader.new(base)
		local first = load("answer")
		local second = load("answer")
		assert.are.equal(first, second)
	end)

	it("keeps separate caches per loader", function()
		local a = loader.new(base)("answer")
		local b = loader.new(base)("answer")
		assert.are_not.equal(a, b)
	end)

	it("caches files that return false", function()
		local load = loader.new(base)
		assert.is_false(load("returns_false"))
		assert.is_false(load("returns_false"))
	end)

	it("fails for a missing file", function()
		local load = loader.new(base)
		assert.has_error(function() load("does_not_exist") end)
	end)

	it("rejects names that leave the mod directory", function()
		local load = loader.new(base)
		assert.has_error(function() load("../src/events") end)
	end)

	it("rejects an empty base path", function()
		assert.has_error(function() loader.new("") end)
	end)
end)
