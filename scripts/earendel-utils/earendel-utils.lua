
-- License: Earendel FMLDOL 
-- https://docs.google.com/document/d/1z-6hZQekEHOu1Pk4z-V5LuwlHnveFLJGTjVAtjYHwMU
-- Copied and modified from jetpack mod, with permission from Earendel

local util = require("__core__/lualib/util.lua")

util.min = math.min
util.max = math.max
util.floor = math.floor
util.abs = math.abs
util.sqrt = math.sqrt
util.sin = math.sin
util.cos = math.cos
util.atan = math.atan
util.pi = math.pi
util.remove = table.remove
util.insert = table.insert
util.str_gsub = string.gsub


-- Jetpack Bounce
-----------------------------------------------------------


util.no_floating_tiles = {
  ["out-of-map"] = true,
}

function util.movement_collision_bounce(character)
  local tiles = character.surface.find_tiles_filtered{area = Util.position_to_area(character.position, 1.49)}
  local best_vector
  local best_distance
  for _, tile in pairs(tiles) do
    if not util.no_floating_tiles[tile.name] then
      local v = Util.vectors_delta(character.position, Util.tile_to_position(tile.position))
      local d = Util.vectors_delta_length(Util.tile_to_position(tile.position), character.position)
      if (not best_distance) or d < best_distance then
        best_distance = d
        best_vector = v
      end
    end
  end
  if best_vector then
    local new_velocity = Util.vector_set_length(best_vector, 0.05)
    local new_position = Util.vectors_add(character.position, Util.vector_multiply(new_velocity, 4))
    character.teleport(new_position)
    return new_velocity
  else
    local x_part = (character.position.x % 1 + 1) % 1 - 0.5
    local y_part = (character.position.y % 1 + 1) % 1 - 0.5
    local new_velocity = {x = x_part, y = y_part}
    new_velocity = Util.set_vector_length(new_velocity, 0.05)
    return new_velocity
  end
end



-- Swap or transfer properties of entities
-----------------------------------------------------------

function util.get_robot_collection(old, new)
  if old.logistic_cell and old.logistic_cell.logistic_network and #old.logistic_cell.logistic_network.robots > 0 then
    return {entity = new, robots = old.logistic_cell.logistic_network.robots}
  end
end

function util.reattach_robot_collection(robot_collection)
  if not robot_collection then return end
  local entity = robot_collection.entity
  if entity.logistic_cell and entity.logistic_cell.valid
  and entity.logistic_cell.logistic_network and entity.logistic_cell.logistic_network.valid then
    for _, robot in pairs(robot_collection.robots) do
      if robot.valid and robot.surface == entity.surface then
        robot.logistic_network = entity.logistic_cell.logistic_network
      end
    end
  end
end

function util.copy_logistic_slots(old, new)
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
end



function util.copy_grid(grid_a, grid_b)
  for _, old_eq in pairs(grid_a.equipment) do
    local new_eq = grid_b.put{name = old_eq.name, position = old_eq.position}
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
end


util.on_character_swapped_event = "on_character_swapped"


