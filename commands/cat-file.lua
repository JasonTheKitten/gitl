local getopts = localRequire("lib/getopts")
local gitobj = localRequire("lib/gitl/gitobj")
local gitrepo = localRequire("lib/gitl/gitrepo")

local function run(arguments)
  local gitDir = gitrepo.locateGitRepo()
  if not gitDir then
    error("Not a git repository")
  end
  local realArguments = arguments.options.arguments
  local objectType, hash = realArguments[1], realArguments[2]
  local type, content = gitobj.readObject(gitDir, hash)
  if type ~= objectType then
    print("Warning: Object type mismatch: " .. type .. " != " .. objectType)
  end
  print(gitobj.decodeObjectData(content, objectType).formatted)
end

return {
  subcommand = "cat-file",
  description = "Provide contents or details of repository objects",
  options = {
    arguments = { flag = getopts.flagless.collect(getopts.stop.times(2)), description = "<type> <hash>" },
  },
  run = run
}