Grapple = {}

-- constants
Grapple.throw_acceleration = 0.2
Grapple.pull_acceleration_per_tick = 0.
Grapple.cancel_cooldown_duration = 10
Grapple.reverse_direction_multiplier = 2


-- utils
------------------------------------------------------------

local function lighten_color(color)
  color = util.copy(color)
  color.r = 0.5 + color.r * 0.2 * 255
  color.g = 0.5 + color.g * 0.2 * 255
  color.b = 0.5 + color.b * 0.2 * 255
  return color
end

local function draw_line(grapple)
  local from = grapple.character
  local to = grapple.projectile
  grapple.line1 = rendering.draw_line{
    color = lighten_color(grapple.character.player.color),--{r=50,g=50,b=50,a=1},
    width = 2,
    gap_length = 0.1,
    dash_length = 0.1,
    from = from,
    from_offset = {x=0, y=-1},
    to = to,
    to_offset = {x=0, y=-1},
    surface = from.surface
  }
  grapple.line2 = rendering.draw_line{
    color = {r=0,g=0,b=0,a=1},
    width = 1,
    from = from,
    from_offset = {x=0, y=-1},
    to = to,
    to_offset = {x=0, y=-1},
    surface = from.surface
  }
end

function Grapple.get_grapples(character)
  local unit_number
  if type(character) == "number" then unit_number = character else unit_number = character.unit_number end
  local grapples = {}
  for _, v in pairs(global.grapples) do
    if v.unit_number == unit_number then 
      table.insert(grapples, v)
    end
  end
  return grapples
end

-- For remote calls, replace the grapple data with the provided data
function Grapple.update_grapple(grapple)
  global.grapples[grapple.id] = grapple
end


-- Only works if the character has a player attached, for now
function Grapple.start_throw(target_position, surface, character)
  local player_index = character.player.index
  if util.is_cooldown_active_player("grapple", player_index) then 
    return false
  end
  
  if global.grapple_button_hold[player_index] then return false end
  global.grapple_button_hold[player_index] = true
  
  local range = MovementConfig.grapple_range(character)
  
  util.start_cooldown_player("grapple", player_index, MovementConfig.grapple_cooldown(character))
  util.start_cooldown_player("grapple_cancel", player_index, Grapple.cancel_cooldown_duration)
  
  if util.vectors_delta_length(target_position, character.position) > range then
    local direction = util.vector_normalise(util.vectors_delta(character.position, target_position))
    target_position = util.vectors_add(character.position, util.vector_multiply(direction, range))
  end
  
  if not MovementConfig.can_grapple_colliding(character) then
    target_position = surface.find_non_colliding_position(FloatingMovement.character_ground_name(character.name), target_position, range / 4, 0.5, false) or target_position
  end
  
  local vector = util.vectors_delta(character.position, target_position)
  if util.vector_length(vector) > range then
    vector = util.vector_set_length(vector, range)
  end
  
  local projectile = surface.create_entity{
    name = "grappling-gun-projectile",
    position = character.position,
    target = util.vectors_add(target_position, vector),
    speed = 0
  }
  
  local grapple = {
    surface = surface,
    target_position = target_position,
    character = character,
    player = character.player,
    throw_speed = MovementConfig.grapple_throw_speed(character),
    pull_acceleration = MovementConfig.grapple_pull_acceleration(character),
    projectile = projectile,
    throw = true,
    unit_number = character.unit_number,
    id = global.grapple_id,
    start_tick = game.tick
  }
  global.grapples[global.grapple_id] = grapple
  global.grapple_id = global.grapple_id + 1
  
  draw_line(grapple)
  
  for _, grp in pairs(global.grapples) do
    if grp.character == character and not grp.invalid and grp.throw and grp ~= grapple then 
      Grapple.destroy(grp)
    end
  end
  
  -- spawn explosion
  surface.create_entity{name="explosion-gunshot", position=character.position, force="neutral", target=character}
  surface.play_sound{position=character.position, path="jump-and-swing-pump-shotgun", volume_modifier=0.5}
  return true
end

function Grapple.on_trigger_created_entity(event)
  local character = event.source
  if event.entity.name == "jump-and-swing-grappling-gun-trigger" and character and character.valid then
    local valid_throw = Grapple.start_throw(event.entity.position, event.entity.surface, character)
    if not valid_throw then 
      local selected = character.selected_gun_index
      local ammo_inventory = event.source.get_inventory(defines.inventory.character_ammo)
      
      local item_stack = ammo_inventory[selected]
      item_stack.add_ammo(1)
    end
  end
end
Event.register(defines.events.on_trigger_created_entity, Grapple.on_trigger_created_entity)


