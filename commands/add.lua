local driver = localRequire "driver"
local getopts = localRequire("lib/getopts")
local gitobj = localRequire("lib/gitl/gitobj")
local gitrepo = localRequire("lib/gitl/gitrepo")
local gitdex = localRequire("lib/gitl/gitdex")
local filesystem = driver.filesystem

local PROHIBITED_FILES = {
  ["."] = true,
  [".."] = true,
  [".git"] = true
}

local function compareEntries(entry1, entry2)
  if entry1 == nil then
    return false
  end
  for key, value in pairs(entry1) do
    local altVal = entry2[key]
    if (altVal ~= nil) and (value ~= altVal) and (key ~= "hash") and (key ~= "name") then
      return false
    end
  end
  return true
end

local function addToIndex(index, path, indexPath, filter, gitDir)
  if indexPath:sub(1, 1) == "/" then
    indexPath = indexPath:sub(2)
  end
  path = filesystem.collapse(path)

  local existingEntry = gitdex.getEntry(index, indexPath)
  if not filter(indexPath) then
    -- Ignore
  elseif filesystem.isDir(path) then
    for _, file in ipairs(filesystem.list(path)) do
      addToIndex(index, filesystem.combine(path, file), filesystem.combine(indexPath, file), filter, gitDir)
    end
  elseif filesystem.isFile(path) and not compareEntries(existingEntry, filesystem.attributes(path)) then
    local fileAttributes = filesystem.attributes(path)

    local fileHandle = assert(io.open(path, "rb"))
    local content = fileHandle:read("*a")
    fileHandle:close()

    fileAttributes.hash = gitobj.writeObject(gitDir, content, "blob")
    fileAttributes.name = indexPath
    gitdex.updateEntry(index, indexPath, fileAttributes)
  end
end

local function run(arguments)
  local filter = function(filename)
    return not PROHIBITED_FILES[filename]
  end

  local gitDir = gitrepo.locateGitRepo()
  local projectDir = gitrepo.locateProjectRepo()
  if not gitDir then
    error("Not a git repository")
  end

  local files = arguments.options.arguments
  if #files == 0 then
    error("No files specified")
  end

  local indexFile = filesystem.combine(gitDir, "index")
  local index = filesystem.exists(indexFile) and gitdex.readIndex(indexFile) or gitdex.createIndex()

  -- TODO: Also detect removals

  for _, file in ipairs(files) do
    local path = filesystem.combine(filesystem.workingDir(), file)
    if not filesystem.exists(path) then
      error("File does not exist: " .. file)
    end
    local indexPath = filesystem.collapse(
    filesystem.combine(
      filesystem.unprefix(projectDir, filesystem.workingDir()),
      file))
    if indexPath == "/" then indexPath = "" end
    addToIndex(index, path, indexPath, filter, gitDir)
  end

  gitdex.writeIndex(index, indexFile)
end

return {
  subcommand = "add",
  description = "Add file contents to the index",
  options = {
    arguments = { flag = getopts.flagless.collect(getopts.stop.times(1)), description = "<file>" },
  },
  run = run
}