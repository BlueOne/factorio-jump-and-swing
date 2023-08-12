
--[[ 

Floating Movement
-----------------
Allow players to move in a flying/floating way. Handle animation, rendering, basic physics, basic air thrust

A character might be floating due to different reasons such as jumping or grappling. This is managed here.
Set a character floating via set_source_flag; if they are already floating then there is no need to change the state but we record the flag. 
Set a character not floating via unset_source_flag, if they are still floating due to another reason, they stay floating. 
--]]


-- TODO
-- Support collision checks
-- draw character in front of trees

FloatingMovement = {}

FloatingMovement.on_player_soft_revived_event = "on_player_soft_revived"
--{character : LuaEntity, old_position : MapPosition, new_position : MapPosition}
--{new_unit_number : uint, old_unit_number : uint, new_character : luaEntity, old_character : luaEntity}
FloatingMovement.name_character_suffix = "-jumppack"
FloatingMovement.name_floater_shadow = "jumppack-animation-shadow"
FloatingMovement.landing_collision_snap_radius = 3
FloatingMovement.drag = 0 --0.01
FloatingMovement.brake = 0.001

FloatingMovement.player_thrust = 0.03
FloatingMovement.thrust_max_speed = 0.2

FloatingMovement.collision_damage = 50
FloatingMovement.shadow_base_offset = {x = 1, y = 0.1}

FloatingMovement.no_floating_tiles = {
  ["out-of-map"] = "bounce",
  ["interior-divider"] = "bounce",
  ["se-spaceship-floor"] = "stop",
}

FloatingMovement.bounce_entities = {
  "se-spaceship-wall",
  "se-spaceship-rocket-engine",
  "se-spaceship-ion-engine",
  "se-spaceship-antimatter-engine",
  "se-spaceship-clamp",
}

FloatingMovement.collide_with_environment = true

function FloatingMovement.is_floating(character)
  if character and character.valid then
    return global.floaters[character.unit_number] ~= nil and not global.floaters[character.unit_number].invalid
  else
    return false
  end
end

function FloatingMovement.set_source_flag(character, key)
  local floater = FloatingMovement.from_character(character)
  if not floater then 
    character = FloatingMovement.set_floating(character)
    floater = FloatingMovement.from_character(character)
    floater.source_flags[key] = true
    return character
  end
  local floater = FloatingMovement.from_character(character)
  floater.source_flags[key] = true
end


local function swap_character_air_ground(character)
  if FloatingMovement.character_is_flying_version(character.name) then
    return util.swap_character(character, util.replace(character.name, FloatingMovement.name_character_suffix, ""))
  else
    return util.swap_character(character, character.name .. FloatingMovement.name_character_suffix)
  end
end

local function character_name_swapped(character)
  if FloatingMovement.character_is_flying_version(character.name) then
    return util.replace(character.name, FloatingMovement.name_character_suffix, "")
  else
    return character.name .. FloatingMovement.name_character_suffix
  end
end



local function stop_floating(floater, attempt_landing)
  if not floater then return end
  local character = floater.character
  local damage
  
  if attempt_landing then
    local non_colliding = character.surface.find_non_colliding_position(
      util.replace(character.name, FloatingMovement.name_character_suffix, ""),
      character.position, 
      FloatingMovement.landing_collision_snap_radius, -- radius
      0.2, -- precision
      false --force_to_tile_center
    )
  
    if non_colliding then 
      character.teleport(non_colliding) 
      local landing_tile = character.surface.get_tile(character.position.x, character.position.y)
      FloatingMovement.animate_landing(character, landing_tile, nil, nil, floater.velocity)
    else
      local landing_tile = character.surface.get_tile(character.position.x, character.position.y)
      FloatingMovement.animate_landing(character, landing_tile, nil, nil, floater.velocity)
      
      local position = character.position
      character.teleport(floater.origin_position)
      damage = FloatingMovement.collision_damage
      Event.raise_custom_event(FloatingMovement.on_player_soft_revived_event, {character = character, old_position = position, new_position = character.position})

      if not character or not character.valid then -- player death
        global.floaters[floater.unit_number] = nil
        return
      end
    end
  end
  
  local speed = util.vector_length(floater.velocity)
  local unit_number = character.unit_number

  global.last_float_direction[character.unit_number] = util.vector_normalise(floater.velocity)

  global.floaters[unit_number] = nil

  if FloatingMovement.character_is_flying_version(character.name) then
    local new_character = swap_character_air_ground(character)
    if not new_character or not new_character.valid then return end
    character = new_character
  end

  if damage then 
    character.damage(damage, "neutral", "physical", character)
  end
  if not character or not character.valid then return end

  character.character_running_speed_modifier = 0
  local mod = (speed / character.character_running_speed) - 1
  if mod > 10 then mod = 10 end
  if mod < 0.5 then mod = 0.5 end
  character.character_running_speed_modifier = mod

