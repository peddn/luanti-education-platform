local session = dofile("mods/lep_math/src/session.lua")
local answer = dofile("mods/lep_math/src/answer.lua")
local layout = dofile("mods/lep_math/src/layout.lua")

local function typed(state, keys)
	local what
	for _, key in ipairs(keys) do
		state, what = session.press(state, key, answer.is_correct)
	end
	return state, what
end

describe("lep_math answers", function()
	it("accepts comma and point", function()
		assert.are.equal(3.5, answer.parse("3,5"))
		assert.are.equal(3.5, answer.parse("3.5"))
		assert.are.equal(12, answer.parse(" 12 "))
		assert.are.equal(-2, answer.parse("-2"))
		assert.are.equal(7, answer.parse("7,"))
	end)

	it("rejects what is not a number", function()
		for _, text in ipairs({ "", "-", ",", "1,2,3", "abc", "1-2", "--1", "1e5" }) do
			assert.is_nil(answer.parse(text), text)
		end
		assert.is_nil(answer.parse(nil))
	end)

	it("compares numbers, not texts", function()
		assert.is_true(answer.is_correct("12", 12))
		assert.is_true(answer.is_correct("012", 12))
		assert.is_true(answer.is_correct("3,50", 3.5))
		assert.is_true(answer.is_correct("0,3", 0.1 + 0.2))
		assert.is_false(answer.is_correct("13", 12))
		assert.is_false(answer.is_correct("", 0))
	end)

	it("writes numbers with a comma and without needless zeros", function()
		assert.are.equal("12", answer.format(12))
		assert.are.equal("3,5", answer.format(3.5))
		assert.are.equal("0,3", answer.format(0.1 + 0.2))
		assert.are.equal("100", answer.format(100))
		assert.are.equal("0", answer.format(0))
	end)
end)

