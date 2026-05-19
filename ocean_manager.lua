-- ocean_manager.lua
-- Ocean chunk manager: discovers ocean areas, applies Gerstner wave heights via VoxelManip

local settings = realistic_fluids.settings.ocean
local OceanWaves = realistic_fluids.ocean_waves

-- Track active ocean regions as a set of chunk hashes
local active_chunks = {}    -- hash -> {min_x, min_z, seafloor={}}
local chunk_queue = {}       -- ordered list of hashes for round-robin
local queue_index = 1
local global_time = 0

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

-- Scan a chunk column with VoxelManip to find the seafloor for each (x,z).
-- Also detects coastal land columns that could be flooded.
-- Returns a table[local_index] = {floor_y=N, is_ocean=bool, land_y=N or nil}, or nil if nothing interesting.
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

			-- Scan top-down
			for y = y_max, y_min, -1 do
				local vi = va:index(min_x + lx, y, min_z + lz)
				local cid = data[vi]

				if cid == c_water_source or cid == c_water_flowing then
					found_water = true
				elseif found_water and cid ~= c_air and cid ~= c_ignore then
					floor_y = y
					break
				elseif not found_water and cid ~= c_air and cid ~= c_ignore then
					-- Land column: record the surface height if it's near sea level
					if y <= sea + flood_max + 2 then
						land_surface_y = y
					end
					break
				end
			end

			if found_water then
				has_anything = true
				columns[idx] = {
					floor_y = floor_y or (y_min - 1),
					is_ocean = true,
				}
			elseif land_surface_y and land_surface_y <= sea + flood_max + 2 then
				-- Coastal land that could be flooded
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
	nodenames = {"default:water_source"},
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
local c_water = nil
local c_air = nil

local function ensure_content_ids()
	if not c_water then
		c_water = minetest.get_content_id("default:water_source")
		c_air = minetest.get_content_id("air")
	end
end

-- Update one chunk: compute Gerstner wave surface for ALL columns uniformly
-- Water naturally spreads wherever the wave surface exceeds the terrain.
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

	local p1 = {x = min_x, y = y_min, z = min_z}
	local p2 = {x = min_x + CHUNK - 1, y = y_max, z = min_z + CHUNK - 1}

	local vm = minetest.get_voxel_manip()
	local emin, emax = vm:read_from_map(p1, p2)
	local data = vm:get_data()
	local va = VoxelArea:new{MinEdge = emin, MaxEdge = emax}

	local modified = false

	for lz = 0, CHUNK - 1 do
		for lx = 0, CHUNK - 1 do
			local idx = lz * CHUNK + lx + 1
			local col = columns[idx]

			if col then
				local wx = min_x + lx
				local wz = min_z + lz
				local floor_y = col.floor_y

				-- Compute the Gerstner wave surface at this position
				-- This is the SAME for ocean and land columns — no invisible walls!
				local wave_surface_y = OceanWaves.get_surface(
					wx, wz, time, effective_sea, iters, amp
				)

				-- Only place water if the wave surface is above the terrain
				if wave_surface_y > floor_y then
					local top_y = math_min(wave_surface_y, y_max)

					-- Fill water from terrain+1 up to the wave surface
					for y = floor_y + 1, top_y do
						local vi = va:index(wx, y, wz)
						local existing = data[vi]
						-- Place water in air or existing water slots only
						if existing == c_air or existing == c_water then
							if existing ~= c_water then
								data[vi] = c_water
								modified = true
							end
						end
						-- If we hit a solid block (tree trunk, wall), skip it
						-- Water flows around it naturally
					end

					-- Clear water above the wave surface (wave receding)
					for y = top_y + 1, y_max do
						local vi = va:index(wx, y, wz)
						local existing = data[vi]
						if existing == c_water then
							data[vi] = c_air
							modified = true
						elseif existing ~= c_air then
							break  -- hit solid, stop
						end
					end
				else
					-- Wave surface is below terrain: clear any leftover water above terrain
					for y = floor_y + 1, math_min(floor_y + 6, y_max) do
						local vi = va:index(wx, y, wz)
						local existing = data[vi]
						if existing == c_water then
							data[vi] = c_air
							modified = true
						elseif existing ~= c_air then
							break
						end
					end
				end
			end
		end
	end

	if modified then
		vm:set_data(data)
		vm:write_to_map(false)
	end
end

-- ============================================================
-- Main globalstep
-- ============================================================

minetest.register_globalstep(function(dtime)
	if not settings.enabled then return end

	global_time = global_time + dtime * settings.wave_speed

	-- Progressive flood: slowly raise the effective sea level
	if settings.flood_enabled then
		local rise_per_sec = (settings.flood_speed or 0.5) / 60.0
		flood_rise = math_min(flood_rise + rise_per_sec * dtime, settings.flood_max or 8)
	end

	-- Export for buoyancy module
	realistic_fluids.ocean_time = global_time
	realistic_fluids.flood_rise = flood_rise

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
