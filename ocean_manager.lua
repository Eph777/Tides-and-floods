-- ocean_manager.lua
-- Ocean chunk manager: discovers ocean areas, applies Gerstner wave heights,
-- and spawns/piles surge_water_moving nodes onto the coastline when wind/tides push.

local settings = realistic_fluids.settings.ocean
local OceanWaves = realistic_fluids.ocean_waves

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
	local c_cust_source = minetest.get_content_id("realistic_fluids:surge_water")
	local c_cust_moving = minetest.get_content_id("realistic_fluids:surge_water_moving")
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
				   cid == c_cust_source or cid == c_cust_moving then
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
	nodenames = {"default:water_source", "realistic_fluids:surge_water", "realistic_fluids:surge_water_moving"},
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
local c_water_flowing = nil
local c_surge = nil
local c_surge_moving = nil
local c_air = nil

local function ensure_content_ids()
	if not c_water then
		c_water = minetest.get_content_id("default:water_source")
		c_water_flowing = minetest.get_content_id("default:water_flowing")
		c_surge = minetest.get_content_id("realistic_fluids:surge_water")
		c_surge_moving = minetest.get_content_id("realistic_fluids:surge_water_moving")
		c_air = minetest.get_content_id("air")
	end
end

-- Update one chunk: render waves in ocean, and spawn surge water in direction of tide force.
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
	local param2_data = vm:get_param2_data()
	local va = VoxelArea:new{MinEdge = emin, MaxEdge = emax}

	local modified = false
	local start_timer_list = {}
	local start_timer_count = 0

	local force = realistic_fluids.force

	for lz = 0, CHUNK - 1 do
		for lx = 0, CHUNK - 1 do
			local idx = lz * CHUNK + lx + 1
			local col = columns[idx]

			if col then
				local wx = min_x + lx
				local wz = min_z + lz
				local floor_y = col.floor_y

				if col.is_ocean then
					-- Render Gerstner waves in ocean columns
					local wave_y, wave_remainder = OceanWaves.get_surface(
						wx, wz, time, effective_sea, iters, amp
					)
					wave_y = math_min(wave_y, y_max)

					-- Fill water from terrain+1 up to wave surface
					if wave_y > floor_y then
						for y = floor_y + 1, wave_y do
							if va:contains(wx, y, wz) then
								local vi = va:index(wx, y, wz)
								local existing = data[vi]
								
								-- Overwrite air, flowing water, surge water, or permeable nodes
								if existing == c_air or existing == c_water_flowing or existing == c_surge or
								   existing == c_surge_moving or get_permeability(existing) == "permeable" then
									
									if y == wave_y then
										local level = math_floor((1.0 - wave_remainder) * 7)
										level = math_min(7, math_max(0, level))
										if existing ~= c_water_flowing or param2_data[vi] ~= level then
											data[vi] = c_water_flowing
											param2_data[vi] = level
											modified = true
										end
									else
										if existing ~= c_water then
											data[vi] = c_water
											param2_data[vi] = 0
											modified = true
										end
									end
								end
							end
						end

						-- Clear any water above wave surface (receding wave)
						for y = wave_y + 1, y_max do
							if va:contains(wx, y, wz) then
								local vi = va:index(wx, y, wz)
								local existing = data[vi]
								if existing == c_water or existing == c_water_flowing or
								   existing == c_surge or existing == c_surge_moving then
									data[vi] = c_air
									param2_data[vi] = 0
									modified = true
								elseif existing ~= c_air then
									break -- hit solid ground above, stop
								end
							end
						end
					else
						-- Wave surface is below seafloor: clear water above seafloor
						for y = floor_y + 1, math_min(floor_y + 6, y_max) do
							if va:contains(wx, y, wz) then
								local vi = va:index(wx, y, wz)
								local existing = data[vi]
								if existing == c_water or existing == c_water_flowing or
								   existing == c_surge or existing == c_surge_moving then
									data[vi] = c_air
									param2_data[vi] = 0
									modified = true
								elseif existing ~= c_air then
									break
								end
							end
						end
					end

					-- Spawner / Generator logic: Push surge water (moving/invisible) onto land
					if force and force.strength > 0 and (force.x ~= 0 or force.z ~= 0) then
						local dx = force.x
						local dz = force.z
						local dest_x = wx + dx
						local dest_z = wz + dz
						local dest_y = wave_y

						if va:contains(dest_x, dest_y, dest_z) then
							local dest_vi = va:index(dest_x, dest_y, dest_z)
							local dest_cid = data[dest_vi]

							if dest_cid == c_air or get_permeability(dest_cid) == "permeable" then
								-- Spawn surge water as moving (invisible) on flat shore
								data[dest_vi] = c_surge_moving
								param2_data[dest_vi] = 0 -- full volume (param2=0 -> level 8)
								modified = true

								start_timer_count = start_timer_count + 1
								start_timer_list[start_timer_count] = {x = dest_x, y = dest_y, z = dest_z}
							elseif dest_cid ~= c_water and dest_cid ~= c_water_flowing and
							       dest_cid ~= c_surge and dest_cid ~= c_surge_moving then
								-- Destination is solid cliff/shoreline: Pile up directly above ocean block
								local above_y = wave_y + 1
								if va:contains(wx, above_y, wz) then
									local above_vi = va:index(wx, above_y, wz)
									local above_cid = data[above_vi]

									if above_cid == c_air or get_permeability(above_cid) == "permeable" then
										data[above_vi] = c_surge_moving
										param2_data[above_vi] = 0 -- full volume
										modified = true

										start_timer_count = start_timer_count + 1
										start_timer_list[start_timer_count] = {x = wx, y = above_y, z = wz}
									end
								end
							end
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

		-- Start node timers for the newly spawned surge water blocks
		for i = 1, start_timer_count do
			minetest.get_node_timer(start_timer_list[i]):start(0.1)
		end
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
