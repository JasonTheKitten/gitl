local driver = localRequire("driver")
local configFile = localRequire("lib/gitl/gitconfigfile")
local filesystem = driver.filesystem

local function withConfigs(gitDir, callback)
  local allConfigs = {}

  local localConfigPath = gitDir and filesystem.combine(gitDir, "config") or nil
  if filesystem.exists(localConfigPath) then
    local localConfig = configFile.readConfig(localConfigPath)
    table.insert(allConfigs, localConfig)
  end

  local globalConfigPath = filesystem.combine(driver.filesystem.homeDir(), ".gitconfig")
  if filesystem.exists(globalConfigPath) then
    local globalConfig = configFile.readConfig(globalConfigPath)
    table.insert(allConfigs, globalConfig)
  end

  return callback(allConfigs)
end

local function keyParts(key)
  local parts = {}
  if type(key) == "table" then
    parts = key
  else
    for part in key:gmatch("[^%.]+") do
      table.insert(parts, part)
    end
  end

  return parts
end

local function getConfigValue(gitDir, key, default)
  local parts = keyParts(key)

  return withConfigs(gitDir, function(configs)
    for _, config in ipairs(configs) do
      local value = config.get(parts)
      if value then return value end
    end

    return default
  end)
end

local function listConfigValues(gitDir, key)
  local parts = keyParts(key)

  return withConfigs(gitDir, function(configs)
    local values = {}
    for _, config in ipairs(configs) do
      local value = config.get(parts)
      for valueName in pairs(value or {}) do
        values[valueName] = true
      end
    end

    local flatValues = {}
    for value in pairs(values) do
      table.insert(flatValues, value)
    end

    return flatValues
  end)
end

local function setConfigValue(gitDir, key, value, global)
  local parts = keyParts(key)

  local configPath = global
    and filesystem.combine(driver.filesystem.homeDir(), ".gitconfig")
    or filesystem.combine(gitDir, "config")
  local config = configFile.readConfig(configPath)
  config.set(parts, value)
  config.write(configPath)
end

local function removeConfigValue(gitDir, key, value, global)
  local parts = keyParts(key)

  local configPath = global
    and filesystem.combine(driver.filesystem.homeDir(), ".gitconfig")
    or filesystem.combine(gitDir, "config")
  local config = configFile.readConfig(configPath)
  config.set(parts, nil)
  config.write(configPath)
end

local function hasConfigValue(gitDir, key)
  return getConfigValue(gitDir, key) ~= nil
end

return {
  get = getConfigValue,
  list = listConfigValues,
  set = setConfigValue,
  remove = removeConfigValue,
  has = hasConfigValue
}