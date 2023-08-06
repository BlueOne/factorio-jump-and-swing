local Jumppack = {}

--TODO: interaction with vehicles!

Jumppack.on_character_swapped_event = "on_character_swapped"
--{new_unit_number = uint, old_unit_number = uint, new_character = luaEntity, old_character = luaEntity}

Jumppack.name_event = "jumppack"
Jumppack.name_character_suffix = "-jumppack"
Jumppack.name_jumppack_shadow = "jumppack-animation-shadow"
Jumppack.drag = 0.01
Jumppack.brake = 0.001
Jumppack.thrust_multiplier_before_move = 0.001
Jumppack.shadow_base_offset = {x = 1, y = 0.1}
Jumppack.altitude_target = 3
Jumppack.altitude_base_increase = 0.01
Jumppack.altitude_percentage_increase = 0.15
Jumppack.altitude_decrease = 0.3
Jumppack.jump_base_thrust = 0.15 -- excluding suit thrust
Jumppack.jump_thrust_multiplier = 5 -- multiplies suit thrust
Jumppack.landing_collision_snap_radius = 3
Jumppack.toggle_cooldown = 0
Jumppack.movement_boost_duration = 50
Jumppack.collision_damage = 50
Jumppack.movement_bonus = 0.5
Jumppack.movement_fallof_duration = 10


Jumppack.jumppacks_to_add = {}

Jumppack.no_jumppacking_tiles = {
  ["out-of-map"] = "bounce",
  ["interior-divider"] = "bounce",
  ["se-spaceship-floor"] = "stop",
}

Jumppack.bounce_entities = {
  "se-spaceship-wall",
  "se-spaceship-rocket-engine",
  "se-spaceship-ion-engine",
  "se-spaceship-antimatter-engine",
  "se-spaceship-clamp",
}

Jumppack.states = {
  walking = 1,
  rising = 2,
  stopping = 3,
}

Jumppack.space_tiles = {["se-space"] = "se-space"}


function Jumppack.tile_is_space(tile)
  return Jumppack.space_tiles[tile.name] and true or false
end

function Jumppack.on_space_tile(character)
  local tile = character.surface.get_tile(character.position.x, character.position.y)
  return Jumppack.tile_is_space(tile)
end

function Jumppack.from_character(character)
  return global.jumppacks[character.unit_number]
end

function Jumppack.is_moving(jumppack)
  return jumppack.velocity.x < -0.001 or jumppack.velocity.x > 0.001 or jumppack.velocity.y < -0.001 or jumppack.velocity.y > 0.001
end


function Jumppack.get_jumppack_for_character(data)
  if data.character and data.character.valid then
    return global.jumppacks[data.character.unit_number]
  end
end

function Jumppack.is_jumppacking(data)
  if data.character and data.character.valid then
    return global.jumppacks[data.character.unit_number] ~= nil
  else
    return false
  end
end


local function get_jumppack_state(jumppack)
  if not jumppack then
    return Jumppack.states.walking
  else
    return jumppack.state
  end
end

local function character_print(character, message)
  if character.player then
    character.player.print(message)
  end
end


-- Instantly swap to walking state
function Jumppack.land_and_start_walking(jumppack)
  local surface = jumppack.character.surface
  local character = jumppack.character
  local land_character
  if Jumppack.character_is_flying_version(character.name) then
    local non_colliding = surface.find_non_colliding_position(
      util.replace(character.name, Jumppack.name_character_suffix, ""), -- name
      character.position, -- center
      Jumppack.landing_collision_snap_radius, --radius
      0.1, -- precision
      false --force_to_tile_center
    )
    if non_colliding then 
      character.teleport(non_colliding) 
      local landing_tile = surface.get_tile(character.position.x, character.position.y)
      JumppackGraphicsSound.create_land_effects(character, landing_tile)
    else
      local landing_tile = surface.get_tile(character.position.x, character.position.y)
      JumppackGraphicsSound.create_land_effects(character, landing_tile)

      character.teleport(jumppack.origin_position)
      character.damage(Jumppack.collision_damage, "enemy", "physical", character)
      if not character or not character.valid then -- player death
        JumppackGraphicsSound.cleanup(jumppack) 
        global.jumppacks[jumppack.unit_number] = nil
        return
      end
      character.tick_of_last_attack = game.tick
      character.tick_of_last_damage = game.tick
    end
    if character.player then
      -- Set cooldown only if there's no higher cooldown already in place
      if not global.player_toggle_cooldown[character.player.index] or global.player_toggle_cooldown[character.player.index] < game.tick + Jumppack.toggle_cooldown then
        global.player_toggle_cooldown[character.player.index] = game.tick + Jumppack.toggle_cooldown
      end
    end

    land_character = Jumppack.swap_to_land_character(character)
  else
    land_character = character
  end
  global.jumppacks[jumppack.unit_number] = nil

  JumppackGraphicsSound.cleanup(jumppack)
