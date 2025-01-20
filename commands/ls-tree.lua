local getopts = localRequire("lib/getopts")
local gitobj = localRequire("lib/gitl/gitobj")
local gitrepo = localRequire("lib/gitl/gitrepo")

local displayTree
function displayTree(gitDir, hash, recursive, fullName)
  local otype, content
  if type(hash) == "table" then
    otype = "tree"
    content = gitobj.decodeTreeData(hash[1])
  else
    otype, content = gitobj.readObject(gitDir, hash)
    if otype ~= "tree" then
      error("Object is not a tree")
    end
    content = gitobj.decodeTreeData(content)
  end

  local entries = content.entries
  for _, entry in ipairs(entries) do
    local myEntryName = (fullName == "" and "" or (fullName .. "/")) .. entry.name
    local myEntryDataType, myEntryData = gitobj.readObject(gitDir, entry.hashHex)
    if (myEntryDataType == "tree") or not recursive then
      print(entry.mode .. " " .. myEntryDataType .. " " .. entry.hashHex .. " " .. myEntryName)
    elseif myEntryDataType == "tree" and recursive then
      displayTree(gitDir, { myEntryData }, true, myEntryName)
    end
  end
end

local function run(arguments)
  local gitDir = gitrepo.locateGitRepo()
  if not gitDir then
    error("Not a git repository")
  end

  local hash = arguments.options.arguments[1]
  local recursive = arguments.options.recursive
  displayTree(gitDir, hash, recursive, "")
end

return {
  subcommand = "ls-tree",
  description = "List the contents of a tree object",
  options = {
    recursive = { flag = "recursive", short = "r", description = "List subdirectories recursively" },
    arguments = { flag = getopts.flagless.collect(getopts.stop.times(1)), description = "<hash>" },
  },
  run = run
}