end


function FloatingMovement.unset_source_flag(unit_number, key, attempt_landing)
  local floater = global.floaters[unit_number]
  if not floater then return end
  floater.source_flags[key] = false
  if util.all_wrong(floater.source_flags) then stop_floating(floater, attempt_landing) end
end

function FloatingMovement.get_source_flag(character, source_flag)
  return FloatingMovement.from_character(character).source_flags[source_flag]
end



function FloatingMovement.character_is_flying_version(name)
  if string.find(name, FloatingMovement.name_character_suffix, 1, true) then return true else return false end
end


function FloatingMovement.tile_is_space(tile)
  return FloatingMovement.space_tiles[tile.name] and true or false
end

function FloatingMovement.on_space_tile(character)
  local tile = character.surface.get_tile(character.position.x, character.position.y)
  return FloatingMovement.tile_is_space(tile)
end

function FloatingMovement.from_character(character)
  local unit_number
  if type(character) == "number" then unit_number = character else unit_number = character.unit_number end
  return global.floaters[unit_number]
end

-- only for remote calls
function FloatingMovement.update(floater)
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

function FloatingMovement.add_altitude(character, delta)
  local floater = FloatingMovement.get_float_data(character)
  if not floater then return end
  
  floater.altitude = floater.altitude + delta
  floater.character.teleport({x = floater.character.position.x, y = floater.character.position.y - delta})
end


function FloatingMovement.update_graphics(floater)
  if floater.character_type == "land" then return end
  
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


local function create_particle_circle(surface, position, nb_particles, particle_name, particle_speed, velocity)
  for orientation=0, 1, 1/nb_particles do
    local fuzzed_orientation = orientation + math.random() * 0.1
    local vector = util.orientation_to_vector(fuzzed_orientation, particle_speed)
    local v = util.copy(vector)
    if velocity and util.vector_length(velocity) > 0.01 then v = util.vectors_add(vector, util.vector_multiply(velocity, 0.1)) end

    surface.create_particle({name = particle_name,
    position = {position.x + vector.x, position.y + vector.y},
    movement = v,
    height = 0.2,
    vertical_speed = 0.1,
    frame_speed = 0.4}
  )
  end
end

local NB_DUST_PUFFS = 14
local NB_WATER_DROPLETS = 30
function FloatingMovement.animate_landing(character, landing_tile, particle_mult, speed_mult, velocity)
  local position = character.position
  if not particle_mult then particle_mult = 1 end
  if not speed_mult then speed_mult = 1 end
  
  if string.find(landing_tile.name, "water", 1, true) then
    -- Water splash
    create_particle_circle(character.surface, position, NB_WATER_DROPLETS * particle_mult, "water-particle", 0.05 * speed_mult, velocity)
    character.surface.play_sound({path="tile-walking/water-shallow", position=position})
  else
    -- Dust
    local particle_name = landing_tile.name .. "-dust-particle"
    if not game.particle_prototypes[particle_name] then
      particle_name = "sand-1-dust-particle"
    end
    create_particle_circle(character.surface, position, NB_DUST_PUFFS * particle_mult, particle_name, 0.1 * speed_mult, velocity)
    local sound_path = "tile-walking/"..landing_tile.name
    if game.is_valid_sound_path(sound_path) then
      character.surface.play_sound({path=sound_path, position=position})
    end
  end
end


function FloatingMovement.get_float_data(character)
  if character and character.valid then
    return global.floaters[character.unit_number]
  end
end