end

local function movement_collision_bounce(jumppack)
  local character = jumppack.character
  local tiles = jumppack.character.surface.find_tiles_filtered{area = Util.position_to_area(jumppack.character.position, 1.49)}
  local best_vector
  local best_distance
  for _, tile in pairs(tiles) do
    if not Jumppack.no_jumppacking_tiles[tile.name] then
      local v = Util.vectors_delta(jumppack.character.position, Util.tile_to_position(tile.position))
      local d = Util.vectors_delta_length(Util.tile_to_position(tile.position), jumppack.character.position)
      if (not best_distance) or d < best_distance then
        best_distance = d
        best_vector = v
      end
    end
  end
  if best_vector then
    jumppack.velocity = Util.vector_set_length(best_vector, 0.05)
    local new_position = {x = character.position.x + jumppack.velocity.x*4, y = character.position.y + jumppack.velocity.y*4}
    character.teleport(new_position)
  else
    local x_part = (jumppack.character.position.x % 1 + 1) % 1 - 0.5
    local y_part = (jumppack.character.position.y % 1 + 1) % 1 - 0.5
    jumppack.velocity = {x = x_part, y = y_part}
    jumppack.velocity = Util.vector_set_length(jumppack.velocity, 0.05)
  end
end

local function movement_tick(jumppack, disallow_thrust)
  local character = jumppack.character

  -- drag
  jumppack.velocity.x = jumppack.velocity.x * (1-Jumppack.drag)
  jumppack.velocity.y = jumppack.velocity.y * (1-Jumppack.drag)

  local walking_state = character.walking_state
  if walking_state.walking and not disallow_thrust then -- Player is pressing a direction
    local direction_vector = util.direction_to_vector(walking_state.direction)
    direction_vector = util.vector_normalise(direction_vector)
    local thrust
    thrust = jumppack.thrust
    local thrust_vector = {x = direction_vector.x * thrust, y = direction_vector.y * thrust}
    jumppack.velocity.x = jumppack.velocity.x + thrust_vector.x
    jumppack.velocity.y = jumppack.velocity.y + thrust_vector.y

  else
    local speed = util.vector_length(jumppack.velocity)
    local new_speed = speed - Jumppack.brake
    if new_speed < 0.001 then
      jumppack.velocity.x = 0
      jumppack.velocity.y = 0
    else
      jumppack.velocity.x = jumppack.velocity.x * new_speed / speed
      jumppack.velocity.y = jumppack.velocity.y * new_speed / speed
    end
  end



  local new_position = {x = character.position.x + jumppack.velocity.x, y = character.position.y + jumppack.velocity.y}

  local target_tile = jumppack.character.surface.get_tile(new_position.x, new_position.y)
  if target_tile then
    local tile_effect = Jumppack.no_jumppacking_tiles[target_tile.name]
    if tile_effect == "bounce" then
      movement_collision_bounce(jumppack)
    elseif tile_effect == "stop" then
      local bounce_entity = character.surface.find_entities_filtered({name = Jumppack.bounce_entities, position = util.tile_to_position(target_tile.position), limit = 1})
      if #bounce_entity == 1 then -- actually, bounce
        movement_collision_bounce(jumppack)
      else
        -- Instant stop
        character.teleport(new_position)
        Jumppack.land_and_start_walking(jumppack)
      end
    elseif Jumppack.is_moving(jumppack) then
      character.teleport(new_position)
    end
  else
    jumppack.velocity.x = jumppack.velocity.x / 2
    jumppack.velocity.y = jumppack.velocity.y / 2
  end
end

local function on_tick_flying(jumppack)
  movement_tick(jumppack)
  if jumppack.character.valid then -- Could have instantly landed in movement_tick
    JumppackGraphicsSound.update_graphics(jumppack)
    -- JumppackGraphicsSound.update_sound(jumppack)
    -- JumppackGraphicsSound.create_smoke(jumppack.character)
  end
end

local function on_tick_rising(jumppack)
  if jumppack.altitude < Jumppack.altitude_target then
    local difference = Jumppack.altitude_target - jumppack.altitude
    local change =  math.min(difference, difference * Jumppack.altitude_percentage_increase + Jumppack.altitude_base_increase)
    jumppack.altitude = jumppack.altitude + change
    jumppack.character.teleport({x = jumppack.character.position.x, y = jumppack.character.position.y - change})
  else
    jumppack.state = Jumppack.states.stopping
  end

  on_tick_flying(jumppack)
