local driver = localRequire("driver")
local utils = localRequire("lib/utils")
local getopts = localRequire("lib/getopts")
local gitdiff = localRequire("lib/gitl/gitdiff")
local gitdex = localRequire("lib/gitl/gitdex")
local gitrepo = localRequire("lib/gitl/gitrepo")
local gitcommits = localRequire("lib/gitl/gitcommits")
local gitobj = localRequire("lib/gitl/gitobj")
local filesystem, readAll = driver.filesystem, utils.readAll

local function noIndexDiff(arguments, writeCallback)
  local files = arguments.options.arguments
  if files[1] ~= "--" then
    error("No -- specified!", -1)
  end
  if #files < 3 then
    error("Not enough files specified!", -1)
  end

  local workingDir = filesystem.workingDir()
  local file1 = filesystem.combine(workingDir, files[2])
  local file2 = filesystem.combine(workingDir, files[3])

  local contents1 = readAll(file1)
  local contents2 = readAll(file2)

  local diff = gitdiff.diff(contents1, contents2)
  local diffContent = gitdiff.formatDiffContent(diff, 3)
  
  writeCallback(diffContent)
end

-- TODO: Show diffs between specific paths
local function run(arguments)
  local longMessageDisplayHandle = driver.openLongMessageDisplay()
  local writeCallback = function(...)
    longMessageDisplayHandle:write(...)
  end

  if arguments.options.noIndex then
    noIndexDiff(arguments, writeCallback)
    return longMessageDisplayHandle:close()
  end

  for i, file in ipairs(arguments.options.arguments) do
    if file == "--" then
      error("Don't yet support -- for diffs, other than when using no-index")
    end
  end

  local gitDir = gitrepo.locateGitRepo()
  local projectDir = filesystem.workingDir()
  local diffFormatterOptions = gitdiff.createTreeDiffFormatterOptions(writeCallback, 3)

  local hash1
  if #arguments.options.arguments >= 1 then
    hash1 = assert(gitcommits.determineHashFromShortName(gitDir, arguments.options.arguments[1]))
  end
  if #(arguments.options.arguments) >= 2 then
    local commit1 = gitobj.readAndDecodeObject(gitDir, hash1, "commit")
    local hash2 = assert(gitcommits.determineHashFromShortName(gitDir, arguments.options.arguments[2]))
    local commit2 = gitobj.readAndDecodeObject(gitDir, hash2, "commit")
    
    gitdiff.diffTree(gitDir, commit1.tree, commit2.tree, diffFormatterOptions)
    return longMessageDisplayHandle:close()
  end
  if hash1 then
    local index = gitdex.readIndex(filesystem.combine(gitDir, "index"))
    gitdiff.diffStaged(gitDir, index, diffFormatterOptions, hash1)
    return longMessageDisplayHandle:close()
  end

  local indexFile = filesystem.combine(gitDir, "index")
  local index = filesystem.exists(indexFile) and gitdex.readIndex(indexFile) or gitdex.createIndex()
  if arguments.options.cached then
    gitdiff.diffStaged(gitDir, index, diffFormatterOptions)
  else
    gitdiff.diffWorking(gitDir, projectDir, index, diffFormatterOptions)
  end

  longMessageDisplayHandle:close()
end

return {
  subcommand = "diff",
  description = "Show changes between commits, commit and working tree, etc",
  options = {
    arguments = { flag = getopts.flagless.collect(getopts.stop.remaining), params = "<options> [--] <path>" },
    noIndex = { flag = "no-index", description = "Compare two files against each other, instead of the index" },
    cached = { flag = "cached", description = "Show changes between the index and the last commit" },
  },
  run = run
}