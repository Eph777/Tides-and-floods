-- settings.lua
-- Global settings for the Physics Mod

realistic_rising_floods = {}

realistic_rising_floods.settings = {
	-- Master kill switch
	disabled = minetest.settings:get_bool("realistic_rising_floods_disabled", false),

	-- ========== Ocean Physics ==========
	ocean = {
		enabled = minetest.settings:get_bool("realistic_rising_floods_ocean_enabled", true),

		-- Sea level Y coordinate (Minetest default ocean is at Y=1)
		sea_level = tonumber(minetest.settings:get("realistic_rising_floods_sea_level")) or 1,

		-- Wave amplitude in blocks (how tall the crests get)
		wave_height = tonumber(minetest.settings:get("realistic_rising_floods_wave_height")) or 1.8,

		-- Wave speed multiplier (higher = faster rolling waves)
		wave_speed = tonumber(minetest.settings:get("realistic_rising_floods_wave_speed")) or 1.0,

		-- Number of Gerstner iterations (1-5, higher = more detail but slower)
		wave_iterations = tonumber(minetest.settings:get("realistic_rising_floods_wave_iterations")) or 3,

		-- How many chunks to process per server step (performance tuning)
		chunks_per_tick = tonumber(minetest.settings:get("realistic_rising_floods_chunks_per_tick")) or 8,

		-- Horizontal radius around player to simulate (in blocks)
		sim_radius = tonumber(minetest.settings:get("realistic_rising_floods_sim_radius")) or 64,

		-- Buoyancy force multiplier
		buoyancy_force = tonumber(minetest.settings:get("realistic_rising_floods_buoyancy_force")) or 6.0,

		-- Progressive coastal flooding
		flood_enabled = minetest.settings:get_bool("realistic_rising_floods_flood_enabled", true),

		-- How fast the sea level rises (blocks per minute)
		flood_speed = tonumber(minetest.settings:get("realistic_rising_floods_flood_speed")) or 0.5,

		-- Maximum flood height above base sea level (blocks)
		flood_max = tonumber(minetest.settings:get("realistic_rising_floods_flood_max")) or 8,

		-- Water lateral spreading speed (0 = fastest, 7 = slowest, default water is 1)
		water_viscosity = tonumber(minetest.settings:get("realistic_rising_floods_water_viscosity")) or 0,

		-- How far water flows from a source block (1-8, default is 8)
		water_range = tonumber(minetest.settings:get("realistic_rising_floods_water_range")) or 8,

		-- Whether to use colorized water blocks to debug tide stages (white/black/purple)
		debug_colors = minetest.settings:get_bool("realistic_rising_floods_debug_colors", false),

		-- Replace water in already generated mapblocks
		fix_generated_water = minetest.settings:get_bool("realistic_rising_floods_fix_generated_water", true),
	},

	-- ========== Building Debris ==========
	debris = {
		enabled = minetest.settings:get_bool("realistic_rising_floods_debris_enabled", true),

		-- Number of fragments per broken block (min, max)
		fragment_min = tonumber(minetest.settings:get("realistic_rising_floods_fragment_min")) or 3,
		fragment_max = tonumber(minetest.settings:get("realistic_rising_floods_fragment_max")) or 6,

		-- Fragment lifetime in seconds
		fragment_lifetime = tonumber(minetest.settings:get("realistic_rising_floods_fragment_lifetime")) or 4.0,

		-- Initial burst velocity for fragments
		burst_speed = tonumber(minetest.settings:get("realistic_rising_floods_burst_speed")) or 3.0,

		-- Gravity acceleration (m/s^2)
		gravity = tonumber(minetest.settings:get("realistic_rising_floods_debris_gravity")) or 9.8,

		-- Bounce coefficient (0 = no bounce, 1 = perfect bounce)
		bounce = tonumber(minetest.settings:get("realistic_rising_floods_debris_bounce")) or 0.3,

		-- Fragment visual scale
		fragment_scale = tonumber(minetest.settings:get("realistic_rising_floods_fragment_scale")) or 0.25,

		-- Enable explosion debris (TNT etc)
		explosions = minetest.settings:get_bool("realistic_rising_floods_debris_explosions", true),

		-- Explosion burst speed multiplier
		explosion_mult = tonumber(minetest.settings:get("realistic_rising_floods_explosion_mult")) or 3.0,
	},
}
