local driver = localRequire("driver")
local getopts = localRequire("lib/getopts")
local gitrepo = localRequire("lib/gitl/gitrepo")
local gitobj = localRequire("lib/gitl/gitobj")
local gitref = localRequire("lib/gitl/gitref")
local filesystem = driver.filesystem

local function expandFiles(files)
  local projectDir = assert(gitrepo.locateProjectRepo())
  local indexPath = filesystem.unprefix(projectDir, filesystem.workingDir())
  local expandedFiles = {}
  for _, file in ipairs(files) do
    table.insert(expandedFiles, filesystem.collapse(filesystem.combine(indexPath, file)))
  end

  return expandedFiles
end

local function checkFileVersion(gitdir, tree, hash, file)
  local firstPart = file:match("^[^/]*")
  local rest = file:match("/.+$")

  if firstPart == "" and not rest then
    return hash
  end
  for _, entry in ipairs(tree.entries) do
    if entry.name == firstPart then
      local isDirectory = tonumber(entry.mode) == 40000
      if isDirectory and rest then
        local obj = gitobj.readAndDecodeObject(gitdir, entry.hash, "tree")
        return checkFileVersion(gitdir, obj, entry.hash, rest:sub(2))
      elseif not rest then
        return entry.hash
      end
    end
  end
end

local function detectCommits(gitDir, allFiles)
  local currentRef = gitref.getLastCommitHash(gitDir)
  local commitRefList = {}
  local currentRefBacklog = { currentRef }
  while #currentRefBacklog > 0 do
    currentRef = table.remove(currentRefBacklog)
    local ok, commit = pcall(gitobj.readAndDecodeObject, gitDir, currentRef, "commit")
    if ok then
      table.insert(commitRefList, currentRef)
      for _, parent in pairs(commit.parents) do
        table.insert(currentRefBacklog, parent)
      end
    end
  end

  local commits = {}
  local lastVersions = {}
  for i = #commitRefList, 1, -1 do
    local commitRef = commitRefList[i]
    local commit = gitobj.readAndDecodeObject(gitDir, commitRef, "commit")
    local tree = gitobj.readAndDecodeObject(gitDir, commit.tree, "tree")
    local insertCommit = false
    for _, file in ipairs(allFiles) do
      local version = checkFileVersion(gitDir, tree, commit.tree, file)
      if version ~= lastVersions[file] then
        insertCommit = true -- TODO: Deletions?
        lastVersions[file] = version
      end
    end
    if insertCommit then
      table.insert(commits, 1, {
        hash = commitRef,
        commit = commit
      })
    end
  end

  return commits
end

local function formatCommits(commits, writer)
  for _, commit in ipairs(commits) do
    local hash = commit.hash
    commit = commit.commit
    -- TODO: Color, also helpfully determine applicable branches
    writer:write("commit " .. hash .. "\n")
    writer:write("Author: " .. commit.author .. "\n")
    writer:write("Date:   " .. os.date(nil, commit.authorTime) .. " " .. commit.authorTimezoneOffset .. "\n\n")
    writer:write("    " .. commit.message:gsub("\n", "\n    ") .. "\n")
    -- TODO: What if the commit date differs?
  end
end

local function formatOneLineCommits(commits, writer)
  for _, commit in ipairs(commits) do
    local hash = commit.hash
    commit = commit.commit
    local message = commit.message:match("[^\n]*")
    if #message > 50 then
      message = message:sub(1, 47) .. "..."
    end
    writer:write(hash:sub(1, 7) .. " " .. message .. "\n")
  end
end

local function run(arguments)
  local allFiles = arguments.options.arguments or {}
  if #allFiles == 0 then
    allFiles = { "" }
  end
  
  local expandedFiles = expandFiles(allFiles)

  local gitDir = assert(gitrepo.locateGitRepo())
  local commits = detectCommits(gitDir, expandedFiles)
  if arguments.options.oneline then
    local longMessageDisplayHandle = driver.openLongMessageDisplay()
    formatOneLineCommits(commits, longMessageDisplayHandle)
    longMessageDisplayHandle:close()
  else
    local longMessageDisplayHandle = driver.openLongMessageDisplay()
    formatCommits(commits, longMessageDisplayHandle)
    longMessageDisplayHandle:close()
  end
end

return {
  subcommand = "log",
  description = "Show commit logs",
  options = {
    arguments = { flag = getopts.flagless.collect(getopts.stop.remaining), params = "<file>" },
    oneline = { flag = "oneline", description = "Show a single line per commit" }
  },
  run = run
}