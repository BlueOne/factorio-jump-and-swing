



local gun = data.raw.gun["grappling-gun"]
gun.attack_parameters.cooldown = 5
gun.attack_parameters.sound = nil

local gun_trigger = data.raw.explosion["grappling-gun-trigger"]
data.raw.explosion["grappling-gun-trigger"] = nil
data.raw.explosion["jump-and-swing-grappling-gun-trigger"] = gun_trigger
gun_trigger.name = "jump-and-swing-grappling-gun-trigger"

local ammo = data.raw.ammo["grappling-gun-ammo"]
ammo.ammo_type.action[1].action_delivery.target_effects[1].entity_name = "jump-and-swing-grappling-gun-trigger"
ammo.ammo_type.action[1].action_delivery.source_effects = nil

data:extend{
    {
        name = "jump-and-swing-pump-shotgun",
        type = "sound",
        filename = "__base__/sound/pump-shotgun.ogg",
        volume = 0.5
    }
}



local grapple_tech = data.raw.technology["grappling-gun"]
local grapple_tech2 = util.copy(data.raw.technology["grappling-gun"])
local grapple_tech3 = util.copy(data.raw.technology["grappling-gun"])

grapple_tech.unit = {
  count = 50,
  time = 30,
  ingredients = {
    { "automation-science-pack", 1 },
    { "logistic-science-pack", 1 },
  },
}
grapple_tech.prerequisites = {"logistic-science-pack", "jump"}
grapple_tech.icon = "__jump-and-swing__/graphics/hook-icon-both-hands.png"
grapple_tech.icon_size = 256
grapple_tech.icon_mipmaps = 1


grapple_tech2 = util.merge{grapple_tech2, {
  name = "grappling-gun-2",
  prerequisites = { "chemical-science-pack", "grappling-gun" },
  unit = {
    count = 50,
    time = 30,
    ingredients = {
      { "automation-science-pack", 1 },
      { "logistic-science-pack", 1 },
      { "chemical-science-pack", 1 }
    }
  },
  localised_description={"technology-description.grappling-gun-2"}
}}
grapple_tech2.effects = nil
grapple_tech2.icon = "__jump-and-swing__/graphics/hook-icon-onehanded.png"
grapple_tech2.icon_size = 256
grapple_tech2.icon_mipmaps = 1

grapple_tech3 = util.merge{grapple_tech3, {
  name = "grappling-gun-3",
  prerequisites = { "chemical-science-pack", "grappling-gun-2" },
  unit = {
    count = 50,
    time = 30,
    ingredients = {
      { "automation-science-pack", 1 },
      { "logistic-science-pack", 1 },
      { "chemical-science-pack", 1 },
      { "production-science-pack", 1},
      { "utility-science-pack", 1}
    }
  },
  localised_description = {"technology-description.grappling-gun-3"}
}}
grapple_tech3.effects = nil
grapple_tech3.icon = "__jump-and-swing__/graphics/hook-icon-nohands.png"
grapple_tech3.icon_size = 256
grapple_tech3.icon_mipmaps = 1

local jump_tech = util.copy(data.raw.technology["grappling-gun"])
jump_tech.unit = {
  count = 20,
  time = 5,
  ingredients = {
    { "automation-science-pack", 1 },
  }
}
jump_tech.prerequisites = {}
jump_tech.name = "jump"
jump_tech.icon = "__jump-and-swing__/graphics/jump-icon.png"
jump_tech.icon_size = 256
jump_tech.icon_mipmaps = 4

data:extend{
  jump_tech,
  grapple_tech2,
  grapple_tech3,
}