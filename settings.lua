-- settings.lua
-- Global settings for the Physics Mod

realistic_fluids = {}

realistic_fluids.settings = {
	-- Master kill switch
	disabled = minetest.settings:get_bool("realistic_fluids_disabled", false),

	-- ========== Ocean Physics ==========
	ocean = {
		enabled = minetest.settings:get_bool("realistic_fluids_ocean_enabled", true),

		-- Sea level Y coordinate (Minetest default ocean is at Y=1)
		sea_level = tonumber(minetest.settings:get("realistic_fluids_sea_level")) or 1,

		-- Wave amplitude in blocks (how tall the crests get)
		wave_height = tonumber(minetest.settings:get("realistic_fluids_wave_height")) or 1.8,

		-- Wave speed multiplier (higher = faster rolling waves)
		wave_speed = tonumber(minetest.settings:get("realistic_fluids_wave_speed")) or 1.0,

		-- Number of Gerstner iterations (1-5, higher = more detail but slower)
		wave_iterations = tonumber(minetest.settings:get("realistic_fluids_wave_iterations")) or 3,

		-- How many chunks to process per server step (performance tuning)
		chunks_per_tick = tonumber(minetest.settings:get("realistic_fluids_chunks_per_tick")) or 8,

		-- Horizontal radius around player to simulate (in blocks)
		sim_radius = tonumber(minetest.settings:get("realistic_fluids_sim_radius")) or 64,

		-- Buoyancy force multiplier
		buoyancy_force = tonumber(minetest.settings:get("realistic_fluids_buoyancy_force")) or 6.0,

		-- Progressive coastal flooding
		flood_enabled = minetest.settings:get_bool("realistic_fluids_flood_enabled", true),

		-- How fast the sea level rises (blocks per minute)
		flood_speed = tonumber(minetest.settings:get("realistic_fluids_flood_speed")) or 0.5,

		-- Maximum flood height above base sea level (blocks)
		flood_max = tonumber(minetest.settings:get("realistic_fluids_flood_max")) or 8,

		-- Depth below sea_level where deep ocean begins (water_source, no CA)
		deep_ocean_depth = tonumber(minetest.settings:get("realistic_fluids_deep_ocean_depth")) or 5,
	},

	-- ========== Cellular Automata Fluid Engine ==========
	ca = {
		-- CA iterations per server tick (more = faster spreading, heavier CPU)
		ticks_per_step = tonumber(minetest.settings:get("realistic_fluids_ca_ticks")) or 2,

		-- Horizontal equalization damping threshold (prevents jitter)
		-- Only transfer if volume difference > this value
		damping = tonumber(minetest.settings:get("realistic_fluids_ca_damping")) or 1,

		-- Maximum volume per cell (matches paramtype2 leveled range)
		max_volume = 64,

		-- Gravity transfer rate (fraction of available volume moved down per tick)
		-- 1.0 = instant fall, 0.5 = half per tick
		gravity_rate = tonumber(minetest.settings:get("realistic_fluids_ca_gravity_rate")) or 1.0,

		-- Horizontal transfer rate (fraction of equalization applied per tick)
		-- 1.0 = instant equalize, 0.3 = gradual spreading
		horizontal_rate = tonumber(minetest.settings:get("realistic_fluids_ca_horizontal_rate")) or 0.8,
	},

	-- ========== Building Debris ==========
	debris = {
		enabled = minetest.settings:get_bool("realistic_fluids_debris_enabled", true),

		-- Number of fragments per broken block (min, max)
		fragment_min = tonumber(minetest.settings:get("realistic_fluids_fragment_min")) or 3,
		fragment_max = tonumber(minetest.settings:get("realistic_fluids_fragment_max")) or 6,

		-- Fragment lifetime in seconds
		fragment_lifetime = tonumber(minetest.settings:get("realistic_fluids_fragment_lifetime")) or 4.0,

		-- Initial burst velocity for fragments
		burst_speed = tonumber(minetest.settings:get("realistic_fluids_burst_speed")) or 3.0,

		-- Gravity acceleration (m/s^2)
		gravity = tonumber(minetest.settings:get("realistic_fluids_debris_gravity")) or 9.8,

		-- Bounce coefficient (0 = no bounce, 1 = perfect bounce)
		bounce = tonumber(minetest.settings:get("realistic_fluids_debris_bounce")) or 0.3,

		-- Fragment visual scale
		fragment_scale = tonumber(minetest.settings:get("realistic_fluids_fragment_scale")) or 0.25,

		-- Enable explosion debris (TNT etc)
		explosions = minetest.settings:get_bool("realistic_fluids_debris_explosions", true),

		-- Explosion burst speed multiplier
		explosion_mult = tonumber(minetest.settings:get("realistic_fluids_explosion_mult")) or 3.0,
	},
}
