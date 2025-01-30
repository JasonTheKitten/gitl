local filesystem = require("filesystem")
local computer = require("computer")
local keyboard = require("keyboard")
local shell = require("shell")
local gpu = require("component").gpu
local internet = require("component").internet

local driver = {}

driver.filesystem = {}
driver.filesystem.collapse = function(path)
  return filesystem.canonical(path)
end
driver.filesystem.combine = function(...)
  return filesystem.concat(...)
end

driver.filesystem.workingDir = function()
  return shell.getWorkingDirectory()
end
driver.filesystem.codeDir = function()
  return _ENV.PROGRAM_LOCATION
end
driver.filesystem.homeDir = function()
  return os.getenv("HOME")
end

driver.filesystem.list = function(path)
  local files = {}
    for file in filesystem.list(path) do
        table.insert(files, file)
    end
    return files
end
driver.filesystem.makeDir = function(path, recursive)
  if recursive then
    local parent = driver.filesystem.collapse(driver.filesystem.combine(path, ".."))
    if parent ~= "" and not driver.filesystem.exists(parent) then
      driver.filesystem.makeDir(parent, true)
    end
  end
  filesystem.makeDirectory(driver.filesystem.collapse(path))
end
driver.filesystem.exists = function(path)
  return filesystem.exists(path)
end
driver.filesystem.isFile = function(path)
  return filesystem.exists(path) and not filesystem.isDirectory(path)
end
driver.filesystem.isDir = function(path)
  return filesystem.isDirectory(path)
end

driver.filesystem.attributes = function(path)
  local modified = math.floor(filesystem.lastModified(path) / 1000)
  -- TODO: File perms
  return {
    ctime = modified, -- This somehow happens to be even more incorrect than the CC port
    mtime = modified,
    mode = driver.filesystem.isFile(path) and 644 or 755,
    size = filesystem.size(path),
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
    for file in filesystem.list(path) do
      driver.filesystem.rm(driver.filesystem.combine(path, file), true)
    end
  end
  filesystem.remove(path)
end

driver.filesystem.openWriteProtected = function(path, mode)
  return io.open(path, mode)
end
driver.filesystem.resolve = function(path)
  return path
end

driver.http = {}

local function wrapHTTPResponse(handle)
  local readBuffer = ""
  local responseCode, _, responseHeaders
  for i = 1, 30 do
    if responseCode then break end
    responseCode, _, responseHeaders = handle.response()
    ---@diagnostic disable-next-line: undefined-field
    os.sleep(0.1)
  end
  responseCode = responseCode or 401 -- If we're unauthorized, responseCode could be nil. We'll just assume 401
  return {
    status = responseCode,
    headers = responseHeaders,
    body = {
      read = function(_, n)
        while #readBuffer < n do
          ---@diagnostic disable-next-line: undefined-field
          os.sleep(0.1)
          local chunk = handle.read(math.max(2048, n - #readBuffer))
          if not chunk then
            error("No more data from remote (Did it time out?)")
          end
          readBuffer = readBuffer .. chunk
        end
        
        local data = readBuffer:sub(1, n)
        readBuffer = readBuffer:sub(n + 1)
        return data
      end,
      close = function()
        handle.close()
      end
    }
  }
end

driver.http.get = function(url, headers)
  return wrapHTTPResponse(internet.request(url, nil, headers))
end
driver.http.post = function(url, headers, body)
  return wrapHTTPResponse(internet.request(url, body, headers))
end

driver.timeAndOffset = function()
  ---@diagnostic disable-next-line: undefined-field
  local fakeFileHandle = assert(io.open("/home/.temp", "w"))
  fakeFileHandle:write("fake")
  fakeFileHandle:close()
  local timestamp = math.floor(filesystem.lastModified("/home/.temp") / 1000)
  filesystem.remove("/home/.temp")

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
  local defaultEditor = os.getenv("EDITOR") or "edit"
  os.execute(defaultEditor .. " " .. file)
end

driver.openLongMessageDisplay = function()
  local tempFileHandle = assert(io.open("/home/.temp", "w"))
  return {
    write = function(self, message)
      tempFileHandle:write(message)
    end,
    close = function(self)
      tempFileHandle:close()
      local pager = os.getenv("PAGER") or "less"
      os.execute(pager .. " /home/.temp")
    end
  }
end

-- Cursor blink should already be off, so don't bother
driver.disableCursor = function()

end
driver.enableCursor = function()

end
driver.resetCursor = function()
  io.write("\r")
end

driver.readPassword = function()
  local password = ""
  while true do
    local time = computer.uptime()
    local oldColor, oldPalette = gpu.getBackground()
    if time % 1 < 0.5 then
      gpu.setBackground(0x000000)
      io.write(" \8")
    else
      gpu.setBackground(0xFFFFFF)
      io.write(" \8")
    end
    gpu.setBackground(oldColor, oldPalette)

    local event, _, char, code = computer.pullSignal(.5)
    if event == "key_down" then
      if code == keyboard.keys.enter then
        break
      elseif code == keyboard.keys.backspace then
        password = password:sub(1, -2)
      elseif char and (char >= 32) and (char <= 126) then
        password = password .. string.char(char)
      end
    elseif event == "clipboard" then
      password = password .. char
    end
  end
  io.write(" \n")

  return password
end

driver.hasFileModes = function()
  return false
end
driver.hasPreciseTime = function()
  return false
end

local oldTime = os.clock() * 100
driver.preventTimeout = function()
  local newTime = os.clock() * 100
  if newTime > (oldTime + 2.5) then
    ---@diagnostic disable-next-line: undefined-global
    computer.pushSignal("")
    coroutine.yield("")
    oldTime = newTime
  end
end

return driver