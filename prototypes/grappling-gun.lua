



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