-- TODO: Put this back the way it was.
-- Does not check if the target location is safe to spawn the new character, if collision masks change. 
function util.swap_character(old, new_name)
  if not game.entity_prototypes[new_name] then error("No entity of type "..new_name.." found! "); return end
  local position = old.position
  local new = old.surface.create_entity{
    name = new_name,
    position = position,
    force = old.force,
    direction = old.direction,
  }
  
  new.copy_settings(old)
  
  for _, k in pairs({
    "character_running_speed_modifier",
    "character_crafting_speed_modifier",
    "character_mining_speed_modifier", 
    "character_additional_mining_categories", 
    "character_running_speed_modifier", "character_build_distance_bonus", 
    "character_item_drop_distance_bonus", 
    "character_reach_distance_bonus", 
    "character_resource_reach_distance_bonus", 
    "character_item_pickup_distance_bonus", 
    "character_loot_pickup_distance_bonus", 
    "character_inventory_slots_bonus", 
    "character_trash_slot_count_bonus", 
    "character_maximum_following_robot_count_bonus", 
    "character_health_bonus", 
    "character_personal_logistic_requests_enabled",
    "health",
    "selected_gun_index",
    "walking_state",
    "shooting_state",
    "character_personal_logistic_requests_enabled",
    "allow_dispatching_robots",
    "tick_of_last_attack",
    "tick_of_last_damage",
    "direction",
    "orientation"
  }) do
    new[k] = old[k]
  end
  
  -- Bots
  local robot_collection = util.get_robot_collection(old, new)
  util.reattach_robot_collection(robot_collection)
  
  for _, robot in pairs (old.following_robots) do
    robot.combat_robot_owner = new
  end
  util.copy_logistic_slots(old, new)
  new.character_personal_logistic_requests_enabled = old.character_personal_logistic_requests_enabled
  new.allow_dispatching_robots = old.allow_dispatching_robots
  
  
  -- Stop overflow when manipulating inventory, crafting-queue and armor
  local buffer_capacity = 1000
  new.character_inventory_slots_bonus = old.character_inventory_slots_bonus + buffer_capacity
  old.character_inventory_slots_bonus = old.character_inventory_slots_bonus + buffer_capacity
  
  
  -- Store variables for restoring after switching character controller
  local hand_location
  if old.player then
    hand_location = old.player.hand_location
  end
  local vehicle = old.vehicle
  local opened_self = old.player and old.player.opened_self
  local saved_queue, queue_progress = util.store_crafting_queue(old)
  
  
  local clipboard_blueprint
  local cursor_is_copy_paste
  if old.player then
    local player = old.player
    if (not hand_location) and player.cursor_stack.valid_for_read and player.cursor_stack.is_blueprint and player.cursor_stack.is_blueprint_setup() then
      clipboard_blueprint = old.cursor_stack
      local inv = #player.get_inventory(defines.inventory.character_main)
      local cleaned = player.clear_cursor()
      if cleaned and inv == #player.get_inventory(defines.inventory.character_main) then
        cursor_is_copy_paste = true
      end
    end
  end



  if old.player then
    old.player.set_controller{type=defines.controllers.character, character=new}
    if opened_self then new.player.opened = new end
  end
  
  
  -- Inventory and equipment  
  util.swap_entity_inventories(old, new, defines.inventory.character_armor)
  if old.grid then
    util.copy_grid(old.grid, new.grid)
    new.grid.inhibit_movement_bonus = old.grid.inhibit_movement_bonus
  end
  util.swap_entity_inventories(old, new, defines.inventory.character_main)
  util.swap_entity_inventories(old, new, defines.inventory.character_guns)
  util.swap_entity_inventories(old, new, defines.inventory.character_ammo)
  util.swap_entity_inventories(old, new, defines.inventory.character_trash)
  
  util.restore_crafting_queue(new, saved_queue, queue_progress)
  new.character_inventory_slots_bonus = new.character_inventory_slots_bonus - buffer_capacity 
  
  -- Cursor
  if clipboard_blueprint and clipboard_blueprint.valid_for_read then
    if cursor_is_copy_paste then
      new.player.activate_paste()
    else
      new.cursor_stack.swap_stack(old.cursor_stack)
    end
  elseif old.cursor_stack and old.cursor_stack.valid_for_read then
    if not (hand_location == nil and (old.cursor_stack.type == "deconstruction-item" or (old.cursor_stack.type == "blueprint"
    and not old.cursor_stack.is_blueprint_setup()))) then
      -- swap, unless this is a deconstruction planner or blank blueprint, created via shortcut 
      new.cursor_stack.swap_stack(old.cursor_stack)
    end
  end  
  new.player.hand_location = hand_location
  
  local event_table = {
    new_unit_number = new.unit_number,
    old_unit_number = old.unit_number,
    new_character = new,
    old_character = old
  }
  Event.raise_custom_event(util.on_character_swapped_event, event_table)
  
  
  
  if old.valid then
    old.destroy()
  end
  if vehicle then
    if not vehicle.get_driver() then
      vehicle.set_driver(new)
    elseif not vehicle.get_passenger() then
      vehicle.set_passenger(new)
    end
  end
  
  return new
