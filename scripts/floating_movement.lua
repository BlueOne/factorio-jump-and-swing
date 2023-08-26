

-- Floating Movement
-- -----------------
-- Allow players to move in a flying/floating way. Handle graphics of floating state and landing animation, basic physics via xy and z velocity, basic air thrust via player input, velocity preservation upon landing

-- A character might be floating due to different reasons such as jumping or grappling. This is managed here:
-- Set a character floating via set_floating_flag; if they are already floating then there is no need to change the state but we record the flag and potentially properties. Set a character not floating via unset_floating_flag, if they are still floating due to another reason, they stay floating. 
-- The floating properties of a character might differ due to the reason they are floating, e.g. one might want different brake values when grappling or jumping. This is managed via the set_properties and get_property_value functions, see below. 


FloatingMovement = {}


-- Custom Events
-- Character swapped event: see utils.
--`{character : LuaEntity, old_position : MapPosition, new_position : MapPosition}`

-- Raised when altitude becomes zero. 
--`{character : LuaEntity, position : MapPosition}`
FloatingMovement.on_character_touch_ground = "on_character_touch_ground"

-- Raised when a landing is attempted, but no suitable landing spot is found, for example in water or dense factory areas. 
--`{new_unit_number : uint, old_unit_number : uint, new_character : luaEntity, old_character : luaEntity}`
FloatingMovement.on_player_soft_revived_event = "on_player_soft_revived"

FloatingMovement.name_character_suffix = "-floating"
FloatingMovement.name_floater_shadow = "jump-and-swing-animation-shadow"


FloatingMovement.shadow_base_offset = {x = 1, y = 0.1}
FloatingMovement.landing_collision_snap_radius = 3
FloatingMovement.default_gravity = -0.02



-- Brake is an absolute velocity, drag is a ratio
FloatingMovement.default_drag = 0 --0.01
FloatingMovement.default_brake = 0.00

FloatingMovement.default_player_thrust = 0.01
FloatingMovement.default_thrust_max_speed = 0.5

FloatingMovement.default_collision_damage = 50
FloatingMovement.default_collide_with_environment = true


FloatingMovement.collision_types = {"cliff", "tree", "simple-entity"}


function FloatingMovement.is_floating(character)
  local floater = FloatingMovement.from_character(character)
  if floater and floater.valid then
    return global.floaters[character.unit_number] ~= nil and global.floaters[character.unit_number].valid
  else
    return false
  end
end

-- You might want FloatingMovement.is_floating instead
local function character_is_flying_version(name)
  if string.find(name, FloatingMovement.name_character_suffix, 1, true) then return true else return false end
end

-- can fail, returns character if valid, nil otherwise
function FloatingMovement.set_floating_flag(character, key)
  local floater = FloatingMovement.from_character(character)
  if not floater then 
    character = FloatingMovement.set_floating(character, key)
    if not character then return end
    floater = FloatingMovement.from_character(character)
    return character
  end
  floater.floating_flags[key] = true
  return character
end



--[[
Example for the layered properties concept as used here:
```lua
set_properties(character, "grapple", "f", {drag=0})
set_properties(character, "jump", "d", {drag=0.1})

get_properties(character, "drag") == 0.1
```
Internally, we now have 
```lua
properties = { d_jump = {key="jump", drag=0.1}, f_grapple = {key="grapple", drag=0} }
```
We use the value of the 'd' layer, as it comes before the 'f' layer in lexicographic order. Use 
]]
function FloatingMovement.set_properties(floater, key, layer_name, properties)
  util.set_layered_properties(floater.properties, layer_name, key, properties)
end

function FloatingMovement.unset_properties(floater, key)
  util.unset_layered_properties(floater.properties, key)
end

function FloatingMovement.get_property_value(floater, property)
  return util.get_layered_properties_value(floater.properties, property)
end

for _, k in pairs({"set_properties", "unset_properties", "get_property_value"}) do
  FloatingMovement[k.."_character"] = function(character, ...)
    if not FloatingMovement.is_floating(character) then return end
    local floater = FloatingMovement.from_character(character)
    return FloatingMovement[k](floater, ...)
  end
end


local function swap_character_air_ground(character)
  if character_is_flying_version(character.name) then
    return util.swap_character(character, util.replace(character.name, FloatingMovement.name_character_suffix, ""))
  else
    return util.swap_character(character, character.name .. FloatingMovement.name_character_suffix)
  end
end

