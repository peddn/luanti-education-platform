local events = dofile("mods/lep_core/src/events.lua")

describe("lep_core events", function()
	it("calls a registered callback with the emitted arguments", function()
		local dispatcher = events.new()
		local received
		dispatcher:register("task_solved", function(player, level)
			received = { player, level }
		end)

		dispatcher:emit("task_solved", "lustiger_loewe", 2)

		assert.are.same({ "lustiger_loewe", 2 }, received)
	end)

	it("calls callbacks in registration order", function()
		local dispatcher = events.new()
		local order = {}
		dispatcher:register("e", function() order[#order + 1] = "first" end)
		dispatcher:register("e", function() order[#order + 1] = "second" end)

		dispatcher:emit("e")

		assert.are.same({ "first", "second" }, order)
	end)

	it("keeps events apart", function()
		local dispatcher = events.new()
		local called = false
		dispatcher:register("a", function() called = true end)

		dispatcher:emit("b")

		assert.is_false(called)
	end)

	it("returns zero counts for an event without callbacks", function()
		local dispatcher = events.new()
		local succeeded, failed = dispatcher:emit("nobody_listens")
		assert.are.equal(0, succeeded)
		assert.are.equal(0, failed)
	end)

	it("continues after a failing callback and reports it", function()
		local errors = {}
		local dispatcher = events.new(function(event_name, err)
			errors[#errors + 1] = { event_name, tostring(err) }
		end)
		local reached = false
		dispatcher:register("e", function() error("boom") end)
		dispatcher:register("e", function() reached = true end)

		local succeeded, failed = dispatcher:emit("e")

		assert.is_true(reached)
		assert.are.equal(1, succeeded)
		assert.are.equal(1, failed)
		assert.are.equal(1, #errors)
		assert.are.equal("e", errors[1][1])
		assert.is_truthy(errors[1][2]:find("boom", 1, true))
	end)

	it("ignores errors when no error handler is given", function()
		local dispatcher = events.new()
		dispatcher:register("e", function() error("boom") end)
		assert.has_no.errors(function() dispatcher:emit("e") end)
	end)

	it("runs callbacks registered during emit only on the next emit", function()
		local dispatcher = events.new()
		local late_calls = 0
		dispatcher:register("e", function()
			dispatcher:register("e", function() late_calls = late_calls + 1 end)
		end)

		dispatcher:emit("e")
		assert.are.equal(0, late_calls)

		dispatcher:emit("e")
		assert.are.equal(1, late_calls)
	end)

	it("counts registered callbacks", function()
		local dispatcher = events.new()
		assert.are.equal(0, dispatcher:count("e"))
		dispatcher:register("e", function() end)
		dispatcher:register("e", function() end)
		assert.are.equal(2, dispatcher:count("e"))
	end)

	it("builds register functions for a fixed event", function()
		local dispatcher = events.new()
		local register_on_task_solved = dispatcher:registrar("task_solved")
		local called = false
		register_on_task_solved(function() called = true end)

		dispatcher:emit("task_solved")

		assert.is_true(called)
	end)

	it("keeps dispatchers independent", function()
		local a, b = events.new(), events.new()
		a:register("e", function() end)
		assert.are.equal(0, b:count("e"))
	end)

	it("rejects invalid arguments", function()
		local dispatcher = events.new()
		assert.has_error(function() dispatcher:register("", function() end) end)
		assert.has_error(function() dispatcher:register("e", "not a function") end)
		assert.has_error(function() dispatcher:emit(nil) end)
		assert.has_error(function() events.new("not a function") end)
	end)
end)
