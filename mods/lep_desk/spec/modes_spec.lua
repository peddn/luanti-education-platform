local modes = dofile("mods/lep_desk/src/modes.lua")

local W, L, R = modes.WILDERNESS, modes.LOBBY, modes.LEARNING

describe("lep_desk class modes", function()
	it("knows the three modes", function()
		assert.are.same({ "leisure", "self_study", "lesson" }, modes.ALL)
		assert.is_true(modes.is_mode("lesson"))
		assert.is_false(modes.is_mode("party"))
		assert.is_false(modes.is_mode(nil))
	end)

	it("opens the wilderness only for leisure", function()
		assert.is_true(modes.wilderness_open(modes.LEISURE))
		assert.is_false(modes.wilderness_open(modes.SELF_STUDY))
		assert.is_false(modes.wilderness_open(modes.LESSON))
	end)

	it("allows everything in leisure", function()
		for _, from in ipairs({ W, L, R }) do
			for _, to in ipairs({ W, L, R }) do
				assert.is_true(modes.allows(modes.LEISURE, from, to))
			end
		end
	end)

	it("closes only the wilderness in self-study", function()
		assert.are.same({ false, modes.WILDERNESS_CLOSED },
			{ modes.allows(modes.SELF_STUDY, L, W) })
		assert.are.same({ false, modes.WILDERNESS_CLOSED },
			{ modes.allows(modes.SELF_STUDY, R, W) })
		assert.is_true(modes.allows(modes.SELF_STUDY, L, R))
		assert.is_true(modes.allows(modes.SELF_STUDY, R, L))
		assert.is_true(modes.allows(modes.SELF_STUDY, W, L))
		assert.is_true(modes.allows(modes.SELF_STUDY, L, L))
	end)

	it("keeps students where the teacher put them in a lesson", function()
		assert.are.same({ false, modes.WILDERNESS_CLOSED },
			{ modes.allows(modes.LESSON, L, W) })
		assert.are.same({ false, modes.NO_ENTERING }, { modes.allows(modes.LESSON, L, R) })
		assert.are.same({ false, modes.NO_LEAVING }, { modes.allows(modes.LESSON, R, L) })
		assert.are.same({ false, modes.WILDERNESS_CLOSED },
			{ modes.allows(modes.LESSON, R, W) })
		assert.is_true(modes.allows(modes.LESSON, W, L))
		assert.is_true(modes.allows(modes.LESSON, L, L))
	end)

	it("rejects unknown modes", function()
		assert.has_error(function() modes.allows("party", L, W) end)
	end)
end)