function FloatingMovement.character_ground_name(character_name)
  if character_is_flying_version(character_name) then
    return util.replace(character_name, FloatingMovement.name_character_suffix, "")
  else
    return character_name
  end
end

function FloatingMovement.character_floating_name(character_name)
  if character_is_flying_version(character_name) then
    return character_name
  else
    return character_name .. FloatingMovement.name_character_suffix
  end
end

local function character_name_swapped(character)
  if character_is_flying_version(character.name) then
    return util.replace(character.name, FloatingMovement.name_character_suffix, "")
  else
    return character.name .. FloatingMovement.name_character_suffix
  end
end



local function stop_floating(floater, attempt_landing, last_key)
  if not floater or not floater.valid or not floater.character or not floater.character.valid then return end
  local damage
  floater.valid = false
  
  local unit_number = floater.unit_number
  local character = floater.character
  
  if character and character.valid and attempt_landing then
    local surface = character.surface
    local non_colliding = util.find_close_noncolliding_position(
      surface,
      util.replace(character.name, FloatingMovement.name_character_suffix, ""),
      character.position, 
      FloatingMovement.landing_collision_snap_radius, -- radius
      0.2, -- precision
    false)
    
    if non_colliding then 
      character.teleport(non_colliding) 
      local landing_tile = surface.get_tile(character.position.x, character.position.y)
      util.animate_landing(character, landing_tile, nil, nil)
    else
      local landing_tile = surface.get_tile(character.position.x, character.position.y)
      util.animate_landing(character, landing_tile, nil, nil)
      
      local position = character.position
      character.teleport(floater.safe_position)
      damage = FloatingMovement.get_property_value(floater, "collision_damage")
      
      if not character or not character.valid then -- player death
        global.floaters[floater.unit_number] = nil
        return
      else
        Event.raise_custom_event(FloatingMovement.on_player_soft_revived_event, {unit_number = character.unit_number, character = character, old_position = position, new_position = character.position})
        if global.bunnyhop_stored_data[character.unit_number] then
          global.bunnyhop_stored_data[character.unit_number] = nil
        end
      end
    end
  end
  
  
  global.movement_decay[unit_number] = {character = character, last_float_direction = util.vector_normalise(floater.velocity)}
  global.floaters[unit_number] = nil
  
  local speed = util.vector_length(floater.velocity)
  
  if not character or not character.valid then return end
  
  global.bunnyhop_stored_data[unit_number] = {tick=game.tick, velocity = floater.velocity, last_floating_reason=last_key}
  if character_is_flying_version(character.name) then
    local new_character = swap_character_air_ground(character)
    if not new_character or not new_character.valid then return end
    character = new_character
    -- if not character_is_flying_version(character.name) then
    --   local position = character.surface.find_non_colliding_position(character.name, character.position, 1, 0.25, false)
    -- if position then character.teleport(character.position) end
    -- end
  end
  
  if damage then 
    character.damage(damage, "neutral", "physical", character)
  end
  if not character or not character.valid then return end
  
  character.character_running_speed_modifier = 0
  local mod = (speed / character.character_running_speed) - 1
  if mod > 10 then mod = 10 end
  if mod < 0 then mod = 0 end
  character.character_running_speed_modifier = mod
  
end

-- if attempt_landing is set, try to find a non colliding position for the character if it stops floating from this
function FloatingMovement.unset_floating_flag(unit_number, key, attempt_landing)
  local floater = global.floaters[unit_number]
  if not floater or not floater.valid then return end
  floater.floating_flags[key] = false
  FloatingMovement.unset_properties(floater, key)
  if util.all_wrong(floater.floating_flags) then stop_floating(floater, attempt_landing, key) end
end

function FloatingMovement.has_floating_flag(character, floating_flag)
  return FloatingMovement.from_character(character).floating_flags[floating_flag]
end


function FloatingMovement.from_character(character)
  if not character then return end
  local unit_number
  if type(character) == "number" then unit_number = character else unit_number = character.unit_number end
  return global.floaters[unit_number]
end

-- only for remote calls
function FloatingMovement.update_float_data(floater)
  if not floater.velocity or not floater.velocity.x then error("A mod attempted to set data of floating movement with wrong format! ") end
  global.floaters[floater.unit_number] = floater
end


function FloatingMovement.is_moving(floater)
  return floater.velocity.x < -0.001 or floater.velocity.x > 0.001 or floater.velocity.y < -0.001 or floater.velocity.y > 0.001
end


