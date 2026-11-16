-- Protocols: append-only files in the world folder. Every LEP mod that
-- has to write down what happened uses this, so all protocols are kept
-- and deleted the same way. See the concept, section 12.

local modpath = core.get_modpath("lep_core")
local protocol = dofile(modpath .. "/src/protocol.lua")

local protocols = {}

local DIR = core.get_worldpath() .. "/lep_protocols"
local opened = {}
local listeners = {}

--- Registers a function(name, record) that is called after an entry was
-- written to any protocol. `name` is the name of the protocol, `record`
-- the table with a value per column. The bridge uses this to pass the
-- entries on to the backend.
function protocols.register_on_append(listener)
	assert(type(listener) == "function", "register_on_append: listener must be a function")
	listeners[#listeners + 1] = listener
end

local function path(name)
	return DIR .. "/" .. name .. ".tsv"
end

local function now()
	return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

--- Opens a protocol. Opening the same name twice returns the same object.
-- @param name Lower case word, also the file name.
-- @param columns List of column names. The time is added automatically.
--   By convention the first column is "account" with the account name,
--   never the display name.
-- @return Object with :append(record) and :read(filter, limit).
function protocols.open(name, columns)
	assert(protocol.is_valid_name(name), "protocol name must be a lower case word")
	if opened[name] then
		return opened[name]
	end
	protocol.check_columns(columns)
	core.mkdir(DIR)

	local object = {}

	--- Appends one entry. `record` is a table with a value per column.
	-- @return true  or  false, error message
	function object.append(_, record)
		local file, err = io.open(path(name), "a")
		if not file then
			core.log("error", "[lep_core] cannot write protocol " .. name .. ": "
				.. tostring(err))
			return false, err
		end
		file:write(protocol.encode(now(), columns, record), "\n")
		file:close()
		for _, listener in ipairs(listeners) do
			local ok, listener_err = pcall(listener, name, record)
			if not ok then
				core.log("error", "[lep_core] listener of protocol " .. name .. " failed: "
					.. tostring(listener_err))
			end
		end
		return true
	end

	--- Returns entries, oldest first, each a table with `time` and one
	-- text field per column.
	-- @param filter Optional function(record) returning true to keep it.
	-- @param limit Optional number: only the last `limit` matching entries.
	function object.read(_, filter, limit)
		local records = {}
		local file = io.open(path(name), "r")
		if not file then
			return records
		end
		for line in file:lines() do
			local record = protocol.decode(columns, line)
			if record and (not filter or filter(record)) then
				records[#records + 1] = record
			end
		end
		file:close()
		return protocol.tail(records, limit)
	end

	opened[name] = object
	return object
end

--- Deletes all protocols of this world. This is part of the yearly
-- closing.
-- @return Number of deleted files.
function protocols.clear_all()
	local count = 0
	for _, file_name in ipairs(core.get_dir_list(DIR, false)) do
		if file_name:match("%.tsv$") and os.remove(DIR .. "/" .. file_name) then
			count = count + 1
		end
	end
	core.log("action", "[lep_core] deleted " .. count .. " protocols")
	return count
end

return protocols
