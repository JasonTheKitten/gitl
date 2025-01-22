local driver = localRequire("driver")
local utils = localRequire("lib/utils")
local getopts = localRequire("lib/getopts")
local gitdiff = localRequire("lib/gitl/gitdiff")
local filesystem, readAll = driver.filesystem, utils.readAll

local function noIndexDiff(arguments)
  local files = arguments.options.arguments
  if files[1] ~= "--" then
    error("No -- specified!")
  end
  if #files < 3 then
    error("No files specified!")
  end

  local workingDir = filesystem.workingDir()
  local file1 = filesystem.combine(workingDir, files[2])
  local file2 = filesystem.combine(workingDir, files[3])

  local contents1 = readAll(file1)
  local contents2 = readAll(file2)

  local diff = gitdiff.diff(contents1, contents2)
  local diffContent = gitdiff.formatDiffContent(diff, 3)
  
  io.write(diffContent)
end

local function run(arguments)
  if arguments.options.noIndex then
    return noIndexDiff(arguments)
  end

  error("Not implemented")
end

return {
  subcommand = "diff",
  description = "Show changes between commits, commit and working tree, etc",
  options = {
    arguments = { flag = getopts.flagless.collect(getopts.stop.remaining), params = "<options> [--] <path>" },
    noIndex = { flag = "no-index", description = "Compare two files against each other, instead of the index" }
  },
  run = run
}