function FloatingMovement.ground_position(character)
  local floater = FloatingMovement.from_character(character)
  local pos = character.position
  local altitude = 0
  if floater then altitude = floater.altitude end
  return {x = pos.x, y = pos.y + altitude}
end

function FloatingMovement.add_altitude_character(character, delta)
  local floater = FloatingMovement.get_float_data(character)
  if not floater then return end
  FloatingMovement.add_altitude(floater, delta)
end

function FloatingMovement.add_altitude(floater, delta)
  local new_altitude = floater.altitude + delta
  local character = floater.character


  if new_altitude > 0.001 then
    floater.character.teleport(util.vectors_add(floater.character.position, {x=0, y=-delta}))
    floater.altitude = new_altitude
  else
    floater.character.teleport(util.vectors_add(floater.character.position, {x=0, y=floater.altitude}))
    floater.altitude = 0
    -- TODO: Move to start of on_tick
    Event.raise_custom_event("on_character_touch_ground", {character=character, position=character.position, floater = floater})
    floater.vel_z = 0
  end
end


function FloatingMovement.update_graphics(floater)
  local frame = floater.character.orientation * 100
  
  if (not floater.animation_shadow) or not rendering.is_valid(floater.animation_shadow) then
    floater.animation_shadow = rendering.draw_animation{
      animation = FloatingMovement.name_floater_shadow,
      surface = floater.character.surface,
      target = floater.character,
      target_offset = {x = FloatingMovement.shadow_base_offset.x + floater.altitude, y = FloatingMovement.shadow_base_offset.y + floater.altitude},
      animation_speed = 0,
      animation_offset = frame,
      tint = {1., 1., 1., 0.5}
    }
  else
    rendering.set_target(floater.animation_shadow, floater.character,
    {x = FloatingMovement.shadow_base_offset.x + floater.altitude, y = FloatingMovement.shadow_base_offset.y + floater.altitude})
    rendering.set_animation_offset(floater.animation_shadow, frame)
  end
  
end


function FloatingMovement.get_float_data(character)
  if character and character.valid then
    return global.floaters[character.unit_number]
  end
end

function FloatingMovement.set_floating(character, key)
  local player = character.player
  local safe_position = character.position
  
  if not player then return end
  if character.vehicle or global.disabled_on and global.disabled_on[character.unit_number] then return end
  local tile = character.surface.get_tile(character.position.x, character.position.y)
  
  -- if tile.name == "out-of-map" then
  --   return
  -- end
  
  
  local velocity
  local altitude = 0
  local stv = global.bunnyhop_stored_data[character.unit_number]
  if stv ~= nil then
    local allow_bunnyhop = stv.last_floating_reason ~= key
    if game.tick - stv.tick < 5 and allow_bunnyhop then
      velocity = stv.velocity
      velocity = util.vector_multiply(velocity, 0.95)
    end
    global.bunnyhop_stored_data[character.unit_number] = nil
  end
  if not velocity then
    if character.walking_state.walking == true then
      local speed = character.character_running_speed
      local direction_vector = util.direction_to_vector(character.walking_state.direction)
      if direction_vector then
        direction_vector = util.vector_normalise(direction_vector)
        velocity = util.vector_multiply(direction_vector, speed)
      end
    end
  end
  if not velocity then velocity = {x=0, y=0} end
  
  if not character_is_flying_version(character.name) then
    local new_character = swap_character_air_ground(character)
    if new_character then 
      character = new_character 
    else 
      for _, floater in pairs(global.floaters) do
        if floater.character == character then return end
      end
    end
  end
  
  local floater = {
    character = character,
    unit_number = character.unit_number,
    velocity = velocity, -- x,y
    vel_z = 0,
    altitude = altitude,
    safe_position = safe_position,
    floating_flags = { [key] = true},
    properties = {},
    valid = true
  }
  
  FloatingMovement.set_properties(floater, "default", "z", {
    drag = FloatingMovement.default_drag,
    brake = FloatingMovement.default_brake,
    thrust = FloatingMovement.default_player_thrust,
    thrust_max_speed = FloatingMovement.default_thrust_max_speed,
    collision_damage = FloatingMovement.default_collision_damage,
    collide_with_environment = MovementConfig.collide_with_environment(),
    gravity = FloatingMovement.default_gravity
  })
  
  global.floaters[character.unit_number] = floater
  return character
end



