local Migrate = {}

function Migrate.migrations()
  if not global.version then global.version = Version end
  if global.version < Version then
    --if global.version < 0003006 then Migrate.v0_3_006() end
    global.version = Version
  end
end

function Migrate.v0_3_006()
  global.player_toggle_cooldown = {}
  global.current_fuel_by_character = {}
  if global.players then
    for player_index, playerdata in pairs(global.players) do
      local player = game.get_player(player_index)
      if player and player.character and player.character.valid and playerdata.saved_fuel then
        global.current_fuel_by_character[player.character.unit_number] = playerdata.saved_fuel
        -- This will miss players who are in the middle of remote view, but whatever.
      end
    end
    global.players = nil
  end
end

local function on_configuration_changed()
  Migrate.migrations()
end
Event.addListener("on_configuration_changed", on_configuration_changed, true)


return Migrate