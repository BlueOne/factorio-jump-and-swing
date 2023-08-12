



local gun = data.raw.gun["grappling-gun"]
gun.attack_parameters.cooldown = 5
gun.attack_parameters.sound = nil

local gun_trigger = data.raw.explosion["grappling-gun-trigger"]
data.raw.explosion["grappling-gun-trigger"] = nil
data.raw.explosion["jumppack-grappling-gun-trigger"] = gun_trigger
gun_trigger.name = "jumppack-grappling-gun-trigger"

local ammo = data.raw.ammo["grappling-gun-ammo"]
ammo.ammo_type.action[1].action_delivery.target_effects[1].entity_name = "jumppack-grappling-gun-trigger"
ammo.ammo_type.action[1].action_delivery.source_effects = nil

data:extend{
    {
        name = "jumppack-pump-shotgun",
        type = "sound",
        filename = "__base__/sound/pump-shotgun.ogg",
        volume = 0.5
    }
}




local grapple_tech2 = util.copy(data.raw.technology["grappling-gun"])
local grapple_tech3 = util.copy(data.raw.technology["grappling-gun"])

grapple_tech2 = util.merge{grapple_tech2, {
  name = "grappling-gun-2",
  prerequisites = { "logistics-2", "grappling-gun" },
  unit = {
    count = 200,
    time = 30,
    ingredients = {
      { "automation-science-pack", 1 },
      { "logistic-science-pack", 1 },
    }
  },
}}
grapple_tech2.effects = nil


grapple_tech3 = util.merge{grapple_tech3, {
  name = "grappling-gun-3",
  prerequisites = { "chemical-science-pack", "grappling-gun-2" },
  unit = {
    count = 200,
    time = 30,
    ingredients = {
      { "automation-science-pack", 1 },
      { "logistic-science-pack", 1 },
      { "chemical-science-pack", 1 }
    }
  },
}}
grapple_tech3.effects = nil

data:extend{
  grapple_tech2,
  grapple_tech3,
}