local driver = localRequire "driver"

local function run()
  print("Initializing git repository in " .. driver.filesystem.workingDir())
end

return {
  subcommand = "init",
  description = "Initialize a new git project",
  run = run
}