end

local function on_tick_stopping(jumppack)
  if jumppack.altitude > 0 then
    jumppack.altitude = math.max(0, jumppack.altitude - Jumppack.altitude_decrease)
    jumppack.character.teleport({x = jumppack.character.position.x, y = jumppack.character.position.y + Jumppack.altitude_decrease})
    movement_tick(jumppack)
    if jumppack.character.valid then -- Could have instantly landed in movement_tick
      JumppackGraphicsSound.update_graphics(jumppack)
      -- JumppackGraphicsSound.update_sound(jumppack)
    end
  else -- Reached the floor
    local player = jumppack.character.player
    Jumppack.land_and_start_walking(jumppack)
    if player.character and player.character.valid then
      global.player_movement_bonus_expire[player.index] = game.tick + Jumppack.movement_boost_duration
      player.character.character_running_speed_modifier = Jumppack.movement_bonus
    end
  end
end


function Jumppack.on_tick_jumppack(jumppack)

  -- Character died or was destroyed
  if not (jumppack.character and jumppack.character.valid) then
    global.jumppacks[jumppack.unit_number] = nil
    return JumppackGraphicsSound.cleanup(jumppack)
  end

  local state = jumppack.state
  if state == Jumppack.states.flying then
    on_tick_flying(jumppack)
  elseif state == Jumppack.states.rising then
    on_tick_rising(jumppack)
  elseif state == Jumppack.states.stopping then
    on_tick_stopping(jumppack)
  end -- else is "walking", do nothing
end

function Jumppack.on_tick(event)
  for _unit_number, jumppack in pairs(global.jumppacks) do
    Jumppack.on_tick_jumppack(jumppack)
  end

  for unit_number, jumppack in pairs(Jumppack.jumppacks_to_add) do
    global.jumppacks[unit_number] = jumppack
  end
  Jumppack.jumppacks_to_add = {}

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
    if global.player_movement_bonus_expire[player.index] and global.player_movement_bonus_expire[player.index] - game.tick < Jumppack.movement_fallof_duration then
      if player.character then
        player.character_running_speed_modifier = player.character_running_speed_modifier - Jumppack.movement_bonus / Jumppack.movement_fallof_duration
      else
        global.player_movement_bonus_expire[player.index] = nil
      end
    end
    if global.player_movement_bonus_expire[player.index] and global.player_movement_bonus_expire[player.index] <= game.tick then
      global.player_movement_bonus_expire[player.index] = nil
    end
  end
end
Event.addListener(defines.events.on_tick, Jumppack.on_tick)

