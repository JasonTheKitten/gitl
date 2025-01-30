local driver = localRequire("driver")
local configFile = localRequire("lib/gitl/gitconfigfile")
local filesystem = driver.filesystem

local defaultConfigs = {}

local function getGlobalConfig()
  local globalConfigPath = filesystem.combine(driver.filesystem.homeDir(), ".gitconfig")
  if filesystem.exists(globalConfigPath) then
    return configFile.readConfig(globalConfigPath)
  end

  return configFile.createConfig().path(globalConfigPath)
end

local function getLocalConfig(gitDir)
  local localConfigPath = gitDir and filesystem.combine(gitDir, "config") or nil
  if localConfigPath and filesystem.exists(localConfigPath) then
    return configFile.readConfig(localConfigPath)
  end

  return configFile.createConfig().path(localConfigPath)
end

local function getPathConfig(configPath)
  if filesystem.exists(configPath) then
    return configFile.readConfig(configPath)
  end

  return configFile.createConfig().path(configPath)
end

local sessionConfig = configFile.createConfig()
local function getSessionConfig()
  return sessionConfig
end

local function loadDefaultConfig(configPath)
  if filesystem.exists(configPath) then
    table.insert(defaultConfigs, configFile.readConfig(configPath))
  else
    table.insert(defaultConfigs, configFile.createConfig().path(configPath))
  end
end

local function withConfigs(gitDir, callback, defaultConfigOverrides)
  if defaultConfigOverrides and #defaultConfigOverrides > 0 then
    return callback(defaultConfigOverrides)
  end

  local allConfigs = { sessionConfig }
  for _, defaultConfig in ipairs(defaultConfigs) do
    table.insert(allConfigs, defaultConfig)
  end

  local localConfigPath = gitDir and filesystem.combine(gitDir, "config") or nil
  if localConfigPath and filesystem.exists(localConfigPath) then
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

local function getConfigValue(gitDir, key, default, defaultConfigOverrides)
  local parts = keyParts(key)

  return withConfigs(gitDir, function(configs)
    for _, config in ipairs(configs) do
      local value = config.get(parts)
      if value then return value end
    end

    return default
  end, defaultConfigOverrides)
end

local function listConfigValues(gitDir, key, defaultConfigOverrides)
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
  end, defaultConfigOverrides)
end

local function setConfigValue(gitDir, key, value, defaultConfigOverrides)
  local parts = keyParts(key)

  local config = defaultConfigOverrides and #defaultConfigOverrides > 0
    and defaultConfigOverrides[1]
    or configFile.readConfig(filesystem.combine(gitDir, "config"))
  config.set(parts, value)
  config.write()
end

local function removeConfigValue(gitDir, key, defaultConfigOverrides)
  local parts = keyParts(key)

  local config = defaultConfigOverrides and #defaultConfigOverrides > 0
    and defaultConfigOverrides[1]
    or configFile.readConfig(filesystem.combine(gitDir, "config"))
  config.set(parts, nil)
  config.write()
end

local function hasConfigValue(gitDir, key, defaultConfigOverrides)
  return getConfigValue(gitDir, key, defaultConfigOverrides) ~= nil
end

return {
  getGlobalConfig = getGlobalConfig,
  getLocalConfig = getLocalConfig,
  getPathConfig = getPathConfig,
  getSessionConfig = getSessionConfig,
  loadDefaultConfig = loadDefaultConfig,
  get = getConfigValue,
  list = listConfigValues,
  set = setConfigValue,
  remove = removeConfigValue,
  has = hasConfigValue
}