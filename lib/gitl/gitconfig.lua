local driver = localRequire("driver")
local configTool = localRequire("lib/configtool")
local filesystem = driver.filesystem

local function getConfigValue(gitdir, key, default)
  local firstPart, secondPart = key:match("([^%.]+)%.([^%.]+)")

  local configPath = filesystem.combine(gitdir, "config")
  if filesystem.exists(configPath) then
    local config = configTool.readConfig(configPath)
    local value = config.section(firstPart).get(secondPart)
    if value then return value end
  end

  local globalConfigPath = filesystem.combine(driver.filesystem.homeDir(), ".gitconfig")
  if filesystem.exists(globalConfigPath) then
    local globalConfig = configTool.readConfig(globalConfigPath)
    local value = globalConfig.section(firstPart).get(secondPart)
    if value then return value end
  end

  return default
end

return {
  get = getConfigValue
}