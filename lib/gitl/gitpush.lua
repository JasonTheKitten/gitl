local gitobj = localRequire("lib/gitl/gitobj")
local gitref = localRequire("lib/gitl/gitref")
local githttp = localRequire("lib/gitl/githttp")
local gitpak = localRequire("lib/gitl/gitpak")
local gitcommits = localRequire("lib/gitl/gitcommits")
local utils = localRequire("lib/utils")
local sha1 = localRequire("third_party/sha1/init").sha1

local recursivelyEnumerateObjects
recursivelyEnumerateObjects = function(gitDir, tree, objects)
  for _, entry in ipairs(tree.entries) do
    if tonumber(entry.mode) == 40000 then
      objects[entry.hash] = true
      local subTree = gitobj.readAndDecodeObject(gitDir, entry.hash, "tree")
      recursivelyEnumerateObjects(gitDir, subTree, objects)
    else
      -- TODO: What if it's not a blob?
      objects[entry.hash] = true
    end
  end
end

local function push(gitDir, repository, branchName, options)
  local branchCommitHash = gitref.getBranchHash(gitDir, branchName)
  local branchCommit = gitobj.readAndDecodeObject(gitDir, branchCommitHash, "commit")
  
  local httpSession = githttp.createHttpSession(options)
  local remoteRefs = githttp.downloadAvailableRefs(repository, httpSession, false)
  
  local remoteBranchHash = remoteRefs.branches["refs/heads/" .. branchName]

  if remoteBranchHash == branchCommitHash then
    return true, options.displayStatus("Everything up-to-date")
  end

  -- TODO: If this returns nil (it likely will if the server's commit is not recognized), it's gonna cause us to push the entire history
  local closestCommonHash = gitcommits.determineNearestAncestor(gitDir, { branchCommitHash, remoteBranchHash })
  if (remoteBranchHash ~= nil) and (remoteBranchHash ~= closestCommonHash) and not options.force then
    return nil, "Failed to find common ancestor - is the remote ahead?"
  end

  local treeHashes = {}
  local commitWantHashes = {}
  local currentCommit, currentCommitHash = branchCommit, branchCommitHash
  while currentCommitHash ~= closestCommonHash do
    table.insert(treeHashes, currentCommit.tree)
    table.insert(commitWantHashes, currentCommitHash)
    if currentCommit.parents and #currentCommit.parents > 0 then
      currentCommitHash = currentCommit.parents[1]
      currentCommit = gitobj.readObject(gitDir, currentCommitHash)
    else break end
  end

  local wantHashes = {}
  for _, treeHash in ipairs(treeHashes) do
    wantHashes[treeHash] = true
    local tree = gitobj.readAndDecodeObject(gitDir, treeHash, "tree")
    recursivelyEnumerateObjects(gitDir, tree, wantHashes)
  end

  if closestCommonHash then
    local haveHashes = {}
    local closestCommonCommit  = gitobj.readAndDecodeObject(gitDir, closestCommonHash, "commit")
    local closestCommonTree = gitobj.readAndDecodeObject(gitDir, closestCommonCommit.tree, "tree")
    recursivelyEnumerateObjects(gitDir, closestCommonTree, haveHashes)

    for haveHash in pairs(haveHashes) do
      wantHashes[haveHash] = nil
    end
  end

  for _, commitHash in ipairs(commitWantHashes) do
    wantHashes[commitHash] = true
  end

  local allWant = {}
  for wantHash in pairs(wantHashes) do
    table.insert(allWant, wantHash)
  end

  local packOptions = {
    countObjects = function() return #allWant end,
    readObject = function(index)
      return gitobj.readObject(gitDir, allWant[index])
    end,
    indicateProgress = options.indicateProgress
  }

  local bufferWriter = gitpak.createBufferWriter()
  gitpak.encodePackFile(bufferWriter, packOptions)
  -- TODO: This should be in gitpak.lua, but we'd need a rolling hash
  local packData = bufferWriter.finalize()
  packData = packData .. utils.format20ByteHash(sha1(packData))
  print()

  local refUpdate = {
    oldHash = remoteBranchHash,
    newHash = branchCommitHash,
    refName = "refs/heads/" .. branchName,
    force = options.force
  }

  githttp.uploadPackFile(repository, httpSession, { refUpdate }, packData)

  return true
end

return {
  push = push
}