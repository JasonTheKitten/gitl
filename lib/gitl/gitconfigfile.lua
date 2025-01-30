local driver = localRequire("driver")
local filesystem = driver.filesystem

local function createConfigHandle(configData)
  local currentSection
  local handle = {}

  local function getSectionByPath(path, autoCreate)
    local configSection = configData
    for i = 1, #path - 1 do
      if autoCreate and not configSection[path[i]] then
        configSection[path[i]] = configSection[path[i]] or {}
      end
      configSection = configSection[path[i]]
      if not configSection then return nil end
    end

    return configSection
  end

  handle.section = function(sectionName)
    currentSection = sectionName
    configData[sectionName] = configData[sectionName] or {}
    return handle
  end
  handle.set = function(key, value)
    if type(key) == "table" then
      local configSection = getSectionByPath(key, true)
      configSection[key[#key]] = value

      return handle
    end

    if not currentSection then
      error("No section selected")
    end
    configData[currentSection][key] = value
    return handle
  end
  handle.get = function(key)
    local configSection = configData
    for i = 1, #key do
      configSection = configSection[key[i]]
      if not configSection then return nil end
    end

    return configSection
  end
  handle.write = function(filepath)
    local file = filesystem.openWriteProtected(filepath, "w")
    if not file then
      error("Failed to open config file for writing")
    end
    local writeSection
    writeSection = function(sectionName, sectionData)
      local wroteHeader = false
      for key, value in pairs(sectionData) do
        if type(value) ~= "table" then
          if not wroteHeader then
            file:write("[" .. sectionName .. "]\n")
            wroteHeader = true
          end
          file:write("\t" .. key .. " = " .. tostring(value) .. "\n")
        end
      end
      for key, value in pairs(sectionData) do
        if type(value) == "table" then
          local newSectionName = sectionName == "" and key or (sectionName .. (" \"" .. key .. "\""))
          writeSection(newSectionName, value)
        end
      end
    end
    writeSection("", configData)

    file:close()
  end

  return handle
end

local function createConfig()
  return createConfigHandle({})
end

local function parseSections(sectionName)
  local parts = {}
  local function insertIfNotEmpty(str)
    if str ~= "" then
      table.insert(parts, str)
    end
  end

  local startPtr, inQuote = 1, false
  for i = 1, #sectionName do
    if sectionName:sub(i, i) == "\"" then
      insertIfNotEmpty(sectionName:sub(startPtr, i - 1))
      inQuote = not inQuote
      startPtr = i + 1
    elseif sectionName:sub(i, i) == " " then
      insertIfNotEmpty(sectionName:sub(startPtr, i - 1))
      startPtr = i + 1
    elseif inQuote then
      -- Ignore
    elseif sectionName:sub(i, i) == "\"" then
      insertIfNotEmpty(sectionName:sub(startPtr, i - 1))
      startPtr = i + 1
    elseif sectionName:sub(i, i) == "." then
      insertIfNotEmpty(sectionName:sub(startPtr, i - 1))
      startPtr = i + 1
    end
  end
  insertIfNotEmpty(sectionName:sub(startPtr))

  return parts
end

local function readConfig(filepath)
  local file = assert(io.open(filepath, "r"))
  local configData = {}
  local currentSection
  for line in file:lines() do
    if (line:sub(1, 1) == "[") and (line:sub(-1) == "]") then
      -- TODO: Advanced stuff like includeIf
      local sectionName = line:sub(2, -2)
      currentSection = configData
      for k, part in ipairs(parseSections(sectionName)) do
        currentSection[part] = currentSection[part] or {}
        currentSection = currentSection[part]
      end
    elseif line == "" then
      -- Ignore
    else
      local key, value = line:match("^%s*([^%s=]+)%s*=%s*(.+)%s*$")
      currentSection[key] = value
    end
  end
  file:close()

  return createConfigHandle(configData)
end

return {
  createConfig = createConfig,
  readConfig = readConfig
}