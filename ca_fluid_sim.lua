-- ca_fluid_sim.lua
-- Cellular Automata Fluid Simulation Engine
-- Volumetric water movement via VoxelManip with strict conservation of mass.
--
-- ARCHITECTURE:
--   1. Read region with +1 margin via VoxelManip
--   2. Decode content IDs into a flat volume array (0-64 per cell)
--   3. Gravity pass: move water DOWN (bottom-to-top iteration)
--   4. Horizontal pass: equalize pressure across 4 cardinal neighbors
--   5. Encode volume array back to content IDs + param2
--   6. Write ONLY interior cells (margin = read-only for chunk boundary safety)

local ca_settings = realistic_fluids.settings.ca
local ocean_settings = realistic_fluids.settings.ocean

local MAX_VOL = ca_settings.max_volume          -- 64
local DAMPING = ca_settings.damping             -- 1
local GRAVITY_RATE = ca_settings.gravity_rate    -- 1.0
local HORIZ_RATE = ca_settings.horizontal_rate   -- 0.8
local TICKS_PER_STEP = ca_settings.ticks_per_step -- 2

local math_floor = math.floor
local math_min = math.min
local math_max = math.max
local math_abs = math.abs

-- ============================================================
-- Content ID cache (initialized lazily after mods loaded)
-- ============================================================
local c_cwater = nil
local c_air = nil
local c_water_source = nil
local c_water_flowing = nil
local c_ignore = nil
local ids_ready = false

-- Permeability cache: cid -> true (passable) or false (solid)
local passable_cache = {}

local function ensure_ids()
	if ids_ready then return end
	c_cwater = minetest.get_content_id("realistic_fluids:cwater")
	c_air = minetest.get_content_id("air")
	c_water_source = minetest.get_content_id("default:water_source")
	c_water_flowing = minetest.get_content_id("default:water_flowing")
	c_ignore = minetest.get_content_id("ignore")

	-- Pre-mark known passable types
	passable_cache[c_air] = true
	passable_cache[c_cwater] = true
	passable_cache[c_water_flowing] = true
	passable_cache[c_ignore] = false  -- unloaded = impassable (boundary safety)
	passable_cache[c_water_source] = false  -- deep ocean = wall for CA (stays as-is)

	ids_ready = true
end

-- Check if a content ID is passable (air, cwater, or non-walkable vegetation)
local function is_passable(cid)
	local cached = passable_cache[cid]
	if cached ~= nil then return cached end

	local name = minetest.get_name_from_content_id(cid)
	local def = minetest.registered_nodes[name]
	if not def then
		passable_cache[cid] = false
		return false
	end

	-- Non-walkable blocks are passable (grass, flowers, leaves)
	local result = not def.walkable
	passable_cache[cid] = result
	return result
end

-- ============================================================
-- Core CA Step: process one 3D region
-- ============================================================
-- region_min, region_max: {x,y,z} of the area to WRITE (interior)
-- The VoxelManip will read +1 margin on all sides (boundary cells)

