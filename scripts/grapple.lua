Grapple = {}

-- constants
Grapple.range = 20
Grapple.throw_speed = 1.6
Grapple.throw_speed_per_tick = 0.02
Grapple.pull_speed = 0.004
Grapple.pull_speed_per_tick = 0.001 -- increase pull speed over time (for longer distances)
Grapple.max_orientation_delta_before_disconnect = 0.01 -- In "orientation" 
Grapple.jetpacking_grapple_duration = 0.01
Grapple.cooldown_duration = 50
Grapple.hook_duration = 100
Grapple.cancel_cooldown_duration = 10

-- TODO: 
-- cooldown
-- Separate button instead of tied to weapon
-- import graphics from earendel's mod
-- upgrade - range 12->20, cooldown 90f->60f


-- utils
------------------------------------------------------------
local function draw_line(grapple)
  local from = grapple.character
  local to = grapple.projectile
  grapple.line1 = rendering.draw_line{
    color = {r=50,g=50,b=50,a=1},
    width = 2,
    gap_length = 0.1,
    dash_length = 0.1,
    from = from,
    from_offset = {0, -1},
    to = to,
    to_offset = {0, -1},
    surface = from.surface
  }
  grapple.line2 = rendering.draw_line{
    color = {r=0,g=0,b=0,a=1},
    width = 1,
    from = from,
    from_offset = {0, -1},
    to = to,
    to_offset = {0, -1},
    surface = from.surface
  }
end


-- Begin
------------------------------------------------------------

function Grapple.start_throw(target_position, surface, character)
  local player_index = character.player.index
  for _, grapple in pairs(global.grapples) do
    if grapple.character == character and not grapple.invalid then 
      return
    end
  end
  if util.is_cooldown_active_player("grapple", player_index) then 
    return
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
    pull_speed = Grapple.pull_speed,
    projectile = projectile,
    throw = true,
    unit_number = character.unit_number
  }
  table.insert(global.grapples, grapple)

  draw_line(grapple)
end

function Grapple.on_trigger_created_entity(event)
  if event.entity.name == "grappling-gun-trigger" and event.source and event.source.valid then
    Grapple.start_throw(event.entity.position, event.entity.surface, event.source)
  end
end
Event.addListener(defines.events.on_trigger_created_entity, Grapple.on_trigger_created_entity)


function Grapple.on_init(event)
  global.grapples = {}
  remote.call("freeplay", "set_ship_items", {  
    ["grappling-gun"] = 1,
    ["grappling-gun-ammo"] = 200
})
end
Event.addListener("on_init", Grapple.on_init, true)


-- Maintain
------------------------------------------------------------

function Grapple.on_tick_grapple(grapple)
  local character = grapple.character
  if grapple.throw then 
    -- Throwing Grapple
    grapple.projectile.teleport(util.move_to(grapple.projectile.position, grapple.target_position, grapple.throw_speed))
    grapple.throw_speed = grapple.throw_speed + Grapple.throw_speed_per_tick
    grapple.projectile.surface.create_trivial_smoke{name="light-smoke", position = util.vectors_add(grapple.projectile.position,{x=0,y=-1})}

    if util.vectors_delta_length(grapple.projectile.position, grapple.target_position) < 0.01 then
      -- local safe_position = grapple.surface.find_non_colliding_position (
      --   character.name, grapple.target_position, Grapple.range / 4, 1, false
      -- )
      -- if not safe_position then 
      --   Grapple.destroy(grapple)
      --   return
      -- else
      -- Begin pulling
      grapple.throw = false
      character.destructible = false
      -- TODO: Make player destructible here, destroy everything if the player dies. 
      grapple.projectile.surface.create_entity{name="explosion-hit", position = util.vectors_add(grapple.projectile.position, {x=0, y=0})}
      grapple.start_pulling_tick = game.tick
      
      if not FloatingMovement.is_floating(character) then
        local new_character = FloatingMovement.set_floating(character)
        character = new_character
        grapple.character = new_character
        draw_line(grapple)
      end
      FloatingMovement.set_source_flag(character, "grapple", true)
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
  

    local delta_v = util.vector_multiply(direction, grapple.pull_speed)
    if util.vectors_cos_angle(velocity, direction) < -0.5 then delta_v = util.vector_multiply(delta_v, 5) end
    local v = util.vectors_add(velocity, delta_v)

    floater.velocity = v
    grapple.pull_speed = grapple.pull_speed + Grapple.pull_speed_per_tick

    -- Stop pull
    local moving_away
    if character.walking_state.walking then 
      local walk_direction = util.direction_to_vector(character.walking_state.direction)
      local moving_towards = util.vectors_cos_angle(walk_direction, direction) > -0.2
      if moving_towards then 
        grapple.moving_towards = true
      end
      moving_away = util.vectors_cos_angle(walk_direction, direction) < -0.7
    end

    if util.vector_length(delta) < 2 * util.vector_length(velocity) or game.tick - grapple.start_pulling_tick > Grapple.hook_duration or (grapple.moving_towards and moving_away) then
      Jumppack.start_on_character(character)
      Grapple.destroy(grapple)
    end
  end
end

function Grapple.on_tick()
  for _, grapple in pairs(global.grapples or {}) do
    if grapple.projectile and grapple.projectile.valid and grapple.character and grapple.character.valid then
      Grapple.on_tick_grapple(grapple)
    else 
      Grapple.destroy(grapple)
    end
  end
end
Event.addListener(defines.events.on_tick, Grapple.on_tick)


Event.addListener(FloatingMovement.on_character_swapped_event, function (event)
  local old_unit_number = event.old_unit_number
  for k, grapple in pairs(global.grapples) do 
    if grapple.unit_number == old_unit_number then
      grapple.unit_number = event.new_unit_number
      grapple.character = event.new_character
      global.grapples[k] = grapple
      draw_line(grapple)
    end
  end
end, true)


-- End
------------------------------------------------------------


function Grapple.destroy(grapple)
  grapple.valid = false
  local new_character
  if grapple.character and grapple.character.valid then
    grapple.character.destructible = true
    new_character = FloatingMovement.set_source_flag(grapple.character, "grapple", false, true)
  end
  if grapple.projectile and grapple.projectile.valid then
    grapple.projectile.surface.create_trivial_smoke{name="smoke", position = grapple.projectile.position}
    grapple.projectile.destroy()
  end
  for k, v in pairs(global.grapples) do
    if v == grapple then
      global.grapples[k] = nil
    end
  end
  return new_character
end


function Grapple.attempt_cancel_grapple(event)
  if util.is_cooldown_active_player("grapple_cancel", event.player_index) then return end

  if not global.grapples then return end
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
      --   local pull_speed = Grapple.get_pull_speed(tick_task)
      --   local velocity = Util.orientation_to_vector(last_orientation, pull_speed)
      --   set_jetpack_velocity(tick_task.character, velocity)
      -- end
      Grapple.destroy(grapple)
      return
    end
  end
end
script.on_event("shoot-enemy", Grapple.attempt_cancel_grapple)
script.on_event("shoot-selected", Grapple.attempt_cancel_grapple)

return Grapple