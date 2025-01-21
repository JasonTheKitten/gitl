local driver = localRequire("driver")
local filesystem = driver.filesystem

local function locateProjectRepo(startDir)
  local currentDir = startDir or filesystem.workingDir()
  while true do
    if filesystem.exists(filesystem.combine(currentDir, ".git")) then
      return currentDir
    end
    if filesystem.collapse(currentDir) == "" then
      return nil
    end
    currentDir = filesystem.combine(currentDir, "..")
  end
end

local function locateGitRepo(startDir)
  local projectDir = locateProjectRepo(startDir)
  if not projectDir then
    return nil
  end
  return filesystem.combine(projectDir, ".git")
end

return {
  locateProjectRepo = locateProjectRepo,
  locateGitRepo = locateGitRepo
}