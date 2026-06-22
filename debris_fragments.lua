-- debris_fragments.lua
-- Falling block debris entity with physics simulation

local settings = realistic_rising_floods.settings.debris

local math_random = math.random
local math_floor = math.floor
local math_abs = math.abs

-- ============================================================
-- Debris Fragment Entity
-- ============================================================

minetest.register_entity("realistic_rising_floods:debris", {
	initial_properties = {
		visual = "cube",
		visual_size = {x = 0.25, y = 0.25, z = 0.25},
		textures = {"default_dirt.png", "default_dirt.png",
		            "default_dirt.png", "default_dirt.png",
		            "default_dirt.png", "default_dirt.png"},
		physical = false,  -- We handle our own physics
		collide_with_objects = false,
		pointable = false,
		static_save = false,  -- Don't persist across restarts
		glow = 0,
	},

	-- Custom fields
	_velocity = {x = 0, y = 0, z = 0},
	_angular_vel = {x = 0, y = 0, z = 0},
	_rotation = {x = 0, y = 0, z = 0},
	_lifetime = 4.0,
	_age = 0,
	_gravity = 9.8,
	_bounce = 0.3,
	_resting = false,
	_rest_time = 0,

	on_activate = function(self, staticdata, dtime_s)
		self.object:set_armor_groups({immortal = 1})

		-- Parse staticdata for texture and settings
		if staticdata and staticdata ~= "" then
			local parts = staticdata:split("|")
			if parts[1] then
				local tex = parts[1]
				self.object:set_properties({
					textures = {tex, tex, tex, tex, tex, tex},
				})
			end
			if parts[2] then
				local scale = tonumber(parts[2]) or 0.25
				-- Add some random variation to fragment size
				local vary = scale * (0.6 + math_random() * 0.8)
				self.object:set_properties({
					visual_size = {x = vary, y = vary, z = vary},
				})
			end
		end
	end,

	on_step = function(self, dtime, moveresult)
		self._age = self._age + dtime

		-- Despawn after lifetime
		if self._age >= self._lifetime then
			self.object:remove()
			return
		end

		-- Fade out in last 1 second (shrink the visual)
		local remaining = self._lifetime - self._age
		if remaining < 1.0 then
			local s = remaining  -- 1.0 -> 0.0
			local props = self.object:get_properties()
			local base = props.visual_size.x
			self.object:set_properties({
				visual_size = {x = base * s, y = base * s, z = base * s},
			})
		end

		-- If resting on ground, just count down and stop
		if self._resting then
			self._rest_time = self._rest_time + dtime
			if self._rest_time > 1.5 then
				-- Just remove after resting a bit
				self.object:remove()
				return
			end
			return
		end

		local pos = self.object:get_pos()
		if not pos then return end

		local vel = self._velocity
		local grav = self._gravity
		local bounce = self._bounce

		-- Apply gravity
		vel.y = vel.y - grav * dtime

		-- Air drag (slight)
		vel.x = vel.x * 0.995
		vel.z = vel.z * 0.995

		-- New position
		local new_x = pos.x + vel.x * dtime
		local new_y = pos.y + vel.y * dtime
		local new_z = pos.z + vel.z * dtime

		-- Ground collision: check the node below
		local ground_pos = {x = math_floor(new_x + 0.5), y = math_floor(new_y), z = math_floor(new_z + 0.5)}
		local ground_node = minetest.get_node(ground_pos)
		local ground_def = minetest.registered_nodes[ground_node.name]

		if ground_def and ground_def.walkable and vel.y < 0 then
			-- Bounce!
			new_y = ground_pos.y + 1.0
			vel.y = -vel.y * bounce

			-- Friction on bounce
			vel.x = vel.x * 0.6
			vel.z = vel.z * 0.6

			-- If velocity is very small, come to rest
			if math_abs(vel.y) < 0.5 then
				self._resting = true
				vel.y = 0
				vel.x = 0
				vel.z = 0
			end
		end

		-- Wall collision: check X direction
		local wall_x_pos = {x = math_floor(new_x + 0.5 + (vel.x > 0 and 0.3 or -0.3)),
		                     y = math_floor(new_y + 0.5),
		                     z = math_floor(new_z + 0.5)}
		local wall_x_node = minetest.get_node(wall_x_pos)
		local wall_x_def = minetest.registered_nodes[wall_x_node.name]
		if wall_x_def and wall_x_def.walkable then
			vel.x = -vel.x * bounce * 0.5
		end

		-- Wall collision: check Z direction
		local wall_z_pos = {x = math_floor(new_x + 0.5),
		                     y = math_floor(new_y + 0.5),
		                     z = math_floor(new_z + 0.5 + (vel.z > 0 and 0.3 or -0.3))}
		local wall_z_node = minetest.get_node(wall_z_pos)
		local wall_z_def = minetest.registered_nodes[wall_z_node.name]
		if wall_z_def and wall_z_def.walkable then
			vel.z = -vel.z * bounce * 0.5
		end

		self._velocity = vel
		self.object:set_pos({x = new_x, y = new_y, z = new_z})

		-- Rotation animation
		local rot = self._rotation
		local avel = self._angular_vel
		rot.x = rot.x + avel.x * dtime
		rot.y = rot.y + avel.y * dtime
		rot.z = rot.z + avel.z * dtime
		self._rotation = rot

		-- Slow down rotation over time
		avel.x = avel.x * 0.98
		avel.y = avel.y * 0.98
		avel.z = avel.z * 0.98
		self._angular_vel = avel

		-- Luanti doesn't natively support entity rotation for cubes via set_rotation
		-- in all versions, but we set yaw which works universally
		self.object:set_yaw(rot.y)
	end,

	get_staticdata = function(self)
		return ""  -- Don't persist
	end,
})

