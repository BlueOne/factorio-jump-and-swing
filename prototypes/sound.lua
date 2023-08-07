local jetpack_volume = settings.startup["jetpack-volume"].value / 100

data:extend ({
  {
    type = "projectile",
    name = "jetpack-sound",
    acceleration = 0,
    animation = {
      filename = "__jetpack__/graphics/entity/character/hr-jetpack.png",
      frame_count = 1,
      height = 1,
      line_length = 1,
      priority = "high",
      width = 1
    },
    flags = { "not-on-map" },
    working_sound = {
      apparent_volume = jetpack_volume,
      sound = {
        {
          filename = "__jetpack__/sound/jetpack.ogg",
          volume = jetpack_volume
        }
      }
    }
  },
  {
    type = "sound",
    name = "jetpack-damage-fall-woosh",
    variations = {
      {filename = "__base__/sound/fight/robot-die-whoosh-01.ogg", volume = 1},
      {filename = "__base__/sound/fight/robot-die-whoosh-02.ogg", volume = 1},
      {filename = "__base__/sound/fight/robot-die-whoosh-03.ogg", volume = 1},
    }
  },
  {
    type = "sound",
    name = "jetpack-damage-fall-vox",
    variations = {
      {filename = "__base__/sound/fight/robot-die-vox-01.ogg", volume = 1},
      {filename = "__base__/sound/fight/robot-die-vox-02.ogg", volume = 1},
      {filename = "__base__/sound/fight/robot-die-vox-03.ogg", volume = 1},
      {filename = "__base__/sound/fight/robot-die-vox-04.ogg", volume = 1},
      {filename = "__base__/sound/fight/robot-die-vox-05.ogg", volume = 1},
      {filename = "__base__/sound/fight/robot-die-vox-06.ogg", volume = 1},
    }
  },
})
