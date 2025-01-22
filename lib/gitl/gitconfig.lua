local driver = localRequire("driver")
local configFile = localRequire("lib/gitl/gitconfigfile")
local filesystem = driver.filesystem

local function getConfigValue(gitdir, key, default)
  local firstPart, secondPart = key:match("([^%.]+)%.([^%.]+)")

  local configPath = gitdir and filesystem.combine(gitdir, "config") or nil
  if configPath and filesystem.exists(configPath) then
    local config = configFile.readConfig(configPath)
    local value = config.section(firstPart).get(secondPart)
    if value then return value end
  end

  local globalConfigPath = filesystem.combine(driver.filesystem.homeDir(), ".gitconfig")
  if filesystem.exists(globalConfigPath) then
    local globalConfig = configFile.readConfig(globalConfigPath)
    local value = globalConfig.section(firstPart).get(secondPart)
    if value then return value end
  end

  return default
end

return {
  get = getConfigValue
}