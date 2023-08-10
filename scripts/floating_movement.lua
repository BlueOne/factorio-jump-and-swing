

-- Handle animation, rendering, basic physics, basic air thrust of floating
-- Does not handle control, cooldowns

-- A character might be floating due to different reasons such as jumping, grappling. This module is intended as an interface. 
-- Set a character floating via set_source_flag; if they are already floating then there is no need to change the state but we record the flag.


-- TODO
-- draw character in front of trees

FloatingMovement = {}

FloatingMovement.on_player_soft_revived_event = "on_player_soft_revived"
--{character : LuaEntity, old_position : MapPosition, new_position : MapPosition}
FloatingMovement.on_character_swapped_event = "on_character_swapped"
--{new_unit_number : uint, old_unit_number : uint, new_character : luaEntity, old_character : luaEntity}
FloatingMovement.name_character_suffix = "-jumppack"
FloatingMovement.name_floater_shadow = "jumppack-animation-shadow"
FloatingMovement.landing_collision_snap_radius = 3
FloatingMovement.drag = 0.01
FloatingMovement.brake = 0.001

FloatingMovement.player_thrust = 0.03
FloatingMovement.thrust_max_speed = 0.3

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

function FloatingMovement.is_floating(character)
  if character and character.valid then
    return global.floaters[character.unit_number] ~= nil
  else
    return false
  end
end

function FloatingMovement.set_source_flag(character, key)
  local floater = FloatingMovement.from_character(character)
  if not floater then 
    character = FloatingMovement.set_floating(character, attempt_landing)
    floater = FloatingMovement.from_character(character)
    floater.source_flags[key] = true
    return character
  end
  local floater = FloatingMovement.from_character(character)
  floater.source_flags[key] = true
end


local function cleanup_animation(floater)
  if floater.sound and floater.sound.valid then
    floater.sound.destroy()
  end
end


