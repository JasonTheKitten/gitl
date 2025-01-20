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
    return configData[currentSection][key]
  end
  handle.write = function(filepath)
    local file = io.open(filepath, "w")
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

return {
  createConfig = createConfig
}