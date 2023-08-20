local Jump = {}


Jump.jump_key_event = "jump"
Jump.jump_cooldown = 0
Jump.default_jump_speed = 0.4

Jump.jumps_to_delete = {}


function Jump.can_jump(character)
  if not character then return false end
  if Jump.is_jumping(character) then return false end

  if util.is_cooldown_active_player("jump", character.player) then return false end

  if not character.force.technologies["jump"].researched then
    return false
  end

  -- Cannot jump on water if floating
  local position = FloatingMovement.ground_position(character) or character.position
  local tile = character.surface.get_tile(position)
  if not MovementConfig.can_jump_colliding(character) and tile.collides_with("player-layer") and FloatingMovement.is_floating(character) then
    return false
  end
  return true
end

function Jump.instant_land_character(character)
  if Jump.is_jumping(character) then Jump.instant_landing(Jump.from_character(character)) end
end
Event.register_custom_event("on_character_touch_ground", function(event)
  if event.character and event.character.valid then
    Jump.instant_land_character(event.character)
  end
end)

function Jump.is_jumping(character)
  if not character or not character.valid then return false end
  local jump = Jump.from_character(character)
  return jump ~= nil and jump.valid
end


-- remove jumping state, trigger cooldown
function Jump.instant_landing(jump)
  local character = jump.character
  local player = character.player

  util.start_cooldown_player("jump", player, Jump.jump_cooldown)

  Jump.destroy(jump)
end

function Jump.destroy(jump)
  if not jump.valid then return end
  jump.valid = false
  global.jumps[jump.unit_number] = nil
  FloatingMovement.unset_floating_flag(jump.unit_number, "jump", true)
end

function Jump.pre_movement_tick()
  for _, jump in pairs(global.jumps) do
    if jump.valid then
      if not (jump.character and jump.character.valid) or not FloatingMovement.is_floating(jump.character) then
        Jump.destroy(jump)
        return
      end
    end
  end
end
Event.register_custom_event("on_pre_movement_tick", Jump.pre_movement_tick)

-- Creates a new jump object and sets character floating.
-- Checks if jumping is allowed, if you want to force a jump then pass skip_check
function Jump.start_jump(character, skip_check)
  if not skip_check and not Jump.can_jump(character) then return false end

  local player = character.player
  local new_character = FloatingMovement.set_floating_flag(character, "jump")
  if new_character then
    character = new_character
  else
    character.player.print({"jump-and-swing.cant_fly_here"})
    return
  end

  local jump = {
    character = new_character or character,
    unit_number = new_character and new_character.unit_number or character.unit_number,
    player_index = player.index,
    valid = true
  }

  FloatingMovement.set_properties_character(character, "jump", "g", { drag = 0.01 })
  local floater = FloatingMovement.from_character(character)
  floater.vel_z = Jump.default_jump_speed

  global.jumps[jump.unit_number] = jump

  return jump
end


function Jump.from_character(character)
  if not character or not character.valid then return end
  return global.jumps[character.unit_number]
end

-- for remote calls
function Jump.update(jump)
  global.jumps[jump.unit_number] = jump
end


function Jump.on_jump_keypress(event)
  if event.player_index and game.players[event.player_index] and game.players[event.player_index].connected then
    local player = game.players[event.player_index]
    local character = player.character
    if Jump.can_jump(character) then
      Jump.start_jump(character)
    else
      player.play_sound{path="utility/cannot_build"}
    end
  end
end
Event.register(Jump.jump_key_event, Jump.on_jump_keypress)


Event.register_custom_event(util.on_character_swapped_event, 
---@param event CharacterSwappedEvent
function (event)
  local jump = global.jumps[event.old_unit_number]
  if jump then
    if not jump.valid then return end
    jump.unit_number = event.new_unit_number
    jump.character = event.new_character
    global.jumps[event.old_unit_number] = nil
    global.jumps[event.new_unit_number] = jump
  end
end)

function Jump.on_init()
  global.jumps = {}
end
Event.register("on_init", Jump.on_init)

function Jump.on_floating_movement_canceled(event)
  local character = event.character
  if not event.character or not event.character.valid then return end
  local jump = Jump.from_character(character)
  if jump and jump.valid then
    Jump.destroy(jump)
  end
end
Event.register_custom_event("on_floating_movement_canceled", Jump.on_floating_movement_canceled)

util.expose_remote_interface(Jump, "jump-and-swing_jump", {
  "is_jumping",
  "start_jump",
  "instant_landing",
  "destroy",
  "from_character",
})


return Jump
