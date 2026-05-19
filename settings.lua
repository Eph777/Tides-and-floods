-- settings.lua
realistic_fluids = {}

realistic_fluids.settings = {
	-- LBM relaxation time (controls viscosity). Default 0.6. Higher = more viscous. > 0.5 required for stability.
	lbm_tau = tonumber(minetest.settings:get("realistic_fluids_lbm_tau")) or 0.6,
	
	-- Max number of LBM cells to update per tick to stay within 5ms budget.
	tick_budget = tonumber(minetest.settings:get("realistic_fluids_tick_budget")) or 4096,
	
	-- Enable shore erosion.
	enable_erosion = minetest.settings:get_bool("realistic_fluids_enable_erosion", false),

	-- Disable the entire LBM system and fallback to default water.
	disable_lbm = minetest.settings:get_bool("realistic_fluids_disable_lbm", false),
}
