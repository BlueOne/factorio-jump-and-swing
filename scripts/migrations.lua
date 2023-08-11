local Migrations = {}

Migrations.migrations = {}

function Migrations.run_migrations()
  if not global.version then global.version = Version end
  for version, migration in pairs(Migrations.migrations) do
    if global.version < version then
      migration()
    end
  end
  global.version = Version
end

Event.register("on_configuration_changed", Migrations.run_migrations)


return Migrations