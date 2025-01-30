local driver = localRequire("driver")
local getopts = localRequire("lib/getopts")
local gitrepo = localRequire("lib/gitl/gitrepo")
local gitfetch = localRequire("lib/gitl/gitfetch")
local gitcreds = localRequire("lib/gitl/gitcreds")
local gitmerge = localRequire("lib/gitl/gitmerge")
local gitref = localRequire("lib/gitl/gitref")

local function run(arguments)
  local gitDir = gitrepo.locateGitRepo()
  local projectDir = gitrepo.locateProjectRepo()
  local remoteName, branchName = arguments.options.arguments[1], arguments.options.arguments[2]
  local repository, isURL = assert(gitrepo.resolveRemoteRepo(gitDir, remoteName))
  print("Pulling branch " .. branchName .. " from remote " .. remoteName)

  local remoteTheirHead = "refs/heads/" .. branchName
  local remoteMyHead = isURL and "FETCH_HEAD" or "refs/remotes/" .. remoteName .. "/" .. branchName

  local ok, err = gitfetch.fetch(gitDir, repository, {
    credentialsCallback = gitcreds.userInputCredentialsHelper,
    fetchRemoteHeads = { remoteTheirHead },
    fetchLocalHeads = { remoteMyHead },
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

  if not ok then
    error("Failed to fetch: " .. tostring(err), -1)
  end

  local currentCommit = gitref.getLastCommitHash(gitDir)
  local nextCommit = assert(gitref.getBranchHash(gitDir, remoteMyHead, true))

  local mode, message, data = gitmerge.merge(gitDir, projectDir, currentCommit, nextCommit)
  if not mode then
    print("Merge failed: " .. message)
    return
  end

  if mode == "fast-forward" then
    print("Merge: " .. message)
    print("Branch is now at " .. data)
    return
  end

  error("Not implemented")
end

return {
  subcommand = "pull",
  description = "Fetch from and integrate with another repository or a local branch",
  options = {
    arguments = { flag = getopts.flagless.collect(getopts.stop.times(2)), description = "<repository> <branch>" },
  },
  run = run
}