end


-- Make sure there is enough inventory space (e.g. increase character.character_inventory_slots_bonus) when using this
function util.store_crafting_queue(character)
  local saved_queue
  local queue_progress = character.crafting_queue_progress
  if character.crafting_queue then
    saved_queue = {}
    local i = character.crafting_queue_size
    while i > 0 do
      table.insert(saved_queue, character.crafting_queue[i])
      character.cancel_crafting(character.crafting_queue[i])
      i = character.crafting_queue_size
    end  
  end
  return saved_queue, queue_progress
end


function util.restore_crafting_queue(character, saved_queue, queue_progress)
  if saved_queue then 
    for _, items in pairs(saved_queue) do
      items.silent = true
      character.begin_crafting(items)
    end
    character.crafting_queue_progress = math.min(1, queue_progress)
  end
end

function util.transfer_burner_direct (burner_a, burner_b)
  if burner_a and burner_b then
    burner_b.heat = burner_a.heat
    if burner_a.currently_burning then
      burner_b.currently_burning = burner_a.currently_burning.name
      burner_b.remaining_burning_fuel = burner_a.remaining_burning_fuel
    end
    if burner_a.inventory and burner_b.inventory then
      util.swap_inventories(burner_a.inventory, burner_b.inventory)
    end
    if burner_a.burnt_result_inventory and burner_b.burnt_result_inventory then
      util.swap_inventories(burner_a.burnt_result_inventory, burner_b.burnt_result_inventory)
    end
  end
end

function util.transfer_burner (entity_a, entity_b)
util.transfer_burner_direct (entity_a.burner, entity_b.burner)
end

function util.copy_inventory (inv_a, inv_b, probability)
  if not probability then probability = 1 end
  if inv_a and inv_b then
      local contents = inv_a.get_contents()
      for item_type, item_count in pairs(contents) do
          if probability == 1 or probability > math.random() then
            inv_b.insert({name=item_type, count=item_count})
          end
      end
  end
end

