-- init.lua
-- Physics Mod for Luanti
-- Adapted from Minecraft Physics Mod mechanics

local modpath = minetest.get_modpath("realistic_fluids")

-- Phase 0: Settings (creates the realistic_fluids global table)
dofile(modpath .. "/settings.lua")

-- Register custom nodes
dofile(modpath .. "/nodes.lua")

if realistic_fluids.settings.disabled then
	minetest.log("action", "[realistic_fluids] Mod disabled via settings.")
	return
end

-- Phase 1: Ocean Physics
if realistic_fluids.settings.ocean.enabled then
	realistic_fluids.ocean_waves = dofile(modpath .. "/ocean_waves.lua")
	realistic_fluids.ocean_time = 0
	dofile(modpath .. "/ocean_manager.lua")  -- Chunk management + VoxelManip updates
	dofile(modpath .. "/ocean_buoyancy.lua") -- Entity bobbing + splash effects
end

-- Phase 2: Building Debris
if realistic_fluids.settings.debris.enabled then
	dofile(modpath .. "/debris_fragments.lua")  -- Debris entity definition
	dofile(modpath .. "/debris_hooks.lua")      -- Break/blast event hooks
end

minetest.log("action", "[realistic_fluids] Physics Mod loaded successfully.")
