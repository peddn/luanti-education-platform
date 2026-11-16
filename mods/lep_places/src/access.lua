-- Rules for the moves players make on their own: through a portal, an
-- exit or a command. Pure Lua, no engine calls.
--
-- Other mods register rules. A rule is a function(player_name,
-- from_place, to_place) that returns false and a message for the player
-- to refuse the move, and anything else to let it pass. Moves that
-- somebody else decides, for example a teacher at the desk, are not
-- asked.

local access = {}

local Rules = {}
Rules.__index = Rules

--- Creates an empty list of rules.
-- @param on_error Optional function(err) for rules that fail.
function access.new(on_error)
	return setmetatable({ _rules = {}, _on_error = on_error }, Rules)
end

--- Adds a rule.
function Rules:register(rule)
	assert(type(rule) == "function", "rule must be a function")
	self._rules[#self._rules + 1] = rule
end

--- Asks all rules. The first refusal counts.
-- @return true  or  false, message
function Rules:check(player_name, from_place, to_place)
	for _, rule in ipairs(self._rules) do
		local ok, allowed, message = pcall(rule, player_name, from_place, to_place)
		if not ok then
			-- A broken rule must not lock anybody in.
			if self._on_error then
				self._on_error(allowed)
			end
		elseif allowed == false then
			return false, type(message) == "string" and message or nil
		end
	end
	return true
end

return access
