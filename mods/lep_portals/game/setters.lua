-- Sets the nodes of a portal: frame, field and sign.

local load = lep_core.loader("lep_portals")
local frames = load("src/frames")

local setters = {}

setters.FIELD = "lep_portals:field"
setters.FIELD_INACTIVE = "lep_portals:field_inactive"
setters.FRAME = "lep_portals:frame"

-- All nodes that are a portal field, by name.
local field_nodes = { [setters.FIELD] = true, [setters.FIELD_INACTIVE] = true }

--- Makes a node name known as a portal field.
function setters.add_field_node(name)
	field_nodes[name] = true
end

--- Returns true if a node with this name is a portal field.
function setters.is_field(name)
	return field_nodes[name] == true
end

--- Loads the map around a portal, so its nodes can be set.
function setters.load_around(pos)
	core.load_area(vector.offset(pos, -2, -2, -2), vector.offset(pos, 2, 3, 2))
end

--- Sets the two field nodes of a portal.
-- @param active False for the dark field of a portal that leads nowhere yet.
-- @param kind One of the kinds of src/links.lua.
-- @param owner Owner of a personal portal or id of a module, or nil.
-- @param node Optional name of the field node, for a field in its own
--   colour.
function setters.set_field(base, axis, active, kind, owner, node)
	for _, pos in ipairs(frames.field(base, axis)) do
		core.set_node(pos, {
			name = active and (node or setters.FIELD) or setters.FIELD_INACTIVE,
			param2 = axis == "x" and 0 or 1,
		})
		local meta = core.get_meta(pos)
		meta:set_string("kind", kind)
		meta:set_string("owner", owner or "")
		meta:mark_as_private({ "kind", "owner" })
	end
end

--- Removes the lit field of a personal portal.
function setters.remove_field(base, axis, owner)
	for _, pos in ipairs(frames.field(base, axis)) do
		if core.get_node(pos).name == setters.FIELD
				and core.get_meta(pos):get_string("owner") == owner then
			core.remove_node(pos)
		end
	end
end

--- Sets the frame of a portal, corners included.
function setters.set_frame(base, axis)
	for _, list in ipairs({ frames.required(base, axis), frames.corners(base, axis) }) do
		for _, pos in ipairs(list) do
			core.set_node(pos, { name = setters.FRAME })
		end
	end
end

--- Hangs a sign with a text.
-- @param wall Direction from the sign to the node it hangs on.
-- @param text Text as the players shall read it. Signs are drawn on the
--   server, so a translatable text is put into German here.
function setters.set_sign(pos, wall, text)
	core.set_node(pos, { name = "lep_portals:sign", param2 = core.dir_to_wallmounted(wall) })
	signs_lib.update_sign(pos, { text = core.get_translated_string("de", text) })
end

--- Sets a whole portal as src/learning.lua describes it: frame, field and
-- sign.
function setters.set_portal(portal, kind, owner, node, sign_text)
	setters.load_around(portal.base)
	setters.set_frame(portal.base, portal.axis)
	setters.set_field(portal.base, portal.axis, true, kind, owner, node)
	setters.set_sign(portal.sign, portal.sign_wall, sign_text)
end

return setters
