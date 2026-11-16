-- Where a portal leads. Pure Lua, no engine calls.

local links = {}

-- Kinds of portals.
links.LOBBY = "lobby"         -- fixed portal in the hall
links.WILDERNESS = "wilderness" -- fixed portal in the wilderness
links.ROOM = "room"           -- portal in a personal room
links.PLOT = "plot"           -- portal a player built on their plot
links.HUB = "hub"             -- portal in the hall that leads to the learning hall
links.EXIT = "exit"           -- portal in the learning hall back to the hall
links.MODULE = "module"       -- portal of a learning module in the learning hall

-- Results of links.destination.
links.TO_WILDERNESS = "to_wilderness"
links.TO_HALL = "to_hall"
links.TO_ROOM = "to_room"
links.TO_PLOT = "to_plot"
links.TO_LEARNING_HALL = "to_learning_hall"
links.TO_HUB = "to_hub"       -- into the hall, in front of the hub portal
links.TO_MODULE = "to_module" -- into the learning room of a module
links.HINT_BUILD = "hint_build"
links.HINT_FOREIGN = "hint_foreign"

--- Decides what happens when a player steps into a portal.
-- @param kind One of the kinds above.
-- @param owner Owner of a room or plot portal, nil for the fixed ones.
-- @param player_name The player in the portal.
-- @param owner_has_plot True if the owner has a lit portal on their plot.
function links.destination(kind, owner, player_name, owner_has_plot)
	if kind == links.LOBBY then
		return links.TO_WILDERNESS
	elseif kind == links.WILDERNESS then
		return links.TO_HALL
	elseif kind == links.ROOM then
		if player_name ~= owner then
			return links.HINT_FOREIGN
		elseif owner_has_plot then
			return links.TO_PLOT
		end
		return links.HINT_BUILD
	elseif kind == links.HUB then
		return links.TO_LEARNING_HALL
	elseif kind == links.EXIT then
		return links.TO_HUB
	elseif kind == links.MODULE then
		return links.TO_MODULE
	elseif kind == links.PLOT then
		if player_name == owner then
			return links.TO_ROOM
		end
		-- Strangers never reach somebody else's room this way.
		return links.TO_HALL
	end
	return nil
end

--- Creates the record of lit plot portals, one per player.
-- @param data Table from an earlier export, or nil.
function links.new_plots(data)
	local plots = {}

	local function valid_pos(pos)
		return type(pos) == "table" and type(pos.x) == "number"
			and type(pos.y) == "number" and type(pos.z) == "number"
	end

	if type(data) == "table" then
		for owner, plot in pairs(data) do
			if type(owner) == "string" and type(plot) == "table"
					and valid_pos(plot.base) and valid_pos(plot.arrival)
					and (plot.axis == "x" or plot.axis == "z") then
				plots[owner] = { base = plot.base, axis = plot.axis, arrival = plot.arrival }
			end
		end
	end

	local record = {}

	--- Returns the plot portal of a player, or nil.
	function record.get(_, owner)
		return plots[owner]
	end

	--- Stores the plot portal of a player.
	-- @return The portal it replaces, or nil.
	function record.set(_, owner, base, axis, arrival)
		local old = plots[owner]
		plots[owner] = { base = base, axis = axis, arrival = arrival }
		return old
	end

	--- Forgets the plot portal of a player.
	-- @return The removed portal, or nil.
	function record.remove(_, owner)
		local old = plots[owner]
		plots[owner] = nil
		return old
	end

	--- Returns a plain table for storage.
	function record.export(_)
		local copy = {}
		for owner, plot in pairs(plots) do
			copy[owner] = plot
		end
		return copy
	end

	return record
end

return links
