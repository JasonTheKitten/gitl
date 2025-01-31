

local gitcommits = localRequire("lib/gitl/gitcommits")
local gitcheckout = localRequire("lib/gitl/gitcheckout")
local gitref = localRequire("lib/gitl/gitref")

local function merge(gitDir, projectDir, commit1, commit2)
  local commonAncestor = gitcommits.determineNearestAncestor(gitDir, { commit1, commit2 })
  if not commonAncestor then
    return nil, "No common ancestor found"
  end

  if commonAncestor == commit2 then
    return nil, "Already up-to-date"
  end

  if commonAncestor == commit1 then
    gitcheckout.switchToExistingBranch(gitDir, projectDir, commit2)
    gitref.setLastCommitHash(gitDir, commit2)
    return "fast-forward", "Fast-Forwarding", commit2
  end

  error("Not implemented")
end

return {
  merge = merge,
}