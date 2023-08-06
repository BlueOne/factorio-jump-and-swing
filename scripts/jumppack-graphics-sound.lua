local JumppackGraphicsSound = {}

function JumppackGraphicsSound.update_graphics(jumppack)
  if jumppack.character_type == "land" then return end

  local frame = jumppack.character.orientation * 100

  if (not jumppack.animation_shadow) or not rendering.is_valid(jumppack.animation_shadow) then
    jumppack.animation_shadow = rendering.draw_animation{
      animation = Jumppack.name_jumppack_shadow,
      surface = jumppack.character.surface,
      target = jumppack.character,
      target_offset = {x = Jumppack.shadow_base_offset.x + jumppack.altitude, y = Jumppack.shadow_base_offset.y + jumppack.altitude},
      animation_speed = 0,
      animation_offset = frame,
      tint = {1., 1., 1., 0.5}
    }
  else
    rendering.set_target(jumppack.animation_shadow, jumppack.character,
      {x = Jumppack.shadow_base_offset.x + jumppack.altitude, y = Jumppack.shadow_base_offset.y + jumppack.altitude})
    rendering.set_animation_offset(jumppack.animation_shadow, frame)
  end

end


local function create_particle_circle(surface, position, nb_particles, particle_name, particle_speed)
  for orientation=0, 1, 1/nb_particles do
    local fuzzed_orientation = orientation + math.random() * 0.1
    local vector = util.orientation_to_vector(fuzzed_orientation, particle_speed)
    surface.create_particle({name = particle_name,
    position = {position.x + vector.x, position.y + vector.y},
    movement = vector,
    height = 0.2,
    vertical_speed = 0.1,
    frame_speed = 0.4}
  )
  end
end

local NB_DUST_PUFFS = 14
local NB_WATER_DROPLETS = 20
function JumppackGraphicsSound.create_land_effects(character, landing_tile, particle_mult, speed_mult)
  local position = character.position
  if not particle_mult then particle_mult = 1 end
  if not speed_mult then speed_mult = 1 end

  if string.find(landing_tile.name, "water", 1, true) then
    -- Water splash
    create_particle_circle(character.surface, position, NB_WATER_DROPLETS * particle_mult, "water-particle", 0.05 * speed_mult)
    character.surface.play_sound({path="tile-walking/water-shallow", position=position})
  else
    -- Dust
    local particle_name = landing_tile.name .. "-dust-particle"
    if not game.particle_prototypes[particle_name] then
      particle_name = "sand-1-dust-particle"
    end
    create_particle_circle(character.surface, position, NB_DUST_PUFFS * particle_mult, particle_name, 0.1 * speed_mult)
    local sound_path = "tile-walking/"..landing_tile.name
    if game.is_valid_sound_path(sound_path) then
      character.surface.play_sound({path=sound_path, position=position})
    end
  end
end


function JumppackGraphicsSound.cleanup(jumppack)
  if jumppack.sound and jumppack.sound.valid then
    jumppack.sound.destroy()
  end
end


return JumppackGraphicsSound
