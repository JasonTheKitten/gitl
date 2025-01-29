local driver = localRequire("driver")
local getopts = localRequire("lib/getopts")
local gitrepo = localRequire("lib/gitl/gitrepo")
local gitpush = localRequire("lib/gitl/gitpush")
local gitcreds = localRequire("lib/gitl/gitcreds")

local function push(arguments)
  local gitDir = gitrepo.locateGitRepo()
  local remoteName, branchName = arguments.options.arguments[1], arguments.options.arguments[2]
  local repository = gitrepo.resolveRemoteRepo(gitDir, remoteName)
  print("Pushing branch " .. branchName .. " to remote " .. remoteName)
  gitpush.push(gitDir, repository, branchName, {
    credentialsCallback = gitcreds.userInputCredentialsHelper,
    displayStatus = print,
    indicateProgress = function(current, total, isDone)
      local totalLen = #tostring(total)
      driver.resetCursor()
      local objectCountStr = string.format("%0" .. totalLen .. "d", current) .. "/" .. tostring(total) .. " objects"
      local objectPercentage = string.format("%2d", current / total * 100) .. "%"
      local doneStr = isDone and ", done." or ""
      io.write("Compressing objects: " .. objectPercentage .. " (" .. objectCountStr .. ")" .. doneStr)
    end
  })
end

return {
  subcommand = "push",
  description = "Update remote refs along with associated objects",
  options = {
    arguments = { flag = getopts.flagless.collect(getopts.stop.times(2)), params = "<remote> <branch>" },
  },
  run = push
}