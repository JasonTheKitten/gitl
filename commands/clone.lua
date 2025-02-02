local driver = localRequire("driver")
local getopts = localRequire("lib/getopts")
local gitinit = localRequire("lib/gitl/gitinit")
local gitclone = localRequire("lib/gitl/gitclone")
local gitcreds = localRequire("lib/gitl/gitcreds")
local gitconfig = localRequire("lib/gitl/gitconfig")
local gitcheckout = localRequire("lib/gitl/gitcheckout")
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
    error("Invalid repository name", -1)
  end
  return name
end

local function isEmptyDir(dir)
  local list = filesystem.list(dir)
  return #list == 0
end

local function cloneRepo(projectDir, arguments, repository)
  filesystem.makeDir(projectDir)
  gitinit.init(projectDir)
  
  local gitDir = filesystem.combine(projectDir, ".git")
  gitconfig.set(gitDir, "remote.origin.url", repository)

  driver.disableCursor()
  local branchHash, newHead = gitclone.clone(projectDir, repository, {
    credentialsCallback = gitcreds.userInputCredentialsHelper,
    displayStatus = print,
    indicateProgress = function(current, total, isDone)
      local totalLen = #tostring(total)
      driver.resetCursor()
      local objectCountStr = string.format("%0" .. totalLen .. "d", current) .. "/" .. tostring(total)
      local objectPercentage = string.format("%2d", math.floor(current / total * 100)) .. "%"
      local doneStr = isDone and ", done." or ""
      io.write("Receiving objects: " .. objectPercentage .. " (" .. objectCountStr .. ")" .. doneStr)
    end,
    channelCallbacks = {
      [2] = function(message)
        for line in message:gmatch("[^\r]+") do
          driver.resetCursor()
          io.write("remote: " .. line)
        end
      end,
      [3] = function(message)
        print("error: " .. message)
      end
    },
    defaultBranch = arguments.options.branch and arguments.options.branch.arguments[1],
    depth = arguments.options.depth and tonumber(arguments.options.depth.arguments[1])
  })
  driver.enableCursor()
  if not arguments.options.depth then -- TODO: Properly detect if a newline is needed
    print()
  end
  if not branchHash then
    error(tostring(newHead), -1)
  end

  if not arguments.options.nocheckout then
    gitcheckout.freshCheckoutExistingBranch(gitDir, projectDir, branchHash, newHead)
  end
end

local function run(arguments)
  local repository = arguments.options.arguments[1]
  local name = arguments.options.arguments[2] or getRepositoryName(repository)

  print("Cloning into '" .. name .. "'...")
  local projectDir = filesystem.combine(filesystem.workingDir(), name)

  if filesystem.exists(projectDir) and not isEmptyDir(projectDir) then
    error("Directory " .. name .. " already exists and is not empty", -1)
  end

  xpcall(function()
    cloneRepo(projectDir, arguments, repository)
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
    arguments = { flag = getopts.flagless.collect(getopts.stop.remaining), params = "<repository> [<name>]" },
    nocheckout = { flag = "no-checkout", description = "Don't checkout the repository after cloning" },
    branch = { flag = "branch", short = "b", params = "<branch>", description = "Checkout a specific branch after cloning", multiple = getopts.stop.single },
    depth = { flag = "depth", short = "d", params = "<depth>", description = "Create a shallow clone with a history truncated to the specified number of commits", multiple = getopts.stop.single }
  },
  run = run
}