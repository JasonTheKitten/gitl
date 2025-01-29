local getopts = localRequire("lib/getopts")
local gitrepo = localRequire("lib/gitl/gitrepo")
local gitref = localRequire("lib/gitl/gitref")
local gitcommits = localRequire("lib/gitl/gitcommits")
local gitmerge = localRequire("lib/gitl/gitmerge")

local function run(arguments)
  if #arguments.options.arguments < 1 then
    print("Please provide a commit to merge")
    return
  end

  local gitDir = gitrepo.locateGitRepo()
  local projectDir = gitrepo.locateProjectRepo()
  local currentCommit = gitref.getLastCommitHash(gitDir)
  local commit = assert(gitcommits.determineHashFromShortName(gitDir, arguments.options.arguments[1]))

  local mode, message, data = gitmerge.merge(gitDir, projectDir, currentCommit, commit)
  if not mode then
    print("Merge failed: " .. message)
    return
  end

  if mode == "fast-forward" then
    print("Merge: " .. message)
    print("Branch is now at " .. data)
  end
end

return {
  subcommand = "merge",
  description = "Join two or more development histories together",
  options = {
    arguments = { flag = getopts.flagless.collect(getopts.stop.times(1)), params = "<commit>" },
  },
  run = run
}