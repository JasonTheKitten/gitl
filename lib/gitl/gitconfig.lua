local driver = localRequire("driver")
local configFile = localRequire("lib/gitl/gitconfigfile")
local filesystem = driver.filesystem

local function getConfigValue(gitdir, key, default)
  local parts = {}
  if type(key) == "table" then
    parts = key
  else
    for part in key:gmatch("[^%.]+") do
      table.insert(parts, part)
    end
  end

  local configPath = gitdir and filesystem.combine(gitdir, "config") or nil
  if configPath and filesystem.exists(configPath) then
    local config = configFile.readConfig(configPath)
    local value = config.get(parts)
    if value then return value end
  end

  local globalConfigPath = filesystem.combine(driver.filesystem.homeDir(), ".gitconfig")
  if filesystem.exists(globalConfigPath) then
    local globalConfig = configFile.readConfig(globalConfigPath)
    local value = globalConfig.get(parts)
    if value then return value end
  end

  return default
end

return {
  get = getConfigValue
}