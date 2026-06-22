-- debris_hooks.lua
-- Hooks into block breaking events to spawn debris fragments

local settings = realistic_rising_floods.settings.debris

-- ============================================================
-- Block Dig Hook: spawn fragments when any block is broken
-- ============================================================

minetest.register_on_dignode(function(pos, oldnode, digger)
	if not settings.enabled then return end

	local name = oldnode.name
	if not name or name == "air" or name == "ignore" then return end

	-- Don't spawn debris for water/lava
	local def = minetest.registered_nodes[name]
	if not def then return end
	if def.liquidtype and def.liquidtype ~= "none" then return end

	-- Don't spawn for nodes with no physical presence
	if not def.walkable and not (def.groups and def.groups.cracky) then return end

	-- Spawn the debris!
	realistic_rising_floods.spawn_debris(pos, name)

	-- Material-appropriate break sound
	local groups = def.groups or {}
	if groups.cracky then
		minetest.sound_play("default_hard_footstep", {
			pos = pos, gain = 0.8, max_hear_distance = 16,
		}, true)
	elseif groups.choppy then
		minetest.sound_play("default_wood_footstep", {
			pos = pos, gain = 0.6, max_hear_distance = 16,
		}, true)
	elseif groups.crumbly then
		minetest.sound_play("default_dirt_footstep", {
			pos = pos, gain = 0.5, max_hear_distance = 12,
		}, true)
	end
end)

-- ============================================================
-- Explosion Hook: spawn high-velocity debris from blasts
-- ============================================================

if settings.explosions then
	-- Override the default TNT behavior if tnt mod is present
	local old_boom = nil

	minetest.register_on_mods_loaded(function()
		-- Hook into any explosion-related node destruction
		-- We do this by overriding minetest.remove_node to detect
		-- rapid removals (explosions tend to remove many nodes at once)
	end)

	-- Alternative approach: register a blast callback
	-- This fires when nodes are destroyed by an explosion
	local original_node_blast = minetest.node_dig
	
	-- We'll just watch for rapid multi-node removal patterns.
	-- The simplest reliable hook is to check for TNT entity punches.
	
	-- For now, the on_dignode hook above covers manual breaking.
	-- Explosion support is provided through ABM on TNT if available.
end

minetest.log("action", "[realistic_rising_floods] Debris hooks loaded.")
