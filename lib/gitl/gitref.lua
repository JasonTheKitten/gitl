local driver = localRequire("driver")
local utils = localRequire("lib/utils")
local filesystem, readAll, writeAll = driver.filesystem, utils.readAll, utils.writeAll

local function getRawHead(gitdir)
  local headPath = filesystem.combine(gitdir, "HEAD")
  if not filesystem.exists(headPath) then return end
  return readAll(headPath):match("([^\n]+)")
end

local function getLastCommitHash(gitdir)
  local headPath = filesystem.combine(gitdir, "HEAD")
  if not filesystem.exists(headPath) then return end
  local headContent = readAll(headPath):match("([^\n\r]+)")

  if headContent:sub(1, 5) ~= "ref: " then
    return headContent -- Hopefully a valid commit hash
  end

  local refPath = filesystem.combine(gitdir, headContent:sub(6, -1))
  if not filesystem.exists(refPath) then return end
  return readAll(refPath):match("([^\n]+)")
end

local function setLastCommitHash(gitdir, commit)
  local headPath = filesystem.combine(gitdir, "HEAD")
  local headContent = readAll(headPath)

  if headContent:sub(1, 5) ~= "ref: " then
    writeAll(headPath, commit)
    return
  end

  local branchPath = headContent:gsub("[\r\n]", ""):sub(6, -1)
  local refPath = filesystem.combine(gitdir, branchPath)
  writeAll(refPath, commit)
end

local function getBranchHash(gitdir, branch, isRaw)
  local refPath =
    isRaw and filesystem.combine(gitdir, branch)
    or filesystem.combine(gitdir, "refs", "heads", branch)
  if not filesystem.exists(refPath) then
    return nil, "Branch not found"
  end
  return readAll(refPath):match("([^\n]+)")
end

local function setBranchHash(gitdir, branch, commit, isRaw)
  local refPath =
    isRaw and filesystem.combine(gitdir, branch)
    or filesystem.combine(gitdir, "refs", "heads", branch)
  writeAll(refPath, commit)
end

local function hasBranch(gitdir, branch)
  local refPath = filesystem.combine(gitdir, "refs", "heads", branch)
  return filesystem.exists(refPath)
end

local function formatCurrentCommitRef(gitdir)
  local headPath = filesystem.combine(gitdir, "HEAD")
  if not filesystem.exists(headPath) then
    return nil, "Head does not exist"
  end
  local headContent = readAll(headPath)

  if headContent:sub(1, 5) ~= "ref: " then
    return "[detached HEAD" .. headContent:match("([^\n]+)") .. "]"
  end

  local refPath = filesystem.combine(gitdir, headContent:match("([^\n]+)"):sub(6, -1))
  if not filesystem.exists(refPath) then
    return nil, "Ref does not exist"
  end
  local commitHash = readAll(refPath):match("([^\n]+)"):sub(1, 7)
  local refName = headContent:match("([^/]+)$"):match("([^\n]+)")
  return "[" .. refName .. " " .. commitHash .. "]"
end

local function isDetachedHead(gitdir)
  local headPath = filesystem.combine(gitdir, "HEAD")
  if not filesystem.exists(headPath) then
    return nil, "Head does not exist"
  end
  local headContent = readAll(headPath)

  return headContent:sub(1, 5) ~= "ref: "
end

return {
  getRawHead = getRawHead,
  getLastCommitHash = getLastCommitHash,
  setLastCommitHash = setLastCommitHash,
  getBranchHash = getBranchHash,
  setBranchHash = setBranchHash,
  hasBranch = hasBranch,
  formatCurrentCommitRef = formatCurrentCommitRef,
  isDetachedHead = isDetachedHead
}