local Jump = {}


--TODO: 
-- Action of jump button while already jumping? - airjump, dash, slow-fall


Jump.jump_key_event = "jump"
Jump.altitude_target = 3
Jump.altitude_base_increase = 0.01
Jump.altitude_percentage_increase = 0.15
Jump.altitude_decrease = 0.3
Jump.jump_cooldown = 0

Jump.jumps_to_add = {}
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


function Jump.is_jumping(character)
  if not character or not character.valid then return false end
  local jump = Jump.from_character(character)
  return jump ~= nil and not jump.invalid
end


-- remove jumping state, trigger cooldown
function Jump.instant_landing(jump)
  local character = jump.character
  local player = character.player

  util.start_cooldown_player("jump", player, Jump.jump_cooldown)

  Jump.destroy(jump)
end

function Jump.destroy(jump)
  if jump.invalid then return end
  jump.invalid = true
  table.insert(Jump.jumps_to_delete, jump.unit_number)
  FloatingMovement.unset_source_flag(jump.unit_number, "jump", true)
end



local function rising_tick(jump)
  local floater = FloatingMovement.get_float_data(jump.character)
  local altitude = floater.altitude

  if altitude < Jump.altitude_target then
    local difference = Jump.altitude_target - altitude
    local change =  math.min(difference, difference * Jump.altitude_percentage_increase + Jump.altitude_base_increase)

    FloatingMovement.add_altitude(jump.character, change)
  else
    jump.rising = false
  end
end

local function falling_tick(jump)
  local floater = FloatingMovement.get_float_data(jump.character)
  local altitude = floater.altitude
  if altitude > 0.2 then
    FloatingMovement.add_altitude(jump.character, -Jump.altitude_decrease)
  else -- Reached the floor
    Jump.instant_landing(jump)
  end
end


function Jump.movement_tick(jump)
  -- Character died or was destroyed
  if not (jump.character and jump.character.valid) then
    Jump.destroy(jump)
    return
  end

  if jump.rising then
    rising_tick(jump)
  else
    falling_tick(jump)
  end -- else is "walking", do nothing
end

function Jump.on_tick()
  for _, jump in pairs(global.jumps) do
    if not jump.invalid then
      Jump.movement_tick(jump)
    end
  end

  for unit_number, jump in pairs(Jump.jumps_to_add) do
    global.jumps[unit_number] = jump
  end
  Jump.jumps_to_add = {}
  for _, unit_number in pairs(Jump.jumps_to_delete) do
    global.jumps[unit_number] = nil
  end
  Jump.jumps_to_delete = {}
end
Event.register(defines.events.on_tick, Jump.on_tick)

-- Creates a new jump object and sets character floating.
-- Does not check if jumping is allowed, check with Jump.can_jump in advance!
function Jump.start_jump(character)

  local player = character.player
  local new_character = FloatingMovement.set_source_flag(character, "jump")
  if new_character then
    character = new_character
  else
    character.player.print({"jump-and-swing.cant_fly_here"})
    return
  end

  local jump = {
    rising = true,
    character = new_character or character,
    unit_number = new_character and new_character.unit_number or character.unit_number,
    player_index = player.index,
  }

  FloatingMovement.set_properties_character(character, "jump", "g", { drag = 0.01 })

  Jump.jumps_to_add[jump.unit_number] = jump
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

function Jump.start_fall(jump)
  jump.rising = false
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



-- TODO: this should be in floating movement
function Jump.on_player_driving_changed_state(event)
  local player = game.get_player(event.player_index)
  if not player or not player.character or not player.character.valid then return end
  if Jump.is_jumping(player.character) then
    Jump.instant_landing(Jump.from_character(player.character))
  end
end
Event.register(defines.events.on_player_driving_changed_state, Jump.on_player_driving_changed_state)


Event.register_custom_event(util.on_character_swapped_event, 
---@param event CharacterSwappedEvent
function (event)
  local jump = global.jumps[event.old_unit_number]
  if jump then
    if jump.invalid then return end
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


util.expose_remote_interface(Jump, "jump-and-swing_jump", {
  "is_jumping",
  "start_jump",
  "instant_landing",
  "destroy",
  "from_character",
})


return Jump
