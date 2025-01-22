local driver = localRequire("driver")
local utils = localRequire("lib/utils")
local gitobj = localRequire("lib/gitl/gitobj")
local githttp = localRequire("lib/gitl/githttp")
local filesystem, writeAll = driver.filesystem, utils.writeAll

local function chooseBranchAndHash(projectDir, repository, defaultBranch)
  local packfile = githttp.downloadAvailableRefs(repository)
  local branchName, branchHash
  if defaultBranch then
    branchName = defaultBranch
    branchHash = packfile.branches[defaultBranch]
  else
    local headBranch = packfile.head
    for name, hash in pairs(packfile.branches) do
      if hash == headBranch then
        branchName = name
        branchHash = hash
        break
      end
    end
  end

  if not branchHash then
    error("Failed to determine branch and hash")
  end

  return branchName, branchHash
end

local function clone(projectDir, repository, defaultBranch)
  if repository:sub(-2) ~= "/" then
    repository = repository .. "/"
  end
  
  -- First, learn what branch/hash to clone
  local gitdir = filesystem.combine(projectDir, ".git")
  local branchName, branchHash = chooseBranchAndHash(projectDir, repository, defaultBranch)
  local headPath = filesystem.combine(gitdir, "HEAD")
  if branchName then
    local branchPath = filesystem.combine(gitdir, branchName)
    writeAll(headPath, "ref: " .. branchName .. "\n")
    writeAll(branchPath, branchHash .. "\n")
  else
    writeAll(headPath, branchHash .. "\n")
  end

  -- Now, download a packfile of new objects
  local packFileOptions = {
    wants = { branchHash }
  }
  githttp.downloadPackFile(repository, packFileOptions, {
    writeObject = function(type, content)
      local mtype, data = gitobj.decompressObject(content)
      assert(mtype == type, "Mismatched object types")
      gitobj.writeObject(gitdir, data, type)
    end,
    loadObject = function(hash)
      return gitobj.readObject(gitdir, hash)
    end
  })
end

return {
  clone = clone
}