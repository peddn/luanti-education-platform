-- Writes rooms into the map.

local build = {}

local function content_ids()
	return {
		floor = core.get_content_id("lep_rooms:floor"),
		wall = core.get_content_id("lep_rooms:wall"),
		ceiling = core.get_content_id("lep_rooms:ceiling"),
		air = core.get_content_id("lep_rooms:air"),
	}
end

-- Loads the area, then calls callback() once.
local function with_area(min, max, callback)
	core.emerge_area(min, max, function(_, _, remaining)
		if remaining == 0 then
			callback()
		end
	end)
end

local function write(geometry, include_shell)
	local ids = content_ids()
	local min = include_shell and geometry.shell_min or geometry.interior_min
	local max = include_shell and geometry.shell_max or geometry.interior_max

	local vm = core.get_voxel_manip()
	local emin, emax = vm:read_from_map(min, max)
	local area = VoxelArea:new({ MinEdge = emin, MaxEdge = emax })
	local data = vm:get_data()

	local imin, imax = geometry.interior_min, geometry.interior_max
	for z = min.z, max.z do
		for y = min.y, max.y do
			local index = area:index(min.x, y, z)
			for x = min.x, max.x do
				local id
				if y < imin.y then
					id = ids.floor
				elseif y > imax.y then
					id = ids.ceiling
				elseif x < imin.x or x > imax.x or z < imin.z or z > imax.z then
					id = ids.wall
				else
					id = ids.air
				end
				data[index] = id
				index = index + 1
			end
		end
	end

	vm:set_data(data)
	vm:write_to_map(true)
end

--- Builds the shell and empties the interior. Calls callback() when done.
function build.room(geometry, callback)
	with_area(geometry.shell_min, geometry.shell_max, function()
		write(geometry, true)
		callback()
	end)
end

--- Empties the interior and leaves the shell alone. Calls callback() when done.
function build.clear_interior(geometry, callback)
	with_area(geometry.interior_min, geometry.interior_max, function()
		write(geometry, false)
		callback()
	end)
end

return build
