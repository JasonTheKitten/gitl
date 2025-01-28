local driver = localRequire("driver")
local utils = localRequire("lib/utils")
local gitobj = localRequire("lib/gitl/gitobj")
local githttp = localRequire("lib/gitl/githttp")
local gitcheckout = localRequire("lib/gitl/gitcheckout")
local filesystem, writeAll = driver.filesystem, utils.writeAll

local function chooseBranchAndHash(repository, httpSession, defaultBranch)
  local packfile = githttp.downloadAvailableRefs(repository, httpSession, true)
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

local function clone(projectDir, repository, options)
  if repository:sub(-2) ~= "/" then
    repository = repository .. "/"
  end

  local httpSession = githttp.createHttpSession(options)
  
  -- First, learn what branch/hash to clone
  local gitDir = filesystem.combine(projectDir, ".git")
  local branchName, branchHash = chooseBranchAndHash(repository, httpSession, options.defaultBranch)
  local newHead
  if branchName then
    local branchPath = filesystem.combine(gitDir, branchName)
    newHead = "ref: " .. branchName .. "\n"
    filesystem.makeDir(filesystem.combine(branchPath, ".."), true)
    writeAll(branchPath, branchHash .. "\n")
  else
    newHead = branchHash .. "\n"
  end

  -- Now, download a packfile of new objects
  local packFileOptions = {
    wants = { branchHash }
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

  -- Finally, all we need to do is check out the branch
  gitcheckout.freshCheckoutExistingBranch(gitDir, projectDir, branchHash, newHead)
end

return {
  clone = clone
}