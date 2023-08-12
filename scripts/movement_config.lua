local MovementConfig = {}

function MovementConfig.can_grapple_colliding(character)
  if character.force and character.force.technologies["grappling-gun-3"].researched then
    return true
  else
    return false
  end
end

function MovementConfig.can_jump_colliding(character)
  if character.force and character.force.technologies["grappling-gun-3"].researched then
    return true
  else
    return false
  end
end

function MovementConfig.grapple_range(character)
  if character.force.technologies["grappling-gun-3"].researched then
    return 20
  elseif character.force and character.force.technologies["grappling-gun-2"].researched then
    return 12
  else
    return 12
  end
end

function MovementConfig.grapple_cooldown(character)
  if character.force then 
    if character.force.technologies["grappling-gun-3"].researched then
      return 25
    elseif character.force.technologies["grappling-gun-2"].researched then
      return 50
    else
      return 300
    end
  end
end

function MovementConfig.grapple_duration(character)
  if character.force and character.force.technologies["grappling-gun-2"].researched then
    return 40
  else
    return 40
  end
end

function MovementConfig.grapple_pull_acceleration_threshold(character)
  if character.force and character.force.technologies["grappling-gun-2"].researched then
    return 0.8
  else
    return 0.4
  end
end


return MovementConfig