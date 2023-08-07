local data_util = require("data_util")

data:extend({
  {
    type = "simple-entity",
    name = data_util.mod_prefix .. "grappling-gun-player-collision",
    animations = {
      {
        direction_count = 1,
        filename = "__jumppack__/graphics/blank.png",
        frame_count = 1,
        height = 1,
        line_length = 1,
        width = 1
      }
    },
    flags = {
      "not-on-map"
    },
    collision_mask = {
      "player-layer",
      "item-layer"
    },
    collision_box = {{-0.5, -0.5}, {0.5, 0.5}}
  },
  {
    type = "explosion",
    name = data_util.mod_prefix .. "grappling-gun-trigger",
    animations = {
      {
        direction_count = 1,
        filename = "__jumppack__/graphics/blank.png",
        frame_count = 1,
        height = 1,
        line_length = 1,
        width = 1
      }
    },
    flags = {
      "not-on-map"
    },
  },
  {
    type = "projectile",
    name = data_util.mod_prefix .. "grappling-gun-projectile",
    acceleration = 0,
    animation = {
      filename = "__jumppack__/graphics/entity/grappling-gun/grapple-head.png",
      width = 58,
      height = 32,
      priority = "high",
      scale = 0.5
    },
    flags = {
      "not-on-map", "placeable-off-grid"
    },
  },
  {
    type = "projectile",
    name = data_util.mod_prefix .. "grappling-gun-projectile-with-drone",
    acceleration = 0,
    animation = {
      layers = {
        {
          filename = "__jumppack__/graphics/entity/grappling-gun/grapple-head.png",
          width = 58,
          height = 32,
          priority = "high",
          scale = 0.5
        },
        {
          filename = "__jumppack__/graphics/entity/grappling-gun/grapple-on-space.png",
          width = 73,
          height = 69,
        },
      }
    },
    flags = {
      "not-on-map", "placeable-off-grid"
    },
  },
  {
    type = "simple-entity",
    name = data_util.mod_prefix .. "grapple-on-space-drone",
    picture = {
      layers = {
        {
          filename = "__jumppack__/graphics/entity/grappling-gun/grapple-on-space.png",
          width = 73,
          height = 69,
          shift = {2/32, -38/32},
        },
        {
          filename = "__jumppack__/graphics/entity/grappling-gun/grapple-on-space-glow.png",
          width = 73,
          height = 69,
          shift = {2/32, -38/32},
          draw_as_glow = true,
        },
      }
    },
    selectable_in_game = false,
    flags = {
      "not-on-map", "placeable-off-grid"
    },
    collision_mask = {},
  },
})
