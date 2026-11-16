local short_tasks = dofile("mods/lep_progress/src/short_tasks.lua")

local function first()
	return 1
end

local function provider(text)
	return function(player_name)
		return {
			text = text .. " for " .. player_name,
			task = "t1",
			level = 2,
			check = function(input)
				return input == "42"
			end,
		}
	end
end

describe("lep_progress short tasks", function()
	it("has nothing without providers", function()
		assert.is_nil(short_tasks.new():pick("anna", first))
	end)

	it("returns the task of a module with its id", function()
		local registry = short_tasks.new()
		registry:register("mod:a", provider("A"))
		local task = registry:pick("anna", first)
		assert.are.equal("mod:a", task.module)
		assert.are.equal("A for anna", task.text)
		assert.are.equal("t1", task.task)
		assert.are.equal(2, task.level)
		assert.is_true(task.check("42"))
		assert.is_false(task.check("41"))
	end)

	it("chooses the module at random", function()
		local registry = short_tasks.new()
		registry:register("mod:a", provider("A"))
		registry:register("mod:b", provider("B"))
		assert.are.same({ "mod:a", "mod:b" }, registry:ids())
		assert.are.equal("mod:b", registry:pick("anna", function() return 2 end).module)
		assert.are.equal("mod:a", registry:pick("anna", first).module)
	end)

	it("tries the other modules if one has nothing", function()
		local registry = short_tasks.new()
		registry:register("mod:empty", function() return nil end)
		registry:register("mod:b", provider("B"))
		assert.are.equal("mod:b", registry:pick("anna", first).module)
	end)

	it("skips providers that fail or return something unusable", function()
		local registry = short_tasks.new()
		registry:register("mod:broken", function() error("boom") end)
		registry:register("mod:wrong", function() return { text = "no check" } end)
		registry:register("mod:b", provider("B"))
		local errors = {}
		local task = registry:pick("anna", first, function(module_id)
			errors[#errors + 1] = module_id
		end)
		assert.are.equal("mod:b", task.module)
		assert.are.same({ "mod:broken", "mod:wrong" }, errors)
	end)

	it("returns nil if no module has a task", function()
		local registry = short_tasks.new()
		registry:register("mod:empty", function() return nil end)
		assert.is_nil(registry:pick("anna", first))
	end)

	it("accepts one provider per module", function()
		local registry = short_tasks.new()
		registry:register("mod:a", provider("A"))
		assert.has_error(function() registry:register("mod:a", provider("A")) end)
		assert.has_error(function() registry:register("", provider("A")) end)
		assert.has_error(function() registry:register("mod:b", "no function") end)
	end)
end)
