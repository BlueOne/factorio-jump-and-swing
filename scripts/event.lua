local Event = require("__stdlib__/stdlib/event/event.lua")

local remote_events = {}
function Event.register_custom_event(name, handler, filter, pattern, options)
  local id = Event.get_event_name(name)
  if not id then id = Event.generate_event_name(name) end
  Event.register(id, handler, filter, pattern, options)
  if not filter and not pattern then
    remote_events[name] = handler
  end
end

local function setup_remote_event_interface()
  remote.add_interface("jump-and-swing_events", remote_events)
end
Event.on_load(setup_remote_event_interface)
Event.on_init(setup_remote_event_interface)

function Event.raise_remote_event(event_name, event_table)
  local responses = {}
  for interface_name, interface_functions in pairs(remote.interfaces) do
      if interface_functions[event_name] then
          responses[interface_name] = remote.call(interface_name, event_name, event_table)
      end
  end
  return responses
end

-- Raise a custom-generated event and call matching remote interfaces
function Event.raise_custom_event(event_name, event_table)
  -- if event_name == "on_character_swapped" then error(serpent.line(event_table.old_character.valid)) end
  local id = Event.get_event_name(event_name)
  Event.raise_remote_event(event_name, event_table)
  if id then
    Event.raise_event(id, event_table)
  end
end

remote.add_interface(Mod_Prefix.."Event", {
  get_event_id = Event.get_event_name
})

-- Not tested. Sorry. 
-- Call only before on_init
-- If not using stdlib, see https://github.com/Bilka2/AbandonedRuins/blob/b344cd3d598cedc7a77a484ab3f9efe4c63e229d/control.lua#L215
function Event.register_custom_event_external(event_name, handler, filter, pattern, options)
  local function deferred_register()
    local event_id
    for name, interface in pairs(remote.interfaces) do
      if interface["get_event_id"] then
        event_id = remote.call(name, "get_event_id", event_name)
      end
    end
    if event_id then
      -- If you are not using stdlib, replace this with script.register(..)
      Event.register(event_id, handler, filter, pattern, options)
    end
  end

  Event.on_init(deferred_register)
  Event.on_load(deferred_register)
end



return Event