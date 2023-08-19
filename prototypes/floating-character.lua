
-- License: Earendel FMLDOL 
-- https://docs.google.com/document/d/1z-6hZQekEHOu1Pk4z-V5LuwlHnveFLJGTjVAtjYHwMU
-- Modified by unique2 with permission from earendel


local data_util = require("data_util")

local char_list = {}

local function remove_shadows_recursive(table)
  for k, v in pairs(table) do
    if type(v) == "table" then
      if v.draw_as_shadow or k == "flipped_shadow_running_with_gun" then
        table[k] = nil
      else
        remove_shadows_recursive(v)
      end
    end
  end
end

local function set_render_layer_recursive(table, render_layer)
  for k, v in pairs(table) do
    if type(v) == "table" then
      if v.filename then
        v.render_layer = render_layer
      end
      set_render_layer_recursive(v, render_layer)
    end
  end
end

for name, character in pairs(data.raw.character) do
  if not character.prevent_jump == true then
    table.insert(char_list, name)
  end
end

for _, name in pairs(char_list) do
  local copy = table.deepcopy(data.raw.character[name])
  copy.name = copy.name .."-floating"
  --copy.running_speed = 0.00001
  copy.running_speed = 0.05
  copy.collision_mask = {"not-colliding-with-itself"}
  remove_shadows_recursive(copy)
  set_render_layer_recursive(copy.animations, "air-object")
  copy.render_layer = "air-object"
  copy.enter_vehicle_distance = 0
  copy.localised_name = {"entity-name.character-floating", {"entity-name."..name}}
  copy.flags = copy.flags or {}
  copy.has_belt_immunity = true
  if copy.water_reflection then
    copy.water_reflection = nil
  end
  if not data_util.table_contains(copy.flags, "hidden") then
    table.insert(copy.flags, "hidden")
  end

  copy.mining_with_tool_particles_animation_positions = {}
  data:extend({copy})
end

data:extend({
  {
    type = "animation",
    name = "jump-and-swing-animation-shadow",
    priority = "extra-high-no-scale",

    filename = "__base__/graphics/entity/character/level1_running_shadow-1.png",
    width = 96,
    height = 34,
    line_length = 11,
    shift = util.by_pixel(0, 2),
    direction_count = 1,
    frame_count = 88,
    animation_speed = 1,

    hr_version = {
      filename = "__base__/graphics/entity/character/hr-level1_running_shadow-1.png",
      width = 190,
      height = 68,
      line_length = 11,
      frame_count = 88,
      direction_count = 1,
      animation_speed = 1,
      scale = 0.5,
    },

    draw_as_shadow = true,
    scale = 0.5,
  }
})


