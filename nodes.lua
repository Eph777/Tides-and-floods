-- nodes.lua
-- Custom surge water node with local Node Timer logic for force-driven Cellular Automata.

local function is_permeable(name)
	if name == "air" then return true end
	if name == "ignore" then return false end
	local def = minetest.registered_nodes[name]
	-- Permeable if it is non-walkable vegetation or air
	return def and not def.walkable and name ~= "default:water_source" and name ~= "default:water_flowing"
end

minetest.register_node("realistic_fluids:surge_water", {
	description = "Surge Water",
	drawtype = "flowingliquid",
	tiles = {"default_water.png"},
	special_tiles = {
		{
			name = "default_water_flowing_animated.png",
			backface_culling = false,
			animation = {
				type = "vertical_frames",
				aspect_w = 16,
				aspect_h = 16,
				length = 0.8,
			},
		},
		{
			name = "default_water_flowing_animated.png",
			backface_culling = false,
			animation = {
				type = "vertical_frames",
				aspect_w = 16,
				aspect_h = 16,
				length = 0.8,
			},
		},
	},
	alpha = 191,
	paramtype = "light",
	paramtype2 = "flowingliquid",
	walkable = false,
	pointable = false,
	diggable = false,
	buildable_to = true,
	is_ground_content = false,
	drop = "",
	drowning = 1,
	liquidtype = "source", -- "source" type enables player swimming but disables built-in flow solver
	liquid_alternative_source = "realistic_fluids:surge_water",
	liquid_alternative_flowing = "realistic_fluids:surge_water",
	liquid_viscosity = 1,
	liquid_range = 0,
	liquid_renewable = false,
	post_effect_color = {a = 103, r = 30, g = 60, b = 90},
	groups = {water = 3, liquid = 3, cools_lava = 1, not_in_creative_inventory = 1},

	on_construct = function(pos)
		-- Start the timer immediately when the node is placed
		minetest.get_node_timer(pos):start(0.2)
	end,

	on_timer = function(pos, elapsed)
		local node = minetest.get_node(pos)
		if node.name ~= "realistic_fluids:surge_water" then return false end

		local param2 = node.param2
		local self_vol = 8 - (param2 % 8)
		if self_vol <= 0 then
			minetest.set_node(pos, {name = "air"})
			return false
		end

		-- Rule 2: Gravity (Downward Flow)
		local down_pos = {x = pos.x, y = pos.y - 1, z = pos.z}
		local down_node = minetest.get_node(down_pos)
		
		if is_permeable(down_node.name) or down_node.name == "realistic_fluids:surge_water" then
			if down_node.name == "realistic_fluids:surge_water" then
				local down_vol = 8 - (down_node.param2 % 8)
				local space = 8 - down_vol
				if space > 0 then
					local flow = math.min(self_vol, space)
					local new_down_vol = down_vol + flow
					self_vol = self_vol - flow
					
					minetest.set_node(down_pos, {
						name = "realistic_fluids:surge_water",
						param2 = 8 - new_down_vol
					})
					minetest.get_node_timer(down_pos):start(0.2)
					
					if self_vol <= 0 then
						minetest.set_node(pos, {name = "air"})
						return false
					end
				end
			else
				-- Move block completely downwards
				minetest.set_node(down_pos, {
					name = "realistic_fluids:surge_water",
					param2 = param2
				})
				minetest.get_node_timer(down_pos):start(0.2)
				minetest.set_node(pos, {name = "air"})
				return false
			end
		end

		-- Rule 3 & 1: Force Push and Coastline Piling
		local force = realistic_fluids.force
		if force and force.strength > 0 and (force.x ~= 0 or force.z ~= 0) then
			local dx = force.x
			local dz = force.z
			
			local dest_pos = {x = pos.x + dx, y = pos.y, z = pos.z + dz}
			local dest_node = minetest.get_node(dest_pos)

			if is_permeable(dest_node.name) or dest_node.name == "realistic_fluids:surge_water" then
				-- Rule 3: Force Push (Move forward)
				-- Split the volume so a crest moves forward
				local flow = math.max(1, math.floor(self_vol * force.strength * 0.75))
				if flow > self_vol then flow = self_vol end
				
				if dest_node.name == "realistic_fluids:surge_water" then
					local dest_vol = 8 - (dest_node.param2 % 8)
					local space = 8 - dest_vol
					local actual_flow = math.min(flow, space)
					if actual_flow > 0 then
						self_vol = self_vol - actual_flow
						minetest.set_node(dest_pos, {
							name = "realistic_fluids:surge_water",
							param2 = 8 - (dest_vol + actual_flow)
						})
						minetest.get_node_timer(dest_pos):start(0.2)
					end
				else
					self_vol = self_vol - flow
					minetest.set_node(dest_pos, {
						name = "realistic_fluids:surge_water",
						param2 = 8 - flow
					})
					minetest.get_node_timer(dest_pos):start(0.2)
				end

				if self_vol <= 0 then
					minetest.set_node(pos, {name = "air"})
					return false
				end
			else
				-- Rule 1: Coastline Piling (Destination is solid)
				local above_pos = {x = pos.x, y = pos.y + 1, z = pos.z}
				local above_node = minetest.get_node(above_pos)
				
				if self_vol >= 4 and is_permeable(above_node.name) then
					local pile_vol = math.max(1, math.floor(self_vol / 2))
					self_vol = self_vol - pile_vol
					
					minetest.set_node(above_pos, {
						name = "realistic_fluids:surge_water",
						param2 = 8 - pile_vol
					})
					minetest.get_node_timer(above_pos):start(0.2)
					
					if self_vol <= 0 then
						minetest.set_node(pos, {name = "air"})
						return false
					end
				end
			end
		end

		-- Rule 2: Spreading (Equalize sideways)
		local dirs = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
		for i = 1, 4 do
			if self_vol <= 1 then break end
			local d = dirs[i]
			local n_pos = {x = pos.x + d[1], y = pos.y, z = pos.z + d[2]}
			local n_node = minetest.get_node(n_pos)
			
			if is_permeable(n_node.name) or n_node.name == "realistic_fluids:surge_water" then
				local n_vol = 0
				if n_node.name == "realistic_fluids:surge_water" then
					n_vol = 8 - (n_node.param2 % 8)
				end
				
				if n_vol < self_vol - 1 then
					local flow = math.floor((self_vol - n_vol) / 2)
					if flow >= 1 then
						self_vol = self_vol - flow
						n_vol = n_vol + flow
						minetest.set_node(n_pos, {
							name = "realistic_fluids:surge_water",
							param2 = 8 - n_vol
						})
						minetest.get_node_timer(n_pos):start(0.2)
					end
				end
			end
		end

		-- Rule 4: Decay and Retraction (Ebb & Flow)
		local decay_rate = 1
		if not force or force.strength < 0.2 or force.x == -1 then
			decay_rate = 2 -- faster decay when wind recedes or reverses
		end
		
		self_vol = self_vol - decay_rate
		if self_vol <= 0 then
			minetest.set_node(pos, {name = "air"})
			return false
		else
			minetest.set_node(pos, {
				name = "realistic_fluids:surge_water",
				param2 = 8 - self_vol
			})
			return true -- continue timer
		end
	end,
})
