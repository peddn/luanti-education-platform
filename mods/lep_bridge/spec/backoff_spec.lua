local backoff = dofile("mods/lep_bridge/src/backoff.lua")

describe("lep_bridge backoff", function()
	it("does not wait without a failure", function()
		assert.are.equal(0, backoff.delay(0))
		assert.are.equal(0, backoff.delay(nil))
	end)

	it("waits longer after every failure", function()
		local last = 0
		for failures = 1, #backoff.STEPS do
			local delay = backoff.delay(failures)
			assert.is_true(delay > last)
			last = delay
		end
		assert.are.equal(1, backoff.delay(1))
	end)

	it("never waits longer than a minute", function()
		assert.are.equal(60, backoff.delay(#backoff.STEPS))
		assert.are.equal(60, backoff.delay(1000))
	end)
end)
