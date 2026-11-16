-- Web access of a teacher, as the desk knows it. Pure Lua, no engine
-- calls.
--
-- The backend decides how a web access stands. The world keeps a copy
-- with shortened addresses, never a whole address.

local web_access = {}

-- What a teacher can ask for.
web_access.SET = "set"
web_access.RESEND = "resend"
web_access.REMOVE = "remove"

-- How a web access can stand.
web_access.NONE = "none"
web_access.PENDING = "pending"
web_access.CONFIRMED = "confirmed"

-- Longest address, as mail allows.
web_access.MAX_EMAIL = 254
-- Seconds between two requests for a confirmation mail.
web_access.MAIL_PAUSE = 60

--- Returns an address as it is sent, trimmed and in lower case, or nil if
-- the text cannot be an address. Whether mail arrives there only the
-- confirmation shows.
function web_access.check_email(text)
	if type(text) ~= "string" then
		return nil
	end
	local email = text:match("^%s*(.-)%s*$"):lower()
	if email == "" or #email > web_access.MAX_EMAIL or email:find("[%s%c]") then
		return nil
	end
	local local_part, domain = email:match("^([^@]+)@([^@]+)$")
	if not local_part or not domain:find(".", 1, true) then
		return nil
	end
	if domain:sub(1, 1) == "." or domain:sub(-1) == "." or domain:find("..", 1, true) then
		return nil
	end
	return email
end

--- Shortens an address for showing it: the first character and the
-- domain.
function web_access.mask(email)
	local local_part, domain = tostring(email):match("^([^@]+)@(.+)$")
	if not local_part then
		return "…"
	end
	-- The first character may take several bytes.
	local first = local_part:match("^[%z\1-\127\194-\244][\128-\191]*")
	return first .. "…@" .. domain
end

local function text_or_nil(value)
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

--- Builds the copy the world keeps: address (confirmed, shortened) and
-- pending (waiting for its confirmation, shortened), each a text or nil.
function web_access.record(address, pending)
	return { address = text_or_nil(address), pending = text_or_nil(pending) }
end

--- Returns how a web access stands: NONE, PENDING or CONFIRMED. A
-- confirmed address stays valid while a new one waits.
function web_access.status(record)
	if record and record.address then
		return web_access.CONFIRMED
	elseif record and record.pending then
		return web_access.PENDING
	end
	return web_access.NONE
end

--- Returns the copy as it stands right after a request, before the
-- backend has answered.
-- @param email The checked address, for SET.
function web_access.after_request(record, kind, email)
	record = record or {}
	if kind == web_access.SET then
		local masked = web_access.mask(email)
		if masked == record.address then
			-- Probably the confirmed address again. The backend knows.
			return web_access.record(record.address, record.pending)
		end
		return web_access.record(record.address, masked)
	elseif kind == web_access.REMOVE then
		return web_access.record(nil, nil)
	end
	return web_access.record(record.address, record.pending)
end

--- Returns true if a new confirmation mail may be asked for.
-- @param last_asked Time of the last request, or nil.
function web_access.may_ask_for_mail(last_asked, now)
	return last_asked == nil or now - last_asked >= web_access.MAIL_PAUSE
end

--- Returns true if two lists hold the same names, in any order.
function web_access.same_names(first, second)
	if #first ~= #second then
		return false
	end
	local seen = {}
	for _, name in ipairs(first) do
		seen[name] = true
	end
	for _, name in ipairs(second) do
		if not seen[name] then
			return false
		end
	end
	return true
end

return web_access
