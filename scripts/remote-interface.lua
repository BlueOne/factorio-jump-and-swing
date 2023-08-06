remote.add_interface(
  "jetpack",
  {

    get_jumppacks = function(data)
      if data.surface_index then
        local jumppacks = {}
        for _, jumppack in pairs(global.jumppacks) do
          if jumppack and jumppack.character and jumppack.character.valid then
            if data.surface_index == jumppack.character.surface.index then
              jumppacks[jumppack.character.unit_number] = jumppack
            end
          end
        end
        return jumppacks
      end
      return global.jumppacks
    end,

--/c remote.call("jumppack", "get_jumppack_for_character", {character=game.player.character})
    get_jumppack_for_character = Jumppack.get_jumppack_for_character,

--/c remote.call("jumppack", "is_jumppacking", {character=game.player.character})
    is_jumppacking = Jumppack.is_jumppacking,

--/c remote.call("jumppack", "is_jumppacking", {character=game.player.character})
    is_jumppacking = function(data)
      if data.character and data.character.valid then
        return global.jumppacks[data.character.unit_number] ~= nil
      else
        return false
      end
    end,

-- "current fuel" means the fuel saved on the characters. That's the fuel currently "loaded".
--/c remote.call("jumppack", "get_current_fuels")
    get_current_fuels = function()
      return global.current_fuel_by_character
    end,

--/c remote.call("jumppack", "get_current_fuel_for_character", {character=game.player.character})
    get_current_fuel_for_character = function()
      if data.character and data.character.valid then
        return global.current_fuel_by_character[data.character.unit_number]
      end
    end,

--/c remote.call("jumppack", "block_jumppack", {character=game.player.character})
    block_jumppack = function(data) -- prevents activation on character
      if data.character and data.character.valid then
        global.disabled_on = global.disabled_on or {}
        global.disabled_on[data.character.unit_number] = data.character.unit_number
      end
    end,

--/c remote.call("jumppack", "unblock_jumppack", {character=game.player.character})
    unblock_jumppack = function(data) -- allows activation on character
      if data.character and data.character.valid then
        global.disabled_on[data.character.unit_number] = nil
      end
    end,

    stop_jumppack_immediate = function(data) -- returns the new character.
      if data.character then
        local jumppack = Jumppack.from_character(data.character)
        if jumppack then
          return Jumppack.land_and_start_walking(jumppack)
        end
      end
    end,

    set_velocity = function(data)
      if data.unit_number and global.jumppacks[data.unit_number] and data.velocity and data.velocity.x and data.velocity.y then
        global.jumppacks[data.unit_number].velocity = data.velocity
      end
    end,

--/c remote.call("jumppack", "swap_jumppack_character", {new_character = luaEntity, old_character_unit_number = number, old_character = luaEntity, })
--old_character_unit_number is required, old_character is optional
    swap_jumppack_character = function(data)
      if not data then return end
      local old_unit_number = data.old_character_unit_number or (data.old_character and data.old_character.valid and data.old_character.unit_number)
      local new_unit_number = data.new_character and data.new_character.valid and data.new_character.unit_number

      if old_unit_number and new_unit_number and global.jumppacks and global.jumppacks[old_unit_number] then
        global.jumppacks[new_unit_number] = global.jumppacks[old_unit_number]
        global.jumppacks[new_unit_number].unit_number = new_unit_number
        global.jumppacks[new_unit_number].character = data.new_character
        global.jumppacks[new_unit_number].character_type = Jumppack.character_is_flying_version(data.new_character.name)
        global.jumppacks[old_unit_number] = nil
      end
    end,


-- informatron implementation
    informatron_menu = function(data)
      return Informatron.menu(data.player_index)
    end,

    informatron_page_content = function(data)
      return Informatron.page_content(data.page_name, data.player_index, data.element)
    end,
  }
)
