-- ocean_manager.lua
-- Ocean chunk manager: discovers ocean areas, applies Gerstner wave heights,
-- and runs 3D Cellular Automata fluid dynamics via VoxelManip.

local settings = realistic_fluids.settings.ocean
local OceanWaves = realistic_fluids.ocean_waves

-- Track active ocean regions as a set of chunk hashes
local active_chunks = {}    -- hash -> {min_x, min_z, columns={}}
local chunk_queue = {}       -- ordered list of hashes for round-robin
local queue_index = 1
local global_time = 0
local tick_count = 0

local CHUNK = 16
local math_floor = math.floor
local math_min = math.min
local math_max = math.max

-- Flood state: current flood level above base sea_level
local flood_rise = 0

-- ============================================================
-- Chunk discovery
-- ============================================================

local function chunk_hash(cx, cz)
	return cx .. "," .. cz
end

local function get_chunk_coords(pos)
	return math_floor(pos.x / CHUNK) * CHUNK,
	       math_floor(pos.z / CHUNK) * CHUNK
end

-- Cache: is a given content ID "permeable" to water?
-- Permeable = water can flow through/replace it (leaves, grass, flowers, saplings)
-- Tree trunks are walkable but water should flow PAST them (not replace them)
local permeability_cache = {}  -- cid -> "solid_ground" | "permeable" | "tree_trunk" | nil

local function get_permeability(cid)
	if permeability_cache[cid] ~= nil then
		return permeability_cache[cid]
	end
	local name = minetest.get_name_from_content_id(cid)
	local def = minetest.registered_nodes[name]
	if not def then
		permeability_cache[cid] = "solid_ground"
		return "solid_ground"
	end
	local groups = def.groups or {}
	if groups.tree then
		-- Tree trunks: water flows past but doesn't replace
		permeability_cache[cid] = "tree_trunk"
	elseif groups.leaves or groups.flora or groups.flower or groups.sapling
	       or groups.snappy or groups.attached_node
	       or not def.walkable then
		-- Non-walkable vegetation: water replaces it
		permeability_cache[cid] = "permeable"
	else
		-- Solid ground (dirt, stone, sand, slabs, stairs, etc.)
		permeability_cache[cid] = "solid_ground"
	end
	return permeability_cache[cid]
end

-- Scan a chunk column with VoxelManip to find the seafloor for each (x,z).
-- Looks THROUGH trees and vegetation to find the actual walkable ground.
local function scan_chunk_terrain(min_x, min_z)
	local sea = settings.sea_level
	local flood_max = settings.flood_max or 8
	local y_min = sea - 30
	local y_max = sea + flood_max + 6

	local p1 = {x = min_x, y = y_min, z = min_z}
	local p2 = {x = min_x + CHUNK - 1, y = y_max, z = min_z + CHUNK - 1}

	local vm = minetest.get_voxel_manip()
	local emin, emax = vm:read_from_map(p1, p2)
	local data = vm:get_data()
	local va = VoxelArea:new{MinEdge = emin, MaxEdge = emax}

	local c_water_source = minetest.get_content_id("default:water_source")
	local c_water_flowing = minetest.get_content_id("default:water_flowing")
	local c_cust_source = minetest.get_content_id("realistic_fluids:water_source")
	local c_cust_flowing = minetest.get_content_id("realistic_fluids:water_flowing")
	local c_air = minetest.get_content_id("air")
	local c_ignore = minetest.get_content_id("ignore")

	local columns = {}
	local has_anything = false

	for lz = 0, CHUNK - 1 do
		for lx = 0, CHUNK - 1 do
			local idx = lz * CHUNK + lx + 1
			local floor_y = nil
			local found_water = false
			local land_surface_y = nil

			-- Scan top-down, looking THROUGH trees and vegetation
			for y = y_max, y_min, -1 do
				local vi = va:index(min_x + lx, y, min_z + lz)
				local cid = data[vi]

				if cid == c_water_source or cid == c_water_flowing or
				   cid == c_cust_source or cid == c_cust_flowing then
					found_water = true
				elseif cid == c_air or cid == c_ignore then
					-- Keep scanning
				elseif found_water then
					-- Under water: check if this is real ground or vegetation
					local perm = get_permeability(cid)
					if perm == "solid_ground" then
						floor_y = y
						break
					end
					-- tree_trunk or permeable: keep scanning for real floor
				else
					-- No water above: check what this block is
					local perm = get_permeability(cid)
					if perm == "solid_ground" then
						-- Actual ground surface
						if y <= sea + flood_max + 2 then
							land_surface_y = y
						end
						break
					end
					-- tree_trunk or permeable vegetation: skip, keep scanning
				end
			end

			if found_water then
				has_anything = true
				columns[idx] = {
					floor_y = floor_y or (y_min - 1),
					is_ocean = true,
				}
			elseif land_surface_y and land_surface_y <= sea + flood_max + 2 then
				has_anything = true
				columns[idx] = {
					floor_y = land_surface_y,
					is_ocean = false,
				}
			else
				columns[idx] = nil
			end
		end
	end

	if has_anything then
		return columns
	end
	return nil
