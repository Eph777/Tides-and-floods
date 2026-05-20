-- ocean_buoyancy.lua
-- Entity interaction with ocean: bobbing, floating, splash particles.
-- Detects both default:water_source (deep ocean) and realistic_fluids:cwater (shore CA water).

local settings = realistic_fluids.settings.ocean
local OceanWaves = realistic_fluids.ocean_waves
local MAX_VOL = realistic_fluids.settings.ca.max_volume

local math_max = math.max
local math_min = math.min
local math_random = math.random
local math_floor = math.floor

-- ============================================================
-- Get effective water surface Y at a world position
-- ============================================================
-- Checks the Gerstner analytical surface for deep ocean,
-- and reads actual CA water param2 for shore water.
local function get_water_surface_at(pos, time, sea, iters, amp)
	-- First check if we're standing in CA water
	local node = minetest.get_node(pos)
	if node.name == "realistic_fluids:cwater" then
		-- CA water: surface = block Y bottom + fractional height from param2
		local frac = (node.param2 or 0) / MAX_VOL
		return math_floor(pos.y) - 0.5 + frac
	end

	-- Check the node at feet level and one above
	local above = {x = pos.x, y = pos.y + 1, z = pos.z}
	local node_above = minetest.get_node(above)
	if node_above.name == "realistic_fluids:cwater" then
		local frac = (node_above.param2 or 0) / MAX_VOL
		return math_floor(above.y) - 0.5 + frac
	end

	-- Check below for CA water
	local below = {x = pos.x, y = pos.y - 1, z = pos.z}
	local node_below = minetest.get_node(below)
	if node_below.name == "realistic_fluids:cwater" then
		local frac = (node_below.param2 or 0) / MAX_VOL
		return math_floor(below.y) - 0.5 + frac
	end

	-- Default water_source or deep ocean: use Gerstner analytical surface
	if node.name == "default:water_source"
	   or node_below.name == "default:water_source" then
		return sea + OceanWaves.get_height(pos.x, pos.z, time, iters, amp)
	end

	-- No water here
	return nil
end

-- ============================================================
-- Player and Entity Buoyancy
-- ============================================================

minetest.register_globalstep(function(dtime)
	if not settings.enabled then return end

	local time = realistic_fluids.ocean_time or 0
	local flood_rise = realistic_fluids.flood_rise or 0
	local sea = settings.sea_level + flood_rise
	local iters = settings.wave_iterations
	local amp = settings.wave_height
	local buoy_force = settings.buoyancy_force

	-- Players
	for _, player in ipairs(minetest.get_connected_players()) do
		local pos = player:get_pos()
		if not pos then goto continue_player end

		local wave_y = get_water_surface_at(pos, time, sea, iters, amp)
		if not wave_y then goto continue_player end

		local feet_y = pos.y

		-- Only apply if player is near/in the water
		if feet_y > wave_y + 2.0 then goto continue_player end
		if feet_y < sea - 30 then goto continue_player end

		local depth = wave_y - feet_y  -- positive = submerged

		if depth > 0.1 then
			-- Buoyancy: push upward proportional to submersion
			local vy = math_min(depth * buoy_force * dtime, 4.0)

			-- Also apply horizontal flow from the wave (for deep ocean)
			local vx, vz = OceanWaves.get_velocity(pos.x, pos.z, time, iters, amp)
			local flow_scale = 1.5 * dtime

			player:add_velocity({
				x = vx * flow_scale,
				y = vy,
				z = vz * flow_scale,
			})
		end

		::continue_player::
	end

	-- Lua entities (dropped items, boats, etc.)
	for _, entity in pairs(minetest.luaentities) do
		if not entity.object then goto continue_entity end
		local pos = entity.object:get_pos()
		if not pos then goto continue_entity end

		-- Skip entities far from sea level
		if pos.y > sea + amp + 10 or pos.y < sea - 30 then goto continue_entity end

		local wave_y = get_water_surface_at(pos, time, sea, iters, amp)
		if not wave_y then goto continue_entity end

		local depth = wave_y - pos.y

		if depth > 0.0 then
			local vy = math_min(depth * buoy_force * 1.5 * dtime, 6.0)
			local vx, vz = OceanWaves.get_velocity(pos.x, pos.z, time, iters, amp)
			local flow_scale = 2.0 * dtime

			entity.object:add_velocity({
				x = vx * flow_scale,
				y = vy,
				z = vz * flow_scale,
			})
		end

		::continue_entity::
	end
end)

-- ============================================================
-- Splash particles when entities enter water
-- ============================================================

local splash_cooldown = {}

local function try_splash(pos, name)
	local key = name or minetest.pos_to_string(pos)
	local now = minetest.get_gametime()
	if splash_cooldown[key] and now - splash_cooldown[key] < 1 then return end
	splash_cooldown[key] = now

	-- Spawn splash particles
	minetest.add_particlespawner({
		amount = 12,
		time = 0.3,
		minpos = {x = pos.x - 0.5, y = pos.y, z = pos.z - 0.5},
		maxpos = {x = pos.x + 0.5, y = pos.y + 0.3, z = pos.z + 0.5},
		minvel = {x = -1.5, y = 1.0, z = -1.5},
		maxvel = {x = 1.5, y = 3.0, z = 1.5},
		minacc = {x = 0, y = -9.8, z = 0},
		maxacc = {x = 0, y = -9.8, z = 0},
		minexptime = 0.3,
		maxexptime = 0.8,
		minsize = 0.5,
		maxsize = 1.5,
		texture = "default_water.png",
		collisiondetection = true,
	})

	-- Splash sound
	minetest.sound_play("default_water_footstep", {
		pos = pos,
		gain = 0.5,
		max_hear_distance = 16,
	}, true)
end

-- Periodically check for entities crossing the water surface
local splash_timer = 0
local prev_submerged = {}

minetest.register_globalstep(function(dtime)
	if not settings.enabled then return end
	splash_timer = splash_timer + dtime
	if splash_timer < 0.2 then return end
	splash_timer = 0

	local time = realistic_fluids.ocean_time or 0
	local flood_rise = realistic_fluids.flood_rise or 0
	local sea = settings.sea_level + flood_rise
	local iters = settings.wave_iterations
	local amp = settings.wave_height

	for _, player in ipairs(minetest.get_connected_players()) do
		local pos = player:get_pos()
		if not pos then goto next_p end
		local name = player:get_player_name()

		local wave_y = get_water_surface_at(pos, time, sea, iters, amp)
		local is_sub = wave_y and pos.y < wave_y

		if is_sub and not prev_submerged[name] then
			try_splash(pos, name)
		end
		prev_submerged[name] = is_sub

		::next_p::
	end
end)

minetest.log("action", "[realistic_fluids] Ocean buoyancy loaded (CA + deep ocean).")
