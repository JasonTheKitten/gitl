

local gitobj = localRequire("lib/gitl/gitobj")
local gitcheckout = localRequire("lib/gitl/gitcheckout")

-- There are ways to optimize this in the future if need be
local function compareNthValue(paths, n)
  local tail = paths[1][#(paths[1]) - n + 1]
  for i = #paths - n, 1, -1 do
    if paths[i][#paths[i] - n + 1] ~= tail then
      return paths[i][#paths[i] - n + 2]
    end
  end
  return paths[1][#paths[1] - n + 1]
end
local function getLowestTableSize(paths)
  local lowest = #paths[1]
  for i = 2, #paths do
    if #paths[i] < lowest then
      lowest = #paths[i]
    end
  end
  return lowest
end
local function determineClosestAncestor(paths)
  local lowest = getLowestTableSize(paths)
  local lastValue
  for i = 1, lowest do
    local nextValue = compareNthValue(paths, i)
    if not nextValue then break end
    lastValue = nextValue
  end

  return lastValue
end

local function getCommitAncestors(gitDir, commitHash)
  local ancestors = {}
  local current = commitHash
  while current do
    table.insert(ancestors, current)
    local currentCommit = gitobj.readAndDecodeObject(gitDir, current, "commit", true)
    current = currentCommit and currentCommit.parents[1] -- TODO: What if there are multiple parents
  end
  return ancestors
end
local function determineNearestAncestor(gitDir, commits)
  local paths = {}
  for _, commit in ipairs(commits) do
    table.insert(paths, getCommitAncestors(gitDir, commit))
  end
  return determineClosestAncestor(paths)
end

local function merge(gitDir, projectDir, commit1, commit2)
  local commonAncestor = determineNearestAncestor(gitDir, { commit1, commit2 })
  if not commonAncestor then
    return nil, "No common ancestor found"
  end

  if commonAncestor == commit1 then
    gitcheckout.switchToExistingBranch(gitDir, projectDir, commit2)
    return "fast-forward", "Fast-Forwarding", commit2
  end

  if commonAncestor == commit2 then
    return nil, "Already up-to-date"
  end

  error("Not implemented")
end

return {
  merge = merge
}