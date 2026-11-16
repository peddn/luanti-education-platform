local daytime = dofile("mods/lep_desk/src/daytime.lua")

describe("lep_desk daytime", function()
	it("starts with a running time", function()
		assert.are.same({ mode = "running", speed = 72 }, daytime.normalize(nil))
		assert.are.same({ mode = "running", speed = 72 }, daytime.normalize("broken"))
		assert.are.same({ mode = "running", speed = 72 },
			daytime.normalize({ mode = "dusk", speed = -5 }))
		assert.are.same({ mode = "night", speed = 30 },
			daytime.normalize({ mode = "night", speed = 30 }))
	end)

	it("stops the time at noon for always day", function()
		local state, steps = daytime.set_mode(daytime.normalize(nil), daytime.DAY, 72)
		assert.are.same({ mode = "day", speed = 72 }, state)
		assert.are.same({
			{ op = "set_time", time = 0.5 },
			{ op = "set_speed", speed = 0 },
		}, steps)
	end)

	it("stops the time at midnight for always night", function()
		local state, steps = daytime.set_mode(daytime.normalize(nil), daytime.NIGHT, 72)
		assert.are.equal("night", state.mode)
		assert.are.same({ op = "set_time", time = 0 }, steps[1])
		assert.are.same({ op = "set_speed", speed = 0 }, steps[2])
	end)

	it("remembers the speed the world had and gives it back", function()
		local state = daytime.set_mode(daytime.normalize(nil), daytime.DAY, 30)
		assert.are.equal(30, state.speed)
		-- While the time stands still, the current speed is 0: keep 30.
		state = daytime.set_mode(state, daytime.NIGHT, 0)
		assert.are.equal(30, state.speed)
		local steps
		state, steps = daytime.set_mode(state, daytime.RUNNING, 0)
		assert.are.same({ mode = "running", speed = 30 }, state)
		assert.are.same({ { op = "set_speed", speed = 30 } }, steps)
	end)

	it("falls back to the default speed if the world stood still before", function()
		local state = daytime.set_mode(daytime.normalize(nil), daytime.DAY, 0)
		assert.are.equal(72, state.speed)
	end)

	it("sets a time without touching the speed while the time runs", function()
		local state, steps = daytime.set_time(daytime.normalize(nil), "evening")
		assert.are.equal("running", state.mode)
		assert.are.same({ { op = "set_time", time = 0.75 } }, steps)
		assert.are.equal(0.25, daytime.TIMES.morning)
		assert.are.equal(0.5, daytime.TIMES.noon)
		assert.are.equal(0, daytime.TIMES.night)
	end)

	it("lets the time run again when a time is set while it stood still", function()
		local state = daytime.set_mode(daytime.normalize(nil), daytime.DAY, 50)
		local steps
		state, steps = daytime.set_time(state, "night")
		assert.are.same({ mode = "running", speed = 50 }, state)
		assert.are.same({
			{ op = "set_time", time = 0 },
			{ op = "set_speed", speed = 50 },
		}, steps)
	end)

	it("restores a mode after a restart", function()
		assert.are.same({}, daytime.restore(daytime.normalize(nil)))
		assert.are.same({
			{ op = "set_time", time = 0 },
			{ op = "set_speed", speed = 0 },
		}, daytime.restore({ mode = "night", speed = 72 }))
	end)

	it("does not change the state it was given", function()
		local state = daytime.normalize(nil)
		daytime.set_mode(state, daytime.DAY, 10)
		daytime.set_time(state, "noon")
		assert.are.same({ mode = "running", speed = 72 }, state)
	end)

	it("rejects unknown modes and times", function()
		assert.has_error(function() daytime.set_mode(daytime.normalize(nil), "dusk", 72) end)
		assert.has_error(function() daytime.set_time(daytime.normalize(nil), "tea time") end)
	end)
end)
