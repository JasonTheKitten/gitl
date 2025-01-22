local driver = localRequire("driver")
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


local function run(arguments)
  local gitDir = assert(gitrepo.locateGitRepo())
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
  },
  run = run
}