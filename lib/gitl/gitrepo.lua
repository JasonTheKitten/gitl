local driver = localRequire("driver")
local gitconfig = localRequire("lib/gitl/gitconfig")
local filesystem = driver.filesystem

local function locateProjectRepo(startDir)
  local currentDir = startDir or filesystem.workingDir()
  while true do
    if filesystem.exists(filesystem.combine(currentDir, ".git")) then
      return currentDir
    end
    if filesystem.collapse(currentDir) == "" then
      return false, "Not a git repository"
    end
    currentDir = filesystem.combine(currentDir, "..")
  end
end

local function locateGitRepo(startDir)
  local projectDir = locateProjectRepo(startDir)
  if not projectDir then
    return false, "Not a git repository"
  end
  return filesystem.combine(projectDir, ".git")
end

local function resolveRemoteRepo(gitDir, remoteName)
  if remoteName:find(":") then
    return remoteName, true
  end

  remoteName = gitconfig.get(gitDir, { "remote", remoteName, "url" })
  if not remoteName then
    return false, "No such remote"
  end

  return remoteName, false
end

return {
  locateProjectRepo = locateProjectRepo,
  locateGitRepo = locateGitRepo,
  resolveRemoteRepo = resolveRemoteRepo
}