end

-- Register a chunk as active
local function register_chunk(min_x, min_z)
	local hash = chunk_hash(min_x, min_z)
	if active_chunks[hash] then return end

	local columns = scan_chunk_terrain(min_x, min_z)
	if not columns then return end

	active_chunks[hash] = {
		min_x = min_x,
		min_z = min_z,
		columns = columns,
	}
	chunk_queue[#chunk_queue + 1] = hash
end

-- Auto-discover ocean chunks when water blocks load
minetest.register_lbm({
	name = "realistic_fluids:discover_ocean",
	nodenames = {"default:water_source", "realistic_fluids:water_source"},
	run_at_every_load = true,
	action = function(pos, node)
		if not settings.enabled then return end
		local cx, cz = get_chunk_coords(pos)
		register_chunk(cx, cz)
	end,
})

-- ============================================================
-- Per-tick ocean update
-- ============================================================

-- Content IDs (cached after first use)
local c_cust_source = nil
local c_cust_flowing = nil
local c_def_source = nil
local c_def_flowing = nil
local c_air = nil
local c_ignore = nil

local function ensure_content_ids()
	if not c_cust_source then
		c_cust_source = minetest.get_content_id("realistic_fluids:water_source")
		c_cust_flowing = minetest.get_content_id("realistic_fluids:water_flowing")
		c_def_source = minetest.get_content_id("default:water_source")
		c_def_flowing = minetest.get_content_id("default:water_flowing")
		c_air = minetest.get_content_id("air")
		c_ignore = minetest.get_content_id("ignore")
	end
end

-- Update one chunk: compute Gerstner waves & run 3D Cellular Automata fluid simulation
local function update_chunk(chunk_data, time, current_flood_rise)
	ensure_content_ids()

	local min_x = chunk_data.min_x
	local min_z = chunk_data.min_z
	local columns = chunk_data.columns
	local sea = settings.sea_level
	local iters = settings.wave_iterations
	local amp = settings.wave_height

	-- Effective sea level includes progressive flood rise
	local effective_sea = sea + current_flood_rise

	-- Determine vertical bounds for the VoxelManip
	local y_min = sea - 30
	local y_max = math_floor(effective_sea + amp) + 6

	-- Pad by 1 block horizontally to handle chunk boundary flow correctly
	local p1 = {x = min_x - 1, y = y_min, z = min_z - 1}
	local p2 = {x = min_x + CHUNK, y = y_max, z = min_z + CHUNK}

	local vm = minetest.get_voxel_manip()
	local emin, emax = vm:read_from_map(p1, p2)
	local data = vm:get_data()
	local param2_data = vm:get_param2_data()
	local va = VoxelArea:new{MinEdge = emin, MaxEdge = emax}

	-- Helpers for volume mapping
	local function node_to_volume(cid, p2)
		if cid == c_cust_source or cid == c_def_source then
			return 8
		elseif cid == c_cust_flowing or cid == c_def_flowing then
			local vol = 7 - (p2 % 8)
			return vol < 1 and 1 or vol
		else
			return 0
		end
	end

	local function volume_to_node(vol)
		if vol >= 8 then
			return c_cust_source, 0
		elseif vol >= 1 then
			return c_cust_flowing, 7 - math_floor(vol)
		else
			return c_air, 0
		end
	end

	-- Create and pre-initialize 3D grid for the padded region
	local grid_V = {}
	local grid_C = {}
	for x = min_x - 1, min_x + CHUNK do
		grid_V[x] = {}
		grid_C[x] = {}
		for z = min_z - 1, min_z + CHUNK do
			grid_V[x][z] = {}
			grid_C[x][z] = {}
		end
	end

	-- Populate local 3D grid from VoxelManip data
	for x = min_x - 1, min_x + CHUNK do
		for z = min_z - 1, min_z + CHUNK do
			for y = y_min, y_max do
				if va:contains(x, y, z) then
					local vi = va:index(x, y, z)
					local cid = data[vi]
					local p2 = param2_data[vi]
					grid_C[x][z][y] = cid
					grid_V[x][z][y] = node_to_volume(cid, p2)
				else
					-- Outside VoxelArea: treat as solid ignore
					grid_C[x][z][y] = c_ignore
					grid_V[x][z][y] = 0
				end
			end
		end
	end

	-- Apply Ocean Boundary Force
	-- Ocean columns are forced to match the Gerstner wave height to keep the ocean full
	for lz = 0, CHUNK - 1 do
		for lx = 0, CHUNK - 1 do
			local idx = lz * CHUNK + lx + 1
			local col = columns[idx]
			if col and col.is_ocean then
				local wx = min_x + lx
				local wz = min_z + lz
				local floor_y = col.floor_y

				local wave_y, wave_rem = OceanWaves.get_surface(wx, wz, time, effective_sea, iters, amp)
				wave_y = math_min(wave_y, y_max)

				-- Fill ocean water up to the wave surface
				for y = floor_y + 1, wave_y do
					grid_V[wx][wz][y] = 8
					grid_C[wx][wz][y] = c_cust_source
				end

				-- Receding wave: clear any water above wave surface in ocean columns
				for y = math_max(floor_y + 1, wave_y + 1), y_max do
					local cid = grid_C[wx][wz][y]
					if cid == c_cust_source or cid == c_cust_flowing or
					   cid == c_def_source or cid == c_def_flowing then
						grid_V[wx][wz][y] = 0
						grid_C[wx][wz][y] = c_air
					end
				end
			end
		end
	end

	-- Cache permeability check
	local function is_perm(x, y, z)
		local cid = grid_C[x][z][y]
		if cid == c_ignore then return false end
		if cid == c_air or cid == c_cust_source or cid == c_cust_flowing or
		   cid == c_def_source or cid == c_def_flowing then
			return true
		end
		return get_permeability(cid) == "permeable"
	end

	-- 1. Gravity Flow (Downward)
	-- Process bottom-to-top to let water cascade down realistically
	for y = y_min + 1, y_max do
		for x = min_x, min_x + CHUNK - 1 do
			for z = min_z, min_z + CHUNK - 1 do
				local v = grid_V[x][z][y]
				if v > 0 then
					local ny = y - 1
					if is_perm(x, ny, z) then
						local v_down = grid_V[x][z][ny]
						if v_down < 8 then
							local flow = math_min(v, 8 - v_down)
							grid_V[x][z][y] = v - flow
							grid_V[x][z][ny] = v_down + flow
							
							-- Update content class to register it as water
							if grid_C[x][z][ny] ~= c_cust_source and grid_C[x][z][ny] ~= c_cust_flowing then
								grid_C[x][z][ny] = c_cust_flowing
							end
							v = v - flow
						end
					end
				end
			end
		end
	end

	-- 2. Horizontal Pressure Equalization (Spreading)
	-- Spread water to neighbors at the same Y level with less volume
	local dirs = {
		{x = 1, z = 0},
		{x = -1, z = 0},
		{x = 0, z = 1},
		{x = 0, z = -1}
	}

	-- Alternate loop directions to eliminate directional bias
	local x_start, x_end, x_step
	local z_start, z_end, z_step

	if tick_count % 4 == 0 then
		x_start, x_end, x_step = min_x, min_x + CHUNK - 1, 1
		z_start, z_end, z_step = min_z, min_z + CHUNK - 1, 1
	elseif tick_count % 4 == 1 then
		x_start, x_end, x_step = min_x + CHUNK - 1, min_x, -1
		z_start, z_end, z_step = min_z + CHUNK - 1, min_z, -1
	elseif tick_count % 4 == 2 then
		x_start, x_end, x_step = min_x, min_x + CHUNK - 1, 1
		z_start, z_end, z_step = min_z + CHUNK - 1, min_z, -1
	else
		x_start, x_end, x_step = min_x + CHUNK - 1, min_x, -1
		z_start, z_end, z_step = min_z, min_z + CHUNK - 1, 1
	end

	for y = y_min, y_max do
		for x = x_start, x_end, x_step do
			for z = z_start, z_end, z_step do
				local v = grid_V[x][z][y]
				if v > 0 then
					-- Find open neighbors with less water
					local open_neighbors = {}
					local k = 0
					for i = 1, 4 do
						local dx = dirs[i].x
						local dz = dirs[i].z
						local nx = x + dx
						local nz = z + dz

						-- Chunk border safety: check bounds and ignore blocks
						if grid_C[nx] and grid_C[nx][nz] and grid_C[nx][nz][y] ~= c_ignore then
							if is_perm(nx, y, nz) then
								local vn = grid_V[nx][nz][y]
								if vn < v then
									k = k + 1
									open_neighbors[k] = {x = nx, z = nz, vol = vn}
								end
							end
						end
					end

					if k > 0 then
						-- Equalize volume
						local sum = v
						for i = 1, k do
							sum = sum + open_neighbors[i].vol
						end

						local target = math_floor(sum / (k + 1))
						local rem = sum % (k + 1)

						-- Assign target to current cell, distribute remainder
						local my_new_vol = target
						if rem > 0 then
							my_new_vol = my_new_vol + 1
							rem = rem - 1
						end
						grid_V[x][z][y] = my_new_vol

						-- Distribute to neighbors
						for i = 1, k do
							local neigh = open_neighbors[i]
							local n_new_vol = target
							if rem > 0 then
								n_new_vol = n_new_vol + 1
								rem = rem - 1
							end
							grid_V[neigh.x][neigh.z][y] = n_new_vol
							
							if grid_C[neigh.x][neigh.z][y] ~= c_cust_source and grid_C[neigh.x][neigh.z][y] ~= c_cust_flowing then
								grid_C[neigh.x][neigh.z][y] = c_cust_flowing
							end
						end
					end
				end
			end
		end
	end

	-- Write back to VoxelManip data arrays (including the 1-block pad)
	local modified = false
	for x = min_x - 1, min_x + CHUNK do
		for z = min_z - 1, min_z + CHUNK do
			for y = y_min, y_max do
				if va:contains(x, y, z) then
					local vi = va:index(x, y, z)
					local old_cid = data[vi]
					local vol = grid_V[x][z][y]
					
					-- Ensure we only overwrite air, water, or permeable nodes
					local is_old_water = (old_cid == c_cust_source or old_cid == c_cust_flowing or
					                      old_cid == c_def_source or old_cid == c_def_flowing)
					
					if is_old_water or (vol > 0 and (old_cid == c_air or get_permeability(old_cid) == "permeable")) then
						local target_cid, target_param2 = volume_to_node(vol)
						if old_cid ~= target_cid or param2_data[vi] ~= target_param2 then
							data[vi] = target_cid
							param2_data[vi] = target_param2
							modified = true
						end
					end
				end
			end
		end
	end

	if modified then
		vm:set_data(data)
		vm:set_param2_data(param2_data)
		vm:update_liquids()
		vm:write_to_map(true)
	end
end

-- ============================================================
-- Main globalstep
-- ============================================================

minetest.register_globalstep(function(dtime)
	if not settings.enabled then return end

	global_time = global_time + dtime * settings.wave_speed
	tick_count = tick_count + 1

	-- Progressive flood: slowly raise the effective sea level
	if settings.flood_enabled then
		local rise_per_sec = (settings.flood_speed or 0.5) / 60.0
		flood_rise = math_min(flood_rise + rise_per_sec * dtime, settings.flood_max or 8)
	end

	-- Export for buoyancy module
	realistic_fluids.ocean_time = global_time
	realistic_fluids.flood_rise = flood_rise
	realistic_fluids.tick_count = tick_count

	local num_chunks = #chunk_queue
	if num_chunks == 0 then return end

	-- Only process chunks near players
	local players = minetest.get_connected_players()
	if #players == 0 then return end

	-- Build set of nearby chunk hashes
	local nearby = {}
	local radius = settings.sim_radius
	for _, player in ipairs(players) do
		local pos = player:get_pos()
		local pcx = math_floor(pos.x / CHUNK) * CHUNK
		local pcz = math_floor(pos.z / CHUNK) * CHUNK
		local range = math_floor(radius / CHUNK)
		for dz = -range, range do
			for dx = -range, range do
				nearby[chunk_hash(pcx + dx * CHUNK, pcz + dz * CHUNK)] = true
			end
		end
	end

	-- Round-robin update
	local budget = settings.chunks_per_tick
	local processed = 0

	for i = 1, num_chunks do
		if processed >= budget then break end

		if queue_index > num_chunks then queue_index = 1 end
		local hash = chunk_queue[queue_index]
		queue_index = queue_index + 1

		if nearby[hash] and active_chunks[hash] then
			update_chunk(active_chunks[hash], global_time, flood_rise)
			processed = processed + 1
		end
	end
end)

minetest.log("action", "[realistic_fluids] Ocean manager loaded.")