local function swap_character(old, new_name)
  if not game.entity_prototypes[new_name] then error("No entity of type "..new_name.." found! "); return end
  local buffer_capacity = 1000
  local position = old.position
  if not FloatingMovement.character_is_flying_version(new_name) then
    position = old.surface.find_non_colliding_position(new_name, position, 1, 0.25, false) or position
  end
  local new = old.surface.create_entity{
    name = new_name,
    position = position,
    force = old.force,
    direction = old.direction,
  }
  
  for _, robot in pairs (old.following_robots) do
    robot.combat_robot_owner = new
  end
  
  new.character_inventory_slots_bonus = old.character_inventory_slots_bonus + buffer_capacity
  old.character_inventory_slots_bonus = old.character_inventory_slots_bonus + buffer_capacity
  
  new.character_running_speed_modifier = old.character_running_speed_modifier
  
  new.walking_state = old.walking_state
  
  local hand_location
  if old.player then
    hand_location = old.player.hand_location
  end
  local vehicle = old.vehicle
  local save_queue = nil
  local crafting_queue_progress = old.crafting_queue_progress
  if old.crafting_queue then
    save_queue = {}
    for i = old.crafting_queue_size, 1, -1 do
      if old.crafting_queue and old.crafting_queue[i] then
        table.insert(save_queue, old.crafting_queue[i])
        old.cancel_crafting(old.crafting_queue[i])
      end
    end
  end
  local opened_self = old.player and old.player.opened_self
  
  if old.logistic_cell and old.logistic_cell.logistic_network and #old.logistic_cell.logistic_network.robots > 0 then
    global.robot_collections = global.robot_collections or {}
    table.insert(global.robot_collections, {character = new, robots = old.logistic_cell.logistic_network.robots})
  end
  
  new.health = old.health
  new.copy_settings(old)
  new.selected_gun_index = old.selected_gun_index
  
  local limit = old.request_slot_count
  local i = 1
  while i <= limit do
    local slot = old.get_personal_logistic_slot(i)
    if slot and slot.name then
      if slot.min then
        if slot.max then
          slot.min = math.min(slot.min, slot.max)
        end
        slot.min = math.max(0, slot.min)
      end
      if slot.max then
        if slot.min then
          slot.max = math.max(slot.min, slot.max)
        end
        slot.max = math.max(0, slot.max)
      end
      new.set_personal_logistic_slot(i, slot)
    end
    i = i + 1
  end
  new.character_personal_logistic_requests_enabled = old.character_personal_logistic_requests_enabled
  new.allow_dispatching_robots = old.allow_dispatching_robots
  
  --to handle when the cursor is holding the result of a cut or copy.  Which is a blueprint (sort of)
  local clipboard_blueprint
  if old.player then
    if (not old.player.hand_location) and old.player.cursor_stack.is_blueprint and old.player.cursor_stack.valid_for_read then
      clipboard_blueprint = old.cursor_stack
    end
  end
  
  if old.player then
    old.player.set_controller{type=defines.controllers.character, character=new}
    if opened_self then new.player.opened = new end
  end
  
  -- need to stop inventory overflow when armor is swapped
  local old_inv = old.get_inventory(defines.inventory.character_armor)
  if old_inv and old_inv[1] and old_inv[1].valid_for_read then
    local new_inv = new.get_inventory(defines.inventory.character_armor)
    new_inv.insert({name = old_inv[1].name, count = 1})
  end
  
  if old.grid then
    for _, old_eq in pairs(old.grid.equipment) do
      local new_eq = new.grid.put{name = old_eq.name, position = old_eq.position}
      if new_eq and new_eq.valid then
        if old_eq.type == "energy-shield-equipment" then
          new_eq.shield = old_eq.shield
        end
        if old_eq.energy then
          new_eq.energy = old_eq.energy
        end
        if old_eq.burner then
          for i = 1, #old_eq.burner.inventory do
            new_eq.burner.inventory.insert(old_eq.burner.inventory[i])
          end
          for i = 1, #old_eq.burner.burnt_result_inventory do
            new_eq.burner.burnt_result_inventory.insert (old_eq.burner.burnt_result_inventory[i])
          end
          
          new_eq.burner.currently_burning = old_eq.burner.currently_burning
          new_eq.burner.heat = old_eq.burner.heat
          new_eq.burner.remaining_burning_fuel = old_eq.burner.remaining_burning_fuel
        end
      end
    end
    new.grid.inhibit_movement_bonus = old.grid.inhibit_movement_bonus
  end
  
  if clipboard_blueprint and clipboard_blueprint.valid_for_read then
    new.player.clear_cursor()
    new.player.activate_paste()
  else
    new.cursor_stack.swap_stack(old.cursor_stack)
  end
  
  if hand_location then
    new.player.hand_location = hand_location
  end
  
  --util.swap_entity_inventories(old, new, defines.inventory.character_armor)
  util.swap_entity_inventories(old, new, defines.inventory.character_main)
  util.swap_entity_inventories(old, new, defines.inventory.character_guns)
  util.swap_entity_inventories(old, new, defines.inventory.character_ammo)
  util.swap_entity_inventories(old, new, defines.inventory.character_trash)
  
  if save_queue then
    for i = #save_queue, 1, -1 do
      local cci = save_queue[i]
      if cci then
        cci.silent = true
        new.begin_crafting(cci)
      end
    end
    new.crafting_queue_progress = math.min(1, crafting_queue_progress)
  end
  new.character_inventory_slots_bonus = new.character_inventory_slots_bonus - buffer_capacity -- needs to be before raise_event
  
  Event.raise(FloatingMovement.on_character_swapped_event, {
    new_unit_number = new.unit_number,
    old_unit_number = old.unit_number,
    new_character = new,
    old_character = old
  })
  if old.valid then
    old.destroy()
  end
  if vehicle then
    if not vehicle.get_driver(new) then
      vehicle.set_driver(new)
    elseif not vehicle.get_passenger(new) then
      vehicle.set_passenger(new)
    end
  end
  
  return new
end


local function swap_character_air_ground(character)
  if FloatingMovement.character_is_flying_version(character.name) then
    return swap_character(character, util.replace(character.name, FloatingMovement.name_character_suffix, ""))
  else
    return swap_character(character, character.name .. FloatingMovement.name_character_suffix)
  end
end