describe("lep_math session", function()
	local TASK = { text = "7+5", answer = 12, type = "add_20_carry" }

	it("collects digits and deletes the last one", function()
		local state, what = typed(session.new(TASK), { "1", "3" })
		assert.are.equal("13", state.input)
		assert.are.equal(session.TYPED, what)
		state = typed(state, { session.KEY_BACK })
		assert.are.equal("1", state.input)
		local _, nothing = typed(session.new(TASK), { session.KEY_BACK })
		assert.are.equal(session.IGNORED, nothing)
	end)

	it("does not take more than fits the display", function()
		local keys = {}
		for index = 1, session.MAX_INPUT + 3 do
			keys[index] = "9"
		end
		local state, what = typed(session.new(TASK), keys)
		assert.are.equal(session.MAX_INPUT, #state.input)
		assert.are.equal(session.IGNORED, what)
		assert.is_true(session.MAX_INPUT < layout.COLUMNS)
	end)

	it("takes one comma after a digit and a minus only in front", function()
		local state = typed(session.new(TASK), { session.KEY_COMMA })
		assert.are.equal("", state.input)
		state = typed(state, { "3", session.KEY_COMMA, session.KEY_COMMA, "5", session.KEY_COMMA })
		assert.are.equal("3,5", state.input)
		state = typed(state, { session.KEY_MINUS })
		assert.are.equal("3,5", state.input)
		state = typed(session.new(TASK), { session.KEY_MINUS, session.KEY_MINUS, "2" })
		assert.are.equal("-2", state.input)
	end)

	it("ignores OK without a number and unknown keys", function()
		local state, what = typed(session.new(TASK), { session.KEY_OK })
		assert.are.equal(session.IGNORED, what)
		assert.are.equal(0, state.attempts)
		state, what = typed(state, { session.KEY_MINUS, session.KEY_OK })
		assert.are.equal(session.IGNORED, what)
		state, what = typed(state, { "x" })
		assert.are.equal(session.IGNORED, what)
		assert.are.equal(0, state.attempts)
	end)

	it("accepts the right answer at the first attempt", function()
		local state, what = typed(session.new(TASK), { "1", "2", session.KEY_OK })
		assert.are.equal(session.CORRECT, what)
		assert.are.equal(1, state.attempts)
	end)

	it("lets the player try again after one wrong answer", function()
		local state, what = typed(session.new(TASK), { "1", "3", session.KEY_OK })
		assert.are.equal(session.WRONG, what)
		assert.are.equal("", state.input)
		assert.are.equal(1, state.attempts)
		state, what = typed(state, { "1", "2", session.KEY_OK })
		assert.are.equal(session.CORRECT, what)
		assert.are.equal(2, state.attempts)
	end)

	it("reveals the solution after the second wrong answer", function()
		local state, what = typed(session.new(TASK),
			{ "1", "3", session.KEY_OK, "1", "1", session.KEY_OK })
		assert.are.equal(session.REVEALED, what)
		assert.are.equal(session.MAX_ATTEMPTS, state.attempts)
	end)

	it("does not change the state it was given", function()
		local state = session.new(TASK)
		typed(state, { "1", "2", session.KEY_OK })
		assert.are.same(session.new(TASK), state)
	end)
end)

describe("lep_math room layout", function()
	local geometry = {
		interior_min = { x = -4, y = 100, z = -3 },
		interior_max = { x = 4, y = 104, z = 3 },
		spawn = { x = 0, y = 100, z = -2 },
	}
	local positions = layout.positions(geometry)

	local min, max = geometry.interior_min, geometry.interior_max

	-- True for a position in a side wall, at a height inside the room.
	local function in_wall(pos, axis, value)
		local other = axis == "x" and "z" or "x"
		return pos[axis] == value and pos.y >= min.y and pos.y <= max.y
			and pos[other] >= min[other] and pos[other] <= max[other]
	end

	it("fits the size of the room", function()
		assert.are.equal(geometry.interior_max.x - geometry.interior_min.x + 1, layout.SIZE.x)
		assert.are.equal(geometry.interior_max.y - geometry.interior_min.y + 1, layout.SIZE.y)
		assert.are.equal(geometry.interior_max.z - geometry.interior_min.z + 1, layout.SIZE.z)
	end)

	it("sets the display into the front wall, the task above the input", function()
		assert.are.equal(layout.COLUMNS, #positions.task)
		assert.are.equal(layout.COLUMNS, #positions.input)
		for column = 1, layout.COLUMNS do
			local task, input = positions.task[column], positions.input[column]
			assert.is_true(in_wall(task, "z", max.z + 1) and in_wall(input, "z", max.z + 1))
			assert.are.equal(task.y - 1, input.y)
			assert.are.equal(task.x, input.x)
			if column > 1 then
				assert.are.equal(positions.task[column - 1].x + 1, task.x)
			end
		end
	end)

	it("sets the keypad upright into the right wall, 7 8 9 on top", function()
		local by_key = {}
		local taken = {}
		for _, entry in ipairs(positions.keys) do
			assert.is_true(in_wall(entry.pos, "x", max.x + 1))
			local id = entry.pos.y .. "," .. entry.pos.z
			assert.is_nil(taken[id])
			taken[id] = true
			by_key[entry.key] = entry.pos
		end
		assert.are.equal(14, #positions.keys)
		-- Facing the right wall, left is +z.
		assert.is_true(by_key["7"].z > by_key["8"].z and by_key["8"].z > by_key["9"].z)
		assert.is_true(by_key["7"].y > by_key["4"].y and by_key["4"].y > by_key["1"].y)
		assert.are.equal(by_key["1"].y - 1, by_key["0"].y)
		assert.are.equal(by_key["8"].z, by_key["0"].z)
		assert.is_true(by_key.back.z > by_key["0"].z and by_key["0"].z > by_key.ok.z)
		-- The lowest row is at floor level, the top row at eye level.
		assert.are.equal(min.y, by_key["0"].y)
		assert.are.equal(min.y + 3, by_key["7"].y)
		for _, entry in ipairs(positions.keys) do
			assert.is_true(entry.pos.z < max.z)
		end
	end)

	it("sets the exit into the left wall beside the place where the player arrives", function()
		assert.is_true(in_wall(positions.exit, "x", min.x - 1))
		assert.are.equal(geometry.spawn.z, positions.exit.z)
	end)

	it("pads display rows to the width of the display", function()
		assert.are.same({ "7", "+", "5", " ", " ", " ", " ", " ", " " }, layout.row("7+5", "left"))
		assert.are.same({ " ", " ", " ", " ", " ", " ", " ", "1", "2" }, layout.row("12", "right"))
		assert.are.equal(layout.COLUMNS, #layout.row("", "left"))
		assert.are.equal("9", layout.row("123456789", "right")[9])
	end)
end)
