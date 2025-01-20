local driver = localRequire("driver")
local filesystem = driver.filesystem

local function locateGitRepo(startDir)
  local currentDir = startDir or filesystem.workingDir()
  while true do
    if filesystem.exists(filesystem.combine(currentDir, ".git")) then
      return filesystem.combine(currentDir, ".git")
    end
    if filesystem.collapse(currentDir) == "/" then
      return nil
    end
    currentDir = filesystem.combine(currentDir, "..")
  end
end

return {
  locateGitRepo = locateGitRepo
}