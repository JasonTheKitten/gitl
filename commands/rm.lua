local driver = localRequire("driver")
local getopts = localRequire("lib/getopts")
local gitrepo = localRequire("lib/gitl/gitrepo")
local gitdex = localRequire("lib/gitl/gitdex")
local filesystem = driver.filesystem

local function run(arguments)
  local gitDir = assert(gitrepo.locateGitRepo())
  local projectDir = assert(gitrepo.locateProjectRepo())

  local files = arguments.options.arguments
  if #files == 0 then
    error("No files specified", -1)
  end

  local indexFile = filesystem.combine(gitDir, "index")
  local index = filesystem.exists(indexFile) and gitdex.readIndex(indexFile) or gitdex.createIndex()

  -- TODO: Add with an exact path does not seem to work properly?
  for _, file in ipairs(files) do
    local indexPath = filesystem.collapse(
      filesystem.combine(
        filesystem.unprefix(projectDir, filesystem.workingDir()),
        file))
    gitdex.removeFromIndex(index, indexPath, arguments.options.recursive)
  end

  gitdex.writeIndex(index, indexFile)
end

return {
  subcommand = "rm",
  description = "Remove file contents from the index",
  options = {
    arguments = { flag = getopts.flagless.collect(getopts.stop.remaining), params = "<file>" },
    recursive = { flag = "recursive", short = "r", description = "Remove directories and their contents" }
  },
  run = run
}