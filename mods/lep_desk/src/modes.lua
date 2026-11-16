-- The class modes. Pure Lua, no engine calls.
--
-- A mode says where students may go on their own:
--   leisure     everything is open
--   self_study  the wilderness is closed; lobby and learning rooms are open
--   lesson      the wilderness is closed, and students enter and leave
--               learning rooms only when the teacher moves them
-- Teachers are not bound by the mode, and what a teacher does to a
-- student is not either.

local modes = {}

modes.LEISURE = "leisure"
modes.SELF_STUDY = "self_study"
modes.LESSON = "lesson"

modes.ALL = { modes.LEISURE, modes.SELF_STUDY, modes.LESSON }

-- Kinds of places, as the rules see them.
modes.WILDERNESS = "wilderness"
modes.LOBBY = "lobby"
modes.LEARNING = "learning"

-- Why a move is refused.
modes.WILDERNESS_CLOSED = "wilderness_closed"
modes.NO_ENTERING = "no_entering"
modes.NO_LEAVING = "no_leaving"

--- Returns true if `mode` is one of the three modes.
function modes.is_mode(mode)
	return mode == modes.LEISURE or mode == modes.SELF_STUDY or mode == modes.LESSON
end

--- Returns true if students may be in the wilderness in this mode.
function modes.wilderness_open(mode)
	return mode == modes.LEISURE
end

--- Decides whether a student may go from one kind of place to another on
-- their own.
-- @return true  or  false, reason (one of the constants above)
function modes.allows(mode, from_kind, to_kind)
	assert(modes.is_mode(mode), "unknown mode '" .. tostring(mode) .. "'")
	if mode == modes.LEISURE then
		return true
	end
	if to_kind == modes.WILDERNESS then
		return false, modes.WILDERNESS_CLOSED
	end
	if mode == modes.LESSON then
		if from_kind == modes.LEARNING then
			return false, modes.NO_LEAVING
		end
		if to_kind == modes.LEARNING then
			return false, modes.NO_ENTERING
		end
	end
	return true
end

return modes