function FloatingMovement.set_floating(character)
  local surface = character.surface
  local player = character.player
  local force_name = character.force.name
  local origin_position = character.position
  
  if not player then return end
  if character.vehicle or global.disabled_on and global.disabled_on[character.unit_number] then return end
  local tile = character.surface.get_tile(character.position.x, character.position.y)

  if FloatingMovement.no_floating_tiles[tile.name] then
    character.print(character, {"jumppack.cant_fly_inside"})
    return
  end
  

  local walking_state = util.copy(character.walking_state)
  local speed = character.character_running_speed
  local velocity = {x=0, y=0}
  local altitude = 0
  if walking_state.walking == true then
    local direction_vector = util.direction_to_vector(walking_state.direction)
    if direction_vector then
      direction_vector = util.vector_normalise(direction_vector)
      velocity = util.vector_multiply(direction_vector, speed)
    end
  end

  if not FloatingMovement.character_is_flying_version(character.name) then
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
    velocity = velocity,
    altitude = altitude,
    origin_position = origin_position,
    source_flags = {},
    thrust = FloatingMovement.player_thrust,
    drag = FloatingMovement.drag
  }


  global.floaters[character.unit_number] = floater
  return character
end


local function movement_collision_bounce(floater)
  local character = floater.character
  local tiles = floater.character.surface.find_tiles_filtered{area = Util.position_to_area(floater.character.position, 1.49)}
  local best_vector
  local best_distance
  for _, tile in pairs(tiles) do
    if not FloatingMovement.no_floating_tiles[tile.name] then
      local v = Util.vectors_delta(floater.character.position, Util.tile_to_position(tile.position))
      local d = Util.vectors_delta_length(Util.tile_to_position(tile.position), floater.character.position)
      if (not best_distance) or d < best_distance then
        best_distance = d
        best_vector = v
      end
    end
  end
  if best_vector then
    floater.velocity = Util.vector_set_length(best_vector, 0.05)
    local new_position = {x = character.position.x + floater.velocity.x*4, y = character.position.y + floater.velocity.y*4}
    character.teleport(new_position)
  else
    local x_part = (floater.character.position.x % 1 + 1) % 1 - 0.5
    local y_part = (floater.character.position.y % 1 + 1) % 1 - 0.5
    floater.velocity = {x = x_part, y = y_part}
    floater.velocity = Util.vector_set_length(floater.velocity, 0.05)
  end
end


Event.register_custom_event(util.on_character_swapped_event, 
---@param event CharacterSwappedEvent
function (event)
  if global.last_float_direction[event.old_unit_number] then
    global.last_float_direction[event.new_unit_number] = global.last_float_direction[event.old_unit_number]
    global.last_float_direction[event.old_unit_number] = nil
  end
end)



