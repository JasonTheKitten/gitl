local driver = localRequire("driver")
local utils = localRequire("lib/utils")
local gitref = localRequire("lib/gitl/gitref")
local gitstat = localRequire("lib/gitl/gitstat")
local gitobj = localRequire("lib/gitl/gitobj")
local gitdex = localRequire("lib/gitl/gitdex")
local gitignore = localRequire("lib/gitl/gitignore")
local filesystem, writeAll = driver.filesystem, utils.writeAll

-- TODO: Track reflogs (branch command too)

local function switchToNewBranch(gitDir, branch)
  local branchesDir = filesystem.combine(gitDir, "refs/heads")
  if not filesystem.exists(branchesDir) then
    filesystem.makeDir(branchesDir)
  end

  local branchPath = filesystem.combine(branchesDir, branch)
  if filesystem.exists(branchPath) then
    return nil, "Branch already exists: " .. branch
  end

  local currentCommit = gitref.getLastCommitHash(gitDir)
  if currentCommit then
    local newHeadDir = filesystem.combine(branchesDir, branch)
    writeAll(newHeadDir, currentCommit)
  end

  local headPath = filesystem.combine(gitDir, "HEAD")
  writeAll(headPath, "ref: refs/heads/" .. branch)

  return true
end

-- The (not so) fun part
local function compareTreeEntries(entry1, entry2)
  return entry1.hash == entry2.hash
end

local updateWorkingDirectory, updateSpecificEntry, deleteObject, directWriteObject
directWriteObject = function(gitDir, objectDir, objectHash, name)
  local object = gitobj.readAndDecodeObject(gitDir, objectHash)
  local objectPath = filesystem.combine(objectDir, name)
  if object.type == "blob" then
    -- TODO: Ensure file permissions are correct (+x)
    local file = assert(io.open(objectPath, "wb"))
    file:write(object.data)
    file:close()
  else
    filesystem.makeDir(objectPath)
    for _, entry in ipairs(object.entries) do
      directWriteObject(gitDir, objectPath, entry.hash, entry.name)
    end
  end
end
deleteObject = function(objectDir, name)
  local objectPath = filesystem.combine(objectDir, name)
  if filesystem.isDir(objectPath) then
    for _, entry in ipairs(filesystem.list(objectPath)) do
      deleteObject(objectPath, entry)
    end
    filesystem.rm(objectPath, true)
  else
    filesystem.rm(objectPath)
  end
end
updateSpecificEntry = function(gitDir, objectDir, newHash, oldHash, name)
  local newObjectPath = filesystem.combine(objectDir, name)
  local newObject = gitobj.readAndDecodeObject(gitDir, newHash)
  local oldObject = gitobj.readAndDecodeObject(gitDir, oldHash)
  if newObject.type == "blob" then
    local file = assert(io.open(newObjectPath, "wb"))
    file:write(newObject.data)
    file:close()
  else
    updateWorkingDirectory(gitDir, newObjectPath, oldObject, newObject)
  end
end
updateWorkingDirectory = function(gitDir, objectDir, oldTree, newTree)
  -- The diffIndexes function can actually be used on trees
  local differences = gitstat.diffIndexes(oldTree, newTree, compareTreeEntries)
  
  for _, entry in ipairs(differences.insertions) do
    local newObjectHash = gitdex.getEntry(newTree, entry).hash
    directWriteObject(gitDir, objectDir, newObjectHash, entry)
  end
  for _, entry in ipairs(differences.deletions) do
    deleteObject(objectDir, entry)
  end
  for _, entry in ipairs(differences.modifications) do
    local newObjectHash = gitdex.getEntry(newTree, entry).hash
    local oldObjectHash = gitdex.getEntry(oldTree, entry).hash
    updateSpecificEntry(gitDir, objectDir, newObjectHash, oldObjectHash, entry)
  end
end

local function finalizeExistingSwitch(gitDir, projectDir, newHead, newCommitHash)
  -- Now, update the HEAD
  if newHead then
    local headPath = filesystem.combine(gitDir, "HEAD")
    writeAll(headPath, newHead)
  end
  gitref.setLastCommitHash(gitDir, newCommitHash)

  -- Finally, rebuild the index
  local filter = gitignore.createFileFilter(projectDir)
  local indexFile = filesystem.combine(gitDir, "index")
  local index = filesystem.exists(indexFile) and gitdex.readIndex(indexFile) or gitdex.createIndex()
  gitdex.addToIndex(gitDir, index, projectDir, "", filter)
  gitdex.clearOldIndexEntries(projectDir, index, projectDir, "", filter)
  gitdex.writeIndex(index, indexFile)
end

local function switchToExistingBranch(gitDir, projectDir, newCommitHash, newHead)
  -- First, get the current tree
  local currentCommitHash = gitref.getLastCommitHash(gitDir)
  local currentCommitTreeHash = gitobj.readAndDecodeObject(gitDir, currentCommitHash, "commit").tree
  local currentTree = gitobj.readAndDecodeObject(gitDir, currentCommitTreeHash, "tree")

  -- Next, the new tree
  local newCommit = gitobj.readAndDecodeObject(gitDir, newCommitHash, "commit")
  local newTree = gitobj.readAndDecodeObject(gitDir, newCommit.tree, "tree")

  -- Now, update the working directory
  updateWorkingDirectory(gitDir, projectDir, currentTree, newTree)

  finalizeExistingSwitch(gitDir, projectDir, newHead, newCommitHash)
end

local function freshCheckoutExistingBranch(gitDir, projectDir, newCommitHash, newHead)
  local newCommit = gitobj.readAndDecodeObject(gitDir, newCommitHash, "commit")
  directWriteObject(gitDir, projectDir, newCommit.tree, "")

  finalizeExistingSwitch(gitDir, projectDir, newHead, newCommitHash)
end

return {
  switchToNewBranch = switchToNewBranch,
  switchToExistingBranch = switchToExistingBranch,
  freshCheckoutExistingBranch = freshCheckoutExistingBranch
}