local function stop_floating(floater, attempt_landing)
  if not floater then return end
  local character = floater.character
  
  if attempt_landing then
    local non_colliding = character.surface.find_non_colliding_position(
      util.replace(character.name, FloatingMovement.name_character_suffix, ""), -- name
      character.position, -- center
      FloatingMovement.landing_collision_snap_radius, --radius
      0.1, -- precision
      false --force_to_tile_center
    )
  
    if non_colliding then 
      character.teleport(non_colliding) 
      local landing_tile = character.surface.get_tile(character.position.x, character.position.y)
      FloatingMovement.create_land_effects(character, landing_tile, nil, nil, floater.velocity)
    else
      local landing_tile = character.surface.get_tile(character.position.x, character.position.y)
      FloatingMovement.create_land_effects(character, landing_tile, nil, nil, floater.velocity)
      
      local position = character.position
      character.teleport(floater.origin_position)
      character.tick_of_last_attack = game.tick
      character.tick_of_last_damage = game.tick
      character.damage(FloatingMovement.collision_damage, "enemy", "physical", character)
      Event.raise(FloatingMovement.on_player_soft_revived_event, {character = character, old_position = position, new_position = character.position})

      if not character or not character.valid then -- player death
        cleanup_animation(floater) 
        global.floaters[floater.unit_number] = nil
        return
      end
    end
  end
  
  local speed = util.vector_length(floater.velocity)
  local unit_number = character.unit_number

  global.last_float_direction[character.unit_number] = util.vector_normalise(floater.velocity)

  if FloatingMovement.character_is_flying_version(character.name) then
    local new_character = swap_character_air_ground(character)
    if not new_character then return end
    character = new_character
  end

  character.character_running_speed_modifier = 0
  local mod = (speed / character.character_running_speed) - 1
  if mod > 10 then mod = 10 end
  if mod < 0.5 then mod = 0.5 end
  character.character_running_speed_modifier = mod

  
  cleanup_animation(floater)
  global.floaters[unit_number] = nil
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

function FloatingMovement.is_floating(character)
  if character and character.valid then
    return global.floaters[character.unit_number] ~= nil
  else
    return false
  end
end

function FloatingMovement.ground_position(character)
  local floater = FloatingMovement.from_character(character)
  if not floater then error("Taking ground position of a non floating character. ") end
  local pos = character.position
  return {x = pos.x, y = pos.y + floater.altitude}
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
function FloatingMovement.create_land_effects(character, landing_tile, particle_mult, speed_mult, velocity)
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
    character_print(character, {"jumppack.cant_fly_inside"})
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


Event.addListener(FloatingMovement.on_character_swapped_event, function (event)
  if global.last_float_direction[event.old_unit_number] then
    global.last_float_direction[event.new_unit_number] = global.last_float_direction[event.old_unit_number]
    global.last_float_direction[event.old_unit_number] = nil
  end
end, true)



local function movement_tick(floater)
  local character = floater.character
  -- Character died or was destroyed
  if not (character and character.valid) then
    global.floaters[floater.unit_number] = nil
    return cleanup_animation(floater)
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
      character.teleport(new_position)
    end
  else
    floater.velocity.x = floater.velocity.x / 2
    floater.velocity.y = floater.velocity.y / 2
  end
  
  FloatingMovement.update_graphics(floater)
end


function FloatingMovement.on_tick(event)
  for _unit_number, floater in pairs(global.floaters) do
    movement_tick(floater)
  end
  
  -- Re-attach personal construction bots after character swap
  if global.robot_collections then
    for k, robot_collection in pairs(global.robot_collections) do
      if not (robot_collection.character and robot_collection.character.valid) then
        global.robot_collections[k] = nil
      elseif robot_collection.character.logistic_cell and robot_collection.character.logistic_cell.valid
      and robot_collection.character.logistic_cell.logistic_network and robot_collection.character.logistic_cell.logistic_network.valid then
        for _, robot in pairs(robot_collection.robots) do
          if robot.valid and robot.surface == robot_collection.character.surface then
            robot.logistic_network = robot_collection.character.logistic_cell.logistic_network
          end
        end
        global.robot_collections[k] = nil
      end
    end
  end

  for _, player in pairs(game.connected_players) do
    if player.character then
      local character = player.character
      if global.last_float_direction[character.unit_number] and not FloatingMovement.is_floating(character) then
        character.character_running_speed_modifier = character.character_running_speed_modifier * 0.97
        local last_dir = global.last_float_direction[character.unit_number]
        if util.vectors_cos_angle(last_dir, util.direction_to_vector(character.walking_state.direction)) < 0.5 then
          character.character_running_speed_modifier = character.character_running_speed_modifier * 0.94
        end
        -- if not character.walking_state.walking then 
        --   character.character_running_speed_modifier = 0
        -- end

        if character.character_running_speed_modifier < 0.05 then
          character.character_running_speed_modifier = 0
          global.last_float_direction[character.unit_number] = nil
        end
      end
    end
  end
end

function FloatingMovement.on_init(event)
  global.floaters = {}
  global.last_float_direction = {}
end
Event.addListener("on_init", FloatingMovement.on_init, true)

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