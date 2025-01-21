local driver = localRequire("driver")
local filesystem = driver.filesystem

local function readAll(file)
  local f = assert(io.open(file, "r"))
  local content = f:read("*a")
  f:close()
  return content
end

local function writeAll(file, content)
  local f = assert(io.open(file, "w"))
  f:write(content)
  f:close()
end

local function getLastCommitHash(gitdir)
  local headPath = filesystem.combine(gitdir, "HEAD")
  if not filesystem.exists(headPath) then return end
  local headContent = readAll(headPath)

  if headContent:sub(1, 5) ~= "ref: " then
    return headContent:match("([^\n]+)") -- Hopefully a valid commit hash
  end

  local refPath = filesystem.combine(gitdir, headContent:sub(6, -2))
  if not filesystem.exists(refPath) then return end
  return readAll(refPath):match("([^\n]+)")
end

local function setLastCommitHash(gitdir, commit)
  local headPath = filesystem.combine(gitdir, "HEAD")
  local headContent = readAll(headPath)

  if headContent:sub(1, 5) ~= "ref: " then
    writeAll(headPath, "ref: " .. commit)
    return
  end

  local refPath = filesystem.combine(gitdir, headContent:sub(6, -2))
  writeAll(refPath, commit)
end

local function formatCurrentCommitRef(gitdir)
  local headPath = filesystem.combine(gitdir, "HEAD")
  if not filesystem.exists(headPath) then return end
  local headContent = readAll(headPath)

  if headContent:sub(1, 5) ~= "ref: " then
    return "[detached HEAD" .. headContent:match("([^\n]+)") .. "]"
  end

  local refPath = filesystem.combine(gitdir, headContent:sub(6, -2))
  if not filesystem.exists(refPath) then return end
  local commitHash = readAll(refPath):match("([^\n]+)"):sub(1, 7)
  local refName = headContent:match("([^/]+)$"):match("([^\n]+)")
  return "[" .. refName .. " " .. commitHash .. "]"
end

return {
  getLastCommitHash = getLastCommitHash,
  setLastCommitHash = setLastCommitHash,
  formatCurrentCommitRef = formatCurrentCommitRef
}