function util.move_inventory_items (inv_a, inv_b)
-- move all items from inv_a to inv_b
-- preserves item data but inv_b MUST be able to accept the items or they are lost.
-- inventory A is cleared.
for i = 1, util.min(#inv_a, #inv_b) do
  if inv_a[i] and inv_a[i].valid then
    inv_b.insert(inv_a[i])
  end
end
inv_a.clear()
end

function util.transfer_inventory_filters (entity_a, entity_b, inventory_type)
  local inv_a = entity_a.get_inventory(inventory_type)
  local inv_b = entity_b.get_inventory(inventory_type)
  if inv_a.supports_filters() and inv_b.supports_filters() then
      for i = 1, util.min(#inv_a, #inv_b) do
          local filter = inv_a.get_filter(i)
          if filter then
              inv_b.set_filter(i, filter)
          end
      end
  end
end

function util.copy_equipment_grid (entity_a, entity_b)
if not (entity_a.grid and entity_b.grid) then return end
for _, a_eq in pairs(entity_a.grid.equipment) do
  local b_eq = entity_b.grid.put{name = a_eq.name, position = a_eq.position}
  if b_eq and b_eq.valid then
    if a_eq.type == "energy-shield-equipment" then
      b_eq.shield = a_eq.shield
    end
    if a_eq.energy then
      b_eq.energy = a_eq.energy
    end
    if a_eq.burner then
      for i = 1, #a_eq.burner.inventory do
        b_eq.burner.inventory.insert(a_eq.burner.inventory[i])
      end
      for i = 1, #a_eq.burner.burnt_result_inventory do
        b_eq.burner.burnt_result_inventory.insert (a_eq.burner.burnt_result_inventory[i])
      end

      b_eq.burner.currently_burning = a_eq.burner.currently_burning
      b_eq.burner.heat = a_eq.burner.heat
      b_eq.burner.remaining_burning_fuel = a_eq.burner.remaining_burning_fuel
    end
  end
end
entity_b.grid.inhibit_movement_bonus = entity_a.grid.inhibit_movement_bonus
end

function util.transfer_equipment_grid (entity_a, entity_b)
if not (entity_a.grid and entity_b.grid) then return end
util.copy_equipment_grid (entity_a, entity_b)
entity_a.grid.clear()
end

function util.swap_entity_inventories(entity_a, entity_b, inventory)
  util.swap_inventories(entity_a.get_inventory(inventory), entity_b.get_inventory(inventory))
end

function util.swap_inventories(inv_a, inv_b)
  if inv_a.is_filtered() then
    for i = 1, math.min(#inv_a, #inv_b) do
      inv_b.set_filter(i, inv_a.get_filter(i))
    end
  end
  for i = 1, math.min(#inv_a, #inv_b)do
    inv_b[i].swap_stack(inv_a[i])
  end
end



-- Graphics
------------------------------------------------------------

function util.create_particle_circle(surface, position, nb_particles, particle_name, particle_speed)
  for orientation=0, 1, 1/nb_particles do
    local fuzzed_orientation = orientation + math.random() * 0.1
    local vector = util.orientation_to_vector(fuzzed_orientation, particle_speed)
    -- local v = util.copy(vector)
    -- if velocity and util.vector_length(velocity) > 0.01 then v = util.vectors_add(vector, util.vector_multiply(velocity, 1)) end

    surface.create_particle{
      name = particle_name,
      position = util.vectors_add(position, vector),
      movement = vector,
      height = 0.2,
      vertical_speed = 0.1,
      frame_speed = 0.4
    }
  end
end

local NB_DUST_PUFFS = 14
local NB_WATER_DROPLETS = 30
function util.animate_landing(character, landing_tile, particle_mult, speed_mult)
  local position = character.position
  if not particle_mult then particle_mult = 1 end
  if not speed_mult then speed_mult = 1 end
  
  if string.find(landing_tile.name, "water", 1, true) then
    -- Water splash
    util.create_particle_circle(character.surface, position, NB_WATER_DROPLETS * particle_mult, "water-particle", 0.05 * speed_mult)
    character.surface.play_sound({path="tile-walking/water-shallow", position=position})
  else
    -- Dust
    local particle_name = landing_tile.name .. "-dust-particle"
    if not game.particle_prototypes[particle_name] then
      particle_name = "sand-1-dust-particle"
    end
    util.create_particle_circle(character.surface, position, NB_DUST_PUFFS * particle_mult, particle_name, 0.1 * speed_mult)
    local sound_path = "tile-walking/"..landing_tile.name
    if game.is_valid_sound_path(sound_path) then
      character.surface.play_sound({path=sound_path, position=position})
    end
  end
end


-- Unrelated to Factorio API
------------------------------------------------------------


function util.shallow_copy (t) -- shallow-copy a table
  if type(t) ~= "table" then return t end
  local meta = getmetatable(t)
  local target = {}
  for k, v in pairs(t) do target[k] = v end
  setmetatable(target, meta)
  return target
end

function util.remove_from_table(list, item)
  local index = 0
  for _,_item in ipairs(list) do
      if item == _item then
          index = _
          break
      end
  end
  if index > 0 then
      util.remove(list, index)
  end
end

function util.shuffle (tbl)
size = #tbl
for i = size, 1, -1 do
  --local rand = 1 + math.floor(size * (math.random() - 0.0000001))
  local rand = math.random(size)
  tbl[i], tbl[rand] = tbl[rand], tbl[i]
end
return tbl
end

function util.random_from_array (tbl)
--return tbl[1 + math.floor(#tbl * (math.random() - 0.0000001))]
return tbl[math.random(#tbl)]
end

function util.area_add_position(area, position)
local area2 = table.deepcopy(area)
for k1, v1 in pairs(area2) do
  for k2, v2 in pairs(v1) do
    if k2 == 1 or k2 == "x" then
      v1[k2] = v2 + (position.x or position[1])
    elseif k2 == 2 or k2 == "y" then
      v1[k2] = v2 + (position.y or position[2])
    end
  end
end
return area2
end

function util.area_extend(area, range)
local area2 = table.deepcopy(area)
for k1, v1 in pairs(area2) do
  local m = 1
  if k1 == 1 or k1 == "left_top" then
    m = -1
  end
  for k2, v2 in pairs(v1) do
    v1[k2] = v2 + range * m
  end
end
return area2
end

function util.position_to_area(position, radius)
return {{x = position.x - radius, y = position.y - radius},
        {x = position.x + radius, y = position.y + radius}}
end

function util.position_to_tile(position)
  return {x = math.floor(position.x), y = math.floor(position.y)}
end

function util.tile_to_position(tile_position)
  return {x = tile_position.x+0.5, y = tile_position.y+0.5}
end

function util.position_to_xy_string(position)
  return util.xy_to_string(position.x, position.y)
end

function util.xy_to_string(x, y)
  return util.floor(x) .. "_" .. util.floor(y)
end

function util.lerp(a, b, alpha)
  return a + (b - a) * alpha
end

function util.lerp_angles(a, b, alpha)
  local da = b - a

  if da <= -0.5 then
      da = da + 1
  elseif da >= 0.5 then
      da = da - 1
  end
  local na = a + da * alpha
  if na < 0 then
      na = na + 1
  elseif na >= 1 then
      na = na - 1
  end
  return na
end

function util.step_angles(a, b, step)
  local da = b - a

  if da <= -0.5 then
      da = da + 1
  elseif da >= 0.5 then
      da = da - 1
  end
  local na = a + Util.sign(da) * math.min(math.abs(da), step)
  if na < 0 then
      na = na + 1
  elseif na >= 1 then
      na = na - 1
  end
  return na
end

function util.array_to_vector(array)
  return {x = array[1], y = array[2]}
end

-- deprecated, use vector_diff instead
function util.vectors_delta(a, b) -- from a to b
if not a and b then return 0 end
return {x = b.x - a.x, y = b.y - a.y}
end

function util.vector_diff(a, b) -- from a to b
return {x = a.x - b.x, y = a.y - b.y}
end

function util.vectors_delta_length(a, b)
  return util.vector_length_xy(b.x - a.x, b.y - a.y)
end

function util.vector_length(a)
  return util.sqrt(a.x * a.x + a.y * a.y)
end

function util.vector_length_xy(x, y)
  return util.sqrt(x * x + y * y)
end

function util.vector_dot(a, b)
  return a.x * b.x + a.y * b.y
end

function util.vector_multiply(a, multiplier)
  return {x = a.x * multiplier, y = a.y * multiplier}
end

function util.vector_dot_projection(a, b)
  local n = util.vector_normalise(a)
  local d = util.vector_dot(n, b)
  return {x = n.x * d, y = n.y * d}
end

function util.vector_normalise(a)
  local length = util.vector_length(a)
  return {x = a.x/length, y = a.y/length}
end

function util.vector_set_length(a, length)
  local old_length = util.vector_length(a)
  if old_length == 0 then return {x = 0, y = -length} end
  return {x = a.x/old_length*length, y = a.y/old_length*length}
end

function util.orientation_from_to(a, b)
  return util.vector_to_orientation_xy(b.x - a.x, b.y - a.y)
end

function util.orientation_to_vector(orientation, length)
  return {x = length * util.sin(orientation * 2 * util.pi), y = -length * util.cos(orientation * 2 * util.pi)}
end

function util.rotate_vector(orientation, a)
  return {
    x = -a.y * util.sin(orientation * 2 * util.pi) + a.x * util.sin((orientation + 0.25) * 2 * util.pi),
    y = a.y * util.cos(orientation * 2 * util.pi) -a.x * util.cos((orientation + 0.25) * 2 * util.pi)}
end

function util.vectors_add(a, b)
  return {x = a.x + b.x, y = a.y + b.y}
end

function util.vectors_cos_angle(a, b)
return util.vector_dot(a, b) / util.vector_length(a) / util.vector_length(b)
end

function util.lerp_vectors(a, b, alpha)
  return {x = a.x + (b.x - a.x) * alpha, y = a.y + (b.y - a.y) * alpha}
end

function util.move_to(a, b, max_distance, eliptical)
  -- move from a to b with max_distance.
  -- if eliptical, reduce y change (i.e. turret muzzle flash offset)
  local eliptical_scale = 0.9
  local delta = util.vectors_delta(a, b)
  if eliptical then
      delta.y = delta.y / eliptical_scale
  end
  local length = util.vector_length(delta)
  if (length > max_distance) then
      local partial = max_distance / length
      delta = {x = delta.x * partial, y = delta.y * partial}
  end
  if eliptical then
      delta.y = delta.y * eliptical_scale
  end
  return {x = a.x + delta.x, y = a.y + delta.y}
end

function util.vector_to_orientation(v)
  return util.vector_to_orientation_xy(v.x, v.y)
end

function util.vector_to_orientation_xy(x, y)
  if x == 0 then
      if y > 0 then
          return 0.5
      else
          return 0
      end
  elseif y == 0 then
      if x < 0 then
          return 0.75
      else
          return 0.25
      end
  else
      if y < 0 then
          if x > 0 then
              return util.atan(x / -y) / util.pi / 2
          else
              return 1 + util.atan(x / -y) / util.pi / 2
          end
      else
          return 0.5 + util.atan(x / -y) / util.pi / 2
      end
  end
end

function util.direction_to_orientation(direction)
  if direction == defines.direction.north then
      return 0
  elseif direction == defines.direction.northeast then
      return 0.125
  elseif direction == defines.direction.east then
      return 0.25
  elseif direction == defines.direction.southeast then
      return 0.375
  elseif direction == defines.direction.south then
      return 0.5
  elseif direction == defines.direction.southwest then
      return 0.625
  elseif direction == defines.direction.west then
      return 0.75
  elseif direction == defines.direction.northwest then
      return 0.875
  end
  return 0
end

function util.orientation_to_direction(orientation)
  orientation = (orientation + 0.0625) % 1
  if orientation <= 0.125 then
    return defines.direction.north
  elseif orientation <= 0.25 then
    return defines.direction.northeast
  elseif orientation <= 0.375 then
    return defines.direction.east
  elseif orientation <= 0.5 then
    return defines.direction.southeast
  elseif orientation <= 0.625 then
    return defines.direction.south
  elseif orientation <= 0.75 then
    return defines.direction.southwest
  elseif orientation <= 0.875 then
    return defines.direction.west
  else
    return defines.direction.northwest
  end
end

function util.signal_to_string(signal)
  return signal.type .. "__" .. signal.name
end

function util.signal_container_add(container, signal, count)
  if signal then
      if not container[signal.type] then
          container[signal.type] = {}
      end
      if container[signal.type][signal.name] then
          container[signal.type][signal.name].count = container[signal.type][signal.name].count + count
      else
          container[signal.type][signal.name] = {signal = signal, count = count}
      end
  end
end

function util.signal_container_add_inventory(container, entity, inventory)
  local inv = entity.get_inventory(inventory)
  if inv then
      local contents = inv.get_contents()
      for item_type, item_count in pairs(contents) do
          util.signal_container_add(container, {type="item", name=item_type}, item_count)
      end
  end
end

function util.signal_container_get(container, signal)
  if container[signal.type] and container[signal.type][signal.name] then
      return container[signal.type][signal.name]
  end
end

util.char_to_multiplier = {
  m = 0.001,
  c = 0.01,
  d = 0.1,
  h = 100,
  k = 1000,
  M = 1000000,
  G = 1000000000,
  T = 1000000000000,
  P = 1000000000000000,
}

function util.string_to_number(str)
  str = ""..str
  local number_string = ""
  local last_char = nil
  for i = 1, #str do
      local c = str:sub(i,i)
      if c == "." or (c == "-" and i == 1) or tonumber(c) ~= nil then
          number_string = number_string .. c
      else
          last_char = c
          break
      end
  end
  if last_char and util.char_to_multiplier[last_char] then
      return tonumber(number_string) * util.char_to_multiplier[last_char]
  end
  return tonumber(number_string)
end

function util.replace(str, what, with)
  what = util.str_gsub(what, "[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%1") -- escape pattern
  with = util.str_gsub(with, "[%%]", "%%%%") -- escape replacement
  return util.str_gsub(str, what, with)
end

-- function util.split(s, delimiter)
--     result = {};
--     for match in (s..delimiter):gmatch("(.-)"..delimiter) do
--         table.insert(result, match);
--     end
--     return result;
-- end

function util.overwrite_table(table_weak, table_strong)
for k,v in pairs(table_strong) do table_weak[k] = v end
return table_weak
end

function util.table_contains(table, check)
for k,v in pairs(table) do if v == check then return true end end
return false
end

function util.table_to_string(table)
return serpent.block( table, {comment = false, numformat = '%1.8g' } )
end

function util.values_to_string(table)
local string = ""
for _, value in pairs(table) do
  string = ((string == "") and "" or ", ") .. string .. value
end
return string
end

function util.math_log(value, base)
--logb(a) = logc(a) / logc(b)
return math.log(value)/math.log(base)
end

function util.seconds_to_clock(seconds)
local seconds = tonumber(seconds)

if seconds <= 0 then
  return "0";
else
  local hours = math.floor(seconds/3600)
  local mins = math.floor(seconds/60 - (hours*60))
  local secs = math.floor(seconds - hours*3600 - mins *60)
  local s_hours = string.format("%02.f",hours);
  local s_mins = string.format("%02.f", mins);
  local s_secs = string.format("%02.f", secs);
  if hours > 0 then
    return s_hours..":"..s_mins..":"..s_secs
  end
  if mins > 0 then
    return s_mins..":"..s_secs
  end
  if secs == 0 then
    return "0"
  end
  return s_secs
end
end

function util.to_rail_grid(number_or_position)
if type(number_or_position) == "table" then
  return {x = util.to_rail_grid(number_or_position.x), y = util.to_rail_grid(number_or_position.y)}
end
return math.floor(number_or_position / 2) * 2
end

function util.format_fuel(fuel, ceil)
return string.format("%.2f",(fuel or 0) / 1000).."k"
end

function util.format_energy(fuel, ceil)
if ceil then
  return math.ceil((fuel or 0) / 1000000000).."GJ"
else
  return math.floor((fuel or 0) / 1000000000).."GJ"
end
end


function util.direction_to_vector(direction)
return util.vector_normalise(util.direction_to_vector_unnormalised(direction))
end

function util.direction_to_vector_unnormalised (direction)
if direction == defines.direction.east then return {x=1,y=0} end
if direction == defines.direction.north then return {x=0,y=-1} end
if direction == defines.direction.northeast then return {x=1,y=-1} end
if direction == defines.direction.northwest then return {x=-1,y=-1} end
if direction == defines.direction.south then return {x=0,y=1} end
if direction == defines.direction.southeast then return {x=1,y=1} end
if direction == defines.direction.southwest then return {x=-1,y=1} end
if direction == defines.direction.west then return {x=-1,y=0} end
end

function util.sign(x)
 if x<0 then
   return -1
 elseif x>0 then
   return 1
 else
   return 0
 end
end

function util.find_first_descendant_by_name(gui_element, name)
for _, child in pairs(gui_element.children) do
  if child.name == name then
    return child
  end
  local found = util.find_first_descendant_by_name(child, name)
  if found then return found end
end
end

function util.find_descendants_by_name(gui_element, name, all_found)
local found = all_found or {}
for _, child in pairs(gui_element.children)do
  if child.name == name then
    table.insert(found, child)
  end
  util.find_descendants_by_name(child, name, found)
end
return found
end



return util