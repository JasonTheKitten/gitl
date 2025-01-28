local driver = localRequire("driver")
local getopts = localRequire("lib/getopts")
local gitinit = localRequire("lib/gitl/gitinit")
local gitclone = localRequire("lib/gitl/gitclone")
local gitcreds = localRequire("lib/gitl/gitcreds")
local filesystem = driver.filesystem

local function getRepositoryName(repository)
  if repository:sub(-1) == "/" then
    repository = repository:sub(1, -2)
  end
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
  -- TODO: Config default branch
  driver.disableCursor()
  gitclone.clone(projectDir, repository, {
    credentialsCallback = gitcreds.userInputCredentialsHelper,
    displayStatus = print,
    indicateProgress = function(current, total, isDone)
      local totalLen = #tostring(total)
      driver.resetCursor()
      local objectCountStr = string.format("%0" .. totalLen .. "d", current) .. "/" .. tostring(total) .. " objects"
      local objectPercentage = string.format("%2d", current / total * 100) .. "%"
      local doneStr = isDone and ", done." or ""
      io.write("Receiving objects: " .. objectPercentage .. " (" .. objectCountStr .. ")" .. doneStr)
    end
  })
  driver.enableCursor()
  print()
end

local function run(arguments)
  local repository = arguments.options.arguments[1]
  local name = getRepositoryName(repository)

  print("Cloning into '" .. name .. "'...")
  local projectDir = filesystem.combine(filesystem.workingDir(), name)

  if filesystem.exists(projectDir) and not isEmptyDir(projectDir) then
    error("Directory " .. name .. " already exists and is not empty")
  end

  xpcall(function()
    cloneRepo(projectDir, repository)
  end, function(err)
    print("Failed to clone repository: " .. tostring(err))
    print("Traceback: " .. debug.traceback())
    filesystem.rm(projectDir, true)
    driver.enableCursor()
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