local function swap_character(old, new_name)
  if not game.entity_prototypes[new_name] then return end
  local buffer_capacity = 1000
  local position = old.position
  if not Jumppack.character_is_flying_version(new_name) then
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

  raise_event(Jumppack.on_character_swapped_event, {
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

function Jumppack.swap_to_land_character(old_character)
  return swap_character(old_character, util.replace(old_character.name, Jumppack.name_character_suffix, ""))
end

function Jumppack.swap_to_flying_character(old_character)
  return swap_character(old_character, old_character.name .. Jumppack.name_character_suffix)
end


function Jumppack.get_current_thrust(character)
  return 0.01
end

function Jumppack.character_is_flying_version(name)
  if string.find(name, Jumppack.name_character_suffix, 1, true) then return true else return false end
end

-- Creates a new jumppack object and swaps character.
-- This method always assumes the character starts from walking state.
function Jumppack.start_on_character(character, thrust, default_state)
  default_state = default_state or Jumppack.states.rising
  local player = character.player
  local force_name = character.force.name

  local origin_position = character.position

  if not player then return end
  if character.vehicle or global.disabled_on and global.disabled_on[character.unit_number] then return end

  local tile = character.surface.get_tile(character.position.x, character.position.y)
  if Jumppack.no_jumppacking_tiles[tile.name] then
    character_print(character, {"jumppack.cant_fly_inside"})
    return
  end

  local walking_state = character.walking_state
  local new_character
  if default_state == Jumppack.states.rising or default_state == Jumppack.states.flying then
    if not Jumppack.character_is_flying_version(character.name) then
      if character.player then
        -- Set cooldown only if there's no higher cooldown already in place
        if not global.player_toggle_cooldown[character.player.index] or global.player_toggle_cooldown[character.player.index] < game.tick + Jumppack.toggle_cooldown then
          global.player_toggle_cooldown[character.player.index] = game.tick + Jumppack.toggle_cooldown
        end
      end
      new_character = Jumppack.swap_to_flying_character(character)
    
      if not new_character then
        for _, jumppack in pairs(global.jumppacks) do
          if jumppack.character == character then return end
        end
        new_character = character
      end
    end
  else
    if Jumppack.character_is_flying_version(character.name) then
      new_character = Jumppack.swap_to_land_character(character)
      if not new_character then
        for _, jumppack in pairs(global.jumppacks) do
          if jumppack.character == character then return end
        end
        new_character = character
      end
    end
  end
  local jumppack = {
    state = default_state,
    character = new_character or character,
    unit_number = new_character and new_character.unit_number or character.unit_number,
    force_name = force_name,
    player_index = player.index,
    velocity = {x=0, y=0},
    altitude = 0,
    thrust = thrust,
    character_type = default_state == Jumppack.states.rising or default_state == Jumppack.states.flying and "fly" or "land",
    origin_position = origin_position
  }
  if walking_state.walking == true then
    local direction_vector = util.direction_to_vector(walking_state.direction)
    if direction_vector then
      direction_vector = util.vector_normalise(direction_vector)
      local thrust = Jumppack.thrust_multiplier_before_move * jumppack.thrust -- get from equipment
      local base_thrust = Jumppack.jump_base_thrust + jumppack.character.character_running_speed_modifier * 0.3
      jumppack.velocity.x = direction_vector.x * (base_thrust + Jumppack.jump_thrust_multiplier * thrust)
      jumppack.velocity.y = direction_vector.y * (base_thrust + Jumppack.jump_thrust_multiplier * thrust)
    end
  end
  JumppackGraphicsSound.update_graphics(jumppack)
  -- JumppackGraphicsSound.update_sound(jumppack)
  Jumppack.jumppacks_to_add[jumppack.unit_number] = jumppack
  return jumppack
end


function Jumppack.on_player_joined_game(event)
  local player = game.players[event.player_index]
  if player and player.connected and player.character then
    if Jumppack.character_is_flying_version(player.character.name) then
      local character = player.character
      local thrust = Jumppack.get_current_thrust(character)
      local jumppack = Jumppack.start_on_character(character, thrust, Jumppack.states.flying)
      if jumppack then
        jumppack.altitude = Jumppack.altitude_target
      end
    end
  end
end
Event.addListener(defines.events.on_player_joined_game, Jumppack.on_player_joined_game)


function Jumppack.stop_jumppack(jumppack)
  jumppack.state = Jumppack.states.stopping
end

function Jumppack.toggle(character)
  local jumppack = Jumppack.from_character(character)
  local state = get_jumppack_state(jumppack)

  if state == Jumppack.states.walking then
    local pid = character.player.index
    --if global.player_movement_bonus_expire[pid] then
    --  return false
    --end

    local thrust = Jumppack.get_current_thrust(character)
    Jumppack.start_on_character(character, thrust, Jumppack.states.rising)
    return true
  else -- rising or flying
    jumppack.state = Jumppack.states.stopping
    return false
  end
end

function Jumppack.on_jumppack_keypress(event)
  if event.player_index and game.players[event.player_index] and game.players[event.player_index].connected then
    local player = game.players[event.player_index]
    if player.character then
      if (not global.player_toggle_cooldown[event.player_index]) or global.player_toggle_cooldown[event.player_index] < game.tick then
        Jumppack.toggle(player.character)
      else
        player.play_sound{path="utility/cannot_build"}
      end
    end
  end
end
Event.addListener(Jumppack.name_event, Jumppack.on_jumppack_keypress)

-- As far as I can tell, when flying you can only enter vehicles via scripts.
-- For example, ironclad.
function Jumppack.on_player_driving_changed_state(event)
  local player = game.get_player(event.player_index)
  if not player or not player.character or not player.character.valid then return end
  local jumppack = Jumppack.from_character(player.character)
  if not jumppack or not jumppack.character.valid then return end

  if Jumppack.character_is_flying_version(jumppack.character.name) then
    Jumppack.land_and_start_walking(jumppack)
  end
end
script.on_event(defines.events.on_player_driving_changed_state, Jumppack.on_player_driving_changed_state)


function Jumppack.on_init(event)
  global.jumppacks = {}
  global.player_toggle_cooldown = {}
  global.player_movement_bonus_expire = {}
end
Event.addListener("on_init", Jumppack.on_init, true)

return Jumppack