Event.register_custom_event(util.on_character_swapped_event, 
---@param event CharacterSwappedEvent
function (event)
  if global.movement_decay[event.old_unit_number] then
    global.movement_decay[event.new_unit_number] = global.movement_decay[event.old_unit_number]
    global.movement_decay[event.new_unit_number].character = event.new_character
    global.movement_decay[event.old_unit_number] = nil
  end
end)



local function movement_tick(floater)
  -- game.print(serpent.line(util.vector_length(floater.velocity)))
  local character = floater.character
  -- Character died or was destroyed
  if not (character and character.valid) or not floater and floater.valid then
    global.floaters[floater.unit_number] = nil
    return
  end

  local drag = FloatingMovement.get_property_value(floater, "drag")
  floater.velocity = util.vector_multiply(floater.velocity, 1-drag)
  
  if character.walking_state.walking and not FloatingMovement.get_property_value(floater, "disallow_thrust") then -- Player is pressing a direction
    local direction_vector = util.direction_to_vector(character.walking_state.direction or 0)
    -- local speed = util.vector_dot(floater.velocity, direction_vector)-- util.vector_length(floater.velocity)
    local speed_in_walking_direction = util.vector_dot(direction_vector, floater.velocity)
    local thrust_max_speed = FloatingMovement.get_property_value(floater, "thrust_max_speed")
    local speed_ratio = speed_in_walking_direction / thrust_max_speed
    local multiplier = math.min(math.max(0, 1 - speed_ratio), 1)
    local thrust = FloatingMovement.get_property_value(floater, "thrust") * multiplier
    local thrust_vector = util.vector_multiply(direction_vector, thrust)
    floater.velocity = util.vectors_add(floater.velocity, thrust_vector)
  else
    local speed = util.vector_length(floater.velocity)
    local brake = FloatingMovement.get_property_value(floater, "brake")
    local new_speed = speed - brake
    if new_speed < 0.001 then
      floater.velocity = {x=0, y=0}
    else
      floater.velocity = util.vector_multiply(floater.velocity, new_speed / speed)
    end
  end
  
  
  local cliff_collision
  local collide_with_environment = FloatingMovement.get_property_value(floater, "collide_with_environment")
  local close_entities
  local impact = 0
  if floater.altitude < 0.2 and collide_with_environment then
    local surface = character.surface
    close_entities = surface.find_entities_filtered{position=character.position, radius=5, type=FloatingMovement.collision_types}
    for _, e in pairs(close_entities) do
      if e.type == "cliff" then
        local intersection = util.do_rects_intersect(character.bounding_box, util.scale_rect(e.bounding_box, 1.1))
        if intersection then
          cliff_collision = true
          local normal = util.box_normal(e.bounding_box, character.position)
          local delta_v = util.vector_multiply(normal, util.vector_dot(normal, floater.velocity))
          floater.velocity = util.vector_diff(floater.velocity, delta_v)
          impact = impact + util.vector_length(delta_v)
        end
      end
    end
  end
  if impact > 0.4 then 
    character.damage(impact * 5, "neutral", "physical", character)
    if not character.valid then return end
  end
  
  
  local new_position = util.vectors_add(character.position, floater.velocity)
  local new_ground_position = {x=new_position.x, y = new_position.y + floater.altitude}
  
  local target_tile = character.surface.get_tile(new_ground_position.x, new_ground_position.y)
  if target_tile and target_tile.name == "out-of-map" then
    floater.velocity = util.movement_collision_bounce(floater.character) or floater.velocity
  elseif target_tile and FloatingMovement.is_moving(floater) then
    if not target_tile.collides_with("player-layer") and game.tick%60==0 then
      local safe_position = character.surface.find_non_colliding_position(FloatingMovement.character_ground_name(character.name), character.position, 2, 0.2, true)
      if safe_position then 
        floater.safe_position = safe_position
      end
    end
    -- Actual Teleport
    local safe_collide
    if cliff_collision then
      safe_collide = util.find_close_noncolliding_position(character.surface, character_name_swapped(character), new_position, 0.5, 0.2, false)
      if safe_collide then 
        character.teleport(safe_collide)
      end
    end
    if not safe_collide then 
      character.teleport(new_position)
    end

    if string.find(target_tile.name, "water") and game.tick % 3 == 0 and floater.altitude < 0.4 then
      character.surface.create_entity{name="water-splash", position=character.position, force="neutral"}
      -- for i = 1, 6 do
      --   local angle = i / 6 + math.random()/10
      --   local angle_vec = util.orientation_to_vector(angle, 0.05)
      --   character.surface.create_particle{name="shallow-water-particle", position=character.position, movement=angle_vec, height=0, vertical_speed=0.1, frame_speed=0.5} 
      -- end
    end
    
    -- environmental hazards
    if floater.altitude < 0.2 and util.vector_length(floater.velocity) > 0.2 and collide_with_environment then
      if not close_entities then 
        close_entities = surface.find_entities_filtered{position=character.position, radius=5, type=FloatingMovement.collision_types}
      end
      FloatingMovement.collision_with_destructibles(floater, new_position, close_entities)
    end
  else
    floater.velocity = util.vector_multiply(floater.velocity, 1/2)
  end

  -- z coordinate
  if character and character.valid then
    if floater.altitude > 0 or floater.vel_z > 0 then
      local gravity = FloatingMovement.get_property_value(floater, "gravity")
      floater.vel_z = floater.vel_z + gravity
      FloatingMovement.add_altitude(floater, floater.vel_z)
    end
  end

  if character and character.valid then 
    FloatingMovement.update_graphics(floater)
  end
