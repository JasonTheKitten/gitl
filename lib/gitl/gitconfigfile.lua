local driver = localRequire("driver")
local filesystem = driver.filesystem

local function createConfigHandle(configData)
  local currentSection
  local handle = {}

  handle.section = function(sectionName)
    currentSection = sectionName
    configData[sectionName] = configData[sectionName] or {}
    return handle
  end
  handle.set = function(key, value)
    if not currentSection then
      error("No section selected")
    end
    configData[currentSection][key] = value
    return handle
  end
  handle.get = function(key)
    if not currentSection then
      error("No section selected")
    end
    return (configData[currentSection] or {})[key]
  end
  handle.write = function(filepath)
    local file = filesystem.openWriteProtected(filepath, "w")
    if not file then
      error("Failed to open config file for writing")
    end
    for sectionName, section in pairs(configData) do
      file:write("[" .. sectionName .. "]\n")
      for key, value in pairs(section) do
        file:write("\t" .. key .. " = " .. tostring(value) .. "\n")
      end
    end
    file:close()
  end

  return handle
end

local function createConfig()
  return createConfigHandle({})
end

local function readConfig(filepath)
  local file = assert(io.open(filepath, "r"))
  local configData = {}
  local currentSection
  for line in file:lines() do
    local sectionName = line:match("^%[([^%]]+)%]$")
    if sectionName then
      currentSection = sectionName
      configData[currentSection] = configData[currentSection] or {}
    else
      local key, value = line:match("^%s*([^%s=]+)%s*=%s*(.+)$")
      configData[currentSection][key] = value
    end
  end
  file:close()

  return createConfigHandle(configData)
end

return {
  createConfig = createConfig,
  readConfig = readConfig
}