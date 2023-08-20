local util = require("earendel-scripts/earendel-utils")



-- Geometry
-----------------------------------------------------------


-- doPolygonsIntersect is taken from https://stackoverflow.com/questions/10962379/how-to-check-intersection-between-2-rotated-rectangles
function util.doPolygonsIntersect(a,b)
  local polygons = {a,b}
  for i=1, #polygons do
    local polygon = polygons[i]
    for i1=1, #polygon do
      local i2 = i1 % #polygon + 1
      local p1 = polygon[i1]
      local p2 = polygon[i2]
      
      local nx = p2[2] - p1[2]
      local ny = p1[1] - p2[1]
      
      local minA = 1e10
      local maxA = -1e10
      for j=1, #a do
        local projected = nx * a[j][1] + ny * a[j][2]
        if projected < minA then minA = projected end
        if projected > maxA then maxA = projected end
      end
      
      local minB = 1e10
      local maxB = -1e10
      for j=1, #b do
        local projected = nx * b[j][1] + ny * b[j][2]
        if projected < minB then minB = projected end
        if projected > maxB then maxB = projected end
      end
      
      if maxA < minB or maxB < minA then return false end
    end
  end
  return true
end


function util.rect_to_polygon(r)
  local x1 = r.left_top.x
  local y1 = r.left_top.y
  local x2 = r.right_bottom.x
  local y2 = r.right_bottom.y
  local center = util.vectors_add(r.left_top, r.right_bottom)
  center = util.vector_multiply(center, 0.5)
  local poly = {{x=x1, y=y1}, {x=x2, y=y1}, {x=x2, y=y2}, {x=x1, y=y2}}
  for k, v in pairs(poly) do
    local w = util.vectors_delta(v, center)
    w = util.rotate_vector(r.orientation or 0, w)
    w = util.vectors_add(w, center)
    poly[k] = {w.x, w.y}
  end
  return poly
end

-- not quite tested
function util.box_normal(rect, position)
  local center = util.vectors_add(rect.left_top, rect.right_bottom)
  center = util.vector_multiply(center, 0.5)
  local left_top = util.vectors_delta(rect.left_top, center)
  local right_bottom = util.vectors_delta(rect.right_bottom, center)

  position = util.vectors_delta(position, center)
  position = util.rotate_vector(rect.direction or 0, position)

  local function dist(p)
    local x = math.max(p.x - left_top.x, right_bottom.x - p.x)
    local y = math.max(p.y - left_top.y, right_bottom.y - p.y)
    return math.max(x, y)
  end

  local gradient = {x=0, y=0}
  for k, offset in pairs({x={x=1, y=0}, y={x=0, y=1}}) do
    local p = util.vectors_add(position, util.vector_multiply(offset, 1e-4))
    local p2 = util.vectors_add(position, util.vector_multiply(offset, -1e-4))
    gradient[k] = (dist(p) - dist(p2)) / 2e-4
  end

  local v = util.vector_normalise(gradient)  
  v = util.rotate_vector(-(rect.direction or 0), v)
  return v
end


function util.find_close_noncolliding_position(surface, name, position, max_radius, precision, tile_center)
  local radius = max_radius / 27
  local pr = precision / 27
  for i=1,4 do
    local p = surface.find_non_colliding_position(name, position, radius, pr, tile_center)
    if p then return p end
    radius = radius * 3
    pr = pr * 3
  end
end

function util.do_rects_intersect(r1, r2)
  local p1 = util.rect_to_polygon(r1)
  local p2 = util.rect_to_polygon(r2)
  return util.doPolygonsIntersect(p1, p2)
end

-- layered properties
-----------------------------------------------------------
-- This is a data structure which may save values for the same property in different ordered layers, and a lookup returns the value of the property in the first layer that sets it. 
-- Each layer has an identifying key and an order string.
-- This data structure probably has a name ...

function util.set_layered_property(data, layer_name, key, k, v)
  layer_name = layer_name .. key
  if not data[layer_name] then data[layer_name] = {_key = key} end
  data[layer_name][k] = v
end

function util.set_layered_properties(data, layer_name, key, properties)
  layer_name = layer_name .. key
  if not data[layer_name] then data[layer_name] =  {_key = key} end
  for k, v in pairs(properties) do
    data[layer_name][k] = v
  end
end

function util.unset_layered_properties(data, key)
  local to_delete = {}
  for k, layer in pairs(data) do
    if layer._key == key then
      table.insert(to_delete, k)
    end
  end
  for _, k in pairs(to_delete) do
    data[k] = nil
  end
end

function util.get_layered_properties_value(data, k)
  local min_layer
  local v
  for layer, layer_properties in pairs(data) do
    if layer_properties[k] ~= nil then
      if not min_layer or min_layer > layer then
        min_layer = layer
        v = layer_properties[k]
      end
    end
  end
  return v
end


-- Slightly easier remote interfaces
-----------------------------------------------------------

function util.expose_remote_interface(module, name, function_names)
  local functions = {}
  for _, k in pairs(function_names) do
    local v = module[k]
    if type(v) == "function" then
      functions[k] = v
    end
  end
  remote.add_interface(name, functions)
end

function util.expose_remote_interface_all(module, name)
  local functions = {}
  for k, v in pairs(module) do
    if type(v) == "function" then
      functions[k] = v
    end
  end
  util.remote_add_interface(name, functions)
end


-- Cooldowns
-----------------------------------------------------------

local function cooldown_on_init(event)
  global.cooldowns = {}
end
Event.on_init(cooldown_on_init)

function util.start_cooldown(key, duration)
  local value = game.tick + duration
  if not global.cooldowns[key] or global.cooldowns[key] < value then 
    global.cooldowns[key] = value 
  end
end

function util.start_cooldown_player(key, player, duration)
  if type(player) ~= "number" then player = player.index end
  key = key..player
  util.start_cooldown(key, duration)
end

function util.is_cooldown_active(key)
  if not global.cooldowns[key] then return false end
  return global.cooldowns[key] > game.tick
end

function util.is_cooldown_active_player(key, player)
  if type(player) ~= "number" then player = player.index end
  key = key..player
  return util.is_cooldown_active(key)
end

function util.reset_cooldown(key)
  global.cooldowns[key] = nil
end

function util.reset_cooldown_player(key, player)
  if type(player) ~= "number" then player = player.index end
  global.cooldowns[key..player] = nil
end



-- Logic
-----------------------------------------------------------

function util.all_wrong(t)
  for _, v in pairs(t) do
    if v then return false end
  end
  return true
end


return util