-- ============================================================
-- Utility: spawn debris from a broken block
-- ============================================================

function realistic_rising_floods.spawn_debris(pos, node_name, burst_velocity)
	if not settings.enabled then return end

	local def = minetest.registered_nodes[node_name]
	if not def then return end

	-- Get the block's texture
	local texture = "default_dirt.png"  -- fallback
	if def.tiles then
		local t = def.tiles[1]
		if type(t) == "table" then
			texture = t.name or texture
		elseif type(t) == "string" then
			texture = t
		end
	end

	-- Determine fragment count based on material
	local frag_min = settings.fragment_min
	local frag_max = settings.fragment_max

	-- Material-specific tuning
	local groups = def.groups or {}
	local scale = settings.fragment_scale
	local bounce = settings.bounce

	if groups.cracky then
		-- Stone-like: more fragments, smaller, less bounce
		frag_min = frag_min + 1
		frag_max = frag_max + 2
		scale = scale * 0.8
		bounce = bounce * 0.5
	elseif groups.snappy or groups.choppy then
		-- Wood-like: fewer, larger fragments
		frag_min = math.max(2, frag_min - 1)
		frag_max = math.max(3, frag_max - 1)
		scale = scale * 1.3
		bounce = bounce * 0.4
	elseif groups.crumbly then
		-- Dirt/sand: many tiny fragments
		frag_min = frag_min + 2
		frag_max = frag_max + 3
		scale = scale * 0.6
		bounce = bounce * 0.2
	end

	local count = math_random(frag_min, frag_max)
	burst_velocity = burst_velocity or settings.burst_speed

	for i = 1, count do
		-- Random burst direction (hemisphere above break point)
		local angle = math_random() * math.pi * 2
		local elevation = math_random() * 0.8 + 0.2  -- mostly upward
		local speed = burst_velocity * (0.5 + math_random() * 0.5)

		local vx = math.cos(angle) * speed * (1 - elevation)
		local vy = speed * elevation
		local vz = math.sin(angle) * speed * (1 - elevation)

		-- Slight offset so fragments don't all start at exact same point
		local offset_x = (math_random() - 0.5) * 0.4
		local offset_y = math_random() * 0.3
		local offset_z = (math_random() - 0.5) * 0.4

		local spawn_pos = {
			x = pos.x + offset_x,
			y = pos.y + offset_y,
			z = pos.z + offset_z,
		}

		local staticdata = texture .. "|" .. tostring(scale)
		local obj = minetest.add_entity(spawn_pos, "realistic_rising_floods:debris", staticdata)

		if obj then
			local ent = obj:get_luaentity()
			if ent then
				ent._velocity = {x = vx, y = vy, z = vz}
				ent._gravity = settings.gravity
				ent._bounce = bounce
				ent._lifetime = settings.fragment_lifetime * (0.7 + math_random() * 0.6)
				ent._angular_vel = {
					x = (math_random() - 0.5) * 10,
					y = (math_random() - 0.5) * 10,
					z = (math_random() - 0.5) * 10,
				}
			end
		end
	end
end

minetest.log("action", "[realistic_rising_floods] Debris fragments loaded.")
