local driver = localRequire("driver")
local gitinit = localRequire("lib/gitl/gitinit")
local filesystem = driver.filesystem

local function run()
  local projectDir = filesystem.workingDir()
  print("Initializing git repository in " .. projectDir)
  gitinit.init(projectDir)
end

return {
  subcommand = "init",
  description = "Initialize a new git project",
  run = run
}