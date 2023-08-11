local util = require("earendel-utils")


-- layered properties
-----------------------------------------------------------
-- properties may be set at multiple "layers", each layer has an identifying order string and properties are looked up in each layer, in the order of the identifying order strings

function util.set_layered_property(data, layer, k, v)
  if not data[layer] then data[layer] = { } end
  data[layer][k] = v
end

function util.set_layered_properties(data, layer, properties)
  if not data[layer] then data[layer] = { } end
  for k, v in pairs(properties) do
    data[layer][k] = v
  end
end

function util.get_layered_properties(data, k)
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

function util.remove_layer(data, layer)
  data[layer] = nil
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


-- Logic
-----------------------------------------------------------

function util.all_wrong(t)
  for _, v in pairs(t) do
    if v then return false end
  end
  return true
end


return util