function realistic_fluids.ca_step(region_min, region_max)
	ensure_ids()

	-- Expand by 1 in all directions for boundary read margin
	-- CHUNK BOUNDARY SAFETY: we read +1 margin, but ONLY write interior.
	-- Edge cells act as read-only boundary conditions.
	-- When the neighboring chunk is processed, IT writes its own cells.
	local margin = 1
	local read_min = {
		x = region_min.x - margin,
		y = region_min.y - margin,
		z = region_min.z - margin,
	}
	local read_max = {
		x = region_max.x + margin,
		y = region_max.y + margin,
		z = region_max.z + margin,
	}

	-- Read VoxelManip
	local vm = minetest.get_voxel_manip()
	local emin, emax = vm:read_from_map(read_min, read_max)
	local data = vm:get_data()
	local param2_data = vm:get_param2_data()
	local va = VoxelArea:new{MinEdge = emin, MaxEdge = emax}

	-- ---- DECODE: Build volume array ----
	-- vol[vi] = -1 (solid/impassable), 0 (empty air), 1-64 (water volume)
	local vol = {}
	local has_water = false
	local area_size = va:getVolume()

	for vi = 1, area_size do
		local cid = data[vi]
		if cid == c_cwater then
			-- Our CA water: param2 = volume level
			local v = param2_data[vi]
			if v < 1 then v = 0 end
			if v > MAX_VOL then v = MAX_VOL end
			vol[vi] = v
			if v > 0 then has_water = true end
		elseif cid == c_air then
			vol[vi] = 0
		elseif is_passable(cid) then
			-- Non-walkable vegetation: treat as empty (will be replaced by water)
			vol[vi] = 0
		else
			-- Solid block (dirt, stone, tree trunk, water_source, etc.)
			vol[vi] = -1
		end
	end

	-- Early exit: no water in this region at all
	if not has_water then return false end

	-- Precompute VoxelArea strides for neighbor access
	local ystride = va.ystride
	local zstride = va.zstride

	-- ---- GRAVITY PASS (bottom to top) ----
	-- Process each cell from y=emin+1 upward. For each cell with water,
	-- try to move water to the cell directly below.
	-- Bottom-to-top ensures water settles fully in one pass.
	for y = emin.y + 1, emax.y do
		for z = emin.z, emax.z do
			for x = emin.x, emax.x do
				local vi_here = va:index(x, y, z)
				local v_here = vol[vi_here]

				if v_here > 0 then
					local vi_below = vi_here - ystride
					local v_below = vol[vi_below]

					-- v_below >= 0 means passable (air or partial water)
					if v_below >= 0 and v_below < MAX_VOL then
						local space = MAX_VOL - v_below
						local transfer = math_min(v_here, space)
						transfer = math_floor(transfer * GRAVITY_RATE)
						if transfer > 0 then
							vol[vi_here] = v_here - transfer
							vol[vi_below] = v_below + transfer
						end
					end
				end
			end
		end
	end

	-- ---- HORIZONTAL EQUALIZATION PASS ----
	-- For each cell with water, equalize with 4 cardinal neighbors at same Y.
	-- We use a separate output array to prevent order-dependent artifacts.
	local vol_new = {}
	for vi = 1, area_size do
		vol_new[vi] = vol[vi]
	end

	for y = emin.y, emax.y do
		for z = emin.z + 1, emax.z - 1 do  -- skip margin
			for x = emin.x + 1, emax.x - 1 do  -- skip margin
				local vi = va:index(x, y, z)
				local v = vol[vi]

				-- Only process cells that have water OR are empty and adjacent to water
				if v < 0 then goto continue_h end  -- solid, skip

				-- Check if cell below is solid (only spread horizontally when supported)
				local vi_below = vi - ystride
				local v_below = vol[vi_below]
				if v > 0 and v_below >= 0 and v_below < MAX_VOL then
					-- Still has room below — gravity hasn't finished, skip horizontal
					goto continue_h
				end

				-- Gather this cell + passable cardinal neighbors
				local neighbors = {}
				local total = v
				local count = 1
				neighbors[1] = vi

				-- +X
				local vi_px = vi + 1
				if vol[vi_px] >= 0 then
					count = count + 1
					neighbors[count] = vi_px
					total = total + vol[vi_px]
				end
				-- -X
				local vi_mx = vi - 1
				if vol[vi_mx] >= 0 then
					count = count + 1
					neighbors[count] = vi_mx
					total = total + vol[vi_mx]
				end
				-- +Z
				local vi_pz = vi + zstride
				if vol[vi_pz] >= 0 then
					count = count + 1
					neighbors[count] = vi_pz
					total = total + vol[vi_pz]
				end
				-- -Z
				local vi_mz = vi - zstride
				if vol[vi_mz] >= 0 then
					count = count + 1
					neighbors[count] = vi_mz
					total = total + vol[vi_mz]
				end

				if count <= 1 or total <= 0 then goto continue_h end

				-- Calculate equalized distribution
				local avg = math_floor(total / count)
				local remainder = total - avg * count

				-- Check if any transfer would actually happen (damping)
				local max_diff = 0
				for i = 1, count do
					local diff = math_abs(vol[neighbors[i]] - avg)
					if diff > max_diff then max_diff = diff end
				end
				if max_diff <= DAMPING then goto continue_h end

				-- Apply equalization with rate limiting
				for i = 1, count do
					local nvi = neighbors[i]
					local target = avg + (i <= remainder and 1 or 0)
					local current = vol[nvi]
					local delta = target - current
					-- Rate-limit the horizontal transfer
					local applied = math_floor(delta * HORIZ_RATE)
					vol_new[nvi] = current + applied
				end

				::continue_h::
			end
		end
	end

	-- Apply horizontal results
	for vi = 1, area_size do
		vol[vi] = vol_new[vi]
	end

	-- ---- ENCODE: Convert volume array back to content IDs ----
	local modified = false

	-- CHUNK BOUNDARY SAFETY: Only write interior cells, NOT the margin.
	-- Margin cells (the +1 border) are read-only — they belong to adjacent chunks.
	for y = region_min.y, region_max.y do
		for z = region_min.z, region_max.z do
			for x = region_min.x, region_max.x do
				local vi = va:index(x, y, z)
				local v = vol[vi]
				local old_cid = data[vi]

				if v <= 0 then
					-- Empty: should be air (only replace cwater or passable nodes)
					if old_cid == c_cwater or (is_passable(old_cid) and old_cid ~= c_air) then
						data[vi] = c_air
						param2_data[vi] = 0
						modified = true
					end
				elseif v > 0 then
					-- Has water volume: set to cwater with param2 = volume
					local clamped = math_min(MAX_VOL, math_max(1, v))
					if old_cid ~= c_cwater or param2_data[vi] ~= clamped then
						data[vi] = c_cwater
						param2_data[vi] = clamped
						modified = true
					end
				end
				-- v == -1 (solid): don't touch
			end
		end
	end

	if modified then
		vm:set_data(data)
		vm:set_param2_data(param2_data)
		-- Do NOT call update_liquids() — we bypass the engine entirely
		vm:write_to_map(true)  -- true for light recalculation
	end

	return modified
