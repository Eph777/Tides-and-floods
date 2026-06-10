-- init.lua
-- Physics Mod for Luanti
-- Adapted from Minecraft Physics Mod mechanics

local modpath = minetest.get_modpath("realistic_fluids")

-- Phase 0: Settings (creates the realistic_fluids global table)
dofile(modpath .. "/settings.lua")

if realistic_fluids.settings.disabled then
	minetest.log("action", "[realistic_fluids] Mod disabled via settings.")
	return
end

-- Phase 1: Ocean Physics
if realistic_fluids.settings.ocean.enabled then
	dofile(modpath .. "/nodes.lua")
	dofile(modpath .. "/voxelmanip.lua")
	dofile(modpath .. "/lbm.lua")
	dofile(modpath .. "/abm.lua")
	realistic_fluids.ocean_waves = dofile(modpath .. "/ocean_waves.lua")
	realistic_fluids.ocean_time = 0
	dofile(modpath .. "/ocean_manager.lua")  -- Tide controller & storage management
	dofile(modpath .. "/ocean_buoyancy.lua") -- Entity bobbing + splash effects
end

-- Phase 1.5: Climate Integration (requires climate_api mod)
if realistic_fluids.settings.ocean.enabled and minetest.get_modpath("climate_api") then
	dofile(modpath .. "/climate_integration.lua")
end

-- Phase 2: Building Debris
if realistic_fluids.settings.debris.enabled then
	dofile(modpath .. "/debris_fragments.lua")  -- Debris entity definition
	dofile(modpath .. "/debris_hooks.lua")      -- Break/blast event hooks
end

minetest.log("action", "[realistic_fluids] Physics Mod loaded successfully.")
