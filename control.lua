
Version = 0001000 -- 0.1.0

Util = require("scripts/util") util = Util
Event = require('scripts/event')
Settings = require("scripts/settings")
Informatron = require('scripts/informatron')
Jumppack = require('scripts/jumppack')
JumppackGraphicsSound = require("scripts/jumppack-graphics-sound")
--Grapple = require("scripts/grapple")

require('scripts/remote-interface')

Migrate = require('scripts/migrate')

function raise_event(event_name, event_data)
  local responses = {}
  for interface_name, interface_functions in pairs(remote.interfaces) do
      if interface_functions[event_name] then
          responses[interface_name] = remote.call(interface_name, event_name, event_data)
      end
  end
  return responses
end