end

-- ============================================================
-- Region Tracker: which regions have active CA water?
-- ============================================================
local active_regions = {}  -- hash -> {min=, max=, last_active=}

function realistic_fluids.ca_register_region(min_pos, max_pos)
	local hash = minetest.hash_node_position(min_pos)
	active_regions[hash] = {
		min = {x = min_pos.x, y = min_pos.y, z = min_pos.z},
		max = {x = max_pos.x, y = max_pos.y, z = max_pos.z},
		last_active = minetest.get_gametime(),
	}
end

-- ============================================================
-- Globalstep: run CA simulation for active regions near players
-- ============================================================
local ca_timer = 0

minetest.register_globalstep(function(dtime)
	if not ocean_settings.enabled then return end

	ca_timer = ca_timer + dtime
	-- Run CA at ~10 Hz (every 0.1s) regardless of server step rate
	if ca_timer < 0.1 then return end
	ca_timer = 0

	ensure_ids()

	local players = minetest.get_connected_players()
	if #players == 0 then return end

	-- Process active regions near players
	local sim_radius = ocean_settings.sim_radius or 64
	local now = minetest.get_gametime()

	for hash, region in pairs(active_regions) do
		-- Skip stale regions (no activity for 30 seconds)
		if now - region.last_active > 30 then
			active_regions[hash] = nil
			goto next_region
		end

		-- Check if any player is close enough
		local close = false
		local cx = (region.min.x + region.max.x) / 2
		local cz = (region.min.z + region.max.z) / 2
		for _, player in ipairs(players) do
			local pp = player:get_pos()
			if pp then
				local dx = pp.x - cx
				local dz = pp.z - cz
				if dx * dx + dz * dz < sim_radius * sim_radius then
					close = true
					break
				end
			end
		end

		if close then
			for t = 1, TICKS_PER_STEP do
				local had_changes = realistic_fluids.ca_step(region.min, region.max)
				if not had_changes then break end  -- settled, stop early
			end
		end

		::next_region::
	end
end)

minetest.log("action", "[realistic_fluids] CA Fluid Engine loaded (max_vol=" .. MAX_VOL
	.. " damping=" .. DAMPING .. " ticks=" .. TICKS_PER_STEP .. ").")
