-- A small checker for the schemas in api/openapi.json, for the tests.
-- It knows the parts of JSON Schema the description uses: objects with
-- required properties, arrays, strings, numbers, booleans, enums,
-- references and values that may be null.

local json = require("dkjson")

local schema = {}

--- Reads api/openapi.json and returns a function check(name, value) that
-- returns true, or false and where the value does not fit the schema of
-- that name.
function schema.load(path)
	local file = assert(io.open(path, "r"), "cannot open " .. path)
	local document = assert(json.decode(file:read("*a")), "cannot read " .. path)
	file:close()
	local schemas = document.components.schemas

	local check

	local function resolve(node)
		if node["$ref"] then
			local name = node["$ref"]:match("^#/components/schemas/(.+)$")
			return assert(schemas[name], "unknown schema " .. tostring(name))
		end
		return node
	end

	local function is_integer(value)
		return type(value) == "number" and value == math.floor(value)
	end

	check = function(node, value, where)
		node = resolve(node)
		if node.enum then
			for _, allowed in ipairs(node.enum) do
				if value == allowed then
					return true
				end
			end
			return false, where .. ": '" .. tostring(value) .. "' is not allowed"
		end
		local kind = node.type
		if type(kind) == "table" then
			-- Several types are allowed, for a value that may be missing:
			-- the first one that is not "null" counts.
			for _, candidate in ipairs(kind) do
				if candidate ~= "null" then
					kind = candidate
					break
				end
			end
		end
		if kind == "object" then
			if type(value) ~= "table" then
				return false, where .. ": expected an object"
			end
			for _, name in ipairs(node.required or {}) do
				if value[name] == nil then
					return false, where .. ": '" .. name .. "' is missing"
				end
			end
			for name, property in pairs(node.properties or {}) do
				if value[name] ~= nil then
					local ok, err = check(property, value[name], where .. "." .. name)
					if not ok then
						return false, err
					end
				end
			end
			return true
		elseif kind == "array" then
			if type(value) ~= "table" then
				return false, where .. ": expected a list"
			end
			for index, item in ipairs(value) do
				local ok, err = check(node.items, item, where .. "[" .. index .. "]")
				if not ok then
					return false, err
				end
			end
			return true
		elseif kind == "string" then
			return type(value) == "string", where .. ": expected a string"
		elseif kind == "integer" then
			return is_integer(value), where .. ": expected a whole number"
		elseif kind == "number" then
			return type(value) == "number", where .. ": expected a number"
		elseif kind == "boolean" then
			return type(value) == "boolean", where .. ": expected true or false"
		end
		error("the checker does not know the schema type '" .. tostring(kind) .. "' at " .. where)
	end

	return function(name, value)
		return check(assert(schemas[name], "unknown schema " .. name), value, name)
	end
end

return schema
