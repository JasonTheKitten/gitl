local driver = localRequire("driver")
local getopts = localRequire("lib/getopts")
local gitrepo = localRequire("lib/gitl/gitrepo")
local gitref = localRequire("lib/gitl/gitref")
local filesystem = driver.filesystem

local function addExisting(gitRepo, allBranches)
  local branchesDir = filesystem.combine(gitRepo, "refs/heads")
  if not filesystem.exists(branchesDir) then return end
  for _, branch in ipairs(filesystem.list(branchesDir)) do
    local head = gitref.getRawHead(gitRepo)
    local refPath = filesystem.combine("refs/heads", branch)
    local isCurrentBranch = head and head:sub(6) == refPath

    table.insert(allBranches, { isCurrentBranch, branch })
  end

  if gitref.isDetachedHead(gitRepo) then
    local hash = gitref.getLastCommitHash(gitRepo):sub(1, 7)
    table.insert(allBranches, { true, "(HEAD detached at " .. hash .. ")" })
  end
end

local function addRemote(gitRepo, allBranches)
  local branchesDir = filesystem.combine(gitRepo, "refs/remotes")
  if not filesystem.exists(branchesDir) then return end
  for _, remote in ipairs(filesystem.list(branchesDir)) do
    for _, branch in ipairs(filesystem.list(filesystem.combine(branchesDir, remote))) do
      table.insert(allBranches, { false, remote .. "/" .. branch })
    end
  end
end

local function listBranches(gitRepo, showExisting, showRemote)
  local allBranches = {}
  if showExisting then
    addExisting(gitRepo, allBranches)
  end
  if showRemote then
    addRemote(gitRepo, allBranches)
  end

  table.sort(allBranches, function(a, b) return a[2] < b[2] end)
  for _, branch in ipairs(allBranches) do
    print((branch[1] and "*" or " ") .. " " .. branch[2])
  end
end

local function deleteBranch(gitDir, branchName)
  local branchPath = filesystem.combine(gitDir, "refs/heads", branchName)
  if not filesystem.exists(branchPath) then
    error("Branch does not exist: " .. branchName, -1)
  end
  filesystem.rm(branchPath)
end

local copy
copy = function(originalPath, newPath)
  if filesystem.isDir(originalPath) then
    filesystem.makeDir(newPath)
    for _, entry in ipairs(filesystem.list(originalPath)) do
      copy(filesystem.combine(originalPath, entry), filesystem.combine(newPath, entry))
    end
  else
    local file = assert(io.open(originalPath, "rb"))
    local data = file:read("*a")
    file:close()

    local newFile = assert(io.open(newPath, "wb"))
    newFile:write(data)
    newFile:close()
  end
end

local function renameBranch(gitDir, originalBranchName, newBranchName, force, isCopy)
  local originalBranchPath = filesystem.combine(gitDir, "refs/heads", originalBranchName)
  if not filesystem.exists(originalBranchPath) then
    error("Branch does not exist: " .. originalBranchName, -1)
  end

  local newBranchPath = filesystem.combine(gitDir, "refs/heads", newBranchName)
  if filesystem.exists(newBranchPath) then
    if not force then
      error("Branch already exists: " .. newBranchName, -1)
    end
    filesystem.rm(newBranchPath)
  end

  copy(originalBranchPath, newBranchPath)

  if not isCopy then
    local head = gitref.getActiveBranch(gitDir)
    if head == originalBranchName then
      gitref.setActiveBranch(gitDir, newBranchName)
    end

    filesystem.rm(originalBranchPath)
  end
end

local function run(arguments)
  local gitDir = assert(gitrepo.locateGitRepo())
  if arguments.options.delete then
    deleteBranch(gitDir, arguments.options.delete.arguments[1])
    return
  end

  local isNormalAction = arguments.options.copy or arguments.options.rename
  local isForceAction = arguments.options.forceCopy or arguments.options.forceRename
  local isCopy = arguments.options.copy or arguments.options.forceCopy
  local activeOption = isNormalAction or isForceAction
  if isNormalAction or isForceAction then
    local originalBranchName, newBranchName = activeOption.arguments[1], activeOption.arguments[2]
    renameBranch(gitDir, originalBranchName, newBranchName, isForceAction, isCopy)
    return
  end

  local impliedList = not arguments.options.remotes
  local allList = arguments.options.all
  listBranches(gitDir, arguments.options.list or allList or impliedList, arguments.options.remotes or allList)
end

return {
  subcommand = "branch",
  description = "List, create, or delete branches",
  options = {
    list = { flag = "list", short = "l", description = "List existing branches" },
    remotes = { flag = "remotes", short = "r", description = "List remote branches" },
    all = { flag = "all", short = "a", description = "List both remote-tracking branches and local branches" },
    delete = { flag = "delete", short = { "d", "D" }, params = "<branch>", description = "Delete a branch", multiple = getopts.stop.single },
    copy = { flag = "copy", short = "c", params = "<oldbranch> <newbranch>", description = "Copy the branch to a new branch", multiple = getopts.stop.times(2) },
    forceCopy = { flag = "force-copy", short = "C", params = "<oldbranch> <newbranch>", description = "Force copy the branch to a new branch", multiple = getopts.stop.times(2) },
    rename = { flag = "rename", short = "m", params = "<oldbranch> <newbranch>", description = "Rename a branch", multiple = getopts.stop.times(2) },
    forceRename = { flag = "force-rename", short = "M", params = "<oldbranch> <newbranch>", description = "Force rename a branch", multiple = getopts.stop.times(2) }
  },
  run = run
}