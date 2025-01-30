---@diagnostic disable: undefined-global

local driver = {}

driver.filesystem = {}
driver.filesystem.collapse = function(path)
  return fs.combine(path)
end
driver.filesystem.combine = function(...)
  return fs.combine(...)
end

driver.filesystem.workingDir = function()
  return _ENV.WORKING_DIR
end
driver.filesystem.codeDir = function()
  return _ENV.PROGRAM_LOCATION
end
driver.filesystem.homeDir = function()
  return "/"
end

driver.filesystem.list = function(path)
  return fs.list(path)
end
driver.filesystem.makeDir = function(path, recursive)
  if recursive then
    local parent = driver.filesystem.collapse(driver.filesystem.combine(path, ".."))
    if parent ~= "" and not driver.filesystem.exists(parent) then
      driver.filesystem.makeDir(parent, true)
    end
  end
  fs.makeDir(driver.filesystem.collapse(path))
end
driver.filesystem.exists = function(path)
  return fs.exists(path)
end
driver.filesystem.isFile = function(path)
  return fs.exists(path) and not fs.isDir(path)
end
driver.filesystem.isDir = function(path)
  return fs.isDir(path)
end

driver.filesystem.attributes = function(path)
  local rawAttributes = fs.attributes(path)
  -- TODO: File perms
  return {
    ctime = math.floor(rawAttributes.created / 1000), -- I'm pretty sure that's NOT what ctime is, but it's better than nothing
    mtime = math.floor(rawAttributes.modification / 1000),
    mode = driver.filesystem.isFile(path) and 644 or 755,
    size = rawAttributes.size,
  }
end
driver.filesystem.unprefix = function(basePath, otherPath)
  basePath = driver.filesystem.collapse(basePath)
  otherPath = driver.filesystem.collapse(otherPath)
  if #otherPath < #basePath then
    return driver.filesystem.unprefix(otherPath, basePath)
  else
    local unprefixedParts = {}
    while #otherPath > #basePath do
      local lastPart = otherPath:match("[^/]+$")
      otherPath = driver.filesystem.combine(otherPath, "..")
      table.insert(unprefixedParts, lastPart)
    end
    if otherPath ~= basePath then
      error("No common prefix")
    end
    return table.concat(unprefixedParts, "/")
  end
end

driver.filesystem.rm = function(path, recursive)
  if recursive and driver.filesystem.isDir(path) then
    for file in lfs.dir(path) do
      driver.filesystem.rm(driver.filesystem.combine(path, file), true)
    end
  end
  fs.delete(path)
end

driver.filesystem.openWriteProtected = function(path, mode)
  return io.open(path, mode)
end
driver.filesystem.resolve = function(path)
  return path
end

driver.http = {}

local function wrapHTTPResponse(handle, _, handle2)
  handle = handle or handle2

  local response = {
    status = handle.getResponseCode(),
    headers = handle.getResponseHeaders(),
    body = {
      read = function(_, n)
        return handle.read(n)
      end,
      close = function()
        handle.close()
      end
    }
  }

  for k, v in pairs(handle.getResponseHeaders()) do
    response.headers[k:lower()] = v
  end

  return response
end

driver.http.get = function(url, headers)
  return wrapHTTPResponse(http.get(url, headers, true))
end
driver.http.post = function(url, headers, body)
  return wrapHTTPResponse(http.post(url, body, headers, true))
end

driver.timeAndOffset = function()
  ---@diagnostic disable-next-line: undefined-field
  local timestamp = os.epoch("utc") / 1000
  local utcTime = os.date("!*t", timestamp)
  local localTime = os.date("*t", timestamp)

  ---@diagnostic disable-next-line: param-type-mismatch
  local timezoneOffsetSeconds = os.time(localTime) - os.time(utcTime)

  local sign = (timezoneOffsetSeconds >= 0) and "+" or "-"
  local absTimezoneOffsetSeconds = math.abs(timezoneOffsetSeconds)
  local hours = math.floor(absTimezoneOffsetSeconds / 3600)
  local minutes = math.floor((absTimezoneOffsetSeconds % 3600) / 60)
  local timezoneOffsetStr = string.format("%s%02d%02d", sign, hours, minutes)

  return timestamp, timezoneOffsetStr
end

driver.edit = function(file)
  _ENV.RUN("edit " .. file)
end

driver.openLongMessageDisplay = function()
  local tempFileHandle = assert(io.open("/.temp", "w"))
  return {
    write = function(self, message)
      tempFileHandle:write(message)
    end,
    close = function(self)
      tempFileHandle:close()
      _ENV.RUN("edit /.temp")
    end
  }
end

-- Cursor blink should already be off, so don't bother
driver.disableCursor = function()
  
end
driver.enableCursor = function()
  
end
driver.resetCursor = function()
  local x, y = term.getCursorPos()
  term.setCursorPos(1, y)
end

driver.readPassword = function()
  return read("*")
end

driver.hasFileModes = function()
  return false
end
driver.hasPreciseTime = function()
  return false
end

local oldTime = os.clock()
driver.preventTimeout = function()
  local newTime = os.clock()
  if newTime > (oldTime + 2.5) then
    ---@diagnostic disable-next-line: undefined-field
    os.queueEvent("")
    coroutine.yield("")
    oldTime = newTime
  end
end

return driver