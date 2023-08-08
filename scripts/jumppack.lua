local Jumppack = {}



--TODO: 
-- Action of jump button while already jumping? - airjump, dash, slow-fall
-- interaction with vehicles

--{new_unit_number = uint, old_unit_number = uint, new_character = luaEntity, old_character = luaEntity}

Jumppack.name_event = "jumppack"
Jumppack.altitude_target = 3
Jumppack.altitude_base_increase = 0.01
Jumppack.altitude_percentage_increase = 0.15
Jumppack.altitude_decrease = 0.3
Jumppack.jump_cooldown = 0

Jumppack.jumppacks_to_add = {}
Jumppack.jumppacks_to_delete = {}


Jumppack.states = {
  walking = 1,
  rising = 2,
  stopping = 3,
}

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
  local player = character.player

  util.start_cooldown_player("jump", player, Jumppack.jump_cooldown)

  Jumppack.destroy(jumppack)
end


local function on_tick_rising(jumppack)
  local floater = FloatingMovement.get_float_data(jumppack.character)
  local altitude = floater.altitude

  if altitude < Jumppack.altitude_target then
    local difference = Jumppack.altitude_target - altitude
    local change =  math.min(difference, difference * Jumppack.altitude_percentage_increase + Jumppack.altitude_base_increase)

    FloatingMovement.add_altitude(jumppack.character, change)
  else
    jumppack.state = Jumppack.states.stopping
  end
end

local function on_tick_stopping(jumppack)
  local floater = FloatingMovement.get_float_data(jumppack.character)
  local altitude = floater.altitude
  if altitude > 0 then
    FloatingMovement.add_altitude(jumppack.character, -Jumppack.altitude_decrease)
  else -- Reached the floor
    Jumppack.land_and_start_walking(jumppack)
  end
end

function Jumppack.destroy(jumppack)
  if jumppack.invalid then return end
  jumppack.invalid = true
  table.insert(Jumppack.jumppacks_to_delete, jumppack.unit_number)
  FloatingMovement.set_source_flag(jumppack.character, "jumppack", false, true)
end



function Jumppack.on_tick_jumppack(jumppack)
  -- Character died or was destroyed
  if not (jumppack.character and jumppack.character.valid) then
    Jumppack.destroy(jumppack)
    return
  end

  local state = jumppack.state
  if state == Jumppack.states.rising then
    on_tick_rising(jumppack)
  elseif state == Jumppack.states.stopping then
    on_tick_stopping(jumppack)
  end -- else is "walking", do nothing
end

function Jumppack.on_tick(event)
  for _unit_number, jumppack in pairs(global.jumppacks) do
    if not jumppack.invalid then
      Jumppack.on_tick_jumppack(jumppack)
    end
  end

  for unit_number, jumppack in pairs(Jumppack.jumppacks_to_add) do
    global.jumppacks[unit_number] = jumppack
  end
  Jumppack.jumppacks_to_add = {}
  for _, unit_number in pairs(Jumppack.jumppacks_to_delete) do
    global.jumppacks[unit_number] = nil
  end
  Jumppack.jumppacks_to_delete = {}
end
Event.addListener(defines.events.on_tick, Jumppack.on_tick)

-- Creates a new jumppack object and sets character floating.
-- This method always assumes the character starts from walking state.
-- If the character is walking, set initial velocity
function Jumppack.start_on_character(character, default_state)
  default_state = default_state or Jumppack.states.rising
  local player = character.player

  if not player then return end
  if character.vehicle or global.disabled_on and global.disabled_on[character.unit_number] then return end


  local walking_state = character.walking_state
  local new_character
  if default_state == Jumppack.states.rising or default_state == Jumppack.states.flying then
    local new_character = FloatingMovement.set_source_flag(character, "jumppack", true)
    if new_character then 
      character = new_character 
    end
  end

  local jumppack = {
    state = default_state,
    character = new_character or character,
    unit_number = new_character and new_character.unit_number or character.unit_number,
    player_index = player.index,
    origin_position = origin_position
  }

  Jumppack.jumppacks_to_add[jumppack.unit_number] = jumppack
  return jumppack
end


-- function Jumppack.on_player_joined_game(event)
--   local player = game.players[event.player_index]
--   if player and player.connected and player.character then
--     if FloatingMovement.character_is_flying_version(player.character.name) then
--       local character = player.character
--       local jumppack = Jumppack.start_on_character(character, Jumppack.states.flying)
--       if jumppack then
--         jumppack.altitude = Jumppack.altitude_target
--       end
--     end
--   end
-- end
-- Event.addListener(defines.events.on_player_joined_game, Jumppack.on_player_joined_game)

function Jumppack.from_character(character)
  return global.jumppacks[character.unit_number]
end

function Jumppack.stop_jumppack(jumppack)
  jumppack.state = Jumppack.states.stopping
end

function Jumppack.on_jumppack_keypress(event)
  if event.player_index and game.players[event.player_index] and game.players[event.player_index].connected then
    local player = game.players[event.player_index]
    local character = player.character
    local can_start = character ~= nil
    can_start = can_start and get_jumppack_state(Jumppack.from_character(character)) == Jumppack.states.walking
    can_start = can_start and not util.is_cooldown_active_player("jump", player)
    if can_start then
      Jumppack.start_on_character(character)
    else
      player.play_sound{path="utility/cannot_build"}
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

  if FloatingMovement.character_is_flying_version(jumppack.character.name) then
    Jumppack.land_and_start_walking(jumppack)
  end
end
script.on_event(defines.events.on_player_driving_changed_state, Jumppack.on_player_driving_changed_state)


Event.addListener(FloatingMovement.on_character_swapped_event, function (event)
  local old_unit_number = event.old_unit_number
  local jumppack = global.jumppacks[event.old_unit_number]
  if jumppack then
    if jumppack.invalid then return end
    jumppack.unit_number = event.new_unit_number
    jumppack.character = event.new_character
    global.jumppacks[event.old_unit_number] = nil
    global.jumppacks[event.new_unit_number] = jumppack
  end
end, true)

function Jumppack.on_init(event)
  global.jumppacks = {}
end
Event.addListener("on_init", Jumppack.on_init, true)

return Jumppack
