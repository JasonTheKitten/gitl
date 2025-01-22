local driver = localRequire("driver")
local getopts = localRequire("lib/getopts")
local gitinit = localRequire("lib/gitl/gitinit")
local gitclone = localRequire("lib/gitl/gitclone")
local filesystem = driver.filesystem

local function getRepositoryName(repository)
  local name = repository:match("([^/]+)$")
  if name and name:sub(-4) == ".git" then
    name = name:sub(1, -5)
  end
  if not name or name == "" then
    error("Invalid repository name")
  end
  return name
end

local function isEmptyDir(dir)
  local list = filesystem.list(dir)
  return #list == 0
end

local function cloneRepo(projectDir, repository)
  filesystem.makeDir(projectDir)
  gitinit.init(projectDir)
  gitclone.clone(projectDir, repository)
end

local function run(arguments)
  local repository = arguments.options.arguments[1]
  local name = getRepositoryName(repository)

  print("Cloning " .. repository .. " into " .. name)
  local projectDir = filesystem.combine(filesystem.workingDir(), name)

  if filesystem.exists(projectDir) and not isEmptyDir(projectDir) then
    error("Directory " .. name .. " already exists and is not empty")
  end

  xpcall(function()
    cloneRepo(projectDir, repository)
  end, function(err)
    filesystem.rm(projectDir, true)
    print("Failed to clone repository: " .. tostring(err))
  end)
end

return {
  subcommand = "clone",
  description = "Clone a remote repository",
  options = {
    arguments = { flag = getopts.flagless.collect(getopts.stop.times(1)), params = "<repository>" }
  },
  run = run
}