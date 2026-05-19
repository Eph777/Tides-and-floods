-- init.lua
-- Realistic Fluids Mod

local modpath = minetest.get_modpath("realistic_fluids")

-- Load settings
dofile(modpath .. "/settings.lua")

-- If LBM is disabled, we gracefully degrade by simply not overriding default water mechanics
if realistic_fluids.settings.disable_lbm then
	minetest.log("action", "[realistic_fluids] Mod disabled via settings, falling back to default water.")
	return
end

-- Phase 1: Pure LBM Core is required by Phase 2, but we don't need to dofile it here
-- as grid_adapter does it, but let's load it formally if we wanted.

-- Phase 2: Voxel Grid Adapter
dofile(modpath .. "/grid_adapter.lua")

-- Phase 3: Dynamics (Currents, Waterfalls, Erosion)
dofile(modpath .. "/dynamics.lua")

-- Phase 4: Visuals & Audio
dofile(modpath .. "/visuals.lua")

minetest.log("action", "[realistic_fluids] Successfully loaded SWE fluid simulation.")
