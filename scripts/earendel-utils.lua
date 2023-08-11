
-- License: Earendel FMLDOL 
-- https://docs.google.com/document/d/1z-6hZQekEHOu1Pk4z-V5LuwlHnveFLJGTjVAtjYHwMU
-- Copied and modified by unique2 with permission from earendel

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

require("earendel-utils2")

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
function util.swap_character(old, new_name)
  if not game.entity_prototypes[new_name] then error("No entity of type "..new_name.." found! "); return end
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
    "character_personal_logistic_requests_enabled",
    "allow_dispatching_robots"
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
      game.print(serpent.line(items))
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


return util