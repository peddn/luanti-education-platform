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

local clear_listeners = {}

--- Registers a function() that is called after all protocols were
-- deleted, at the end of the year. A mod that keeps data of the year
-- somewhere else deletes it then.
function protocols.register_on_clear(listener)
	assert(type(listener) == "function", "register_on_clear: listener must be a function")
	clear_listeners[#clear_listeners + 1] = listener
end

--- Deletes all protocols of this world: every file in the folder of the
-- protocols, also of protocols no mod has opened this time. This is the
-- end of the year, see the concept, section 12. Protocols stay open and
-- can be written to right away.
-- @return number of files deleted, number of files that could not be
function protocols.clear_all()
	local deleted, failed = 0, 0
	for _, file in ipairs(core.get_dir_list(DIR, false)) do
		if file:match("%.tsv$") then
			if os.remove(DIR .. "/" .. file) then
				deleted = deleted + 1
			else
				failed = failed + 1
			end
		end
	end
	core.log("action", "[lep_core] deleted " .. deleted .. " protocol file(s)"
		.. (failed > 0 and ", " .. failed .. " could not be deleted" or ""))
	for _, listener in ipairs(clear_listeners) do
		local ok, err = pcall(listener)
		if not ok then
			core.log("error", "[lep_core] listener for deleted protocols failed: "
				.. tostring(err))
		end
	end
	return deleted, failed
end

local function path(name)
	return DIR .. "/" .. name .. ".tsv"
end

-- Per opened protocol: the numbers of the columns that say whose entry a
-- line is. A file no mod has opened this time is taken by the rule that
-- the first column is the account.
local account_positions = {}
local DEFAULT_POSITIONS = { 1 }

--- Deletes the entries of one account from all protocols of this world:
-- what the account caused itself, and what was addressed to it alone.
-- Lines of others that only mention the account stay. This is deleting
-- on request, see the concept, section 12.
-- @return number of entries deleted, number of files that could not be
--   rewritten
function protocols.remove_account(account)
	assert(type(account) == "string" and account ~= "", "remove_account: account is missing")
	local removed, failed = 0, 0
	for _, file_name in ipairs(core.get_dir_list(DIR, false)) do
		local name = file_name:match("^(.*)%.tsv$")
		local file = name and io.open(path(name), "r")
		if file then
			local lines = {}
			for line in file:lines() do
				lines[#lines + 1] = line
			end
			file:close()
			local kept, count = protocol.without_account(lines, account,
				account_positions[name] or DEFAULT_POSITIONS)
			if count > 0 then
				local text = #kept > 0 and table.concat(kept, "\n") .. "\n" or ""
				if core.safe_file_write(path(name), text) then
					removed = removed + count
				else
					failed = failed + 1
				end
			end
		end
	end
	core.log("action", "[lep_core] deleted " .. removed .. " protocol entries of one account"
		.. (failed > 0 and ", " .. failed .. " file(s) could not be rewritten" or ""))
	return removed, failed
end

local function now()
	return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

--- Opens a protocol. Opening the same name twice returns the same object.
-- @param name Lower case word, also the file name.
-- @param columns List of column names. The time is added automatically.
--   By convention the first column is "account" with the account name,
--   never the display name.
-- @param accounts Optional list of the columns that say whose entry a
--   line is, by default { "account" }. A protocol with entries that are
--   addressed to somebody names that column as well, so deleting an
--   account takes them along.
-- @return Object with :append(record) and :read(filter, limit).
function protocols.open(name, columns, accounts)
	assert(protocol.is_valid_name(name), "protocol name must be a lower case word")
	if opened[name] then
		return opened[name]
	end
	protocol.check_columns(columns)
	account_positions[name] = protocol.positions(columns, accounts or { "account" })
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

return protocols