end

function FloatingMovement.collision_with_destructibles(floater, new_position, close_entities)
  local character = floater.character
  local surface = character.surface
  local impact = 0
  for _, e in pairs(close_entities) do
    if e.valid and e.type == "simple-entity" and string.find(e.name, "rock") and util.vector_distance_squared(character.position, e.position) < 4 then
      e.die()
      impact = impact + 5
    end
  end
  for _, e in pairs(close_entities) do
    if e.valid and e.type == "tree" and util.vector_distance_squared(character.position, e.position) < 1 then
      e.die()
      impact = impact + 1
    end
  end
  
  if impact > 0 then
    character.damage(impact * 5, "neutral", "physical", character)
    floater.velocity = util.vector_set_length(floater.velocity, math.max(0, util.vector_length(floater.velocity) - impact * 0.2))
  end
end


function FloatingMovement.walk_speed_decay(unit_number, decay_data)
  if decay_data then 
    if decay_data.character and decay_data.character.valid then
      local character = decay_data.character
      if not FloatingMovement.is_floating(character) then
        if character.character_running_speed_modifier < 0.05 then
          character.character_running_speed_modifier = 0
          global.movement_decay[unit_number] = nil
        else
          character.character_running_speed_modifier = character.character_running_speed_modifier * 0.97
          local last_dir = decay_data.last_float_direction
          local walk_dir = util.direction_to_vector(character.walking_state.direction)
          local multiplier = util.vectors_cos_angle(last_dir, walk_dir)
          if multiplier < 0 then multiplier = 0 end
          character.character_running_speed_modifier = character.character_running_speed_modifier * multiplier
          decay_data.last_float_direction = walk_dir
        end
      end
    else
      global.movement_decay[unit_number] = nil
    end
  end
end


function FloatingMovement.on_tick(event)
  Event.raise_custom_event("on_pre_movement_tick", event)

  for _, floater in pairs(global.floaters) do
    movement_tick(floater)
  end
  
  
  for unit_number, decay_data in pairs(global.movement_decay) do
    FloatingMovement.walk_speed_decay(unit_number, decay_data)
  end
end
Event.register(defines.events.on_tick, FloatingMovement.on_tick)


function FloatingMovement.on_init()
  global.floaters = {}
  global.movement_decay = {}
  global.bunnyhop_stored_data = {}
end
Event.register("on_init", FloatingMovement.on_init)

Event.register(defines.events.on_pre_player_died, function(event)
  local character = game.players[event.player_index].character
  if character and character.valid then
    global.movement_decay[character.unit_number] = nil
    global.bunnyhop_stored_data[character.unit_number] = nil
  end
end)

-- This can only happen via script
function FloatingMovement.on_player_driving_changed_state(event)
  local player = game.get_player(event.player_index)
  if not player or not player.character or not player.character.valid then return end
  local character = player.character
  if FloatingMovement.is_floating(character) then
    local floater = FloatingMovement.get_float_data(character)
    Event.raise_custom_event("on_floating_movement_canceled", {character=character})
    stop_floating(floater)
  end
end
Event.register(defines.events.on_player_driving_changed_state, FloatingMovement.on_player_driving_changed_state)


util.expose_remote_interface(FloatingMovement, "jump-and-swing_floating_movement", {
  "is_floating",
  "set_floating_flag",
  "unset_floating_flag",
  "get_floating_flag",
  "from_character",
  "is_moving",
  "ground_position",
  "get_float_data",
  "update_float_data",
})
return FloatingMovement