local function movement_tick(floater)
  local character = floater.character
  -- Character died or was destroyed
  if not (character and character.valid) then
    global.floaters[floater.unit_number] = nil
    return
  end

  if not floater.velocity.x then error(serpent.line(floater)) end
  floater.velocity.x = floater.velocity.x * (1-FloatingMovement.drag)
  floater.velocity.y = floater.velocity.y * (1-FloatingMovement.drag)
  
  local walking_state = character.walking_state
  if walking_state.walking and not floater.disallow_thrust then -- Player is pressing a direction
    local direction_vector = util.direction_to_vector(walking_state.direction)
    direction_vector = util.vector_normalise(direction_vector)
    local speed = util.vector_dot(floater.velocity, direction_vector)-- util.vector_length(floater.velocity)
    local multiplier = util.max(0, FloatingMovement.thrust_max_speed - speed)
    local thrust = floater.thrust * multiplier
    local thrust_vector = {x = direction_vector.x * thrust, y = direction_vector.y * thrust}
    floater.velocity.x = floater.velocity.x + thrust_vector.x
    floater.velocity.y = floater.velocity.y + thrust_vector.y
  else
    local speed = util.vector_length(floater.velocity)
    local new_speed = speed - FloatingMovement.brake
    if new_speed < 0.001 then
      floater.velocity.x = 0
      floater.velocity.y = 0
    else
      floater.velocity.x = floater.velocity.x * new_speed / speed
      floater.velocity.y = floater.velocity.y * new_speed / speed
    end
  end


  local cliff_collision
  if floater.altitude < 0.2 and FloatingMovement.collide_with_environment then
    local surface = character.surface
    local cliffs = surface.find_entities_filtered{position=character.position, radius=5, type="cliff"}
    for _, e in pairs(cliffs) do
      cliff_collision = true
      local intersection = util.do_rects_intersect(character.bounding_box, e.bounding_box)
      if intersection then
        local normal = util.box_normal(e.bounding_box, character.position)
        floater.velocity = util.vector_diff(floater.velocity, util.vector_multiply(normal, util.vector_dot(normal, floater.velocity)))
      end
    end
  end
  


  local new_position = util.vectors_add(character.position, floater.velocity)

  local target_tile = character.surface.get_tile(new_position.x, new_position.y)
  if target_tile then
    local tile_effect = FloatingMovement.no_floating_tiles[target_tile.name]
    if tile_effect == "bounce" then
      movement_collision_bounce(floater)
    elseif tile_effect == "stop" then
      local bounce_entity = character.surface.find_entities_filtered({name = FloatingMovement.bounce_entities, position = util.tile_to_position(target_tile.position), limit = 1})
      if #bounce_entity == 1 then -- actually, bounce
        movement_collision_bounce(floater)
      else
        -- Instant stop
        character.teleport(new_position)
        stop_floating(character, false)
      end
    elseif FloatingMovement.is_moving(floater) then
      -- Actual Teleport
      local safe_collide
      if cliff_collision then
        safe_collide = util.find_close_noncolliding_position(character.surface, character_name_swapped(character), new_position, 0.5, 0.1, false)
        if safe_collide then 
          character.teleport(safe_collide)
        end
      end
      if not safe_collide then 
        character.teleport(new_position)
      end

      -- environmental hazards
      if floater.altitude < 0.2 and util.vector_length(floater.velocity) > 0.2 and FloatingMovement.collide_with_environment then
        local surface = character.surface
        local simple_entities = surface.find_entities_filtered{position=new_position, radius=2, type="simple-entity"}
        local impact = 0
        for _, e in pairs(simple_entities) do
          if string.find(e.name, "rock") then
            e.destroy()
            impact = impact + 5
          end
        end
        local trees = surface.find_entities_filtered{position=new_position, radius=1, type="tree"}
        for _, e in pairs(trees) do
          e.destroy()
          impact = impact + 1
        end

        if impact > 0 then
          character.damage(impact * 5, "neutral", "physical", character)
          floater.velocity = util.vector_set_length(floater.velocity, math.max(0, util.vector_length(floater.velocity) - impact * 0.2))
        end
        
      end
    end
  else
    floater.velocity.x = floater.velocity.x / 2
    floater.velocity.y = floater.velocity.y / 2
  end
  
  if character and character.valid then 
    FloatingMovement.update_graphics(floater)
  end
end


function FloatingMovement.on_tick(event)
  for _unit_number, floater in pairs(global.floaters) do
    movement_tick(floater)
  end
  

  for _, player in pairs(game.connected_players) do
    local character = player.character
    if character and character.valid then
      if global.last_float_direction[character.unit_number] and not FloatingMovement.is_floating(character) then
        if character.character_running_speed_modifier < 0.05 then
          character.character_running_speed_modifier = 0
          global.last_float_direction[character.unit_number] = nil
        else

          character.character_running_speed_modifier = character.character_running_speed_modifier * 0.97
          local last_dir = global.last_float_direction[character.unit_number]
          if util.vectors_cos_angle(last_dir, util.direction_to_vector(character.walking_state.direction)) < 0.5 then
            character.character_running_speed_modifier = character.character_running_speed_modifier * 0.94
          end
        -- if not character.walking_state.walking then 
        --   character.character_running_speed_modifier = 0
        -- end
        end
      end
    end
  end
end

function FloatingMovement.on_init(event)
  global.floaters = {}
  global.last_float_direction = {}
end
Event.register("on_init", FloatingMovement.on_init)

util.expose_remote_interface(FloatingMovement, "jumppack_floating_movement", {
  "is_floating",
  "set_source_flag",
  "unset_source_flag",
  "get_source_flag",
  "from_character",
  "is_moving",
  "ground_position",
  "get_float_data",
  "update",
})
return FloatingMovement