function Grapple.on_init()
  global.grapples = {}
  global.grapple_to_destroy = {}
  global.grapple_id = 1
  global.grapple_button_hold = {}
  -- For testing. 
  -- if remote.interfaces.freeplay then 
  --   remote.call("freeplay", "set_respawn_items", {  
  --     ["grappling-gun"] = 1,
  --     ["grappling-gun-ammo"] = 200,
  --   }) 
  -- end
  -- if remote.interfaces.freeplay then 
  --   remote.call("freeplay", "set_created_items", {  
  --     ["grappling-gun"] = 1,
  --     ["grappling-gun-ammo"] = 200,
  --   }) 
  -- end
end
Event.register("on_init", Grapple.on_init)


function Grapple.throwing_tick(grapple)
  local projectile = grapple.projectile
  projectile.teleport(util.move_to(projectile.position, grapple.target_position, grapple.throw_speed))
  grapple.throw_speed = grapple.throw_speed + Grapple.throw_acceleration
  
  if util.vectors_delta_length(projectile.position, grapple.target_position) < 0.01 then
    Grapple.start_pulling(grapple)
  end
end

function Grapple.start_pulling(grapple)
  local character = grapple.character
  local projectile = grapple.projectile
  local surface = grapple.projectile.surface
  
  local range = MovementConfig.grapple_range(character)
  local position = projectile.position
  if not MovementConfig.can_grapple_colliding(character) then
    position = surface.find_non_colliding_position (FloatingMovement.character_ground_name(character.name), position, range / 4, 1, false)
  end
  
  local function cancel_grapple(grapple)
    Grapple.destroy(grapple)
    local player = grapple.player
    util.reset_cooldown_player("grapple", player)
    util.start_cooldown_player("grapple", player.index, 10)
    
    local selected = character.selected_gun_index
    local ammo_inventory = character.get_inventory(defines.inventory.character_ammo)
    
    local item_stack = ammo_inventory[selected]
    item_stack.add_ammo(1)
  end
  
  if not position or util.vector_length(util.vectors_delta(position, character.position)) < 2 then
    cancel_grapple(grapple)
    return
  end
  
  projectile.surface.create_entity{name="explosion-hit", position = util.vectors_add(projectile.position, {x=0, y=0})}
  grapple.start_pulling_tick = game.tick
  
  local new_character = FloatingMovement.set_floating_flag(character, "grapple"..grapple.id)
  if not new_character then
    character.player.print({"jump-and-swing.cant_fly_here"})
    cancel_grapple(grapple)
    return
  end
  
  local redraw
  if character ~= new_character then redraw = true end
  character = new_character or character
  grapple.character = character
  if redraw then draw_line(grapple) end
  
  -- Stop any other pulling grapples for this character
  for _, grp in pairs(global.grapples) do
    if grp.character == grapple.character and not grp.throw then
      Grapple.destroy(grp)
    end
  end
  grapple.throw = false
end


function Grapple.pulling_tick(grapple)
  local character = grapple.character
  if character.stickers then
    for _, sticker in pairs(character.stickers) do sticker.destroy() end
  end
  
  local floater = FloatingMovement.from_character(character)
  if not floater then error() end
  local velocity = floater.velocity
  local position = FloatingMovement.ground_position(character)
  local delta = util.vectors_delta(position, grapple.target_position)
  local direction = util.vector_normalise(delta)


  -- Stop pull
  local autojump = MovementConfig.autojump(character)
  local hook_duration_elapsed = game.tick - grapple.start_pulling_tick > MovementConfig.grapple_duration(character)
  
  local not_holding_hook_button = character.player and not global.grapple_button_hold[grapple.character.player.index]
  --local close_to_center = util.vector_length(delta) < 2 * util.vector_length(velocity)
  if hook_duration_elapsed or not_holding_hook_button then
    local jump = autojump --and util.vector_length(velocity) > 0.4 
    if jump and grapple.character and grapple.character.valid then
      Jump.start_jump(grapple.character)
    end
    Grapple.destroy(grapple)
    return
  end
  
  
  
  local delta_v = util.vector_multiply(direction, grapple.pull_acceleration)
  local cosangle = util.vectors_cos_angle(velocity, direction)
  local multiplier = 1
  if cosangle < -0.5 then multiplier = Grapple.reverse_direction_multiplier end
  if cosangle > 0.7 and util.vector_length(velocity) > MovementConfig.grapple_pull_acceleration_threshold(character) then
    multiplier = 0
  end
  delta_v = util.vector_multiply(delta_v, multiplier)
  velocity = util.vectors_add(velocity, delta_v)
  
  -- local dist = util.vector_length(delta)
  -- local rel_dist = dist / 5000
  -- if rel_dist > 2 then rel_dist = 0 end
  -- velocity = util.vector_set_length(velocity, util.vector_length(velocity) + rel_dist)
  
  floater.velocity = velocity
  grapple.pull_acceleration = grapple.pull_acceleration + Grapple.pull_acceleration_per_tick
  
  -- Check if moving away or towards
  -- local moving_away
  -- if character.walking_state.walking then 
  --   local walk_direction = util.direction_to_vector(character.walking_state.direction)
  --   local moving_towards = util.vectors_cos_angle(walk_direction, direction) > -0.2
  --   if moving_towards then 
  --     grapple.moving_towards = true
  --   end
  --   moving_away = util.vectors_cos_angle(walk_direction, direction) < -0.3
  -- else 
  --   grapple.character.direction = util.orientation_to_direction(util.vector_to_orientation(delta))
  -- end
  end

