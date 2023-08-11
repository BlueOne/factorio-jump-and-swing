Grapple = {}

-- constants
Grapple.range = 20
Grapple.throw_speed = 1.
Grapple.throw_speed_per_tick = 0.1
Grapple.pull_acceleration = 0.02
Grapple.pull_acceleration_threshold = 0.8
Grapple.pull_acceleration_per_tick = 0.00001
Grapple.cooldown_duration = 20
Grapple.hook_duration = 100
Grapple.cancel_cooldown_duration = 10
Grapple.reverse_direction_multiplier = 2

Grapple.to_destroy = {}


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

function Grapple.update_grapple(grapple)
  local id = grapple.id
  for k, v in pairs(global.grapples) do
    if grapple.id == v.id then 
      global.grapples[k] = grapple 
      return
    end
  end
end


-- Construct
------------------------------------------------------------

function Grapple.start_throw(target_position, surface, character)
  local player_index = character.player.index
  if util.is_cooldown_active_player("grapple", player_index) then 
    return false
  end

  util.start_cooldown_player("grapple", player_index, Grapple.cooldown_duration)
  util.start_cooldown_player("grapple_cancel", player_index, Grapple.cancel_cooldown_duration)

  if util.vectors_delta_length(target_position, character.position) > Grapple.range then
    local direction = util.vector_normalise(util.vectors_delta(character.position, target_position))
    target_position = util.vectors_add(character.position, util.vector_multiply(direction, Grapple.range))
  end
  -- local safe_position = surface.find_non_colliding_position (
  --   character.name, target_position, Grapple.range / 4, 1, false
  -- )
  -- target_position = safe_position or target_position

  local vector = util.vectors_delta(character.position, target_position)
  if util.vector_length(vector) > Grapple.range then
    vector = util.vector_set_length(vector, Grapple.range)
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
    throw_speed = Grapple.throw_speed,
    pull_acceleration = Grapple.pull_acceleration,
    projectile = projectile,
    throw = true,
    unit_number = character.unit_number,
    id = global.grapple_id
  }
  global.grapple_id = global.grapple_id + 1
  table.insert(global.grapples, grapple)

  draw_line(grapple)

  for _, grp in pairs(global.grapples) do
    if grp.character == character and not grp.invalid and grp.throw and grp ~= grapple then 
      Grapple.destroy(grp)
    end
  end

  -- spawn explosion
  surface.create_entity{name="explosion-gunshot", position=character.position, force="neutral", target=character}
  surface.play_sound{position=character.position, path="jumppack-pump-shotgun", volume_modifier=0.5}
  return true
end

function Grapple.on_trigger_created_entity(event)
  if event.entity.name == "jumppack-grappling-gun-trigger" and event.source and event.source.valid then
    local valid_throw = Grapple.start_throw(event.entity.position, event.entity.surface, event.source)
    if not valid_throw then 
      local character = event.source
      local selected = character.selected_gun_index
      local ammo_inventory = event.source.get_inventory(defines.inventory.character_ammo)

      local item_stack = ammo_inventory[selected]
      item_stack.add_ammo(1)
    end
  end
end
Event.register(defines.events.on_trigger_created_entity, Grapple.on_trigger_created_entity)


function Grapple.on_init(event)
  global.grapples = {}
  global.grapple_id = 0
  remote.call("freeplay", "set_created_items", {  
      ["grappling-gun"] = 1,
      ["grappling-gun-ammo"] = 200,
      ["iron-plate"] = 8,
      ["wood"] = 1,
      ["pistol"] = 1,
      ["firearm-magazine"] = 10,
      ["burner-mining-drill"] = 1,
      ["stone-furnace"] = 1,
})
end
Event.register("on_init", Grapple.on_init)


-- Maintain
------------------------------------------------------------

