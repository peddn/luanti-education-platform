-- Writes the text of signs the server sets up itself. The signs are
-- drawn by signs_lib, with one text entity per sign.
--
-- A sign must not get its entity while nobody is near. The server keeps
-- objects of a block asleep until a player comes close, so signs_lib
-- cannot see an entity that is already there and adds another one with
-- every call. In that case only the text is stored. signs_lib draws it
-- when the block wakes up: it does that for all its signs at every load.

local signs = {}

--- Sets the text of a sign that stands at pos.
-- @param text Text as the players shall read it.
function signs.write(pos, text)
	assert(core.global_exists("signs_lib"), "lep_core.signs needs the mod signs_lib")
	if core.compare_block_status(pos, "active") then
		signs_lib.update_sign(pos, { text = text })
	else
		core.get_meta(pos):set_string("text", text)
	end
end

return signs