function Grapple.movement_tick(grapple)
  if grapple.throw then
    Grapple.throwing_tick(grapple)
  else
    Grapple.pulling_tick(grapple)
  end
end


function Grapple.check(grapple)
  if grapple.invalid then return false end
  if not grapple.projectile or not grapple.projectile.valid or not grapple.character or not grapple.character.valid or grapple.projectile.surface ~= grapple.character.surface or (not grapple.throw and not FloatingMovement.is_floating(grapple.character)) then
    Grapple.destroy(grapple)
    return false
  end
  return true
end

function Grapple.pre_movement_tick()
  for _, player in pairs(game.connected_players) do
    global.grapple_button_hold[player.index] = global.grapple_button_hold[player.index] and player.character ~= nil and player.character.shooting_state.state ~= defines.shooting.not_shooting
  end
  for _, grapple in pairs(global.grapples) do
    if Grapple.check(grapple) then
      Grapple.movement_tick(grapple)
    else
      Grapple.destroy(grapple)
    end
  end
  for _, v in pairs(global.grapple_to_destroy) do
    global.grapples[v.id] = nil
  end
  global.grapple_to_destroy = {}
end
Event.register_custom_event("on_pre_movement_tick", Grapple.pre_movement_tick)


Event.register_custom_event(util.on_character_swapped_event, 
--@param event CharacterSwappedEvent
function (event)
  local old_unit_number = event.old_unit_number
  for _, grapple in pairs(global.grapples) do
    if not grapple.invalid and grapple.unit_number == old_unit_number then
      grapple.unit_number = event.new_unit_number
      grapple.character = event.new_character
      draw_line(grapple)
    end
  end
end)


-- End
------------------------------------------------------------


function Grapple.destroy(grapple)
  if grapple.invalid then return end
  grapple.invalid = true
    
  local new_character
  if grapple.character and grapple.character.valid then
    grapple.character.destructible = true
    new_character = FloatingMovement.unset_floating_flag(grapple.character.unit_number, "grapple"..grapple.id, true)
  end
  if grapple.projectile and grapple.projectile.valid then
    grapple.projectile.surface.create_trivial_smoke{name="smoke", position = grapple.projectile.position}
    grapple.projectile.destroy()
  end
  
  table.insert(global.grapple_to_destroy, grapple)
  return new_character
end


function Grapple.on_jump_keypress(event)
  if event.player_index and game.players[event.player_index] and game.players[event.player_index].connected then
    local player = game.players[event.player_index]
    local character = player.character
    for _, grapple in pairs(global.grapples) do
      if grapple.character == character and not grapple.throw and Jump.can_jump(grapple.character) then
        Grapple.destroy(grapple)
      end
    end
  end
end
Event.register(Jump.jump_key_event, Grapple.on_jump_keypress)

function Grapple.on_player_soft_revived(event)
  local character = event.character
  if not character or not character.valid then return end
  for _, grapple in pairs(global.grapples) do
    if grapple.character and grapple.character == event.character then
      Grapple.destroy(grapple)
    end
  end
end
Event.register_custom_event(FloatingMovement.on_player_soft_revived_event, Grapple.on_player_soft_revived)

function Grapple.on_floating_movement_canceled(event)
  local character = event.character
  if not event.character or not event.character.valid then return end
  local grapples = Grapple.get_grapples(character)
  for _, grapple in pairs(grapples) do
    if grapple and grapple.valid and not grapple.throw then
      Grapple.destroy(grapple)
    end
  end
end
Event.register_custom_event("on_floating_movement_canceled", Grapple.on_floating_movement_canceled)

util.expose_remote_interface(Grapple, "jump-and-swing_grapple", {
  "start_throw",
  "check",
  "get_grapples",
  "update_grapple",
})

return Grapple