local MovementConfig = {}



local function compute_tech_level(player)
  if not player then return -1 end
  local tech = player.force.technologies
  if tech["grappling-gun-3"].researched then return 3 end
  if tech["grappling-gun-2"].researched then return 2 end
  if tech["grappling-gun"].researched then return 1 end
  if tech.jump.researched then return 0 end
  return -1
end

local function compute_autojump(player)
  if not player then 
    return settings.player["jump-and-swing_autojump"].value
  end
  return settings.get_player_settings(player)["jump-and-swing_autojump"].value
end

local function compute_environment_collision()
  global.MovementConfig.collide_with_environment =settings.global["jump-and-swing_collide-with-environment"].value
end

local function player_index(player)
  local player_index
  if not player then player_index = -1 else player_index = player.index end
  return player_index
end

local function update_config(player)
  local player_index = player_index(player)
  global.MovementConfig.tech_level[player_index] = compute_tech_level(player)
  global.MovementConfig.autojump[player_index] = compute_autojump(player)
end

local function update_all()
  for _, player in pairs(game.connected_players) do
    update_config(player)
  end
  update_config()
  compute_environment_collision()
end

Event.register({
  defines.events.on_runtime_mod_setting_changed,
  defines.events.on_research_finished,
  defines.events.on_research_reversed,
  defines.events.on_player_created,
}, update_all)


Event.on_init(function()
  global.MovementConfig = { tech_level = {}, autojump = {}, collide_with_environment = false }
end)

local function level(character)
  if not character then return -1 end
  return global.MovementConfig.tech_level[player_index(character.player)]
end

function MovementConfig.can_grapple_colliding(character)
  if level(character) >= 2 then return true else return false end
end

function MovementConfig.can_jump_colliding(character)
  if level(character) >= 2 then return true else return false end
end

function MovementConfig.grapple_range(character)
  local level = level(character)
  local values = {[-1]=12, [0]=12, [1]=12, [2]=25, [3]=40}
  return values[level]
end

function MovementConfig.grapple_cooldown(character)
  --local values = {[-1]=80, [0]=80, [1]=40, [2]=25, [3]=25}
  local values = {[-1]=80, [0]=80, [1]=40, [2]=40, [3]=40}
  return values[level(character)]
end

function MovementConfig.grapple_duration(character)
  local level = level(character)
  local values = {[-1]=30, [0]=30, [1]=40, [2]=40, [3]=50}
  local multiplier = 1
  if not MovementConfig.autojump(character) then multiplier = 3 end
  return values[level] * multiplier
end

function MovementConfig.grapple_pull_acceleration_threshold(character)
  local level = level(character)
  local values = {[-1]=0.4, [0]=0.4, [1]=0.5, [2]=0.7, [3]=2}
  return values[level]
end

function MovementConfig.grapple_initial_speed_boost(character)
  local level = level(character)
  local values = {[-1]=0., [0]=0., [1]=0., [2]=0.1, [3]=0.2}
  return values[level]
end

function MovementConfig.grapple_pull_acceleration(character)
  local level = level(character)
  local values = {[-1]=0.02, [0]=0.02, [1]=0.02, [2]=0.028, [3]=0.04}
  return values[level]
end

function MovementConfig.autojump(character)
  if not character then return false end
  return global.MovementConfig.autojump[player_index(character.player)]
end

function MovementConfig.collide_with_environment()
  return global.MovementConfig.collide_with_environment
end


return MovementConfig