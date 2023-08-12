
Version = "0.1.0"
Mod_Prefix = "jumppack_"

Event = require("scripts/event")
--Event = require('scripts/event')
Util = require("scripts/util") util = Util

MovementConfig = require("scripts/movement_config")
FloatingMovement = require('scripts/floating_movement')
Jumppack = require('scripts/jumppack')
Grapple = require("scripts/grapple")

Migrations = require('scripts/migrations')


-- Run this after on_tick of other mods so they can make changes first
Event.register(defines.events.on_tick, FloatingMovement.on_tick)

