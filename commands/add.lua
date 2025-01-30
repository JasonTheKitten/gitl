local driver = localRequire("driver")
local getopts = localRequire("lib/getopts")
local gitrepo = localRequire("lib/gitl/gitrepo")
local gitdex = localRequire("lib/gitl/gitdex")
local gitignore = localRequire("lib/gitl/gitignore")
local filesystem = driver.filesystem

local function run(arguments)
  local gitDir = assert(gitrepo.locateGitRepo())
  local projectDir = assert(gitrepo.locateProjectRepo())

  local files = arguments.options.arguments
  if #files == 0 then
    error("No files specified", -1)
  end

  local filter = gitignore.createFileFilter(projectDir)
  local indexFile = filesystem.combine(gitDir, "index")
  local index = filesystem.exists(indexFile) and gitdex.readIndex(indexFile) or gitdex.createIndex()

  -- TODO: Add with an exact path does not seem to work properly?
  for _, file in ipairs(files) do
    local path = filesystem.combine(filesystem.workingDir(), file)
    if not filesystem.exists(path) then
      error("File does not exist: " .. file, -1)
    end
    local indexPath = filesystem.collapse(
      filesystem.combine(
        filesystem.unprefix(projectDir, filesystem.workingDir()),
        file))
    gitdex.addToIndex(index, path, indexPath, filter, gitDir)
    gitdex.clearOldIndexEntries(index, path, indexPath, filter)
  end

  gitdex.writeIndex(index, indexFile)
end

return {
  subcommand = "add",
  description = "Add file contents to the index",
  options = {
    arguments = { flag = getopts.flagless.collect(getopts.stop.times(1)), params = "<file>" },
  },
  run = run
}