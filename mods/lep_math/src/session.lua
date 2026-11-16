-- What happens between a task and its answer. Pure Lua, no engine calls.
--
-- A session belongs to one player. It holds the current task, what the
-- player has typed so far and how often they were wrong. The room with
-- its keypad and, later, the window of the task chest both drive it.

local session = {}

-- How often a player may answer before the solution is shown.
session.MAX_ATTEMPTS = 2
-- How many characters fit into the input row of the display.
session.MAX_INPUT = 7

-- Keys of the keypad besides the digits "0" to "9".
session.KEY_BACK = "back"
session.KEY_OK = "ok"
session.KEY_COMMA = "comma"
session.KEY_MINUS = "minus"

-- What a key press led to.
session.TYPED = "typed"       -- the input changed
session.IGNORED = "ignored"   -- nothing happened
session.CORRECT = "correct"   -- right answer: the task is finished
session.WRONG = "wrong"       -- wrong answer: the player may try again
session.REVEALED = "revealed" -- wrong too often: the task is finished

--- Starts a session with a task (see src/tasks.lua).
function session.new(task)
	return { task = task, input = "", attempts = 0 }
end

local function with_input(state, input)
	return { task = state.task, input = input, attempts = state.attempts }
end

--- Handles a key.
-- @param key "0" to "9" or one of the KEY_ constants.
-- @param is_correct Function(text, expected) deciding whether an answer is
--   right.
-- @return new state, what happened (one of the constants above)
function session.press(state, key, is_correct)
	local input = state.input

	if type(key) == "string" and key:match("^%d$") then
		if #input >= session.MAX_INPUT then
			return state, session.IGNORED
		end
		return with_input(state, input .. key), session.TYPED
	elseif key == session.KEY_COMMA then
		if #input >= session.MAX_INPUT or input:find(",", 1, true)
				or not input:match("%d$") then
			return state, session.IGNORED
		end
		return with_input(state, input .. ","), session.TYPED
	elseif key == session.KEY_MINUS then
		if input ~= "" then
			return state, session.IGNORED
		end
		return with_input(state, "-"), session.TYPED
	elseif key == session.KEY_BACK then
		if input == "" then
			return state, session.IGNORED
		end
		return with_input(state, input:sub(1, -2)), session.TYPED
	elseif key == session.KEY_OK then
		if not input:match("%d") then
			return state, session.IGNORED
		end
		local attempts = state.attempts + 1
		if is_correct(input, state.task.answer) then
			return { task = state.task, input = input, attempts = attempts }, session.CORRECT
		elseif attempts >= session.MAX_ATTEMPTS then
			return { task = state.task, input = "", attempts = attempts }, session.REVEALED
		end
		return { task = state.task, input = "", attempts = attempts }, session.WRONG
	end
	return state, session.IGNORED
end

return session
