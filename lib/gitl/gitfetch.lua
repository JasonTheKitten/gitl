local driver = localRequire("driver")
local utils = localRequire("lib/utils")
local gitobj = localRequire("lib/gitl/gitobj")
local githttp = localRequire("lib/gitl/githttp")
local gitref = localRequire("lib/gitl/gitref")
local gitcommits = localRequire("lib/gitl/gitcommits")
local filesystem, writeAll = driver.filesystem, utils.writeAll

local function chooseBranchAndHash(repository, httpSession, branchRef)
  local packfile = githttp.downloadAvailableRefs(repository, httpSession, true)
  local branchHash = packfile.branches[branchRef]

  if not branchHash then
    return nil, "Failed to determine branch and hash"
  end

  return branchHash
end

local function fetch(gitDir, repository, options)
  if repository:sub(-2) ~= "/" then
    repository = repository .. "/"
  end

  local httpSession = githttp.createHttpSession(options)

  local branches = {}
  for k, v in ipairs(options.fetchRemoteHeads) do
    local branchHash, err = chooseBranchAndHash(repository, httpSession, v)
    if not branchHash then
      return nil, branchHash
    end
    branches[v] = branchHash
  end

  local wants = {}
  for k, v in pairs(branches) do
    table.insert(wants, v)
  end

  local havesReverse = {}
  local allBranches = options.fetchLocalHeads -- TODO: This should actually be *all* local branches
  for k, v in ipairs(allBranches) do
    local branchHash = gitref.getBranchHash(gitDir, v, true)
    if branchHash then
      local allCommitAncestors = gitcommits.getCommitAncestors(gitDir, branchHash)
      for i = #allCommitAncestors, 1, -1 do
        local commitHash = allCommitAncestors[i]
        if havesReverse[commitHash] then break end
        havesReverse[commitHash] = true
      end
    end
  end

  local haves = {}
  for k, v in pairs(havesReverse) do
    table.insert(haves, k)
  end

  local packFileOptions = {
    wants = wants,
    haves = haves
  }

  githttp.downloadPackFile(repository, httpSession, packFileOptions, {
    writeObject = function(type, content)
      gitobj.writeObject(gitDir, content, type)
    end,
    readObject = function(objectHash)
      return gitobj.readObject(gitDir, objectHash)
    end,
    indicateProgress = options.indicateProgress or function() end
  })

  for i = 1, #options.fetchRemoteHeads do
    local remoteHead = options.fetchRemoteHeads[i]
    local localHead = options.fetchLocalHeads[i]
    local branchPath = filesystem.combine(gitDir, localHead)
    filesystem.makeDir(filesystem.combine(branchPath, ".."), true)
    writeAll(branchPath, branches[remoteHead] .. "\n")
  end
  
  return true
end

return {
  fetch = fetch
}