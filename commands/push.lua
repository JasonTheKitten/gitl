local driver = localRequire("driver")
local getopts = localRequire("lib/getopts")
local gitrepo = localRequire("lib/gitl/gitrepo")
local gitpush = localRequire("lib/gitl/gitpush")
local gitcreds = localRequire("lib/gitl/gitcreds")

local function push(arguments)
  local gitDir = gitrepo.locateGitRepo()
  local remoteName, branchName = arguments.options.arguments[1], arguments.options.arguments[2]
  local repository = gitrepo.resolveRemoteRepo(gitDir, remoteName)
  local forcedStr = arguments.options.force and " (forced update)" or ""
  print("Pushing branch " .. branchName .. " to remote " .. remoteName .. forcedStr)
  assert(gitpush.push(gitDir, repository, branchName, {
    credentialsCallback = gitcreds.userInputCredentialsHelper,
    displayStatus = print,
    indicateProgress = function(current, total, isDone)
      local totalLen = #tostring(total)
      driver.resetCursor()
      local objectCountStr = string.format("%0" .. totalLen .. "d", current) .. "/" .. tostring(total)
      local objectPercentage = string.format("%2d", math.floor(current / total * 100)) .. "%"
      local doneStr = isDone and ", done." or ""
      io.write("Compressing objects: " .. objectPercentage .. " (" .. objectCountStr .. ")" .. doneStr)
    end,
    force = arguments.options.force
  }))
end

return {
  subcommand = "push",
  description = "Update remote refs along with associated objects",
  options = {
    arguments = { flag = getopts.flagless.collect(getopts.stop.times(2)), params = "<remote> <branch>" },
    force = { flag = "force", short = "f", description = "Force push" },
  },
  run = push
}