local driver = localRequire("driver")
local filesystem = driver.filesystem

local PROHIBITED_FILES = {
  ["."] = true,
  [".."] = true,
  [".git"] = true
}

local function splitPath(path)
  local parts = {}
  for part in path:gmatch("[^/]+") do
    table.insert(parts, part)
  end
  return parts
end

local function readAll(file)
  local f = assert(io.open(file, "r"))
  local content = f:read("*a")
  f:close()
  return content
end

-- TODO: Better matching for **, also ? and group - may need a FSM?
-- TODO: Also directories that don't start with a / should be matched anywhere
local function ruleMatchesPart(rulePart, filenamePart)
  if rulePart == filenamePart then
    return true
  end
  if rulePart == "**" then
    return true
  end
  if rulePart == "*" then
    return filenamePart:match("[^/]+")
  end
  return false
end

local function ruleMatches(rule, filename, isDirectory)
  rule = rule:gsub("([^\\\\]%s)+$", "")
  if rule:gsub("^%s+", ""):sub(1, 1) == "#" then
    return false
  end
  if rule:gsub("^%s+", "") == "" then
    return false
  end

  local matchDirectory = rule:sub(-1) == "/"
  if matchDirectory then
    rule = rule:sub(1, -2)
  end

  if matchDirectory and not isDirectory then
    return false
  end

  local ruleParts = splitPath(rule)
  local filenameParts = splitPath(filename)
  for i, rulePart in ipairs(ruleParts) do
    local filenamePart = filenameParts[i]
    if not ruleMatchesPart(rulePart, filenamePart) then
      return false
    end
  end

  return true
end

local function isIgnored(gitIgnoreLines, filename, isDirectory)
  local ignored = false
  for _, line in ipairs(gitIgnoreLines) do
    local isNegated = line:sub(1, 1) == "!"
    if isNegated then
      line = line:sub(2)
    end
    local matches = ruleMatches(line, filename, isDirectory)
    if matches then
      ignored = not isNegated
    end
  end
  return ignored
end

local function createFileFilter(projectDir)
  local gitIgnoreLines = {}
  local gitIgnorePath = filesystem.combine(projectDir, ".gitignore")
  if filesystem.exists(gitIgnorePath) then
    local gitIgnoreContent = readAll(gitIgnorePath)
    for line in gitIgnoreContent:gmatch("([^\n]+)") do
      table.insert(gitIgnoreLines, line)
    end
  end

  return function(filename, isDirectory)
    for pathPart in filename:gmatch("[^/]+") do
      if PROHIBITED_FILES[pathPart] then
        return false
      end
    end

    return not isIgnored(gitIgnoreLines, filename, isDirectory)
  end
end

return {
  createFileFilter = createFileFilter
}