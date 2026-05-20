-- init.lua
-- Physics Mod for Luanti
-- Adapted from Minecraft Physics Mod mechanics
-- Uses a Cellular Automata fluid engine to bypass the C++ liquid system

local modpath = minetest.get_modpath("realistic_fluids")

-- Phase 0: Settings (creates the realistic_fluids global table)
dofile(modpath .. "/settings.lua")

if realistic_fluids.settings.disabled then
	minetest.log("action", "[realistic_fluids] Mod disabled via settings.")
	return
end

-- Phase 1: Ocean Physics
if realistic_fluids.settings.ocean.enabled then
	-- Gerstner wave math (pure math, no side effects)
	realistic_fluids.ocean_waves = dofile(modpath .. "/ocean_waves.lua")
	realistic_fluids.ocean_time = 0
	realistic_fluids.flood_rise = 0

	-- CA water node (registers realistic_fluids:cwater + conversion LBM)
	dofile(modpath .. "/ca_water_node.lua")

	-- CA fluid simulation engine (the core gravity + spread algorithm)
	dofile(modpath .. "/ca_fluid_sim.lua")

	-- Ocean manager (chunk discovery + Gerstner injection into CA)
	dofile(modpath .. "/ocean_manager.lua")

	-- Buoyancy (entity bobbing + splash effects)
	dofile(modpath .. "/ocean_buoyancy.lua")
end

-- Phase 2: Building Debris
if realistic_fluids.settings.debris.enabled then
	dofile(modpath .. "/debris_fragments.lua")  -- Debris entity definition
	dofile(modpath .. "/debris_hooks.lua")      -- Break/blast event hooks
end

minetest.log("action", "[realistic_fluids] Physics Mod loaded successfully (CA Fluid Engine).")
