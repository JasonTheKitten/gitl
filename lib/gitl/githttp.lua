local driver = localRequire("driver")
local gitpak = localRequire("lib/gitl/gitpak")
local base64 = localRequire("third_party/base64/base64")
local http = driver.http

local GIT_USER_AGENT = "git/2.30.0"

local function fixupRepositoryURL(repository)
  local stripped = repository:gsub("/+$", "")
  if stripped:sub(-4) ~= ".git" then
    stripped = stripped .. ".git"
  end
  return stripped .. "/"
end

local function parsePacketLines(packFileHandle, stages, options)
  options = options or {}
  local currentStage = 1
  while currentStage <= #stages do
    local n = packFileHandle.body:read(4)
    if n == nil then
      assert(currentStage == #stages, "Unexpected EOF")
      break
    end
    local objectLength = tonumber(n, 16) - 4
    if objectLength == -4 then
      currentStage = currentStage + 1
    else
      local nextLine = packFileHandle.body:read(objectLength):gsub("[\n\r]", "")
      if nextLine:sub(1, 1) ~= "#" then
        if stages[currentStage][1](nextLine) then break end
      end
    end
  end
end

local function createPacketLinesStream(innerStream, channelCallbacks, options)
  if not options.sideband64k then
    return innerStream
  end

  local function readLine()
    local objectLength = tonumber(innerStream:read(4), 16) - 5
    local channel = innerStream:read(1):byte()
    local line = innerStream:read(objectLength)
    if channelCallbacks[channel] then
      channelCallbacks[channel](line)
    end

    return channel == 1 and line or ""
  end

  local buffer = ""
  return {
    read = function(_, n)
      while #buffer < n do
        buffer = buffer .. readLine()
      end
      local result = buffer:sub(1, n)
      buffer = buffer:sub(n + 1)
      return result
    end,
    close = function()
      innerStream:close()
    end
  }
end

local function parseRefLine(nextLine, response)
  local spaceIndex = nextLine:find(" ")
  local zeroIndex = nextLine:find("\0") or (#nextLine + 1)
  local hash = nextLine:sub(1, spaceIndex - 1)
  local branchName = nextLine:sub(spaceIndex + 1, zeroIndex - 1)
  if branchName == "HEAD" then
    response.head = hash
    for capability in nextLine:sub(zeroIndex + 1):gmatch("[^%s]+") do
      local equalsIndex = capability:find("=")
      if equalsIndex then
        response.capabilities[capability:sub(1, equalsIndex - 1)] = capability:sub(equalsIndex + 1)
      else
        response.capabilities[capability] = true
      end
    end
  else
    response.branches[branchName] = hash
  end
end


local function formatLineSize(line)
  return string.format("%04x", #line + 5)
end

local function createPacketLinesWriter()
  local buffer = {}
  return {
    write = function(line)
      table.insert(buffer, formatLineSize(line))
      table.insert(buffer, line)
      table.insert(buffer, "\n")
    end,
    flush = function()
      table.insert(buffer, "0000")
    end,
    finalize = function()
      return table.concat(buffer)
    end
  }
end

local function downloadAvailableRefs(repository, httpSession, isUpload)
  local contentType = isUpload and "application/x-git-upload-pack-request" or "application/x-git-receive-pack-request"
  local service = isUpload and "git-upload-pack" or "git-receive-pack"
  local packFileURL = fixupRepositoryURL(repository) .. "info/refs?service=" .. service
  local packFileHandle = httpSession.handle(http.get, packFileURL, {
    ["content-type"] = contentType,
    ["user-agent"] = GIT_USER_AGENT,
    ["git-protocol"] = "version=1"
  })

  local response = {
    head = nil,
    branches = {},
    capabilities = {}
  }

  local function onMainMessage(nextLine)
    parseRefLine(nextLine, response)
  end

  parsePacketLines(packFileHandle, {
    { function(line) end },
    { onMainMessage },
  })

  packFileHandle.body:close()

  return response
end

local function writePackFileOptions(writer, options)
  for k, v in ipairs(options.wants) do
    local capabilityString = k == 1 and " report-status-v2 side-band-64k" or ""
    writer.write("want " .. v .. capabilityString)
    if options.depths and options.depths[v] then
      writer.write("deepen " .. options.depths[v])
    end
  end
  writer.flush()
  for _, v in ipairs(options.haves or {}) do
    writer.write("have " .. v)
  end
  writer.write("done")
  writer.flush()
end

local function downloadPackFile(repository, httpSession, options, pakOptions)
  local packFileURL = fixupRepositoryURL(repository) .. "git-upload-pack"
  local packetLinesWriter = createPacketLinesWriter()
  writePackFileOptions(packetLinesWriter, options)
  local postBody = packetLinesWriter.finalize()
  local packFileHandle = httpSession.handle(http.post, packFileURL, {
    ["content-type"] = "application/x-git-upload-pack-request",
    ["user-agent"] = GIT_USER_AGENT,
    ["git-protocol"] = "version=1"
  }, postBody)

  local function onMainMessage(nextLine)
    if nextLine:sub(1, 3) == "ACK" then
      return true
    elseif nextLine:sub(1, 8) == "shallow " then
      -- TODO: We don't really care yet
    elseif nextLine:sub(1, 4) ~= "NAK" then
      error("Expected NAK response, got " .. nextLine)
    else
      local packFileReader = createPacketLinesStream(packFileHandle.body, pakOptions.channelCallbacks or {}, { sideband64k = true })
      gitpak.decodePackFile(packFileReader, pakOptions)
      return true
    end
  end

  parsePacketLines(packFileHandle, {
    { onMainMessage },
    { onMainMessage}
  })

  packFileHandle.body:close()
end

local function determineCapabilitiesString()
  local capabilities = { "report-status-v2", "side-band-64k", "delete-ref" }
  return table.concat(capabilities, " ")
end

local function writeReferenceUpdates(writer, refUpdates)
  local capabilityStr = determineCapabilitiesString()
  for i = 1, #refUpdates do
    local v = refUpdates[i]
    local capabilityString = i == 1 and ("\0" .. capabilityStr) or ""
    local oldHash = v.oldHash or "0000000000000000000000000000000000000000"
    writer.write(oldHash .. " " .. v.newHash .. " " .. v.refName .. capabilityString)
  end
  writer.flush()
end

local function uploadPackFile(repository, httpSession, refUpdates, packFile)
  local packetLinesWriter = createPacketLinesWriter()
  writeReferenceUpdates(packetLinesWriter, refUpdates)
  local postBody = packetLinesWriter.finalize() .. packFile

  local packFileURL = fixupRepositoryURL(repository) .. "git-receive-pack"
  local packFileHandle = httpSession.handle(http.post, packFileURL, {
    ["content-type"] = "application/x-git-receive-pack-request",
    ["user-agent"] = GIT_USER_AGENT,
    ["git-protocol"] = "version=1"
  }, postBody)
  
  local function onMainMessage(nextLine)
    -- TODO
  end

  parsePacketLines(packFileHandle, {
    { onMainMessage }
  })

  packFileHandle.body:close()
end

local function createHttpSession(options)
  local username, password = nil, nil
  local handle
  handle = function(func, url, headers, body)
    local usedHeaders = headers or {}
    if username and password then
      local oldUsedHeaders = usedHeaders
      usedHeaders = {}
      for k, v in pairs(oldUsedHeaders) do
        usedHeaders[k] = v
      end

      usedHeaders["authorization"] = "Basic " .. base64.encode(username .. ":" .. password)
    end

    local response = func(url, usedHeaders, body)
    if response.status == 401 and not password then
      username, password = options.credentialsCallback()
      return handle(func, url, headers, body)
    elseif response.status == 401 then
      options.displayStatus(response.body:read(1024))
      error("Authentication failed")
    elseif response.status < 200 or response.status >= 300 then
      error("HTTP request failed with status " .. response.status)
    end

    return response
  end

  return {
    handle = handle
  }
end

return {
  downloadAvailableRefs = downloadAvailableRefs,
  downloadPackFile = downloadPackFile,
  uploadPackFile = uploadPackFile,
  createHttpSession = createHttpSession
}