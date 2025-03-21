local driver = localRequire("driver")
local utils = localRequire("lib/utils")
local getopts = localRequire("lib/getopts")
local gitrepo = localRequire("lib/gitl/gitrepo")
local gitstat = localRequire("lib/gitl/gitstat")
local gitobj = localRequire("lib/gitl/gitobj")
local gitcheckout = localRequire("lib/gitl/gitcheckout")
local gitcommits = localRequire("lib/gitl/gitcommits")
local gitconfig = localRequire("lib/gitl/gitconfig")
local gitref = localRequire("lib/gitl/gitref")
local filesystem, readAll = driver.filesystem, utils.readAll

local DEFAULT_OVERWITE_ERROR_MESSAGE =
  "You have local changes that could be overwritten by the checkout!\n"
  .. "Please commit your changes before you switch branches."

local DETACHED_HEAD_MESSAGE = [[Note: switching to '$BRANCH_NAME'.

You are in 'detached HEAD' state. You can look around, make experimental
changes and commit them, and you can discard any commits you make in this
state without impacting any branches by switching back to a branch.

If you want to create a new branch to retain commits you create, you may
do so (now or later) by using -b with the checkout command. Example:

  git checkout -b <new-branch-name>

Turn off this advice by setting config variable advice.detachedHead to false]]

-- TODO: Better, more lenient conflict handling
-- Also, what if new branch would overwrite a gitignore'd file?
local function ensureNoFilesStaged(gitDir, projectDir)
  local currentCommitHash = gitref.getLastCommitHash(gitDir)
  if not currentCommitHash then
    return true
  end

  local differences = gitstat.stat(gitDir, projectDir)
  local checks = {
    differences.workingDirChanges.insertions,
    differences.workingDirChanges.deletions,
    differences.workingDirChanges.modifications,
    differences.treeChanges.insertions,
    differences.treeChanges.deletions,
    differences.treeChanges.modifications
  }

  for _, check in ipairs(checks) do
    if #check > 0 then
      print(DEFAULT_OVERWITE_ERROR_MESSAGE)
      return false
    end
  end

  return true
end

local function switchToExistingBranch(gitDir, branchName, arguments)
  local newCommitHash, newHead
  if gitobj.objectExists(gitDir, branchName) then
    newCommitHash = branchName
    newHead = branchName
  else
    local refPath = filesystem.combine(gitDir, "refs/heads", branchName)
    if not filesystem.exists(refPath) then
      error("Branch does not exist: " .. branchName, -1)
    end
    newCommitHash = readAll(refPath):match("([^\n]+)")
    newHead = "ref: refs/heads/" .. branchName
  end

  local projectDir = assert(gitrepo.locateProjectRepo())
  if not arguments.options.force and not ensureNoFilesStaged(gitDir, projectDir) then
    return
  end

  gitcheckout.switchToExistingBranch(gitDir, projectDir, newCommitHash, newHead)
end

local function getBranchName(gitDir, arguments)
  local branchName, isAttached = gitcommits.determineHashFromShortName(gitDir, arguments.options.arguments[1], true)
  if not isAttached and gitconfig.get(gitDir, "advice.detachedHead", true, nil, "boolean") then
    local message = DETACHED_HEAD_MESSAGE:gsub("$BRANCH_NAME", branchName)
    print(message)
  end

  return branchName
end

local function run(arguments)
  local gitDir = assert(gitrepo.locateGitRepo())

  -- Start with the simplist case
  if arguments.options.branch or arguments.options.orphaned then
    if #arguments.options.arguments == 0 then
      error("No branch name specified", -1)
    end

    local branchName = arguments.options.arguments[1]
    local ok, err = gitcheckout.switchToNewBranch(gitDir, branchName, arguments.options.orphaned)
    if not ok then
      error(err, -1)
    end
    return
  end

  if #arguments.options.arguments == 0 then
    return -- TODO: This is supposed to list staged files
  end

  -- Now the hard one
  local branchName = getBranchName(gitDir, arguments)
  switchToExistingBranch(gitDir, branchName, arguments)
end

return {
  subcommand = "checkout",
  description = "Switch branches",
  options = {
    arguments = { flag = getopts.flagless.collect(getopts.stop.remaining), params = "<branch>" },
    branch = { flag = "branch", short = "b", description = "Create a new branch and switch to it" },
    force = { flag = "force", short = "f", description = "Proceed even if the index or the working tree differs from HEAD" },
    orphaned = { flag = "orphan", description = "Create a new branch with no history" }
  },
  run = run
}