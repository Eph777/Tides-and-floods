-- ocean_manager.lua
-- Ocean chunk manager: Gerstner waves inject volume into the CA fluid system.
-- Deep ocean (below sea_level - deep_ocean_depth) stays as default:water_source.
-- Shore zone: Gerstner height is converted to CA water volume and injected each tick.
-- The CA engine (ca_fluid_sim.lua) propagates the water inland naturally.

local settings = realistic_fluids.settings.ocean
local OceanWaves = realistic_fluids.ocean_waves
local MAX_VOL = realistic_fluids.settings.ca.max_volume

-- Track active ocean regions as a set of chunk hashes
local active_chunks = {}    -- hash -> {min_x, min_z, columns={}}
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
-- Permeability cache (shared logic with ca_fluid_sim)
-- ============================================================
local permeability_cache = {}

local function get_permeability(cid)
	if permeability_cache[cid] ~= nil then
		return permeability_cache[cid]
	end
	local name = minetest.get_name_from_content_id(cid)
	local def = minetest.registered_nodes[name]
	if not def then
		permeability_cache[cid] = "solid"
		return "solid"
	end
	local groups = def.groups or {}
	if groups.tree then
		permeability_cache[cid] = "tree"
	elseif groups.leaves or groups.flora or groups.flower
	       or groups.sapling or groups.attached_node
	       or not def.walkable then
		permeability_cache[cid] = "permeable"
	else
		permeability_cache[cid] = "solid"
	end
	return permeability_cache[cid]
end

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

-- Scan a chunk to find terrain surface heights.
-- Looks THROUGH trees and vegetation to find actual ground.
local function scan_chunk_terrain(min_x, min_z)
	local sea = settings.sea_level
	local flood_max = settings.flood_max or 8
	local deep = settings.deep_ocean_depth or 5
	local y_min = sea - 30
	local y_max = sea + flood_max + 10

	local p1 = {x = min_x, y = y_min, z = min_z}
	local p2 = {x = min_x + CHUNK - 1, y = y_max, z = min_z + CHUNK - 1}

	local vm = minetest.get_voxel_manip()
	local emin, emax = vm:read_from_map(p1, p2)
	local data = vm:get_data()
	local va = VoxelArea:new{MinEdge = emin, MaxEdge = emax}

	local c_water_source = minetest.get_content_id("default:water_source")
	local c_water_flowing = minetest.get_content_id("default:water_flowing")
	local c_cwater = minetest.get_content_id("realistic_fluids:cwater")
	local c_air = minetest.get_content_id("air")
	local c_ignore = minetest.get_content_id("ignore")

	local columns = {}
	local has_anything = false

	for lz = 0, CHUNK - 1 do
		for lx = 0, CHUNK - 1 do
			local idx = lz * CHUNK + lx + 1
			local ground_y = nil
			local is_ocean = false

			-- Scan top-down, looking through trees/vegetation
			for y = y_max, y_min, -1 do
				local vi = va:index(min_x + lx, y, min_z + lz)
				local cid = data[vi]

				if cid == c_water_source or cid == c_water_flowing or cid == c_cwater then
					is_ocean = true
				elseif cid == c_air or cid == c_ignore then
					-- Keep scanning
				else
					local perm = get_permeability(cid)
					if perm == "solid" then
						ground_y = y
						break
					end
					-- tree/permeable: skip, keep scanning
				end
			end

			if is_ocean and ground_y then
				has_anything = true
				local is_deep = ground_y < (sea - deep)
				columns[idx] = {
					ground_y = ground_y,
					is_deep = is_deep,  -- deep ocean: don't inject CA, leave as water_source
				}
			elseif ground_y and ground_y <= sea + flood_max + 2 then
				-- Coastal land that could be flooded
				has_anything = true
				columns[idx] = {
					ground_y = ground_y,
					is_deep = false,
				}
			end
		end
	end

	if has_anything then return columns end
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

	-- Register this chunk as a CA active region
	local sea = settings.sea_level
	local flood_max = settings.flood_max or 8
	realistic_fluids.ca_register_region(
		{x = min_x, y = sea - 5, z = min_z},
		{x = min_x + CHUNK - 1, y = sea + flood_max + 6, z = min_z + CHUNK - 1}
	)
