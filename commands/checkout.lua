local driver = localRequire("driver")
local utils = localRequire("lib/utils")
local getopts = localRequire("lib/getopts")
local gitrepo = localRequire("lib/gitl/gitrepo")
local gitstat = localRequire("lib/gitl/gitstat")
local gitobj = localRequire("lib/gitl/gitobj")
local gitcheckout = localRequire("lib/gitl/gitcheckout")
local filesystem, readAll = driver.filesystem, utils.readAll

local DEFAULT_OVERWITE_ERROR_MESSAGE =
  "You have local changes that could be overwritten by the checkout!\n"
  .. "Please commit your changes or stash them before you switch branches."

-- TODO: Better, more lenient conflict handling
-- Also, what if new branch would overwrite a gitignore'd file?
local function ensureNoFilesStaged(gitDir, projectDir)
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
      error("Branch does not exist: " .. branchName)
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

local function run(arguments)
  local gitDir = assert(gitrepo.locateGitRepo())

  -- Start with the simplist case
  if arguments.options.branch then
    if #arguments.options.arguments == 0 then
      error("No branch name specified")
    end
    gitcheckout.switchToNewBranch(gitDir, arguments.options.arguments[1])
    return
  end

  if #arguments.options.arguments == 0 then
    return -- TODO: This is supposed to list staged files
  end

  -- Now the hard one
  local branchName = arguments.options.arguments[1]
  switchToExistingBranch(gitDir, branchName, arguments)
end

return {
  subcommand = "checkout",
  description = "Switch branches or restore working tree files",
  options = {
    arguments = { flag = getopts.flagless.collect(getopts.stop.remaining), params = "<branch>" },
    branch = { flag = "branch", short = "b", description = "Create a new branch and switch to it" },
    force = { flag = "force", short = "f", description = "Proceed even if the index or the working tree differs from HEAD" }
  },
  run = run
}