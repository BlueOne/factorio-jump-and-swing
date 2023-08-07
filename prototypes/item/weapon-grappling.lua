local data_util = require("data_util")

data:extend({
  {
    type = "ammo-category",
    name = "grappling",
    bonus_gui_order = "k-d",
  },
  {
    type = "gun",
    name = data_util.mod_prefix .. "grappling-gun",
    attack_parameters = {
      ammo_category = "grappling",
      cooldown = 60,
      movement_slow_down_factor = 0.25,
      damage_modifier = 1,
      range = 20,
      type = "projectile",
      sound = {
        {
          filename = "__base__/sound/pump-shotgun.ogg",
          volume = 0.5
        },
      },
    },
    icon = "__jumppack__/graphics/icons/grappling-gun.png",
    icon_size = 64,
    order = "z-g[grappling]",
    stack_size = 5,
    subgroup = "gun",
  },
  {
    type = "ammo",
    name = data_util.mod_prefix .. "grappling-gun-ammo",
    ammo_type =
    {
      category = "grappling",
      target_type = "direction",
      action = {
        {
          type = "direct",
          action_delivery = {
            type = "instant",
            source_effects =
            {
              {
                type = "create-explosion",
                entity_name = "explosion-gunshot"
              }
            },
            target_effects = {
              {
                type = "create-entity",
                entity_name = data_util.mod_prefix .. "grappling-gun-trigger",
                trigger_created_entity = true,
                show_in_tooltip = false,
              },
            }
          }
        },
      }
    },
    icon = "__jumppack__/graphics/icons/grappling-gun-ammo.png",
    icon_size = 64,
    magazine_size = 10,
    order = "z-g[grappling]",
    stack_size = 200,
    subgroup = "ammo",
  },
})
data.raw.explosion["explosion-hit"].flags = data.raw.explosion["explosion-hit"].flags or {}
table.insert(data.raw.explosion["explosion-hit"].flags, "placeable-off-grid")