end

-- Auto-discover ocean/shore chunks
minetest.register_lbm({
	name = "realistic_fluids:discover_ocean",
	nodenames = {"default:water_source", "realistic_fluids:cwater"},
	run_at_every_load = true,
	action = function(pos, node)
		if not settings.enabled then return end
		local cx, cz = get_chunk_coords(pos)
		register_chunk(cx, cz)
	end,
})

-- ============================================================
-- Gerstner Wave Injection into CA
-- ============================================================
-- Each tick, compute the Gerstner wave surface at shore columns
-- and inject CA water volume. The CA engine handles all spreading.

local c_cwater_cached = nil

local function inject_gerstner(chunk_data, time, current_flood_rise)
	if not c_cwater_cached then
		c_cwater_cached = minetest.get_content_id("realistic_fluids:cwater")
	end

	local min_x = chunk_data.min_x
	local min_z = chunk_data.min_z
	local columns = chunk_data.columns
	local sea = settings.sea_level
	local iters = settings.wave_iterations
	local amp = settings.wave_height
	local effective_sea = sea + current_flood_rise

	-- Vertical bounds for the VoxelManip
	local y_min = sea - 5
	local y_max = math_floor(effective_sea + amp) + 4

	local p1 = {x = min_x, y = y_min, z = min_z}
	local p2 = {x = min_x + CHUNK - 1, y = y_max, z = min_z + CHUNK - 1}

	local vm = minetest.get_voxel_manip()
	local emin, emax = vm:read_from_map(p1, p2)
	local data = vm:get_data()
	local param2 = vm:get_param2_data()
	local va = VoxelArea:new{MinEdge = emin, MaxEdge = emax}

	local c_cwater = c_cwater_cached
	local c_air = minetest.get_content_id("air")
	local modified = false

	for lz = 0, CHUNK - 1 do
		for lx = 0, CHUNK - 1 do
			local idx = lz * CHUNK + lx + 1
			local col = columns[idx]
			if not col or col.is_deep then goto next_col end

			local wx = min_x + lx
			local wz = min_z + lz
			local ground_y = col.ground_y

			-- Compute Gerstner wave surface at this world position
			local wave_y, wave_frac = OceanWaves.get_surface(
				wx, wz, time, effective_sea, iters, amp
			)

			-- For each Y level from ground+1 up to wave surface, inject CA water
			if wave_y > ground_y then
				for y = ground_y + 1, math_min(wave_y, y_max) do
					local vi = va:index(wx, y, wz)
					local existing = data[vi]
					local perm = get_permeability(existing)

					-- Only inject into air, cwater, or permeable vegetation
					if existing == c_air or existing == c_cwater
					   or perm == "permeable" then
						local target_vol
						if y == wave_y then
							-- Top block: fractional volume from wave remainder
							target_vol = math_max(1, math_floor(wave_frac * MAX_VOL))
						else
							-- Full block below the surface
							target_vol = MAX_VOL
						end

						-- Inject: set volume to at LEAST the wave target
						-- (don't reduce existing volume — the CA handles drainage)
						local current_vol = 0
						if existing == c_cwater then
							current_vol = param2[vi]
						end

						if target_vol > current_vol then
							data[vi] = c_cwater
							param2[vi] = target_vol
							modified = true
						end
					end
				end
			end

			::next_col::
		end
	end

	if modified then
		vm:set_data(data)
		vm:set_param2_data(param2)
		vm:write_to_map(true)
	end
end

-- ============================================================
-- Main globalstep: Gerstner injection + flood rise
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

	local players = minetest.get_connected_players()
	if #players == 0 then return end

	-- Build nearby chunk set
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

	-- Round-robin Gerstner injection
	local budget = settings.chunks_per_tick
	local processed = 0

	for i = 1, num_chunks do
		if processed >= budget then break end
		if queue_index > num_chunks then queue_index = 1 end
		local hash = chunk_queue[queue_index]
		queue_index = queue_index + 1

		if nearby[hash] and active_chunks[hash] then
			inject_gerstner(active_chunks[hash], global_time, flood_rise)
			processed = processed + 1
		end
	end
end)

minetest.log("action", "[realistic_fluids] Ocean manager loaded (Gerstner -> CA injection).")
