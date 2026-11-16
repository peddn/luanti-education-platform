-- Reading and comparing answers. Pure Lua, no engine calls.

local answer = {}

--- Reads what a player typed. "3,5" and "3.5" are both accepted.
-- @return the number, or nil if the text is not a number
function answer.parse(text)
	if type(text) ~= "string" then
		return nil
	end
	text = text:gsub("%s", ""):gsub(",", ".")
	if not text:match("^%-?%d+%.?%d*$") then
		return nil
	end
	return tonumber(text)
end

--- Returns true if the typed text is the expected number.
function answer.is_correct(text, expected)
	local number = answer.parse(text)
	return number ~= nil and math.abs(number - expected) < 0.0001
end

--- Returns a number the way the display shows it: with a decimal comma
-- and without needless zeros.
function answer.format(number)
	local text = string.format("%.2f", number):gsub("0+$", ""):gsub("%.$", "")
	return (text:gsub("%.", ","))
end

return answer
