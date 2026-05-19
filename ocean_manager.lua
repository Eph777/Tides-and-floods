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
-- Returns a table[local_index] = seafloor_y, or nil if no ocean here.
local function scan_chunk_seafloor(min_x, min_z)
	local sea = settings.sea_level
	local y_min = sea - 30
	local y_max = sea + 10

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

	local seafloor = {}
	local has_ocean = false

	for lz = 0, CHUNK - 1 do
		for lx = 0, CHUNK - 1 do
			local idx = lz * CHUNK + lx + 1
			local floor_y = nil
			local found_water = false

			-- Scan top-down: find the water column then the first solid below it
			for y = y_max, y_min, -1 do
				local vi = va:index(min_x + lx, y, min_z + lz)
				local cid = data[vi]

				if cid == c_water_source or cid == c_water_flowing then
					found_water = true
				elseif found_water and cid ~= c_air and cid ~= c_ignore then
					-- First solid block under water = seafloor
					floor_y = y
					break
				elseif not found_water and cid ~= c_air and cid ~= c_ignore then
					-- Solid above water level with no water found above it
					-- This column is land, not ocean
					break
				end
			end

			if found_water then
				has_ocean = true
				seafloor[idx] = floor_y or (y_min - 1)
			else
				seafloor[idx] = nil  -- land column, don't touch
			end
		end
	end

	if has_ocean then
		return seafloor
	end
	return nil
end

-- Register a chunk as active ocean
local function register_chunk(min_x, min_z)
	local hash = chunk_hash(min_x, min_z)
	if active_chunks[hash] then return end

	local seafloor = scan_chunk_seafloor(min_x, min_z)
	if not seafloor then return end

	active_chunks[hash] = {
		min_x = min_x,
		min_z = min_z,
		seafloor = seafloor,
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

-- Update one chunk: compute Gerstner heights and write water/air via VoxelManip
local function update_chunk(chunk_data, time)
	ensure_content_ids()

	local min_x = chunk_data.min_x
	local min_z = chunk_data.min_z
	local seafloor = chunk_data.seafloor
	local sea = settings.sea_level
	local iters = settings.wave_iterations
	local amp = settings.wave_height

	-- Determine vertical bounds for the VoxelManip
	-- We need from the deepest seafloor to sea_level + max_amplitude + margin
	local y_min = sea - 30
	local y_max = sea + math_floor(amp) + 4

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
			local floor_y = seafloor[idx]

			if floor_y then
				-- This is an ocean column
				local wx = min_x + lx
				local wz = min_z + lz

				local top_y, remainder = OceanWaves.get_surface(
					wx, wz, time, sea, iters, amp
				)

				-- Clamp: don't go below seafloor
				if top_y < floor_y + 1 then
					top_y = floor_y
				end

				-- Write water from seafloor+1 up to top_y
				for y = floor_y + 1, math_min(top_y, y_max) do
					local vi = va:index(wx, y, wz)
					if data[vi] ~= c_water then
						data[vi] = c_water
						modified = true
					end
				end

				-- Write air from top_y+1 upward (clear old wave crests)
				for y = math_max(top_y + 1, floor_y + 1), y_max do
					local vi = va:index(wx, y, wz)
					local existing = data[vi]
					-- Only replace water or air, never solid blocks
					if existing == c_water then
						data[vi] = c_air
						modified = true
					elseif existing ~= c_air then
						break  -- hit solid, stop clearing
					end
				end
			end
		end
	end

	if modified then
		vm:set_data(data)
		vm:write_to_map(false)  -- false = don't recalculate light (faster)
	end
end

-- ============================================================
-- Main globalstep
-- ============================================================

minetest.register_globalstep(function(dtime)
	if not settings.enabled then return end

	global_time = global_time + dtime * settings.wave_speed

	-- Export for buoyancy module
	realistic_fluids.ocean_time = global_time

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
			update_chunk(active_chunks[hash], global_time)
			processed = processed + 1
		end
	end
end)

minetest.log("action", "[realistic_fluids] Ocean manager loaded.")
