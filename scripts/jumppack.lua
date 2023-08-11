local Jumppack = {}


--TODO: 
-- Action of jump button while already jumping? - airjump, dash, slow-fall


Jumppack.jump_key_event = "jumppack"
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

function Jumppack.is_jumping(character)
  local state = get_jumppack_state(Jumppack.from_character(character)) 
  return state ~= Jumppack.states.walking
end

-- remove jumping state, trigger cooldown
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
  if altitude > 0.2 then
    FloatingMovement.add_altitude(jumppack.character, -Jumppack.altitude_decrease)
  else -- Reached the floor
    Jumppack.land_and_start_walking(jumppack)
  end
end

function Jumppack.destroy(jumppack)
  if jumppack.invalid then return end
  jumppack.invalid = true
  table.insert(Jumppack.jumppacks_to_delete, jumppack.unit_number)
  FloatingMovement.unset_source_flag(jumppack.character.unit_number, "jumppack", true)
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
Event.register(defines.events.on_tick, Jumppack.on_tick)

-- Creates a new jumppack object and sets character floating.
-- Does not check if jumping is allowed, check with Jumppack.can_jump in advance!
function Jumppack.start_jump(character)

  local walking_state = character.walking_state
  local player = character.player
  local new_character = FloatingMovement.set_source_flag(character, "jumppack")
  if new_character then
    character = new_character
  end

  local jumppack = {
    state = Jumppack.states.rising,
    character = new_character or character,
    unit_number = new_character and new_character.unit_number or character.unit_number,
    player_index = player.index,
  }

  Jumppack.jumppacks_to_add[jumppack.unit_number] = jumppack
  return jumppack
end


function Jumppack.from_character(character)
  return global.jumppacks[character.unit_number]
end

-- only for remote calls
function Jumppack.update(jumppack)
  global.jumppacks[jumppack.unit_number] = jumppack
end

function Jumppack.start_fall(jumppack)
  jumppack.state = Jumppack.states.stopping
end

function Jumppack.can_jump(character)
  if not character then return false end
  if get_jumppack_state(Jumppack.from_character(character)) ~= Jumppack.states.walking then return false end

  if util.is_cooldown_active_player("jump", character.player) then return false end

  local position = FloatingMovement.ground_position(character) or character.position
  local tile = character.surface.get_tile(position)
  game.print(tile.name)
  game.print(serpent.line(FloatingMovement.is_floating(character)))
  local is_water = string.find(tile.name, "water")
  local is_shallow = string.find(tile.name, "shallow")
  --game.print("water"..is_water..", shallow"..is_shallow)
  if (is_water and not is_shallow) then
    if FloatingMovement.is_floating(character) then
      return false
    end
  end
  return true
end

function Jumppack.on_jumppack_keypress(event)
  if event.player_index and game.players[event.player_index] and game.players[event.player_index].connected then
    local player = game.players[event.player_index]
    local character = player.character
    if Jumppack.can_jump(character) then
      Jumppack.start_jump(character)
    else
      player.play_sound{path="utility/cannot_build"}
    end
  end
end
Event.register(Jumppack.jump_key_event, Jumppack.on_jumppack_keypress)

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
Event.register(defines.events.on_player_driving_changed_state, Jumppack.on_player_driving_changed_state)


Event.register_custom_event(util.on_character_swapped_event, 
---@param event CharacterSwappedEvent
function (event)
  local jumppack = global.jumppacks[event.old_unit_number]
  if jumppack then
    if jumppack.invalid then return end
    jumppack.unit_number = event.new_unit_number
    jumppack.character = event.new_character
    global.jumppacks[event.old_unit_number] = nil
    global.jumppacks[event.new_unit_number] = jumppack
  end
end)

function Jumppack.on_init()
  global.jumppacks = {}
end
Event.register("on_init", Jumppack.on_init)


util.expose_remote_interface(Jumppack, "jumppack_jump", {
  "is_jumping",
  "start_jump",
  "land_and_start_walking",
  "destroy",
  "from_character",
})


return Jumppack
