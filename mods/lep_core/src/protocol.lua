-- Line format of the protocols. Pure Lua, no engine calls.
--
-- A protocol is a text file that is only appended to. One line is one
-- entry: the time, then the columns of that protocol, separated by tabs.
-- Tabs, line breaks and backslashes inside a value are escaped, so every
-- entry stays on one line.

local protocol = {}

local ESCAPES = { ["\\"] = "\\\\", ["\t"] = "\\t", ["\n"] = "\\n", ["\r"] = "" }
local UNESCAPES = { ["\\"] = "\\", t = "\t", n = "\n" }

--- Returns a value as text that fits into one column.
function protocol.escape(value)
	if value == nil then
		return ""
	end
	return (tostring(value):gsub("[\\\t\n\r]", ESCAPES))
end

--- Reverses protocol.escape.
function protocol.unescape(text)
	return (text:gsub("\\(.)", function(char)
		return UNESCAPES[char] or char
	end))
end

--- Returns true if the name can be used for a protocol and its file.
function protocol.is_valid_name(name)
	return type(name) == "string" and name:match("^[a-z][a-z0-9_]*$") ~= nil
end

--- Checks a list of column names.
function protocol.check_columns(columns)
	assert(type(columns) == "table" and #columns >= 1, "columns must be a non-empty list")
	local seen = { time = true }
	for _, column in ipairs(columns) do
		assert(type(column) == "string" and column:match("^[a-z][a-z0-9_]*$"),
			"column names must be lower case words")
		assert(not seen[column], "column '" .. column .. "' is used twice or reserved")
		seen[column] = true
	end
end

--- Returns the line for one entry, without a line break.
-- @param time Text for the time column.
-- @param columns List of column names.
-- @param record Table with a value per column. Missing values are empty.
function protocol.encode(time, columns, record)
	local values = { protocol.escape(time) }
	for index, column in ipairs(columns) do
		values[index + 1] = protocol.escape(record[column])
	end
	return table.concat(values, "\t")
end

--- Returns the entry of one line as a table with `time` and one field per
-- column, all as text. Returns nil for an empty line.
function protocol.decode(columns, line)
	if type(line) ~= "string" or line == "" then
		return nil
	end
	local record = {}
	local index = 0
	for value in (line .. "\t"):gmatch("(.-)\t") do
		local column = index == 0 and "time" or columns[index]
		if column then
			record[column] = protocol.unescape(value)
		end
		index = index + 1
	end
	for _, column in ipairs(columns) do
		record[column] = record[column] or ""
	end
	return record
end

--- Returns true if one line is an entry of an account: one of the
-- given columns holds exactly its name.
-- @param positions List of column numbers, 1 for the first column after
--   the time.
function protocol.concerns(line, account, positions)
	if type(line) ~= "string" or line == "" then
		return false
	end
	local values = {}
	for value in (line .. "\t"):gmatch("(.-)\t") do
		values[#values + 1] = value
	end
	for _, position in ipairs(positions) do
		local value = values[position + 1]
		if value and protocol.unescape(value) == account then
			return true
		end
	end
	return false
end

--- Returns the lines that are no entries of an account, and how many
-- were left out. See protocol.concerns.
function protocol.without_account(lines, account, positions)
	local kept, removed = {}, 0
	for _, line in ipairs(lines) do
		if protocol.concerns(line, account, positions) then
			removed = removed + 1
		else
			kept[#kept + 1] = line
		end
	end
	return kept, removed
end

--- Returns the numbers of the named columns, for protocol.concerns.
function protocol.positions(columns, names)
	local positions = {}
	for _, wanted in ipairs(names) do
		for index, column in ipairs(columns) do
			if column == wanted then
				positions[#positions + 1] = index
			end
		end
	end
	return positions
end

--- Returns the last `limit` entries of a list, oldest first.
function protocol.tail(records, limit)
	if not limit or limit >= #records then
		return records
	end
	local result = {}
	for index = math.max(1, #records - limit + 1), #records do
		result[#result + 1] = records[index]
	end
	return result
end

return protocol