function Grapple.on_tick_grapple(grapple)
  if grapple.invalid then return end
  local character = grapple.character
  if grapple.throw then 
    -- Throwing Grapple
    grapple.projectile.teleport(util.move_to(grapple.projectile.position, grapple.target_position, grapple.throw_speed))
    grapple.throw_speed = grapple.throw_speed + Grapple.throw_speed_per_tick

    if game.tick % 2 == 0 then
      grapple.projectile.surface.create_trivial_smoke{name="light-smoke", position = util.vectors_add(grapple.projectile.position,{x=0,y=-1})}
    end

    if util.vectors_delta_length(grapple.projectile.position, grapple.target_position) < 0.01 then
      -- Begin pulling
      -- local safe_position = grapple.surface.find_non_colliding_position (
      --   character.name, grapple.target_position, Grapple.range / 4, 1, false
      -- )
      -- if not safe_position then 
      --   Grapple.destroy(grapple)
      --   return
      -- else
      grapple.projectile.surface.create_entity{name="explosion-hit", position = util.vectors_add(grapple.projectile.position, {x=0, y=0})}
      grapple.start_pulling_tick = game.tick

      local new_character = FloatingMovement.set_source_flag(character, "grapple"..grapple.id)
      local redraw
      if character ~= new_character then redraw = true end
      character = new_character or character
      grapple.character = character
      if redraw then draw_line(grapple) end

      for _, grp in pairs(global.grapples) do
        if grp.character == grapple.character and not grp.throw then
          Grapple.destroy(grp)
        end
      end
      grapple.throw = false
    end
  else -- Pulling in
    if character.stickers then
      for _, sticker in pairs(character.stickers) do sticker.destroy() end
    end

    local position = FloatingMovement.ground_position(character)
    local delta = util.vectors_delta(position, grapple.target_position)
    local direction = util.vector_normalise(delta)
    local floater = FloatingMovement.from_character(character)
    local velocity = floater.velocity
  

    local delta_v = util.vector_multiply(direction, grapple.pull_acceleration)
    local cosangle = util.vectors_cos_angle(velocity, direction)
    local multiplier = 1
    if cosangle < -0.5 then multiplier = Grapple.reverse_direction_multiplier end
    if cosangle > 0.7 and util.vector_length(velocity) > Grapple.pull_acceleration_threshold then
      multiplier = 0
    end
    delta_v = util.vector_multiply(delta_v, multiplier)

    local v = util.vectors_add(velocity, delta_v)
    floater.velocity = v
    grapple.pull_acceleration = grapple.pull_acceleration + Grapple.pull_acceleration_per_tick

    -- Check if moving away or towards
    -- local moving_away
    -- if character.walking_state.walking then 
    --   local walk_direction = util.direction_to_vector(character.walking_state.direction)
    --   local moving_towards = util.vectors_cos_angle(walk_direction, direction) > -0.2
    --   if moving_towards then 
    --     grapple.moving_towards = true
    --   end
    --   moving_away = util.vectors_cos_angle(walk_direction, direction) < -0.7
    -- else 
    grapple.character.direction = util.orientation_to_direction(util.vector_to_orientation(delta))
    -- end
    
    -- Stop pull
    if util.vector_length(delta) < 2 * util.vector_length(velocity) or game.tick - grapple.start_pulling_tick > Grapple.hook_duration --[[or (grapple.moving_towards and moving_away)--]] then
      if Jumppack.can_jump(character) then
        Jumppack.start_jump(character)
      end
      Grapple.destroy(grapple)
    end
  end
end


function Grapple.check(grapple)
  if grapple.invalid then return false end
  if not grapple.projectile or not grapple.projectile.valid or not grapple.character or not grapple.character.valid or grapple.projectile.surface ~= grapple.character.surface then 
    Grapple.destroy(grapple)
    return false
  end
  return true
end

function Grapple.on_tick()
  for _, grapple in pairs(global.grapples) do
    if Grapple.check(grapple) then
      Grapple.on_tick_grapple(grapple)
    end
  end
  for k, v in pairs(Grapple.to_destroy) do
    global.grapples[k] = nil
  end
  Grapple.to_destroy = {}
end
Event.register(defines.events.on_tick, Grapple.on_tick)


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
    new_character = FloatingMovement.unset_source_flag(grapple.character.unit_number, "grapple"..grapple.id, true)
  end
  if grapple.projectile and grapple.projectile.valid then
    grapple.projectile.surface.create_trivial_smoke{name="smoke", position = grapple.projectile.position}
    grapple.projectile.destroy()
  end

  table.insert(Grapple.to_destroy, grapple)
  return new_character
end


function Grapple.attempt_cancel_grapple(event)
  if util.is_cooldown_active_player("grapple_cancel", event.player_index) then return end

  local character = game.players[event.player_index].character
  if not character then return end
  local gun_inventory = character.get_inventory(defines.inventory.character_guns)
  if not gun_inventory then return end
  local selected_gun = gun_inventory[character.selected_gun_index]
  if selected_gun.valid_for_read and selected_gun.name ~= "grappling-gun" then return end

   for _, grapple in pairs(global.grapples) do
    if grapple.character == character then
      -- Grappling hook is already out, cancel this one
      -- if tick_task.pull then
      --   local last_orientation = tick_task.last_orientation or Util.vector_to_orientation(Util.vectors_delta(tick_task.character.position, tick_task.target_position))
      --   local pull_acceleration = Grapple.get_pull_acceleration(tick_task)
      --   local velocity = Util.orientation_to_vector(last_orientation, pull_acceleration)
      --   set_jetpack_velocity(tick_task.character, velocity)
      -- end
      Grapple.destroy(grapple)
      return
    end
  end
end
-- script.on_event("shoot-enemy", Grapple.attempt_cancel_grapple)
-- script.on_event("shoot-selected", Grapple.attempt_cancel_grapple)

function Grapple.on_jumppack_keypress(event)
  if event.player_index and game.players[event.player_index] and game.players[event.player_index].connected then
    local player = game.players[event.player_index]
    local character = player.character
    for _, grapple in pairs(global.grapples) do
      if grapple.character == character and not grapple.throw and Jumppack.can_jump(grapple.character) then
        Grapple.destroy(grapple)
      end
    end
  end
end
Event.register(Jumppack.jump_key_event, Grapple.on_jumppack_keypress)

function Grapple.on_player_soft_revived(event)
  for _, grapple in pairs(global.grapples) do
    if grapple.character == event.character then
      Grapple.destroy(grapple)
    end
  end
end
Event.register_custom_event(FloatingMovement.on_player_soft_revived_event, Grapple.on_player_soft_revived)

util.expose_remote_interface(Grapple, "jumppack_grapple", {
  "start_throw",
  "check",
  "get_grapples",
  "update_grapple",
})

return Grapple