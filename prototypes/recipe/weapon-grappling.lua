local data_util = require("data_util")

data:extend({
  {
    type = "recipe",
    name = data_util.mod_prefix .. "grappling-gun",
    result = data_util.mod_prefix .. "grappling-gun",
    enabled = true,
    energy_required = 10,
    ingredients = {
      { "steel-plate", 10 },
      { "iron-gear-wheel", 10 },
      { "pipe", 5 },
    },
    requester_paste_multiplier = 1,
  },
  {
    type = "recipe",
    name = data_util.mod_prefix .. "grappling-gun-ammo",
    result = data_util.mod_prefix .. "grappling-gun-ammo",
    enabled = true,
    energy_required = 1,
    ingredients = {
      { "iron-stick", 4 },
      { "coal", 2 },
    },
    requester_paste_multiplier = 1,
  },
})
