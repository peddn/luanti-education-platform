local tabs = dofile("mods/lep_desk/src/tabs.lua")

local function tab(privilege)
	return { title = "Tab", privilege = privilege, build = function() end,
		on_fields = function() end }
end

describe("lep_desk tabs", function()
	it("keeps tabs in the order they were registered", function()
		local registry = tabs.new()
		registry:register("b:second", tab("p"))
		registry:register("a:first", tab("p"))
		local list = registry:allowed(function() return true end)
		assert.are.equal("b:second", list[1].id)
		assert.are.equal("a:first", list[2].id)
		assert.are.equal(2, tabs.index_of(list, "a:first"))
		assert.is_nil(tabs.index_of(list, "unknown"))
	end)

	it("shows a teacher only the tabs they may use", function()
		local registry = tabs.new()
		registry:register("a", tab("web"))
		registry:register("b", tab("other"))
		local list = registry:allowed(function(privilege) return privilege == "web" end)
		assert.are.equal(1, #list)
		assert.are.equal("a", list[1].id)
		assert.are.same({}, registry:allowed(function() return false end))
	end)

	it("refuses tabs that are not complete", function()
		local registry = tabs.new()
		registry:register("a", tab("p"))
		assert.has_error(function() registry:register("a", tab("p")) end)
		assert.has_error(function() registry:register("", tab("p")) end)
		for _, missing in ipairs({ "title", "privilege", "build", "on_fields" }) do
			local def = tab("p")
			def[missing] = nil
			assert.has_error(function() registry:register("x_" .. missing, def) end)
		end
	end)
end)
