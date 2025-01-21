local driver = localRequire("driver")
local gitignore = localRequire("lib/gitl/gitignore")
local gitdex = localRequire("lib/gitl/gitdex")
local gitobj = localRequire("lib/gitl/gitobj")
local gitref = localRequire("lib/gitl/gitref")
local filesystem = driver.filesystem

-- TODO: This might be better in gitrepo.lua
local INDEX_ENTRIES_TO_COMPARE = {
  "ctime", "ctimeNanos", "mtime", "mtimeNanos", "dev", "ino", "mode", "uid", "gid", "size"
}

local function compareIndexEntries(entry1, entry2)
  for i, key in ipairs(INDEX_ENTRIES_TO_COMPARE) do
    local value1 = entry1[key]
    local value2 = entry2[key]
    if (value1 ~= value2) and (value1 ~= nil) and (value2 ~= nil) then
      return false
    end
  end
  return true
end

local function diffIndexes(index1, index2, comparisonFunc)
  local insertions, deletions, modifications = {}, {}, {}

  local indexPtr1, indexPtr2 = 1, 1
  while indexPtr1 <= #index1.entries or indexPtr2 <= #index2.entries do
    local entry1 = index1.entries[indexPtr1]
    local entry2 = index2.entries[indexPtr2]

    if not entry1 then
      table.insert(insertions, entry2.name)
      indexPtr2 = indexPtr2 + 1
    elseif not entry2 then
      table.insert(deletions, entry1.name)
      indexPtr1 = indexPtr1 + 1
    elseif entry1.name == entry2.name then
      if not comparisonFunc(entry1, entry2) then
        table.insert(modifications, entry1.name)
      end
      indexPtr1 = indexPtr1 + 1
      indexPtr2 = indexPtr2 + 1
    elseif entry1.name < entry2.name then
      table.insert(deletions, entry1.name)
      indexPtr1 = indexPtr1 + 1
    else
      table.insert(insertions, entry2.name)
      indexPtr2 = indexPtr2 + 1
    end
  end

  return {
    insertions = insertions,
    deletions = deletions,
    modifications = modifications
  }
end

local function compareWorkingWithIndex(gitDir, projectDir, index, filter)
  filter = filter or gitignore.createFileFilter(projectDir)

  local workingIndex = gitdex.createIndex()
  gitdex.addToIndex(workingIndex, projectDir, "", filter, gitDir, true)

  return diffIndexes(index, workingIndex, compareIndexEntries)
end

local function addTreeToPsuedoIndex(gitDir, psuedoIndex, treeHash, prefix)
  local contentType, contentData = gitobj.readObject(gitDir, treeHash)
  if contentType ~= "tree" then
    error("Expected tree object")
  end
  contentData = gitobj.decodeTreeData(contentData)

  for _, entry in ipairs(contentData.entries) do
    local path = filesystem.combine(prefix, entry.name)
    if tonumber(entry.mode) == tonumber("040000") then -- TODO: Is this check enough?
      addTreeToPsuedoIndex(gitDir, psuedoIndex, entry.hash, path)
    else
      local indexEntry = {
        name = path,
        hash = entry.hash,
      }
      gitdex.updateEntry(psuedoIndex, indexEntry.name, indexEntry)
    end
  end
end

local function convertTreeToPsuedoIndex(gitDir, treeHash)
  -- This isn't a real index - it is missing a lot of data
  local psuedoIndex = { entries = {} }
  addTreeToPsuedoIndex(gitDir, psuedoIndex, treeHash, "")
  return psuedoIndex
end

local function comparePsuedoIndexEntries(entry1, entry2)
  return entry1.hash == entry2.hash
end

local function compareTreeWithIndex(gitDir, tree, index)
  local psuedoIndex = convertTreeToPsuedoIndex(gitDir, tree)

  return diffIndexes(psuedoIndex, index, comparePsuedoIndexEntries)
end

local function stat(gitDir, projectDir)
  local indexFile = filesystem.combine(gitDir, "index")
  local index = filesystem.exists(indexFile) and gitdex.readIndex(indexFile) or gitdex.createIndex()
  local workingDirChanges = compareWorkingWithIndex(gitDir, projectDir, index)

  local lastCommitHash = gitref.getLastCommitHash(gitDir)
  local _, commitObj = gitobj.readObject(gitDir, lastCommitHash)
  local commit = gitobj.decodeCommitData(commitObj)

  local treeHash = commit.tree
  local treeChanges = compareTreeWithIndex(gitDir, treeHash, index)

  return {
    workingDirChanges = workingDirChanges,
    treeChanges = treeChanges
  }
end

return {
  compareWorkingWithIndex = compareWorkingWithIndex,
  compareTreeWithIndex = compareTreeWithIndex,
  stat = stat
}