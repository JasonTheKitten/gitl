local getopts = localRequire("lib/getopts")
local gitobj = localRequire("lib/gitl/gitobj")
local gitrepo = localRequire("lib/gitl/gitrepo")
local gitcommits = localRequire("lib/gitl/gitcommits")

local function run(arguments)
  local gitDir = assert(gitrepo.locateGitRepo())
  local realArguments = arguments.options.arguments
  local objectType, hash = realArguments[1], realArguments[2]
  hash = assert(gitcommits.determineHashFromShortName(gitDir, hash))
  local type, content = gitobj.readObject(gitDir, hash)
  if type ~= objectType then
    print("Warning: Object type mismatch: " .. type .. " != " .. objectType)
  end
  io.write(gitobj.decodeObjectData(content, objectType).formatted)
end

return {
  subcommand = "cat-file",
  description = "Provide contents or details of repository objects",
  options = {
    arguments = { flag = getopts.flagless.collect(getopts.stop.times(2)), description = "<type> <hash>" },
  },
  run = run
}